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
          class = "oo-oda-btn oo-oda-btn-birincil oo-btn-cagir",
          title = "Ortak oturuma yeni katılımcı çağır",
          `aria-label` = "Ortak oturuma katılımcı çağır"
        ),
        downloadButton(
          ns("oda_disa_aktar"),
          label = "Tutanağı İndir",
          class = "oo-oda-btn oo-oda-btn-notr oo-btn-disa-aktar",
          title = "Oturum tutanağını UTF-8 metin dosyası olarak indir",
          `aria-label` = "Ortak oturum tutanağını UTF-8 metin olarak indir"
        ),
        uiOutput(ns("oda_yonetim_aksiyonlari"), inline = TRUE),
        actionButton(
          ns("oda_ayril"),
          label = tagList(icon("right-from-bracket"), span("Ayrıl")),
          class = "oo-oda-btn oo-oda-btn-uyari oo-btn-ayril",
          title = "Ortak oturumdan ayrıl",
          `aria-label` = "Ortak oturumdan ayrıl"
        ),
        actionButton(
          ns("oda_kapat"),
          label = tagList(icon("arrow-left"), span("Listeye Dön")),
          class = "oo-oda-btn oo-oda-btn-notr oo-btn-kapat",
          title = "Odayı kapat ve ortak oturum listesine dön",
          `aria-label` = "Odayı kapat ve listeye dön"
        )
      )
    ),

    # Ortak Bilge Yolaç odaları için çalışma alanı paneli (yalnızca BY türünde
    # görünür; NormalSohbet odalarında renderUI NULL döner).
    uiOutput(ns("by_alani")),

    div(
      class = "oo-oda-govde",

      # Ana panel: yapay zekâ akışı + üretim durumu + mesaj yazma alanı.
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

        # Mesaj yazma alanı: oda mesajı ile yapay zekâ sorusu AYRI eylemlerdir.
        # Model / persona / araç seçimleri girdi kutusunun ALTINDA, aksiyon
        # butonlarıyla AYNI satırdadır (dikey alan tasarrufu; ana söyleşi
        # "Model Değiştir" dili). Açıklama paragrafı yerine buton title'ları
        # kullanılır: "Yapay Zekâya Sor" başlığı yanıtın tüm katılımcılar
        # tarafından görüleceğini açıklamaya devam eder.
        div(
          class = "oo-composer",
          uiOutput(ns("composer_uyari_alani")),
          uiOutput(ns("oda_arac_rozet_alani")),
          tags$textarea(
            id = ns("oda_mesaj_metni"),
            class = "oo-composer-girdi form-control",
            rows = "2",
            placeholder = "Mesajınızı yazın...",
            `aria-label` = "Ortak oturum mesajı"
          ),
          div(
            class = "oo-composer-aksiyonlar",
            div(
              class = "oo-composer-secimler",
              uiOutput(ns("oda_model_secim_alani"), inline = TRUE),
              uiOutput(ns("oda_persona_secim_alani"), inline = TRUE),
              uiOutput(ns("oda_arac_secim_alani"), inline = TRUE)
            ),
            div(
              class = "oo-composer-butonlar",
              actionButton(
                ns("oda_baglam_temizle"),
                label = icon("wand-magic-sparkles"),
                class = "oo-oda-btn oo-oda-btn-notr oo-btn-baglam-temizle oo-btn-ikon",
                title = "Yeni bağlam başlat: bundan sonraki sorular önceki yazışmaları bağlam olarak kullanmaz (transkript korunur)",
                `aria-label` = "Yeni yapay zekâ bağlamı başlat"
              ),
              uiOutput(ns("oda_sohbet_temizle_alani"), inline = TRUE),
              actionButton(
                ns("odaya_yaz"),
                label = tagList(icon("comments"), span("Odaya Yaz")),
                class = "oo-oda-btn oo-oda-btn-notr oo-btn-odaya-yaz",
                title = "Mesajı yalnızca katılımcılara gönder; yapay zekâya GİTMEZ",
                `aria-label` = "Mesajı odaya yaz; yapay zekâya gönderilmez"
              ),
              actionButton(
                ns("yapay_zekaya_sor"),
                label = tagList(icon("robot"), span("Yapay Zekâya Sor")),
                class = "oo-oda-btn oo-oda-btn-birincil oo-btn-yz-sor",
                title = "Bu mesaj yapay zekâya gönderilecek ve yanıt tüm katılımcılar tarafından görülecek.",
                `aria-label` = "Soruyu yapay zekâya gönder; yanıtı tüm katılımcılar görür"
              )
            )
          )
        )
      ),

      # Yan panel: katılımcılar + ortak belgeler (daraltılabilir).
      div(
        class = "oo-oda-yan-panel",
        `data-oo-yan-panel` = "1",
        tags$button(
          type = "button",
          class = "oo-yan-panel-toggle",
          `data-oo-toggle-yan` = "1",
          `aria-label` = "Yan paneli daralt/genişlet",
          title = "Katılımcılar ve Ortak Belgeler panelini daralt/genişlet",
          icon("chevron-right", class = "oo-yan-panel-toggle-ikon")
        ),
        div(
          class = "oo-yan-panel-icerik",
          div(
            class = "oo-yan-bolum oo-yan-katilimcilar",
            h4(class = "oo-bolum-baslik", tagList(icon("users"), span("Katılımcılar"))),
            div(class = "oo-katilimci-listesi", uiOutput(ns("katilimcilar_alani")))
          ),
          # Sürüklenebilir dikey ayraç: Katılımcılar / Ortak Belgeler yüksekliğini
          # kullanıcı ayarlar (oturum boyunca korunur; sadece görsel — JS köprüsü).
          tags$div(
            class = "oo-yan-resizer",
            `data-oo-resizer` = "1",
            role = "separator",
            `aria-orientation` = "horizontal",
            `aria-label` = "Katılımcılar ve Ortak Belgeler panel yüksekliğini ayarla",
            tabindex = "0",
            tags$span(class = "oo-yan-resizer-tutamac", `aria-hidden` = "true")
          ),
          div(
            class = "oo-yan-bolum oo-yan-belgeler",
            h4(class = "oo-bolum-baslik", tagList(icon("folder-open"), span("Ortak Belgeler"))),
            uiOutput(ns("belge_yukleme_alani")),
            div(class = "oo-belgeler-listesi", uiOutput(ns("belgeler_alani")))
          )
        )
      )
    )
  )
}

