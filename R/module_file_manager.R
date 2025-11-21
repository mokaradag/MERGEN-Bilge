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
    # JS to translate progress bar text and apply success class
    tags$script(HTML("
      $(document).ready(function() {
        var observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            if (mutation.type === 'childList' || mutation.type === 'characterData') {
              var $bar = $(mutation.target).closest('.progress-bar');
              if ($bar.length && $bar.text().indexOf('Upload complete') > -1) {
                $bar.text('Yükleme tamamlandı');
                $bar.addClass('upload-complete-success');
              }
            }
          });
        });
        var target = document.getElementById('bulk_upload_div');
        if (target) {
          observer.observe(target, { childList: true, subtree: true, characterData: true });
        }
      });
    ")),
    div(
      class = "content-container",
      style = "padding-right: 20px;",
      # Header matching "Ayarlar" page style
      div(
        class = "files-header",
        h3("Toplu Dosya Yükleme", class = "page-title"),
        actionButton(
          ns("clear_files"),
          label = tagList(icon("trash-alt"), "Tümünü Temizle"),
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
                buttonLabel = tagList(icon("folder-open"), "Göz At"),
                placeholder = "Henüz dosya seçilmedi",
                accept = c(".txt", ".pdf", ".docx", ".xlsx", ".xls", ".csv", ".json", ".R", ".r", ".py", ".md", ".log", ".xml", ".html")
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
			"Seçim kuralı: MCP açıkken yalnızca 1 dosya eklenebilir; kapalıyken birden fazla seçim yapabilirsiniz."
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
  mcp_enabled_reactive = reactive({ FALSE }),
  user_id = NULL
) {
  moduleServer(id, function(input, output, session) {
  ns <- session$ns

    module_user_id <- user_id %||% session$userData$user_id %||% "unknown"
    module_user_id_chr <- as.character(module_user_id %||% "unknown")

    fm_debug <- function(event, ...) {
      parts <- vapply(list(...), function(x) {
        if (length(x) == 0) return("")
        paste(as.character(x), collapse = " ")
      }, character(1))
      msg <- trimws(paste(parts, collapse = " "))
      cat(sprintf("[FILE_MANAGER][user:%s][%s] %s\n",
                  module_user_id_chr %||% "unknown",
                  event %||% "event",
                  if (nzchar(msg)) msg else "(no details)"))
    }

    fm_debug("init", sprintf("module booting (ns=%s)", ns("")))

    ensure_session_registry <- function() {
      if (is.null(session$userData$current_session_files) ||
          !is.list(session$userData$current_session_files)) {
        session$userData$current_session_files <- list()
        fm_debug("ensure_registry", "session registry initialized")
      }
    }

    register_session_file <- function(filename, fpath) {
      ensure_session_registry()
      fname <- as.character(filename %||% "")
		if (!nzchar(fname)) return(invisible(FALSE))
			  
			  # CHANGE: Trust existing paths to avoid UNC duplication errors
			  norm_path <- if (path_exists_relaxed(fpath)) {
				as.character(fpath)
			  } else {
				tryCatch(
				  normalize_mcp_path(fpath, must_exist = FALSE),
				  error = function(e) as.character(fpath %||% "")
				)
			  }
			if (!nzchar(norm_path)) return(invisible(FALSE))
	
      session$userData$current_session_files[[fname]] <- list(
        name = fname,
        datapath = norm_path,
        path = norm_path,
        persisted_path = norm_path
      )
      fm_debug("register", sprintf("%s -> %s", fname, norm_path))
      invisible(TRUE)
    }

    unregister_session_file <- function(filename) {
      ensure_session_registry()
      fname <- as.character(filename %||% "")
      if (!nzchar(fname)) return(invisible(FALSE))
      session$userData$current_session_files[[fname]] <- NULL
      invisible(TRUE)
    }
  
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

	# Update parent session_files using the bridge we were given
	attach_in_parent <- function(file_obj) {
	  if (is.null(session_files_reactive)) return(invisible())
	  update_session_files(function(cur) {
			cur <- cur %||% list()
			# Minimal payload is OK for Ekli Dosyalar badge; summary will arrive later
			cur[[file_obj$name]] <- cur[[file_obj$name]] %||% list(name = file_obj$name)
			cur
	  })
	  fm_debug("attach", sprintf("added %s to session context", file_obj$name))
	}

	detach_in_parent <- function(file_name) {
	  if (is.null(session_files_reactive)) return(invisible())
	  update_session_files(function(cur) {
			cur <- cur %||% list()
			cur[[file_name]] <- NULL
			cur
	  })
	  fm_debug("detach", sprintf("removed %s from session context", file_name))
	}
	
	# MCP ayarı değiştiğinde (Örn: Excel modu açıldığında) mevcut seçimleri doğrula
    observeEvent(mcp_enabled_reactive(), {
      if (isTRUE(mcp_enabled_reactive())) {
        # 1. Mevcut seçili dosyaları kontrol et
        attached_ids <- names(module_values$files_in_context)
        removed_any <- FALSE
        
        for (fid in attached_ids) {
           info <- module_values$file_contents[[fid]]
           if (is.null(info)) next
           
           ext <- tolower(tools::file_ext(info$name))
           # Excel değilse kaldır
           if (!ext %in% c("xls", "xlsx")) {
              module_values$files_in_context[[fid]] <- NULL
              detach_in_parent(info$name)
              # Arayüzdeki tiki kaldır
              session$sendCustomMessage(ns("setAttachState"), list(ids = fid, checked = FALSE))
              removed_any <- TRUE
           }
        }
        
        if (removed_any) {
           showToast(session, "MCP Excel modu açıldığı için uyumsuz dosyalar seçimden kaldırıldı.", "warning")
        }
        
        # 2. Eğer birden fazla Excel dosyası seçiliyse, sadece birini bırak (MCP kuralı)
        remaining <- names(module_values$files_in_context)
        if (length(remaining) > 1) {
           # İlkini tut, diğerlerini kaldır
           to_remove <- remaining[-1]
           for (fid in to_remove) {
              module_values$files_in_context[[fid]] <- NULL
              info <- module_values$file_contents[[fid]]
              detach_in_parent(info$name)
              session$sendCustomMessage(ns("setAttachState"), list(ids = fid, checked = FALSE))
           }
           showToast(session, "MCP Excel modu tek dosya destekler. Fazla seçimler kaldırıldı.", "warning")
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

	if (checked) {
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

	  } else {
			# Unselect
			module_values$files_in_context[[fid]] <- NULL
			detach_in_parent(fname)
			fm_debug("checkbox", sprintf("%s (id=%s) unchecked", fname, fid))
	  }

	  # Update the hint text dynamically
	  txt <- if (isTRUE(mcp_enabled_reactive())) {
			"Seçim kuralı: MCP açıkken yalnızca 1 dosya eklenebilir."
	  } else {
			"Seçim kuralı: MCP kapalıyken birden fazla dosya seçebilirsiniz."
	  }
	  shinyjs::html(id = "attach_rule_hint", html = txt, add = FALSE)
	}, ignoreInit = TRUE)

	observe({
	  txt <- if (isTRUE(mcp_enabled_reactive())) {
			"Seçim kuralı: MCP açıkken yalnızca 1 dosya eklenebilir."
	  } else {
			"Seçim kuralı: MCP kapalıyken birden fazla dosya seçebilirsiniz."
	  }
	  shinyjs::html(id = "attach_rule_hint", html = txt, add = FALSE)
	})
  
  # --- NEW: persistent storage helpers -----------------------------------------
  get_user_upload_dir <- function() {
    base <- getOption(
      "mergen.mcp_base_dir",
      Sys.getenv("MCP_FILES_BASE",
                 normalizePath(file.path(getwd(), "mergen_uploads"),
                               winslash = "/", mustWork = FALSE))
    )
    file.path(base, sprintf("user_%s", module_user_id_chr))
  }
  
  is_under_mcp_base <- function(p) {
    if (is.null(p) || !nzchar(p)) return(FALSE)
    base <- getOption("mergen.mcp_base_dir", Sys.getenv("MCP_FILES_BASE", ""))
    if (!nzchar(base)) return(FALSE)
    np <- tryCatch(normalizePath(p, winslash = "/", mustWork = FALSE), error = function(e) p)
    nb <- tryCatch(normalizePath(base, winslash = "/", mustWork = FALSE), error = function(e) base)
    startsWith(tolower(np), tolower(paste0(nb, "/"))) || identical(tolower(np), tolower(nb))
  }
    
  list_user_folder_files <- function() {
    udir <- get_user_upload_dir()
    if (!dir.exists(udir)) return(character(0))
    list.files(udir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE)
  }
  
	refresh_from_user_folder <- function(trigger = "manual") {
	  uid <- module_user_id_chr
	  fm_debug("refresh_start", sprintf("trigger=%s", trigger))
	  df <- try(mergen_list_user_files(uid), silent = TRUE)

	  module_values$files <- empty_files_df()
	  module_values$file_contents <- list()
	  module_values$files_in_context <- list()
	  ensure_session_registry()
	  session$userData$current_session_files <- list()

	  if (inherits(df, "try-error")) {
			cond <- attr(df, "condition")
			msg <- if (inherits(cond, "condition")) conditionMessage(cond) else as.character(df)
			fm_debug("refresh_error", msg)
			return(invisible(NULL))
	  }
	  
      source_tag <- attr(df, "source") %||% "unknown"

	  if (is.null(df) || nrow(df) == 0) {
		fm_debug("refresh_done", sprintf("no persisted files found (source=%s)", source_tag))
		return(invisible(NULL))
	  }

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
			
			# Windows UNC yolları (\\server\share) veritabanından tek slash (/server/share) olarak gelebilir.
            # Bu durumda R dosyayı bulamaz. Eğer dosya bu haliyle erişilemiyorsa, başına slash ekleyip (//server/share) 
            # UNC formatına çevirerek deniyoruz.
            
            # 1. Tüm ters slash'leri R standardı olan düz slash'e çevir
            p_fixed <- gsub("\\\\", "/", p)
            
            # 2. Eğer dosya bu haliyle doğrudan bulunamıyorsa onarmayı dene
            if (!file.exists(p_fixed) && !fs::file_exists(p_fixed)) {
              
              # 3. Eğer yol tek slash ile başlıyorsa (örn: /rehisds/...) ama çift slash değilse
              if (grepl("^/[^/]", p_fixed)) {
                 p_unc <- paste0("/", p_fixed) # Başına slash ekle -> //rehisds/...
                 # Eğer bu UNC varyasyonu diskte varsa, yolu güncelle
                 if (file.exists(p_unc) || fs::file_exists(p_unc)) {
                    p_fixed <- p_unc
                 }
              }
            }
            # 4. Onarılmış yolu ana değişkene ata
            p <- p_fixed

            # CHANGE: Robust size calculation that handles NA/errors gracefully
			f_size <- tryCatch({
               s <- fs::file_info(p)$size
               if (is.na(s)) stop("NA size")
               as.numeric(s)
            }, error = function(e) {
               s <- suppressWarnings(file.info(p)$size)
               if (is.na(s)) 0 else as.numeric(s)
            })

			finfo <- list(
			  name     = display_name,
			  datapath = p,
			  size     = f_size,
			  type     = mime::guess_type(p) %||% tools::file_ext(display_name)
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
	  
		fm_debug("refresh_done", sprintf("table rows=%d", nrow(module_values$files)))
	}

    # ---------- STATE ----------
	empty_files_df <- function() {
	  data.frame(
		Dosya_Adi = character(0),
		Boyut = character(0),
		Tur = character(0),
		Yuklenme_Tarihi = character(0),
		Islemler = character(0),
		Model_Baglam = character(0),   # NEW COLUMN (renders the checkbox)
		stringsAsFactors = FALSE
	  )
	}
		
    module_values <- reactiveValues(
      files = empty_files_df(),
      file_contents = list(),
      file_id_to_delete = NULL,
      files_in_context = list()
    )

    # --- NEW: initial population from the user's persistent folder
	observeEvent(TRUE, {
	  refresh_from_user_folder("initial")
	}, once = TRUE, ignoreNULL = TRUE)

    if (is.null(session$userData$temp_files)) session$userData$temp_files <- list()

    bulk_files_to_process <- reactiveVal(NULL)
	file_to_preview       <- reactiveVal(NULL)
    file_removed          <- reactiveVal(NULL)
    all_files_cleared     <- reactiveVal(FALSE)

    message_trigger <- reactiveVal(0)
    message_data    <- reactiveVal(NULL)

    files_added_to_context <- reactiveVal(NULL)   # -> parent

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
          norm_path <- tryCatch(normalizePath(persisted_path, winslash = "/", mustWork = FALSE),
                                error = function(e) persisted_path)
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
    
      # Validate type
      allowed_extensions <- c("txt","pdf","docx","xlsx","xls","csv","json","r","py","md","log","xml","html")
      file_ext <- tolower(tools::file_ext(file_name))
      if (!file_ext %in% allowed_extensions) {
        showToast(
          session,
          sprintf(
            "'%s' uzantılı dosya desteklenmiyor. Desteklenen türler: TXT, PDF, DOCX, XLSX, XLS, CSV, JSON, R, PY, MD, LOG, XML, HTML.",
            toupper(file_ext)
          ),
          "warning"
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
    
      # 1) Try to delete the persisted copy under mergen_uploads/user_<id>
      uid <- isolate(module_user_id_chr)
      persisted <- try(resolve_uploaded_file(info$name, uid), silent = TRUE)
      if (!inherits(persisted, "try-error") && !is.null(persisted) && file.exists(persisted)) {
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
      uid <- isolate(module_user_id_chr)
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
	  get_file_to_preview      = reactive({ file_to_preview() }),
	  message_trigger          = reactive({ message_trigger() }),
	  get_message              = reactive({ message_data() }),
	  file_contents            = reactive({ module_values$file_contents }),
	  file_removed             = reactive({ file_removed() }),
	  all_files_cleared        = reactive({ all_files_cleared() }),
	  files_added_to_context   = reactive({ files_added_to_context() }),
	  remove_file_from_manager = function(filename) { remove_file_by_name(filename, quiet = TRUE) },
	  set_attachment_checked   = set_attachment_checked,
	  sync_file_to_context     = sync_file_to_context
	)
  })
}