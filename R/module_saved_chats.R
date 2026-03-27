# R/module_saved_chats.R (Updated with regex escaping, increased pagination, First/Last buttons)

savedChatsUI <- function(id) {
  ns <- NS(id)
  
tagList(
    div(
      class = "content-container",
      div(
        class = "files-header",
        h3("Kayıtlı Söyleşiler", class = "page-title"),
        div(
          class = "chat-actions",
          actionButton(ns("refresh_saved_chats"), label = tagList(icon("sync-alt"), "Yenile"), class = "btn-modern btn-primary"),
          actionButton(ns("clear_all_chats"), label = tagList(icon("trash-alt"), "Tümünü Temizle"), class = "btn-modern btn-danger")
        )
      ),
      div(
        class = "scrollable-content",
        div(
          class = "saved-chats-controls",
          textInput(ns("search_chats"), label = NULL, placeholder = "Başlıklarda ara...", width = "300px"),
          tags$button(
            type = "button",
            class = "btn-modern btn-secondary",
            style = "margin-left: 8px; white-space: nowrap;",
            title = "Tüm söyleşi içeriklerinde tam metin araması yapar",
            onclick = "if(window.openChatSearchModal) window.openChatSearchModal();",
            tags$i(class = "fas fa-search", style = "margin-right: 6px;"),
            "İçerikte Ara"
          )
        ),
        div(
          class = "pagination-controls",
          style = "text-align: center; margin: 6px 0 14px; padding: 10px 0;",
          actionButton(ns("first_page"), "\U00AB İlk", class = "btn-modern btn-secondary"),
          actionButton(ns("prev_page"), "\U2039 Önceki", class = "btn-modern btn-secondary"),
          span(textOutput(ns("page_info"), inline = TRUE), style = "margin: 0 20px;"),
          actionButton(ns("next_page"), "Sonraki \U203A", class = "btn-modern btn-secondary"),
          actionButton(ns("last_page"), "Son \U00BB", class = "btn-modern btn-secondary")
        ),
        uiOutput(ns("saved_chats_list"))
      )
    )
  )
}

