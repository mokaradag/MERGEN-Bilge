# R/module_saved_chats.R (Updated with regex escaping, increased pagination, First/Last buttons)

savedChatsUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    div(
      class = "content-container",
      style = "padding-right: 20px;",
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
          textInput(ns("search_chats"), label = NULL, placeholder = "Söyleşilerde ara...", width = "300px")
        ),
        uiOutput(ns("saved_chats_list")),
        # FIX #13: Enhanced pagination with First/Last buttons
        div(
          class = "pagination-controls",
          style = "text-align: center; margin-top: 10px; padding: 10px 0;",
          actionButton(ns("first_page"), "« İlk", class = "btn-modern btn-secondary"),
          actionButton(ns("prev_page"), "‹ Önceki", class = "btn-modern btn-secondary"),
          span(textOutput(ns("page_info"), inline = TRUE), style = "margin: 0 20px;"),
          actionButton(ns("next_page"), "Sonraki ›", class = "btn-modern btn-secondary"),
          actionButton(ns("last_page"), "Son »", class = "btn-modern btn-secondary")
        )
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

    search_term_debounced <- reactiveVal()
    search_timer <- reactiveTimer(300)

    observeEvent(input$search_chats, {
      search_timer()
      current_page(1)  # Reset to first page on search
    })

    observeEvent(search_timer(), {
      search_term_debounced(input$search_chats)
    })
    
    # FIX #2: Escape regex special characters in search
    escape_regex <- function(string) {
      gsub("([\\[\\]\\{\\}\\(\\)\\*\\+\\?\\.\\^\\$\\|\\\\])", "\\\\\\1", string)
    }
    
    # FIX #2: Search from entire list, not just paginated
    filtered_saved_chats <- reactive({
      chats <- saved_chats()
      refresh_trigger()
      search_term <- input$search_chats
      
      if (is.null(chats) || length(chats) == 0) {
        return(list())
      }
      
      # Sort by timestamp (newest first)
      timestamps <- sapply(chats, function(x) {
        if (inherits(x$timestamp, "POSIXct")) {
          x$timestamp
        } else {
          as.POSIXct(x$timestamp, origin = "1970-01-01")
        }
      })
      sorted_indices <- order(timestamps, decreasing = TRUE)
      chats <- chats[sorted_indices]
      
      # FIX #2: Apply search with escaped regex
      if (!is.null(search_term) && nchar(search_term) > 0) {
        escaped_term <- escape_regex(search_term)
        chats <- chats[sapply(chats, function(chat) {
          tryCatch({
            grepl(escaped_term, chat$title, ignore.case = TRUE, fixed = FALSE)
          }, error = function(e) {
            # Fallback to fixed matching if regex still fails
            grepl(search_term, chat$title, ignore.case = TRUE, fixed = TRUE)
          })
        })]
      }
      
      return(chats)
    })
    
    # Paginated chats
    paginated_chats <- reactive({
      all_chats <- filtered_saved_chats()
      if (length(all_chats) == 0) return(list())
      
      start_idx <- (current_page() - 1) * chats_per_page + 1
      end_idx <- min(start_idx + chats_per_page - 1, length(all_chats))
      
      all_chats[start_idx:end_idx]
    })
    
    total_pages <- reactive({
      ceiling(length(filtered_saved_chats()) / chats_per_page)
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
    
    # Render the list of saved chat cards
    output$saved_chats_list <- renderUI({
      chats <- paginated_chats()
      
      # Handle empty states (preserve original behavior)
      if (is.null(chats) || length(chats) == 0) {
        if (!is.null(input$search_chats) && nchar(input$search_chats) > 0) {
          return(
            div(
              class = "empty-state",
              tags$i(class = "fas fa-search fa-3x"),
              h4("Sonuç Bulunamadı"),
              p("Aramanızla eşleşen kayıtlı söyleşi bulunamadı.")
            )
          )
        } else if (length(filtered_saved_chats()) == 0) {
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
      
      # ---- Group chats by month-year ----
      chats_by_month <- list()
      for (chat_id in names(chats)) {
        chat <- chats[[chat_id]]
        month_key <- format(chat$timestamp, "%Y-%m")
        month_label_raw <- format(chat$timestamp, "%B %Y")
        # Convert English months to Turkish
        month_label <- gsub("January", "Ocak", month_label_raw)
        month_label <- gsub("February", "Şubat", month_label)
        month_label <- gsub("March", "Mart", month_label)
        month_label <- gsub("April", "Nisan", month_label)
        month_label <- gsub("May", "Mayıs", month_label)
        month_label <- gsub("June", "Haziran", month_label)
        month_label <- gsub("July", "Temmuz", month_label)
        month_label <- gsub("August", "Ağustos", month_label)
        month_label <- gsub("September", "Eylül", month_label)
        month_label <- gsub("October", "Ekim", month_label)
        month_label <- gsub("November", "Kasım", month_label)
        month_label <- gsub("December", "Aralık", month_label)
        
        if (is.null(chats_by_month[[month_key]])) {
          chats_by_month[[month_key]] <- list(
            label = month_label,
            chats = list()
          )
        }
        chats_by_month[[month_key]]$chats[[chat_id]] <- chat
      }
      
      # Sort months: newest first
      chats_by_month <- chats_by_month[order(names(chats_by_month), decreasing = TRUE)]
      
      # ---- Render grouped UI (UPDATED STYLING) ----
      tagList(
        lapply(chats_by_month, function(month_group) {
          ids <- names(month_group$chats)
          ids <- ids[order(
            sapply(ids, function(id) month_group$chats[[id]]$timestamp),
            decreasing = TRUE
          )]
          
          # Only take first 25 to make 5x5 grid
          ids <- head(ids, 25)
          
          div(
            class = "month-group",
            style = "margin: 0 15px 20px 0; background: rgba(18, 18, 18, 0.6); padding: 15px; border-radius: 12px; border: 1px solid rgba(255, 138, 0, 0.2); backdrop-filter: blur(10px);",
            h4(
              month_group$label, 
              style = "color: #ff8a00; margin-bottom: 20px; font-size: 20px; font-weight: 600; text-decoration: underline; text-decoration-color: rgba(255, 138, 0, 0.3); text-underline-offset: 5px;"
            ),
            div(
              class = "saved-chats-grid-custom",
              style = "display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 15px; width: 100%; overflow-x: hidden;",
              lapply(ids, function(chat_id) {
                chat <- month_group$chats[[chat_id]]
                div(
                  class = "saved-chat-card saved-chat-card-small animate-fadeIn",
                  style = "min-width: 0; overflow: hidden;",
                  `data-chat-id` = chat_id,
                  onclick = sprintf("
                    if (!this.dataset.loading) {
                      this.dataset.loading = 'true';
                      Shiny.setInputValue('%s', '%s', {priority: 'event'});
                      setTimeout(() => delete this.dataset.loading, 1000);
                    }
                  ", ns("load_chat_id"), chat_id),
                  div(
                    class = "chat-card-header",
                    h5(chat$title, class = "chat-title chat-title-small", style = "white-space: nowrap; overflow: hidden; text-overflow: ellipsis;"),
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
                    span(class = "message-count", paste(chat$message_count, "mesaj")),
                    span(class = "chat-date", format(chat$timestamp, "%d.%m.%Y"))
                  )
                )
              })
            )
          )
        })
      )
    })
    
    # Handle delete request
    observeEvent(input$delete_chat_request, {
      req(input$delete_chat_request)
      chat_id <- input$delete_chat_request
      
      # Find the chat title from the current filtered list
      chats <- filtered_saved_chats()
      chat_title <- if (chat_id %in% names(chats)) {
        chats[[chat_id]]$title
      } else {
        "Bu söyleşi"
      }
      
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
      if (length(filtered_saved_chats()) > 0) {
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
        load_chat_id = eventReactive(input$load_chat_id, { input$load_chat_id }),
        delete_chat_id = delete_chat_trigger,
        clear_all_chats_trigger = clear_all_trigger,
        refresh = refresh
      )
    )
    
  })
}