# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_room_ui.R
# Açıklama: Ortak Oturum odası UI iskeleti ve SAF HTML üreticileri: mesaj
#           balonu, katılımcı satırı, belge kartı ve davet satırı. Sunucu
#           mantığı R/module_ortak_oturum_room.R içindedir.
#
# Tasarım sözleşmesi: tüm yüzeyler tema token'larıyla stillendirilir
# (www/css/ortak_oturumlar.css; koyu tema varsayılan, açık tema
# html[data-theme="light"] kapsamında). Kullanıcı ve yapay zekâ kontrollü tüm
# metinler htmlEscape'ten geçer (XSS sınırı).
# ==============================================================================

ortakOturumRoomUI <- function(id) {
  ns <- NS(id)

  div(
    class = "oo-oda-yerlesim",
    `data-oo-role` = "oda",

    # Oda başlığı: başlık + tür/durum rozetleri + kapatma eylemleri.
    div(
      class = "oo-oda-baslik",
      div(
        class = "oo-oda-baslik-sol",
        uiOutput(ns("oda_baslik_alani"))
      ),
      div(
        class = "oo-oda-baslik-aksiyonlar",
        actionButton(
          ns("oda_katilimci_cagir"),
          label = tagList(icon("user-plus"), span("Katılımcı Çağır")),
          class = "btn-modern oo-btn-cagir",
          `aria-label` = "Ortak oturuma katılımcı çağır"
        ),
        downloadButton(
          ns("oda_disa_aktar"),
          label = "Tutanağı İndir",
          class = "btn-modern oo-btn-disa-aktar",
          `aria-label` = "Ortak oturum tutanağını UTF-8 metin olarak indir"
        ),
        uiOutput(ns("oda_yonetim_aksiyonlari"), inline = TRUE),
        actionButton(
          ns("oda_ayril"),
          label = tagList(icon("right-from-bracket"), span("Ayrıl")),
          class = "btn-modern oo-btn-ayril",
          `aria-label` = "Ortak oturumdan ayrıl"
        ),
        actionButton(
          ns("oda_kapat"),
          label = tagList(icon("xmark"), span("Listeye Dön")),
          class = "btn-modern oo-btn-kapat",
          `aria-label` = "Odayı kapat ve listeye dön"
        )
      )
    ),

    div(
      class = "oo-oda-govde",

      # Ana panel: yapay zekâ akışı + ortak belgeler + mesaj yazma alanı.
      div(
        class = "oo-oda-ana-panel",
        div(
          class = "oo-mesaj-akisi",
          id = ns("mesaj_akisi"),
          role = "log",
          `aria-live` = "polite",
          `aria-label` = "Ortak oturum mesaj akışı",
          uiOutput(ns("mesajlar_alani"))
        ),
        uiOutput(ns("uretim_durumu_alani")),
        div(
          class = "oo-belgeler-bolumu",
          h4(class = "oo-bolum-baslik", tagList(icon("folder-open"), span("Ortak Belgeler"))),
          uiOutput(ns("belgeler_alani"))
        ),

        # Mesaj yazma alanı: oda mesajı ile yapay zekâ sorusu AYRI eylemlerdir.
        div(
          class = "oo-composer",
          uiOutput(ns("composer_uyari_alani")),
          tags$textarea(
            id = ns("oda_mesaj_metni"),
            class = "oo-composer-girdi form-control",
            rows = "3",
            placeholder = "Mesajınızı yazın...",
            `aria-label` = "Ortak oturum mesajı"
          ),
          div(
            class = "oo-composer-aksiyonlar",
            actionButton(
              ns("odaya_yaz"),
              label = tagList(icon("comments"), span("Odaya Yaz")),
              class = "btn-modern oo-btn-odaya-yaz",
              title = "Mesajı yalnızca katılımcılara gönder; yapay zekâya GİTMEZ",
              `aria-label` = "Mesajı odaya yaz; yapay zekâya gönderilmez"
            ),
            actionButton(
              ns("yapay_zekaya_sor"),
              label = tagList(icon("robot"), span("Yapay Zekâya Sor")),
              class = "btn-modern btn-primary oo-btn-yz-sor",
              title = "Bu mesaj yapay zekâya gönderilecek ve yanıt tüm katılımcılar tarafından görülecek.",
              `aria-label` = "Soruyu yapay zekâya gönder; yanıtı tüm katılımcılar görür"
            )
          ),
          p(
            class = "oo-composer-yz-notu",
            tags$em("“Yapay Zekâya Sor”: Bu mesaj yapay zekâya gönderilecek ve yanıt tüm katılımcılar tarafından görülecek.")
          )
        )
      ),

      # Yan panel: katılımcılar + oda içi bilgiler.
      div(
        class = "oo-oda-yan-panel",
        h4(class = "oo-bolum-baslik", tagList(icon("users"), span("Katılımcılar"))),
        div(class = "oo-katilimci-listesi", uiOutput(ns("katilimcilar_alani")))
      )
    )
  )
}

