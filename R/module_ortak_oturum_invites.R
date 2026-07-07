# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_invites.R
# Açıklama: Ortak Oturum "Katılımcı Çağır" paneli bağlayıcısı: kullanıcı
#           arama/filtreleme, Mergen içi çağrı (bildirim), e-posta taslağı
#           hazırlama ve davet hız sınırı. Oda sunucu modülünden
#           (R/module_ortak_oturum_room.R) çağrılır; aynı modül input/output
#           bağlamını paylaşır.
#
# Sözleşmeler:
#   * Davet spam koruması: oturum başına 10 dakikada en çok 15 davet; aynı
#     kullanıcıya mevcut bekleyen davet varken ikinci davet üretilmez.
#   * E-posta OTOMATİK GÖNDERİLMEZ; yalnızca içerik sızdırmayan taslak
#     hazırlanır (helpers_ortak_oturum_email.R sözleşmesi).
#   * Davet yetkisi sunucu tarafında doğrulanır (davet_et; fail-closed).
# ==============================================================================

# Basit oturum-içi davet hız sınırı: pencere içinde kalan hak sayısını döner.
oo_davet_hiz_siniri_asildi_mi <- function(zaman_damgalari,
                                          simdi = Sys.time(),
                                          pencere_saniye = 600,
                                          en_fazla = 15L) {
  gecerli <- zaman_damgalari[
    as.numeric(difftime(simdi, zaman_damgalari, units = "secs")) <= pencere_saniye
  ]
  length(gecerli) >= en_fazla
}

