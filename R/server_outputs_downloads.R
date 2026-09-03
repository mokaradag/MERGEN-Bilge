# R/server_outputs_downloads.R
# Dosya Yolu: R/server_outputs_downloads.R
# Açıklama: İndirme işleyicileri, dosya gösterge UI'ı ve widget bağımlılık çıktıları.
# Bu dosya server.R'deki çeşitli output tanımlarını içerir.

#' İndirme ve Çıktı Tanımlarını Başlat
#' @description İndirme işleyicileri ve çeşitli UI çıktılarını tanımlar
#' @param output Shiny output nesnesi
#' @param session Shiny session nesnesi
#' @param session_files Oturum dosyaları reaktif değeri
#' @param current_user_id Mevcut kullanıcı ID'si
downloadOutputsInit <- function(output, session, session_files, current_user_id) {

  resolve_runtime_user_id <- function() {
    uid <- if (is.function(current_user_id)) current_user_id() else current_user_id
    uid <- suppressWarnings(as.integer(session$userData$user_id %||% uid %||% 0L))
    if (is.na(uid) || uid < 0L) uid <- 0L
    uid
  }
  
  # Ekli dosya göstergesi UI'ı
  output$file_prompt_indicator_ui <- renderUI({
    files_list <- names(session_files())
    req(length(files_list) > 0)
    
    div(class = "file-indicator-wrapper",
      tags$p(
        class = "file-indicator-title",
        sprintf("Ekli Dosyalar (%d):", length(files_list))
      ),
      div(
        class = "file-indicator-scroll-container",
        lapply(files_list, function(filename) {
          div(class = "file-indicator",
            tagList(
              icon("paperclip"),
              span(class = "file-indicator-name", filename),
              tags$button(
                icon("times"),
                class = "file-indicator-close action-button",
                onclick = sprintf("Shiny.setInputValue('remove_file_from_prompt', { name: '%s', nonce: Math.random() }, {priority: 'event'})", filename)
              )
            )
          )
        })
      )
    )
  })
  
  # Sohbet log'larını indirme işleyicisi
  output$download_logs <- downloadHandler(
    filename = function() {
      paste0("chat_logs_", format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
	  logs_df <- fetch_user_activity_logs(resolve_runtime_user_id())
      write.csv(logs_df, file, row.names = FALSE, fileEncoding = "UTF-8")
    }
  )
  
  invisible(NULL)
}

#' Widget Bağımlılık Çıktısını Başlat
#' @description Highcharter için bağımlılık yükleyici çıktısı tanımlar.
#'   Grafikler tek motorla (highcharter) render edilir; plotly bağımlılığı
#'   tamamen kaldırılmıştır.
#' @param output Shiny output nesnesi
widgetDependencyOutputsInit <- function(output) {

  # Highcharter bağımlılık yükleyicisi
  if (requireNamespace("highcharter", quietly = TRUE)) {
    output$deps_hc <- highcharter::renderHighchart({
      highcharter::highchart()
    })
  }

  invisible(NULL)
}