# ==============================================================================
# Dosya Yolu: R/module_ortak_calismalar.R
# Açıklama: "Ortak Çalışmalarım" merkez modülü. Tek modül kimliğiyle üç sekme
#           yüzeyini besler (destek modülü deseni): hub (Ortak Çalışmalarım),
#           sohbet (Ortak Söyleşiler) ve bilge_yolac (Ortak Bilge Yolaç
#           Oturumları). Oda sunucusu R/module_ortak_oturum_room.R içindedir
#           ve yalnızca hub yüzeyine gömülür.
#
# Sözleşmeler:
#   * Kişisel geçmiş listeleriyle ASLA karışmaz: bu modül yalnızca
#     MB_OrtakOturumlar ailesinden okur.
#   * Kullanıcı bazlı arşiv yalnızca kullanıcının görünümünü etkiler.
#   * Davet kabul edilmeden oda içeriği açılmaz; davet kartı yalnızca
#     metadata gösterir.
#   * Kalp atışı gözlemcisi yalnızca geçerli (pozitif) kullanıcı kimliğiyle
#     yazar; SSO placeholder (0) kimlikle canlı durum yazılmaz.
# ==============================================================================

ortakCalismalarUI <- function(id, sayfa = "hub") {
  ns <- NS(id)

  baslik <- switch(
    sayfa,
    "sohbet" = "Ortak Söyleşiler",
    "bilge_yolac" = "Ortak Bilge Yolaç Oturumları",
    "Ortak Çalışmalarım"
  )

  tagList(
    div(
      class = "ortak-calismalar-container",
      `data-oo-sayfa` = sayfa,

      # Sayfa başlığı standart uygulama başlık desenini izler (ikon YOK; diğer
      # sayfalarla aynı hizalama). ORTAK rozeti Yönetici/AJAN pill diliyle stillenir.
      div(
        class = "chat-header settings-header-fixed oo-page-header",
        div(
          class = "chat-header-left",
          h4(baslik, class = "page-title"),
          tags$span(class = "oo-rozet oo-rozet-ortak", "ORTAK")
        ),
        div(
          class = "chat-header-right oo-header-aksiyonlar",
          if (identical(sayfa, "hub")) {
            actionButton(
              ns("yeni_ortak_oturum"),
              label = tagList(icon("plus"), span("Yeni Ortak Oturum")),
              class = "btn-modern btn-primary oo-btn-yeni",
              `aria-label` = "Yeni ortak oturum oluştur"
            )
          } else {
            NULL
          },
          actionButton(
            ns(paste0("yenile_", sayfa)),
            label = tagList(icon("sync"), span("Yenile")),
            class = "btn-modern oo-btn-yenile",
            `aria-label` = "Ortak oturum listesini yenile"
          )
        )
      ),

      if (identical(sayfa, "hub")) {
        tagList(
          # Filtre butonları ve liste yalnızca oda KAPALIYKEN görünür; oda
          # açıkken CSS (.oo-oda-acik) bunları gizler, böylece aktif oda
          # dikeyde tüm alanı kullanır (bkz. hub_oda_acik observer).
          div(
            class = "oo-hub-liste-alani",
            div(
              class = "oo-hub-filtreler",
              radioButtons(
                ns("hub_filtre"),
                label = NULL,
                choices = c("Tümü", "Davetlerim", "Arşivlenmiş Ortak Oturumlar"),
                selected = "Tümü",
                inline = TRUE
              )
            ),
            div(class = "oo-oturum-listesi", uiOutput(ns("liste_hub")))
          ),
          uiOutput(ns("oda_alani"), class = "oo-oda-alani")
        )
      } else if (identical(sayfa, "sohbet")) {
        div(class = "oo-oturum-listesi", uiOutput(ns("liste_sohbet")))
      } else {
        div(class = "oo-oturum-listesi", uiOutput(ns("liste_bilge_yolac")))
      }
    )
  )
}

# --- SAF liste kartı üreticileri ---------------------------------------------------

