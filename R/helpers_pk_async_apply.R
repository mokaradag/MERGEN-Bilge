# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_apply.R
# Açıklama: Faz 6 (§5.10) — PK analiz sonucunu mesaj bağlamına uygulama,
#           SENKRON yürütme yolu, işçi durum -> kullanıcı metni eşlemesi ve
#           asenkron istek hazırlığı.
# ==============================================================================

#' Analiz sonucunu mesaj bağlamına uygula (SENKRON ve ASENKRON için TEK yol)
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
    return(list(
      action = "answer",
      answer = as.character(analiz_result$content %||% "Analiz tamamlanamadı.")[1],
      messages_to_process = messages_to_process,
      chips = analiz_result$pk_chips %||% list()
    ))
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

#' Analizi SENKRON çalıştır (v1 uyumluluk yolu; `MERGEN_PK_ASYNC=false`)
mergen_pk_run_sync <- function(ctx) {
  tryCatch({
    if (isTRUE(ctx$deep_thinking)) {
      pk_deep_analysis_process(
        ctx$user_message_text, ctx$messages_to_process, ctx$session,
        detail_level = ctx$analysis_detail,
        stop_check = ctx$stop_generation
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

#' İşçi durum kodunu kullanıcıya görünen sonuca çevir
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

  mesaj <- tryCatch(as.character(error)[1], error = function(e) NA_character_)
  if (is.null(mesaj) || length(mesaj) == 0L || is.na(mesaj) || !nzchar(mesaj)) {
    mesaj <- "Analiz tamamlanamadı."
  }
  paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", mesaj)
}

#' İptal jetonunu OTURUM + istek kimliğiyle adlandır
#'
#' İstek sayaçları her Shiny oturumunda yeniden başlayabilir. Yalnız req_id ile
#' üretilen global temp dosyası bu yüzden iki kullanıcının `request_1` isteğini
#' aynı cancellation bayrağına bağlayabilirdi. `session$token` Shiny'nin oturum
#' kapsamlı benzersiz anahtarıdır ve dosya adına slug edilerek eklenir.
mergen_pk_cancel_token_for_session <- function(session, request_id) {
  oturum <- tryCatch(as.character(session$token %||% "")[1], error = function(e) "")
  if (is.na(oturum) || !nzchar(oturum)) oturum <- "session"

  file.path(
    pk_cancel_token_root(),
    paste0(
      "pk_stop_", .pk_cancel_token_slug(oturum), "_",
      .pk_cancel_token_slug(request_id), ".flag"
    )
  )
}

#' Worker'da yazılmış dışa aktarımı GERÇEK Shiny oturumunda yeniden sun
#'
#' Worker vekilinde `registerDataObj` yoktur; dolayısıyla dosya üretilebilir ama
#' URL üretilemez. Future sonucu ana sürece geldikten sonra aynı artifact gerçek
#' session ile kaydedilir ve attachment kartındaki düz dosya satırı tıklanabilir
#' oturum-kapsamlı URL ile değiştirilir.
mergen_pk_serve_worker_artifact <- function(result, session) {
  if (!is.list(result) || !is.list(result$pk_attachment)) return(result)
  if (!exists("pk_export_serve", mode = "function", inherits = TRUE)) return(result)

  eski <- result$pk_attachment
  yeni <- tryCatch(pk_export_serve(session, eski), error = function(e) eski)
  result$pk_attachment <- yeni

  if (exists("pk_compose_attachment_card", mode = "function", inherits = TRUE) &&
      is.character(result$pk_answer_block) && length(result$pk_answer_block) == 1L) {
    eski_kart <- tryCatch(pk_compose_attachment_card(eski), error = function(e) NULL)
    yeni_kart <- tryCatch(pk_compose_attachment_card(yeni), error = function(e) NULL)
    if (is.character(eski_kart) && length(eski_kart) == 1L && nzchar(eski_kart) &&
        is.character(yeni_kart) && length(yeni_kart) == 1L && nzchar(yeni_kart) &&
        grepl(eski_kart, result$pk_answer_block, fixed = TRUE)) {
      result$pk_answer_block <- sub(eski_kart, yeni_kart, result$pk_answer_block, fixed = TRUE)
    }
  }

  result
}

#' Bayat/iptal edilmiş worker sonucunun sunulmamış dosyalarını temizle
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
    if (grepl("(^|/)run_[^/]*$", gsub("\\\\", "/", dizin)) &&
        dir.exists(dizin) && !length(list.files(dizin))) {
      try(unlink(dizin, recursive = TRUE, force = TRUE), silent = TRUE)
    }
  }

  invisible(length(yollar) > 0L)
}

#' Asenkron gönderim için istek anlık görüntüsünü hazırla
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
    user_prompt = ctx$user_message_text,
    chat_history = ctx$messages_to_process,
    username = kimlik$username,
    request_id = ctx$req_id,
    deep_thinking = isTRUE(ctx$deep_thinking),
    detail_level = ctx$analysis_detail,
    api_key_plan = anahtar_plani,
    user_session_snapshot = pk_async_capture_user_data(ctx$session),
    select_state = tryCatch(ctx$session$userData[["pk_select_state"]], error = function(e) NULL),
    repo_root = mergen_pk_async_repo_root(),
    cancel_token = jeton,
    deadline_sec = tryCatch(
      pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC"), error = function(e) 300L
    ),
    engine = motor,
    bootstrap_files = pk_async_worker_bootstrap_files(),
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

# Repo kökü: işçi `getwd()` VARSAYMAZ (çalışma dizini işçide farklı olabilir).
mergen_pk_async_repo_root <- function() {
  kok <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
  if (nzchar(kok) && dir.exists(kok)) {
    return(normalizePath(kok, winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}
