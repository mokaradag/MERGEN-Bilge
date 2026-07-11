# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_belge_paneli.R
# Açıklama: Ortak Belgeler paneli sunucu bağlayıcısı + belge kartı/yükleme
#           alanı SAF HTML üreticileri ve "Sohbeti Temizle" (kalıcı) onay
#           akışı. Oda sunucu modülünden (R/module_ortak_oturum_room.R)
#           çağrılır; aynı input/output bağlamını paylaşır. Oda modülünün
#           bakım bütçesini korumak için bu yüzeyler ayrı dosyadadır.
#
# Sözleşmeler:
#   * Ortak Belgeler artık paylaşılan MODEL GİRDİSİDİR: yetkili katılımcı
#     (yapay_zeka_sor) belge yükler/kaldırır/seçer; yalnızca SEÇİLİ belgeler
#     sonraki yapay zekâ sorusunun bağlamına girer.
#   * Her eylem sunucu tarafında fail-closed yetki doğrulamasından geçer
#     (helpers_ortak_oturum_belgeler.R); UI gizlemesi güvenlik değildir.
#   * "Sohbeti Temizle" bağlam sıfırlamadan FARKLIDIR ve açık onay modalı
#     olmadan çalışmaz (geri alınamaz eylem).
#   * Tüm kullanıcı metinleri escape edilir (XSS sınırı); kimlikler CSS
#     seçicisine gömülmez (dataset + delege JS köprüsü).
# ==============================================================================

