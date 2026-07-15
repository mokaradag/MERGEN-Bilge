# ==============================================================================
# Dosya Yolu: R/helpers_ai_expert_speech.R
# Açıklama: AI Uzman parçalı (chunked) TTS konuşma dizisi orkestrasyonu.
#
#   Amaç (iki üretim hatasını kökten düzeltir):
#     1) Parçalar arası uzun sessiz duraklama: eski akış 2..N parçalarını
#        yalnızca 1. parça SENTEZLENİP istemciye gönderildikten SONRA sıraya
#        alıyordu; bu yüzden ilk parça biterken sonrakiler daha sentezlenmemiş
#        olabiliyordu. Bu yardımcı TÜM parçaları ("eager") hemen sentez kuyruğuna
#        verir (eşzamanlılık, paylaşılan sınırlı TTS kuyruğuyla LOCAL_TTS_MAX_
#        CONCURRENCY ile sınırlıdır). Böylece sonraki parçalar arka planda
#        paralel sentezlenir.
#     2) Sıra dışı sentez: sentez tamamlanma sırası ne olursa olsun oynatma
#        kesin olarak parça indeksi sırasında gönderilir (strict ordered
#        dispatch). 1. parça daima açılış-kritik olarak önce gönderilir.
#
#   Yarış/eskime koruması: TÜM asenkron geri çağrımlar enjekte edilen is_active()
#   yüklemi ile korunur. Durdurulmuş veya yeni bir konuşma dizisiyle değiştirilmiş
#   (superseded) eski geri çağrımlar sessizce yok sayılır. Her parça en fazla BİR
#   kez sentez kuyruğuna verilir (at-most-once).
#
#   Kurtarma: yapısal olarak geçersiz/eksik ses üreten bir parça sınırlı (varsayılan
#   1) kez yeniden denenir; yine başarısızsa o parça için KONTROLLÜ altyazı-yalnız
#   geri dönüş uygulanır (ses yok ama metin gösterilir), dizi durmaz.
#
#   Bu dosya SAF'tır: Shiny/DB/ağ/reaktif yan etkisi yoktur. synthesize,
#   send_message ve is_active enjekte edilir; bu sayede gerçek TTS/LLM/tarayıcı
#   olmadan deterministik test edilebilir. ai_expert_helpers bölümünde
#   chunking'den sonra yüklenir; module_ai_expert.R bunu çağırır.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}
# İzole test/worker bağlamı için promises pipe köprüleri (fonksiyon sayacına eklenmez).
if (!exists("%...>%", mode = "function", inherits = TRUE)) `%...>%` <- promises::`%...>%`
if (!exists("%...!%", mode = "function", inherits = TRUE)) `%...!%` <- promises::`%...!%`