# --- SAF HTML üreticileri (tüm metinler escape edilir) ---------------------------

# Tek mesaj balonu. Mesaj türüne göre stil sınıfı seçilir; yapay zekâ yanıtı
# güvenli markdown render'ından geçer (render_safe_markdown_html), diğer tüm
# metinler düz metin olarak escape edilir.
oo_mesaj_persona_id <- function(satir) {
  meta <- as.character(satir$MetaJson %||% "")[1]
  if (!nzchar(meta) || is.na(meta) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return("")
  }
  parsed <- tryCatch(jsonlite::fromJSON(meta, simplifyVector = TRUE), error = function(e) NULL)
  if (!is.list(parsed)) {
    return("")
  }

  persona_id <- as.character(parsed$persona_id %||% "")[1]
  if (is.na(persona_id)) "" else trimws(persona_id)
}

oo_mesaj_html <- function(satir, aktif_kullanici_id = NULL, persona = NULL) {
  tur <- as.character(satir$MesajTuru %||% "OdaMesajı")[1]
  metin <- as.character(satir$MesajMetni %||% "")[1]
  gonderen <- as.character(satir$GonderenAdi %||% "")[1]
  zaman <- as.character(satir$OlusturmaZamani %||% "")[1]

  # Yapay zekâ yanıtı yalnızca kendi metadata'sındaki persona_id ile etiketlenir.
  # Metadata yoksa room-level/current persona kullanılmaz; eski ya da içe aktarılan
  # yanıtlar güvenli biçimde genel "Yapay Zekâ" etiketiyle kalır.
  mesaj_persona_id <- oo_mesaj_persona_id(satir)
  if (identical(tur, "YapayZekaYanıtı")) {
    persona <- if (nzchar(mesaj_persona_id)) {
      ortak_oturum_persona_gorunumu(mesaj_persona_id)
    } else {
      NULL
    }
  }
  yz_persona_ad <- if (is.list(persona)) as.character(persona$ad %||% "")[1] else ""
  yz_persona_accent <- if (is.list(persona)) as.character(persona$accent %||% "")[1] else ""

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
    if (nzchar(yz_persona_ad)) yz_persona_ad else "Yapay Zekâ"
  } else if (identical(tur, "SistemMesajı")) {
    "Sistem"
  } else if (identical(tur, "BelgeBildirimi")) {
    "Ortak Belge"
  } else if (nzchar(gonderen)) {
    gonderen
  } else {
    "Katılımcı"
  }

  rozet <- switch(
    tur,
    "YapayZekaSorusu" = tags$span(class = "oo-rozet oo-rozet-yz-soru",
                                  tagList(icon("robot"), span("Yapay Zekâya Soru"))),
    "YapayZekaYanıtı" = tags$span(class = "oo-rozet oo-rozet-yz-yanit",
                                  tagList(icon("wand-magic-sparkles"), span("Yapay Zekâ Yanıtı"))),
    "OdaMesajı" = tags$span(class = "oo-rozet oo-rozet-oda",
                            tagList(icon("comments"), span("Oda"))),
    "SistemMesajı" = tags$span(class = "oo-rozet oo-rozet-sistem",
                               tagList(icon("circle-info"), span("Sistem"))),
    "BelgeBildirimi" = tags$span(class = "oo-rozet oo-rozet-belge",
                                 tagList(icon("file-lines"), span("Belge"))),
    NULL
  )

  # Gönderen adının baş harfi: küçük avatar rozeti (Ana Söyleşi deseni).
  bas_harf <- {
    temiz <- trimws(gonderen_etiket)
    if (nzchar(temiz)) toupper(substr(temiz, 1L, 1L)) else "?"
  }
  avatar_sinifi <- switch(
    tur,
    "YapayZekaYanıtı" = "oo-mesaj-avatar-yz",
    "SistemMesajı" = "oo-mesaj-avatar-sistem",
    "BelgeBildirimi" = "oo-mesaj-avatar-belge",
    "oo-mesaj-avatar-kullanici"
  )

  # Yapay zekâ avatarı persona aksan rengiyle boyanır (görsel varlık gerekmez).
  avatar_stili <- if (identical(tur, "YapayZekaYanıtı") && nzchar(yz_persona_accent)) {
    sprintf("background:%s;", yz_persona_accent)
  } else {
    NULL
  }

  # Avatar görseli (ana söyleşi deseni): yapay zekâ yanıtı için persona görseli,
  # kullanıcı mesajı için Sicil'e dayalı profil fotoğrafı. Görsel yüklenemezse
  # onerror ile baş harf yedeğe geçilir (kırık görsel riski yok).
  avatar_url <- ""
  if (identical(tur, "YapayZekaYanıtı") && nzchar(mesaj_persona_id) &&
      exists("get_character_asset_paths", mode = "function", inherits = TRUE)) {
    varliklar <- tryCatch(get_character_asset_paths(mesaj_persona_id), error = function(e) NULL)
    avatar_url <- as.character((varliklar$avatar %||% "")[1])
  } else if (identical(avatar_sinifi, "oo-mesaj-avatar-kullanici") &&
             exists("mb_sidebar_user_avatar_url", mode = "function", inherits = TRUE)) {
    sicil <- as.character(satir$GonderenSicil %||% "")[1]
    if (!is.na(sicil) && nzchar(sicil)) {
      avatar_url <- tryCatch(mb_sidebar_user_avatar_url(sicil), error = function(e) "")
    }
  }
  if (is.na(avatar_url)) {
    avatar_url <- ""
  }

  avatar_icerik <- if (nzchar(avatar_url)) {
    tagList(
      tags$img(
        src = avatar_url,
        class = "oo-mesaj-avatar-img",
        alt = "",
        onerror = "this.style.display='none'; var p=this.parentElement; if(p){var f=p.querySelector('.oo-mesaj-avatar-yedek'); if(f){f.style.display='flex';}}"
      ),
      tags$span(class = "oo-mesaj-avatar-yedek", style = "display:none;", bas_harf)
    )
  } else {
    span(bas_harf)
  }

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
      class = paste("oo-mesaj-avatar", avatar_sinifi),
      style = avatar_stili,
      `aria-hidden` = "true",
      avatar_icerik
    ),
    div(
      class = "oo-mesaj-govde",
      div(
        class = "oo-mesaj-ust",
        tags$span(class = "oo-mesaj-gonderen", HTML(htmltools::htmlEscape(gonderen_etiket))),
        rozet,
        tags$span(class = "oo-mesaj-zaman", HTML(htmltools::htmlEscape(zaman)))
      ),
      div(class = "oo-mesaj-metin", metin_html)
    )
  )
}

