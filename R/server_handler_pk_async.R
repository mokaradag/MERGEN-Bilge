# ==============================================================================
# Dosya Yolu: R/server_handler_pk_async.R
# Açıklama: Faz 6 (§5.10) — Proje ve Kaynak Analizi GÖNDERİM katmanı.
#           Senkron/asenkron kararını verir, işçiyi explicit-mode ile gönderir,
#           istek+sohbet kimliği korumalı geri çağrıları bağlar ve devamı çağırır.
# ==============================================================================

# Derin analiz gözlem fabrikası, `server_chat_engine_dependencies.R` içindeki
# istek-kapsamlı `pk_analysis_observe` sarmalayıcısını korumalıdır. Fabrika ayrı
# dosyaya çıkarılınca kendi lexical global ortamından `pk_analysis_observe`
# çözmeye başlamış ve wrapper'ın kısa ömürlü telemetri bağlantısını atlamıştı.
# Burada fabrikayı bir kez caller-aware yapıyoruz: çağıranın kapsamındaki gözlem
# fonksiyonu varsa fabrikanın yerel lexical katmanına enjekte edilir.
if (exists("pk_deep_observation_helpers", mode = "function", inherits = TRUE) &&
    !exists(".pk_async_deep_observation_factory_core", envir = .GlobalEnv, inherits = FALSE)) {
  assign(
    ".pk_async_deep_observation_factory_core",
    get("pk_deep_observation_helpers", mode = "function", inherits = TRUE),
    envir = .GlobalEnv
  )

  pk_deep_observation_helpers <- function(...) {
    factory <- get(".pk_async_deep_observation_factory_core", envir = .GlobalEnv,
                   inherits = FALSE)
    scoped_observer <- tryCatch(
      get("pk_analysis_observe", envir = parent.frame(), mode = "function", inherits = TRUE),
      error = function(e) NULL
    )

    if (is.function(scoped_observer)) {
      scope_env <- new.env(parent = environment(factory))
      scope_env$pk_analysis_observe <- scoped_observer
      environment(factory) <- scope_env
    }

    factory(...)
  }
}

