# Dosya Yolu: R/module_destek_geri_bildirim.R
# Açıklama: Geri Bildirim & Hata Bildirimi alt sayfası modülü.
#            İki sekmeli yapıda (Geri Bildirim / Hata Bildir) form yönetimi,
#            dosya yükleme ve veritabanına kaydetme işlemlerini yönetir.

# ==============================================================================
# GERİ BİLDİRİM & HATA UI
# ==============================================================================

destekGeriBildirimUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-feedback-container",
      # Başlık
      div(
        class = "destek-section-header",
        div(class = "destek-section-icon destek-icon-pulse",
          icon("comment-dots")
        ),
        h3("Geri Bildirim & Hata Bildirimi"),
        p(
          class = "destek-section-desc",
          "Görüşleriniz bizim için çok değerli. Geri bildirimleriniz ve hata raporlarınız, ürünümüzü geliştirmemize yardımcı olur."
        )
      ),

      # Sekme butonları
      div(
        class = "destek-tabs",
        div(
          id = ns("tab_btn_geri_bildirim"),
          class = "destek-tab-btn active",
          onclick = sprintf("Shiny.setInputValue('%s', 'geri_bildirim', {priority: 'event'})", ns("aktif_sekme")),
          div(class = "destek-tab-icon-wrapper",
            icon("star", class = "destek-tab-icon-star")
          ),
          span("Geri Bildirim")
        ),
        div(
          id = ns("tab_btn_hata"),
          class = "destek-tab-btn",
          onclick = sprintf("Shiny.setInputValue('%s', 'hata', {priority: 'event'})", ns("aktif_sekme")),
          div(class = "destek-tab-icon-wrapper",
            icon("bug", class = "destek-tab-icon-bug")
          ),
          span("Hata Bildir")
        )
      ),

      # ================================================================
      # SEKME 1: GERİ BİLDİRİM FORMU
      # ================================================================
      div(
        id = ns("sekme_geri_bildirim"),
        class = "destek-tab-content active",
        div(
          class = "destek-form-card",

          # Memnuniyet Puanı (Zorunlu)
          div(
            class = "destek-form-group",
            tags$label(
              class = "destek-form-label destek-label-required",
              "Genel Memnuniyet"
            ),
            div(
              class = "destek-satisfaction-selector",
              id = ns("satisfaction_container"),
              lapply(1:5, function(i) {
                emojiler <- c(
                  "\U0001F621", # 1 - Çok Kötü
                  "\U0001F615", # 2 - Kötü
                  "\U0001F610", # 3 - Orta
                  "\U0001F642", # 4 - İyi
                  "\U0001F60D"  # 5 - Çok İyi
                )
                etiketler <- c(
                  "Çok Kötü",
                  "Kötü",
                  "Orta",
                  "İyi",
                  "Çok İyi"
                )
                div(
                  class = "destek-satisfaction-item",
                  `data-value` = i,
                  onclick = sprintf(
                    "destekSelectSatisfaction('%s', %d)",
                    ns("memnuniyet"), i
                  ),
                  span(class = "destek-emoji", emojiler[i]),
                  span(class = "destek-emoji-label", etiketler[i])
                )
              })
            ),
            # Gizli input (Shiny'ye değer gönderir)
            tags$input(
              type = "hidden",
              id = ns("memnuniyet"),
              name = ns("memnuniyet"),
              value = ""
            ),
            div(id = ns("hata_memnuniyet"), class = "destek-error-msg", style = "display:none;",
              icon("circle-exclamation"),
              "Lütfen genel memnuniyetinizi belirtin."
            )
          ),

          # NPS Puanı (Opsiyonel)
          div(
            class = "destek-form-group",
            tags$label(class = "destek-form-label",
              "Bizi bir arkadaşınıza veya meslektaşınıza tavsiye etme olasılığınız nedir?"
            ),
            div(
              class = "destek-nps-container",
              span(class = "destek-nps-label-left", "Kesinlikle hayır"),
              div(
                class = "destek-nps-buttons",
                id = ns("nps_container"),
                lapply(0:10, function(i) {
                  div(
                    class = "destek-nps-btn",
                    `data-value` = i,
                    onclick = sprintf(
                      "destekSelectNPS('%s', %d)",
                      ns("nps_puan"), i
                    ),
                    as.character(i)
                  )
                })
              ),
              span(class = "destek-nps-label-right", "Kesinlikle evet")
            ),
            tags$input(
              type = "hidden",
              id = ns("nps_puan"),
              name = ns("nps_puan"),
              value = ""
            )
          ),

          # Geri Bildirim Etiketleri (Opsiyonel) - Animasyonlu ikonlar
          div(
            class = "destek-form-group",
            tags$label(class = "destek-form-label", "Etiketler"),
            div(
              class = "destek-tags-container",
              id = ns("feedback_tags_container"),
              lapply(list(
                list(id = "yeni_ozellik", label = "Yeni Özellik İsteği", icon = "wand-magic-sparkles", renk = "indigo", anim = "sparkle"),
                list(id = "tasarim", label = "Tasarım Önerisi", icon = "palette", renk = "purple", anim = "palette"),
                list(id = "sikayet", label = "Şikayet", icon = "circle-exclamation", renk = "red", anim = "alert"),
                list(id = "performans", label = "Performans", icon = "bolt", renk = "amber", anim = "bolt"),
                list(id = "diger", label = "Diğer", icon = "ellipsis", renk = "cyan", anim = "dots")
              ), function(etiket) {
                div(
                  class = paste0("destek-tag-btn destek-tag-", etiket$renk),
                  `data-tag` = etiket$id,
                  onclick = sprintf(
                    "destekToggleTag(this, '%s')",
                    ns("secili_etiketler")
                  ),
                  div(class = paste0("destek-tag-icon-", etiket$anim),
                    icon(etiket$icon)
                  ),
                  span(etiket$label)
                )
              })
            ),
            tags$input(
              type = "hidden",
              id = ns("secili_etiketler"),
              name = ns("secili_etiketler"),
              value = ""
            )
          ),

          # En çok neyi sevdiniz? (Opsiyonel)
          div(
            class = "destek-form-group",
            tags$label(class = "destek-form-label", "En çok neyi sevdiniz?"),
            div(
              class = "destek-textarea-wrapper",
              tags$textarea(
                id = ns("en_cok_sevilen"),
                class = "destek-textarea",
                placeholder = "Deneyiminizle ilgili beğendiğiniz şeyleri paylaşın...",
                maxlength = "500",
                rows = 3,
                oninput = sprintf("destekUpdateCharCount(this, '%s')", ns("sevilen_counter"))
              ),
              span(id = ns("sevilen_counter"), class = "destek-char-counter", "0 / 500")
            )
          ),

          # Neyi geliştirebiliriz? (Opsiyonel)
          div(
            class = "destek-form-group",
            tags$label(class = "destek-form-label", "Neyi geliştirebiliriz?"),
            div(
              class = "destek-textarea-wrapper",
              tags$textarea(
                id = ns("gelistirme"),
                class = "destek-textarea",
                placeholder = "Geliştirmemizi istediğiniz alanları belirtin...",
                maxlength = "500",
                rows = 3,
                oninput = sprintf("destekUpdateCharCount(this, '%s')", ns("gelistirme_counter"))
              ),
              span(id = ns("gelistirme_counter"), class = "destek-char-counter", "0 / 500")
            )
          ),

          # İletişim izni
          div(
            class = "destek-form-group destek-checkbox-group",
            div(
              class = "destek-checkbox-wrapper",
              id = ns("iletisim_checkbox_wrapper"),
              onclick = sprintf("destekToggleCheckbox('%s')", ns("iletisim_izni")),
              div(
                class = "destek-checkbox",
                id = ns("iletisim_checkbox_visual"),
                icon("check", class = "destek-checkbox-icon")
              ),
              span(class = "destek-checkbox-label",
                "Geri bildirimimle ilgili benimle iletişime geçebilirsiniz."
              )
            ),
            tags$input(
              type = "hidden",
              id = ns("iletisim_izni"),
              name = ns("iletisim_izni"),
              value = "0"
            )
          ),

          # Gönder butonu
          div(
            class = "destek-form-actions",
            div(
              class = "destek-submit-wrapper",
              actionButton(
                ns("gonder_geri_bildirim"),
                label = tagList(icon("paper-plane"), "Gönder"),
                class = "destek-submit-btn",
                title = "Ctrl + Enter ile gönder"
              )
            )
          )
        )
      ),

      # ================================================================
      # SEKME 2: HATA BİLDİR FORMU
      # ================================================================
      div(
        id = ns("sekme_hata"),
        class = "destek-tab-content",
        style = "display: none;",
        # Hata Bildir alt modül UI'ı
        destekHataBildirUI(ns("hata_bildir_module"))
      ),

      # ================================================================
      # BAŞARI EKRANI
      # ================================================================
      div(
        id = ns("basari_ekrani"),
        class = "destek-success-screen",
        style = "display: none;",
        div(
          class = "destek-success-content",
          div(class = "destek-success-icon-wrapper",
            icon("circle-check", class = "destek-success-icon")
          ),
          h3("Teşekkür Ederiz"),
          p(
            id = ns("basari_mesaji"),
            class = "destek-success-message",
            "Değerli geri bildiriminiz için teşekkürler. Fikirleriniz, ürünümüzün geleceğini şekillendiriyor."
          )
        )
      )
    )
  )
}

