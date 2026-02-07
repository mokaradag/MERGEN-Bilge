# Dosya Yolu: R/module_image_gallery.R
# Gorsel Galerisi modulu - kullanicinin olusturdugu gorselleri goruntulemek, yonetmek ve silmek icin

#' Gorsel Galerisi UI
#' @param id Modul ID
#' @return Shiny UI tagList
imageGalleryUI <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "content-container",
      div(
        class = "files-header",
        h3("G\u00f6rsel Galerisi", class = "page-title"),
        div(
          class = "gallery-actions",
          actionButton(ns("refresh_gallery"), label = tagList(icon("sync-alt"), "Yenile"), class = "btn-modern btn-primary"),
          actionButton(ns("clear_all_images"), label = tagList(icon("trash-alt"), "T\u00fcm\u00fcn\u00fc Temizle"), class = "btn-modern btn-danger")
        )
      ),
      div(
        class = "scrollable-content",
        div(
          class = "gallery-controls",
          textInput(ns("search_images"), label = NULL, placeholder = "G\u00f6rsellerde ara...", width = "300px")
        ),
        div(
          class = "pagination-controls",
          style = "text-align: center; margin: 6px 0 14px; padding: 10px 0;",
          actionButton(ns("first_page"), "\u00ab \u0130lk", class = "btn-modern btn-secondary"),
          actionButton(ns("prev_page"), "\u2039 \u00d6nceki", class = "btn-modern btn-secondary"),
          span(textOutput(ns("page_info"), inline = TRUE), style = "margin: 0 20px;"),
          actionButton(ns("next_page"), "Sonraki \u203a", class = "btn-modern btn-secondary"),
          actionButton(ns("last_page"), "Son \u00bb", class = "btn-modern btn-secondary")
        ),
        uiOutput(ns("gallery_content"))
      )
    )
  )
}