# --- SAF HTML üreticileri (tüm metinler escape edilir) ---------------------------

# Tek mesaj balonu. Mesaj türüne göre stil sınıfı seçilir; yapay zekâ yanıtı
# güvenli markdown render'ından geçer (render_safe_markdown_html), diğer tüm
# metinler düz metin olarak escape edilir.
oo_mesaj_html <- function(satir, aktif_kullanici_id = NULL) {
  tur <- as.character(satir$MesajTuru %||% "OdaMesajı")[1]
  metin <- as.character(satir$MesajMetni %||% "")[1]
  gonderen <- as.character(satir$GonderenAdi %||% "")[1]
  zaman <- as.character(satir$OlusturmaZamani %||% "")[1]

  tur_sinifi <- switch(
    tur,
    "YapayZekaSorusu" = "oo-mesaj-yz-soru",
    "YapayZekaYanıtı" = "oo-mesaj-yz-yanit",
    "SistemMesajı" = "oo-mesaj-sistem",
    "BelgeBildirimi" = "oo-mesaj-belge",
    "oo-mesaj-oda"
  )

  benim <- !is.null(aktif_kullanici_id) &&
    identical(
      suppressWarnings(as.integer(satir$GonderenKullaniciID %||% NA_integer_)[1]),
      suppressWarnings(as.integer(aktif_kullanici_id)[1])
    )

  gonderen_etiket <- if (identical(tur, "YapayZekaYanıtı")) {
    "Yapay Zekâ"
  } else if (identical(tur, "SistemMesajı")) {
    "Sistem"
  } else if (nzchar(gonderen)) {
    gonderen
  } else {
    "Katılımcı"
  }

  rozet <- switch(
    tur,
    "YapayZekaSorusu" = tags$span(class = "oo-rozet oo-rozet-yz-soru", "Yapay Zekâ Sorusu"),
    "YapayZekaYanıtı" = tags$span(class = "oo-rozet oo-rozet-yz-yanit", "Yapay Zekâ Yanıtı"),
    "OdaMesajı" = tags$span(class = "oo-rozet oo-rozet-oda", "Oda Mesajı"),
    NULL
  )

  # Yapay zekâ yanıtı: güvenli markdown; diğerleri düz metin (escape).
  metin_html <- if (identical(tur, "YapayZekaYanıtı") &&
                    exists("render_safe_markdown_html", mode = "function", inherits = TRUE)) {
    HTML(render_safe_markdown_html(metin))
  } else {
    tags$span(HTML(htmltools::htmlEscape(metin)))
  }

  div(
    class = paste("oo-mesaj", tur_sinifi, if (benim) "oo-mesaj-benim" else NULL),
    div(
      class = "oo-mesaj-ust",
      tags$span(class = "oo-mesaj-gonderen", HTML(htmltools::htmlEscape(gonderen_etiket))),
      rozet,
      tags$span(class = "oo-mesaj-zaman", HTML(htmltools::htmlEscape(zaman)))
    ),
    div(class = "oo-mesaj-metin", metin_html)
  )
}

# Katılımcı satırı: canlı durum noktası + ad + rol rozeti.
oo_katilimci_html <- function(satir, canli_durum = "ÇevrimDışı") {
  ad <- as.character(satir$KaynakAdi %||% satir$KullaniciAdi %||% "Kullanıcı")[1]
  rol <- as.character(satir$Rol %||% "")[1]
  katilim <- as.character(satir$KatilimDurumu %||% "")[1]

  durum_sinifi <- switch(
    as.character(canli_durum)[1],
    "Çevrimİçi" = "oo-canli-cevrimici",
    "Boşta" = "oo-canli-bosta",
    "oo-canli-cevrimdisi"
  )

  bekliyor <- identical(katilim, "DavetEdildi")

  div(
    class = paste("oo-katilimci", if (bekliyor) "oo-katilimci-bekliyor" else NULL),
    tags$span(
      class = paste("oo-canli-nokta", durum_sinifi),
      title = as.character(canli_durum)[1],
      `aria-label` = as.character(canli_durum)[1]
    ),
    tags$span(class = "oo-katilimci-ad", HTML(htmltools::htmlEscape(ad))),
    tags$span(class = "oo-rozet oo-rozet-rol", HTML(htmltools::htmlEscape(rol))),
    if (bekliyor) tags$span(class = "oo-rozet oo-rozet-bekliyor", "Davet Bekliyor") else NULL
  )
}

