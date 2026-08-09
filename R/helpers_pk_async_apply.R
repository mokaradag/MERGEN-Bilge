# ==============================================================================
# Faz 6: PK async sonuç uygulama, senkron fallback ve ana-süreç yardımcıları.
# ==============================================================================

mergen_pk_apply_analysis_result <- function(analiz_result, messages_to_process) {
  if (is.character(analiz_result)) {
    return(list(action = "answer", answer = as.character(analiz_result)[1],
                messages_to_process = messages_to_process, chips = list()))
  }
  if (!is.list(analiz_result)) {
    return(list(action = "continue", messages_to_process = messages_to_process,
                max_output_tokens = NULL))
  }
  if (identical(analiz_result$type, "error_message")) {
    return(list(action = "answer",
                answer = as.character(analiz_result$content %||% "Analiz tamamlanamadı.")[1],
                messages_to_process = messages_to_process,
                chips = analiz_result$pk_chips %||% list()))
  }

  son <- length(messages_to_process)
  if (son > 0L && !is.null(analiz_result$user_context)) {
    messages_to_process[[son]]$content <- analiz_result$user_context
  }
  if (!is.null(analiz_result$prompt_context)) {
    messages_to_process <- append(
      list(list(role = "system", content = analiz_result$prompt_context, type = "system")),
      messages_to_process
    )
  }
  list(action = "continue", messages_to_process = messages_to_process,
       max_output_tokens = analiz_result$max_tokens)
}

mergen_pk_run_sync <- function(ctx) {
  tryCatch({
    if (isTRUE(ctx$deep_thinking)) {
      pk_deep_analysis_process(
        ctx$user_message_text, ctx$messages_to_process, ctx$session,
        detail_level = ctx$analysis_detail, stop_check = ctx$stop_generation
      )
    } else {
      pk_analiz_process_request(
        ctx$user_message_text, ctx$messages_to_process, ctx$session,
        stop_check = ctx$stop_generation
      )
    }
  }, error = function(e) {
    paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", conditionMessage(e))
  })
}

mergen_pk_worker_outcome_text <- function(status, error = NA_character_) {
  if (identical(status, "cancelled") || identical(status, "deadline")) {
    return(pk_async_halt_message(status))
  }
  if (identical(status, "bootstrap_failed")) {
    return(paste0(
      "\U000026A0\U0000FE0F **Analiz Altyapısı Hazır Değil:** Analiz arka plan ",
      "işçisinde başlatılamadı. Analiz senkron olarak yeniden denendi."
    ))
  }
  mesaj <- try(as.character(error)[1], silent = TRUE)
  if (inherits(mesaj, "try-error")) mesaj <- NA_character_
  if (is.null(mesaj) || !length(mesaj) || is.na(mesaj) || !nzchar(mesaj)) {
    mesaj <- "Analiz tamamlanamadı."
  }
  paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", mesaj)
}

# req_id oturumlar arasında çakışabilir; token adı session$token ile namespace edilir.
mergen_pk_cancel_token_for_session <- function(session, request_id) {
  oturum <- try(as.character(session$token %||% "")[1], silent = TRUE)
  if (inherits(oturum, "try-error")) oturum <- ""
  if (is.na(oturum) || !nzchar(oturum)) oturum <- "session"
  file.path(
    pk_cancel_token_root(),
    paste0("pk_stop_", .pk_cancel_token_slug(oturum), "_",
           .pk_cancel_token_slug(request_id), ".flag")
  )
}

# Worker vekili registerDataObj içermez. Guard geçince artifact gerçek session'da sunulur.
mergen_pk_serve_worker_artifact <- function(result, session) {
  if (!is.list(result) || !is.list(result$pk_attachment) ||
      !exists("pk_export_serve", mode = "function", inherits = TRUE)) return(result)

  eski <- result$pk_attachment
  yeni <- try(pk_export_serve(session, eski), silent = TRUE)
  if (inherits(yeni, "try-error")) yeni <- eski
  result$pk_attachment <- yeni

  if (exists("pk_compose_attachment_card", mode = "function", inherits = TRUE) &&
      is.character(result$pk_answer_block) && length(result$pk_answer_block) == 1L) {
    eski_kart <- try(pk_compose_attachment_card(eski), silent = TRUE)
    yeni_kart <- try(pk_compose_attachment_card(yeni), silent = TRUE)
    if (inherits(eski_kart, "try-error")) eski_kart <- NULL
    if (inherits(yeni_kart, "try-error")) yeni_kart <- NULL
    if (is.character(eski_kart) && length(eski_kart) == 1L && nzchar(eski_kart) &&
        is.character(yeni_kart) && length(yeni_kart) == 1L && nzchar(yeni_kart) &&
        grepl(eski_kart, result$pk_answer_block, fixed = TRUE)) {
      result$pk_answer_block <- sub(eski_kart, yeni_kart, result$pk_answer_block, fixed = TRUE)
    }
  }
  result
}

