# ==============================================================================
# Dosya Yolu: R/server_handler_pk_async.R
# Açıklama: Faz 6 (§5.10) — Proje ve Kaynak Analizi GÖNDERİM katmanı.
#           Senkron/asenkron kararını verir, işçiyi explicit-mode ile gönderir,
#           istek-kimliği korumalı geri çağrıları bağlar ve devamı (continuation)
#           çağırır.
#
# `R/server_send_message.R` bu dosyaya DELEGE eder ve kendisi ince kalır
# (ratchet bütçesi). Handler deseni, `handle_true_streaming_mode(ctx)` /
# `handle_streaming_tts_mode(ctx)` ile aynıdır. Sonuç uygulama / senkron yol /
# istek hazırlığı yardımcıları `R/helpers_pk_async_apply.R` içindedir (manifestte
# bu dosyadan ÖNCE yüklenir).
#
# YAŞAM DÖNGÜSÜ SÖZLEŞMESİ:
#   * `session`, reaktif değer veya DB bağlantısı işçiye ASLA gitmez
#     (`pk_async_validate_request()` savunmacı olarak doğrular),
#   * her geri çağrı `pk_async_should_apply()` ile korunur,
#   * geri çağrı içindeki HER reaktif okuma `shiny::isolate()` ile sarılır
#     (promise/`later` geri çağrıları reaktif BAĞLAM içinde DEĞİLDİR — Ortak
#     Oturum dersi),
#   * iptal jetonu her çıkışta temizlenir.
# ==============================================================================

#' PK analizini çalıştır: senkron veya asenkron
#'
#' @param ctx Alanlar: `session`, `values`, `user_message_text`,
#'   `messages_to_process`, `deep_thinking`, `analysis_detail`, `req_id`,
#'   `active_request_id`, `stop_generation`, `cleanup_send_message`,
#'   `add_message_fn`, `continue_fn`.
#' @return `list(action = "continue"|"answer"|"deferred"|"stop", ...)`.
#'   `deferred` = işçi gönderildi; devam GERİ ÇAĞRIDA çalışacak, çağıran HEMEN
#'   dönmelidir.
mergen_pk_analysis_execute <- function(ctx) {
  if (isTRUE(tryCatch(ctx$stop_generation(), error = function(e) FALSE))) {
    return(list(action = "stop"))
  }

  uygun <- pk_async_available()

  if (!isTRUE(uygun$available)) {
    if (!identical(uygun$reason, "flag_off")) {
      log_info(sprintf(
        "[PK_ASYNC] Asenkron gonderim yapilamadi (%s); senkron yol kullaniliyor.",
        uygun$reason
      ))
    }
    return(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), ctx$messages_to_process))
  }

  hazirlik <- mergen_pk_prepare_async_request(ctx)
  if (!isTRUE(hazirlik$ok)) {
    if (isTRUE(hazirlik$fallback_sync)) {
      return(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), ctx$messages_to_process))
    }
    return(list(action = "answer", answer = hazirlik$answer, chips = list()))
  }

  mergen_pk_dispatch_async(ctx, hazirlik$request, hazirlik$cancel_token)
}

