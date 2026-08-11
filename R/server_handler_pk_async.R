# ==============================================================================
# Faz 6: PK async ana-süreç gönderim ve callback yaşam döngüsü.
# ==============================================================================

# Extracted factory caller kapsamındaki kısa-ömürlü telemetry observer'ını korur.
.pk_handler_env <- environment()
if (exists("pk_deep_observation_helpers", mode = "function",
           envir = .pk_handler_env, inherits = TRUE)) {
  .pk_deep_factory <- get("pk_deep_observation_helpers", mode = "function",
                          envir = .pk_handler_env, inherits = TRUE)
  pk_deep_observation_helpers <- local({
    core <- .pk_deep_factory
    function(...) {
      observer <- try(
        get("pk_analysis_observe", envir = parent.frame(), mode = "function", inherits = TRUE),
        silent = TRUE
      )
      factory <- core
      if (is.function(observer)) {
        e <- new.env(parent = environment(factory))
        e$pk_analysis_observe <- observer
        environment(factory) <- e
      }
      factory(...)
    }
  })
  rm(.pk_deep_factory)
}
rm(.pk_handler_env)

mergen_pk_analysis_execute <- function(ctx) {
  stopped <- try(ctx$stop_generation(), silent = TRUE)
  if (!inherits(stopped, "try-error") && isTRUE(stopped)) return(list(action = "stop"))

  uygun <- pk_async_available()
  if (!isTRUE(uygun$available)) {
    if (!identical(uygun$reason, "flag_off")) {
      log_info(sprintf("[PK_ASYNC] Async yok (%s); senkron yol.", uygun$reason))
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

mergen_pk_dispatch_async <- function(ctx, request, cancel_token) {
  req_id <- as.character(ctx$req_id %||% "")[1]
  mesajlar <- ctx$messages_to_process
  oturum <- ctx$session

  chat_key <- function(x) {
    if (is.null(x) || !length(x)) return("<new-chat>")
    y <- try(as.character(x)[1], silent = TRUE)
    if (inherits(y, "try-error") || is.na(y) || !nzchar(y)) "<new-chat>" else y
  }
  kaynak_chat <- try(shiny::isolate(ctx$values$current_chat_id), silent = TRUE)
  if (inherits(kaynak_chat, "try-error")) kaynak_chat <- NULL
  kaynak_chat_key <- chat_key(kaynak_chat)

  request_done <- FALSE
  kayit <- try({
    oturum$onSessionEnded(function() {
      if (!isTRUE(request_done)) pk_cancel_token_signal(cancel_token)
    })
    TRUE
  }, silent = TRUE)
  if (!identical(kayit, TRUE)) log_info("[PK_ASYNC] onSessionEnded iptal kaydi yapilamadi.")

  # continuation ve message insertion alt çağrıları da reactive okuyabildiği için
  # callback'teki tüm gövde isolate edilir.
  devam_et <- function(uygulama) shiny::isolate({
    if (identical(uygulama$action, "answer")) {
      ctx$cleanup_send_message()
      ctx$add_message_fn(uygulama$answer, "ai")
      return(invisible(NULL))
    }
    ctx$continue_fn(uygulama$messages_to_process, uygulama$max_output_tokens)
  })

  koruma_gecti <- function(etiket, result = NULL) {
    aktif <- try(shiny::isolate(ctx$active_request_id()), silent = TRUE)
    if (inherits(aktif, "try-error")) aktif <- NULL
    stopped <- try(shiny::isolate(ctx$stop_generation()), silent = TRUE)
    stopped <- !inherits(stopped, "try-error") && isTRUE(stopped)
    karar <- pk_async_should_apply(aktif, req_id, stopped = stopped)

    simdiki <- try(shiny::isolate(ctx$values$current_chat_id), silent = TRUE)
    if (inherits(simdiki, "try-error")) simdiki <- NULL
    ayni_chat <- identical(chat_key(simdiki), kaynak_chat_key)
    if (isTRUE(karar$apply) && isTRUE(ayni_chat)) return(TRUE)

    sebep <- if (!isTRUE(karar$apply)) karar$reason else "chat_changed"
    log_info(sprintf("[PK_ASYNC] Callback yok sayildi (%s, sebep=%s).", etiket, sebep))
    request_done <<- TRUE
    pk_cancel_token_clear(cancel_token)
    try(mergen_pk_cleanup_worker_artifact(result), silent = TRUE)
    try(shiny::isolate(
      mergen_send_message_release_values_token(ctx$values, req_id = req_id)
    ), silent = TRUE)
    FALSE
  }

  session_token <- try(oturum$token, silent = TRUE)
  if (inherits(session_token, "try-error")) session_token <- NULL
  vaat <- try(
    tracked_future_promise(
      task_fn = function() pk_async_run_analysis(request),
      task_type = if (isTRUE(request$deep_thinking)) "pk_deep_analysis" else "pk_analysis",
      session_token = session_token,
      dependency_mode = "explicit",
      globals = c(pk_async_worker_globals(), list(request = request)),
      packages = c("DBI", "jsonlite")
    ),
    silent = TRUE
  )
  if (inherits(vaat, "try-error")) {
    request_done <- TRUE
    log_warn("[PK_ASYNC] Gonderim basarisiz; senkron yol.")
    pk_cancel_token_clear(cancel_token)
    return(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), mesajlar))
  }

  promises::then(
    vaat,
    onFulfilled = function(worker_result) {
      if (!isTRUE(koruma_gecti("fulfilled", worker_result$result))) return(invisible(NULL))
      request_done <<- TRUE
      pk_cancel_token_clear(cancel_token)
      durum <- as.character(worker_result$status %||% "error")[1]

      if (identical(durum, "ok")) {
        # Worker'da oluşturulan kart surrogate session nedeniyle URL'sizdir.
        # Gerçek session'da serve ettikten sonra aynı eski blok worker'ın
        # provenance footer kopyasında da yenilenir; nihai yanıt o footer'dan
        # dekore edildiği için yalnız result alanını değiştirmek yeterli değildir.
        eski_sonuc <- worker_result$result
        sonuc <- mergen_pk_serve_worker_artifact(eski_sonuc, oturum)
        pending <- worker_result$session_writes$pk_provenance_pending
        eski_blok <- as.character(eski_sonuc$pk_answer_block %||% "")[1]
        yeni_blok <- as.character(sonuc$pk_answer_block %||% "")[1]
        if (is.list(pending) && is.character(pending$footer) && length(pending$footer) == 1L &&
            nzchar(eski_blok) && nzchar(yeni_blok) && !identical(eski_blok, yeni_blok) &&
            grepl(eski_blok, pending$footer, fixed = TRUE)) {
          pending$footer <- sub(eski_blok, yeni_blok, pending$footer, fixed = TRUE)
          worker_result$session_writes$pk_provenance_pending <- pending
        }
        try(pk_async_apply_session_writes(oturum, worker_result$session_writes), silent = TRUE)
        return(devam_et(mergen_pk_apply_analysis_result(sonuc, mesajlar)))
      }

      try(pk_async_apply_session_writes(oturum, worker_result$session_writes), silent = TRUE)
      if (identical(durum, "bootstrap_failed")) {
        log_warn("[PK_ASYNC] Worker bootstrap basarisiz; senkron yeniden deneniyor.")
        return(devam_et(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), mesajlar)))
      }
      shiny::isolate({
        ctx$cleanup_send_message()
        ctx$add_message_fn(mergen_pk_worker_outcome_text(durum, worker_result$error), "ai")
      })
      invisible(NULL)
    },
    onRejected = function(error) {
      if (!isTRUE(koruma_gecti("rejected"))) return(invisible(NULL))
      request_done <<- TRUE
      pk_cancel_token_clear(cancel_token)
      log_warn("[PK_ASYNC] Isci reddedildi.")
      shiny::isolate({
        ctx$cleanup_send_message()
        ctx$add_message_fn(mergen_pk_worker_outcome_text("error"), "ai")
      })
      invisible(NULL)
    }
  )
  list(action = "deferred")
}

mergen_pk_signal_cancel <- function(request_id, session = NULL) {
  kimlik <- try(as.character(request_id)[1], silent = TRUE)
  if (inherits(kimlik, "try-error") || is.null(kimlik) || !length(kimlik) ||
      is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))
  pk_cancel_token_signal(mergen_pk_cancel_token_for_session(session, kimlik))
}
