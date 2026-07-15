# R/module_tts.R
# Dosya Yolu: R/module_tts.R
# Açıklama: OpenAI/VoxCPM2 uyumlu Metinden Sese (TTS) dönüştürme modülü.
#           Düşük gecikme süresi için optimize edilmiştir (Namespace kullanımı,
#           worker'larda kütüphane yüklemesi yapılmaz). VoxCPM2 referans-ses
#           profili, üretilen-ses önbelleği ve sınırlı eşzamanlılık kuyruğu
#           mantığı ayrı yardımcı dosyalarındadır; bu modül yalnızca ince
#           entegrasyon çağrıları yapar.

#' TTS İşleme Sunucu Modülü
#'
#' OpenAI/VoxCPM2 uyumlu bir `/audio/speech` uç noktası kullanarak metni sese
#' dönüştürmek için asenkron bir yardımcı sağlar. Sohbet arayüzüne enjekte
#' edilebilen base64 kodlu ses URL'leri döndürür.
#'
#' @param id Modül ad alanı kimliği
#' @param settings_data (opsiyonel) Merkezi ayarlar reaktif değerleri; verilirse
#'   seçili persona profili konuşma özelliği açıldığında tembel ön yüklenir.
#' @return Modül sunucu mantığı listesi (synthesize_speech, tts_available,
#'   prepare_tts_text, preload_profile)
ttsProcessingServer <- function(id, settings_data = NULL) {
  moduleServer(id, function(input, output, session) {

    #' TTS hizmetinin kullanılabilir olup olmadığını kontrol et (uç nokta yapılandırılmış mı?)
    tts_available <- function() {
      endpoint <- tts_config$base_url %||% ""
      nzchar(endpoint)
    }

    #' TTS'e göndermeden önce metni hazırla (yalın geçiş).
    #' Kullanıcıdan veya modelden gelen metni ek sanitizasyon yapmadan iletir.
    prepare_tts_text <- function(text) {
      if (!is.character(text) || length(text) == 0) return("")
      as.character(text[1])
    }

    #' Nihai ses uç noktası (speech endpoint) URL'sini oluştur
    build_speech_url <- function() {
      base <- tts_config$base_url %||% ""
      if (!nzchar(base)) return("")
      base <- sub("/+$", "", base)
      if (grepl("/audio/speech$", base, ignore.case = TRUE)) {
        return(base)
      }
      paste0(base, "/audio/speech")
    }

    #' TTS uç noktası için API anahtarını belirle
    #' Öncelik: kişisel anahtar > TTS servis anahtarı > izinli kurum anahtarı > eski LLM anahtarı
    resolve_tts_api_key <- function() {
      tts_service_key <- tts_config$api_key %||% ""
      legacy_llm_key <- tryCatch(Sys.getenv("LOCAL_LLM_API_KEY", ""), error = function(e) "")

      mb_api_key_get_feature_key_value(
        session = session,
        service_key = tts_service_key,
        fallback_key = legacy_llm_key,
        require_auth = TRUE,
        clear_on_mismatch = TRUE,
        prefer_service_key_after_personal = TRUE
      )
    }

    #' Seçili persona ses profilini tembel yükle (yalnızca doğrula + base64;
    #' ağ isteği veya konuşma üretimi YAPMAZ). VoxCPM2 profilleri kapalıysa
    #' güvenli no-op. Aynı profil sürümü için base64 yalnızca bir kez üretilir.
    preload_profile <- function(char_id = NULL) {
      if (!isTRUE(mergen_tts_voice_profiles_enabled(tts_config))) return(invisible(FALSE))
      pid <- mergen_tts_profile_for_character(char_id)
      # Ana Söyleşi'nin açılış-kritik yolunu bloklamamak için düşük öncelikle ertele.
      later::later(function() {
        tryCatch({
          res <- mergen_tts_load_profile_cached(pid, tts_config)
          if (isTRUE(res$ok)) {
            cat(sprintf("[TTS] Ses profili yüklendi: %s (sürüm %s)\n", pid, res$version %||% "?"))
          } else {
            cat(sprintf("[TTS] Ses profili yüklenemedi: %s - %s\n", pid, res$error %||% "bilinmeyen"))
          }
        }, error = function(e) {
          cat(sprintf("[TTS] Ses profili ön yükleme hatası (%s): %s\n", pid, conditionMessage(e)))
        })
      }, delay = 0.1)
      invisible(TRUE)
    }

    resolve_profile_id_for_speech <- function(profile_id = NULL) {
      char_id <- tryCatch({
        if (!is.null(settings_data) && !is.null(settings_data$selected_character)) {
          shiny::isolate(settings_data$selected_character)
        } else {
          NULL
        }
      }, error = function(e) NULL)

      if (exists("mergen_tts_resolve_profile_id", mode = "function", inherits = TRUE)) {
        return(mergen_tts_resolve_profile_id(profile_id = profile_id, char_id = char_id, config = tts_config))
      }

      explicit_profile <- tolower(trimws(as.character(profile_id %||% "")[1]))
      if (!is.na(explicit_profile) && nzchar(explicit_profile)) explicit_profile else NULL
    }

    #' Asenkron olarak ses sentezle
    #' @param text Seslendirilecek metin
    #' @param voice Kullanılacak jenerik yedek ses (opsiyonel)
    #' @param profile_id VoxCPM2 persona ses profili kimliği (opsiyonel)
    #' @param should_cancel Kuyruk başlamadan iptali kontrol eden fonksiyon (opsiyonel)
    #' @param priority Paylaşılan kuyruk önceliği (yüksek değer önce; eşitte FIFO)
    #' @param trace_context Gizlilik-güvenli seq/generation/page/chunk kimlikleri
    #' @return promise nesnesi: list(success, audio_src, voice, duration, error)
    synthesize_speech <- function(text, voice = NULL, profile_id = NULL,
                                  should_cancel = NULL, priority = 0L,
                                  trace_context = NULL) {
      if (!tts_available()) {
        cat("[TTS] Seslendirme kullanılamıyor: uç nokta yapılandırılmamış\n")
        return(promises::promise_resolve(list(
          success = FALSE, audio_src = NULL, voice = voice, duration = 0,
          media_duration = NA_real_, retryable = FALSE, error = "TTS uç noktası yapılandırılmamış."
        )))
      }

      speech_text <- prepare_tts_text(text)
      if (!nzchar(speech_text)) {
        cat("[TTS] Temizleme sonrası metin boş, seslendirme atlanıyor\n")
        return(promises::promise_resolve(list(
          success = FALSE, audio_src = NULL, voice = voice, duration = 0,
          media_duration = NA_real_, retryable = FALSE, error = "Seslendirilecek metin boş."
        )))
      }

      profile_to_use <- resolve_profile_id_for_speech(profile_id)

      # --- KONUŞMA PLANI (profil çözümleme + önbellek; ana süreçte, worker öncesi) ---
      plan <- tryCatch(
        mergen_tts_prepare_speech_plan(speech_text, config = tts_config, profile_id = profile_to_use, voice = voice),
        error = function(e) NULL
      )
      if (is.null(plan)) {
        # Yardımcılar yoksa jenerik güvenli plana düş (eski davranış).
        plan <- list(
          body = list(
            model = tts_config$model %||% "tts-1-hd",
            input = speech_text,
            voice = voice %||% tts_config$default_voice %||% "default",
            response_format = "mp3"
          ),
          mime_type = "audio/mpeg", voice = voice %||% tts_config$default_voice %||% "default",
          response_format = "mp3", speed = NULL,
          cached_audio_src = NULL, cache_write_path = "", profile_active = FALSE
        )
      }

      voice_to_use <- plan$voice %||% "default"

      # --- ÜRETİLEN-SES ÖNBELLEĞİ İSABETİ: ağ turu olmadan birebir aynı ses ---
      if (!is.null(plan$cached_audio_src) && nzchar(plan$cached_audio_src)) {
        cat(sprintf("[TTS] Önbellek isabeti (profil=%s), ağ isteği atlanıyor.\n", profile_to_use %||% "-"))
        return(promises::promise_resolve(list(
          success = TRUE, audio_src = plan$cached_audio_src, voice = voice_to_use,
          duration = 0, media_duration = plan$cached_duration %||% NA_real_,
          error = NULL, cache_hit = TRUE
        )))
      }

      # --- ANA SÜREÇ DEĞİŞKENLERİ (Future içine aktarılmadan önce yakalanır) ---
      speech_url       <- build_speech_url()
      api_key          <- resolve_tts_api_key()
      model_to_use     <- plan$body$model %||% (tts_config$model %||% "tts-1-hd")
      body_data        <- plan$body
      mime_default     <- plan$mime_type %||% "audio/mpeg"
      cache_write_path <- plan$cache_write_path %||% ""
      timeout_val      <- as.numeric(tts_config$timeout_seconds %||% 90)
      if (is.na(timeout_val) || timeout_val <= 0) timeout_val <- 90
      verify_ssl_val   <- tts_config$verify_ssl
      should_verify    <- if (is.null(verify_ssl_val)) FALSE else isTRUE(verify_ssl_val)
      response_format  <- tolower(as.character(plan$response_format %||% plan$body$response_format %||% "wav")[1])
      speed_to_use     <- suppressWarnings(as.numeric(plan$speed %||% 1.0)[1])
      if (is.na(speed_to_use) || !is.finite(speed_to_use) || speed_to_use <= 0) speed_to_use <- 1.0

      # WAV yapısal doğrulama yardımcısını worker'a AÇIKÇA taşı. Böylece üretilen
      # ses (yalnızca WAV) önbelleğe yazılmadan ve tarayıcıya gönderilmeden önce
      # yapısal olarak doğrulanır; auto-detection'a ek kesin güvence sağlar.
      # (worker_monitor iç içe bağımlılıkları -parse/le_uint- otomatik genişletir.)
      tts_worker_globals <- list()
      if (exists("mergen_tts_validate_generated_wav", mode = "function", inherits = TRUE)) {
        tts_worker_globals[["mergen_tts_validate_generated_wav"]] <-
          get("mergen_tts_validate_generated_wav", mode = "function", inherits = TRUE)
      }
      if (exists("mergen_tts_decode_audio_payload", mode = "function", inherits = TRUE)) {
        tts_worker_globals[["mergen_tts_decode_audio_payload"]] <-
          get("mergen_tts_decode_audio_payload", mode = "function", inherits = TRUE)
      }

      # Gövde (ref_audio base64) ASLA loglanmaz.
      cat(sprintf("[TTS] İstek: URL=%s | Model=%s | Ses=%s | Profil=%s | API Key uzunluk=%d | Metin=%d karakter\n",
                  speech_url, model_to_use, voice_to_use,
                  if (isTRUE(plan$profile_active)) (profile_to_use %||% "-") else "jenerik",
                  nchar(api_key), nchar(speech_text)))

      debug_log_file <- normalizePath(file.path("logs", "tts_debug.txt"), mustWork = FALSE)
      if (!file.exists(dirname(debug_log_file))) dir.create(dirname(debug_log_file), recursive = TRUE)

      queue <- tryCatch(mergen_tts_default_queue(tts_config), error = function(e) NULL)

      worker_started_at <- NULL
      redact_tts_error <- function(msg, max_chars = 500L) {
        if (exists("mergen_tts_redact_error_text", mode = "function", inherits = TRUE)) {
          mergen_tts_redact_error_text(msg, max_chars = max_chars)
        } else {
          "TTS isteği başarısız oldu."
        }
      }

      # --- ASENKRON ÇALIŞTIRICI (WORKER) FABRİKASI ---
      worker_factory <- function() {
        worker_started_at <<- Sys.time()
        if (is.list(trace_context) &&
            exists("mergen_ai_expert_trace_context_line", mode = "function", inherits = TRUE)) {
          cat(mergen_ai_expert_trace_context_line("tts_worker_start", trace_context), "\n")
        }
        tracked_future_promise(
          task_fn = function() {
            start_time <- Sys.time()

            worker_log <- function(msg) {
              try({
                cat(sprintf("[%s] [Worker-%s] %s\n",
                            format(Sys.time(), "%H:%M:%S"), Sys.getpid(), msg),
                    file = debug_log_file, append = TRUE)
              }, silent = TRUE)
            }

            worker_log(sprintf("BAŞLATMA: URL=%s | Model=%s | Ses=%s", speech_url, model_to_use, voice_to_use))

            # ÖNEMLİ: Burada library() çağrısı yapılmaz; açık ad alanları kullanılır.
            headers <- c(
              `Content-Type` = "application/json",
              `Authorization` = paste("Bearer", api_key)
            )

            req_config <- if (isTRUE(should_verify)) {
              list()
            } else {
              httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L)
            }

            worker_log("POST İsteği Gönderiliyor...")

            resp <- tryCatch({
              httr::POST(
                url = speech_url,
                httr::add_headers(.headers = headers),
                body = body_data,
                encode = "json",
                httr::timeout(timeout_val),
                req_config
              )
            }, error = function(e) {
              worker_log(sprintf("POST İşleminde Kritik Hata: %s", redact_tts_error(conditionMessage(e), max_chars = 200L)))
              return(list(error_obj = e))
            })

            if (is.list(resp) && !is.null(resp$error_obj)) {
              err_msg <- redact_tts_error(conditionMessage(resp$error_obj))
              return(list(success = FALSE, audio_src = NULL, voice = voice_to_use, duration = 0,
                          media_duration = NA_real_, retryable = TRUE, error = err_msg))
            }

            status <- httr::status_code(resp)
            worker_log(sprintf("YANIT Durumu: %d", status))

            if (status >= 200 && status < 300) {
              content_type <- httr::headers(resp)[["content-type"]] %||% ""
              mime_type <- mime_default
              if (nzchar(content_type)) {
                mime_type <- strsplit(content_type, ";", fixed = TRUE)[[1]][1]
              }

              # Ham ses baytlarını ELDE ET (JSON sarmalı base64 veya doğrudan ikili).
              # Doğrulama VE önbellek daima ham baytlar üzerinden yapılır.
              audio_src <- NULL
              audio_raw <- NULL

              # JSON sarmalayıcı kontrolü (bazı proxy'lerde nadir de olsa görülebilir)
              if (grepl("json", content_type, ignore.case = TRUE)) {
                parsed <- tryCatch(httr::content(resp, as = "parsed", encoding = "UTF-8"),
                                   error = function(e) NULL)
                b64 <- NULL
                if (is.list(parsed)) {
                  if (!is.null(parsed$audio)) b64 <- parsed$audio
                  else if (!is.null(parsed$data)) b64 <- parsed$data
                  else if (!is.null(parsed$content)) b64 <- parsed$content
                }
                if (!is.null(b64) && nzchar(as.character(b64)[1])) {
                  b64_str <- as.character(b64)[1]
                  audio_src <- if (startsWith(b64_str, "data:")) {
                    b64_str
                  } else {
                    paste0("data:", mime_type, ";base64,", b64_str)
                  }
                  if (exists("mergen_tts_decode_audio_payload", mode = "function", inherits = TRUE)) {
                    audio_raw <- mergen_tts_decode_audio_payload(b64_str)
                  }
                }
              }

              # Standart İkili (Binary) Yanıt (OpenAI/VoxCPM2 için en yaygın durum)
              if (is.null(audio_raw)) {
                audio_raw <- httr::content(resp, as = "raw")
                worker_log(sprintf("İKİLİ İÇERİK: %d bayt alındı", length(audio_raw)))
              }

              if (is.null(audio_raw) || length(audio_raw) == 0) {
                worker_log("BAŞARISIZ: Ses içeriği boş.")
                return(list(success = FALSE, audio_src = NULL, voice = voice_to_use,
                            duration = 0, media_duration = NA_real_,
                            error = "Ses yanıtı boş döndü.", retryable = TRUE))
              }

              # --- YAPISAL WAV DOĞRULAMA (yalnızca WAV biçimi) ---
              # Geçersiz/eksik/kesik WAV önbelleğe YAZILMAZ ve tarayıcıya
              # GÖNDERİLMEZ (yarıda kesilmiş ses belirtisi). Kurtarma (sınırlı
              # yeniden deneme) çağıran taraftaki AI Uzman konuşma dizisindedir.
              media_duration <- NA_real_
              if (identical(response_format, "wav") &&
                  exists("mergen_tts_validate_generated_wav", mode = "function", inherits = TRUE)) {
                vres <- mergen_tts_validate_generated_wav(
                  audio_raw, text = speech_text, speech_speed = speed_to_use
                )
                if (!isTRUE(vres$ok)) {
                  worker_log(sprintf("GEÇERSİZ SES reddedildi (%d bayt): %s",
                                     length(audio_raw), vres$error %||% "bilinmeyen"))
                  return(list(success = FALSE, audio_src = NULL, voice = voice_to_use,
                              duration = 0, media_duration = NA_real_,
                              error = vres$error %||% "Üretilen ses geçersiz veya eksik.",
                              retryable = TRUE))
                }
                media_duration <- suppressWarnings(as.numeric(vres$duration %||% NA_real_))
                worker_log(sprintf("WAV doğrulandı: süre=%.2fs kanal=%s örnekleme=%s",
                                   if (is.na(media_duration)) 0 else media_duration,
                                   vres$channels %||% "-", vres$sample_rate %||% "-"))
              }

              # audio_src henüz yoksa (ikili yol) doğrulanmış ham bayttan üret.
              if (is.null(audio_src)) {
                audio_b64 <- base64enc::base64encode(audio_raw)
                audio_src <- paste0("data:", mime_type, ";base64,", audio_b64)
              }

              # --- DOĞRULANMIŞ SESİ ÖNBELLEĞE ATOMİK YAZ ---
              if (nzchar(cache_write_path)) {
                try({
                  cdir <- dirname(cache_write_path)
                  if (!dir.exists(cdir)) dir.create(cdir, recursive = TRUE, showWarnings = FALSE)
                  tmp <- paste0(cache_write_path, ".tmp-", Sys.getpid(), "-", as.integer(stats::runif(1, 1, 1e9)))
                  con2 <- file(tmp, open = "wb"); writeBin(audio_raw, con2); close(con2)
                  if (!isTRUE(suppressWarnings(file.rename(tmp, cache_write_path)))) {
                    file.copy(tmp, cache_write_path, overwrite = TRUE); unlink(tmp, force = TRUE)
                  }
                }, silent = TRUE)
              }

              duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
              worker_log(sprintf("BAŞARILI: Ses %.2fs içinde hazırlandı (medya süresi=%.2fs)",
                                 duration, if (is.na(media_duration)) 0 else media_duration))

              list(success = TRUE, audio_src = audio_src, voice = voice_to_use,
                   duration = duration, media_duration = media_duration, error = NULL)
            } else {
              err_msg <- tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"),
                                  error = function(e) "TTS isteği başarısız oldu.")
              safe_err_msg <- redact_tts_error(err_msg)
              worker_log(sprintf("API HATASI: %s", substr(safe_err_msg, 1, 100)))
              list(success = FALSE, audio_src = NULL, voice = voice_to_use,
                   duration = 0, media_duration = NA_real_, retryable = TRUE,
                   error = paste("TTS hata:", safe_err_msg))
            }
          },
          task_type = "tts",
          session_token = session$token,
          globals = tts_worker_globals,
          meta = list(voice = voice_to_use, model = model_to_use)
        )
      }

      on_worker_error <- function(e) {
        if (is.list(trace_context) && !is.null(worker_started_at) &&
            exists("mergen_ai_expert_trace_context_line", mode = "function", inherits = TRUE)) {
          cat(mergen_ai_expert_trace_context_line("tts_worker_complete", trace_context,
            as.numeric(difftime(Sys.time(), worker_started_at, units = "secs")) * 1000), "\n")
        }
        safe_err_msg <- redact_tts_error(conditionMessage(e))
        cat(sprintf("[TTS] Worker hatası: %s\n", safe_err_msg))
        try({
          cat(sprintf("[%s] [Worker-HATA] %s\n", format(Sys.time(), "%H:%M:%S"), safe_err_msg),
              file = normalizePath(file.path("logs", "tts_debug.txt"), mustWork = FALSE), append = TRUE)
        }, silent = TRUE)
        list(success = FALSE, audio_src = NULL, voice = voice_to_use,
             duration = 0, media_duration = NA_real_, retryable = TRUE, error = safe_err_msg)
      }

      # Sınırlı eşzamanlılık kuyruğuyla gönder (iptal-farkındalı); kuyruk yoksa
      # doğrudan çalıştır (geriye dönük güvenli davranış).
      worker_promise <- if (is.environment(queue) && is.function(queue$submit)) {
        if (is.list(trace_context) &&
            exists("mergen_ai_expert_trace_context_line", mode = "function", inherits = TRUE)) {
          cat(mergen_ai_expert_trace_context_line("tts_queue_submit", trace_context), "\n")
        } else {
          cat(sprintf("[TTS_TRACE] at=%s event=queue_submit priority=%s chars=%d\n",
            format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z"), as.character(priority), nchar(speech_text)))
        }
        queue$submit(worker_factory, should_cancel = should_cancel, priority = priority,
                     resolve_before_pump = TRUE)
      } else {
        worker_factory()
      }
      worker_promise %...>% (function(result) {
        if (is.list(trace_context) && !is.null(worker_started_at) &&
            exists("mergen_ai_expert_trace_context_line", mode = "function", inherits = TRUE)) {
          cat(mergen_ai_expert_trace_context_line("tts_worker_complete", trace_context,
            as.numeric(difftime(Sys.time(), worker_started_at, units = "secs")) * 1000), "\n")
        }
        result
      }) %...!% on_worker_error
    }

    # TTS/AI Uzman açıksa seçili profili tembel ön yükleme politikasını bağla.
    if (!is.null(settings_data) &&
        exists("mergen_tts_bind_profile_preload", mode = "function", inherits = TRUE)) {
      tryCatch(
        mergen_tts_bind_profile_preload(
          session = session,
          settings_data = settings_data,
          tts_processor = list(preload_profile = preload_profile)
        ),
        error = function(e) cat(sprintf("[TTS] Profil ön yükleme bağlanamadı: %s\n", conditionMessage(e)))
      )
    }

    list(
      synthesize_speech = synthesize_speech,
      tts_available = tts_available,
      prepare_tts_text = prepare_tts_text,
      preload_profile = preload_profile,
      cancel_pending = function() {
        if (is.environment(queue) && is.function(queue$cancel_pending)) queue$cancel_pending() else 0L
      }
    )
  })
}

#' Sohbet mesajı için yeniden kullanılabilir ses oynatıcı UI parçası oluştur
#'
#' @param message_id Mesajın kimliği
#' @param audio_src Base64 kodlu ses kaynağı
#' @param voice Ses adı (etiket için)
#' @return HTML div elemanı
build_tts_audio_ui <- function(message_id, audio_src, voice = NULL) {
  if (is.null(audio_src) || !nzchar(audio_src)) return(NULL)

  label <- if (!is.null(voice) && nzchar(voice)) {
    paste("Ses:", voice)
  } else {
    "Sesli Yanıt"
  }

  div(
    id = paste0("tts_audio_", message_id),
    class = "tts-audio-wrapper",
    div(
      class = "tts-audio-header",
      tags$i(class = "fas fa-volume-up"),
      span(label)
    ),
  tags$audio(
      controls = "controls",
      preload = "auto",
      src = audio_src,
      `data-mergen-audio-owner` = "tts_manual"
    )
  )
}