#' İşçiyi explicit-mode ile gönder ve korumalı geri çağrıları bağla
mergen_pk_dispatch_async <- function(ctx, request, cancel_token) {
  req_id <- as.character(ctx$req_id %||% "")[1]

  # Reaktif okumaları GÖNDERİMDEN ÖNCE yakala. Geri çağrılar reaktif BAĞLAM
  # içinde çalışmaz; oradaki çıplak bir reactiveVal okuması
  # "Operation not allowed without an active reactive context" ile patlar.
  mesajlar <- ctx$messages_to_process
  oturum <- ctx$session

  # Oturum kapanırsa/durdurulursa işçi jetonu görür ve KENDİ KENDİNE durur.
  # Yalnızca geri çağrıyı atmak işçiyi çalışır ve bağlantıyı tutar hâlde bırakır.
  iptal_kaydi <- tryCatch({
    oturum$onSessionEnded(function() pk_cancel_token_signal(cancel_token))
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(iptal_kaydi)) {
    log_info("[PK_ASYNC] onSessionEnded kaydi yapilamadi; iptal jetonu yalnizca Durdur ile isaretlenecek.")
  }

  # Devam (continuation): geri çağrıdan çağrılır. Reaktif olmayan bağlamda
  # çalıştığı için tüm reaktif erişimler `isolate()` ile sarılıdır.
  devam_et <- function(uygulama) {
    if (identical(uygulama$action, "answer")) {
      ctx$cleanup_send_message()
      ctx$add_message_fn(uygulama$answer, "ai")
      return(invisible(NULL))
    }
    ctx$continue_fn(uygulama$messages_to_process, uygulama$max_output_tokens)
  }

  # Geri çağrı girişinde ORTAK koruma. Üç ret sebebi de AYRI loglanır.
  koruma_gecti <- function(etiket) {
    aktif <- tryCatch(shiny::isolate(ctx$active_request_id()), error = function(e) NULL)
    durduruldu <- isTRUE(tryCatch(shiny::isolate(ctx$stop_generation()), error = function(e) FALSE))
    karar <- pk_async_should_apply(aktif, req_id, stopped = durduruldu)

    if (!isTRUE(karar$apply)) {
      log_info(sprintf(
        "[PK_ASYNC] Bayat/durdurulmus geri cagri yok sayildi (%s, sebep=%s).",
        etiket, karar$reason
      ))
      # Bayat istek: jetonunu temizle ki dosya sizmasin.
      pk_cancel_token_clear(cancel_token)
      return(FALSE)
    }
    TRUE
  }

  gorev <- function() pk_async_run_analysis(request)

  vaat <- tryCatch(
    tracked_future_promise(
      task_fn = gorev,
      task_type = if (isTRUE(request$deep_thinking)) "pk_deep_analysis" else "pk_analysis",
      session_token = tryCatch(oturum$token, error = function(e) NULL),
      dependency_mode = "explicit",
      globals = c(
        pk_async_worker_globals(),
        list(request = request)
      ),
      packages = c("DBI", "jsonlite")
    ),
    error = function(e) e
  )

  if (inherits(vaat, "condition")) {
    log_warn(sprintf(
      "[PK_ASYNC] Gonderim basarisiz (%s); senkron yola donuluyor.",
      conditionMessage(vaat)
    ))
    pk_cancel_token_clear(cancel_token)
    return(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), mesajlar))
  }

  promises::then(
    vaat,
    onFulfilled = function(worker_result) {
      if (!isTRUE(koruma_gecti("fulfilled"))) return(invisible(NULL))
      pk_cancel_token_clear(cancel_token)

      durum <- as.character(worker_result$status %||% "error")[1]

      # Oturum yazımları (seçim durumu, köken alt bilgisi) YALNIZCA koruma
      # geçtikten sonra uygulanır; bayat bir sonuç daha yeni bir isteğin
      # durumunu EZEMEZ.
      tryCatch(
        pk_async_apply_session_writes(oturum, worker_result$session_writes),
        error = function(e) NULL
      )

      if (identical(durum, "ok")) {
        return(devam_et(mergen_pk_apply_analysis_result(worker_result$result, mesajlar)))
      }

      # Bootstrap başarısızlığı OPERASYONEL bir ortam sorunudur, kullanıcının
      # sorusuyla ilgisi yoktur: bir kez senkron yeniden denenir ki kullanıcı
      # doğru yanıtı alsın; operatöre yüksek sesli uyarı loglanır.
      if (identical(durum, "bootstrap_failed")) {
        log_warn(paste0(
          "[PK_ASYNC] Isci bootstrap basarisiz; bu istek SENKRON yeniden ",
          "deneniyor. MERGEN_PK_ASYNC=false ile geri alinabilir."
        ))
        return(devam_et(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), mesajlar)))
      }

      ctx$cleanup_send_message()
      ctx$add_message_fn(
        mergen_pk_worker_outcome_text(durum, worker_result$error), "ai"
      )
      invisible(NULL)
    },
    onRejected = function(error) {
      if (!isTRUE(koruma_gecti("rejected"))) return(invisible(NULL))
      pk_cancel_token_clear(cancel_token)

      log_warn(sprintf(
        "[PK_ASYNC] Isci reddedildi: %s",
        tryCatch(conditionMessage(error), error = function(e) "bilinmeyen")
      ))
      ctx$cleanup_send_message()
      ctx$add_message_fn(mergen_pk_worker_outcome_text("error"), "ai")
      invisible(NULL)
    }
  )

  list(action = "deferred")
}

#' Durdurma anında iptal jetonunu işaretle (durdur gözlemcisinden çağrılır)
#'
#' UI tarafında "sonucu yok say" kontrolü TEK BAŞINA iptal DEĞİLDİR: işçi
#' çalışmaya devam eder, DB bağlantısını ve işçi yuvasını tutar.
mergen_pk_signal_cancel <- function(request_id) {
  if (!exists("pk_cancel_token_path", mode = "function", inherits = TRUE)) {
    return(invisible(FALSE))
  }
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.null(kimlik) || length(kimlik) == 0L || is.na(kimlik) || !nzchar(kimlik)) {
    return(invisible(FALSE))
  }
  pk_cancel_token_signal(pk_cancel_token_path(kimlik))
}
