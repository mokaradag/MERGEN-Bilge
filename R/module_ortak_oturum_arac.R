# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_arac.R
# Açıklama: Ortak Oturum ARAÇ SEÇİCİ UI katmanı ve sunucu bağlayıcısı: zengin
#           açılır menü (araç listesi + araç-özel ayarlar: Derin Düşünme,
#           Detay Seviyesi, Süreç Akışı), aktif araç rozeti ve araç etkinken
#           model kilidi. Saf karar/plan yardımcıları
#           R/helpers_ortak_oturum_arac.R içindedir ve bu dosyadan ÖNCE yüklenir.
#
# Sözleşmeler:
#   * Tekil oturumdaki belge/araç uyumluluk kontrolü Ortak Söyleşi'de
#     UYGULANMAZ (bilinçli ürün kararı): seçili ortak belgeler araç ne olursa
#     olsun bağlama eklenebilir.
#   * Araç etkinken model seçimi kilitlenir; araç kendi modelini kullanır.
#     Araç temizlenince oda model seçimi geri gelir.
#   * Ayar girdileri kontrolsüz DOM girdileridir; değişimler delege JS
#     köprüsüyle sunucuya yazılır ve açık menüyü kapatan yeniden çizim
#     TETİKLENMEZ. Kimlikler CSS seçicisine gömülmez.
# ==============================================================================

# Açılır menü içindeki araç-özel ayar blokları (SAF HTML). Ayar girdileri
# kontrolsüz (uncontrolled) DOM girdileridir; değişiklikler delege JS
# köprüsüyle (data-oo-arac-ayar) ayar_input_id'ye {alan, deger} yazar.
# Girdi kimlikleri CSS seçicisine gömülmez.
.oo_arac_ayar_bloklari_html <- function(giris, ayarlar, ayar_input_id, akislar = list()) {
  if (is.null(giris) || !any(c(giris$derin_var, giris$akis_var))) {
    return(NULL)
  }

  bloklar <- tagList()

  if (isTRUE(giris$derin_var)) {
    bloklar <- tagList(
      bloklar,
      tags$label(
        class = "oo-arac-ayar-satiri",
        tags$input(
          type = "checkbox",
          class = "oo-arac-ayar-kutu",
          `data-oo-arac-ayar` = "1",
          `data-oo-alan` = "derin",
          `data-oo-hedef-input` = ayar_input_id,
          checked = if (isTRUE(ayarlar$derin)) "checked" else NULL
        ),
        tags$span(class = "oo-arac-ayar-etiket", "Derin Düşünme"),
        tags$small(
          class = "oo-arac-ayar-alt",
          if (isTRUE(giris$detay_var)) "Çoklu sorgu analizi" else "Derin düşünme modeli"
        )
      )
    )
  }

  if (isTRUE(giris$detay_var)) {
    bloklar <- tagList(
      bloklar,
      tags$label(
        class = "oo-arac-ayar-satiri",
        tags$span(class = "oo-arac-ayar-etiket", "Detay Seviyesi"),
        tags$select(
          class = "oo-arac-ayar-secim",
          `data-oo-arac-ayar` = "1",
          `data-oo-alan` = "detay",
          `data-oo-hedef-input` = ayar_input_id,
          tags$option(value = "ozet", selected = if (identical(ayarlar$detay, "ozet")) "selected" else NULL, "Özet"),
          tags$option(value = "standart", selected = if (identical(ayarlar$detay, "standart")) "selected" else NULL, "Standart"),
          tags$option(value = "detayli", selected = if (identical(ayarlar$detay, "detayli")) "selected" else NULL, "Detaylı")
        )
      )
    )
  }

  if (isTRUE(giris$seviye_var)) {
    bloklar <- tagList(
      bloklar,
      tags$label(
        class = "oo-arac-ayar-satiri",
        tags$span(class = "oo-arac-ayar-etiket", "Düşünme Seviyesi"),
        tags$select(
          class = "oo-arac-ayar-secim",
          `data-oo-arac-ayar` = "1",
          `data-oo-alan` = "seviye",
          `data-oo-hedef-input` = ayar_input_id,
          tags$option(value = "low", selected = if (!identical(ayarlar$seviye, "high")) "selected" else NULL, "Düşük (Hızlı)"),
          tags$option(value = "high", selected = if (identical(ayarlar$seviye, "high")) "selected" else NULL, "Yüksek (Derin)")
        )
      )
    )
  }

  if (isTRUE(giris$akis_var) && length(akislar) > 0L) {
    secili_akis <- as.character(ayarlar$surec_akisi %||% "")[1]
    bloklar <- tagList(
      bloklar,
      tags$label(
        class = "oo-arac-ayar-satiri",
        tags$span(class = "oo-arac-ayar-etiket", "Süreç Akışı"),
        tags$select(
          class = "oo-arac-ayar-secim",
          `data-oo-arac-ayar` = "1",
          `data-oo-alan` = "surec_akisi",
          `data-oo-hedef-input` = ayar_input_id,
          lapply(akislar, function(fl) {
            anahtar <- as.character(fl$key %||% "")[1]
            tags$option(
              value = anahtar,
              selected = if (identical(anahtar, secili_akis)) "selected" else NULL,
              HTML(htmltools::htmlEscape(as.character(fl$name %||% anahtar)[1]))
            )
          })
        )
      )
    )
  }

  div(
    class = "oo-arac-ayarlar",
    div(class = "oo-arac-ayarlar-baslik", tagList(icon("sliders"), span("Araç Ayarları"))),
    bloklar
  )
}

