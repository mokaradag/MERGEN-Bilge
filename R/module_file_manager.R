# R/module_file_manager.R

fileManagerServer <- function(
  id,
  new_file_trigger = reactive(NULL),
  session_files_reactive = NULL,
  mcp_enabled_reactive = reactive({ FALSE }),
  user_id = NULL,
  settings_data = NULL,
  auth_ready_provider = NULL
) {
  moduleServer(id, function(input, output, session) {
  ns <- session$ns

  runtime_helpers <- fm_create_server_runtime_helpers(
    session = session,
    user_id = user_id,
    settings_data = settings_data,
    session_files_reactive = session_files_reactive,
    mcp_enabled_reactive = mcp_enabled_reactive,
    ns = ns,
    module_values_provider = function() module_values,
    auth_ready_provider = auth_ready_provider
  )

  safe_settings_data <- runtime_helpers$safe_settings_data
  get_summarization_mode <- runtime_helpers$get_summarization_mode
  build_attach_rule_hint_text <- runtime_helpers$build_attach_rule_hint_text
  update_attach_rule_hint <- runtime_helpers$update_attach_rule_hint
  get_effective_user_id <- runtime_helpers$get_effective_user_id
  module_user_id_chr <- runtime_helpers$module_user_id_chr
  is_auth_ready <- runtime_helpers$is_auth_ready
  fm_debug <- runtime_helpers$fm_debug
  ensure_session_registry <- runtime_helpers$ensure_session_registry
  register_session_file <- runtime_helpers$register_session_file
  unregister_session_file <- runtime_helpers$unregister_session_file
  ext_icon_html <- runtime_helpers$ext_icon_html
  get_summarization_allowed_extensions <- runtime_helpers$get_summarization_allowed_extensions
  get_normal_allowed_extensions <- runtime_helpers$get_normal_allowed_extensions
  resolve_allowed_extensions <- runtime_helpers$resolve_allowed_extensions
  show_unsupported_extension_toast <- runtime_helpers$show_unsupported_extension_toast
  get_file_by_id <- runtime_helpers$get_file_by_id
  update_session_files <- runtime_helpers$update_session_files
  attach_in_parent <- runtime_helpers$attach_in_parent
  detach_in_parent <- runtime_helpers$detach_in_parent
  format_timestamp <- runtime_helpers$format_timestamp

  fm_debug("init", sprintf("module booting (ns=%s)", ns("")))
	
	# MCP ayarı değiştiğinde (Örn: Excel modu açıldığında) mevcut seçimleri doğrula
    observeEvent(mcp_enabled_reactive(), {
      if (isTRUE(mcp_enabled_reactive())) {
        cleanup_plan <- fm_plan_mcp_context_cleanup(
          file_contents = module_values$file_contents,
          files_in_context = module_values$files_in_context
        )

        if (length(cleanup_plan$remove_ids) > 0L) {
          for (fid in cleanup_plan$remove_ids) {
            module_values$files_in_context[[fid]] <- NULL
          }

          for (fname in cleanup_plan$detached_names) {
            detach_in_parent(fname)
          }

          session$sendCustomMessage(
            ns("setAttachState"),
            list(ids = cleanup_plan$remove_ids, checked = FALSE)
          )
        }

        if (length(cleanup_plan$non_excel_ids) > 0L) {
          showToast(
            session,
            "MCP Excel modu açıldığı için uyumsuz dosyalar seçimden kaldırıldı.",
            "warning"
          )
        }

        if (length(cleanup_plan$excess_ids) > 0L) {
          showToast(
            session,
            "MCP Excel modu tek dosya destekler. Fazla seçimler kaldırıldı.",
            "warning"
          )
        }
      }
    }, ignoreInit = TRUE)

	observeEvent(input$attach_toggled, {
	  req(input$attach_toggled)
	  fid <- input$attach_toggled$id
	  fname <- input$attach_toggled$filename
	  checked <- isTRUE(input$attach_toggled$checked)
	  info <- get_file_by_id(fid)
	  req(info)
	  
	  # Define summarization_mode BEFORE the conditional block
	  summarization_mode <- FALSE
	  summarization_allowed <- get_summarization_allowed_extensions()
	  
	  # Summarization modu için dosya formatı kontrolü
	  if (checked) {
		# Summarization modunu güvenli şekilde kontrol et
		summarization_mode <- get_summarization_mode()
		
		if (summarization_mode) {
		  # Summarization modunda sadece belirli formatlara izin ver
		  ext <- tolower(tools::file_ext(fname))
		  
		  if (!ext %in% summarization_allowed) {
			showToast(session, 
					  sprintf("Dosya Özetleme modunda sadece şu formatlar desteklenir: %s.",
							  paste(toupper(summarization_allowed), collapse = ", ")),
					  "warning")
			# Tiki hemen geri al
			session$sendCustomMessage(ns("setAttachState"), list(ids = fid, checked = FALSE))
			return()
		  }
		}
		
		# MCP ON? allow only one AND check extension
		if (isTRUE(mcp_enabled_reactive())) {
		  
		  # Türkçe: Uzantı kontrolü - Sadece Excel
		  ext <- tolower(tools::file_ext(fname))
		  if (!ext %in% c("xls", "xlsx")) {
			showToast(session, "MCP: Excel modunda sadece Excel dosyaları (.xls, .xlsx) seçilebilir.", "warning")
			# Tiki hemen geri al
			session$sendCustomMessage(ns("setAttachState"), list(ids = fid, checked = FALSE))
			return()
		  }
		  
		  # Uncheck all other selected ones
		  others <- names(module_values$files_in_context)
		  others <- setdiff(others, fid)
		  if (length(others)) {
			module_values$files_in_context[others] <- NULL
			# Update parent (detach others)
			lapply(others, function(ofid) {
			  ofn <- module_values$file_contents[[ofid]]$name
			  if (!is.null(ofn)) detach_in_parent(ofn)
			})
			# Push silent uncheck to UI
			session$sendCustomMessage(ns("setAttachState"), list(ids = others, checked = FALSE))
			showToast(session, "MCP açıkken sadece 1 dosya eklenebilir.", "warning")
		  }
		}
		
		# Mark this one selected
		module_values$files_in_context[[fid]] <- TRUE
		attach_in_parent(info)
		fm_debug("checkbox", sprintf("%s (id=%s) checked", fname, fid))
		showToast(session, paste0("'", fname, "' model bağlamına eklendi."), "success")
		
	  } else {
		# Unselect
		module_values$files_in_context[[fid]] <- NULL
		detach_in_parent(fname)
		fm_debug("checkbox", sprintf("%s (id=%s) unchecked", fname, fid))
		showToast(session, paste0("'", fname, "' model bağlamından çıkarıldı."), "info")
	  }
	  
	  update_attach_rule_hint(
		summarization_mode = summarization_mode,
		allow_summarization_text = TRUE
	  )
	}, ignoreInit = TRUE)

	observe({
	  update_attach_rule_hint()
	})
  
  # --- NEW: persistent storage helpers -----------------------------------------
  storage_helpers <- fm_create_server_storage_helpers(
    module_user_id_chr = module_user_id_chr,
    fm_debug = fm_debug
  )

  get_user_upload_dir <- storage_helpers$get_user_upload_dir
  is_under_mcp_base <- storage_helpers$is_under_mcp_base
  list_user_folder_files <- storage_helpers$list_user_folder_files
  ensure_persisted_upload_index <- storage_helpers$ensure_persisted_upload_index
  
  # Aynı oturumda arka arkaya tetiklenen dosya yenilemelerinde eski istek
  # daha sonra tamamlanırsa yeni state'i ezmesin.
  refresh_guard <- fm_create_refresh_request_guard()
  
	refresh_from_user_folder <- function(trigger = "manual") {
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

		  saved <- process_uploaded_file(finfo, generate_message = FALSE)

		  if (!is.null(saved$id) && !is.null(module_values$file_contents[[saved$id]])) {
			module_values$file_contents[[saved$id]]$persisted_path <- p
			module_values$file_contents[[saved$id]]$datapath <- p
			fm_debug("refresh_file", sprintf("restored entry id=%s", saved$id))
		  } else {
			fm_debug("refresh_file", sprintf("process skipped for %s", display_name))
		  }
		}

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

		module_values$files <- previous_state$files
		module_values$file_contents <- previous_state$file_contents
		module_values$files_in_context <- previous_state$files_in_context
		session$userData$current_session_files <- previous_state$session_registry

		fm_debug("refresh_error", conditionMessage(e))
		fm_debug("refresh_restore", "yenileme başarısız; önceki durum geri yüklendi")
		invisible(NULL)
	  })
	}

    # ---------- STATE ----------
    module_values <- reactiveValues(
      files = fm_empty_files_df(),
      file_contents = list(),
      file_id_to_delete = NULL,
      files_in_context = list()
    )

    observeEvent(TRUE, {
      # SSO açıkken doğrulama tamamlanmadan erken tarama yapma
      if (isTRUE(SSO_ENABLED) && !is_auth_ready()) return()
      refresh_from_user_folder("initial")
    }, once = TRUE, ignoreNULL = TRUE)

    # Not: SSO sonrası tetikleme server.R tarafından tek sefer yönetilir

    if (is.null(session$userData$temp_files)) session$userData$temp_files <- list()

    bulk_files_to_process <- reactiveVal(NULL)
	file_to_preview       <- reactiveVal(NULL)
    file_removed          <- reactiveVal(NULL)
    all_files_cleared     <- reactiveVal(FALSE)

    message_trigger <- reactiveVal(0)
    message_data    <- reactiveVal(NULL)

    files_added_to_context <- reactiveVal(NULL)   # -> parent

    # Tarayıcı tarafında boyut sınırına takılan dosyalar için kullanıcıya toast göster.
    observeEvent(input$bulk_upload_client_error, {
      bilgi <- input$bulk_upload_client_error
      max_mb <- bilgi$max_mb %||% getOption("mergen.upload_max_mb", 25L)

      dosya_ozeti <- ""
      if (!is.null(bilgi$files) && length(bilgi$files) > 0L) {
        dosya_ozeti <- paste(
          vapply(bilgi$files, function(x) {
            sprintf(
              "%s (%.1f MB)",
              x$name %||% "dosya",
              as.numeric(x$size_mb %||% 0)
            )
          }, character(1)),
          collapse = ", "
        )
      }

      showToast(
        session,
        sprintf(
          "Dosya yüklenmedi. Dosya başına en fazla %s MB yükleyebilirsiniz. %s",
          max_mb,
          dosya_ozeti
        ),
        "error"
      )
    }, ignoreInit = TRUE)

    sync_file_to_context <- function(filename, summary = NULL, persisted_path = NULL) {
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

    # ---------- HELPERS ----------
	append_uploaded_file_row <- function(file_name, file_size, file_info, file_id) {
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

    # Helper to remove a file by its display name (invoked from the chat's close button)
    remove_file_by_name <- function(filename, quiet = FALSE) {
      if (!length(module_values$file_contents)) return(invisible(FALSE))
    
      # Find the first matching file-id by filename
      fid <- NULL
      for (id in names(module_values$file_contents)) {
        if (identical(module_values$file_contents[[id]]$name, filename)) { fid <- id; break }
      }
      if (is.null(fid)) return(invisible(FALSE))
    
      info <- module_values$file_contents[[fid]]
    
      # Clean temp file if we persisted it
      if (!is.null(session$userData$temp_files[[fid]])) {
        try(unlink(session$userData$temp_files[[fid]]), silent = TRUE)
        session$userData$temp_files[[fid]] <- NULL
      }
    
      # Önce bağlam/ek durumunu temizle; aksi halde hayalet dosya kalabilir
      module_values$files_in_context[[fid]] <- NULL
      detach_in_parent(filename)

      # Drop from module state
      module_values$file_contents[[fid]] <- NULL
      unregister_session_file(filename)
    
      # Remove the row in the datatable (by id or by name as fallback)
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

    # Persist a stable copy + add to table
	process_uploaded_file <- function(file_info, generate_message = TRUE) {
	  # Normalize incoming structure (Shiny df row OR list)
	  file_name <- as.character(file_info$name %||% "")
	  file_size <- as.numeric(file_info$size %||% NA_real_)
	  in_path   <- as.character(file_info$datapath %||% file_info$path %||% "")
	  fm_debug("process_start", sprintf("name=%s path=%s msg=%s", file_name, in_path, generate_message))
	  
	  # CHANGE: Use path_exists_relaxed instead of file.exists to handle long paths/UNC/spaces
	  if (!nzchar(file_name) || !nzchar(in_path) || !path_exists_relaxed(in_path)) {
		showToast(session, "Yüklenen dosya yolu okunamadı.", "error")
		fm_debug("process_abort", sprintf("invalid path for %s", file_name))
		return(NULL)
	  }
	  
	  # Validate type - ÖZEL: Eğer Dosya Özetleme modu açıksa sadece belirli formatları kabul et
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

      # ALWAYS use a stable “display id” for the table; do not depend on a temp copy
      file_id <- paste0("file_", floor(as.numeric(Sys.time()) * 1000000), "_", sample(100000:999999, 1))
    
		# Use the path we already have (can be Shiny temp OR persisted mergen_uploads)
      # CHANGE: Do NOT re-normalize if path already works (fixes UNC duplication)
      stable_path <- if (path_exists_relaxed(in_path)) {
         in_path
      } else {
         tryCatch(
          normalize_mcp_path(in_path, must_exist = FALSE),
          error = function(e) in_path
        )
      }
    
      # If Shiny’s upload temp disappears later it’s fine; preview code reads immediately,
      # and server will persist a copy separately (processAndSummarizeFile).
      saved <- list(
        name           = file_name,
        datapath       = stable_path,
        size           = file_size,
        type           = file_info$type %||% "",
        id             = file_id,
        persisted_path = stable_path
      )

      register_session_file(file_name, stable_path)
	    fm_debug("process_saved", sprintf("id=%s persisted=%s", file_id, stable_path))
	  
      module_values$file_contents[[file_id]] <- saved
      session$userData$temp_files[[file_id]] <- NULL  # no temp we own here
    
      append_uploaded_file_row(
        file_name = file_name,
        file_size = file_size,
        file_info = file_info,
        file_id = file_id
      )
    
      if (isTRUE(generate_message)) {
		html_message <- sprintf(
		  "\U0001F4CE <b>%s</b> yüklendi. Yapay zekâya eklemek için <i>Model Bağlamı</i> sütunundaki kutucuğu işaretleyin. Önizlemek için <a href='#' class='file-link js-file-action' data-action='view' data-file-id='%s'>tıklayın</a>.",
		  htmltools::htmlEscape(file_name), file_id
		)
        message_data(list(content = paste(file_name, "yüklendi."),
                          html = html_message, type = "system"))
        message_trigger(message_trigger() + 1)
      }
    
      saved
    }

	# Dynamic downloads
    observe({
      lapply(names(module_values$file_contents), function(fid) {
        local({
          my_id <- fid
          output[[paste0("download_", my_id)]] <- downloadHandler(
            filename = function() module_values$file_contents[[my_id]]$name,
            content  = function(file) {
                src <- module_values$file_contents[[my_id]]$datapath
                tryCatch(
                    fs::file_copy(src, file, overwrite = TRUE),
                    error = function(e) file.copy(src, file, overwrite = TRUE)
                )
            },
            contentType = "application/octet-stream"
          )
          outputOptions(output, paste0("download_", my_id), suspendWhenHidden = FALSE)
        })
      })
    })

    # ---------- EVENTS ----------

    # Show action buttons when a selection exists
    observeEvent(input$bulk_upload, {
      shinyjs::runjs(sprintf("$('#%s').show();", ns("execute_bulk_upload_container")))
    }, ignoreInit = TRUE)

	observeEvent(input$clear_pending_files, {
      shinyjs::reset(ns("bulk_upload"))
      shinyjs::runjs(sprintf("$('#%s').hide();", ns("execute_bulk_upload_container")))
	  shinyjs::runjs("$('#bulk_upload_div .progress').hide(); $('#bulk_upload_div .shiny-file-input-progress').hide();")
      session$sendCustomMessage('resetBulkUploadCaption', list())
      showToast(session, "Seçili dosyalar kaldırıldı.", "info")
    })

    # a single file coming from outside (chat area)
    observeEvent(new_file_trigger(), {
      req(new_file_trigger())
      new_file <- new_file_trigger()
      existing <- vapply(module_values$file_contents, `[[`, "", "name")
      if (!new_file$name %in% existing) process_uploaded_file(new_file, generate_message = TRUE)
    }, ignoreInit = TRUE)

    # bulk upload button
	observeEvent(input$execute_bulk_upload, {
      req(input$bulk_upload)

      files_df <- input$bulk_upload
      shinyjs::reset(ns("bulk_upload"))
	  shinyjs::runjs("$('#bulk_upload_div .progress').hide(); $('#bulk_upload_div .shiny-file-input-progress').hide();")
      session$sendCustomMessage('resetBulkUploadCaption', list())
      shinyjs::runjs(sprintf("$('#%s').hide();", ns("execute_bulk_upload_container")))

      existing_names <- vapply(module_values$file_contents, `[[`, "", "name")
      new_df <- files_df[!files_df$name %in% existing_names, , drop = FALSE]
      dup_df <- files_df[ files_df$name %in% existing_names, , drop = FALSE]

      if (nrow(dup_df) > 0) {
        showToast(session, paste("Dosya(lar) zaten mevcut:", paste(dup_df$name, collapse = ", ")), "warning")
      }

      saved_infos <- list()
      if (nrow(new_df) > 0) {
        uid <- module_user_id_chr()

        withProgress(message = 'Dosyalar yükleniyor...', value = 0, {
          for (i in seq_len(nrow(new_df))) {
            incProgress(1 / nrow(new_df), detail = new_df$name[i])

            upload_row <- new_df[i, , drop = FALSE]
            upload_name <- as.character(upload_row$name[1] %||% "")
            upload_path <- as.character(upload_row$datapath[1] %||% "")

            if (!nzchar(uid) || identical(uid, "unknown") || identical(uid, "0")) {
              fm_debug("persist_abort", sprintf("geçersiz user_id nedeniyle kaydedilemedi: %s", upload_name))
              showToast(session, paste("Dosya kalıcı klasöre kaydedilemedi:", upload_name), "error")
              next
            }

			# Varsayılan sınır 25 MB; daha düşük/yüksek ihtiyaç olursa
			# getOption("mergen.upload_max_mb") veya MERGEN_UPLOAD_MAX_MB ile geçilebilir.
            if (exists("validate_uploaded_file", envir = globalenv(), inherits = FALSE)) {
			  max_mb <- fm_upload_limit_mb()

              dogrulama <- validate_uploaded_file(
                path = upload_path,
                filename = upload_name,
                max_size_mb = max_mb,
                allowed_ext = NULL
              )

              if (!isTRUE(dogrulama$ok)) {
                fm_debug("upload_validation_reject",
                         sprintf("%s -> %s (%s)", upload_name,
                                 dogrulama$code %||% "unknown",
                                 dogrulama$error %||% ""))
                showToast(
                  session,
                  sprintf("Dosya reddedildi: %s - %s",
                          upload_name,
                          dogrulama$error %||% "bilinmeyen doğrulama hatası"),
                  "error"
                )
                next
              }
            }

            if (!is_under_mcp_base(upload_path)) {
              persisted_path <- tryCatch({
                copy_to_mcp_base(
                  list(
                    name = upload_name,
                    datapath = upload_path,
                    size = suppressWarnings(as.numeric(upload_row$size[1] %||% NA_real_)),
                    type = as.character(upload_row$type[1] %||% "")
                  ),
                  uid
                )
              }, error = function(e) {
                fm_debug("persist_error", sprintf("%s -> %s", upload_name, conditionMessage(e)))
                ""
              })

              if (!nzchar(persisted_path) || !path_exists_relaxed(persisted_path)) {
                showToast(session, paste("Dosya kalıcı klasöre kaydedilemedi:", upload_name), "error")
                next
              }

              upload_row$datapath[1] <- persisted_path

              persisted_size <- suppressWarnings(file.info(persisted_path)$size[1])
              if (!is.na(persisted_size)) {
                upload_row$size[1] <- persisted_size
              }
            }

            final_persisted_path <- as.character(upload_row$datapath[1] %||% "")
            ensure_persisted_upload_index(
              abs_path = final_persisted_path,
              display_name = upload_name,
              uid = uid
            )

            result <- process_uploaded_file(upload_row, generate_message = FALSE)
			
            if (!is.null(result)) {
              saved_infos[[length(saved_infos) + 1]] <- result
            }
          }
        })

        if (length(saved_infos) > 0) {
          message_data(list(
            content = sprintf("%d dosya yüklendi.", length(saved_infos)),
            html    = sprintf("\U0001F4CE <b>%d dosya</b> yüklendi ve sohbete eklendi.", length(saved_infos)),
            type    = "system"
          ))
          message_trigger(message_trigger() + 1)
          showToast(session, paste(length(saved_infos), "dosya başarıyla yüklendi!"), "success")

          files_added_to_context(saved_infos)
        }

        shinyjs::delay(100, session$sendCustomMessage('resetBulkUploadCaption', list()))
      }
    }, ignoreInit = TRUE)

    # per-row actions
    observeEvent(input$file_action, {
      req(input$file_action)
      info <- module_values$file_contents[[ input$file_action$id ]]
      req(info)

      if (input$file_action$action == "view") {
        file_to_preview(info)
        message_data(list(type = "view_file", content = info$id, html = NULL))
        message_trigger(message_trigger() + 1)

      } else if (input$file_action$action == "delete") {
        module_values$file_id_to_delete <- info$id
        showModal(modalDialog(
          title = "Dosyayı Sil",
          paste0("'", info$name, "' adlı dosyayı silmek istediğinizden emin misiniz?"),
          footer = tagList(
            actionButton(ns("confirm_delete_file"), "Evet, Sil", class = "btn-modern btn-danger"),
            modalButton("İptal", icon = icon("ban"))
          ),
          easyClose = TRUE
        ))
      }
    }, ignoreInit = TRUE)

    observeEvent(input$confirm_delete_file, {
      req(module_values$file_id_to_delete)
      file_id <- module_values$file_id_to_delete
      info    <- module_values$file_contents[[file_id]]
      removeModal()
      req(info)
    
	  # 1) Fiziksel dosyayı sil (birden fazla yol adayını dene)
      uid <- isolate(module_user_id_chr())
      deleted_physical <- FALSE

      # Önce doğrudan bilinen yolları dene (en güvenilir)
      direct_candidates <- c(info$persisted_path, info$datapath, info$path)
      for (cand in direct_candidates) {
        if (!is.null(cand) && nzchar(cand) && path_exists_relaxed(cand)) {
          try(unlink(cand, force = TRUE), silent = TRUE)
          deleted_physical <- TRUE
          fm_debug("delete_physical", sprintf("silindi: %s", cand))
          break
        }
      }

      # Doğrudan yol bulunamazsa resolve ile dene
      if (!deleted_physical) {
        persisted <- try(resolve_uploaded_file(info$name, uid), silent = TRUE)
        if (!inherits(persisted, "try-error") && !is.null(persisted) && path_exists_relaxed(persisted)) {
          try(unlink(persisted, force = TRUE), silent = TRUE)
          deleted_physical <- TRUE
          fm_debug("delete_physical", sprintf("resolve ile silindi: %s", persisted))
        }
      }

      # Son çare: kullanıcı klasöründe basename ile ara
      if (!deleted_physical && !is.null(uid)) {
        fallback_path <- file.path(get_user_upload_dir(), basename(info$name))
        if (path_exists_relaxed(fallback_path)) {
          try(unlink(fallback_path, force = TRUE), silent = TRUE)
          fm_debug("delete_physical", sprintf("fallback ile silindi: %s", fallback_path))
        }
      }

      # İndeksten kaldır
      if (!is.null(uid)) try(mergen_remove_from_index(uid, info$name), silent = TRUE)
    
      # 2) Also drop any local temp we might have created (we no longer create one, but keep for safety)
      if (!is.null(session$userData$temp_files[[file_id]])) {
        try(unlink(session$userData$temp_files[[file_id]]), silent = TRUE)
        session$userData$temp_files[[file_id]] <- NULL
      }
    
      # 3) Clean selection + module state / table row
      module_values$files_in_context[[file_id]] <- NULL
      detach_in_parent(info$name)

      file_removed(info)  # -> parent observers
      module_values$file_contents[[file_id]] <- NULL
      unregister_session_file(info$name)	    
	  idx <- which(grepl(paste0('data-file-id=\"', file_id, '\"'), module_values$files$Islemler))
      if (length(idx) > 0) module_values$files <- module_values$files[-idx, , drop = FALSE]
    
      showToast(session, paste("Dosya silindi:", info$name), "warning")
      message_data(list(type = "system", content = paste0("Silindi: ", info$name), html = NULL))
      message_trigger(message_trigger() + 1)
    }, ignoreInit = TRUE)

    observeEvent(input$clear_files, {
      if (nrow(module_values$files) == 0) return(showToast(session, "Temizlenecek dosya yok.", "info"))
      showModal(modalDialog(
        title = "Tüm Dosyaları Temizle",
        "Tüm yüklenmiş dosyaları silmek istediğinizden emin misiniz?",
        footer = tagList(
          actionButton(ns("confirm_clear_files"), "Evet, Tümünü Sil", class = "btn-modern btn-danger"),
          modalButton("İptal", icon = icon("ban"))
        ),
        easyClose = TRUE
      ))
    })

    observeEvent(input$confirm_clear_files, {
      removeModal()
    
      # 1) Physically delete everything in the user's persisted bucket and clear index
      uid <- isolate(module_user_id_chr())
      if (!is.null(uid)) try(mergen_clear_user_bucket(uid), silent = TRUE)
    
      # 2) Notify parent that all files are gone
      for (file_id in names(module_values$file_contents)) file_removed(module_values$file_contents[[file_id]])
    
      # 3) Clean module state and UI
      for (p in session$userData$temp_files) try(unlink(p), silent = TRUE)
      module_values$files <- module_values$files[0, ]
      module_values$file_contents <- list()
      module_values$files_in_context <- list()
      session$userData$temp_files <- list()
      ensure_session_registry()
      session$userData$current_session_files <- list()
    
      all_files_cleared(TRUE)
      showToast(session, "Tüm dosyalar (diskten de) temizlendi.", "warning")
	  session$sendCustomMessage('resetBulkUploadCaption', list())
      shinyjs::runjs("$('#bulk_upload_div .progress').hide(); $('#bulk_upload_div .shiny-file-input-progress').hide();")
      message_data(list(type = "system", content = "Tüm dosyalar kalıcı klasörden silindi.", html = NULL))
      message_trigger(message_trigger() + 1)
      shinyjs::delay(100, { all_files_cleared(FALSE) })
    }, ignoreInit = TRUE)
                   
	output$files_table <- DT::renderDT({
	  dat <- module_values$files
	  if (nrow(dat) == 0) dat <- dat[0, ]
	  DT::datatable(
		dat,
		escape = FALSE,
		rownames = FALSE,
		selection = "none",
		colnames = c("Dosya Adı", "Boyut", "Tür", "Yükleme Tarihi", "İşlemler", "Model Bağlamı"),
		options = list(
		  # Keep default server-side processing; just show the controls:
		  pageLength = 10,                           # default page size (adjust if you prefer 5)
		  lengthMenu = list(c(5, 10, 25, 50, 100),   # page size dropdown
							c('5', '10', '25', '50', '100')),
		  language = list(
			lengthMenu = "Sayfa başına _MENU_ kayıt göster",
			info       = "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
			infoEmpty  = "Gösterilecek kayıt yok",
			paginate   = list(previous = "Önceki", `next` = "Sonraki")
		  ),
		  paging = TRUE,                             # make it explicit
		  dom = 'l tip',                             # l=length, t=table, i=info, p=pager
		  columnDefs = list(
			list(orderable = FALSE, targets = c(ncol(dat) - 2, ncol(dat) - 1)),  # last TWO cols not sortable
			list(className = 'dt-center', targets = ncol(dat) - 1)               # center last col (cells + header)
		  ),
		  drawCallback = DT::JS(
			sprintf("
			  function(settings){
				var tbl = this.api().table().container();
				try{Shiny.unbindAll(tbl);}catch(e){}
				try{Shiny.bindAll(tbl);}catch(e){}

				// (Re)bind attach checkbox events
				var ns = '%s';
				var $tbl = $(tbl);
				$tbl.find('input.attach-checkbox').off('change.attach').on('change.attach', function(){
				  var fid = this.getAttribute('data-file-id');
				  var fname = this.getAttribute('data-filename');
				  var checked = this.checked ? true : false;
				  Shiny.setInputValue(ns + 'attach_toggled', { id: fid, filename: fname, checked: checked, nonce: Math.random() }, {priority:'event'});
				});
				
				// (Re)init Bootstrap tooltip on the attach checkboxes (uses native title attribute)
				if ($.fn && $.fn.tooltip) {
				  $tbl.find('input.attach-checkbox').tooltip({container:'body', placement:'top', trigger:'hover'});
				}
			  }
			", ns(""))
		  )
		),
		callback = DT::JS("
		  var tbl = table.table().container();
		  try{Shiny.unbindAll(tbl);}catch(e){}
		  try{Shiny.bindAll(tbl);}catch(e){}
		")
	  )
	})
	
	# one-time JS handler for silent checkbox state updates
	observeEvent(TRUE, {
	  session$sendCustomMessage("initAttachHandlerOnce", list(ns_prefix = ns("")))
	}, once = TRUE)

	# register client-side handler
	session$onFlushed(function(){
	  shinyjs::runjs(sprintf("
		(function(){
		  if (window.__attachHandlerInit) return;
		  window.__attachHandlerInit = true;
		  Shiny.addCustomMessageHandler('initAttachHandlerOnce', function(x){ /* no-op; gate */ });
		  Shiny.addCustomMessageHandler('%ssetAttachState', function(msg){
			var ids = Array.isArray(msg.ids) ? msg.ids : [msg.ids];
			ids.forEach(function(fid){
			  var el = document.getElementById('%s' + 'attach_' + fid);
			  if(el){ el.checked = !!msg.checked; }
			});
		  });
		})();
	  ", ns(""), ns("")))
	})

    session$onSessionEnded(function() {
      tf <- session$userData$temp_files
      if (is.null(tf)) return()
      for (temp_path in tf) try(unlink(temp_path), silent = TRUE)
      session$userData$temp_files <- list()
    })
	
	set_attachment_checked <- function(filename, checked) {
	  # find row by name
	  fid <- NULL
	  for (id in names(module_values$file_contents)) {
		if (identical(module_values$file_contents[[id]]$name, filename)) { fid <- id; break }
	  }
	  if (is.null(fid)) return(invisible(FALSE))

	  # Update local selection model
	  if (isTRUE(checked)) {
		module_values$files_in_context[[fid]] <- TRUE
		attach_in_parent(module_values$file_contents[[fid]])
	  } else {
		module_values$files_in_context[[fid]] <- NULL
		detach_in_parent(filename)
	  }

	  # Update checkbox in UI silently (no change event)
	  session$sendCustomMessage(ns("setAttachState"), list(ids = fid, checked = isTRUE(checked)))
	  invisible(TRUE)
	}

    # expose to parent
	list(
	  get_bulk_files           = reactive({ bulk_files_to_process() }),
	  get_file_to_preview      = reactive({ file_to_preview() }),
	  message_trigger          = reactive({ message_trigger() }),
	  get_message              = reactive({ message_data() }),
	  file_contents            = reactive({ module_values$file_contents }),
	  file_removed             = reactive({ file_removed() }),
	  all_files_cleared        = reactive({ all_files_cleared() }),
	  files_added_to_context   = reactive({ files_added_to_context() }),
	  remove_file_from_manager = function(filename) { remove_file_by_name(filename, quiet = TRUE) },
	  set_attachment_checked   = set_attachment_checked,
	  sync_file_to_context     = sync_file_to_context,
	  refresh_persisted_files  = function(trigger = "manual") {
		refresh_from_user_folder(trigger)
	  },
	  reset_attachment_state   = function() {
		ids <- names(module_values$files_in_context)
		if (length(ids) > 0) {
		  session$sendCustomMessage(ns("setAttachState"), list(ids = ids, checked = FALSE))
		  module_values$files_in_context <- list()
		}
	  }
	)
  })
}