# Katılımcı satırı: canlı durum noktası + ad + rol rozeti. Durum göstergesi
# saf ortak_sunum_rozeti() ile üretilir: yalnızca renge dayanmaz, title/
# aria-label metni taşır. ayni_odada = TRUE iken yeşil "bu odada" göstergesi.
oo_katilimci_html <- function(satir, canli_durum = "ÇevrimDışı", ayni_odada = FALSE) {
  ad <- as.character(satir$KaynakAdi %||% satir$KullaniciAdi %||% "Kullanıcı")[1]
  rol <- as.character(satir$Rol %||% "")[1]
  katilim <- as.character(satir$KatilimDurumu %||% "")[1]

  bekliyor <- identical(katilim, "DavetEdildi")
  rozet <- ortak_sunum_rozeti(canli_durum, ayni_odada = ayni_odada, davet_bekliyor = bekliyor)
  rol_etiket <- ortak_rol_gorunen_ad(rol)

  div(
    class = paste("oo-katilimci", if (bekliyor) "oo-katilimci-bekliyor" else NULL),
    tags$span(
      class = paste("oo-canli-nokta", rozet$sinif),
      title = rozet$etiket,
      `aria-label` = rozet$etiket
    ),
    tags$span(class = "oo-katilimci-ad", HTML(htmltools::htmlEscape(ad))),
    if (nzchar(rol_etiket)) {
      tags$span(class = "oo-rozet oo-rozet-rol", HTML(htmltools::htmlEscape(rol_etiket)))
    } else {
      NULL
    },
    if (bekliyor) tags$span(class = "oo-rozet oo-rozet-bekliyor", "Davet Bekliyor") else NULL
  )
}