savedChatsServer <- function(id, saved_chats) {
  moduleServer(id, function(input, output, session) {
    
    ns <- session$ns
    
    # FIX #13: Increased chats per page from 12 to 30
    chats_per_page <- 30
    current_page <- reactiveVal(1)
    
    # Reactive values
    load_chat_trigger <- reactiveVal()
    delete_chat_trigger <- reactiveVal()
    clear_all_trigger <- reactiveVal(0)
    refresh_trigger <- reactiveVal(0)

    observeEvent(input$load_chat_id, {
      # Sohbet kartı tıklamasını doğrudan reactiveVal'e aktar.
      # eventReactive gecikmesi/önceki değer riski olmadan güncel ID taşınır.
      load_chat_trigger(input$load_chat_id)
    }, ignoreInit = TRUE)

    search_term_debounced <- reactiveVal()
    search_timer <- reactiveTimer(300)
	
	    empty_meta <- function() {
      data.frame(
        chat_id = character(),
        title = character(),
        title_lower = character(),
        timestamp = as.POSIXct(character()),
        message_count = integer(),
        display_date = character(),
        month_key = character(),
        month_label = character(),
        stringsAsFactors = FALSE
      )
    }

    cached_meta <- reactiveVal(empty_meta())

    # Saat dilimi sabiti - DB'deki zaman damgaları Istanbul zamanında saklanır
    TARGET_TZ <- "Europe/Istanbul"

    parse_timestamp <- function(value) {
      if (inherits(value, "POSIXt")) {
        # DB sürücüsü (ODBC) zaman damgasını UTC olarak döndürebilir,
        # ancak DB'deki gerçek değer Istanbul zamanıdır.
        # Saat yüzü değerini Istanbul olarak yeniden yorumla (dönüştürme yapmadan).
        clock_str <- format(value, "%Y-%m-%d %H:%M:%S")
        return(as.POSIXct(clock_str, tz = TARGET_TZ))
      }
      if (is.numeric(value)) {
        return(as.POSIXct(value, origin = "1970-01-01", tz = TARGET_TZ))
      }
      if (is.character(value) && nzchar(value)) {
        parsed <- suppressWarnings(as.POSIXct(value, tz = TARGET_TZ))
        if (is.na(parsed)) {
          parsed <- suppressWarnings(as.POSIXct(value, format = "%d.%m.%Y - %H:%M", tz = TARGET_TZ))
        }
        if (is.na(parsed)) {
          parsed <- suppressWarnings(as.POSIXct(value, format = "%Y-%m-%d %H:%M:%S", tz = TARGET_TZ))
        }
        if (!is.na(parsed)) {
          return(parsed)
        }
      }
      Sys.time()
    }

    month_map <- c(
      "January" = "Ocak",
      "February" = "Şubat",
      "March" = "Mart",
      "April" = "Nisan",
      "May" = "Mayıs",
      "June" = "Haziran",
      "July" = "Temmuz",
      "August" = "Ağustos",
      "September" = "Eylül",
      "October" = "Ekim",
      "November" = "Kasım",
      "December" = "Aralık"
    )

    observeEvent(input$search_chats, {
      search_timer()
      current_page(1)  # Reset to first page on search
    })

    observeEvent(search_timer(), {
      search_term_debounced(input$search_chats)
    })
    
	    observeEvent(saved_chats(), {
      chats <- saved_chats()

      if (is.null(chats) || length(chats) == 0) {
        cached_meta(empty_meta())
        return()
      }

      ids <- names(chats)
      titles <- vapply(chats, function(chat) chat$title %||% "Söyleşi", character(1))
      timestamps <- vapply(chats, function(chat) {
        raw <- chat$last_message_timestamp %||% chat$timestamp
        as.numeric(parse_timestamp(raw))
      }, numeric(1))

      timestamps <- as.POSIXct(timestamps, origin = "1970-01-01", tz = TARGET_TZ)

      message_counts <- vapply(chats, function(chat) as.integer(chat$message_count %||% 0L), integer(1))

      month_keys <- format(timestamps, "%Y-%m")
      month_labels <- paste0(month_map[format(timestamps, "%B")], " ", format(timestamps, "%Y"))
      month_labels[is.na(month_labels)] <- format(timestamps[is.na(month_labels)], "%B %Y")

      meta <- data.frame(
        chat_id = ids,
        title = titles,
        title_lower = tolower(titles),
        timestamp = timestamps,
        message_count = message_counts,
        display_date = format(timestamps, "%d.%m.%Y"),
        month_key = month_keys,
        month_label = month_labels,
        stringsAsFactors = FALSE
      )

      meta <- meta[order(meta$timestamp, decreasing = TRUE), , drop = FALSE]
      rownames(meta) <- NULL
      cached_meta(meta)
    }, ignoreNULL = FALSE)
	
    # FIX #2: Escape regex special characters in search
    escape_regex <- function(string) {
      gsub("([\\[\\]\\{\\}\\(\\)\\*\\+\\?\\.\\^\\$\\|\\\\])", "\\\\\\1", string)
    }
    
    # FIX #2: Search from entire list, not just paginated
	filtered_saved_chats <- reactive({
        meta <- cached_meta()
        refresh_trigger()
        search_term <- input$search_chats

        if (nrow(meta) == 0) {
          return(meta)
        }

        if (!is.null(search_term) && nchar(search_term) > 0) {
          escaped_term <- escape_regex(search_term)
          matches <- tryCatch({
            grepl(escaped_term, meta$title, ignore.case = TRUE, perl = TRUE)
          }, error = function(e) {
            rep(FALSE, nrow(meta))
          })

          if (!any(matches)) {
            matches <- grepl(search_term, meta$title, ignore.case = TRUE, fixed = TRUE)
          }

          meta <- meta[matches, , drop = FALSE]
        }

        meta
	})

    # Paginated chats
	paginated_chats <- reactive({
        meta <- filtered_saved_chats()
        if (nrow(meta) == 0) return(meta)

        start_idx <- (current_page() - 1) * chats_per_page + 1
        start_idx <- max(1, start_idx)
        end_idx <- min(start_idx + chats_per_page - 1, nrow(meta))

        meta[start_idx:end_idx, , drop = FALSE]
	})
    
    total_pages <- reactive({
      meta <- filtered_saved_chats()
      if (nrow(meta) == 0) {
        return(0L)
      }
      ceiling(nrow(meta) / chats_per_page)
    })

    observeEvent(filtered_saved_chats(), {
      meta <- filtered_saved_chats()
      total <- if (nrow(meta) == 0) 0L else ceiling(nrow(meta) / chats_per_page)
      if (total == 0) {
        current_page(1)
      } else if (current_page() > total) {
        current_page(total)
      }
    })
    
    # FIX #13: Add First/Last page navigation
    observeEvent(input$first_page, {
      current_page(1)
    })
    
    observeEvent(input$last_page, {
      if (total_pages() > 0) {
        current_page(total_pages())
      }
    })
    
    observeEvent(input$prev_page, {
      if (current_page() > 1) {
        current_page(current_page() - 1)
      }
    })
    
    observeEvent(input$next_page, {
      if (current_page() < total_pages()) {
        current_page(current_page() + 1)
      }
    })
    
    output$page_info <- renderText({
      if (total_pages() == 0) {
        ""
      } else {
        sprintf("Sayfa %d / %d", current_page(), total_pages())
      }
    })
    outputOptions(output, "page_info", suspendWhenHidden = FALSE)
	
	# Render the list of saved chat cards
    output$saved_chats_list <- renderUI({
      chats_meta <- paginated_chats()
      filtered_meta <- filtered_saved_chats()
      
      # Handle empty states (preserve original behavior)
      if (nrow(chats_meta) == 0) {
        if (!is.null(input$search_chats) && nchar(input$search_chats) > 0) {
          return(
            div(
              class = "empty-state",
              tags$i(class = "fas fa-search fa-3x"),
              h4("Sonuç Bulunamadı"),
              p("Aramanızla eşleşen kayıtlı söyleşi bulunamadı.")
            )
          )
        } else if (nrow(filtered_meta) == 0) {
          return(
            div(
              class = "empty-state",
              tags$i(class = "fas fa-comments fa-3x"),
              h4("Henüz kayıtlı söyleşi yok"),
              p("Yeni bir söyleşi başlattığınızda mevcut söyleşiniz otomatik olarak kaydedilir.")
            )
          )
        } else {
          return(div()) # Empty page, but chats exist
        }
      }
            
      month_order <- unique(chats_meta$month_key)
	  
      tagList(
        lapply(month_order, function(month_key) {
          month_rows <- chats_meta[chats_meta$month_key == month_key, , drop = FALSE]
          if (nrow(month_rows) == 0) return(NULL)

          month_rows <- month_rows[order(month_rows$timestamp, decreasing = TRUE), , drop = FALSE]
          month_rows <- month_rows[seq_len(min(nrow(month_rows), 25)), , drop = FALSE]
          
          div(
            class = "month-group",
            style = "margin: 0 15px 20px 0; background: rgba(18, 18, 18, 0.6); padding: 15px; border-radius: 12px; border: 1px solid rgba(255, 138, 0, 0.2); backdrop-filter: blur(10px);",
            h4(
              month_rows$month_label[1],
              style = "color: #ff8a00; margin-bottom: 20px; font-size: 20px; font-weight: 600; text-decoration: underline; text-decoration-color: rgba(255, 138, 0, 0.3); text-underline-offset: 5px;"
            ),
            div(
              class = "saved-chats-grid-custom",
              style = "display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 15px; width: 100%; overflow-x: hidden;",
              lapply(seq_len(nrow(month_rows)), function(idx) {
                chat_row <- month_rows[idx, ]
                chat_id <- chat_row$chat_id
                div(
                  class = "saved-chat-card saved-chat-card-small animate-fadeIn",
                  style = "min-width: 0; overflow: hidden;",
                  `data-chat-id` = chat_id,
                  onclick = sprintf(
                    "Shiny.setInputValue('%s', '%s', {priority: 'event'});",
                    ns("load_chat_id"), chat_id
                  ),
                  div(
                    class = "chat-card-header",
                    h5(chat_row$title, class = "chat-title chat-title-small", style = "white-space: nowrap; overflow: hidden; text-overflow: ellipsis;"),
                    div(
                      class = "chat-actions",
                      actionButton(
                        inputId = ns(paste0("delete_", chat_id)),
                        label = "",
                        icon = icon("trash"),
                        class = "btn-icon-only btn-icon-small",
                        onclick = sprintf(
                          "event.stopPropagation(); Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                          ns("delete_chat_request"), chat_id
                        )
                      )
                    )
                  ),
                  div(
                    class = "chat-card-meta chat-card-meta-small",
                    span(class = "message-count", paste(chat_row$message_count, "mesaj")),
                    span(class = "chat-date", chat_row$display_date)
                  )
                )
              })
            )
          )
        })
      )
	})

    outputOptions(output, "saved_chats_list", suspendWhenHidden = FALSE)
    
    # Handle delete request
    observeEvent(input$delete_chat_request, {
      req(input$delete_chat_request)
      chat_id <- input$delete_chat_request
      
      meta <- cached_meta()
      match_idx <- match(chat_id, meta$chat_id)
      chat_title <- if (!is.na(match_idx)) meta$title[match_idx] else "Bu söyleşi"
      
      showModal(modalDialog(
        title = "Söyleşiyi Sil",
        paste0("'", chat_title, "' başlıklı söyleşiyi silmek istediğinizden emin misiniz?"),
        footer = tagList(
          actionButton(ns("confirm_delete_chat"), "Evet, Sil", class = "btn-modern btn-danger",
                      `data-chat-id` = chat_id),
          tags$button("İptal", class = "btn-modern btn-success", `data-dismiss` = "modal")
        ),
        easyClose = TRUE
      ))
    })
    
    observeEvent(input$confirm_delete_chat, {
      chat_id <- input$delete_chat_request
      removeModal()
      delete_chat_trigger(chat_id)
      showToast(session, "Söyleşi silindi.", "warning")
    })
    
    observeEvent(input$clear_all_chats, {
      if (nrow(filtered_saved_chats()) > 0) {
        showModal(modalDialog(
          title = "Tüm Söyleşileri Temizle",
          "Tüm kayıtlı söyleşileri silmek istediğinizden emin misiniz? Bu işlem geri alınamaz!",
          footer = tagList(
            actionButton(ns("confirm_clear_all_chats"), "Evet, Tümünü Sil", class = "btn-modern btn-danger"),
            tags$button("İptal", class = "btn-modern btn-success", `data-dismiss` = "modal")
          ),
          easyClose = TRUE
        ))
      } else {
        showToast(session, "Temizlenecek söyleşi yok.", "info")
      }
    })
    
    observeEvent(input$confirm_clear_all_chats, {
      removeModal()
      clear_all_trigger(clear_all_trigger() + 1)
      current_page(1)  # Reset to first page
    })
    
    # Refresh handler
    observeEvent(input$refresh_saved_chats, {
      refresh_trigger(refresh_trigger() + 1)
      shinyjs::runjs(sprintf("$('#%s').fadeOut(200).fadeIn(200);", ns("saved_chats_list")))
      showToast(session, "Söyleşiler yenilendi.", "info")
    })
    
    # Public refresh method
    refresh <- function() {
      refresh_trigger(refresh_trigger() + 1)
    }
    
    return(
      list(
        load_chat_id = load_chat_trigger,
        delete_chat_id = delete_chat_trigger,
        clear_all_chats_trigger = clear_all_trigger,
        refresh = refresh
      )
    )

  })
}