# Araç seçici (SAF): "Model Değiştir" diliyle aynı açılır bileşen. Araç listesi
# + aktif aracın ayar blokları + "Araç Kullanma" seçeneği. Tüm görünen metin
# escape edilir; family değerleri JS string literaline (toJSON) kodlanır.
oo_arac_secici_html <- function(katalog,
                                ayarlar,
                                dropdown_id,
                                secim_input_id,
                                ayar_input_id,
                                akislar = list()) {
  secili_family <- as.character(ayarlar$family %||% "")[1]
  aktif_giris <- NULL
  for (giris in katalog) {
    if (identical(giris$family, secili_family)) {
      aktif_giris <- giris
    }
  }

  temizle_ogesi <- tags$li(tags$a(
    class = paste0("dropdown-item model-option oo-arac-option", if (!nzchar(secili_family)) " active" else ""),
    href = "#",
    title = "Araç kullanmadan standart ortak söyleşi",
    onclick = sprintf(
      "Shiny.setInputValue(%s, %s, {priority:'event'}); return false;",
      jsonlite::toJSON(as.character(secim_input_id), auto_unbox = TRUE),
      jsonlite::toJSON("", auto_unbox = TRUE)
    ),
    div(
      class = "model-item-content",
      div(
        class = "oo-arac-oge",
        tags$span(class = "oo-arac-ikon", icon("comment")),
        div(
          class = "oo-arac-metin",
          span(class = "model-name", "Araç Kullanma"),
          tags$small(class = "oo-arac-alt", "Standart ortak söyleşi")
        )
      ),
      if (!nzchar(secili_family)) icon("check", class = "selected-icon") else NULL
    )
  ))

  ogeler <- lapply(katalog, function(giris) {
    aktif <- identical(giris$family, secili_family)
    devre_disi <- !isTRUE(giris$destekleniyor)

    tags$li(tags$a(
      class = paste0(
        "dropdown-item model-option oo-arac-option",
        if (aktif) " active" else "",
        if (devre_disi) " oo-arac-devredisi" else ""
      ),
      href = "#",
      title = if (devre_disi) {
        paste0(giris$baslik, " ortak oturumlarda desteklenmez")
      } else {
        giris$aciklama
      },
      onclick = if (devre_disi) {
        "return false;"
      } else {
        sprintf(
          "Shiny.setInputValue(%s, %s, {priority:'event'}); return false;",
          jsonlite::toJSON(as.character(secim_input_id), auto_unbox = TRUE),
          jsonlite::toJSON(as.character(giris$family), auto_unbox = TRUE)
        )
      },
      div(
        class = "model-item-content",
        div(
          class = "oo-arac-oge",
          tags$span(
            class = "oo-arac-ikon",
            style = sprintf("color:%s;", htmltools::htmlEscape(giris$renk, attribute = TRUE)),
            icon(giris$ikon)
          ),
          div(
            class = "oo-arac-metin",
            span(class = "model-name", HTML(htmltools::htmlEscape(giris$baslik))),
            tags$small(
              class = "oo-arac-alt",
              HTML(htmltools::htmlEscape(
                if (devre_disi) "Ortak oturumlarda desteklenmez" else giris$aciklama
              ))
            )
          )
        ),
        if (aktif) icon("check", class = "selected-icon") else NULL
      )
    ))
  })

  div(
    class = "oo-secici oo-secici-arac",
    title = "Yapay zekâ sorusunda kullanılacak analiz aracını seç",
    shinyWidgets::dropdown(
      inputId = dropdown_id,
      style = "minimal",
      icon = icon("toolbox"),
      status = "default",
      up = FALSE,
      width = "320px",
      div(class = "dropdown-menu-header", icon("screwdriver-wrench"), tags$span("Analiz Araçları")),
      tags$ul(class = "dropdown-menu-custom-list oo-arac-listesi", temizle_ogesi, ogeler),
      .oo_arac_ayar_bloklari_html(aktif_giris, ayarlar, ayar_input_id, akislar = akislar)
    ),
    tags$span(
      class = "oo-secici-etiket",
      `aria-label` = "Seçili araç",
      if (!is.null(aktif_giris)) {
        HTML(htmltools::htmlEscape(aktif_giris$baslik))
      } else {
        "Araç Yok"
      }
    )
  )
}

