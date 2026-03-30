# ==============================================================================
# Dosya Yolu: R/module_claude_code_klasor.R
# Açıklama: Claude Code sayfasındaki sunucu taraflı klasör tarayıcı (modal)
#           işlevselliğini barındırır. Klasör seçme, gezinme, üst dizine çıkma
#           ve seçimi onaylama gözlemcilerini içerir. module_claude_code.R
#           sunucu fonksiyonu tarafından çağrılır.
# ==============================================================================

#' Klasör Tarayıcı Gözlemcilerini Başlat
#'
#' Sunucu taraflı klasör tarayıcı modal penceresi için gerekli tüm
#' gözlemcileri (observer) kayıt eder. Klasör açma, gezinme, üst dizin
#' ve seçim onaylama işlemlerini yönetir.
#'
#' @param input Shiny input nesnesi
#' @param output Shiny output nesnesi
#' @param session Shiny session nesnesi
#' @param ns Ad alanı fonksiyonu (session$ns)
#' @param rv_browser Klasör tarayıcı reaktif değerleri (current_path, history)
#' @return invisible(NULL)
init_klasor_gezgini_observers <- function(input, output, session, ns, rv_browser) {

  # --- Kullanıcının ana dizinini belirle (SSO modunda kullanıcı profilini kullan) ---
  resolve_user_home <- function() {
    # SSO modunda oturum açmış kullanıcının profil dizinini kullan
    if (isTRUE(SSO_ENABLED)) {
      kullanici <- session$userData$system_username
      if (!is.null(kullanici) && nzchar(kullanici)) {
        if (.Platform$OS.type == "windows") {
          profil <- file.path("C:/Users", kullanici)
          if (dir.exists(profil)) return(normalizePath(profil, winslash = "/"))
        } else {
          profil <- file.path("/home", kullanici)
          if (dir.exists(profil)) return(normalizePath(profil))
        }
      }
    }
    # Varsayılan: R sürecinin ana dizini
    if (.Platform$OS.type == "windows") {
      Sys.getenv("USERPROFILE", "C:/")
    } else {
      Sys.getenv("HOME", "/")
    }
  }

  # --- Klasör tarayıcı modalını aç ---
  observeEvent(input$open_folder_browser, {
    # Mevcut çalışma dizininden başla veya kullanıcının ana dizininden
    baslangic <- input$workdir
    if (is.null(baslangic) || !nzchar(baslangic) || !dir.exists(baslangic)) {
      baslangic <- resolve_user_home()
    }
    rv_browser$current_path <- normalizePath(baslangic, winslash = "/", mustWork = FALSE)

    # SSO modunda sunucu dosya sistemi uyarısı göster
    sunucu_uyarisi <- if (isTRUE(SSO_ENABLED)) {
      tags$div(
        class = "cc-fb-server-notice",
        style = "background: #2a2a3e; border: 1px solid #4a4a6a; border-radius: 6px; padding: 8px 12px; margin-bottom: 10px; font-size: 12px; color: #b0b0d0;",
        icon("server"), " ",
        "Bu tarayıcı sunucu dosya sistemini gösterir. Claude Code komutları sunucuda çalışır."
      )
    }

    showModal(modalDialog(
      title = tagList(icon("folder-tree"), "Klasör Seçici"),
      size = "m",
      easyClose = TRUE,
      div(
        class = "cc-folder-browser",
        sunucu_uyarisi,
        # Mevcut yol göstergesi
        div(
          class = "cc-fb-path-bar",
          actionButton(ns("fb_go_up"), label = NULL, icon = icon("arrow-up"),
                      class = "btn-sm", title = "Üst dizine git"),
          tags$span(id = ns("fb_current_path"), class = "cc-fb-path-text")
        ),
        # Klasör listesi
        div(class = "cc-fb-list-container",
          uiOutput(ns("fb_folder_list"))
        )
      ),
      footer = tagList(
        actionButton(ns("fb_select"), "Bu Klasörü Seç",
                    class = "btn-primary", icon = icon("check")),
        modalButton("İptal")
      )
    ))
  })

  # --- Klasör tarayıcı yol göstergesini ve listeyi güncelle ---
  observe({
    req(rv_browser$current_path)
    yol <- rv_browser$current_path

    # Yol göstergesini güncelle
    shinyjs::runjs(sprintf(
      "var el = document.getElementById('%s'); if(el) el.textContent = '%s';",
      ns("fb_current_path"),
      gsub("\\\\", "\\\\\\\\", gsub("'", "\\\\'", yol))
    ))

    # Klasörleri listele
    output$fb_folder_list <- renderUI({
      if (!dir.exists(yol)) {
        return(tags$p(class = "cc-dir-error", paste0("Dizin bulunamadı: ", yol)))
      }
      dosyalar <- tryCatch({
        list.dirs(yol, full.names = TRUE, recursive = FALSE)
      }, error = function(e) character(0))

      if (length(dosyalar) == 0) {
        return(tags$p(class = "cc-dir-empty", "Alt klasör bulunamadı."))
      }

      # En fazla 100 klasör göster
      dosyalar <- head(dosyalar, 100)

      tags$div(
        class = "cc-fb-folder-list",
        lapply(dosyalar, function(d) {
          klasor_adi <- basename(d)
          tam_yol <- normalizePath(d, winslash = "/", mustWork = FALSE)
          tags$div(
            class = "cc-dir-item cc-dir-klasor cc-dir-clickable",
            onclick = sprintf(
              "Shiny.setInputValue('%s', '%s', {priority: 'event'});",
              ns("fb_navigate"),
              gsub("'", "\\\\'", tam_yol)
            ),
            icon("folder"),
            tags$span(class = "cc-dir-name", klasor_adi)
          )
        })
      )
    })
  })

  # --- Klasör tarayıcıda gezinme ---
  observeEvent(input$fb_navigate, {
    req(input$fb_navigate)
    yeni_yol <- input$fb_navigate
    if (dir.exists(yeni_yol)) {
      rv_browser$current_path <- normalizePath(yeni_yol, winslash = "/", mustWork = FALSE)
    }
  })

  # --- Üst dizine git ---
  observeEvent(input$fb_go_up, {
    req(rv_browser$current_path)
    ust <- dirname(rv_browser$current_path)
    if (dir.exists(ust) && ust != rv_browser$current_path) {
      rv_browser$current_path <- normalizePath(ust, winslash = "/", mustWork = FALSE)
    }
  })

  # --- Seçimi onayla ---
  observeEvent(input$fb_select, {
    req(rv_browser$current_path)
    updateTextInput(session, "workdir", value = rv_browser$current_path)
    removeModal()
  })

  invisible(NULL)
}