# Ortak oturum liste kartı. Eylem butonları JS delegasyonuyla (data-oo-*)
# namespaceli Shiny inputlarına bağlanır; tüm metinler escape edilir.
oo_liste_karti <- function(satir, ac_input_id, arsiv_input_id, arsivde = FALSE) {
  oturum_id <- suppressWarnings(as.integer(satir$OrtakOturumID %||% NA_integer_)[1])
  baslik <- as.character(satir$Baslik %||% "Ortak Oturum")[1]
  kaynak <- as.character(satir$KaynakTuru %||% "NormalSohbet")[1]
  durum <- as.character(satir$OturumDurumu %||% "Aktif")[1]
  rol <- as.character(satir$Rol %||% "")[1]
  katilimci_sayisi <- suppressWarnings(as.integer(satir$KatilimciSayisi %||% 0L)[1])
  belge_sayisi <- suppressWarnings(as.integer(satir$BelgeSayisi %||% 0L)[1])
  son_etkinlik <- as.character(satir$SonEtkinlikZamani %||% "")[1]

  kaynak_etiketi <- if (identical(kaynak, "BilgeYolaç")) "Bilge Yolaç" else "Söyleşi"

  div(
    class = "oo-oturum-karti",
    `data-oo-oturum-id` = as.character(oturum_id),
    div(
      class = "oo-kart-baslik",
      icon(if (identical(kaynak, "BilgeYolaç")) "robot" else "comments", class = "oo-kart-ikon"),
      tags$span(class = "oo-kart-baslik-metin", HTML(htmltools::htmlEscape(baslik)))
    ),
    div(
      class = "oo-kart-rozetler",
      tags$span(class = "oo-rozet oo-rozet-kaynak", kaynak_etiketi),
      tags$span(class = "oo-rozet oo-rozet-durum", HTML(htmltools::htmlEscape(durum))),
      if (nzchar(rol)) tags$span(class = "oo-rozet oo-rozet-rol", HTML(htmltools::htmlEscape(rol))) else NULL
    ),
    div(
      class = "oo-kart-meta",
      tags$span(tagList(icon("users"), span(sprintf(" %d katılımcı", katilimci_sayisi)))),
      tags$span(tagList(icon("file-lines"), span(sprintf(" %d belge", belge_sayisi)))),
      if (nzchar(son_etkinlik)) {
        tags$span(tagList(icon("clock"), span(paste0(" ", son_etkinlik))))
      } else {
        NULL
      }
    ),
    div(
      class = "oo-kart-aksiyonlar",
      tags$button(
        type = "button",
        class = "btn-modern btn-primary oo-btn-oturum-ac",
        `data-oo-oturum-id` = as.character(oturum_id),
        `data-oo-hedef-input` = ac_input_id,
        `aria-label` = paste("Ortak oturumu aç:", baslik),
        tagList(icon("door-open"), span("Aç"))
      ),
      tags$button(
        type = "button",
        class = "btn-modern oo-btn-oturum-arsiv",
        `data-oo-oturum-id` = as.character(oturum_id),
        `data-oo-hedef-input` = arsiv_input_id,
        `aria-label` = if (arsivde) "Ortak oturumu listeye geri yükle" else "Ortak oturumu kendi listemde arşivle",
        if (arsivde) tagList(icon("rotate-left"), span("Geri Yükle")) else tagList(icon("box-archive"), span("Arşivle"))
      )
    )
  )
}