#' AI Uzman Konuşma Dizisi Oluştur (eager, sıralı, eskime-korumalı)
#'
#' @param chunks Parça metinleri (list veya character; en az 1)
#' @param synthesize function(text, startup_priority, chunk_index, should_cancel) ->
#'   promise; sonuç list(success, audio_src, duration, media_duration, retryable,
#'   cancelled) çözer. İlk parçada startup_priority=TRUE, diğerlerinde FALSE
#'   gönderilir. should_cancel destekleniyorsa helper, ilk-parça altyazı
#'   geri dönüşünden sonra kuyruğa alınmış sonraki parçaları iptal ettirir.
#' @param send_message function(type, data); istemciye özel mesaj gönderir
#'   (ör. session$sendCustomMessage).
#' @param is_active function() -> logical; dizinin hâlâ güncel VE konuşmanın
#'   aktif olduğunu belirtir. TÜM asenkron geri çağrımlar bununla korunur.
#' @param meta list(ns_prefix, avatar_src, accent_color, font_size, full_text);
#'   gönderim yükleri için veri alanları.
#' @param first_chunk_promise (opsiyonel) 1. parça için önceden hazır/uçuşta
#'   promise (ön ısıtma). Başarısız olursa taze sentez ile denenir.
#' @param log (opsiyonel) function(msg); gizlilik-güvenli tanılama.
#' @param cancel_pending (opsiyonel) function(); ilk parça tüm-metin altyazı
#'   geri dönüşüne düşünce kuyrukta bekleyen sonraki parçaları iptal eder.
#' @param max_retries Parça başına sınırlı yeniden deneme (varsayılan 1).
#' @return list(start, snapshot): start() diziyi başlatır; snapshot() test için
#'   iç durumu döndürür.
mergen_ai_expert_new_speech_sequence <- function(chunks, synthesize, send_message,
                                                 is_active, meta = list(),
                                                 first_chunk_promise = NULL,
                                                 log = NULL,
                                                 cancel_pending = NULL,
                                                 max_retries = 1L) {
  chunks <- as.list(chunks)
  total <- length(chunks)
  max_retries <- max(0L, as.integer(max_retries %||% 1L))
  if (is.null(log) || !is.function(log)) log <- function(msg) invisible(NULL)
  if (is.null(cancel_pending) || !is.function(cancel_pending)) cancel_pending <- function() 0L

  st <- new.env(parent = emptyenv())
  st$total <- total
  st$submitted <- logical(max(total, 1L))
  st$resolved <- logical(max(total, 1L))
  st$items <- vector("list", max(total, 1L))
  st$next_dispatch <- 2L        # 1. parça ayrı (aiExpertStartWithAudio) gönderilir
  st$first_dispatched <- FALSE
  st$fallback_mode <- FALSE     # 1. parça başarısız -> tüm metin altyazı; kalanı atla
  st$cancel_later <- FALSE      # Kuyrukta bekleyen 2..N parçalarını başlatmadan iptal et

  active <- function() isTRUE(suppressWarnings(try(is_active(), silent = TRUE)))
  chunk_ok <- function(res) is.list(res) && isTRUE(res$success) && nzchar(res$audio_src %||% "")
  is_recoverable <- function(res) {
    is.list(res) && !isTRUE(res$success) && !isTRUE(res$cancelled) &&
      !identical(res$retryable, FALSE)
  }
  audio_dur <- function(res) suppressWarnings(as.numeric(res$media_duration %||% res$duration %||% 0))
  later_cancelled <- function() isTRUE(st$cancel_later) || !active()
  synth_supports_cancel <- function() {
    fmls <- names(formals(synthesize))
    "should_cancel" %in% fmls || "..." %in% fmls
  }

  send_start_with_audio <- function(text, src, dur) {
    send_message("aiExpertStartWithAudio", list(
      text = text, totalChunks = total,
      avatarSrc = meta$avatar_src, accentColor = meta$accent_color,
      nsPrefix = meta$ns_prefix, audioSrc = src, audioDuration = dur,
      fontSize = meta$font_size, speechSeq = meta$speech_seq
    ))
  }
  send_queue_chunk <- function(idx, item) {
    has_audio <- nzchar(item$audio_src %||% "")
    send_message("aiExpertQueueAudioChunk", list(
      index = idx - 1L, text = item$text,
      audioSrc = item$audio_src %||% "", audioDuration = item$duration %||% 0,
      hasAudio = has_audio, nsPrefix = meta$ns_prefix, speechSeq = meta$speech_seq
    ))
  }
  send_subtitle_fallback <- function() {
    send_message("aiExpertStartSubtitle", list(
      text = meta$full_text, avatarSrc = meta$avatar_src,
      accentColor = meta$accent_color, nsPrefix = meta$ns_prefix,
      fontSize = meta$font_size, speechSeq = meta$speech_seq
    ))
    send_message("aiExpertNoAudioFallback", list(
      textLength = nchar(meta$full_text %||% ""), nsPrefix = meta$ns_prefix,
      speechSeq = meta$speech_seq
    ))
  }

  # 2..N parçalarını KESİN sıra ile gönder (yalnızca 1. parça gönderildikten
  # sonra ve ardışık hazır oldukça).
  flush <- function() {
    if (!isTRUE(st$first_dispatched) || isTRUE(st$fallback_mode)) return(invisible(NULL))
    while (st$next_dispatch <= total && isTRUE(st$resolved[st$next_dispatch])) {
      send_queue_chunk(st$next_dispatch, st$items[[st$next_dispatch]])
      log(sprintf("stage=audio_dispatch chunk=%d", st$next_dispatch))
      st$next_dispatch <- st$next_dispatch + 1L
    }
    invisible(NULL)
  }

  on_first_success <- function(res) {
    if (isTRUE(st$first_dispatched)) return(invisible(NULL))
    st$first_dispatched <- TRUE
    send_start_with_audio(chunks[[1]], res$audio_src, audio_dur(res))
    log("stage=audio_dispatch chunk=1 mode=audio")
    flush()
    invisible(NULL)
  }
  on_first_fail <- function() {
    if (isTRUE(st$first_dispatched) || isTRUE(st$fallback_mode)) return(invisible(NULL))
    st$fallback_mode <- TRUE
    st$cancel_later <- TRUE
    cancelled <- suppressWarnings(try(cancel_pending(), silent = TRUE))
    if (is.numeric(cancelled) && cancelled > 0L) log(sprintf("stage=tts_queue_cancel_pending count=%d", cancelled))
    send_subtitle_fallback()
    log("stage=audio_dispatch chunk=1 mode=subtitle_only")
    invisible(NULL)
  }

  # 2..N parçaları için sonucu tampona al ve sıralı gönderimi dene.
  finalize_later <- function(idx, res) {
    if (isTRUE(st$fallback_mode) || isTRUE(st$resolved[idx])) return(invisible(NULL))
    st$resolved[idx] <- TRUE
    if (chunk_ok(res)) {
      st$items[[idx]] <- list(text = chunks[[idx]], audio_src = res$audio_src, duration = audio_dur(res))
    } else {
      # Kurtarma başarısız: bu parça için altyazı-yalnız (ses yok) -> dizi durmaz.
      st$items[[idx]] <- list(text = chunks[[idx]], audio_src = "", duration = 0)
      log(sprintf("chunk=%d audio_failed=subtitle_only", idx))
    }
    flush()
    invisible(NULL)
  }

  # Sınırlı yeniden deneme; asla reddetmez (son başarısızlığı sonuç listesine
  # normalize eder). synthesize'in kendi hatası veya kurtarılabilir başarısızlığı
  # bir kez daha denenir.
  synth_with_retry <- function(text, idx, startup_priority = FALSE) {
    attempt <- function(left) {
      log(sprintf("stage=tts_queue_submit chunk=%d startup=%s", idx, isTRUE(startup_priority)))
      p <- tryCatch(
        if (synth_supports_cancel()) {
          synthesize(text, startup_priority = startup_priority, chunk_index = idx,
                     should_cancel = if (idx > 1L) later_cancelled else function() !active())
        } else {
          synthesize(text, startup_priority = startup_priority, chunk_index = idx)
        },
        error = function(e) promises::promise_reject(e)
      )
      p %...>% (function(res) {
        if (left > 0L && is_recoverable(res)) {
          log("retry=recoverable_failure")
          return(attempt(left - 1L))
        }
        res
      }) %...!% (function(e) {
        if (left > 0L) {
          log("retry=rejected")
          return(attempt(left - 1L))
        }
        list(success = FALSE, audio_src = NULL, duration = 0,
             media_duration = NA_real_, error = conditionMessage(e), retryable = FALSE)
      })
    }
    attempt(max_retries)
  }

  # 1. parça başarısızsa (ön ısıtma/uçuşta veya taze) taze sentezle bir kez daha
  # dene; o da olmazsa tüm-metin altyazı geri dönüşü.
  try_fresh_first <- function() {
    if (isTRUE(st$first_dispatched) || isTRUE(st$fallback_mode)) return(invisible(NULL))
    synth_with_retry(chunks[[1]], 1L, startup_priority = TRUE) %...>% (function(res2) {
      if (!active()) return(invisible(NULL))
      if (chunk_ok(res2)) on_first_success(res2) else on_first_fail()
    }) %...!% (function(e) {
      if (active()) on_first_fail()
    })
    invisible(NULL)
  }

  submit_first <- function() {
    if (isTRUE(st$submitted[1])) return(invisible(NULL))
    st$submitted[1] <- TRUE
    # Ön ısıtma promise'i varsa 1. parça için onu kullan (yeniden deneme yok);
    # yoksa taze sentez + sınırlı yeniden deneme.
    src <- if (!is.null(first_chunk_promise)) {
      first_chunk_promise
    } else {
      synth_with_retry(chunks[[1]], 1L, startup_priority = TRUE)
    }
    src %...>% (function(res) {
      if (!active()) return(invisible(NULL))
      if (chunk_ok(res)) { on_first_success(res); return(invisible(NULL)) }
      if (!is.null(first_chunk_promise)) try_fresh_first() else on_first_fail()
    }) %...!% (function(e) {
      if (!active()) return(invisible(NULL))
      if (!is.null(first_chunk_promise)) try_fresh_first() else on_first_fail()
    })
    invisible(NULL)
  }

  submit_later <- function(idx) {
    if (isTRUE(st$submitted[idx])) return(invisible(NULL))
    st$submitted[idx] <- TRUE
    synth_with_retry(chunks[[idx]], idx, startup_priority = FALSE) %...>% (function(res) {
      if (active()) finalize_later(idx, res)
    }) %...!% (function(e) {
      if (active()) finalize_later(idx, list(success = FALSE))
    })
    invisible(NULL)
  }

  # TÜM parçaları hemen (eager) sentez kuyruğuna ver. Eşzamanlılık, paylaşılan
  # sınırlı TTS kuyruğuyla sınırlanır; oynatma sırası flush() ile korunur.
  start <- function() {
    if (total < 1L) return(invisible(NULL))
    submit_first()
    if (total >= 2L) {
      for (idx in 2:total) submit_later(idx)
    }
    invisible(NULL)
  }

  snapshot <- function() {
    list(
      total = st$total,
      submitted = st$submitted[seq_len(max(total, 1L))],
      resolved = st$resolved[seq_len(max(total, 1L))],
      next_dispatch = st$next_dispatch,
      first_dispatched = st$first_dispatched,
      fallback_mode = st$fallback_mode,
      cancel_later = st$cancel_later
    )
  }

  list(start = start, snapshot = snapshot)
}
