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
	messages_cache <- reactiveVal(list())

    stamp_for_chat <- function(chat_info) {
      stamp_obj <- chat_info$last_message_timestamp %||% chat_info$timestamp %||% NA
      if (inherits(stamp_obj, "POSIXt")) {
        format(stamp_obj, "%Y-%m-%d %H:%M:%S", tz = "UTC")
      } else {
        as.character(stamp_obj %||% "")
      }
    }

    build_history_rows <- function(chat_title, messages) {
      if (length(messages) == 0) {
        return(list())
      }

      user_messages <- messages[sapply(messages, function(x) x$type == "user")]
      ai_messages <- messages[sapply(messages, function(x) x$type %in% c("ai", "assistant"))]

      if (length(user_messages) == 0 || length(ai_messages) == 0) {
        return(list())
      }

      n <- min(length(user_messages), length(ai_messages))
      lapply(seq_len(n), function(i) {
        list(
          Chat_ID = chat_title,
          Tarih = user_messages[[i]]$timestamp,
          Soru = substr(user_messages[[i]]$content, 1, 100),
          Cevap = substr(ai_messages[[i]]$content, 1, 100)
        )
      })
    }

    ensure_history_cache <- function(chat_ids, chats) {
      if (length(chat_ids) == 0) {
        return(invisible(NULL))
      }

      cache <- messages_cache()
      to_fetch <- character()
      stamp_map <- list()

      for (chat_id in chat_ids) {
        chat_info <- chats[[chat_id]]
        if (is.null(chat_info)) next

        stamp_key <- stamp_for_chat(chat_info)
        stamp_map[[chat_id]] <- stamp_key

        cached <- cache[[chat_id]]
        if (!is.null(cached) && identical(cached$stamp, stamp_key)) {
          next
        }

        if (!is.null(chat_info$messages) && length(chat_info$messages) > 0) {
          rows <- build_history_rows(chat_info$title %||% chat_id, chat_info$messages)
          cache[[chat_id]] <- list(rows = rows, stamp = stamp_key)
        } else {
          to_fetch <- c(to_fetch, chat_id)
        }
      }

      if (length(to_fetch) > 0) {
        fetched <- try(load_chat_messages_batch(to_fetch), silent = TRUE)
        if (inherits(fetched, "try-error") || length(fetched) == 0) {
          for (chat_id in to_fetch) {
            cache[[chat_id]] <- list(rows = list(), stamp = stamp_map[[chat_id]])
          }
        } else {
          for (chat_id in to_fetch) {
            data <- fetched[[chat_id]] %||% fetched[[as.character(chat_id)]]
            messages <- if (is.list(data) && !is.null(data$messages)) data$messages else list()
            chat_info <- chats[[chat_id]]
            title <- chat_info$title %||% data$title %||% chat_id
            rows <- build_history_rows(title, messages)
            cache[[chat_id]] <- list(rows = rows, stamp = stamp_map[[chat_id]])
          }
        }
      }

      messages_cache(cache)
	  invisible(NULL)
    }
    
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
	  chat_ids <- names(chats)
      
	  ensure_history_cache(chat_ids, chats)
        
      cache <- messages_cache()
      for (chat_id in chat_ids) {
        cached <- cache[[chat_id]]
        if (!is.null(cached) && length(cached$rows) > 0) {
          history_list <- c(history_list, cached$rows)
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