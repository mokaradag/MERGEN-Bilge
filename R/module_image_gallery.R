# Dosya Yolu: R/module_image_gallery.R
# Görsel Galerisi modülü - kullanıcının oluşturduğu görselleri görüntülemek, yönetmek ve silmek için

#' Görsel Galerisi UI
#' @param id Modül ID
#' @return Shiny UI tagList
imageGalleryUI <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "content-container",
      div(
        class = "files-header",
        h3("Görsel Galerisi", class = "page-title"),
        div(
          class = "gallery-actions",
          actionButton(ns("refresh_gallery"), label = tagList(icon("sync-alt"), "Yenile"), class = "btn-modern btn-refresh"),
          actionButton(ns("clear_all_images"), label = tagList(icon("trash-alt"), "Tümünü Temizle"), class = "btn-modern btn-danger")
        )
      ),
      div(
        class = "scrollable-content",
        div(
          class = "gallery-controls",
          textInput(ns("search_images"), label = NULL, placeholder = "Görsellerde ara (açıklama, tarih, söyleşi)...", width = "400px")
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
        uiOutput(ns("gallery_content"))
      )
    )
  )
}

#' Görsel Galerisi Server
#' @param id Modül ID
#' @param current_user_id Mevcut kullanıcı ID
#' @return Reaktif değerler listesi
imageGalleryServer <- function(id, current_user_id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    coerce_user_id <- function(x) suppressWarnings(as.integer(x %||% 0L))

    resolve_current_user_id <- function() {
      resolve_effective_user_id(
        session = session,
        current_user_id = current_user_id
      )
    }

    empty_images_df <- function() {
      data.frame(
        file_path = character(), chat_id = character(), filename = character(),
        created_at = as.POSIXct(character()), file_size = numeric(),
        month_key = character(), month_label = character(),
        description = character(), chat_title = character(),
        stringsAsFactors = FALSE
      )
    }

    images_per_page <- 24
    current_page <- reactiveVal(1)
    refresh_trigger <- reactiveVal(0)
    gallery_revision <- reactiveVal(0)
    effective_user_id <- reactiveVal(coerce_user_id(resolve_current_user_id()))
    cached_images <- reactiveVal(empty_images_df())

    # TEMBEL galeri: görsel tarama + açıklama DB sorguları soğuk açılışta
    # ÇALIŞMAZ. Galeri, kullanıcı sayfayı ilk açtığında (navigasyon gözlemcisi
    # refresh_gallery girdisini gönderir) etkinleşir; o ana kadar tarama atlanır.
    gallery_activated <- reactiveVal(FALSE)

    # Tarama sürerken kullanıcıya yükleme durumu gösterilir. Tarama bir "tick"
    # ertelenir ki yükleme animasyonu taramadan ÖNCE ekrana çizilebilsin; aksi
    # halde senkron tarama ilk render'ı blokluyor ve sayfa saniyelerce boş
    # görünüyordu.
    gallery_loading <- reactiveVal(FALSE)

    delete_image_trigger <- reactiveVal(NULL)
    clear_all_trigger <- reactiveVal(0)
    navigate_to_chat_trigger <- reactiveVal(NULL)

    # İki galeri tarama sonucunun aynı görselleri içerip içermediğini karşılaştır
    gallery_images_same <- function(a, b) {
      if (!is.data.frame(a) || !is.data.frame(b)) return(FALSE)
      if (nrow(a) != nrow(b)) return(FALSE)
      if (nrow(a) == 0) return(TRUE)
      a_key <- paste(a$file_path, a$file_size, sep = "|")
      b_key <- paste(b$file_path, b$file_size, sep = "|")
      setequal(a_key, b_key)
    }

    # Gerçek (senkron) tarama gövdesi; yalnızca ertelenmiş geri çağrıdan koşar.
    gallery_do_scan <- function(force = FALSE) {
      uid <- coerce_user_id(resolve_current_user_id())
      effective_user_id(uid)

      if (is.na(uid) || uid <= 0) {
        cached_images(empty_images_df())
        return(invisible(NULL))
      }

      tarama_baslangici <- Sys.time()
      scanned <- scan_user_images(uid)
      cat(sprintf(
        "[IMAGE_GALLERY] tarama tamamlandı: %d görsel, %.0f ms\n",
        nrow(scanned),
        as.numeric(difftime(Sys.time(), tarama_baslangici, units = "secs")) * 1000
      ))

      # Tarama sonucu mevcut önbellekle aynıysa reaktif güncelleme yapma.
      # Galeri zaten önbellekten anında görünür; sekme geçişlerinde gereksiz
      # yeniden render ve titreme bu sayede önlenir. Yeni veya silinen görsel
      # olduğunda tarama farklı olur ve önbellek güncellenir.
      if (isTRUE(force) || !gallery_images_same(isolate(cached_images()), scanned)) {
        cached_images(scanned)
      }
      if (isTRUE(force)) {
        gallery_revision(gallery_revision() + 1)
      }
      invisible(NULL)
    }

    refresh_gallery_cache <- function(force = FALSE) {
      # Galeri hiç açılmadıysa tarama yapma: açılıştaki auth-sonrası refresh
      # tetikleri (SSO refreshable-module kancası dahil) burada güvenle atlanır.
      # İlk gerçek sayfa açılışı gallery_activated'ı TRUE yapar ve tarar.
      if (!isTRUE(gallery_activated())) {
        return(invisible(NULL))
      }
      if (isTRUE(isolate(gallery_loading()))) {
        return(invisible(NULL))
      }

      gallery_loading(TRUE)
      later::later(function() {
        # Oturum kapandıysa (testServer/oturum sonu) yok edilmiş modül
        # reaktiflerine dokunma; bayat geri çağrı sessizce düşer.
        kapali <- tryCatch(isTRUE(session$isClosed()), error = function(e) TRUE)
        if (kapali) return(invisible(NULL))
        shiny::withReactiveDomain(session, {
          shiny::isolate({
            tryCatch(
              gallery_do_scan(force = force),
              error = function(e) {
                cat(sprintf("[IMAGE_GALLERY] tarama hatası: %s\n", conditionMessage(e)))
              }
            )
            gallery_loading(FALSE)
          })
        })
      }, delay = 0.05)
      invisible(NULL)
    }

    observe({
      refresh_trigger()
      refresh_gallery_cache()
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

    # Arama: açıklama, dosya adı, ay etiketi ve sohbet başlığı üzerinden filtrele
    filtered_images <- reactive({
      # Normal sekme geçişlerinde önbellek değişmedikçe render tetiklenmez;
      # kullanıcının açık Yenile tıklaması ise gallery_revision üzerinden
      # aynı dosya listesinde bile ekranı bilinçli olarak tazeler.
      gallery_revision()
      imgs <- cached_images()
      term <- search_term_debounced()

      if (nrow(imgs) == 0) return(imgs)

	  if (nzchar(term)) {
        term_lower <- tolower(term)
        # Dosya adı, ay etiketi, açıklama ve söyleşi başlığı üzerinden ara
        matches <- grepl(term_lower, tolower(imgs$filename), fixed = TRUE) |
                   grepl(term_lower, tolower(imgs$month_label), fixed = TRUE) |
                   grepl(term_lower, tolower(imgs$description), fixed = TRUE) |
                   grepl(term_lower, tolower(imgs$chat_title), fixed = TRUE)
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
        sprintf("Sayfa %d / %d (%d görsel)", current_page(), total_pages(), total_imgs)
      }
    })
    outputOptions(output, "page_info", suspendWhenHidden = FALSE)

    output$gallery_content <- renderUI({
      imgs <- paginated_images()

      # İlk tarama sürerken kullanıcı boş ekran yerine yükleme durumu görür.
      if (isTRUE(gallery_loading()) && nrow(imgs) == 0) {
        return(div(
          class = "mergen-loading-state",
          div(class = "mergen-loading-spinner"),
          h4("Görseller yükleniyor"),
          p("Görsel galeriniz taranıyor, lütfen bekleyin...")
        ))
      }

      if (nrow(imgs) == 0) {
        search_val <- input$search_images
        if (!is.null(search_val) && nzchar(search_val)) {
          return(div(
            class = "empty-state",
            tags$i(class = "fas fa-search fa-3x"),
            h4("Sonuç Bulunamadı"),
            p("Aramanızla eşleşen görsel bulunamadı.")
          ))
        }
        return(div(
          class = "empty-state",
          tags$i(class = "fas fa-images fa-3x"),
          h4("Henüz görsel yok"),
          p("Görsel Uzmanı aracı ile görsel oluşturduğunuzda burada görünecektir.")
        ))
      }

      month_order <- unique(imgs$month_key)

      tagList(
        lapply(month_order, function(mk) {
          month_rows <- imgs[imgs$month_key == mk, , drop = FALSE]
          if (nrow(month_rows) == 0) return(NULL)

          div(
            class = "month-group gallery-month-group image-gallery-month-group",
            style = "margin: 0 15px 20px 0; background: rgba(18, 18, 18, 0.6); padding: 15px; border-radius: 12px; border: 1px solid rgba(255, 138, 0, 0.2); backdrop-filter: blur(10px);",
            h4(
              month_rows$month_label[1],
              # Aylık görsel sayısı rozeti - light tema CSS bu sınıfı
              # turuncu/güçlü kontrast ile gösterir (theme_light_pages.css).
              tags$span(
                class = "gallery-month-count month-count-badge",
                sprintf("(%d görsel)", nrow(month_rows))
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
                chat_title <- row$chat_title %||% ""
                if (!nzchar(chat_title)) chat_title <- "Bilinmeyen Söyleşi"

                # Açıklama metnini tooltip olarak göster
                desc_text <- if (nzchar(row$description)) row$description else ""
                # Tooltip: açıklama + tarih + boyut + söyleşi
                tooltip_parts <- c()
                if (nzchar(desc_text)) tooltip_parts <- c(tooltip_parts, desc_text)
                tooltip_parts <- c(tooltip_parts,
                  paste0("Tarih: ", created_str),
                  paste0("Boyut: ", file_size_kb, " KB"),
                  paste0("Söyleşi: ", chat_title)
                )
                tooltip_text <- paste(tooltip_parts, collapse = " | ")

                card_id <- paste0("img_card_", gsub("[^a-zA-Z0-9]", "_", row$filename))

                # chat_id'nin geçerli bir sayı olup olmadığını kontrol et
                chat_id_valid <- !is.na(row$chat_id) && !is.na(suppressWarnings(as.integer(row$chat_id)))

                div(
                  class = "gallery-card animate-fadeIn",
                  id = card_id,
                  title = tooltip_text,
                  div(
                    class = "gallery-card-image-wrapper",
                    onclick = if (chat_id_valid) {
                      sprintf(
                        "Shiny.setInputValue('%s', %s, {priority: 'event'});",
                        ns("navigate_to_chat"),
                        jsonlite::toJSON(
                          list(
                            chat_id = as.character(row$chat_id),
                            file_path = as.character(row$file_path)
                          ),
                          auto_unbox = TRUE
                        )
                      )
                    } else {
                      sprintf("showToast('Bu görselin ait olduğu söyleşi bilgisi bulunamadı.', 'warning');")
                    },
                    if (!is.null(img_b64)) {
                      tags$img(
                        src = img_b64,
                        alt = if (nzchar(desc_text)) desc_text else row$filename,
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
                      tags$span("Söyleşiye Git")
                    )
                  ),
                  # Açıklama metni (kart altında kısa özet)
                  if (nzchar(desc_text)) {
                    div(class = "gallery-card-description",
                      tags$p(
                        if (nchar(desc_text) > 80) paste0(substring(desc_text, 1, 80), "...") else desc_text
                      )
                    )
                  },
                  div(
                    class = "gallery-card-footer",
                    div(
                      class = "gallery-card-info",
                      tags$span(class = "gallery-card-date", created_str),
                      tags$span(class = "gallery-card-size", paste0(file_size_kb, " KB"))
                    ),
					tags$button(
                      type = "button",
                      class = "gallery-delete-btn",
                      title = "Görseli Sil",
                      onclick = sprintf(
                        "event.stopPropagation(); Shiny.setInputValue('%s', %s, {priority: 'event'});",
                        ns("delete_image_request"),
                        jsonlite::toJSON(
                          list(
                            file_path = as.character(row$file_path),
                            chat_id = as.character(row$chat_id),
                            filename = as.character(row$filename)
                          ),
                          auto_unbox = TRUE
                        )
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

    # NOT: gallery_content bilinçli olarak suspendWhenHidden varsayılanında
    # (TRUE) bırakılır. Aksi halde tüm galeri kartları (her görselin base64
    # gövdesi dahil) galeri sayfası hiç açılmadan soğuk açılışta render edilip
    # websocket üzerinden gönderiliyordu; bu, açılıştaki en büyük gizli
    # maliyetlerden biriydi. Sekme ilk açıldığında Shiny render'ı otomatik başlatır.

    observeEvent(input$delete_image_request, {
      req(input$delete_image_request)
      info <- input$delete_image_request
      fname <- info$filename %||% "Bu görsel"

      showModal(modalDialog(
        title = "Görseli Sil",
        paste0("'", fname, "' görselini silmek istediğinizden emin misiniz? İlgili söyleşideki mesajda görselin silindiği belirtilecektir."),
        footer = tagList(
          actionButton(ns("confirm_delete_image"), "Evet, Sil", class = "btn-modern btn-danger"),
          tags$button("İptal", type = "button", class = "btn-modern btn-success", `data-dismiss` = "modal", `data-bs-dismiss` = "modal")
        ),
        easyClose = TRUE
      ))
    })

    observeEvent(input$confirm_delete_image, {
      info <- input$delete_image_request
      removeModal()
      req(info$file_path)

      success <- delete_single_image(info$file_path, effective_user_id(), info$chat_id)
      if (success) {
        showToast(session, "Görsel silindi.", "warning")
        delete_image_trigger(list(file_path = info$file_path, chat_id = info$chat_id))
        refresh_trigger(refresh_trigger() + 1)
      } else {
        showToast(session, "Görsel silinemedi.", "error")
      }
    })

    observeEvent(input$clear_all_images, {
      imgs <- filtered_images()
      if (nrow(imgs) > 0) {
        showModal(modalDialog(
          title = "Tüm Görselleri Sil",
          sprintf("Toplam %d görselinizi silmek istediğinizden emin misiniz? Bu işlem geri alınamaz. İlgili söyleşilerdeki mesajlarda görsellerin silindiği belirtilecektir.", nrow(cached_images())),
          footer = tagList(
            actionButton(ns("confirm_clear_all_images"), "Evet, Tümünü Sil", class = "btn-modern btn-danger"),
            tags$button("İptal", type = "button", class = "btn-modern btn-success", `data-dismiss` = "modal", `data-bs-dismiss` = "modal")
          ),
          easyClose = TRUE
        ))
      } else {
        showToast(session, "Silinecek görsel yok.", "info")
      }
    })

    observeEvent(input$confirm_clear_all_images, {
      removeModal()
      deleted_count <- delete_all_user_images(effective_user_id())
      clear_all_trigger(clear_all_trigger() + 1)
      refresh_trigger(refresh_trigger() + 1)
      current_page(1)
      showToast(session, sprintf("%d görsel silindi.", deleted_count), "warning")
    })

    observeEvent(input$navigate_to_chat, {
      req(input$navigate_to_chat)
      navigate_to_chat_trigger(input$navigate_to_chat)
    })

    observeEvent(input$refresh_gallery, {
      # Navigasyon gözlemcisi bu input'a Unix zaman damgası gönderir; bu durumda
      # başlangıç/sekme geçişinde görünür zorunlu re-render yapma. Kullanıcının
      # gerçek Yenile düğmesi ise actionButton sayacı (küçük integer) olarak gelir
      # ve bilinçli bir ekran tazelemesi ister.
      from_navigation <- is.numeric(input$refresh_gallery) &&
        length(input$refresh_gallery) == 1L &&
        is.finite(input$refresh_gallery) &&
        input$refresh_gallery > 1000000000

      # Sayfa açılışı veya manuel yenileme: tembel galeri artık etkin.
      gallery_activated(TRUE)

      if (isTRUE(from_navigation)) {
        refresh_trigger(refresh_trigger() + 1)
      } else {
        refresh_gallery_cache(force = TRUE)
        showToast(session, "Galeri yenileniyor...", "info")
      }
    })

    return(list(
      delete_image = delete_image_trigger,
      clear_all_images = clear_all_trigger,
      navigate_to_chat = navigate_to_chat_trigger,
      refresh = function() refresh_trigger(refresh_trigger() + 1)
    ))
  })
}