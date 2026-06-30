# ==============================================================================
# Dosya Yolu: R/module_admin_documentation.R
# Açıklama: Yönetici paneli "Dokümantasyon" sayfası (Shiny modülü).
#            Yöneticilerin depo belgelerini (README, RUNBOOK, docs/* vb.) canlı
#            uygulama içinde, tema-duyarlı ve okunaklı bir arayüzde salt okunur
#            biçimde görüntülemesini sağlar.
#
#            - Üst düzey gruplar admin_page_layout pills'leriyle gösterilir.
#            - Her grupta belge seçici kartlar (mb-doc-card) bulunur.
#            - Seçilen belge zengin metin (Markdown -> güvenli HTML) olarak
#              render edilir; başlıklardan İçindekiler (TOC) üretilir.
#            - Saf yardımcılar R/helpers_admin_documentation.R içindedir.
#            - Belge seçimi/TOC kaydırma davranışı www/js/admin_documentation.js
#              dosyasındadır; stiller www/css/admin_documentation.css içindedir.
# ==============================================================================

# ==============================================================================
# UI FONKSİYONU
# ==============================================================================

adminDokumantasyonUI <- function(id) {
  ns <- NS(id)

  admin_page_layout(
    ns = ns,
    page_title = "Dokümantasyon",
    page_icon = "book",
    tab_panels = admin_doc_group_tab_panels()
  )
}

# Üst düzey grup sekmelerini (pills) kayıt defterinden üretir.
admin_doc_group_tab_panels <- function() {
  lapply(admin_doc_registry(), function(g) {
    tabPanel(
      title = tags$span(
        title = g$title,
        tagList(icon(g$icon %||% "book"), paste0(" ", g$title))
      ),
      value = g$id
    )
  })
}

# Bir grup için belge seçici kartlarını üretir (saf UI, test edilebilir).
admin_doc_card_list_ui <- function(ns, docs, selected_doc_id) {
  div(
    class = "mb-doc-card-list",
    `data-doc-input` = ns("doc_select"),
    role = "tablist",
    `aria-label` = "Belge seç",
    lapply(docs, function(d) {
      active <- identical(d$id, selected_doc_id)
      tags$button(
        type = "button",
        class = paste("mb-doc-card", if (active) "mb-doc-card-active" else ""),
        `data-doc-id` = d$id,
        `aria-pressed` = if (active) "true" else "false",
        div(class = "mb-doc-card-title", d$title),
        div(class = "mb-doc-card-desc", d$desc %||% "")
      )
    })
  )
}

# İçindekiler (TOC) listesini üretir. Okunabilirlik için 1-3. seviye gösterilir.
admin_doc_toc_ui <- function(ns, toc) {
  has_items <- !is.null(toc) && length(toc) > 0L

  shown <- list()
  if (has_items) {
    shown <- Filter(function(item) {
      lvl <- suppressWarnings(as.integer(item$level))
      !is.na(lvl) && lvl >= 1L && lvl <= 3L
    }, toc)
  }

  tags$nav(
    class = "mb-doc-toc",
    `aria-label` = "İçindekiler",
    div(class = "mb-doc-toc-title", icon("list-ul"), tags$span("İçindekiler")),
    if (length(shown) == 0L) {
      tags$p(class = "mb-doc-toc-empty", "Bu belgede başlık bulunamadı.")
    } else {
      tags$ul(
        class = "mb-doc-toc-list",
        lapply(shown, function(item) {
          lvl <- max(1L, min(3L, as.integer(item$level)))
          tags$li(
            class = paste0("mb-doc-toc-item mb-doc-toc-lvl", lvl),
            tags$a(
              class = "mb-doc-toc-link",
              href = "#",
              `data-target-id` = item$id,
              item$text
            )
          )
        })
      )
    }
  )
}

