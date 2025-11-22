# R/helpers_file_pipeline.R

summarize_file_with_llm <- function(file_text, filename, settings) {
  snippet <- substr(file_text %||% "", 1, 12000)
  chat <- list(
    list(type = "system",
         content = "Türkçe yanıtla. Görevin: yüklenen bir dosyayı kısa ama mantıklı şekilde özetlemek. \
Başlık, kısa açıklama (2-3 cümle) ve en fazla 5 madde halinde ana noktaları ver."),
    list(type = "user",
         content = paste0("Dosya adı: ", filename,
                          "\nİçerik (kısaltılmış olabilir):\n", snippet))
  )
  tryCatch({
    warn_msgs <- character(0)
    res <- withCallingHandlers(
      call_llm_with_retry(chat, reactiveValuesToList(settings), max_retries = 2),
      warning = function(w) {
        warn_msgs <<- c(warn_msgs, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    if (is.list(res) && !is.null(res$content)) {
      res <- res$content
    }
    if (!is.character(res) || length(res) == 0 || is.na(res[1])) {
      res <- ""
    } else {
      res <- as.character(res)[1]
    }
    if (!nzchar(res)) {
      paste("Özet çıkarılamadı. İçerikten bir parça:\n", substr(snippet, 1, 1000))
    } else {
      res
    }
  }, error = function(e) {
    paste("Özet çıkarılamadı. İçerikten bir parça:\n", substr(snippet, 1, 1000))
  })
}

processAndSummarizeFile <- function(file_info,
                                    current_user_id,
                                    session,
                                    settings,
                                    file_manager_data,
                                    session_files_reactive,
                                    update_manager_ui = TRUE,
                                    show_toast = TRUE,
                                    auto_attach = FALSE) {
  note_id <- showNotification(sprintf("İşlem başlatıldı: %s", file_info$name),
                              duration = NULL, type = "message")

  # Ensure file is persisted under MCP base
  dest <- file_info$datapath
  if (!is_under_mcp_base(dest)) {
    dest <- copy_to_mcp_base(list(name = file_info$name, datapath = file_info$datapath), current_user_id)
  }

  # Keep in session for MCP tools
  if (is.null(session$userData$current_session_files)) session$userData$current_session_files <- list()
  session$userData$current_session_files[[file_info$name]] <- list(
    name = file_info$name, datapath = dest, path = dest
  )

  # Snapshot settings once
  settings_snapshot <- tryCatch(reactiveValuesToList(settings), error = function(e) list())
  settings_snapshot$shiny_session <- NULL

  promises::future_promise({
    file_ext <- tolower(tools::file_ext(file_info$name))
    digest <- switch(file_ext,
      "xlsx" = , "xls" = build_excel_digest_json(dest, top_levels = 12),
      {
        txt <- readFileContentToString(list(name = file_info$name, datapath = dest, size = file.info(dest)$size))
        substr(txt, 1, 50000)
      }
    )
    summary_text <- summarize_file_with_llm(digest, file_info$name, settings_snapshot)
    list(summary = summary_text, dest = dest, ext = file_ext)
  }) %...>%
    (function(res) {
      if (isTRUE(auto_attach)) {
        current_files <- session_files_reactive() %||% list()
        current_files[[file_info$name]] <- list(
          name = file_info$name,
          summary = res$summary,
          size = file.info(res$dest)$size,
          type = res$ext
        )
        session_files_reactive(current_files)
      }

      if (is.null(session$userData$file_summaries)) session$userData$file_summaries <- list()
      session$userData$file_summaries[[file_info$name]] <- res$summary

      if (!is.null(file_manager_data$sync_file_to_context)) {
        file_manager_data$sync_file_to_context(
          file_info$name,
          summary = res$summary,
          persisted_path = res$dest
        )
      }

      try(global_register_file(
            res$dest, file_info$name,
            user_id = current_user_id,
            persist_under_mcp_base = TRUE
          ),
          silent = TRUE
      )

      removeNotification(note_id)
      if (isTRUE(show_toast)) showToast(session, paste(file_info$name, "özetlendi."), "success")
    }) %...!%
    (function(e) {
      removeNotification(note_id)
      msg <- tryCatch(enc2utf8(conditionMessage(e)), error = function(err) conditionMessage(e))
      showToast(session, paste("Dosya işlenemedi:", msg), "error")
    })

  invisible(NULL)
}

# Handle a batch from fileInput with identical logic to server.R observer
handle_file_upload_batch <- function(uploads_df,
                                     current_user_id,
                                     session,
                                     settings_data,
                                     file_manager_data,
                                     session_files_reactive,
                                     file_to_add_reactive) {
  if (is.null(uploads_df)) return(invisible(NULL))

  uploads <- NULL
  if (is.data.frame(uploads_df)) {
    if (nrow(uploads_df) == 0) return(invisible(NULL))
    uploads <- lapply(seq_len(nrow(uploads_df)), function(i) {
      list(
        name     = as.character(uploads_df$name[i]),
        datapath = as.character(uploads_df$datapath[i]),
        size     = suppressWarnings(as.numeric(uploads_df$size[i] %||% NA_real_)),
        type     = as.character(uploads_df$type[i] %||% "")
      )
    })
  } else if (is.list(uploads_df) && !is.null(uploads_df$name)) {
    uploads <- list(list(
      name     = uploads_df$name,
      datapath = uploads_df$datapath,
      size     = uploads_df$size %||% suppressWarnings(file.info(uploads_df$datapath)$size),
      type     = uploads_df$type %||% ""
    ))
  } else {
    showToast(session, "Dosya yükleme bilgisi okunamadı.", "error")
    return(invisible(NULL))
  }

  total <- length(uploads)
  cat(sprintf("[UPLOAD] %d dosya alındı: %s\n",
              total, paste(vapply(uploads, `[[`, "", "name"), collapse = ", ")))

  note_id <- showNotification(if (total > 1) "Dosyalar alındı. İşleme başlanıyor…" else
                                            "Dosya alındı. İşleme başlanıyor…",
                              duration = NULL, type = "message")

  process_next <- function(i) {
    if (i > total) {
      removeNotification(note_id)
      return(invisible(NULL))
    }
    uf <- uploads[[i]]
	
    allowed_exts <- c("txt","pdf","docx","xlsx","xls","csv","json","r","py","md","log","xml","html")
    ext <- tolower(tools::file_ext(uf$name))
    
    if (!ext %in% allowed_exts) {
      showToast(session, sprintf("'%s' uzantılı dosya desteklenmiyor. İşlem atlandı.", ext), "warning")
      shinyjs::delay(50, process_next(i + 1))
      return(invisible(NULL))
    }
	
    removeNotification(note_id)
    note_id <<- showNotification(sprintf("[%d/%d] İşleniyor: %s", i, total, uf$name),
                                 duration = NULL, type = "message")

    try({
      dest <- copy_to_mcp_base(uf, current_user_id)
      uf$datapath <- dest
    }, silent = TRUE)

    file_to_add_reactive(uf)

    processAndSummarizeFile(
      uf,
      current_user_id = current_user_id,
      session = session,
      settings = settings_data,
      file_manager_data = file_manager_data,
      session_files_reactive = session_files_reactive,
      update_manager_ui = TRUE,
      show_toast = TRUE,
      auto_attach = FALSE
    )

    shinyjs::delay(50, process_next(i + 1))
  }

  process_next(1)
}