# NOT: Ortak belge kartı üreticisi (oo_dosya_karti_html) belge paneli
# bağlayıcısına taşındı: R/module_ortak_oturum_belge_paneli.R ("Kendi
# Dosyalarıma Kaydet" + bağlam seçimi + kaldırma eylemleriyle birlikte).

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

  durum <- as.character(canli_durum %||% "")[1]
  cevrimici_ya_da_bosta <- durum %in% c("Çevrimİçi", "Boşta")

  davetli <- identical(mevcut_durum, "DavetEdildi")
  katildi <- identical(mevcut_durum, "Katıldı")
  rozet_bilgi <- ortak_sunum_rozeti(canli_durum, davet_bekliyor = davetli)

  mevcut_rozet <- if (katildi) {
    tags$span(class = "oo-rozet oo-rozet-kopyalandi",
              tagList(icon("check"), span("Katıldı")))
  } else if (davetli) {
    tags$span(class = "oo-rozet oo-rozet-bekliyor",
              tagList(icon("hourglass-half"), span("Davet edildi")))
  } else {
    NULL
  }

  # Zaten katılmış kullanıcıya davet eylemi sunulmaz.
  aksiyonlar <- if (katildi) {
    NULL
  } else {
    tagList(
      # Çevrim içi/boşta kullanıcı için birincil eylem: Mergen içi çağrı.
      if (cevrimici_ya_da_bosta) {
        tags$button(
          type = "button",
          class = "oo-oda-btn oo-oda-btn-birincil oo-btn-mergen-cagir",
          `data-oo-kullanici-id` = as.character(kullanici_id),
          `data-oo-hedef-input` = cagir_input_id,
          `aria-label` = paste("Mergen içinden çağır:", ad),
          tagList(icon("bell"), span(if (davetli) "Tekrar Çağır" else "Mergen İçinden Çağır"))
        )
      } else {
        NULL
      },
      if (nzchar(eposta)) {
        tags$button(
          type = "button",
          class = "oo-oda-btn oo-oda-btn-notr oo-btn-eposta-taslak",
          `data-oo-kullanici-id` = as.character(kullanici_id),
          `data-oo-hedef-input` = eposta_input_id,
          `aria-label` = paste("E-posta taslağı hazırla:", ad),
          tagList(icon("envelope"), span("E-posta Taslağı Hazırla"))
        )
      } else {
        NULL
      }
    )
  }

  div(
    class = "oo-davet-satiri",
    `data-oo-kullanici-id` = as.character(kullanici_id),
    tags$span(
      class = paste("oo-canli-nokta", rozet_bilgi$sinif),
      title = rozet_bilgi$etiket,
      `aria-label` = rozet_bilgi$etiket
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
    div(class = "oo-davet-aksiyonlar", aksiyonlar)
  )
}