# Davet kartı: yalnızca davet metadata'sı (içerik erişimi YOK).
oo_davet_karti <- function(satir, kabul_input_id, red_input_id) {
  davet_id <- suppressWarnings(as.integer(satir$DavetID %||% NA_integer_)[1])
  baslik <- as.character(satir$Baslik %||% "Ortak Oturum")[1]
  davet_eden <- as.character(satir$DavetEdenAdi %||% "")[1]
  rol <- as.character(satir$Rol %||% "")[1]
  kaynak <- as.character(satir$KaynakTuru %||% "NormalSohbet")[1]
  katilimci_sayisi <- suppressWarnings(as.integer(satir$KatilimciSayisi %||% 0L)[1])

  div(
    class = "oo-oturum-karti oo-davet-karti",
    `data-oo-davet-id` = as.character(davet_id),
    div(
      class = "oo-kart-baslik",
      icon("envelope-open-text", class = "oo-kart-ikon"),
      tags$span(class = "oo-kart-baslik-metin", HTML(htmltools::htmlEscape(baslik)))
    ),
    div(
      class = "oo-kart-meta",
      tags$span(HTML(htmltools::htmlEscape(sprintf("%s sizi bu ortak çalışmaya davet ediyor.", davet_eden)))),
      tags$span(HTML(htmltools::htmlEscape(sprintf("Rol: %s · %d katılımcı · %s", rol, katilimci_sayisi,
                                                   if (identical(kaynak, "BilgeYolaç")) "Bilge Yolaç" else "Söyleşi"))))
    ),
    div(
      class = "oo-kart-aksiyonlar",
      tags$button(
        type = "button",
        class = "btn-modern btn-primary oo-btn-davet-kabul",
        `data-oo-davet-id` = as.character(davet_id),
        `data-oo-hedef-input` = kabul_input_id,
        `aria-label` = paste("Daveti kabul et:", baslik),
        tagList(icon("check"), span("Katıl"))
      ),
      tags$button(
        type = "button",
        class = "btn-modern oo-btn-davet-red",
        `data-oo-davet-id` = as.character(davet_id),
        `data-oo-hedef-input` = red_input_id,
        `aria-label` = paste("Daveti reddet:", baslik),
        tagList(icon("xmark"), span("Reddet"))
      )
    )
  )
}

# --- Sunucu ---------------------------------------------------------------------

