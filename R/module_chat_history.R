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
		  tags$style(HTML(sprintf("#%s table.dataTable thead th { text-align: center !important; }", ns("history_table")))),
          DTOutput(ns("history_table"))
        )
      )
    )
  )
}

historyServer <- function(id, all_messages, current_user_id = NULL) {
  moduleServer(id, function(input, output, session) {
  
    resolve_current_user_id <- function() {
      uid <- if (is.function(current_user_id)) {
        tryCatch(current_user_id(), error = function(e) NULL)
      } else {
        current_user_id
      }

      session_uid <- session$userData$user_id %||% NULL
      uid <- suppressWarnings(as.integer(session_uid %||% uid %||% 0L))
      if (is.na(uid)) uid <- 0L
      uid
    }
    
    trigger_refresh <- reactiveVal(0)
	messages_cache <- reactiveVal(list())
    latest_chats <- reactiveVal(list())

    stamp_for_chat <- function(chat_info) {
      stamp_obj <- chat_info$last_message_timestamp %||% chat_info$timestamp %||% NA
      if (inherits(stamp_obj, "POSIXt")) {
        format(stamp_obj, "%Y-%m-%d %H:%M:%S", tz = "UTC")
      } else {
        as.character(stamp_obj %||% "")
      }
    }

    history_chat_activity_day_num <- function(chat_info) {
      stamp_obj <- chat_info$last_message_timestamp %||% chat_info$timestamp %||% NA

      if (inherits(stamp_obj, "POSIXt")) {
        return(as.numeric(as.Date(stamp_obj)))
      }

      if (inherits(stamp_obj, "Date")) {
        return(as.numeric(stamp_obj))
      }

      stamp_chr <- as.character(stamp_obj %||% "")
      if (!nzchar(stamp_chr) || is.na(stamp_chr)) {
        return(NA_real_)
      }

      parsed_time <- suppressWarnings(as.POSIXct(
        stamp_chr,
        tz = Sys.timezone(),
        tryFormats = c(
          "%Y-%m-%d %H:%M:%S",
          "%Y-%m-%d %H:%M",
          "%Y-%m-%d",
          "%d.%m.%Y - %H:%M",
          "%d.%m.%Y %H:%M",
          "%d/%m/%Y"
        )
      ))

      if (!is.na(parsed_time)) {
        return(as.numeric(as.Date(parsed_time)))
      }

      parsed_date <- suppressWarnings(as.Date(
        stamp_chr,
        tryFormats = c("%Y-%m-%d", "%d.%m.%Y", "%d/%m/%Y")
      ))

      if (!is.na(parsed_date)) {
        return(as.numeric(parsed_date))
      }

      NA_real_
    }

    history_chat_ids_for_date_range <- function(chats, date_range = NULL) {
      all_chat_ids <- setdiff(names(chats %||% list()), "current_chat")

      if (length(all_chat_ids) == 0L) {
        return(character(0))
      }

      if (is.null(date_range) || length(date_range) != 2L ||
          any(is.na(as.Date(date_range)))) {
        return(all_chat_ids)
      }

      start_num <- as.numeric(as.Date(date_range[1]))
      end_num <- as.numeric(as.Date(date_range[2]))

      chat_days <- vapply(
        all_chat_ids,
        function(chat_id) history_chat_activity_day_num(chats[[chat_id]]),
        numeric(1)
      )

      all_chat_ids[!is.na(chat_days) & chat_days >= start_num & chat_days <= end_num]
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

	ensure_history_cache <- function(chat_ids, chats, invalidate = TRUE) {
      if (length(chat_ids) == 0) {
        return(invisible(NULL))
      }

      cache <- messages_cache()
      to_fetch <- character()
      stamp_map <- list()

      normalized_ids <- as.character(chat_ids)
      normalized_ids <- normalized_ids[nzchar(normalized_ids)]

      for (chat_id in normalized_ids) {
        chat_info <- chats[[chat_id]]
        if (is.null(chat_info)) next
		
		if (identical(chat_id, "current_chat")) {
          if (!is.null(chat_info$messages) && length(chat_info$messages) > 0) {
            rows <- build_history_rows(chat_info$title %||% chat_id, chat_info$messages)
            cache[[chat_id]] <- list(rows = rows, stamp = Sys.time())
          }
          next
        }

        stamp_key <- stamp_for_chat(chat_info)
        stamp_map[[chat_id]] <- stamp_key

        cached <- cache[[chat_id]]
        if (!is.null(cached) &&
            identical(cached$stamp, stamp_key) &&
            length(cached$rows %||% list()) > 0) {
          next
        }

        to_fetch <- c(to_fetch, chat_id)
      }

      if (length(to_fetch) > 0) {
        fetched <- try(
          load_history_rows_batch(
            to_fetch,
            user_id = resolve_current_user_id()
          ),
          silent = TRUE
        )
		
        if (inherits(fetched, "try-error") || length(fetched) == 0) {
          for (chat_id in to_fetch) {
            cache[[chat_id]] <- list(rows = list(), stamp = stamp_map[[chat_id]])
          }
        } else {
          for (chat_id in to_fetch) {
            pairs <- fetched[[chat_id]] %||% fetched[[as.character(chat_id)]]
            if (!is.list(pairs) || length(pairs) == 0) {
              cache[[chat_id]] <- list(rows = list(), stamp = stamp_map[[chat_id]])
              next
            }

            cache[[chat_id]] <- list(rows = pairs, stamp = stamp_map[[chat_id]])
          }
        }
      }

      messages_cache(cache)
      if (isTRUE(invalidate) && length(to_fetch) > 0) {
        trigger_refresh(shiny::isolate(trigger_refresh()) + 1)
      }
      invisible(NULL)
    }
	
    refresh_history_cache <- function(chats = latest_chats(), force = FALSE, date_range = NULL) {
		chats <- chats %||% list()

        active_date_range <- date_range %||% shiny::isolate(input$date_range)
		chat_ids <- history_chat_ids_for_date_range(chats, active_date_range)

      if (isTRUE(force)) {
        messages_cache(list())
      } else {
        cache <- messages_cache()
        if (length(cache) > 0) {
          keep_ids <- intersect(names(cache), chat_ids)
          messages_cache(cache[keep_ids])
        }
      }

      if (length(chat_ids) == 0) {
        trigger_refresh(shiny::isolate(trigger_refresh()) + 1)
        return(invisible(NULL))
      }

      ensure_history_cache(chat_ids, chats, invalidate = TRUE)

      invisible(NULL)
    }

    # FIX #5: Add "Bugün" button handler
    observeEvent(input$today_filter, {
      updateDateRangeInput(session, "date_range",
                          start = Sys.Date(),
                          end = Sys.Date())
      showToast(session, "Bugünün kayıtları gösteriliyor.", "info")
    })
	
    observeEvent(all_messages(), {
      chats <- all_messages() %||% list()
      latest_chats(chats)

      # Geçmiş sekmesi henüz açılmadıysa başlangıçta ağır ön yükleme yapma.
      # Kullanıcı geçmişi ilk kez açtığında veya elle yenilediğinde doldurulacak.
      if (length(messages_cache()) > 0) {
        refresh_history_cache(
          chats = chats,
          force = FALSE,
          date_range = shiny::isolate(input$date_range)
        )
      }
    }, ignoreNULL = FALSE, priority = 1)

    observeEvent(input$date_range, {
      req(input$date_range)
      refresh_history_cache(
        chats = latest_chats(),
        force = TRUE,
        date_range = input$date_range
      )
    }, ignoreInit = TRUE)
	
    filtered_history <- reactive({
      req(all_messages())
      trigger_refresh()

      history_list <- list()
      chats <- all_messages()
      chat_ids <- names(chats)

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
    
    output$history_table <- DT::renderDT({
      DT::datatable(
        filtered_history(),
        colnames = c("Söyleşi Adı", "Tarih", "Soru", "Cevap"),
        escape = TRUE,
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
    
	outputOptions(output, "history_table", suspendWhenHidden = FALSE)
	
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
      refresh_history_cache(force = TRUE)
      showToast(session, "Geçmiş tablosu yenilendi.", "info")
    })

	# Ana sekme değişikliğinde tabloyu yenile (parent session'dan gelen sinyal)
    # NOT: Bu input, parent session tarafından doğrudan set edilir
    observeEvent(input$external_refresh_trigger, {
      cat("[HISTORY] Dış tetikleyici ile yenileme başlatıldı\n")
      refresh_history_cache(force = TRUE)
    }, ignoreInit = TRUE)
  })
}

showToast <- function(session, message, type = 'info', duration = 3000) {
  session$sendCustomMessage(
    type = 'showToast',
    message = list(message = message, type = type, duration = duration)
  )
}