# Model seçici (SAF): ana söyleşi "Model Değiştir" bileşeniyle (shinyWidgets
# dropdown) aynı dil. Model çözümü (api_config) çağıran sunucuda yapılır; burası
# yalnızca çözülmüş listeyi HTML'e dönüştürür. Seçim onclick ile secim_input_id'ye
# yazılır (namespaceli). Tüm görünen metin escape edilir.
oo_model_secici_html <- function(modeller, adlar, aciklamalar, secili,
                                 dropdown_id, secim_input_id) {
  if (length(modeller) == 0L) {
    return(tags$span(class = "oo-composer-model-yok", "Varsayılan model"))
  }
  aciklamalar <- if (is.list(aciklamalar)) aciklamalar else list()

  ogeler <- lapply(seq_along(modeller), function(i) {
    m_id <- modeller[i]
    m_ad <- if (!is.null(adlar)) adlar[i] else m_id
    aktif <- identical(as.character(m_id), as.character(secili))
    aciklama <- as.character(aciklamalar[[m_id]] %||% m_ad)[1]
    tags$li(tags$a(
      class = paste0("dropdown-item model-option", if (aktif) " active" else ""),
      href = "#",
      title = aciklama,
      # Model id ve girdi adı, inline onclick JS'ine ham gömülmez; tek tırnak veya
      # ters bölü içeren katalog değerleri handler'ı bozabilir veya script
      # enjekte edebilir. Ana söyleşi "Model Değiştir" yolundaki gibi JS string
      # literaline (jsonlite::toJSON, çift tırnaklı) kodlanır.
      onclick = sprintf(
        "Shiny.setInputValue(%s, %s, {priority:'event'}); return false;",
        jsonlite::toJSON(as.character(secim_input_id), auto_unbox = TRUE),
        jsonlite::toJSON(as.character(m_id), auto_unbox = TRUE)
      ),
      div(
        class = "model-item-content",
        span(class = "model-name", HTML(htmltools::htmlEscape(m_ad))),
        if (aktif) icon("check", class = "selected-icon") else NULL
      )
    ))
  })

  secili_ad <- if (!is.null(adlar)) {
    idx <- match(secili, modeller)
    if (!is.na(idx)) adlar[idx] else secili
  } else {
    secili
  }

  div(
    class = "oo-secici oo-secici-model",
    title = "Yanıt üretiminde kullanılacak modeli değiştir",
    shinyWidgets::dropdown(
      inputId = dropdown_id,
      style = "minimal",
      icon = icon("microchip"),
      status = "default",
      up = TRUE,
      width = "260px",
      div(class = "dropdown-menu-header", icon("layer-group"), tags$span("Model Kataloğu")),
      tags$ul(class = "dropdown-menu-custom-list", ogeler)
    ),
    tags$span(
      class = "oo-secici-etiket",
      `aria-label` = "Seçili model",
      HTML(htmltools::htmlEscape(secili_ad))
    )
  )
}