ortakOturumInvitesBind <- function(input, output, session, ctx) {
  ns <- session$ns

  davet_zamanlari <- reactiveVal(as.POSIXct(character(0)))

  davet_gonderebilir_mi <- function() {
    zamanlar <- isolate(davet_zamanlari())
    if (oo_davet_hiz_siniri_asildi_mi(zamanlar)) {
      ctx$bildir("Davet hız sınırına ulaşıldı; lütfen birkaç dakika sonra tekrar deneyin.", tur = "warning")
      return(FALSE)
    }
    TRUE
  }

  davet_kaydet_zaman <- function() {
    davet_zamanlari(c(isolate(davet_zamanlari()), Sys.time()))
  }

  # Aynı kullanıcıya bekleyen davet / mevcut katılım varken tekrar davet edilmez.
  yinelenen_davet_mi <- function(oturum_id, hedef_id) {
    mevcut <- ortak_db_katilimci_getir(oturum_id, hedef_id)
    if (is.null(mevcut)) {
      return(FALSE)
    }
    mevcut$KatilimDurumu[1] %in% c("DavetEdildi", "Katıldı")
  }

  davet_eden_adi <- function() {
    mevcutlar <- ctx$katilimcilar()
    if (is.data.frame(mevcutlar) && nrow(mevcutlar) > 0L) {
      benim <- mevcutlar[mevcutlar$KullaniciID == as.integer(ctx$current_user_id()), , drop = FALSE]
      if (nrow(benim) > 0L) {
        return(as.character(benim$KaynakAdi[1] %||% ""))
      }
    }
    ""
  }

  observeEvent(input$oda_katilimci_cagir, {
    katilim <- ctx$benim_katilimim()
    if (is.null(katilim) || !ortak_yetki_var_mi(katilim$Rol[1], "davet_et")) {
      ctx$bildir("Katılımcı çağırma yetkiniz yok.", tur = "error")
      return(invisible(NULL))
    }

    showModal(modalDialog(
      title = "Katılımcı Çağır",
      size = "l",
      easyClose = TRUE,
      div(
        class = "oo-davet-paneli",
        radioButtons(
          ns("davet_filtre"),
          label = NULL,
          choices = c("Çevrim İçi Kullanıcılar", "Tüm Kullanıcılar", "Davet Edilenler"),
          selected = "Çevrim İçi Kullanıcılar",
          inline = TRUE
        ),
        textInput(
          ns("davet_arama"),
          label = NULL,
          placeholder = "Ad, kullanıcı adı, e-posta veya departman ara..."
        ),
        selectInput(
          ns("davet_rol"),
          label = "Atanacak Rol",
          choices = ortak_rol_secenekleri(),
          selected = "Katılımcı",
          selectize = FALSE
        ),
        div(class = "oo-davet-listesi", uiOutput(ns("davet_kullanici_listesi")))
      ),
      footer = modalButton("Kapat")
    ))
  })

  output$davet_kullanici_listesi <- renderUI({
    ctx$yenile_sayaci()
    # Modal açıkken canlı liste kendi kendine tazelensin (davet paneli ana oda
    # 4 sn yoklamasına ek olarak; başka sekmedeki kullanıcılar hızlı görünür).
    invalidateLater(6000, session)

    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    filtre <- as.character(input$davet_filtre %||% "Çevrim İçi Kullanıcılar")[1]
    kullanicilar <- ortak_db_kullanici_arama(input$davet_arama %||% "")

    if (!is.data.frame(kullanicilar) || nrow(kullanicilar) == 0L) {
      return(div(class = "oo-bos-durum", p("Eşleşen kullanıcı bulunamadı.")))
    }

    # Aktif satırlarla (Katıldı/DavetEdildi) mevcut davet/katılım durumu; çıkarılan
    # kullanıcılar yeniden davet edilebilsin diye sadece_aktif = TRUE kullanılır.
    mevcutlar <- ortak_db_katilimci_listesi(oturum_id)
    benim_id <- as.integer(ctx$current_user_id())

    satirlar <- lapply(seq_len(nrow(kullanicilar)), function(i) {
      satir <- kullanicilar[i, , drop = FALSE]
      kullanici_id <- as.integer(satir$UserID[1])

      if (identical(kullanici_id, benim_id)) {
        return(NULL)
      }

      durum <- ctx$kullanici_canli_durumu(kullanici_id)

      mevcut_durum <- ""
      if (is.data.frame(mevcutlar) && nrow(mevcutlar) > 0L) {
        eslesen <- mevcutlar[mevcutlar$KullaniciID == kullanici_id, , drop = FALSE]
        if (nrow(eslesen) > 0L) {
          mevcut_durum <- as.character(eslesen$KatilimDurumu[1])
        }
      }

      # Zaten katılmış kullanıcı davet listesinde tekrar gösterilmez.
      if (identical(mevcut_durum, "Katıldı")) {
        return(NULL)
      }

      # "Çevrim İçi Kullanıcılar": uygulamada aktif olan (Çevrimİçi + Boşta)
      # kullanıcılar; çevrim dışı olanlar bu görünümde gizlenir.
      if (identical(filtre, "Çevrim İçi Kullanıcılar") &&
          !(durum %in% c("Çevrimİçi", "Boşta"))) {
        return(NULL)
      }
      if (identical(filtre, "Davet Edilenler") && !identical(mevcut_durum, "DavetEdildi")) {
        return(NULL)
      }

      oo_davet_kullanici_html(
        satir,
        canli_durum = durum,
        cagir_input_id = ns("davet_cagir"),
        eposta_input_id = ns("davet_eposta"),
        mevcut_durum = mevcut_durum
      )
    })

    satirlar <- Filter(Negate(is.null), satirlar)
    if (length(satirlar) == 0L) {
      bos_mesaj <- switch(
        filtre,
        "Çevrim İçi Kullanıcılar" = "Şu an çevrim içi başka kullanıcı yok. “Tüm Kullanıcılar” sekmesinden davet edebilirsiniz.",
        "Davet Edilenler" = "Henüz bekleyen davet yok.",
        "Gösterilecek kullanıcı yok."
      )
      return(div(class = "oo-bos-durum", icon("user-group"), p(bos_mesaj)))
    }

    tagList(satirlar)
  })

  # Mergen içinden çağır: davet kaydı + uygulama içi bildirim.
  observeEvent(input$davet_cagir, {
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    hedef_id <- suppressWarnings(as.integer(input$davet_cagir$id))
    req(!is.na(hedef_id))

    if (!davet_gonderebilir_mi()) {
      return(invisible(NULL))
    }

    if (yinelenen_davet_mi(oturum_id, hedef_id)) {
      ctx$bildir("Bu kullanıcı zaten davetli veya katılımcı.", tur = "warning")
      return(invisible(NULL))
    }

    davet_id <- ortak_db_davet_olustur(
      oturum_id = oturum_id,
      davet_eden_kullanici_id = ctx$current_user_id(),
      davet_edilen_kullanici_id = hedef_id,
      rol = as.character(input$davet_rol %||% "Katılımcı")[1],
      davet_yontemi = "Mergenİçi"
    )

    if (is.null(davet_id)) {
      ctx$bildir("Davet oluşturulamadı.", tur = "error")
      return(invisible(NULL))
    }

    davet_kaydet_zaman()
    bilgi <- ctx$oturum_bilgisi()
    ad <- davet_eden_adi()

    ortak_db_bildirim_ekle(
      alici_kullanici_id = hedef_id,
      bildirim_turu = "OrtakOturumÇağrı",
      baslik = sprintf(
        "%s sizi ortak oturuma çağırıyor.",
        if (nzchar(ad)) ad else "Bir katılımcı"
      ),
      mesaj = as.character(bilgi$Baslik[1] %||% "Ortak Çalışma"),
      gonderen_kullanici_id = ctx$current_user_id(),
      ilgili_oturum_id = oturum_id
    )

    ortak_db_olay_ekle(oturum_id, "DavetGönderildi", ctx$current_user_id())
    ctx$bildir("Davet gönderildi; kullanıcı Mergen içinden yanıtlayabilir.")
    ctx$yenile()
  })

  # E-posta taslağı: davet kaydı + güvenli (içeriksiz) mailto taslağı modalı.
  observeEvent(input$davet_eposta, {
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    hedef_id <- suppressWarnings(as.integer(input$davet_eposta$id))
    req(!is.na(hedef_id))

    if (!davet_gonderebilir_mi()) {
      return(invisible(NULL))
    }

    if (yinelenen_davet_mi(oturum_id, hedef_id)) {
      ctx$bildir("Bu kullanıcı zaten davetli veya katılımcı.", tur = "warning")
      return(invisible(NULL))
    }

    kullanicilar <- ortak_db_kullanici_arama("")
    hedef <- kullanicilar[kullanicilar$UserID == hedef_id, , drop = FALSE]
    if (nrow(hedef) == 0L || !nzchar(as.character(hedef$Email[1] %||% ""))) {
      ctx$bildir("Kullanıcının kayıtlı e-posta adresi yok.", tur = "warning")
      return(invisible(NULL))
    }

    davet_id <- ortak_db_davet_olustur(
      oturum_id = oturum_id,
      davet_eden_kullanici_id = ctx$current_user_id(),
      davet_edilen_kullanici_id = hedef_id,
      rol = as.character(input$davet_rol %||% "Katılımcı")[1],
      davet_yontemi = "Eposta",
      davet_edilen_eposta = as.character(hedef$Email[1])
    )

    if (is.null(davet_id)) {
      ctx$bildir("Davet oluşturulamadı.", tur = "error")
      return(invisible(NULL))
    }

    davet_kaydet_zaman()
    bilgi <- ctx$oturum_bilgisi()
    ad <- davet_eden_adi()

    taslak <- ortak_davet_eposta_metni(ad, as.character(bilgi$Baslik[1] %||% ""))
    href <- ortak_davet_eposta_taslak_href(
      as.character(hedef$Email[1]),
      ad,
      as.character(bilgi$Baslik[1] %||% "")
    )

    ortak_db_davet_gonderim_isaretle(davet_id)
    ortak_db_olay_ekle(oturum_id, "DavetGönderildi", ctx$current_user_id())

    showModal(modalDialog(
      title = "E-posta Taslağı Hazır",
      p(class = "oo-eposta-notu", paste(
        "Taslak yalnızca davet bilgisini içerir; oturum içeriği, yapay zekâ",
        "yanıtı veya belge bağlantısı e-postaya EKLENMEZ. Gözden geçirip",
        "kendi e-posta istemcinizden gönderin."
      )),
      tags$pre(class = "oo-eposta-taslagi", htmltools::htmlEscape(taslak$govde)),
      footer = tagList(
        tags$a(
          href = href,
          class = "btn btn-primary oo-btn-eposta-ac",
          target = "_blank",
          rel = "noopener",
          "E-posta Taslağını Aç"
        ),
        modalButton("Kapat")
      )
    ))
  })

  invisible(TRUE)
}