# Aktif araç rozeti (SAF): ikon + başlık + ayar özeti + temizleme düğmesi.
# Araç yoksa NULL döner.
oo_arac_rozet_html <- function(katalog, ayarlar, temizle_input_id) {
  secili_family <- as.character(ayarlar$family %||% "")[1]
  if (!nzchar(secili_family)) {
    return(NULL)
  }

  aktif_giris <- NULL
  for (giris in katalog) {
    if (identical(giris$family, secili_family)) {
      aktif_giris <- giris
    }
  }
  if (is.null(aktif_giris)) {
    return(NULL)
  }

  ozet <- oo_arac_ayar_ozeti(ayarlar)

  tags$span(
    class = "oo-arac-rozet",
    style = sprintf("--oo-arac-renk:%s;", htmltools::htmlEscape(aktif_giris$renk, attribute = TRUE)),
    title = paste0("Aktif araç: ", aktif_giris$baslik, if (nzchar(ozet)) paste0(" (", ozet, ")") else ""),
    tags$span(class = "oo-arac-rozet-ikon", icon(aktif_giris$ikon)),
    tags$span(class = "oo-arac-rozet-ad", HTML(htmltools::htmlEscape(aktif_giris$baslik))),
    if (nzchar(ozet)) {
      tags$span(class = "oo-arac-rozet-ozet", HTML(htmltools::htmlEscape(ozet)))
    } else {
      NULL
    },
    tags$button(
      type = "button",
      class = "oo-arac-rozet-temizle",
      `data-oo-arac-temizle` = "1",
      `data-oo-hedef-input` = temizle_input_id,
      `aria-label` = "Aracı temizle ve standart söyleşiye dön",
      title = "Aracı temizle",
      HTML("&times;")
    )
  )
}

# ------------------------------------------------------------------------------
# SUNUCU BAĞLAYICISI
# ------------------------------------------------------------------------------