# Persona seçici (SAF): "Model Değiştir" diliyle aynı açılır liste; 5 persona
# aksan noktası + ad ile listelenir. Yetkisi olmayan katılımcı için salt-okunur
# rozet döner. Seçim onclick ile secim_input_id'ye yazılır.
oo_persona_secici_html <- function(secili, yetkili, dropdown_id, secim_input_id) {
  gorunum <- ortak_oturum_persona_gorunumu(secili)

  if (!isTRUE(yetkili)) {
    return(tags$span(
      class = "oo-composer-persona-rozet",
      title = "Odanın yapay zekâ personası",
      tags$span(
        class = "oo-composer-persona-nokta",
        style = sprintf("background:%s;", gorunum$accent),
        `aria-hidden` = "true"
      ),
      span(as.character(gorunum$ad))
    ))
  }

  personalar <- c("emre", "selin", "deniz", "can", "ipek")
  ogeler <- lapply(personalar, function(pid) {
    g <- ortak_oturum_persona_gorunumu(pid)
    aktif <- identical(as.character(pid), as.character(secili))
    alt <- if (exists("get_character_record", mode = "function", inherits = TRUE)) {
      rec <- tryCatch(get_character_record(pid), error = function(e) NULL)
      as.character((rec$subtitle %||% "")[1])
    } else {
      ""
    }
    tags$li(tags$a(
      class = paste0("dropdown-item model-option oo-persona-option", if (aktif) " active" else ""),
      href = "#",
      title = if (nzchar(alt)) alt else as.character(g$ad),
      # Persona id'leri sabit ASCII olsa da, girdi adı ve değer inline onclick
      # JS'ine model seçicideki gibi JS string literaline kodlanır (tutarlılık +
      # savunma amaçlı).
      onclick = sprintf(
        "Shiny.setInputValue(%s, %s, {priority:'event'}); return false;",
        jsonlite::toJSON(as.character(secim_input_id), auto_unbox = TRUE),
        jsonlite::toJSON(as.character(pid), auto_unbox = TRUE)
      ),
      div(
        class = "model-item-content",
        div(
          class = "oo-persona-oge",
          tags$span(class = "oo-persona-nokta", style = sprintf("background:%s;", g$accent), `aria-hidden` = "true"),
          div(
            class = "oo-persona-metin",
            span(class = "model-name", HTML(htmltools::htmlEscape(as.character(g$ad)))),
            if (nzchar(alt)) tags$small(class = "oo-persona-alt", HTML(htmltools::htmlEscape(alt))) else NULL
          )
        ),
        if (aktif) icon("check", class = "selected-icon") else NULL
      )
    ))
  })

  div(
    class = "oo-secici oo-secici-persona",
    title = "Odanın yapay zekâ personasını değiştir",
    shinyWidgets::dropdown(
      inputId = dropdown_id,
      style = "minimal",
      icon = icon("masks-theater"),
      status = "default",
      up = TRUE,
      width = "280px",
      div(class = "dropdown-menu-header", icon("user-astronaut"), tags$span("Yapay Zekâ Personası")),
      tags$ul(class = "dropdown-menu-custom-list", ogeler)
    ),
    tags$span(
      class = "oo-secici-etiket",
      `aria-label` = "Seçili persona",
      tags$span(
        class = "oo-persona-nokta oo-persona-nokta-kucuk",
        style = sprintf("background:%s;", gorunum$accent),
        `aria-hidden` = "true"
      ),
      HTML(htmltools::htmlEscape(as.character(gorunum$ad)))
    )
  )
}
