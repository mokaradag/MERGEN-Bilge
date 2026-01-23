# R/server_observers_files.R
# Dosya Yolu: R/server_observers_files.R
# Açıklama: Dosya yönetimi ile ilgili observer fonksiyonları.
# Dosya ekleme, çıkarma ve MCP dosya sınırlamaları bu dosyadadır.

#' Dosya Gözlemcilerini Başlat
#' @description Dosya yönetimi observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param session_files Oturum dosyaları reaktif değeri
#' @param file_manager_data Dosya yöneticisi modül verisi
#' @param current_user_id Mevcut kullanıcı ID'si
fileObserversInit <- function(input, session, settings_data, session_files, 
                               file_manager_data, current_user_id) {
  
  observeEvent(settings_data$enable_mcp_tools, {
    if (isTRUE(settings_data$enable_mcp_tools)) {
      cur <- names(session_files())
      if (length(cur) > 1) {
        keep <- cur[1]
        to_uncheck <- cur[-1]
        sf <- session_files()
        for (nm in to_uncheck) sf[[nm]] <- NULL
        session_files(sf)
        if (!is.null(file_manager_data$set_attachment_checked)) {
          lapply(to_uncheck, function(nm) file_manager_data$set_attachment_checked(nm, FALSE))
        }
        showToast(session, "MCP açıkken yalnızca 1 dosya eklenebilir. Fazla seçimler kaldırıldı.", "warning")
      }
    }
  })
  
  observeEvent(input$remove_file_from_prompt, {
    filename_to_remove <- input$remove_file_from_prompt$name
    req(filename_to_remove)

    current_files <- session_files()
    current_files[[filename_to_remove]] <- NULL
    session_files(current_files)

    if (!is.null(file_manager_data$set_attachment_checked)) {
      file_manager_data$set_attachment_checked(filename_to_remove, FALSE)
    }

    showToast(session, paste0("'", filename_to_remove, "' bağlamdan çıkarıldı."), "info")
  }, ignoreInit = TRUE)
  
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
  
  invisible(NULL)
}