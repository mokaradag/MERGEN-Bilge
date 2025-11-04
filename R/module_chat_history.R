# R/module_chat_history.R (Updated with "Bugün" button functionality)

historyUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    div(
      class = "content-container",
      div(
        class = "files-header",
        h3("Söyleşi Geçmişi", class = "page-title"),
        div(
          class = "history-actions",
          actionButton(ns("refresh_history"), label = tagList(icon("sync-alt"), "Yenile"), class = "btn-modern btn-primary"),
          actionButton(ns("today_filter"), label = tagList(icon("calendar-day"), "Bugün"), class = "btn-modern btn-info"),
          downloadButton(ns("export_history"), label = "Excel'e Aktar", class = "btn-modern btn-success")
        )
      ),
      div(
        class = "scrollable-content",
        div(
          class = "history-controls date-filter dark-date-picker",
          dateRangeInput(
            inputId = ns("date_range"),
            label = "Tarih Aralığı:",
            start = Sys.Date() - 30,
            end = Sys.Date(),
            language = "tr",
            separator = " - ",
            format = "dd/mm/yyyy",
            width = "300px"
          )
        ),
        div(
          class = "history-table-card",
          DTOutput(ns("history_table"))
        )
      )
    )
  )
}

historyServer <- function(id, all_messages) {
  moduleServer(id, function(input, output, session) {
    
    trigger_refresh <- reactiveVal(0)
    
    # FIX #5: Add "Bugün" button handler
    observeEvent(input$today_filter, {
      updateDateRangeInput(session, "date_range",
                          start = Sys.Date(),
                          end = Sys.Date())
      showToast(session, "Bugünün kayıtları gösteriliyor.", "info")
    })
    
    filtered_history <- reactive({
      req(all_messages())
      trigger_refresh()
      
      history_list <- list()
      chats <- all_messages()
      
      for (chat_id in names(chats)) {
        chat_info <- chats[[chat_id]]
        messages <- chat_info$messages
        
        if (length(messages) > 0) {
          user_messages <- messages[sapply(messages, function(x) x$type == "user")]
          ai_messages <- messages[sapply(messages, function(x) x$type %in% c("ai", "assistant"))]
          
          if (length(user_messages) > 0 && length(ai_messages) > 0) {
            n <- min(length(user_messages), length(ai_messages))
            
            for (i in 1:n) {
              history_list[[length(history_list) + 1]] <- list(
                Chat_ID = chat_info$title,
                Tarih = user_messages[[i]]$timestamp,
                Soru = substr(user_messages[[i]]$content, 1, 100),
                Cevap = substr(ai_messages[[i]]$content, 1, 100)
              )
            }
          }
        }
      }
      
      if (length(history_list) == 0) {
        return(data.frame(
          Chat_ID = character(0),
          Tarih = character(0),
          Soru = character(0),
          Cevap = character(0)
        ))
      }
      
      history_data <- data.table::rbindlist(history_list)
      
      # Apply date filter
      if (!is.null(input$date_range) && length(input$date_range) == 2) {
        dates <- tryCatch(
          as.Date(history_data$Tarih, format = "%d.%m.%Y - %H:%M"),
          error = function(e) as.Date(NA)
        )
        
        if (any(!is.na(dates))) {
          mask <- dates >= input$date_range[1] & dates <= input$date_range[2]
          history_data <- history_data[mask & !is.na(mask), ]
        }
      }
      
      # Sort by date
      if (nrow(history_data) > 0) {
        history_data[, sort_ts := as.POSIXct(Tarih, format = "%d.%m.%Y - %H:%M", tz = Sys.timezone())]
        data.table::setorder(history_data, -sort_ts)
        history_data[, sort_ts := NULL]
      }
      
      return(history_data)
    })
    
    output$history_table <- renderDataTable({
      DT::datatable(
        filtered_history(),
        colnames = c("Söyleşi Adı", "Tarih", "Soru", "Cevap"),
        escape = FALSE,
        class = "display compact stripe hover dark-table",
        options = list(
          selection = "none",
          pageLength = 10,
          lengthMenu = list(c(5, 10, 25, 50, -1), c('5', '10', '25', '50', 'Tümü')),
          dom = 'lfrtip',
          responsive = TRUE,
          language = list(
            search = "Ara:",
            lengthMenu = "Sayfa başına _MENU_ kayıt göster",
            paginate = list(first = "İlk", last = "Son", previous = "Önceki", `next` = "Sonraki"),
            emptyTable = "Gösterilecek sohbet geçmişi yok",
            zeroRecords = "Filtre ile eşleşen kayıt bulunamadı",
            info = "_TOTAL_ kayıttan _START_ - _END_ arası gösteriliyor",
            infoEmpty = "0 kayıt gösteriliyor",
            infoFiltered = "(_MAX_ kayıt içerisinden filtrelendi)"
          ),
          columnDefs = list(
            list(className = 'dt-center', targets = '_all')
          )
        ),
        rownames = FALSE
      ) %>%
        formatStyle(
          columns = 1:4,
          color = '#e6e6e6',
          backgroundColor = 'transparent'
        )
    })
    
    output$export_history <- downloadHandler(
      filename = function() {
        paste0("mergen_sohbet_gecmisi_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".xlsx")
      },
      content = function(file) {
        export_data <- filtered_history()
        
        if (nrow(export_data) == 0) {
          export_data <- data.frame(Bilgi = "Dışa aktarılacak veri bulunamadı.")
        }
        
        writexl::write_xlsx(export_data, file)
      }
    )
    
    observeEvent(input$refresh_history, {
      trigger_refresh(trigger_refresh() + 1)
      showToast(session, "Geçmiş tablosu yenilendi.", "info")
    })
    
  })
}

showToast <- function(session, message, type = 'info', duration = 3000) {
  session$sendCustomMessage(
    type = 'showToast',
    message = list(message = message, type = type, duration = duration)
  )
}