mergen_pk_cleanup_worker_artifact <- function(result) {
  if (!is.list(result) || !is.list(result$pk_attachment)) return(invisible(FALSE))
  dosyalar <- result$pk_attachment$files %||% list()
  if (!is.list(dosyalar) || !length(dosyalar)) return(invisible(FALSE))

  yollar <- vapply(dosyalar, function(x) {
    if (!is.list(x)) return("")
    as.character(x$path %||% "")[1]
  }, character(1))
  yollar <- yollar[!is.na(yollar) & nzchar(yollar)]
  for (yol in yollar) try(unlink(yol, force = TRUE), silent = TRUE)
  for (dizin in unique(dirname(yollar))) {
    norm <- gsub("\\\\", "/", dizin)
    if (grepl("(^|/)run_[^/]*$", norm) && dir.exists(dizin) && !length(list.files(dizin))) {
      try(unlink(dizin, recursive = TRUE, force = TRUE), silent = TRUE)
    }
  }
  invisible(length(yollar) > 0L)
}

mergen_pk_prepare_async_request <- function(ctx) {
  kimlik <- tryCatch(resolve_pk_analysis_username(ctx$session), error = function(e) NULL)
  if (!is.list(kimlik) || !isTRUE(kimlik$ready)) {
    return(list(ok = FALSE, answer = paste0(
      "\U000023F3 **Kimlik Doğrulama Hazırlanıyor:** ",
      "Proje ve Kaynak Analizi için kullanıcı kimliğiniz henüz hazır değil. ",
      "Lütfen SSO oturumunuz tamamlandıktan sonra tekrar deneyin."
    )))
  }

  anahtar_plani <- tryCatch(
    mb_api_key_get_effective_key(
      session = ctx$session, require_auth = TRUE,
      allow_default = NULL, clear_on_mismatch = TRUE
    ),
    error = function(e) list(key = "", source = "missing", owner = NULL)
  )

  jeton <- mergen_pk_cancel_token_for_session(ctx$session, ctx$req_id)
  pk_cancel_token_clear(jeton)
  motor <- if (exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
               isTRUE(tryCatch(pk_engine_is_v2(), error = function(e) FALSE))) "v2" else "v1"

  istek <- pk_async_build_request(
    user_prompt = ctx$user_message_text, chat_history = ctx$messages_to_process,
    username = kimlik$username, request_id = ctx$req_id,
    deep_thinking = isTRUE(ctx$deep_thinking), detail_level = ctx$analysis_detail,
    api_key_plan = anahtar_plani, user_session_snapshot = pk_async_capture_user_data(ctx$session),
    select_state = tryCatch(ctx$session$userData[["pk_select_state"]], error = function(e) NULL),
    repo_root = mergen_pk_async_repo_root(), cancel_token = jeton,
    deadline_sec = tryCatch(pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC"),
                            error = function(e) 300L),
    engine = motor, bootstrap_files = pk_async_worker_bootstrap_files(),
    started_at = Sys.time()
  )

  dogrulama <- pk_async_validate_request(istek)
  if (!isTRUE(dogrulama$safe)) {
    log_warn(paste0(
      "[PK_ASYNC] Istek anlik goruntusu isci-guvenli degil; senkron yola donuluyor: ",
      paste(utils::head(dogrulama$violations, 5L), collapse = ", ")
    ))
    return(list(ok = FALSE, fallback_sync = TRUE))
  }
  list(ok = TRUE, request = istek, cancel_token = jeton)
}

mergen_pk_async_repo_root <- function() {
  kok <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
  if (nzchar(kok) && dir.exists(kok)) {
    return(normalizePath(kok, winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}
