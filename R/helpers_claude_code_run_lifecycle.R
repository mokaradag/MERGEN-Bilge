# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_run_lifecycle.R
# Açıklama: Bilge Yolaç komut çalıştırma yaşam döngüsü ve async sonuç korumaları.
#           Bu dosya Shiny modülünden bağımsız, küçük ve test edilebilir yardımcılar
#           içerir. Amaç stale promise/poll callback'lerinin yeni çalışma durumunu
#           ezmesini engellemektir.
# ==============================================================================

cc_next_run_request_id <- function(prefix = "ccrun") {
  prefix <- as.character(prefix %||% "ccrun")[1]
  if (is.na(prefix) || !nzchar(prefix)) {
    prefix <- "ccrun"
  }

  paste0(
    prefix,
    "_",
    format(Sys.time(), "%Y%m%d%H%M%OS6"),
    "_",
    sprintf("%04d", sample.int(10000L, 1L) - 1L)
  )
}

cc_mark_active_run <- function(rv, request_id) {
  request_id <- as.character(request_id %||% "")[1]

  if (is.na(request_id) || !nzchar(request_id)) {
    stop("request_id boş olamaz.", call. = FALSE)
  }

  rv$active_request_id <- request_id
  invisible(request_id)
}

cc_is_active_run <- function(rv, request_id = NULL) {
  # Geriye dönük uyumluluk: eski çağrılar request_id göndermediğinde
  # finalize davranışı aynen devam eder.
  if (is.null(request_id) || length(request_id) == 0L) {
    return(TRUE)
  }

  request_id <- as.character(request_id)[1]
  if (is.na(request_id) || !nzchar(request_id)) {
    return(TRUE)
  }

  active <- tryCatch(
    as.character(rv$active_request_id %||% "")[1],
    error = function(e) ""
  )

  !is.na(active) && nzchar(active) && identical(active, request_id)
}

cc_abort_run_before_streaming <- function(rv, request_id = NULL) {
  if (!cc_is_active_run(rv, request_id)) {
    return(invisible(FALSE))
  }

  rv$is_running <- FALSE
  rv$active_request_id <- NULL

  invisible(TRUE)
}

cc_send_run_blocked_message <- function(session, ns, message, escape = TRUE) {
  msg <- as.character(message %||% "")[1]
  if (is.na(msg)) msg <- ""

  content <- if (isTRUE(escape)) {
    htmltools::htmlEscape(msg)
  } else {
    msg
  }

  session$sendCustomMessage(
    type = "cc-add-message",
    message = list(
      target = ns("output_area"),
      type = "error",
      content = content,
      timestamp = format(Sys.time(), "%H:%M:%S"),
      welcomeId = ns("welcome_screen")
    )
  )

  invisible(TRUE)
}

cc_finalize_if_active <- function(rv,
                                  request_id = NULL,
                                  finalize_streaming,
                                  durum_metin,
                                  durum_ikon,
                                  durum_renk,
                                  sure = NULL) {
  if (!cc_is_active_run(rv, request_id)) {
    return(invisible(FALSE))
  }

  finalize_streaming(
    durum_metin,
    durum_ikon,
    durum_renk,
    sure,
    request_id = request_id
  )

  invisible(TRUE)
}

cc_observe_dir_if_active <- function(rv,
                                     request_id = NULL,
                                     observe_dir_contents,
                                     dizin) {
  if (!cc_is_active_run(rv, request_id)) {
    return(invisible(FALSE))
  }

  observe_dir_contents(dizin = dizin)
  invisible(TRUE)
}

cc_reset_document_summary_session_context <- function(rv, model) {
  rv$cli_session_id <- NULL
  rv$conversation_context <- list()
  rv$current_runtime_model <- model

  invisible(TRUE)
}