#' PK analizini çalıştır: senkron veya asenkron
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
  # içinde çalışmaz.
  mesajlar <- ctx$messages_to_process
  oturum <- ctx$session

  chat_key <- function(x) {
    if (is.null(x) || length(x) == 0L) return("<new-chat>")
    y <- tryCatch(as.character(x)[1], error = function(e) NA_character_)
    if (is.na(y) || !nzchar(y)) "<new-chat>" else y
  }
  kaynak_chat <- tryCatch(shiny::isolate(ctx$values$current_chat_id), error = function(e) NULL)
  kaynak_chat_key <- chat_key(kaynak_chat)

  # onSessionEnded geri çağrısı kaldırılamaz. Bu yüzden callback yalnızca iş
  # gerçekten HÂLÂ aktifken token'ı işaretler. İş tamamlandıktan sonra token
  # temizlenip oturum kapanırsa eski callback dosyayı yeniden yaratamaz.
  request_done <- FALSE
  iptal_kaydi <- tryCatch({
    oturum$onSessionEnded(function() {
      if (!isTRUE(request_done)) pk_cancel_token_signal(cancel_token)
    })
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(iptal_kaydi)) {
    log_info("[PK_ASYNC] onSessionEnded kaydi yapilamadi; iptal jetonu yalnizca Durdur ile isaretlenecek.")
  }

  # Promise/later continuation'ının TAMAMI isolate içindedir. `add_message_fn`
  # ve `continue_fn` alt çağrıları values/current_chat gibi reactives okuyabilir;
  # yalnız üst seviyedeki açık okumaları isolate etmek yeterli değildir.
  devam_et <- function(uygulama) {
    shiny::isolate({
      if (identical(uygulama$action, "answer")) {
        ctx$cleanup_send_message()
        ctx$add_message_fn(uygulama$answer, "ai")
        return(invisible(NULL))
      }
      ctx$continue_fn(uygulama$messages_to_process, uygulama$max_output_tokens)
    })
  }

  # Geri çağrı girişinde ORTAK koruma: request id + stop + sohbet kapsamı.
  # Ret halinde genel cleanup çağrılmaz; yalnız BU req_id'ye ait backpressure
  # slotu bırakılır. Böylece daha yeni isteğin UI/typing durumu sıfırlanmaz.
  koruma_gecti <- function(etiket, result = NULL) {
    aktif <- tryCatch(shiny::isolate(ctx$active_request_id()), error = function(e) NULL)
    durduruldu <- isTRUE(tryCatch(shiny::isolate(ctx$stop_generation()), error = function(e) FALSE))
    karar <- pk_async_should_apply(aktif, req_id, stopped = durduruldu)
    simdiki_chat <- tryCatch(shiny::isolate(ctx$values$current_chat_id), error = function(e) NULL)
    ayni_chat <- identical(chat_key(simdiki_chat), kaynak_chat_key)

    if (!isTRUE(karar$apply) || !isTRUE(ayni_chat)) {
      sebep <- if (!isTRUE(karar$apply)) karar$reason else "chat_changed"
      log_info(sprintf(
        "[PK_ASYNC] Bayat/durdurulmus/sohbet-degismis geri cagri yok sayildi (%s, sebep=%s).",
        etiket, sebep
      ))
      request_done <<- TRUE
      pk_cancel_token_clear(cancel_token)
      try(mergen_pk_cleanup_worker_artifact(result), silent = TRUE)
      try(shiny::isolate(
        mergen_send_message_release_values_token(ctx$values, req_id = req_id)
      ), silent = TRUE)
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
      globals = c(pk_async_worker_globals(), list(request = request)),
      packages = c("DBI", "jsonlite")
    ),
    error = function(e) e
  )

  if (inherits(vaat, "condition")) {
    request_done <- TRUE
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
      if (!isTRUE(koruma_gecti("fulfilled", worker_result$result))) return(invisible(NULL))
      request_done <<- TRUE
      pk_cancel_token_clear(cancel_token)

      durum <- as.character(worker_result$status %||% "error")[1]

      tryCatch(
        pk_async_apply_session_writes(oturum, worker_result$session_writes),
        error = function(e) NULL
      )

      if (identical(durum, "ok")) {
        # Worker vekilinde registerDataObj yoktur. Sunum ve session-end cleanup
        # GERÇEK Shiny session'a burada bağlanır, yalnız guard geçtikten sonra.
        sonuc <- mergen_pk_serve_worker_artifact(worker_result$result, oturum)
        return(devam_et(mergen_pk_apply_analysis_result(sonuc, mesajlar)))
      }

      if (identical(durum, "bootstrap_failed")) {
        log_warn(paste0(
          "[PK_ASYNC] Isci bootstrap basarisiz; bu istek SENKRON yeniden ",
          "deneniyor. MERGEN_PK_ASYNC=false ile geri alinabilir."
        ))
        return(devam_et(mergen_pk_apply_analysis_result(mergen_pk_run_sync(ctx), mesajlar)))
      }

      shiny::isolate({
        ctx$cleanup_send_message()
        ctx$add_message_fn(
          mergen_pk_worker_outcome_text(durum, worker_result$error), "ai"
        )
      })
      invisible(NULL)
    },
    onRejected = function(error) {
      if (!isTRUE(koruma_gecti("rejected"))) return(invisible(NULL))
      request_done <<- TRUE
      pk_cancel_token_clear(cancel_token)

      log_warn(sprintf(
        "[PK_ASYNC] Isci reddedildi: %s",
        tryCatch(conditionMessage(error), error = function(e) "bilinmeyen")
      ))
      shiny::isolate({
        ctx$cleanup_send_message()
        ctx$add_message_fn(mergen_pk_worker_outcome_text("error"), "ai")
      })
      invisible(NULL)
    }
  )

  list(action = "deferred")
}

#' Durdurma anında OTURUM-KAPSAMLI iptal jetonunu işaretle
mergen_pk_signal_cancel <- function(request_id, session = NULL) {
  if (!exists("mergen_pk_cancel_token_for_session", mode = "function", inherits = TRUE)) {
    return(invisible(FALSE))
  }
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.null(kimlik) || length(kimlik) == 0L || is.na(kimlik) || !nzchar(kimlik)) {
    return(invisible(FALSE))
  }
  pk_cancel_token_signal(mergen_pk_cancel_token_for_session(session, kimlik))
}