# Ortak belge kartı (SAF): metadata + bağlam seçim kutusu + kaldırma +
# "Kendi Dosyalarıma Kaydet". Eski iki-argümanlı çağrılarla geriye dönük
# uyumludur (secim/sil kimlikleri verilmezse o eylemler çizilmez).
# baglam_secimi = FALSE: bağlam seçim kutusu VE "Bağlamda" rozeti hiç
# çizilmez (BilgeYolaç odaları: belgeler yapay zekâ bağlamına girmez; kart
# bunu ima etmemelidir).
oo_dosya_karti_html <- function(satir,
                                kopyala_input_id,
                                secim_input_id = NULL,
                                sil_input_id = NULL,
                                yetkili = FALSE,
                                baglam_secimi = TRUE) {
  ad <- as.character(satir$DosyaAdi %||% "belge")[1]
  ureten <- as.character(satir$UretenAdi %||% "")[1]
  zaman <- as.character(satir$OlusturmaZamani %||% "")[1]
  kopya_durumu <- as.character(satir$KopyalamaDurumu %||% "")[1]
  dosya_id <- suppressWarnings(as.integer(satir$OrtakDosyaID %||% NA_integer_)[1])

  meta <- if (exists("ortak_belge_meta", mode = "function", inherits = TRUE)) {
    ortak_belge_meta(satir$MetaJson %||% "")
  } else {
    list(kaynak = "", secili = FALSE)
  }
  yukleme_mi <- identical(meta$kaynak, "KatilimciYuklemesi")

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

  secim_kutusu <- NULL
  if (!isTRUE(baglam_secimi)) {
    secim_kutusu <- NULL
  } else if (!is.null(secim_input_id) && isTRUE(yetkili)) {
    secim_kutusu <- tags$label(
      class = "oo-belge-secim",
      title = "Seçili belgeler bir sonraki yapay zekâ sorusunun bağlamına dahil edilir",
      tags$input(
        type = "checkbox",
        class = "oo-belge-secim-kutu",
        `data-oo-secim-input` = secim_input_id,
        `data-oo-dosya-id` = as.character(dosya_id),
        checked = if (isTRUE(meta$secili)) "checked" else NULL,
        `aria-label` = paste("Belgeyi yapay zekâ bağlamına dahil et:", ad)
      ),
      tags$span(class = "oo-belge-secim-etiket", "Bağlama dahil et")
    )
  } else if (isTRUE(meta$secili)) {
    secim_kutusu <- tags$span(
      class = "oo-rozet oo-rozet-baglamda",
      tagList(icon("wand-magic-sparkles"), span("Bağlamda"))
    )
  }

  sil_dugmesi <- NULL
  if (!is.null(sil_input_id) && isTRUE(yetkili)) {
    sil_dugmesi <- tags$button(
      type = "button",
      class = "oo-btn-belge-sil",
      `data-oo-dosya-id` = as.character(dosya_id),
      `data-oo-hedef-input` = sil_input_id,
      `aria-label` = paste("Ortak belgeyi kaldır:", ad),
      title = "Belgeyi ortak oturumdan kaldır",
      icon("trash-can")
    )
  }

  div(
    class = paste(
      "oo-belge-karti",
      if (isTRUE(baglam_secimi) && isTRUE(meta$secili)) "oo-belge-secili" else NULL
    ),
    `data-oo-dosya-id` = as.character(dosya_id),
    div(
      class = "oo-belge-ust",
      icon("file-lines", class = "oo-belge-ikon"),
      tags$span(class = "oo-belge-ad", title = ad, HTML(htmltools::htmlEscape(ad))),
      sil_dugmesi
    ),
    div(
      class = "oo-belge-meta",
      tags$span(
        class = paste("oo-rozet", if (yukleme_mi) "oo-rozet-yukleme" else "oo-rozet-uretilen"),
        if (yukleme_mi) "Yükleme" else "Üretildi"
      ),
      if (nzchar(boyut_metni)) tags$span(boyut_metni) else NULL,
      if (nzchar(ureten)) tags$span(HTML(htmltools::htmlEscape(paste("Ekleyen:", ureten)))) else NULL,
      tags$span(HTML(htmltools::htmlEscape(zaman)))
    ),
    div(
      class = "oo-belge-aksiyonlar",
      secim_kutusu,
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

# Belge yükleme alanı (SAF): kompakt sürükle-bırak yüzeyi + "Belge Seç"
# eylemi + tür/boyut ipucu. Gerçek bırakma davranışı www/js/ortak_oturumlar.js
# içindeki delege data-oo-belge-drop köprüsüyle çalışır (dosyalar gizli
# fileInput'a atanır; mevcut doğrulanmış sunucu yolu değişmez). Yalnızca
# yetkili katılımcıya çizilir; sunucu tarafı doğrulama yine de zorunludur.
oo_belge_yukleme_alani_html <- function(yukle_input_id, izinli_uzantilar, limit_mb) {
  ornek_turler <- toupper(utils::head(as.character(izinli_uzantilar), 5L))
  tur_ipucu <- if (length(izinli_uzantilar) > 5L) {
    paste0(paste(ornek_turler, collapse = ", "), "…")
  } else {
    paste(ornek_turler, collapse = ", ")
  }

  div(
    class = "oo-belge-yukleme",
    div(
      class = "oo-belge-drop",
      `data-oo-belge-drop` = "1",
      role = "button",
      tabindex = "0",
      `aria-label` = "Ortak belge yükle: dosyaları buraya sürükleyin veya belge seçin",
      icon("cloud-arrow-up", class = "oo-belge-drop-ikon"),
      tags$span(class = "oo-belge-drop-baslik", "Belgeleri buraya sürükleyin"),
      tags$span(class = "oo-belge-drop-ayrac", "veya"),
      div(
        class = "oo-belge-drop-secim",
        fileInput(
          yukle_input_id,
          label = NULL,
          multiple = TRUE,
          accept = paste0(".", izinli_uzantilar),
          buttonLabel = tagList(icon("folder-open"), span("Belge Seç")),
          placeholder = ""
        )
      )
    ),
    tags$small(
      class = "oo-belge-yukleme-ipucu",
      sprintf(
        "En fazla %d MB · %s ve tekil oturum yüklemeleriyle aynı diğer türler",
        as.integer(limit_mb),
        tur_ipucu
      )
    )
  )
}

# ------------------------------------------------------------------------------
# SUNUCU BAĞLAYICILARI
# ------------------------------------------------------------------------------

# Ortak Belgeler paneli bağlayıcısı: yükleme alanı + belge listesi render'ı ve
# yükleme/seçim/kaldırma/kopyalama gözlemcileri.
ortakOturumBelgePaneliBind <- function(input, output, session, ctx) {
  ns <- session$ns

  # Aktif oda BilgeYolaç türünde mi? (belge bağlam kontrolleri oda türüne
  # göre kapılanır; BY odalarında belgeler yapay zekâ bağlamına GİRMEZ.)
  by_odasi_mi <- function() {
    bilgi <- ctx$oturum_bilgisi()
    !is.null(bilgi) && identical(as.character(bilgi$KaynakTuru[1] %||% ""), "BilgeYolaç")
  }

  # Yükleme alanı yalnızca ODA/ROL değişince yeniden çizilir (4 sn yoklamada
  # değil); böylece süren bir dosya seçimi/yükleme akışı bozulmaz. BilgeYolaç
  # odasında yükleme/bağlam kontrolü yerine dürüst bilgilendirme notu çizilir:
  # belge paylaşımı orada çalışma alanı üzerinden yürür.
  output$belge_yukleme_alani <- renderUI({
    ctx$aktif_oturum()
    if (by_odasi_mi()) {
      return(div(
        class = "oo-belge-by-notu",
        icon("circle-info"),
        span(paste(
          "Bilge Yolaç odalarında dosyalar paylaşılan çalışma alanı üzerinden",
          "yönetilir; buradaki belgeler yapay zekâ bağlamına eklenmez.",
          "Üretilen dosyalar aşağıda listelenir."
        ))
      ))
    }
    rol <- ctx$oda_rol()
    if (!ortak_yetki_var_mi(rol, "yapay_zeka_sor")) {
      return(NULL)
    }

    oo_belge_yukleme_alani_html(
      yukle_input_id = ns("belge_dosya_yukle"),
      izinli_uzantilar = ortak_belge_izinli_uzantilar(),
      limit_mb = getOption("mergen.upload_max_mb", 25L)
    )
  })

  output$belgeler_alani <- renderUI({
    by_odasi <- by_odasi_mi()
    df <- ctx$belgeler()

    if (!is.data.frame(df) || nrow(df) == 0L) {
      # Boş durum panel yüksekliğini doldurur; metin hiçbir zaman kırpılmaz
      # (sabit yükseklik/ellipsis yok, kaydırma çubuğu üretmez).
      return(div(
        class = "oo-bos-durum oo-bos-belge",
        icon("folder-open", class = "oo-bos-belge-ikon"),
        p(class = "oo-bos-belge-baslik", "Henüz ortak belge yok"),
        p(
          class = "oo-bos-belge-metin",
          if (by_odasi) {
            "Bilge Yolaç'ın çalışma alanında ürettiği dosyalar burada listelenir."
          } else {
            "Yüklediğiniz belgeler tüm katılımcılarla paylaşılır; seçilenler yapay zekâ bağlamına eklenir."
          }
        )
      ))
    }

    rol <- ctx$oda_rol()
    yetkili <- ortak_yetki_var_mi(rol, "yapay_zeka_sor")

    # BilgeYolaç odası: üretilen ortak belgeler LİSTELENİR (indirme/kopyalama
    # ve yetkili kaldırma korunur) ama bağlam seçimi sunulmaz — belgelerin
    # yürütme bağlamına girdiği imasından kaçınılır.
    tagList(lapply(seq_len(nrow(df)), function(i) {
      oo_dosya_karti_html(
        df[i, , drop = FALSE],
        kopyala_input_id = ns("belge_kopyala"),
        secim_input_id = if (by_odasi) NULL else ns("belge_secim"),
        sil_input_id = ns("belge_sil"),
        yetkili = yetkili,
        baglam_secimi = !by_odasi
      )
    }))
  })

  # Yükleme: her dosya tekil oturumla aynı sunucu doğrulamasından geçer.
  # Oda kimliği gözlemci ANINDA okunur; oda değişiminde fileInput yeniden
  # çizildiği için bayat yükleme başka odaya yazamaz.
  observeEvent(input$belge_dosya_yukle, {
    dosyalar <- input$belge_dosya_yukle
    req(is.data.frame(dosyalar), nrow(dosyalar) > 0L)

    # Sunucu tarafı oda-türü kapısı: BY odasında belge paneli yüklemesi yoktur
    # (UI gizlemesi güvenlik değildir; istemci ne gönderirse göndersin reddedilir).
    if (by_odasi_mi()) {
      ctx$bildir(
        "Bilge Yolaç odalarında dosyalar çalışma alanı üzerinden paylaşılır.",
        tur = "warning"
      )
      return(invisible(NULL))
    }

    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)
    uid <- ctx$current_user_id()

    basarili_sayisi <- 0L
    for (i in seq_len(nrow(dosyalar))) {
      sonuc <- ortak_db_belge_yukle(
        oturum_id = oturum_id,
        kullanici_id = uid,
        kaynak_yol = as.character(dosyalar$datapath[i]),
        dosya_adi = as.character(dosyalar$name[i])
      )

      if (isTRUE(sonuc$basarili)) {
        basarili_sayisi <- basarili_sayisi + 1L
      } else {
        ctx$bildir(
          sprintf("%s yüklenemedi: %s", as.character(dosyalar$name[i]), sonuc$mesaj),
          tur = "error"
        )
      }
    }

    if (basarili_sayisi > 0L) {
      ctx$bildir(sprintf(
        "%d ortak belge yüklendi; seçili belgeler yapay zekâ bağlamına dahil edilecek.",
        basarili_sayisi
      ))
    }
    ctx$yenile()
  })

  # Bağlam seçimi: {id, secili, nonce} yükü (delege JS köprüsü).
  observeEvent(input$belge_secim, {
    yuk <- input$belge_secim
    dosya_id <- suppressWarnings(as.integer(yuk$id))
    req(!is.na(dosya_id))

    # BY odasında belge bağlam seçimi sunulmaz; bayat/istemci kaynaklı seçim
    # istekleri sessizce reddedilir (soru yolu zaten boş anlık görüntü yazar).
    if (by_odasi_mi()) {
      return(invisible(NULL))
    }

    tamam <- ortak_db_belge_secim_guncelle(
      ortak_dosya_id = dosya_id,
      kullanici_id = ctx$current_user_id(),
      secili = isTRUE(yuk$secili)
    )

    if (!isTRUE(tamam)) {
      ctx$bildir("Belge seçimi güncellenemedi: yetkiniz yok veya belge kaldırılmış.", tur = "warning")
    }
    ctx$yenile()
  })

  # Kaldırma: soft delete + güvenli fiziksel silme (helpers katmanında).
  observeEvent(input$belge_sil, {
    dosya_id <- suppressWarnings(as.integer(input$belge_sil$id))
    req(!is.na(dosya_id))

    sonuc <- ortak_db_belge_sil(dosya_id, ctx$current_user_id())
    ctx$bildir(sonuc$mesaj, tur = if (isTRUE(sonuc$basarili)) "message" else "error")
    ctx$yenile()
  })

  # "Kendi Dosyalarıma Kaydet" (oda modülünden taşındı; davranış aynı).
  observeEvent(input$belge_kopyala, {
    dosya_id <- suppressWarnings(as.integer(input$belge_kopyala$id))
    req(!is.na(dosya_id))

    sonuc <- ortak_dosya_kisisel_kopyala(dosya_id, ctx$current_user_id())

    if (isTRUE(sonuc$basarili)) {
      ortak_db_olay_ekle(ctx$aktif_oturum(), "BelgeKopyalandı", ctx$current_user_id())
      ctx$bildir(sonuc$mesaj)
    } else {
      ctx$bildir(sonuc$mesaj, tur = "error")
    }
    ctx$yenile()
  })

  invisible(TRUE)
}

# "Sohbeti Temizle" bağlayıcısı: açık onay modalı olmadan ÇALIŞMAZ. Bağlam
# sıfırlamadan (transkripti koruyan işaret) farklı, geri alınamaz bir eylemdir;
# yalnızca katilimci_yonet yetkili rollere (Sahip / Oturum Yöneticisi) çizilir
# ve sunucu tarafında da aynı yetkiyle doğrulanır.
ortakOturumSohbetTemizleBind <- function(input, output, session, ctx) {
  ns <- session$ns

  output$oda_sohbet_temizle_alani <- renderUI({
    ctx$aktif_oturum()
    rol <- ctx$oda_rol()
    if (!ortak_yetki_var_mi(rol, "katilimci_yonet")) {
      return(NULL)
    }

    actionButton(
      ns("oda_sohbet_temizle"),
      label = icon("trash-can"),
      class = "oo-oda-btn oo-oda-btn-tehlike oo-btn-sohbet-temizle oo-btn-ikon",
      title = "Sohbeti kalıcı olarak temizle: TÜM mesajlar silinir (bağlam temizlemekten farklıdır)",
      `aria-label` = "Ortak sohbeti kalıcı olarak temizle"
    )
  })

  observeEvent(input$oda_sohbet_temizle, {
    req(ctx$aktif_oturum())

    showModal(modalDialog(
      title = tagList(icon("triangle-exclamation"), span("Sohbeti Kalıcı Olarak Temizle")),
      size = "m",
      easyClose = TRUE,
      div(
        class = "oo-sohbet-temizle-modal",
        p(
          "Bu işlem odadaki ", tags$strong("TÜM mesajları kalıcı olarak siler"),
          " ve ", tags$strong("geri alınamaz"), "."
        ),
        p(
          class = "oo-sohbet-temizle-notu",
          "Not: Bu, yeni bağlam başlatmaktan (sihirli değnek) farklıdır; bağlam temizleme",
          " transkripti korurken bu eylem tüm katılımcıların sohbet geçmişini siler.",
          " Ortak belgeler silinmez."
        )
      ),
      footer = tagList(
        modalButton("Vazgeç"),
        actionButton(
          ns("oda_sohbet_temizle_onay"),
          tagList(icon("trash-can"), span("Kalıcı Olarak Temizle")),
          class = "oo-oda-btn oo-oda-btn-tehlike"
        )
      )
    ))
  })

  observeEvent(input$oda_sohbet_temizle_onay, {
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    sonuc <- ortak_db_sohbet_temizle(oturum_id, ctx$current_user_id())

    removeModal()
    ctx$bildir(sonuc$mesaj, tur = if (isTRUE(sonuc$basarili)) "message" else "error")
    ctx$yenile()
  })

  invisible(TRUE)
}