# ==============================================================================
# GERİ BİLDİRİM & HATA SERVER
# ==============================================================================

destekGeriBildirimServer <- function(id, current_user_id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Hata Bildir alt modülünü başlat
    hata_result <- destekHataBildirServer("hata_bildir_module", current_user_id = current_user_id)

    # Sekme geçişi
    observeEvent(input$aktif_sekme, {
      sekmeler <- c("geri_bildirim", "hata")

      for (s in sekmeler) {
        shinyjs::hide(paste0("sekme_", s))
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').classList.remove('active');",
          ns(paste0("tab_btn_", s))
        ))
      }

      shinyjs::show(paste0("sekme_", input$aktif_sekme))
      shinyjs::runjs(sprintf(
        "document.getElementById('%s').classList.add('active');",
        ns(paste0("tab_btn_", input$aktif_sekme))
      ))
    }, ignoreInit = TRUE)

    # Geri bildirim formu gönderimi
    observeEvent(input$gonder_geri_bildirim, {
      # Memnuniyet doğrulama
      memnuniyet <- input$memnuniyet
      if (is.null(memnuniyet) || memnuniyet == "" || memnuniyet == "0") {
        shinyjs::show("hata_memnuniyet")
        return(invisible(NULL))
      }
      shinyjs::hide("hata_memnuniyet")

      # Verileri topla
      nps <- input$nps_puan
      etiketler <- input$secili_etiketler
      sevilen <- input$en_cok_sevilen
      gelistirme_metin <- input$gelistirme

      # İletişim izni: "1" ise TRUE, diğer tüm durumlar FALSE
      iletisim_degeri <- input$iletisim_izni
      iletisim <- identical(as.character(iletisim_degeri), "1")

      # Veritabanına kaydet
      tryCatch({
        destek_geri_bildirim_kaydet(
          user_id = current_user_id,
          memnuniyet = as.integer(memnuniyet),
          nps_puan = if (!is.null(nps) && nps != "") as.integer(nps) else NULL,
          etiketler = if (!is.null(etiketler) && etiketler != "") etiketler else NULL,
          en_cok_sevilen = if (!is.null(sevilen) && nzchar(sevilen)) sevilen else NULL,
          gelistirme = if (!is.null(gelistirme_metin) && nzchar(gelistirme_metin)) gelistirme_metin else NULL,
          iletisim_izni = iletisim
        )

        # Başarı ekranını göster
        shinyjs::runjs(sprintf(
          "document.getElementById('%s').textContent = 'Değerli geri bildiriminiz için teşekkürler. Fikirleriniz, ürünümüzün geleceğini şekillendiriyor.';",
          ns("basari_mesaji")
        ))
        shinyjs::hide("sekme_geri_bildirim")
        shinyjs::hide("sekme_hata")
        shinyjs::show("basari_ekrani")

        # 4 saniye sonra formu sıfırla
        shinyjs::delay(4000, {
          shinyjs::hide("basari_ekrani")
          shinyjs::show("sekme_geri_bildirim")
          # Formu sıfırla (JS ile)
          shinyjs::runjs(sprintf("destekResetFeedbackForm('%s');", ns("")))
        })

      }, error = function(e) {
        cat("[DESTEK] Geri bildirim kaydedilemedi:", conditionMessage(e), "\n")
        showToast(session, "Geri bildirim kaydedilemedi. Lütfen tekrar deneyin.", "error")
      })
    })

    # Hata bildirimi başarılı gönderildiğinde
    observeEvent(hata_result$basarili(), {
      req(hata_result$basarili() > 0)

      shinyjs::runjs(sprintf(
        "document.getElementById('%s').textContent = 'Hata bildiriminiz başarıyla sistemimize kaydedildi. Ekibimiz en kısa sürede inceleyecektir.';",
        ns("basari_mesaji")
      ))
      shinyjs::hide("sekme_geri_bildirim")
      shinyjs::hide("sekme_hata")
      shinyjs::show("basari_ekrani")

      shinyjs::delay(4000, {
        shinyjs::hide("basari_ekrani")
        shinyjs::show("sekme_hata")
      })
    }, ignoreInit = TRUE)

    invisible(NULL)
  })
}
