# R/module_file_manager.R

#' File Manager UI Module
#'
#' @param id A character string, the namespace ID for the module.
#'
#' @return A UI definition for the file manager tab.
fileManagerUI <- function(id) {
  ns <- NS(id)
  
tagList(
    # 32×32 attach checkbox + center it in its cell
	tags$head(tags$style(HTML("
		  .files-table-card .attach-cell { display:flex; align-items:center; justify-content:center; }
		  .files-table-card input.attach-checkbox { width:32px; height:32px; margin:0; }
		  /* center the header cell of the last column (Model Bağlamı) */
		  .files-table-card table.dataTable thead th:last-child { text-align: center !important; }
		"))),
    div(
      class = "content-container",
      style = "padding-right: 20px;",
      # Header matching "Ayarlar" page style
      div(
        class = "files-header",
        h3("Toplu Dosya Yükleme", class = "page-title"),
		actionButton(
		  ns("clear_files"),
		  label = tagList(icon("trash-alt"), span("Tümünü Temizle", class = "btn-text")),
		  class = "btn-modern btn-danger"
		)
      ),
      # Scrollable content area
      div(
        class = "scrollable-content",
        # Drag and drop area
        div(
          class = "file-upload-card",
          div(
            id = ns("main_drop_zone"),
            class = "main-drop-zone",
            tags$i(class = "fas fa-upload fa-3x"),
            h4("Dosyaları buraya sürükleyin veya göz atın"),
            div(
              id = "bulk_upload_div",
              fileInput(
                ns("bulk_upload"),
                label = NULL,
                multiple = TRUE,
                buttonLabel = tagList(
                  icon("folder-open", class = "file-browse-icon"),
                  span("Göz At")
                ),
                placeholder = "Henüz dosya seçilmedi"
              )
            ),
            p(class = "upload-hint", "Birden fazla dosya seçebilirsiniz"),
            p(class = "upload-hint", 
              style = "margin-top: 8px; font-size: 12px;",
              "Desteklenen dosya türleri: TXT, PDF, DOCX, XLSX, XLS, CSV, JSON, R, PY, MD, LOG, XML, HTML"),
            div(
              id = ns("execute_bulk_upload_container"),
              style = "display: none; margin-top: 20px;"
            )
          )
        ),
        # Files table
		div(
		  class = "files-table-card",
		  h3("Yüklenen Dosyalar", class = "section-title"),
		  div(
				id = ns("attach_rule_hint"),
				style = "margin: 6px 0 12px 0; font-size: 12px; color: #a3a3a3;",
				"Seçim kuralı: MCP (Excel) açıkken yalnızca tek bir Excel dosyası bağlanabilir; kapalıyken birden fazla seçim yapabilirsiniz."
		  ),
		  DT::dataTableOutput(ns("files_table"))
		)
      )
    ),
    shinyjs::useShinyjs()
  )
}

fileManagerServer <- function(
  id,
  new_file_trigger = reactive(NULL),
  session_files_reactive = NULL,
  mcp_enabled_reactive = reactive({ FALSE })
) {
  moduleServer(id, function(input, output, session) {
  ns <- session$ns
  
    # Dosya uzantısına göre ikon + etiket HTML'i üretir
  ext_icon_html <- function(ext) {
    e <- tolower(ext %||% "")
    ico <- switch(
      e,
      "pdf"  = "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>",
      "doc"  = "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>",
      "docx" = "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>",
      "xls"  = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
      "xlsx" = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
      # Not: csv için Excel ikonunu kullanıyoruz (geniş uyumluluk)
      "csv"  = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
      # Kod/biçimlendirilmiş metin türleri
      "json" = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
      "xml"  = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
      "html" = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
      "r"    = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
      "py"   = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
      # Düz metin türleri
      "md"   = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
      "log"  = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
      "txt"  = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
      # Varsayılan
      "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
    )
    paste0(ico, toupper(e))
  }
  
	# Get (id -> file object)
	get_file_by_id <- function(fid) {
	  module_values$file_contents[[fid]] %||% NULL
	}

	is_excel_file <- function(info) {
	  if (is.null(info)) return(FALSE)
	  excel_exts <- c("xls", "xlsx", "xlsm", "xlsb", "xltx", "xltm")
	  excel_mimes <- c(
		"application/vnd.ms-excel",
		"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		"application/vnd.ms-excel.sheet.macroenabled.12",
		"application/vnd.ms-excel.sheet.binary.macroenabled.12"
	  )
	  ext <- tolower(tools::file_ext(info$name %||% ""))
	  mime <- tolower(info$type %||% "")
	  (nzchar(ext) && ext %in% excel_exts) || (nzchar(mime) && mime %in% excel_mimes)
	}

	# Update parent session_files using the bridge we were given
	attach_in_parent <- function(file_obj) {
	  if (is.null(session_files_reactive)) return(invisible())
	  update_session_files(function(cur) {
		cur <- cur %||% list()
		# Minimal payload is OK for Ekli Dosyalar badge; summary will arrive later
		cur[[file_obj$name]] <- cur[[file_obj$name]] %||% list(name = file_obj$name)
		cur
	  })
	}

	detach_in_parent <- function(file_name) {
	  if (is.null(session_files_reactive)) return(invisible())
	  update_session_files(function(cur) {
		cur <- cur %||% list()
		cur[[file_name]] <- NULL
		cur
	  })
	}
	
	observeEvent(input$attach_toggled, {
	  req(input$attach_toggled)
	  fid <- input$attach_toggled$id
	  fname <- input$attach_toggled$filename
	  checked <- isTRUE(input$attach_toggled$checked)
	  info <- get_file_by_id(fid)
	  req(info)

  if (checked) {
		if (isTRUE(mcp_enabled_reactive()) && !is_excel_file(info)) {
		  session$sendCustomMessage(ns("setAttachState"), list(ids = fid, checked = FALSE))
		  module_values$files_in_context[[fid]] <- NULL
		  detach_in_parent(fname)
		  showToast(session, "MCP: Excel modunda yalnızca Excel dosyaları bağlanabilir.", "error")
		  return()
		}
		# MCP ON? allow only one
		if (isTRUE(mcp_enabled_reactive())) {
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

	  } else {
		# Unselect
		module_values$files_in_context[[fid]] <- NULL
		detach_in_parent(fname)
	  }

	  # Update the hint text dynamically
	  txt <- if (isTRUE(mcp_enabled_reactive())) {
			"Seçim kuralı: MCP (Excel) açıkken yalnızca tek bir Excel dosyası bağlanabilir."
	  } else {
			"Seçim kuralı: MCP kapalıyken birden fazla dosya seçebilirsiniz."
	  }
	  shinyjs::html(id = "attach_rule_hint", html = txt, add = FALSE)
	}, ignoreInit = TRUE)

	observe({
	  txt <- if (isTRUE(mcp_enabled_reactive())) {
			"Seçim kuralı: MCP (Excel) açıkken yalnızca tek bir Excel dosyası bağlanabilir."
	  } else {
			"Seçim kuralı: MCP kapalıyken birden fazla dosya seçebilirsiniz."
	  }
	  shinyjs::html(id = "attach_rule_hint", html = txt, add = FALSE)
	})

	observeEvent(mcp_enabled_reactive(), {
	  if (!isTRUE(mcp_enabled_reactive())) return()
	  selected_ids <- names(module_values$files_in_context)
	  if (!length(selected_ids)) return()

	  keep_id <- NULL
	  invalid_ids <- character()
	  extra_ids <- character()

	  for (fid in selected_ids) {
		info <- module_values$file_contents[[fid]]
		if (is.null(info)) next

		if (!is_excel_file(info)) {
		  invalid_ids <- c(invalid_ids, fid)
		} else if (is.null(keep_id)) {
		  keep_id <- fid
		} else {
		  extra_ids <- c(extra_ids, fid)
		}
	  }

	  to_uncheck <- unique(c(invalid_ids, extra_ids))
	  if (!length(to_uncheck)) return()

	  module_values$files_in_context[to_uncheck] <- NULL
	  lapply(to_uncheck, function(fid) {
		info <- module_values$file_contents[[fid]]
		if (!is.null(info)) detach_in_parent(info$name)
	  })
	  session$sendCustomMessage(ns("setAttachState"), list(ids = to_uncheck, checked = FALSE))

	  if (length(invalid_ids) > 0 && length(extra_ids) > 0) {
		showToast(session,
				 "MCP: Sadece tek bir Excel dosyası tutuldu; diğer türler ve fazladan seçimler kaldırıldı.",
				 "warning")
	  } else if (length(invalid_ids) > 0) {
		showToast(session,
				 "MCP: Excel modunda yalnızca Excel dosyaları bağlanabilir. Uygun olmayan seçimler kaldırıldı.",
				 "warning")
	  } else {
		showToast(session,
				 "MCP açıkken yalnızca tek bir Excel dosyası seçilebilir; fazladan seçimler kaldırıldı.",
				 "warning")
	  }
	})
  
  # --- NEW: persistent storage helpers -----------------------------------------
  get_user_upload_dir <- function() {
    base <- getOption(
      "mergen.mcp_base_dir",
      Sys.getenv("MCP_FILES_BASE",
                 normalizePath(file.path(getwd(), "mergen_uploads"),
                               winslash = "/", mustWork = FALSE))
    )
    file.path(base, sprintf("user_%s", as.character(session$userData$user_id %||% "unknown")))
  }
    
  list_user_folder_files <- function() {
    udir <- get_user_upload_dir()
    if (!dir.exists(udir)) return(character(0))
    list.files(udir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE)
  }
  
	refresh_from_user_folder <- function() {
	  uid <- session$userData$user_id %||% "unknown"
	  df <- try(mergen_list_user_files(uid), silent = TRUE)

	  # Reset table + state, then rebuild (preserving original display names)
	  module_values$files <- module_values$files[0, ]
	  module_values$file_contents <- list()

	  if (inherits(df, "try-error") || is.null(df) || nrow(df) == 0) return(invisible(NULL))

	  for (i in seq_len(nrow(df))) {
		p <- df$path[i]
		display_name <- df$name[i]
		if (!path_exists_relaxed(p)) next
		finfo <- file.info(p)

		# Avoid POSIXt '*' issue: wrap Sys.time() with as.numeric()
		fid <- paste0("persist_", as.integer(as.numeric(Sys.time()) * 1000), "_", sample(100000:999999, 1))

		actions <- as.character(tags$div(
		  class = "file-actions",
		  tags$button(class = "file-action-btn file-view js-file-action",
					  title = "Görüntüle", `data-action` = "view", `data-file-id` = fid, icon("eye")),
		  tags$button(class = "file-action-btn file-download js-download-btn",
					  title = "İndir", `data-download-id` = fid, icon("download")),
		  tags$button(class = "file-action-btn file-delete js-file-action",
					  title = "Sil", `data-action` = "delete", `data-file-id` = fid, icon("trash")),
		  HTML(as.character(tags$span(style="display:none;",
			  shiny::downloadLink(outputId = ns(paste0("download_", fid)), label = ""))))
		))
		
		attach_cell <- as.character(tags$div(
		  class = "attach-cell",
		  tags$input(
			id = ns(paste0("attach_", fid)),
			type = "checkbox",
			class = "attach-checkbox",
			`data-file-id` = fid,
			`data-filename` = display_name,
			title = "Bu dosyayı model bağlamına ekle/çıkar",
			`aria-label` = "Model bağlamına ekle veya çıkar"
		  )
		))

		# Uzantıyı küçük harfe çevir (ikon eşlemesi için)
		ext <- tolower(tools::file_ext(display_name))

		module_values$files <- rbind(
		  module_values$files,
			data.frame(
			  Dosya_Adi       = display_name,
			  Boyut           = paste(round(finfo$size / 1024, 2), "KB"),
			  # Tür sütunu: ikon + etiket
			  Tur             = ext_icon_html(ext),
			  Yuklenme_Tarihi = format(finfo$mtime, "%Y-%m-%d %H:%M"),
			  Islemler        = actions,
			  Model_Baglam    = attach_cell,
			  stringsAsFactors = FALSE
			)
		)

		module_values$file_contents[[fid]] <- list(
		  id             = fid,
		  name           = display_name,
		  datapath       = p,
		  size           = finfo$size,
		  type           = tools::file_ext(display_name),
		  persisted_path = p
		)
	  }
	}

    # ---------- STATE ----------
    module_values <- reactiveValues(
		files = data.frame(
		  Dosya_Adi = character(0),
		  Boyut = character(0),
		  Tur = character(0),
		  Yuklenme_Tarihi = character(0),
		  Islemler = character(0),
		  Model_Baglam = character(0),   # NEW COLUMN (renders the checkbox)
		  stringsAsFactors = FALSE
		),
      file_contents = list(),
      file_id_to_delete = NULL,
      files_in_context = list()
    )

    # --- NEW: initial population from the user's persistent folder
    observeEvent(TRUE, {
      refresh_from_user_folder()
    }, once = TRUE)

    if (is.null(session$userData$temp_files)) session$userData$temp_files <- list()

    bulk_files_to_process <- reactiveVal(NULL)
    file_removed          <- reactiveVal(NULL)
    all_files_cleared     <- reactiveVal(FALSE)

    message_trigger <- reactiveVal(0)
    message_data    <- reactiveVal(NULL)

    # ---- INITIAL LOAD FROM PERSISTED FOLDER ----
    observeEvent(TRUE, {
      uid <- isolate(session$userData$user_id %||% NULL)
      if (is.null(uid)) return()
    
      existing <- try(mergen_list_user_files(uid), silent = TRUE)
      if (inherits(existing, "try-error") || nrow(existing) == 0) return()
    
      for (i in seq_len(nrow(existing))) {
        finfo <- list(
          name     = existing$name[i],
          datapath = existing$path[i],
          size     = suppressWarnings(file.info(existing$path[i])$size),
          type     = mime::guess_type(existing$path[i]) %||% ""
        )
        # generate_message = FALSE to avoid flooding the chat
        process_uploaded_file(finfo, generate_message = FALSE)
      }
    }, once = TRUE, ignoreInit = TRUE)

    files_added_to_context <- reactiveVal(NULL)   # -> parent

    # ---------- HELPERS ----------
    format_timestamp <- function() format(Sys.time(), "%Y-%m-%d %H:%M")

    update_session_files <- function(update_fn) {
      if (is.null(session_files_reactive)) return(invisible())
      try({
        cur <- session_files_reactive()
        session_files_reactive(update_fn(cur))
      }, silent = TRUE)
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
    
      # Drop from module state
      module_values$file_contents[[fid]] <- NULL
    
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
      file_name <- as.character(file_info$name %||% "")
      file_size <- suppressWarnings(as.numeric(file_info$size %||% NA_real_))
      in_path   <- as.character(file_info$datapath %||% file_info$path %||% "")

      if (!nzchar(file_name) || !nzchar(in_path) || !path_exists_relaxed(in_path)) {
        showToast(session, "Yüklenen dosya yolu okunamadı.", "error")
        return(NULL)
      }
	  
      allowed_extensions <- c("txt","pdf","docx","xlsx","xls","csv","json","r","py","md","log","xml","html")
      file_ext <- tolower(tools::file_ext(file_name))
      if (!file_ext %in% allowed_extensions) {
        showToast(session, sprintf("'%s' dosya türü desteklenmiyor!", file_ext), "error")
        return(NULL)
      }

      file_id <- paste0("file_", floor(as.numeric(Sys.time()) * 1000000), "_", sample(100000:999999, 1))
      stable_path <- in_path

      if (!is.finite(file_size) || is.na(file_size)) {
        file_size <- suppressWarnings(as.numeric(file.info(stable_path)$size))
      }
	  
      saved <- list(
        name     = file_name,
        datapath = stable_path,
        size     = file_size,
        type     = file_info$type %||% "",
        id       = file_id,
        persisted_path = stable_path
      )
	  
      module_values$file_contents[[file_id]] <- saved
      session$userData$temp_files[[file_id]] <- NULL  # no temp we own here
    
      hidden_dl <- as.character(
        tags$span(
          style = "display:none;",
          shiny::downloadLink(outputId = ns(paste0("download_", file_id)), label = "")
        )
      )
    
		actions <- as.character(tags$div(
		  class = "file-actions",
		  tags$button(class = "file-action-btn file-view js-file-action",
					  title = "Görüntüle", `data-action` = "view", `data-file-id` = file_id, icon("eye")),
		  tags$button(class = "file-action-btn file-download js-download-btn",
					  title = "İndir", `data-download-id` = file_id, icon("download")),
		  tags$button(class = "file-action-btn file-delete js-file-action",
					  title = "Sil", `data-action` = "delete", `data-file-id` = file_id, icon("trash")),
		  HTML(hidden_dl)
		))
		
		attach_cell <- as.character(tags$div(
		  class = "attach-cell",
		  tags$input(
			id = ns(paste0("attach_", file_id)),
			type = "checkbox",
			class = "attach-checkbox",
			`data-file-id` = file_id,
			`data-filename` = file_name,
			title = "Bu dosyayı model bağlamına ekle/çıkar",
			`aria-label` = "Model bağlamına ekle veya çıkar"
		  )
		))

		# Uzantıyı küçük harfe çevir (ikon eşlemesi için)
		ext <- tolower(tools::file_ext(file_name))

		module_values$files <- rbind(
		  module_values$files,
		  data.frame(
			Dosya_Adi       = file_name,
			Boyut           = paste(round((file_size %||% 0) / 1024, 2), "KB"),
			# Tür sütunu: ikon + etiket
			Tur             = ext_icon_html(ext),
			Yuklenme_Tarihi = format_timestamp(),
			Islemler        = actions,
			Model_Baglam    = attach_cell,
			stringsAsFactors = FALSE
		  )
		)
    
      if (isTRUE(generate_message)) {
		html_message <- sprintf(
		  "📎 <b>%s</b> yüklendi. Yapay zekâya eklemek için <i>Model Bağlamı</i> sütunundaki kutucuğu işaretleyin. Önizlemek için <a href='#' class='file-link js-file-action' data-action='view' data-file-id='%s'>tıklayın</a>.",
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
            content  = function(file) file.copy(module_values$file_contents[[my_id]]$datapath, file, overwrite = TRUE),
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
          withProgress(message = 'Dosyalar yükleniyor...', value = 0, {
            for (i in seq_len(nrow(new_df))) {
              incProgress(1 / nrow(new_df), detail = new_df$name[i])
              result <- process_uploaded_file(new_df[i, , drop = FALSE], generate_message = FALSE)
              # Only add to saved_infos if result is not NULL (valid file)
              if (!is.null(result)) {
                saved_infos[[length(saved_infos) + 1]] <- result
              }
            }
          })
          
          # Only show success message if at least one file was successfully uploaded
          if (length(saved_infos) > 0) {
            message_data(list(
              content = sprintf("%d dosya yüklendi.", length(saved_infos)),
              html    = sprintf("📎 <b>%d dosya</b> yüklendi ve sohbete eklendi.", length(saved_infos)),
              type    = "system"
            ))
            message_trigger(message_trigger() + 1)
            showToast(session, paste(length(saved_infos), "dosya başarıyla yüklendi!"), "success")
  
            # hand off to parent (stable paths) → summarizer
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
    
      # 1) Try to delete the persisted copy under mergen_uploads/user_<id>
      uid <- isolate(session$userData$user_id %||% NULL)
      persisted <- try(resolve_uploaded_file(info$name, uid), silent = TRUE)
      if (!inherits(persisted, "try-error") && !is.null(persisted) && path_exists_relaxed(persisted)) {
        try(unlink(persisted, force = TRUE), silent = TRUE)
      }
      # Remove from index
      if (!is.null(uid)) try(mergen_remove_from_index(uid, info$name), silent = TRUE)
    
      # 2) Also drop any local temp we might have created (we no longer create one, but keep for safety)
      if (!is.null(session$userData$temp_files[[file_id]])) {
        try(unlink(session$userData$temp_files[[file_id]]), silent = TRUE)
        session$userData$temp_files[[file_id]] <- NULL
      }
    
      # 3) Clean module state / table row
      file_removed(info)  # -> parent observers
      module_values$file_contents[[file_id]] <- NULL
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
      uid <- isolate(session$userData$user_id %||% NULL)
      if (!is.null(uid)) try(mergen_clear_user_bucket(uid), silent = TRUE)
    
      # 2) Notify parent that all files are gone
      for (file_id in names(module_values$file_contents)) file_removed(module_values$file_contents[[file_id]])
    
      # 3) Clean module state and UI
      for (p in session$userData$temp_files) try(unlink(p), silent = TRUE)
      module_values$files <- module_values$files[0, ]
      module_values$file_contents <- list()
      module_values$files_in_context <- list()
      session$userData$temp_files <- list()
    
      all_files_cleared(TRUE)
      showToast(session, "Tüm dosyalar (diskten de) temizlendi.", "warning")
      session$sendCustomMessage('resetBulkUploadCaption', list())
      message_data(list(type = "system", content = "Tüm dosyalar kalıcı klasörden silindi.", html = NULL))
      message_trigger(message_trigger() + 1)
      shinyjs::delay(100, { all_files_cleared(FALSE) })
    }, ignoreInit = TRUE)
                   
	output$files_table <- DT::renderDataTable({
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
	  message_trigger          = reactive({ message_trigger() }),
	  get_message              = reactive({ message_data() }),
	  file_contents            = reactive({ module_values$file_contents }),
	  file_removed             = reactive({ file_removed() }),
	  all_files_cleared        = reactive({ all_files_cleared() }),
	  files_added_to_context   = reactive({ files_added_to_context() }),
	  remove_file_from_manager = function(filename) { remove_file_by_name(filename, quiet = TRUE) },
	  set_attachment_checked   = set_attachment_checked
	)
  })
}