# Araç seçici + model kilidi sunucu bağlayıcısı. Oda sunucu modülünden
# (R/module_ortak_oturum_room.R) çağrılır; aynı input/output bağlamını
# paylaşır. Araç durumu motor ortamı üzerinden üretim motoruna ve soru
# gönderme yoluna açılır:
#   * motor$arac_durumu       : reactiveVal(list(family, derin, seviye, detay, surec_akisi))
#   * motor$arac_meta_listesi : soru MetaJson'u için ek metadata üreticisi
ortakOturumAracBind <- function(input, output, session, ctx, motor) {
  ns <- session$ns

  arac_durumu <- reactiveVal(oo_arac_varsayilan_ayarlar())
  # Kompakt aile sinyali: araç SEÇİCİ yalnızca aile değişince yeniden çizilsin
  # diye (ayar değişimi açık menüyü kapatacak bir yeniden çizim tetiklemez).
  arac_ailesi <- reactiveVal("")
  motor$arac_durumu <- arac_durumu
  motor$arac_meta_listesi <- function() {
    oo_arac_meta_listesi(shiny::isolate(arac_durumu()))
  }

  arac_sifirla <- function() {
    arac_durumu(oo_arac_varsayilan_ayarlar())
    arac_ailesi("")
  }

  # Oda değişince araç seçimi sıfırlanır (oda-yerel, oturum-yerel durum).
  observeEvent(ctx$aktif_oturum(), {
    arac_sifirla()
  }, ignoreNULL = FALSE)

  # Araç seçici: yalnızca ODA/ROL/AİLE değişince yeniden çizilir. Ayar
  # değerleri isolate ile okunur; ayar değişimi menüyü kapatacak bir yeniden
  # çizim TETİKLEMEZ (kontrolsüz DOM girdileri canlı durumu taşır).
  output$oda_arac_secim_alani <- renderUI({
    ctx$aktif_oturum()
    arac_ailesi()
    bilgi <- ctx$oturum_bilgisi()
    if (!is.null(bilgi) && identical(as.character(bilgi$KaynakTuru[1] %||% ""), "BilgeYolaç")) {
      return(NULL)
    }
    rol <- ctx$oda_rol()
    if (!ortak_yetki_var_mi(rol, "yapay_zeka_sor")) {
      return(NULL)
    }

    ayarlar <- shiny::isolate(arac_durumu())

    akislar <- if (exists("mergen_langflow_process_flows", mode = "function", inherits = TRUE)) {
      tryCatch(mergen_langflow_process_flows(), error = function(e) list())
    } else {
      list()
    }

    oo_arac_secici_html(
      katalog = oo_arac_katalogu(),
      ayarlar = ayarlar,
      dropdown_id = ns("oda_arac_dropdown"),
      secim_input_id = ns("oda_arac_secimi"),
      ayar_input_id = ns("oda_arac_ayari"),
      akislar = akislar
    )
  })

  # Aktif araç rozeti: ayar özetini canlı gösterir (ayar değişiminde de tazelenir).
  # BilgeYolaç odalarında analiz araçları yürütme yoluna girmediği için rozet de
  # çizilmez (seçiciyle aynı oda-türü kapısı; yanıltıcı araç vaadi olmaz).
  output$oda_arac_rozet_alani <- renderUI({
    bilgi <- ctx$oturum_bilgisi()
    if (!is.null(bilgi) && identical(as.character(bilgi$KaynakTuru[1] %||% ""), "BilgeYolaç")) {
      return(NULL)
    }
    rol <- ctx$oda_rol()
    if (!ortak_yetki_var_mi(rol, "yapay_zeka_sor")) {
      return(NULL)
    }
    oo_arac_rozet_html(
      katalog = oo_arac_katalogu(),
      ayarlar = arac_durumu(),
      temizle_input_id = ns("oda_arac_temizle")
    )
  })

  # Araç seçimi: family değişir, ayarlar varsayılana döner (araç-özel ayarlar
  # araçlar arasında taşınmaz). Boş family = araç temizlendi.
  observeEvent(input$oda_arac_secimi, {
    yeni_family <- as.character(input$oda_arac_secimi %||% "")[1]

    katalog <- oo_arac_katalogu()
    gecerli <- vapply(katalog, function(g) {
      identical(g$family, yeni_family) && isTRUE(g$destekleniyor)
    }, logical(1))

    if (nzchar(yeni_family) && !any(gecerli)) {
      ctx$bildir("Bu araç ortak oturumlarda kullanılamaz.", tur = "warning")
      return(invisible(NULL))
    }

    yeni <- oo_arac_varsayilan_ayarlar()
    yeni$family <- yeni_family
    arac_durumu(yeni)
    arac_ailesi(yeni_family)
  }, ignoreInit = TRUE)

  # Rozetteki × düğmesi: aracı temizle (JS delege köprüsü {id, nonce} yollar).
  observeEvent(input$oda_arac_temizle, {
    arac_sifirla()
  }, ignoreInit = TRUE)

  # Araç-özel ayar değişikliği: {alan, deger} yükü. Bayat/yarış koruması:
  # yalnızca bilinen alanlar ve aktif araç varken uygulanır.
  observeEvent(input$oda_arac_ayari, {
    yuk <- input$oda_arac_ayari
    alan <- as.character(yuk$alan %||% "")[1]
    if (!(alan %in% c("derin", "seviye", "detay", "surec_akisi"))) {
      return(invisible(NULL))
    }

    durum <- shiny::isolate(arac_durumu())
    if (!nzchar(as.character(durum$family %||% "")[1])) {
      return(invisible(NULL))
    }

    if (identical(alan, "derin")) {
      durum$derin <- isTRUE(as.logical(yuk$deger %||% FALSE)[1])
    } else {
      durum[[alan]] <- as.character(yuk$deger %||% "")[1]
    }
    arac_durumu(durum)
  }, ignoreInit = TRUE)

  # Model seçici: araç YOKKEN etkileşimli "Model Değiştir" bileşeni; araç
  # AKTİFKEN kilitli görünüm (araç kendi modelini kullanır). Yalnızca
  # ODA/ROL/AİLE değişince yeniden çizilir (menü seçimi/odak bozulmaz).
  output$oda_model_secim_alani <- renderUI({
    ctx$aktif_oturum()
    rol <- ctx$oda_rol()
    if (!ortak_yetki_var_mi(rol, "yapay_zeka_sor")) {
      return(NULL)
    }

    durum <- arac_durumu()
    if (nzchar(as.character(durum$family %||% "")[1])) {
      plan <- oo_arac_uretim_plani(shiny::isolate(arac_durumu()))
      model_etiketi <- if (identical(plan$yol, "langflow")) {
        "Akış modeli (Langflow)"
      } else if (nzchar(plan$model_id) && exists("api_config", inherits = TRUE)) {
        adlar <- names(api_config$local_models)
        eslesme <- match(plan$model_id, as.character(api_config$local_models))
        if (!is.na(eslesme) && !is.null(adlar)) adlar[eslesme] else plan$model_id
      } else {
        "Araç modeli"
      }

      return(div(
        class = "oo-secici oo-secici-model oo-secici-kilitli",
        title = "Araç etkinken model, aracın kendi modeliyle sabitlenir. Model seçimini geri açmak için aracı temizleyin.",
        `aria-disabled` = "true",
        tags$span(class = "oo-secici-kilit-ikon", icon("lock")),
        tags$span(
          class = "oo-secici-etiket",
          `aria-label` = "Araç modeli (kilitli)",
          HTML(htmltools::htmlEscape(as.character(model_etiketi)[1]))
        )
      ))
    }

    modeller <- if (exists("api_config", inherits = TRUE)) {
      as.character(api_config$local_models %||% character(0))
    } else {
      character(0)
    }
    adlar <- if (exists("api_config", inherits = TRUE)) names(api_config$local_models) else NULL
    aciklamalar <- if (exists("api_config", inherits = TRUE)) {
      api_config$local_model_descriptions %||% list()
    } else {
      list()
    }

    gecerli <- nzchar(modeller)
    modeller <- modeller[gecerli]
    if (!is.null(adlar) && length(adlar) == length(gecerli)) {
      adlar <- adlar[gecerli]
    } else {
      adlar <- NULL
    }

    secili <- as.character(ctx$secili_model() %||% "")[1]
    if (!nzchar(secili) && length(modeller) > 0L) {
      secili <- modeller[1]
    }

    oo_model_secici_html(
      modeller, adlar, aciklamalar, secili,
      dropdown_id = ns("oda_model_dropdown"),
      secim_input_id = ns("oda_model_secimi")
    )
  })

  observeEvent(input$oda_model_secimi, {
    deger <- as.character(input$oda_model_secimi %||% "")[1]
    if (nzchar(deger)) {
      ctx$secili_model(deger)
    }
  }, ignoreInit = TRUE)

  invisible(TRUE)
}