# Ortak belge kartı: metadata + "Kendi Dosyalarıma Kaydet" eylemi.
# buton_id çağıran modülün namespace'lenmiş data-eylem hedefidir.
oo_dosya_karti_html <- function(satir, kopyala_input_id) {
  ad <- as.character(satir$DosyaAdi %||% "belge")[1]
  ureten <- as.character(satir$UretenAdi %||% "")[1]
  zaman <- as.character(satir$OlusturmaZamani %||% "")[1]
  kopya_durumu <- as.character(satir$KopyalamaDurumu %||% "")[1]
  dosya_id <- suppressWarnings(as.integer(satir$OrtakDosyaID %||% NA_integer_)[1])

  boyut <- suppressWarnings(as.numeric(satir$DosyaBoyutu %||% NA_real_)[1])
  boyut_metni <- if (!is.na(boyut) && boyut > 0) {
    if (boyut >= 1024 * 1024) {
      sprintf("%.1f MB", boyut / (1024 * 1024))
    } else {
      sprintf("%.0f KB", boyut / 1024)
    }
  } else {
    ""
  }

  kopyalandi <- identical(kopya_durumu, "Kopyalandı")

  div(
    class = "oo-belge-karti",
    `data-oo-dosya-id` = as.character(dosya_id),
    div(
      class = "oo-belge-ust",
      icon("file-lines", class = "oo-belge-ikon"),
      tags$span(class = "oo-belge-ad", title = ad, HTML(htmltools::htmlEscape(ad)))
    ),
    div(
      class = "oo-belge-meta",
      if (nzchar(boyut_metni)) tags$span(boyut_metni) else NULL,
      if (nzchar(ureten)) tags$span(HTML(htmltools::htmlEscape(paste("Üreten:", ureten)))) else NULL,
      tags$span(HTML(htmltools::htmlEscape(zaman)))
    ),
    div(
      class = "oo-belge-aksiyonlar",
      if (kopyalandi) {
        tags$span(class = "oo-rozet oo-rozet-kopyalandi", tagList(icon("check"), span("Dosyalarımda")))
      } else {
        tags$button(
          type = "button",
          class = "btn-modern oo-btn-belge-kopyala",
          `data-oo-dosya-id` = as.character(dosya_id),
          `data-oo-hedef-input` = kopyala_input_id,
          `aria-label` = paste("Belgeyi kendi dosyalarına kaydet:", ad),
          tagList(icon("download"), span("Kendi Dosyalarıma Kaydet"))
        )
      }
    )
  )
}

# Davet paneli kullanıcı satırı: ad/kullanıcı adı/e-posta/departman + canlı
# durum + eylem butonları (Mergen içi çağrı / e-posta taslağı).
oo_davet_kullanici_html <- function(satir,
                                    canli_durum,
                                    cagir_input_id,
                                    eposta_input_id,
                                    mevcut_durum = "") {
  ad <- as.character(satir$KaynakAdi %||% satir$KullaniciAdi %||% "Kullanıcı")[1]
  kullanici_adi <- as.character(satir$KullaniciAdi %||% "")[1]
  eposta <- as.character(satir$Email %||% "")[1]
  departman <- as.character(satir$Departman %||% "")[1]
  kullanici_id <- suppressWarnings(as.integer(satir$UserID %||% NA_integer_)[1])

  cevrimici <- identical(as.character(canli_durum)[1], "Çevrimİçi")

  durum_sinifi <- switch(
    as.character(canli_durum)[1],
    "Çevrimİçi" = "oo-canli-cevrimici",
    "Boşta" = "oo-canli-bosta",
    "oo-canli-cevrimdisi"
  )

  mevcut_rozet <- if (nzchar(mevcut_durum)) {
    tags$span(class = "oo-rozet oo-rozet-davet-durum", HTML(htmltools::htmlEscape(mevcut_durum)))
  } else {
    NULL
  }

  div(
    class = "oo-davet-satiri",
    `data-oo-kullanici-id` = as.character(kullanici_id),
    tags$span(
      class = paste("oo-canli-nokta", durum_sinifi),
      title = as.character(canli_durum)[1]
    ),
    div(
      class = "oo-davet-kimlik",
      tags$span(class = "oo-davet-ad", HTML(htmltools::htmlEscape(ad))),
      tags$span(
        class = "oo-davet-detay",
        HTML(htmltools::htmlEscape(paste(
          Filter(nzchar, c(kullanici_adi, eposta, departman)),
          collapse = " · "
        )))
      )
    ),
    mevcut_rozet,
    div(
      class = "oo-davet-aksiyonlar",
      if (cevrimici) {
        tags$button(
          type = "button",
          class = "btn-modern btn-primary oo-btn-mergen-cagir",
          `data-oo-kullanici-id` = as.character(kullanici_id),
          `data-oo-hedef-input` = cagir_input_id,
          `aria-label` = paste("Mergen içinden çağır:", ad),
          tagList(icon("bell"), span("Mergen İçinden Çağır"))
        )
      } else {
        NULL
      },
      if (nzchar(eposta)) {
        tags$button(
          type = "button",
          class = "btn-modern oo-btn-eposta-taslak",
          `data-oo-kullanici-id` = as.character(kullanici_id),
          `data-oo-hedef-input` = eposta_input_id,
          `aria-label` = paste("E-posta taslağı hazırla:", ad),
          tagList(icon("envelope"), span("E-posta Taslağı Hazırla"))
        )
      } else {
        NULL
      }
    )
  )
}