# Seçili grup + belge için tüm içerik alanını kurar (saf UI, test edilebilir).
admin_doc_build_content_ui <- function(ns, group_id, selected_doc_id, render) {
  docs <- admin_doc_docs_in_group(group_id)
  ids <- vapply(docs, function(d) d$id, character(1))
  if (length(ids) && !(selected_doc_id %in% ids)) {
    selected_doc_id <- ids[1]
  }

  ok <- isTRUE(render$ok)

  div(
    class = "mb-doc-wrapper",
    # Belge kartları + İçindekiler araç çubuğu, kaydırma sırasında üstte sabit
    # kalsın diye tek bir yapışkan (sticky) başlık kabında gruplanır; belge
    # gövdesi bu sabit alanın altında kayar (admin sekme şeridi mantığı).
    div(
      class = "mb-doc-sticky-head",
      admin_doc_card_list_ui(ns, docs, selected_doc_id),
      div(
        class = "mb-doc-toolbar",
        tags$button(
          type = "button",
          class = "btn-modern mb-doc-toc-toggle",
          `aria-label` = "İçindekiler panelini aç/kapat",
          icon("list-ul"),
          tags$span("İçindekiler")
        ),
        tags$span(
          class = "mb-doc-source",
          icon("file-lines"),
          tags$span("Kaynak dosya: "),
          tags$code(render$source %||% "")
        )
      )
    ),
    div(
      class = "mb-doc-layout",
      admin_doc_toc_ui(ns, render$toc),
      div(
        class = "mb-doc-body-wrap",
        if (ok) {
          div(
            id = ns("doc_body"),
            class = "mb-doc-body markdown-body",
            HTML(render$html %||% "")
          )
        } else {
          div(
            class = "mb-doc-empty",
            icon("triangle-exclamation"),
            tags$p(render$message %||% "Belge görüntülenemiyor.")
          )
        },
        div(
          class = "mb-doc-readonly-note",
          icon("lock"),
          tags$span("Bu belge canlı uygulama içinde salt okunur olarak gösterilir.")
        )
      )
    )
  )
}

# ==============================================================================
# SERVER FONKSİYONU
# ==============================================================================

adminDokumantasyonServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Çalışma zamanında repo kökü (belge dosyaları için)
    repo_root <- admin_doc_repo_root()

    # Render önbelleği: doc_id -> render sonucu (büyük belgeler tek kez render edilir)
    render_cache <- new.env(parent = emptyenv())

    # Reaktif durum
    selected_doc <- reactiveVal(admin_doc_default_doc_id())
    refresh_token <- reactiveVal(0L)

    send_timestamp <- function() {
      session$sendCustomMessage("updateAdminTimestamp", list(
        id = ns("admin_last_update"),
        time = format(Sys.time(), "%d.%m.%Y %H:%M:%S")
      ))
    }

    # İlk yüklemede son güncelleme zamanını gönder (kardeş admin sayfalarıyla uyumlu)
    if (is.function(session$onFlushed)) {
      session$onFlushed(function() send_timestamp(), once = TRUE)
    }

    # Grup (pills) değişince, mevcut seçim o grupta değilse ilk belgeye geç
    observeEvent(input$admin_tabs, {
      grp <- input$admin_tabs
      docs <- admin_doc_docs_in_group(grp)
      if (length(docs)) {
        ids <- vapply(docs, function(d) d$id, character(1))
        if (!(selected_doc() %in% ids)) {
          selected_doc(ids[1])
        }
      }
    }, ignoreInit = FALSE)

    # Belge kartı seçimi (tarayıcı tarafı JS -> doc_select). Yalnızca izin listeli
    # kimlik kabul edilir; rastgele yol/girdi reddedilir.
    observeEvent(input$doc_select, {
      did <- input$doc_select
      if (is.character(did) && length(did) == 1L && nzchar(did) &&
          admin_doc_is_known(did)) {
        selected_doc(did)
      }
    }, ignoreInit = TRUE)

    # Yenile: önbelleği temizle, belgeyi diskten tekrar oku, zaman damgasını yenile
    observeEvent(input$refresh_analytics, {
      if (requireNamespace("shinyjs", quietly = TRUE)) {
        shinyjs::runjs("$('.tooltip').remove();")
      }
      keys <- ls(render_cache)
      if (length(keys)) rm(list = keys, envir = render_cache)
      refresh_token(refresh_token() + 1L)
      send_timestamp()
      showToast(session, "Dokümantasyon yenilendi", "success")
    }, ignoreInit = TRUE)

    # Seçili belgeyi render eder (önbellekli; yenile jetonu önbelleği geçersiz kılar)
    current_render <- reactive({
      refresh_token()
      did <- selected_doc()
      req(did)

      cached <- render_cache[[did]]
      if (!is.null(cached)) return(cached)

      res <- admin_doc_render_document(did, repo_root)
      render_cache[[did]] <- res
      res
    })

    # İçerik alanı
    output$tab_content_area <- renderUI({
      grp <- input$admin_tabs
      if (is.null(grp)) grp <- admin_doc_default_group_id()
      admin_doc_build_content_ui(ns, grp, selected_doc(), current_render())
    })
  })
}
