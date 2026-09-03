# R/module_file_manager.R

fileManagerServer <- function(
  id,
  new_file_trigger = reactive(NULL),
  session_files_reactive = NULL,
  mcp_enabled_reactive = reactive({ FALSE }),
  user_id = NULL,
  settings_data = NULL,
  auth_ready_provider = NULL,
  boot_ready = NULL
) {
moduleServer(id, function(input, output, session) {
  ns <- session$ns

  get_module_values <- function() module_values

  runtime_helpers <- fm_create_server_runtime_helpers(
    session = session,
    user_id = user_id,
    settings_data = settings_data,
    session_files_reactive = session_files_reactive,
    mcp_enabled_reactive = mcp_enabled_reactive,
    ns = ns,
    module_values_provider = get_module_values,
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
			  module_values$files_in_context[[fid]] <- NULL
			  detach_in_parent(info$name %||% fname)

			  showToast(session, 
						sprintf("Dosya Özetleme modunda sadece şu formatlar desteklenir: %s.",
								paste(toupper(summarization_allowed), collapse = ", ")),
						"warning")
			  session$sendCustomMessage(ns("setAttachState"), list(ids = fid, checked = FALSE))
			  return()
			}
		}
		
		# MCP ON? allow only one AND check extension
		if (isTRUE(mcp_enabled_reactive())) {
		  
		  # Türkçe: Uzantı kontrolü - Sadece Excel
		  ext <- tolower(tools::file_ext(fname))
			if (!ext %in% c("xls", "xlsx")) {
			  module_values$files_in_context[[fid]] <- NULL
			  detach_in_parent(info$name %||% fname)

			  showToast(session, "MCP: Excel modunda sadece Excel dosyaları (.xls, .xlsx) seçilebilir.", "warning")
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

  refresh_from_user_folder <- fm_create_refresh_from_user_folder(
    session = session,
    ns = ns,
    module_values_provider = get_module_values,
    module_user_id_chr = module_user_id_chr,
    is_auth_ready = is_auth_ready,
    ensure_session_registry = ensure_session_registry,
    attach_in_parent = attach_in_parent,
    process_uploaded_file_callback = function(finfo) {
      process_uploaded_file(finfo, generate_message = FALSE)
    },
    refresh_guard = refresh_guard,
    fm_debug = fm_debug
  )

    # ---------- STATE ----------
    module_values <- reactiveValues(
      files = fm_empty_files_df(),
      file_contents = list(),
      file_id_to_delete = NULL,
      files_in_context = list()
    )

    # Kalıcı dosya envanteri TEMBEL yüklenir: açılışta dosya sistemi/indeks taranmaz
    # (soğuk açılış kritik yolu bloklanmaz). Tarama, Dosya Yönetimi ilk açıldığında
    # (page_opened) veya manuel/araç tetiklerinde yapılır.
    persisted_scan_pending <- reactiveVal(TRUE)

    observeEvent(TRUE, {
      # Yerel modda boot kontrol noktası dürüst "deferred" ayrıntısıyla işaretlenir;
      # SSO modunda aynı işaretleme refresh_persisted_files("auth_ready") ile yapılır.
      if (isTRUE(SSO_ENABLED) && !is_auth_ready()) return()
      if (!is.null(boot_ready) && is.function(boot_ready$mark)) boot_ready$mark("file_index_ready", label = "Dosyalar gerektiğinde yüklenecek", detail = list(deferred = TRUE))
    }, once = TRUE, ignoreNULL = TRUE)

    observeEvent(input$page_opened, {
      if (!isTRUE(persisted_scan_pending()) || (isTRUE(SSO_ENABLED) && !is_auth_ready())) return()
      persisted_scan_pending(FALSE)
      fm_baslat_sayfa_acilis_taramasi(session, refresh_from_user_folder)
    }, ignoreInit = TRUE)

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

    # ---------- HELPERS ----------
    file_action_helpers <- fm_create_file_action_helpers(
      session = session,
      ns = ns,
      module_values_provider = get_module_values,
      get_summarization_mode = get_summarization_mode,
      resolve_allowed_extensions = resolve_allowed_extensions,
      show_unsupported_extension_toast = show_unsupported_extension_toast,
      register_session_file = register_session_file,
      unregister_session_file = unregister_session_file,
      detach_in_parent = detach_in_parent,
      message_data = message_data,
      message_trigger = message_trigger,
      fm_debug = fm_debug
    )

    sync_file_to_context <- file_action_helpers$sync_file_to_context
    append_uploaded_file_row <- file_action_helpers$append_uploaded_file_row
    remove_file_by_name <- file_action_helpers$remove_file_by_name
    process_uploaded_file <- file_action_helpers$process_uploaded_file

    # Toplu yükleme arka planda çalıştığı için oturum/iptal koruması gerekir:
    # kapanan oturumda UI'ya dokunulmaz, "Tümünü Temizle" sonrası uçuştaki
    # partinin kopyaladığı dosyalar temizlenir ve indekse yazılmaz.
    upload_runtime <- fm_create_upload_runtime(
      session = session,
      process_uploaded_file = process_uploaded_file,
      message_data = message_data,
      message_trigger = message_trigger,
      files_added_to_context = files_added_to_context,
      fm_debug = fm_debug
    )

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
      uid <- module_user_id_chr()

      # Doğrulama/kopyalama/bütünlük denetimi arka plana gider; observer anında
      # döner ve olay döngüsü serbest kalır. Tablo satırları ve bildirimler
      # commit geri çağrısında ana süreçte üretilir.
      fm_dispatch_bulk_upload_batch(
        files_df = files_df,
        existing_names = existing_names,
        session = session,
        uid = uid,
        is_auth_ready = is_auth_ready,
        controller = upload_runtime$controller,
        commit_ctx = upload_runtime$commit_ctx,
        fm_debug = fm_debug
      )

      shinyjs::delay(100, session$sendCustomMessage('resetBulkUploadCaption', list()))
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
    
	  # 1) Fiziksel dosyayı ve kalıcı indeks kaydını helper üzerinden temizle.
      uid <- isolate(module_user_id_chr())
      fm_delete_persisted_file_artifacts(
        info = info,
        uid = uid,
        get_user_upload_dir = get_user_upload_dir,
        fm_debug = fm_debug
      )
    
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

    # Yenile butonu: dosya tablosunu kalıcı kullanıcı klasöründen yeniden yükler.
    # Mevcut refresh_from_user_folder mekanizmasını kullanır (yeni yardımcı eklemez).
    observeEvent(input$refresh_files, {
      refresh_from_user_folder("manual")
      persisted_scan_pending(FALSE)
      showToast(session, "Dosya listesi yenilendi.", "info")
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

      # 0) Uçuştaki toplu yükleme partisi bu temizliği ezmesin: kopyaları
      # temizlenir, indekse yazılmaz ve tabloya satır eklemez.
      file_ingestion_cancel_controller(upload_runtime$controller)

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
                   
    fm_register_file_manager_table_runtime(
      session = session,
      output = output,
      ns = ns,
      module_values_provider = get_module_values
    )

    session$onSessionEnded(function() {
      tf <- session$userData$temp_files
      if (is.null(tf)) return()
      for (temp_path in tf) try(unlink(temp_path), silent = TRUE)
      session$userData$temp_files <- list()
    })
	
    set_attachment_checked <- fm_create_file_manager_attachment_setter(
      session = session,
      ns = ns,
      module_values_provider = get_module_values,
      attach_in_parent = attach_in_parent,
      detach_in_parent = detach_in_parent
    )

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
		  # Açılış tetikleri (initial/auth_ready/startup) tarama YAPMAZ: envanter
		  # ertelenir, kontrol noktası "deferred" işaretlenir. Diğerleri gerçek taramadır.
		  if (trigger %in% c("initial", "auth_ready", "startup")) {
		    if (!is.null(boot_ready) && is.function(boot_ready$mark)) boot_ready$mark("file_index_ready", label = "Dosyalar gerektiğinde yüklenecek", detail = list(deferred = TRUE))
		    return(invisible(TRUE))
		  }
		  refresh_from_user_folder(trigger)
		  persisted_scan_pending(FALSE)
		  invisible(TRUE)
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