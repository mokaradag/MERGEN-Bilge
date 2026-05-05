# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_state_runtime.R
# Açıklama: Dosya Yönetimi kalıcı refresh ve dosya state mutasyon yardımcıları.
# ==============================================================================

fm_create_file_action_helpers <- function(
  session,
  ns,
  module_values_provider,
  get_summarization_mode,
  resolve_allowed_extensions,
  show_unsupported_extension_toast,
  register_session_file,
  unregister_session_file,
  detach_in_parent,
  message_data,
  message_trigger,
  fm_debug
) {
  sync_file_to_context <- function(filename, summary = NULL, persisted_path = NULL) {
    module_values <- module_values_provider()
    if (!length(module_values$file_contents)) return(invisible(FALSE))

    updated <- FALSE
    for (id in names(module_values$file_contents)) {
      entry <- module_values$file_contents[[id]]
      if (!identical(entry$name, filename)) next

      if (!is.null(summary)) {
        module_values$file_contents[[id]]$summary <- summary
        fm_debug("sync", sprintf("summary updated for %s", filename))
      }

      if (!is.null(persisted_path) && nzchar(persisted_path)) {
        norm_path <- tryCatch({
          if (exists("normalize_mcp_path", mode = "function")) {
            normalize_mcp_path(persisted_path, must_exist = FALSE)
          } else {
            persisted_path
          }
        }, error = function(e) persisted_path)

        module_values$file_contents[[id]]$persisted_path <- norm_path
        module_values$file_contents[[id]]$datapath <- norm_path
        register_session_file(filename, norm_path)
        fm_debug("sync", sprintf("path updated for %s -> %s", filename, norm_path))
      }

      updated <- TRUE
    }

    invisible(updated)
  }

  append_uploaded_file_row <- function(file_name, file_size, file_info, file_id) {
    module_values <- module_values_provider()

    module_values$files <- rbind(
      module_values$files,
      fm_build_file_table_row(
        file_name = file_name,
        file_size = file_size,
        file_info = file_info,
        file_id = file_id,
        ns = ns
      )
    )

    invisible(TRUE)
  }

  remove_file_by_name <- function(filename, quiet = FALSE) {
    module_values <- module_values_provider()
    if (!length(module_values$file_contents)) return(invisible(FALSE))

    fid <- NULL
    for (id in names(module_values$file_contents)) {
      if (identical(module_values$file_contents[[id]]$name, filename)) {
        fid <- id
        break
      }
    }

    if (is.null(fid)) return(invisible(FALSE))

    if (!is.null(session$userData$temp_files[[fid]])) {
      try(unlink(session$userData$temp_files[[fid]]), silent = TRUE)
      session$userData$temp_files[[fid]] <- NULL
    }

    module_values$files_in_context[[fid]] <- NULL
    detach_in_parent(filename)

    module_values$file_contents[[fid]] <- NULL
    unregister_session_file(filename)

    rm_idx <- which(
      grepl(paste0('data-file-id=\\"', fid, '\\"'), module_values$files$Islemler) |
        module_values$files$Dosya_Adi == filename
    )

    if (length(rm_idx) > 0) {
      module_values$files <- module_values$files[-rm_idx, , drop = FALSE]
    }

    if (!quiet) {
      showToast(session, paste("Dosya kaldırıldı:", filename), "info")
    }

    invisible(TRUE)
  }

  process_uploaded_file <- function(file_info, generate_message = TRUE) {
    module_values <- module_values_provider()

    raw_file_name <- as.character(file_info$name %||% "")
    file_name <- raw_file_name

    if (exists("recover_display_name_from_storage_name", mode = "function", inherits = TRUE)) {
      recovered_name <- try(recover_display_name_from_storage_name(raw_file_name), silent = TRUE)

      if (!inherits(recovered_name, "try-error") &&
          !is.na(recovered_name) &&
          nzchar(recovered_name)) {
        file_name <- recovered_name
      }
    }

    if (!is.na(file_name) && nzchar(file_name)) {
      file_info$name <- file_name
    }

    file_size <- as.numeric(file_info$size %||% NA_real_)
    in_path <- as.character(file_info$datapath %||% file_info$path %||% "")

    fm_debug("process_start", sprintf("name=%s path=%s msg=%s", file_name, in_path, generate_message))

    if (!nzchar(file_name) || !nzchar(in_path) || !path_exists_relaxed(in_path)) {
      showToast(session, "Yüklenen dosya yolu okunamadı.", "error")
      fm_debug("process_abort", sprintf("invalid path for %s", file_name))
      return(NULL)
    }

    file_ext <- tolower(tools::file_ext(file_name))

    summarization_mode <- get_summarization_mode()
    allowed_extensions <- resolve_allowed_extensions(
      generate_message = generate_message,
      summarization_mode = summarization_mode
    )

    if (!file_ext %in% allowed_extensions) {
      show_unsupported_extension_toast(
        file_ext = file_ext,
        summarization_mode = summarization_mode
      )
      fm_debug("process_abort", sprintf("unsupported extension: %s", file_ext))
      return(NULL)
    }

    file_id <- paste0(
      "file_",
      floor(as.numeric(Sys.time()) * 1000000),
      "_",
      sample(100000:999999, 1)
    )

    stable_path <- if (path_exists_relaxed(in_path)) {
      in_path
    } else {
      tryCatch(
        normalize_mcp_path(in_path, must_exist = FALSE),
        error = function(e) in_path
      )
    }

    saved <- list(
      name = file_name,
      datapath = stable_path,
      size = file_size,
      type = file_info$type %||% "",
      id = file_id,
      persisted_path = stable_path
    )

    register_session_file(file_name, stable_path)
    fm_debug("process_saved", sprintf("id=%s persisted=%s", file_id, stable_path))

    module_values$file_contents[[file_id]] <- saved
    session$userData$temp_files[[file_id]] <- NULL

    append_uploaded_file_row(
      file_name = file_name,
      file_size = file_size,
      file_info = file_info,
      file_id = file_id
    )

    if (isTRUE(generate_message)) {
      html_message <- sprintf(
        "\U0001F4CE <b>%s</b> yüklendi. Yapay zekâya eklemek için <i>Model Bağlamı</i> sütunundaki kutucuğu işaretleyin. Önizlemek için <a href='#' class='file-link js-file-action' data-action='view' data-file-id='%s'>tıklayın</a>.",
        htmltools::htmlEscape(file_name),
        file_id
      )

      message_data(list(
        content = paste(file_name, "yüklendi."),
        html = html_message,
        type = "system"
      ))
      message_trigger(message_trigger() + 1)
    }

    saved
  }

  list(
    sync_file_to_context = sync_file_to_context,
    append_uploaded_file_row = append_uploaded_file_row,
    remove_file_by_name = remove_file_by_name,
    process_uploaded_file = process_uploaded_file
  )
}

