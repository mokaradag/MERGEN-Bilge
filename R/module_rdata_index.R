# R/module_rdata_index.R

rdataIndexUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(class="content-container",
      h3("RData Lake Durumu", class = "page-title"),
      fluidRow(
        column(3, actionButton(ns("refresh_all"), "Yeniden Tara ve İndeksle", class="btn-modern")),
        column(3, verbatimTextOutput(ns("status")))
      )
    )
  )
}

rdataIndexServer <- function(id) {
  moduleServer(id, function(input, output, session) {

	output$status <- renderText({
	  # Eski motor yerine aktif lake kataloğunu göster.
	  catv <- helpers_rdata_lake$catalog
	  if (!nrow(catv)) return("Katalog yüklenmedi.")
	  paste0(
		"Tablo sayısı: ", length(unique(catv$table_name %||% character(0))),
		"\nToplam kaynak dosya: ", length(unique(catv$source_file %||% character(0))),
		"\nToplam satır: ", sum(as.numeric(catv$n_rows %||% 0), na.rm = TRUE)
	  )
	})

    observeEvent(input$refresh_all, {
      showNotification("Klasörler yeniden taranıyor…", duration = NULL, type = "message", id = "idx_note")
		promises::future_promise({
		  helpers_rdata_lake$rdata_refresh_all()
		}) %...>% (function(.) {
        removeNotification("idx_note")
        showNotification("RData lake güncellendi.", type = "message")
        output$status <- renderText({
          # Türkçe yorum: Lake kataloğundan güncel özet ver.
          catv <- helpers_rdata_lake$catalog
          if (!nrow(catv)) return("Katalog yüklenmedi.")
          paste0(
            "Tablo sayısı: ", length(unique(catv$table_name %||% character(0))),
            "\nToplam kaynak dosya: ", length(unique(catv$source_file %||% character(0))),
            "\nToplam satır: ", sum(as.numeric(catv$n_rows %||% 0), na.rm = TRUE)
          )
        })
      }) %...!% (function(e) {
        removeNotification("idx_note")
        showNotification(paste("Hata:", conditionMessage(e)), type = "error")
      })
    })
  })
}
