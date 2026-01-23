# R/module_file_context_handlers.R
# AI bağlamına dosya ekleme/çıkarma olaylarını yöneten modül

#' Dosya Bağlamı Olay İşleyicileri
#'
#' @description
#' Bu modül, kullanıcının dosya yöneticisinden AI bağlamına dosya eklemesi
#' veya çıkarmasını yönetir. Ayrıca kaynak dosya tıklamalarını da işler.
#'
#' @param id Modül ad alanı kimliği
#' @param input Shiny input objesi
#' @param session Shiny session objesi
#' @param settings_data Ayarlar modülünden gelen reaktif değerler
#' @param session_files AI bağlamındaki dosyaları tutan reactiveVal
#' @param file_manager_data Dosya yöneticisi modülünden dönen değerler
#' @param current_user_id Mevcut kullanıcı kimliği
#' @param filePreview Dosya önizleme modülü objesi
#' @param api_config API yapılandırma objesi
#' @param last_source_click Kaynak tıklama debounce için reactiveVal
#'
#' @return NULL
#'
#' @export
fileContextHandlersServer <- function(id = "file_context_handlers",
                                       input,
                                       session,
                                       settings_data,
                                       session_files,
                                       file_manager_data,
                                       current_user_id,
                                       filePreview,
                                       api_config,
                                       last_source_click) {
  
  # Not: Bu modül moduleServer kullanmıyor çünkü input/session'ı doğrudan dinliyor
  # Namespace'e ihtiyacı yok
  
  # MCP araçları açıkken sadece 1 dosya eklenebilir
  observeEvent(settings_data$enable_mcp_tools, {
    if (isTRUE(settings_data$enable_mcp_tools)) {
      # Birden fazla dosya ekliyse, ilkini tut, diğerlerini kaldır
      cur <- names(session_files())
      if (length(cur) > 1) {
        keep <- cur[1]
        to_uncheck <- cur[-1]
        sf <- session_files()
        for (nm in to_uncheck) sf[[nm]] <- NULL
        session_files(sf)
        # Dosya Yöneticisi checkbox'larına yansıt
        if (!is.null(file_manager_data$set_attachment_checked)) {
          lapply(to_uncheck, function(nm) file_manager_data$set_attachment_checked(nm, FALSE))
        }
        showToast(session, "MCP açıkken yalnızca 1 dosya eklenebilir. Fazla seçimler kaldırıldı.", "warning")
      }
    }
  })
  
  # Belirli bir dosyayı AI bağlamından kaldır
  observeEvent(input$remove_file_from_prompt, {
    filename_to_remove <- input$remove_file_from_prompt$name
    req(filename_to_remove)
    
    # 1) AI bağlamından kaldır
    current_files <- session_files()
    current_files[[filename_to_remove]] <- NULL
    session_files(current_files)
    
    # 2) Dosya Yöneticisinde sadece işareti kaldır (satırı silme)
    if (!is.null(file_manager_data$set_attachment_checked)) {
      file_manager_data$set_attachment_checked(filename_to_remove, FALSE)
    }
    
    showToast(session, paste("Dosya AI bağlamından kaldırıldı:", filename_to_remove), "info")
  })
  
  # Kaynakça'dan dosya tıklamalarını işle
  observeEvent(input$source_file_clicked, {
    req(input$source_file_clicked)
    
    # Normalize + debounce
    ev <- input$source_file_clicked
    raw_name <- if (is.character(ev)) ev[1] else (ev$filename %||% ev$name %||% "")
    raw_name <- as.character(raw_name %||% "")
    raw_name <- sub("^\\s*\\d+\\)\\s*", "", raw_name)  # numaralı önekleri temizle
    
    # Çift tıklama yutma (500ms) — tam ipucu bazlı
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
    
    # Günlük: tıklanan kaynak
    log_info("[SRC_CLICK] tıklanan kaynak: '{raw_name}'")
    
    # Tüm çözümleme/önizleme işini tek bir yerde topla
    handle_source_file_click(ev, settings_data, api_config, session, filePreview)
  }, ignoreInit = TRUE)
  
  # Analiz dosyası tıklamalarını işle
  observeEvent(input$analysis_file_clicked, {
    req(input$analysis_file_clicked)
    
    filepath_raw <- input$analysis_file_clicked$filepath
    if (is.null(filepath_raw) || !nzchar(filepath_raw)) {
      showToast(session, "Geçersiz dosya yolu.", "error")
      return(invisible(NULL))
    }
    
    filepath_clean <- trimws(as.character(filepath_raw))
    
    full_path <- NULL
    if (startsWith(filepath_clean, "www/")) {
      full_path <- file.path(getwd(), filepath_clean)
    } else if (startsWith(filepath_clean, "/") || grepl("^[A-Za-z]:", filepath_clean)) {
      full_path <- filepath_clean
    } else {
      full_path <- file.path(getwd(), "www", filepath_clean)
    }
    
    full_path <- normalize_mcp_path(full_path, must_exist = FALSE)
    
    if (!path_exists_relaxed(full_path)) {
      showToast(session, paste("Dosya bulunamadı:", basename(filepath_clean)), "error")
      log_error("[ANALYSIS_FILE] Dosya mevcut değil: {full_path}")
      return(invisible(NULL))
    }
    
    file_info <- list(
      name = basename(full_path),
      datapath = full_path,
      size = suppressWarnings(file.info(full_path)$size)
    )
    
    log_info("[ANALYSIS_FILE] Önizleme açılıyor: {full_path}")
    openAnyPreview(file_info, session, filePreview)
    
  }, ignoreInit = TRUE)
  
  # Dosya yöneticisinden dosya kaldırılmasını izle
  observeEvent(file_manager_data$file_removed(), {
    removed_file <- file_manager_data$file_removed()
    if (!is.null(removed_file)) {
      current_files <- session_files()
      if (!is.null(removed_file$name) && removed_file$name %in% names(current_files)) {
        current_files[[removed_file$name]] <- NULL
        session_files(current_files)
        showToast(session, paste("Dosya AI bağlamından kaldırıldı:", removed_file$name), "info")
        
        session$userData$file_summaries[[removed_file$name]] <- NULL
      }
    }
  }, ignoreInit = TRUE)
  
  # Tüm dosyaların temizlenmesini izle
  observeEvent(file_manager_data$all_files_cleared(), {
    if (isTRUE(file_manager_data$all_files_cleared())) {
      # Tüm dosyaları session'dan temizle
      session_files(list())
      session$userData$file_summaries <- list()
      showToast(session, "Tüm dosyalar AI bağlamından temizlendi.", "warning")
    }
  }, ignoreInit = TRUE)
  
  # Dosya yöneticisi üzerinden eklenen dosyaları işle
  observeEvent(file_manager_data$files_added_to_context(), {
    files_to_add <- file_manager_data$files_added_to_context()
    req(files_to_add)
    
    processed_count <- 0
    for (file_info in files_to_add) {
      if (!(file_info$name %in% names(session_files()))) {
        processAndSummarizeFile(
          file_info,
          current_user_id = current_user_id,
          session = session,
          settings = settings_data,
          file_manager_data = file_manager_data,
          session_files_reactive = session_files,
          update_manager_ui = FALSE,
          show_toast = FALSE,
          auto_attach = FALSE
        )
        processed_count <- processed_count + 1
      }
    }
    
    if (processed_count > 0) {
      showToast(session, paste(processed_count, "dosya AI bağlamına eklendi."), "success")
    }
  }, ignoreInit = TRUE)
  
  return(invisible(NULL))
}