fm_create_refresh_from_user_folder <- function(
  session,
  ns,
  module_values_provider,
  module_user_id_chr,
  is_auth_ready,
  ensure_session_registry,
  attach_in_parent,
  process_uploaded_file_callback,
  refresh_guard,
  fm_debug
) {
  function(trigger = "manual") {
    uid <- module_user_id_chr()

    if (isTRUE(SSO_ENABLED) && !is_auth_ready()) {
      fm_debug("refresh_skip", sprintf("trigger=%s, auth henüz tamamlanmadı", trigger))
      return(invisible(NULL))
    }

    if (!fm_valid_user_id(uid)) {
      fm_debug("refresh_skip", sprintf("trigger=%s, geçersiz user_id=%s", trigger, uid))
      return(invisible(NULL))
    }

    request_id <- refresh_guard$next_id()

    fm_debug("refresh_start", sprintf("trigger=%s request_id=%s", trigger, request_id))

    ensure_session_registry()

    module_values <- module_values_provider()

    previous_state <- list(
      files = module_values$files,
      file_contents = module_values$file_contents,
      files_in_context = module_values$files_in_context,
      session_registry = session$userData$current_session_files
    )

    df <- try(mergen_list_user_files(uid), silent = TRUE)

    if (!refresh_guard$is_latest(request_id)) {
      fm_debug("refresh_skip", sprintf(
        "trigger=%s request_id=%s eski kaldı; yeni yenileme isteği uygulanacak",
        trigger,
        request_id
      ))
      return(invisible(NULL))
    }

    if (inherits(df, "try-error")) {
      cond <- attr(df, "condition")
      msg <- if (inherits(cond, "condition")) conditionMessage(cond) else as.character(df)
      fm_debug("refresh_error", msg)
      fm_debug("refresh_restore", "önceki durum korunuyor")
      return(invisible(NULL))
    }

    source_tag <- attr(df, "source") %||% "unknown"

    if (is.null(df) || nrow(df) == 0) {
      fm_debug("refresh_skip", sprintf("empty result (source=%s), mevcut durum korunuyor", source_tag))
      return(invisible(NULL))
    }

    previously_attached_names <- unique(vapply(
      names(previous_state$files_in_context),
      function(fid) {
        entry <- previous_state$file_contents[[fid]]
        if (is.null(entry) || is.null(entry$name)) "" else as.character(entry$name)
      },
      character(1)
    ))
    previously_attached_names <- previously_attached_names[nzchar(previously_attached_names)]

    tryCatch({
      if (!refresh_guard$is_latest(request_id)) {
        fm_debug("refresh_skip", sprintf(
          "trigger=%s request_id=%s state uygulanmadan eski kaldı",
          trigger,
          request_id
        ))
        return(invisible(NULL))
      }

      module_values <- module_values_provider()

      module_values$files <- fm_empty_files_df()
      module_values$file_contents <- list()
      module_values$files_in_context <- list()
      session$userData$current_session_files <- list()

      fm_debug("refresh_found", sprintf("%d candidate file(s) (source=%s)", nrow(df), source_tag))

      for (i in seq_len(nrow(df))) {
        p <- df$path[i]
        display_name <- df$name[i]
        exists_now <- path_exists_relaxed(p)

        fm_debug("refresh_file", sprintf("%s -> %s exists=%s", display_name, p, exists_now))

        if (!exists_now) {
          fm_debug("refresh_skip", sprintf("skipping %s (missing on disk)", display_name))
          next
        }

        p_fixed <- gsub("\\\\", "/", p)

        if (!file.exists(p_fixed) && !fs::file_exists(p_fixed)) {
          if (grepl("^/[^/]", p_fixed)) {
            p_unc <- paste0("/", p_fixed)
            if (file.exists(p_unc) || fs::file_exists(p_unc)) {
              p_fixed <- p_unc
            }
          }
        }

        p <- p_fixed

        f_size <- tryCatch({
          s <- fs::file_info(p)$size
          if (is.na(s)) stop("NA size")
          as.numeric(s)
        }, error = function(e) {
          s <- suppressWarnings(file.info(p)$size)
          if (is.na(s)) 0 else as.numeric(s)
        })

        finfo <- list(
          name = display_name,
          datapath = p,
          size = f_size,
          type = mime::guess_type(p) %||% tools::file_ext(display_name)
        )

        saved <- process_uploaded_file_callback(finfo)

        module_values <- module_values_provider()

        if (!is.null(saved$id) && !is.null(module_values$file_contents[[saved$id]])) {
          module_values$file_contents[[saved$id]]$persisted_path <- p
          module_values$file_contents[[saved$id]]$datapath <- p
          fm_debug("refresh_file", sprintf("restored entry id=%s", saved$id))
        } else {
          fm_debug("refresh_file", sprintf("process skipped for %s", display_name))
        }
      }

      module_values <- module_values_provider()

      if (length(previously_attached_names) > 0) {
        for (fid in names(module_values$file_contents)) {
          entry <- module_values$file_contents[[fid]]
          if (is.null(entry) || is.null(entry$name)) next
          if (!entry$name %in% previously_attached_names) next

          module_values$files_in_context[[fid]] <- TRUE
          attach_in_parent(entry)
          session$sendCustomMessage(ns("setAttachState"), list(ids = fid, checked = TRUE))
        }
      }

      fm_debug("refresh_done", sprintf("table rows=%d", nrow(module_values$files)))
    }, error = function(e) {
      if (!refresh_guard$is_latest(request_id)) {
        fm_debug("refresh_error_stale", sprintf(
          "trigger=%s request_id=%s hata verdi ama eski kaldığı için state restore edilmedi: %s",
          trigger,
          request_id,
          conditionMessage(e)
        ))
        return(invisible(NULL))
      }

      module_values <- module_values_provider()

      module_values$files <- previous_state$files
      module_values$file_contents <- previous_state$file_contents
      module_values$files_in_context <- previous_state$files_in_context
      session$userData$current_session_files <- previous_state$session_registry

      fm_debug("refresh_error", conditionMessage(e))
      fm_debug("refresh_restore", "yenileme başarısız; önceki durum geri yüklendi")
      invisible(NULL)
    })
  }
}