cc_handle_document_summary_run <- function(session,
                                           ns,
                                           rv,
                                           run_request_id,
                                           dokuman_baglami,
                                           model,
                                           zaman_asimi,
                                           kaynak_calisma_dizini,
                                           calisma_dizini,
                                           effective_user_id,
                                           kullanici_prompt,
                                           karakter,
                                           karakter_id,
                                           karakter_renk,
                                           finalize_streaming,
                                           observe_dir_contents) {
  # Doküman görevlerinde Claude Code CLI oturumu kesinlikle kullanılmaz.
  # Eski --resume oturumu veya araç bağlamı bu akışa taşınmaz.
  cc_reset_document_summary_session_context(rv, model)

  target_dir <- kaynak_calisma_dizini %||% calisma_dizini

  if (!isTRUE(dokuman_baglami$text_sidecars_ready)) {
    cikarma_detayi <- paste(
      c(
        "Doküman görevi algılandı ancak yerel metin çıkarımı hazırlanamadı.",
        if (length(dokuman_baglami$extraction_errors %||% character(0))) {
          "Çıkarma hataları:"
        } else {
          NULL
        },
        dokuman_baglami$extraction_errors %||% character(0)
      ),
      collapse = "\n"
    )

    log_error(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Doküman görevi CLI'a düşmeden durduruldu.",
      gsub("[{}]", "", cikarma_detayi)
    ))

    session$sendCustomMessage(
      type = "cc-add-message",
      message = list(
        target = ns("output_area"),
        type = "error",
        content = htmltools::htmlEscape(cikarma_detayi),
        timestamp = format(Sys.time(), "%H:%M:%S"),
        welcomeId = ns("welcome_screen")
      )
    )

    cc_finalize_if_active(
      rv = rv,
      request_id = run_request_id,
      finalize_streaming = finalize_streaming,
      durum_metin = "Hata",
      durum_ikon = "exclamation-triangle",
      durum_renk = "#E57373",
      sure = NULL
    )

    cc_observe_dir_if_active(
      rv = rv,
      request_id = run_request_id,
      observe_dir_contents = observe_dir_contents,
      dizin = target_dir
    )

    return(invisible(FALSE))
  }

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Doküman görevi yerel özetleme yoluna yönlendirildi.",
    "Model:", model,
    "| Hazır dosya sayısı:", length(dokuman_baglami$prepared_files %||% list()),
    "| Destek dizini:", dokuman_baglami$effective_workdir %||% ""
  ))

  dokuman_api_key <- tryCatch(
    as.character(session$userData$ai_api_key %||% "")[1],
    error = function(e) ""
  )

  tracked_future_promise(
    task_fn = function() {
      summarize_claude_code_documents_with_local_llm(
        document_context = dokuman_baglami,
        model_id = model,
        api_key = dokuman_api_key,
        request_timeout_sec = zaman_asimi,
        output_dir = target_dir,
        user_id = effective_user_id,
        session_token = session$token %||% format(Sys.time(), "%Y%m%d%H%M%S")
      )
    },
    task_type = "claude_code_document_summary",
    session_token = session$token
  ) |>
    promises::then(function(sonuc) {
      if (!cc_is_active_run(rv, run_request_id)) {
        return(NULL)
      }

      sure <- sonuc$duration %||% NA_real_

      if (isTRUE(sonuc$success)) {
        rv$conversation_context <- c(
          rv$conversation_context,
          list(list(role = "assistant", content = sonuc$output %||% ""))
        )

        assistant_html <- paste0(
          format_claude_code_output(sonuc$output %||% ""),
          sonuc$generated_downloads_html %||% "",
          if (!nzchar(sonuc$generated_downloads_html %||% "") &&
              nzchar(sonuc$generated_summary_path %||% "")) {
            paste0(
              '<div class="cc-generated-files">',
              '<div class="cc-generated-files-title">',
              '<i class="fas fa-file-alt"></i> Oluşturulan Dosya',
              '</div>',
              '<div class="cc-tool-content">',
              '<span class="cc-tool-path">',
              htmltools::htmlEscape(sonuc$generated_summary_path),
              '</span>',
              '</div>',
              '</div>'
            )
          } else {
            ""
          }
        )

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "assistant",
            content = assistant_html,
            timestamp = format(Sys.time(), "%H:%M:%S"),
            accentColor = karakter_renk,
            characterName = karakter$display_name,
            welcomeId = ns("welcome_screen")
          )
        )

        rv$last_result <- sonuc

        cc_finalize_if_active(
          rv = rv,
          request_id = run_request_id,
          finalize_streaming = finalize_streaming,
          durum_metin = "Tamamlandı",
          durum_ikon = "check-circle",
          durum_renk = "#81C784",
          sure = sure
        )
      } else {
        rv$last_result <- sonuc

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = htmltools::htmlEscape(sonuc$error %||% "Bilinmeyen hata"),
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )

        cc_finalize_if_active(
          rv = rv,
          request_id = run_request_id,
          finalize_streaming = finalize_streaming,
          durum_metin = "Hata",
          durum_ikon = "exclamation-triangle",
          durum_renk = "#E57373",
          sure = sure
        )
      }

      rv$output_history <- c(
        rv$output_history,
        list(list(
          prompt = kullanici_prompt,
          result = rv$last_result,
          timestamp = Sys.time(),
          character = karakter_id
        ))
      )

      cc_observe_dir_if_active(
        rv = rv,
        request_id = run_request_id,
        observe_dir_contents = observe_dir_contents,
        dizin = target_dir
      )

      NULL
    }) |>
    promises::catch(function(e) {
      if (!cc_is_active_run(rv, run_request_id)) {
        return(NULL)
      }

      hata_metni <- conditionMessage(e)

      rv$last_result <- list(
        success = FALSE,
        output = "",
        error = hata_metni,
        duration = NA_real_,
        tool_uses = list(),
        session_id = NULL
      )

      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "error",
          content = htmltools::htmlEscape(hata_metni),
          timestamp = format(Sys.time(), "%H:%M:%S"),
          welcomeId = ns("welcome_screen")
        )
      )

      cc_finalize_if_active(
        rv = rv,
        request_id = run_request_id,
        finalize_streaming = finalize_streaming,
        durum_metin = "Hata",
        durum_ikon = "exclamation-triangle",
        durum_renk = "#E57373",
        sure = NULL
      )

      cc_observe_dir_if_active(
        rv = rv,
        request_id = run_request_id,
        observe_dir_contents = observe_dir_contents,
        dizin = target_dir
      )

      NULL
    })

  invisible(TRUE)
}