ortakCalismalarServer <- function(id, current_user_id, parent_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    aktif_oturum <- reactiveVal(NULL)
    liste_yenile <- reactiveVal(0L)
    gosterilen_bildirimler <- reactiveVal(integer(0))

    oo_hub_bildir <- function(mesaj, tur = "message") {
      shiny::showNotification(mesaj, type = tur, duration = 6)
    }

    yenile <- function(neden = "manual") {
      liste_yenile(isolate(liste_yenile()) + 1L)
      invisible(neden)
    }

    gecerli_kullanici <- function() {
      uid <- suppressWarnings(as.integer(current_user_id())[1])
      if (is.na(uid) || uid <= 0L) NA_integer_ else uid
    }

    # Oda sunucusu bir kez bağlanır; hub yüzeyindeki dinamik oda UI'sine hizmet eder.
    oda <- ortakOturumRoomServer(
      "oda",
      current_user_id = current_user_id,
      aktif_oturum = aktif_oturum,
      on_close = function() {
        aktif_oturum(NULL)
        yenile("oda_kapandi")
      },
      parent_session = parent_session
    )

    # --- Kalp atışı (JS 30 sn'de bir gönderir) --------------------------------

    son_kalp_atisi_yazimi <- reactiveVal(NULL)

    observeEvent(input$canli_kalp_atisi, {
      uid <- gecerli_kullanici()
      if (is.na(uid) || !ortak_db_tablolar_hazir_mi()) {
        return(invisible(NULL))
      }

      # SQL Server'ı korumak için sunucu tarafı kısma: 20 sn'den sık yazılmaz.
      onceki <- isolate(son_kalp_atisi_yazimi())
      if (!is.null(onceki) &&
          as.numeric(difftime(Sys.time(), onceki, units = "secs")) < 20) {
        return(invisible(NULL))
      }
      son_kalp_atisi_yazimi(Sys.time())

      ortak_db_kalp_atisi(
        kullanici_id = uid,
        oturum_anahtari = session$token,
        sayfa = as.character(input$canli_kalp_atisi$sayfa %||% "")[1],
        gorulen_ortak_oturum_id = aktif_oturum()
      )

      # Bakım temizliği oturum başına en fazla bir kez, fırsatçı tetiklenir.
      if (!isTRUE(session$userData$oo_bakim_yapildi)) {
        session$userData$oo_bakim_yapildi <- TRUE
        ortak_db_bakim_temizlik()
      }
    })
    ortak_canli_durum_oturum_temizligi_bagla(session)

    # --- Bildirim yoklaması: Mergen içi davet/çağrı modalı --------------------

    observe({
      invalidateLater(20000, session)

      uid <- gecerli_kullanici()
      if (is.na(uid) || !ortak_db_tablolar_hazir_mi()) {
        return(invisible(NULL))
      }

      bildirimler <- ortak_db_bildirimlerim(uid)
      if (!is.data.frame(bildirimler) || nrow(bildirimler) == 0L) {
        return(invisible(NULL))
      }

      gosterilenler <- isolate(gosterilen_bildirimler())
      yeni <- bildirimler[!(bildirimler$BildirimID %in% gosterilenler), , drop = FALSE]
      if (nrow(yeni) == 0L) {
        return(invisible(NULL))
      }

      ilk <- yeni[1, , drop = FALSE]
      gosterilen_bildirimler(c(gosterilenler, as.integer(ilk$BildirimID[1])))

      showModal(modalDialog(
        title = "Ortak Oturum Çağrısı",
        div(
          class = "oo-bildirim-modal",
          p(class = "oo-bildirim-baslik", HTML(htmltools::htmlEscape(as.character(ilk$Baslik[1])))),
          p(class = "oo-bildirim-detay", HTML(htmltools::htmlEscape(
            paste("Ortak çalışma:", as.character(ilk$Mesaj[1] %||% ""))
          )))
        ),
        footer = tagList(
          actionButton(ns("bildirim_katil"), "Katıl", class = "btn-primary",
                       `data-oo-bildirim-id` = as.character(ilk$BildirimID[1])),
          actionButton(ns("bildirim_sonra"), "Daha Sonra"),
          actionButton(ns("bildirim_reddet"), "Reddet", class = "btn-danger")
        )
      ))

      session$userData$oo_son_bildirim <- list(
        bildirim_id = as.integer(ilk$BildirimID[1]),
        oturum_id = suppressWarnings(as.integer(ilk$IlgiliOturumID[1]))
      )
    })

    bildirim_davetini_bul <- function(oturum_id) {
      davetler <- ortak_db_davetlerim(gecerli_kullanici())
      if (!is.data.frame(davetler) || nrow(davetler) == 0L) {
        return(NA_integer_)
      }
      eslesen <- davetler[davetler$OrtakOturumID == oturum_id, , drop = FALSE]
      if (nrow(eslesen) == 0L) {
        return(NA_integer_)
      }
      as.integer(eslesen$DavetID[1])
    }

    observeEvent(input$bildirim_katil, {
      son <- session$userData$oo_son_bildirim
      req(is.list(son))

      ortak_db_bildirim_okundu(son$bildirim_id, gecerli_kullanici())

      davet_id <- bildirim_davetini_bul(son$oturum_id)
      if (!is.na(davet_id) &&
          isTRUE(ortak_db_davet_yanitla(davet_id, gecerli_kullanici(), kabul = TRUE))) {
        oo_hub_bildir("Davet kabul edildi; ortak oturum açılıyor.")
        aktif_oturum(son$oturum_id)
        if (!is.null(parent_session)) {
          shinydashboard::updateTabItems(parent_session, "tabs", "ortak_calismalar")
        }
      } else {
        oo_hub_bildir("Davet bulunamadı veya yanıtlanamadı.", tur = "warning")
      }

      removeModal()
      yenile("bildirim_katil")
    })

    observeEvent(input$bildirim_sonra, {
      son <- session$userData$oo_son_bildirim
      if (is.list(son)) {
        ortak_db_bildirim_okundu(son$bildirim_id, gecerli_kullanici())
      }
      removeModal()
      oo_hub_bildir("Davet, Ortak Çalışmalarım > Davetlerim bölümünde bekliyor.")
    })

    observeEvent(input$bildirim_reddet, {
      son <- session$userData$oo_son_bildirim
      req(is.list(son))

      ortak_db_bildirim_okundu(son$bildirim_id, gecerli_kullanici())

      davet_id <- bildirim_davetini_bul(son$oturum_id)
      if (!is.na(davet_id)) {
        ortak_db_davet_yanitla(davet_id, gecerli_kullanici(), kabul = FALSE)
      }

      removeModal()
      yenile("bildirim_reddet")
    })

    # --- Liste görünümleri -----------------------------------------------------

    liste_olustur <- function(df, arsivde = FALSE, bos_mesaj = "Henüz ortak oturum yok.") {
      if (!is.data.frame(df) || nrow(df) == 0L) {
        return(div(class = "oo-bos-durum oo-bos-liste", icon("users"), p(bos_mesaj)))
      }

      tagList(lapply(seq_len(nrow(df)), function(i) {
        oo_liste_karti(
          df[i, , drop = FALSE],
          ac_input_id = ns("oturum_ac"),
          arsiv_input_id = if (arsivde) ns("oturum_geri_yukle") else ns("oturum_arsivle"),
          arsivde = arsivde
        )
      }))
    }

    output$liste_hub <- renderUI({
      liste_yenile()
      if (!is.null(aktif_oturum())) {
        return(NULL)
      }

      uid <- gecerli_kullanici()
      if (is.na(uid)) {
        return(div(class = "oo-bos-durum", p("Kimlik doğrulaması tamamlanıyor...")))
      }

      if (!ortak_db_tablolar_hazir_mi()) {
        return(div(
          class = "oo-bos-durum oo-tablo-yok",
          icon("database"),
          p("Ortak Oturum tabloları henüz kurulmamış. Kurulum: docs/sql/2026-07-ortak-oturumlar.sql (DBA/operatör)." )
        ))
      }

      filtre <- as.character(input$hub_filtre %||% "Tümü")[1]

      if (identical(filtre, "Davetlerim")) {
        davetler <- ortak_db_davetlerim(uid)
        if (!is.data.frame(davetler) || nrow(davetler) == 0L) {
          return(div(class = "oo-bos-durum", icon("envelope"), p("Bekleyen davetiniz yok.")))
        }
        return(tagList(lapply(seq_len(nrow(davetler)), function(i) {
          oo_davet_karti(
            davetler[i, , drop = FALSE],
            kabul_input_id = ns("davet_kabul"),
            red_input_id = ns("davet_red")
          )
        })))
      }

      arsivde <- identical(filtre, "Arşivlenmiş Ortak Oturumlar")
      liste_olustur(
        ortak_db_oturum_listesi(uid, arsiv_gorunumu = arsivde),
        arsivde = arsivde,
        bos_mesaj = if (arsivde) "Arşivlenmiş ortak oturum yok." else "Henüz ortak oturum yok. “Yeni Ortak Oturum” ile başlayın."
      )
    })

    output$liste_sohbet <- renderUI({
      liste_yenile()
      uid <- gecerli_kullanici()
      req(!is.na(uid))
      liste_olustur(
        ortak_db_oturum_listesi(uid, kaynak_turu = "NormalSohbet"),
        bos_mesaj = "Henüz ortak söyleşi yok."
      )
    })

    output$liste_bilge_yolac <- renderUI({
      liste_yenile()
      uid <- gecerli_kullanici()
      req(!is.na(uid))
      liste_olustur(
        ortak_db_oturum_listesi(uid, kaynak_turu = "BilgeYolaç"),
        bos_mesaj = "Henüz ortak Bilge Yolaç oturumu yok."
      )
    })

    output$oda_alani <- renderUI({
      req(aktif_oturum())
      ortakOturumRoomUI(ns("oda"))
    })

    # Oda açık/kapalı durumu hub kabuğuna yansır; kök sınıfı (oo-oda-acik-kok)
    # paylaşılan .content-wrapper üzerinde SEKMEYE DUYARLI merkez güncelleyici
    # (MergenOrtakOturum.kokGuncelle; köprü yoksa eski toggle) ile yönetilir.
    observeEvent(aktif_oturum(), {
      acik <- !is.null(aktif_oturum())
      shinyjs::runjs(sprintf(
        "(function(){var acik=%s;var k=document.querySelector('.ortak-calismalar-container[data-oo-sayfa=\"hub\"]');if(k){k.classList.toggle('oo-oda-acik', acik);}if(window.MergenOrtakOturum&&typeof window.MergenOrtakOturum.kokGuncelle==='function'){window.MergenOrtakOturum.kokGuncelle();}else{var c=document.querySelector('.content-wrapper');if(c){c.classList.toggle('oo-oda-acik-kok', acik);}}})();",
        if (acik) "true" else "false"
      ))
    }, ignoreNULL = FALSE)

    # --- Kart eylemleri ---------------------------------------------------------

    observeEvent(input$oturum_ac, {
      oturum_id <- suppressWarnings(as.integer(input$oturum_ac$id))
      req(!is.na(oturum_id))

      katilim <- ortak_db_katilimci_getir(oturum_id, gecerli_kullanici())
      if (is.null(katilim) || !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1])) {
        oo_hub_bildir("Bu odayı açmak için önce daveti kabul etmelisiniz.", tur = "warning")
        return(invisible(NULL))
      }

      aktif_oturum(oturum_id)
      if (!is.null(parent_session)) {
        shinydashboard::updateTabItems(parent_session, "tabs", "ortak_calismalar")
      }
    })

    observeEvent(input$oturum_arsivle, {
      oturum_id <- suppressWarnings(as.integer(input$oturum_arsivle$id))
      req(!is.na(oturum_id))

      # Kullanıcı bazlı arşiv: yalnızca bu kullanıcının listesinden gizlenir.
      ortak_db_kullanici_gorunum_guncelle(oturum_id, gecerli_kullanici(), "KullanıcıArşivledi")
      oo_hub_bildir("Ortak oturum kendi listenizde arşivlendi (diğer katılımcılar etkilenmez).")
      yenile("arsiv")
    })

    observeEvent(input$oturum_geri_yukle, {
      oturum_id <- suppressWarnings(as.integer(input$oturum_geri_yukle$id))
      req(!is.na(oturum_id))

      uid <- gecerli_kullanici()

      # Her zaman kullanıcı görünümünü geri getir.
      ortak_db_kullanici_gorunum_guncelle(oturum_id, uid, "Görünüyor")

      # Oda düzeyi arşiv (Arşivlendi/Kapandı) ise: yetkili kullanıcı (Sahip)
      # odayı herkes için yeniden Aktif yapar. Yetkisi yoksa yalnızca kendi
      # görünümü geri gelir ve durum açıkça bildirilir.
      bilgi <- ortak_db_oturum_getir(oturum_id)
      oda_arsivli <- !is.null(bilgi) &&
        as.character(bilgi$OturumDurumu[1]) %in% c("Arşivlendi", "Kapandı")

      if (oda_arsivli) {
        katilim <- ortak_db_katilimci_getir(oturum_id, uid)
        yetkili <- !is.null(katilim) && ortak_yetki_var_mi(katilim$Rol[1], "oturum_kapat")

        if (yetkili) {
          if (isTRUE(ortak_db_oturum_durum_guncelle(oturum_id, uid, "Aktif"))) {
            ortak_db_olay_ekle(oturum_id, "OturumGeriYüklendi", uid)
            oo_hub_bildir("Ortak oturum herkes için geri yüklendi (yeniden aktif).")
          } else {
            oo_hub_bildir("Ortak oturum geri yüklenemedi.", tur = "error")
          }
        } else {
          oo_hub_bildir(
            "Bu oda tüm katılımcılar için arşivlendi; yalnızca Sahip yeniden aktifleştirebilir. Kendi listenizden gizlemeyi kaldırdınız.",
            tur = "warning"
          )
        }
      } else {
        oo_hub_bildir("Ortak oturum listenize geri yüklendi.")
      }

      yenile("geri_yukle")
    })

    davet_oturumunu_bul <- function(davet_id) {
      davetler <- ortak_db_davetlerim(gecerli_kullanici())
      if (!is.data.frame(davetler) || nrow(davetler) == 0L) {
        return(NA_integer_)
      }
      eslesen <- davetler[davetler$DavetID == davet_id, , drop = FALSE]
      if (nrow(eslesen) == 0L) {
        return(NA_integer_)
      }
      as.integer(eslesen$OrtakOturumID[1])
    }

    observeEvent(input$davet_kabul, {
      davet_id <- suppressWarnings(as.integer(input$davet_kabul$id))
      req(!is.na(davet_id))

      oturum_id <- davet_oturumunu_bul(davet_id)

      if (isTRUE(ortak_db_davet_yanitla(davet_id, gecerli_kullanici(), kabul = TRUE))) {
        if (!is.na(oturum_id)) {
          ortak_db_olay_ekle(oturum_id, "KullanıcıKatıldı", gecerli_kullanici())
        }
        oo_hub_bildir("Davet kabul edildi; oturum listenize eklendi.")
      } else {
        oo_hub_bildir("Davet yanıtlanamadı.", tur = "error")
      }
      yenile("davet_kabul")
    })

    observeEvent(input$davet_red, {
      davet_id <- suppressWarnings(as.integer(input$davet_red$id))
      req(!is.na(davet_id))

      oturum_id <- davet_oturumunu_bul(davet_id)

      ortak_db_davet_yanitla(davet_id, gecerli_kullanici(), kabul = FALSE)
      if (!is.na(oturum_id)) {
        ortak_db_olay_ekle(oturum_id, "DavetReddedildi", gecerli_kullanici())
      }
      oo_hub_bildir("Davet reddedildi.")
      yenile("davet_red")
    })

    # --- Yeni ortak oturum ------------------------------------------------------

    observeEvent(input$yeni_ortak_oturum, {
      showModal(modalDialog(
        title = "Yeni Ortak Oturum",
        size = "l",
        div(
          class = "oo-yeni-oturum-modal",
          radioButtons(
            ns("yeni_kaynak_turu"),
            label = "Oturum Türü",
            choices = c("Ortak Söyleşi" = "NormalSohbet", "Ortak Bilge Yolaç" = "BilgeYolaç"),
            selected = "NormalSohbet"
          ),
          textInput(ns("yeni_baslik"), label = "Başlık", placeholder = "Ortak çalışma başlığı..."),
          uiOutput(ns("yeni_paylasim_alani"))
        ),
        footer = tagList(
          actionButton(ns("yeni_olustur"), tagList(icon("plus"), span("Oluştur")), class = "oo-oda-btn oo-oda-btn-birincil"),
          modalButton("Vazgeç")
        )
      ))
    })

    output$yeni_paylasim_alani <- renderUI({
      kaynak <- as.character(input$yeni_kaynak_turu %||% "NormalSohbet")[1]
      tipler <- ortak_paylasim_baslangic_tipleri(kaynak)

      etiketler <- if (identical(kaynak, "BilgeYolaç")) {
        c(
          "Sadece yeni çalıştırmaları ortak yap (önerilen)",
          "Mevcut geçmişi salt okunur özet olarak aktar",
          "Tüm geçmişi ve üretilen belgeleri ortak oturuma kopyala"
        )
      } else {
        c(
          "Sadece bundan sonrasını ortak yap (önerilen)",
          "Mevcut geçmişin bir kopyasını ortak oturuma aktar",
          "Boş ortak oturum oluştur"
        )
      }

      radioButtons(
        ns("yeni_paylasim_tipi"),
        label = "Paylaşım Başlangıcı",
        choices = stats::setNames(tipler, etiketler),
        selected = tipler[1]
      )
    })

    observeEvent(input$yeni_olustur, {
      uid <- gecerli_kullanici()
      req(!is.na(uid))

      baslik <- trimws(as.character(input$yeni_baslik %||% "")[1])
      if (!nzchar(baslik)) {
        oo_hub_bildir("Lütfen bir başlık girin.", tur = "warning")
        return(invisible(NULL))
      }

      kaynak <- as.character(input$yeni_kaynak_turu %||% "NormalSohbet")[1]

      oturum_id <- ortak_db_oturum_olustur(
        kaynak_turu = kaynak,
        baslik = baslik,
        olusturan_kullanici_id = uid,
        paylasim_tipi = as.character(input$yeni_paylasim_tipi %||% "")[1]
      )

      if (is.null(oturum_id)) {
        oo_hub_bildir("Ortak oturum oluşturulamadı (tablolar kurulu mu?).", tur = "error")
        return(invisible(NULL))
      }

      # Ortak Bilge Yolaç oturumları için 1:1 çalışma alanı kaydı da açılır.
      if (identical(kaynak, "BilgeYolaç")) {
        ortak_db_by_oturum_olustur(oturum_id)
      }

      ortak_db_olay_ekle(oturum_id, "KullanıcıKatıldı", uid)
      removeModal()

      paylasim <- as.character(input$yeni_paylasim_tipi %||% "")[1]

      # Geçmiş kopyalama açık onaylı bir adımdır: "GeçmişKopyasıAktarıldı"
      # seçildiyse hemen odaya girmeden ÖNCE kişisel söyleşi seçtiren onay
      # modalı açılır (kaynak kişisel kayıt DEĞİŞMEZ).
      if (identical(kaynak, "NormalSohbet") &&
          identical(paylasim, "GeçmişKopyasıAktarıldı")) {
        gecmis_kopya_hedef_oturum(oturum_id)
        oo_hub_bildir("Ortak oturum oluşturuldu. Kopyalanacak kişisel söyleşiyi seçin.")
        gecmis_kopya_modali_ac(oturum_id)
        yenile("olusturuldu")
        return(invisible(NULL))
      }

      oo_hub_bildir("Ortak oturum oluşturuldu.")
      aktif_oturum(oturum_id)
      yenile("olusturuldu")
    })

    # --- Kişisel geçmiş kopyalama (açık onaylı) --------------------------------

    gecmis_kopya_hedef_oturum <- reactiveVal(NULL)

    gecmis_kopya_modali_ac <- function(oturum_id) {
      uid <- gecerli_kullanici()
      sohbetler <- tryCatch(
        load_chats_preview_from_db(uid, limit = 30L),
        error = function(e) list()
      )

      secenekler <- list()
      if (length(sohbetler) > 0L) {
        for (s in sohbetler) {
          cid <- suppressWarnings(as.integer(s$id %||% s$chat_id %||% NA_integer_))
          baslik <- as.character(s$title %||% s$name %||% "Söyleşi")[1]
          if (!is.na(cid)) {
            secenekler[[baslik]] <- cid
          }
        }
      }

      showModal(modalDialog(
        title = "Kişisel Söyleşi Geçmişini Kopyala",
        if (length(secenekler) == 0L) {
          p("Kopyalanabilir kişisel söyleşiniz bulunamadı. Odaya boş başlayabilirsiniz.")
        } else {
          tagList(
            p(class = "oo-kopya-notu",
              "Seçtiğiniz kişisel söyleşinin bir KOPYASI ortak oturuma aktarılır. Kaynak kişisel kaydınız değişmez."),
            selectInput(
              ns("gecmis_kopya_chat"),
              label = "Kopyalanacak söyleşi",
              choices = secenekler,
              selectize = FALSE
            )
          )
        },
        footer = tagList(
          if (length(secenekler) > 0L) {
            actionButton(ns("gecmis_kopya_onayla"), tagList(icon("copy"), span("Kopyala ve Odaya Gir")),
                         class = "btn-primary")
          } else {
            NULL
          },
          actionButton(ns("gecmis_kopya_atla"), "Boş Başla")
        )
      ))
    }

    observeEvent(input$gecmis_kopya_onayla, {
      oturum_id <- gecmis_kopya_hedef_oturum()
      chat_id <- suppressWarnings(as.integer(input$gecmis_kopya_chat))
      req(!is.null(oturum_id), !is.na(chat_id))

      sonuc <- ortak_db_gecmis_kopyala(oturum_id, gecerli_kullanici(), chat_id)
      oo_hub_bildir(sonuc$mesaj, tur = if (isTRUE(sonuc$basarili)) "message" else "warning")

      removeModal()
      aktif_oturum(oturum_id)
      yenile("gecmis_kopyalandi")
    })

    observeEvent(input$gecmis_kopya_atla, {
      oturum_id <- gecmis_kopya_hedef_oturum()
      removeModal()
      if (!is.null(oturum_id)) {
        aktif_oturum(oturum_id)
      }
      yenile("gecmis_atlandi")
    })

    list(
      refresh = yenile,
      aktif_oturum = aktif_oturum,
      oda = oda
    )
  })
}
