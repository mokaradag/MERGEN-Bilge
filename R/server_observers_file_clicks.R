# R/server_observers_file_clicks.R
# Dosya Yolu: R/server_observers_file_clicks.R
# Açıklama: Kaynak dosya tıklamaları, analiz dosyası tıklamaları ve
# dosya yöneticisi bağlantı observer'ları.
# Kaynakça linkleri, analiz çıktı dosyaları ve sohbet içi dosya önizlemeleri burada işlenir.

#' Dosya Tıklama Gözlemcilerini Başlat
#' @description Kaynak ve analiz dosyası tıklama observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param api_config API yapılandırma listesi
#' @param filePreview Dosya önizleme modülü
#' @param file_manager_data Dosya yöneticisi modül verisi
#' @param session_files Oturum dosyaları reaktif değeri
fileClickObserversInit <- function(input, session, settings_data, api_config,
                                    filePreview, file_manager_data, session_files) {
  
  last_source_click <- reactiveVal(list(name = NULL, t = 0))
  
  observeEvent(input$source_file_clicked, {
    req(input$source_file_clicked)
    
    ev <- input$source_file_clicked
    raw_name <- if (is.character(ev)) ev[1] else (ev$filename %||% ev$name %||% "")
    raw_name <- as.character(raw_name %||% "")
    raw_name <- sub("^\\s*\\d+\\)\\s*", "", raw_name)
    
    now  <- as.numeric(Sys.time())
    last <- last_source_click()
    if (is.list(last) && identical(last$name, raw_name) && (now - (last$t %||% 0)) < 0.5) {
      return(invisible(NULL))
    }
    last_source_click(list(name = raw_name, t = now))
    
    if (!nzchar(raw_name)) {
      showToast(session, "Geçersiz kaynak bağlantısı: dosya adı yok.", "error")
      return(invisible(NULL))
    }
    
    log_info("[SRC_CLICK] tıklanan kaynak: '{raw_name}'")
    
    handle_source_file_click(ev, settings_data, api_config, session, filePreview)
  }, ignoreInit = TRUE)
  
  observeEvent(input$analysis_file_clicked, {
    req(input$analysis_file_clicked)
    
    filepath_raw <- input$analysis_file_clicked$filepath
    if (is.null(filepath_raw) || !nzchar(filepath_raw)) {
      showToast(session, "Geçersiz dosya yolu.", "error")
      return(invisible(NULL))
    }
    
	filepath_clean <- trimws(as.character(filepath_raw))

	repo_root_for_files <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
	repo_candidates <- unique(Filter(nzchar, c(
	  repo_root_for_files,
	  tryCatch(as.character(get0("repo_root", envir = globalenv(), inherits = TRUE) %||% "")[1],
			   error = function(e) ""),
	  getwd(),
	  file.path(getwd(), ".."),
	  file.path(getwd(), "../..")
	)))

	repo_root_for_files <- getwd()
	for (cand in repo_candidates) {
	  cand_norm <- tryCatch(normalizePath(cand, winslash = "/", mustWork = FALSE),
							error = function(e) cand)
	  if (file.exists(file.path(cand_norm, "app.R")) &&
		  dir.exists(file.path(cand_norm, "www"))) {
		repo_root_for_files <- cand_norm
		break
	  }
	}

	full_path <- NULL
	if (startsWith(filepath_clean, "www/")) {
	  full_path <- file.path(repo_root_for_files, filepath_clean)
	} else if (startsWith(filepath_clean, "/") ||
			   grepl("^//", filepath_clean) ||
			   grepl("^[A-Za-z]:", filepath_clean)) {
	  full_path <- filepath_clean
	} else {
	  full_path <- file.path(repo_root_for_files, "www", filepath_clean)
	}
    
    full_path <- normalize_mcp_path(full_path, must_exist = FALSE)
    
	if (!path_exists_relaxed(full_path)) {
	  showToast(session, paste("Dosya bulunamadı:", basename(filepath_clean)), "error")
	  log_error("[ANALYSIS_FILE] Dosya mevcut değil: {full_path}", full_path = full_path)
	  return(invisible(NULL))
	}
    
    file_info <- list(
      name = basename(full_path),
      datapath = full_path,
      size = suppressWarnings(file.info(full_path)$size)
    )
    
    log_info("[ANALYSIS_FILE] Önizleme açılıyor: {full_path}", full_path = full_path)
    openAnyPreview(file_info, session, filePreview)
    
  }, ignoreInit = TRUE)
  
  observeEvent(input$view_file_from_chat, {
    req(input$view_file_from_chat)
    file_id <- input$view_file_from_chat
    
    if (exists("file_store") && !is.null(file_store[[file_id]])) {
      file_info <- file_store[[file_id]]
      filePreview$open(file_info)
    } else {
      showToast(session, "Dosya bulunamadı.", "error")
    }
  }, ignoreInit = TRUE)
  
  observeEvent(file_manager_data$file_removed(), {
    removed_file <- file_manager_data$file_removed()
    if (!is.null(removed_file)) {
      current_files <- session_files()
      if (!is.null(removed_file$name) && removed_file$name %in% names(current_files)) {
        current_files[[removed_file$name]] <- NULL
        session_files(current_files)
        showToast(session, paste("Dosya AI bağlamından kaldırıldı:", removed_file$name), "info")
        
        session_user_data_remove_list_item(
          session,
          "file_summaries",
          removed_file$name
        )
      }
    }
  }, ignoreInit = TRUE)
  
  observeEvent(file_manager_data$all_files_cleared(), {
    if (isTRUE(file_manager_data$all_files_cleared())) {
      session_files(list())
      session_user_data_set_list(session, "file_summaries", list())
      showToast(session, "Tüm dosyalar AI bağlamından temizlendi.", "info")
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}