#' Gorsel Galerisi Server
#' @param id Modul ID
#' @param current_user_id Mevcut kullanici ID
#' @return Reaktif degerler listesi
imageGalleryServer <- function(id, current_user_id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    images_per_page <- 24
    current_page <- reactiveVal(1)
    refresh_trigger <- reactiveVal(0)
    cached_images <- reactiveVal(data.frame(
      file_path = character(), chat_id = character(), filename = character(),
      created_at = as.POSIXct(character()), file_size = numeric(),
      month_key = character(), month_label = character(),
      stringsAsFactors = FALSE
    ))

    delete_image_trigger <- reactiveVal(NULL)
    clear_all_trigger <- reactiveVal(0)
    navigate_to_chat_trigger <- reactiveVal(NULL)

    observe({
      refresh_trigger()
      images <- scan_user_images(current_user_id)
      cached_images(images)
    })

    search_term_debounced <- reactiveVal("")
    search_timer <- reactiveTimer(300)

    observeEvent(input$search_images, {
      search_timer()
      current_page(1)
    })

    observeEvent(search_timer(), {
      search_term_debounced(input$search_images %||% "")
    })

    filtered_images <- reactive({
      imgs <- cached_images()
      refresh_trigger()
      term <- search_term_debounced()

      if (nrow(imgs) == 0) return(imgs)

      if (nzchar(term)) {
        term_lower <- tolower(term)
        matches <- grepl(term_lower, tolower(imgs$filename), fixed = TRUE) |
                   grepl(term_lower, tolower(imgs$month_label), fixed = TRUE) |
                   grepl(term_lower, tolower(imgs$chat_id), fixed = TRUE)
        imgs <- imgs[matches, , drop = FALSE]
      }

      imgs
    })

    total_pages <- reactive({
      n <- nrow(filtered_images())
      if (n == 0) return(0L)
      ceiling(n / images_per_page)
    })

    paginated_images <- reactive({
      imgs <- filtered_images()
      if (nrow(imgs) == 0) return(imgs)

      start_idx <- (current_page() - 1) * images_per_page + 1
      start_idx <- max(1, start_idx)
      end_idx <- min(start_idx + images_per_page - 1, nrow(imgs))

      imgs[start_idx:end_idx, , drop = FALSE]
    })

    observeEvent(filtered_images(), {
      total <- total_pages()
      if (total == 0) {
        current_page(1)
      } else if (current_page() > total) {
        current_page(total)
      }
    })

    observeEvent(input$first_page, { current_page(1) })
    observeEvent(input$last_page, { if (total_pages() > 0) current_page(total_pages()) })
    observeEvent(input$prev_page, { if (current_page() > 1) current_page(current_page() - 1) })
    observeEvent(input$next_page, { if (current_page() < total_pages()) current_page(current_page() + 1) })

    output$page_info <- renderText({
      if (total_pages() == 0) {
        ""
      } else {
        total_imgs <- nrow(filtered_images())
        sprintf("Sayfa %d / %d (%d g\u00f6rsel)", current_page(), total_pages(), total_imgs)
      }
    })
    outputOptions(output, "page_info", suspendWhenHidden = FALSE)

    output$gallery_content <- renderUI({
      imgs <- paginated_images()

      if (nrow(imgs) == 0) {
        search_val <- input$search_images
        if (!is.null(search_val) && nzchar(search_val)) {
          return(div(
            class = "empty-state",
            tags$i(class = "fas fa-search fa-3x"),
            h4("Sonu\u00e7 Bulunamad\u0131"),
            p("Araman\u0131zla e\u015fle\u015fen g\u00f6rsel bulunamad\u0131.")
          ))
        }
        return(div(
          class = "empty-state",
          tags$i(class = "fas fa-images fa-3x"),
          h4("Hen\u00fcz g\u00f6rsel yok"),
          p("G\u00f6rsel Uzman\u0131 arac\u0131 ile g\u00f6rsel olu\u015fturdu\u011funuzda burada g\u00f6r\u00fcnecektir.")
        ))
      }

      month_order <- unique(imgs$month_key)

      tagList(
        lapply(month_order, function(mk) {
          month_rows <- imgs[imgs$month_key == mk, , drop = FALSE]
          if (nrow(month_rows) == 0) return(NULL)

          div(
            class = "month-group gallery-month-group",
            style = "margin: 0 15px 20px 0; background: rgba(18, 18, 18, 0.6); padding: 15px; border-radius: 12px; border: 1px solid rgba(255, 138, 0, 0.2); backdrop-filter: blur(10px);",
            h4(
              month_rows$month_label[1],
              tags$span(
                class = "gallery-month-count",
                sprintf("(%d g\u00f6rsel)", nrow(month_rows))
              ),
              style = "color: #ff8a00; margin-bottom: 20px; font-size: 20px; font-weight: 600; text-decoration: underline; text-decoration-color: rgba(255, 138, 0, 0.3); text-underline-offset: 5px;"
            ),
            div(
              class = "gallery-grid",
              lapply(seq_len(nrow(month_rows)), function(idx) {
                row <- month_rows[idx, ]
                img_b64 <- get_image_thumbnail_base64(row$file_path)

                file_size_kb <- round(row$file_size / 1024, 1)
                created_str <- format(row$created_at, "%d.%m.%Y %H:%M")
                chat_title <- get_chat_title_for_image(row$chat_id, current_user_id) %||% "Bilinmeyen S\u00f6yle\u015fi"
                tooltip_text <- sprintf("Tarih: %s | Boyut: %s KB | S\u00f6yle\u015fi: %s",
                                        created_str, file_size_kb, chat_title)

                card_id <- paste0("img_card_", gsub("[^a-zA-Z0-9]", "_", row$filename))

                div(
                  class = "gallery-card animate-fadeIn",
                  id = card_id,
                  `data-file-path` = row$file_path,
                  `data-chat-id` = row$chat_id,
                  `data-tooltip` = tooltip_text,
                  div(
                    class = "gallery-card-image-wrapper",
                    onclick = sprintf(
                      "Shiny.setInputValue('%s', {chat_id: '%s', file_path: '%s'}, {priority: 'event'});",
                      ns("navigate_to_chat"), row$chat_id, gsub("'", "\\\\'", row$file_path)
                    ),
                    if (!is.null(img_b64)) {
                      tags$img(
                        src = img_b64,
                        alt = row$filename,
                        class = "gallery-card-image",
                        loading = "lazy"
                      )
                    } else {
                      div(
                        class = "gallery-card-placeholder",
                        tags$i(class = "fas fa-image fa-2x")
                      )
                    },
                    div(class = "gallery-card-overlay",
                      tags$i(class = "fas fa-expand-alt"),
                      tags$span("S\u00f6yle\u015fiye Git")
                    )
                  ),
                  div(
                    class = "gallery-card-footer",
                    div(
                      class = "gallery-card-info",
                      tags$span(class = "gallery-card-date", created_str),
                      tags$span(class = "gallery-card-size", paste0(file_size_kb, " KB"))
                    ),
                    tags$button(
                      class = "gallery-delete-btn",
                      title = "G\u00f6rseli Sil",
                      onclick = sprintf(
                        "event.stopPropagation(); Shiny.setInputValue('%s', {file_path: '%s', chat_id: '%s', filename: '%s'}, {priority: 'event'});",
                        ns("delete_image_request"),
                        gsub("'", "\\\\'", row$file_path),
                        row$chat_id,
                        row$filename
                      ),
                      tags$i(class = "fas fa-trash-alt")
                    )
                  )
                )
              })
            )
          )
        })
      )
    })

    outputOptions(output, "gallery_content", suspendWhenHidden = FALSE)

    observeEvent(input$delete_image_request, {
      req(input$delete_image_request)
      info <- input$delete_image_request
      fname <- info$filename %||% "Bu g\u00f6rsel"

      showModal(modalDialog(
        title = "G\u00f6rseli Sil",
        paste0("'", fname, "' g\u00f6rselini silmek istedi\u011finizden emin misiniz? \u0130lgili s\u00f6yle\u015fideki mesajda g\u00f6rselin silindi\u011fi belirtilecektir."),
        footer = tagList(
          actionButton(ns("confirm_delete_image"), "Evet, Sil", class = "btn-modern btn-danger"),
          tags$button("\u0130ptal", class = "btn-modern btn-success", `data-dismiss` = "modal")
        ),
        easyClose = TRUE
      ))
    })

    observeEvent(input$confirm_delete_image, {
      info <- input$delete_image_request
      removeModal()
      req(info$file_path)

      success <- delete_single_image(info$file_path, current_user_id, info$chat_id)
      if (success) {
        showToast(session, "G\u00f6rsel silindi.", "warning")
        delete_image_trigger(list(file_path = info$file_path, chat_id = info$chat_id))
        refresh_trigger(refresh_trigger() + 1)
      } else {
        showToast(session, "G\u00f6rsel silinemedi.", "error")
      }
    })

    observeEvent(input$clear_all_images, {
      imgs <- filtered_images()
      if (nrow(imgs) > 0) {
        showModal(modalDialog(
          title = "T\u00fcm G\u00f6rselleri Sil",
          sprintf("Toplam %d g\u00f6rselinizi silmek istedi\u011finizden emin misiniz? Bu i\u015flem geri al\u0131namaz. \u0130lgili s\u00f6yle\u015filerdeki mesajlarda g\u00f6rsellerin silindi\u011fi belirtilecektir.", nrow(cached_images())),
          footer = tagList(
            actionButton(ns("confirm_clear_all_images"), "Evet, T\u00fcm\u00fcn\u00fc Sil", class = "btn-modern btn-danger"),
            tags$button("\u0130ptal", class = "btn-modern btn-success", `data-dismiss` = "modal")
          ),
          easyClose = TRUE
        ))
      } else {
        showToast(session, "Silinecek g\u00f6rsel yok.", "info")
      }
    })

    observeEvent(input$confirm_clear_all_images, {
      removeModal()
      deleted_count <- delete_all_user_images(current_user_id)
      clear_all_trigger(clear_all_trigger() + 1)
      refresh_trigger(refresh_trigger() + 1)
      current_page(1)
      showToast(session, sprintf("%d g\u00f6rsel silindi.", deleted_count), "warning")
    })

    observeEvent(input$navigate_to_chat, {
      req(input$navigate_to_chat)
      navigate_to_chat_trigger(input$navigate_to_chat)
    })

    observeEvent(input$refresh_gallery, {
      refresh_trigger(refresh_trigger() + 1)
      shinyjs::runjs(sprintf("$('#%s').fadeOut(200).fadeIn(200);", ns("gallery_content")))
      showToast(session, "Galeri yenilendi.", "info")
    })

    return(list(
      delete_image = delete_image_trigger,
      clear_all_images = clear_all_trigger,
      navigate_to_chat = navigate_to_chat_trigger,
      refresh = function() refresh_trigger(refresh_trigger() + 1)
    ))
  })
}
