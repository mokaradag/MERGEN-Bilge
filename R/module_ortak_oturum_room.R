# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_room.R
# Açıklama: Ortak Oturum odası sunucu modülü: mesaj akışı yoklama, oda içi
#           yazışma ("Odaya Yaz"), yapay zekâ sorusu ("Yapay Zekâya Sor"),
#           katılımcı çağırma paneli, katılımcı yönetimi, ortak belge
#           kopyalama ve odadan ayrılma/arşivleme eylemleri.
#
# Sözleşmeler:
#   * OdaMesajı ASLA LLM tetiklemez; tek LLM yolu "Yapay Zekâya Sor" eylemidir.
#   * Oda başına TEK aktif yanıt üretimi: kilit DB'dedir
#     (ortak_db_uretim_kilidi_al); kilit doluysa kullanıcıya açık
#     "Yanıt üretimi sürüyor" mesajı gösterilir.
#   * Tüm yazma eylemleri sunucu tarafında rol/erişim doğrulamasından geçer
#     (DB katmanı fail-closed); UI gizlemesi tek başına güvenlik değildir.
#   * Yapay zekâ çağrısı worker'da koşar (tracked_future_promise); DB
#     kalıcılığı ana süreçteki promise callback'inde yapılır.
# ==============================================================================

ortakOturumRoomServer <- function(id,
                                  current_user_id,
                                  aktif_oturum,
                                  on_close = function() NULL,
                                  parent_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    yenile_sayaci <- reactiveVal(0L)
    yonetilen_kullanici <- reactiveVal(NULL)

    oo_bildir <- function(mesaj, tur = "message") {
      shiny::showNotification(mesaj, type = tur, duration = 6)
    }

    oo_yenile <- function() {
      yenile_sayaci(isolate(yenile_sayaci()) + 1L)
    }

    # Oda açıkken 4 sn'de bir DB'den tazele (tüm katılımcılar aynı akışı görür).
    observe({
      req(aktif_oturum())
      invalidateLater(4000, session)
      oo_yenile()
    })

    oturum_bilgisi <- reactive({
      yenile_sayaci()
      oturum_id <- aktif_oturum()
      if (is.null(oturum_id)) {
        return(NULL)
      }
      ortak_db_oturum_getir(oturum_id)
    })

    benim_katilimim <- reactive({
      yenile_sayaci()
      oturum_id <- aktif_oturum()
      if (is.null(oturum_id)) {
        return(NULL)
      }
      ortak_db_katilimci_getir(oturum_id, current_user_id())
    })

    mesajlar <- reactive({
      yenile_sayaci()
      oturum_id <- aktif_oturum()
      if (is.null(oturum_id)) {
        return(data.frame())
      }
      ortak_db_mesajlari_getir(oturum_id, current_user_id())
    })

    katilimcilar <- reactive({
      yenile_sayaci()
      oturum_id <- aktif_oturum()
      katilim <- benim_katilimim()
      if (is.null(oturum_id) || is.null(katilim) ||
          !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1])) {
        return(data.frame())
      }
      ortak_db_katilimci_listesi(oturum_id)
    })

    belgeler <- reactive({
      yenile_sayaci()
      oturum_id <- aktif_oturum()
      if (is.null(oturum_id)) {
        return(data.frame())
      }
      ortak_db_dosyalar(oturum_id, current_user_id())
    })

    canli_durumlar <- reactive({
      yenile_sayaci()
      ortak_db_canli_durumlar()
    })

    kullanici_canli_durumu <- function(kullanici_id) {
      durumlar <- canli_durumlar()
      if (!is.data.frame(durumlar) || nrow(durumlar) == 0L) {
        return("ÇevrimDışı")
      }
      satir <- durumlar[durumlar$KullaniciID == kullanici_id, , drop = FALSE]
      if (nrow(satir) == 0L) {
        return("ÇevrimDışı")
      }
      as.character(satir$CanliDurum[1])
    }

    # --- Oda başlığı --------------------------------------------------------

    output$oda_baslik_alani <- renderUI({
      bilgi <- oturum_bilgisi()
      req(bilgi)

      kaynak_etiketi <- if (identical(bilgi$KaynakTuru[1], "BilgeYolaç")) {
        "Bilge Yolaç"
      } else {
        "Söyleşi"
      }

      tagList(
        h3(class = "oo-oda-baslik-metin", HTML(htmltools::htmlEscape(
          as.character(bilgi$Baslik[1] %||% "Ortak Oturum")
        ))),
        tags$span(class = "oo-rozet oo-rozet-kaynak", kaynak_etiketi),
        tags$span(class = "oo-rozet oo-rozet-durum", HTML(htmltools::htmlEscape(
          as.character(bilgi$OturumDurumu[1])
        )))
      )
    })

    # --- Mesaj akışı / katılımcılar / belgeler -------------------------------

    output$mesajlar_alani <- renderUI({
      df <- mesajlar()
      katilim <- benim_katilimim()

      if (is.null(katilim) || !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1])) {
        return(div(
          class = "oo-bos-durum",
          icon("lock"),
          p("Bu odanın içeriğini görmek için daveti kabul etmeniz gerekir.")
        ))
      }

      if (!is.data.frame(df) || nrow(df) == 0L) {
        return(div(
          class = "oo-bos-durum",
          icon("comments"),
          p("Henüz mesaj yok. İlk mesajı odaya yazın ya da yapay zekâya sorun.")
        ))
      }

      benim_id <- current_user_id()
      tagList(lapply(seq_len(nrow(df)), function(i) {
        oo_mesaj_html(df[i, , drop = FALSE], aktif_kullanici_id = benim_id)
      }))
    })

    output$katilimcilar_alani <- renderUI({
      df <- katilimcilar()

      if (!is.data.frame(df) || nrow(df) == 0L) {
        return(div(class = "oo-bos-durum", p("Katılımcı bilgisi yok.")))
      }

      katilim <- benim_katilimim()
      yonetebilir <- !is.null(katilim) &&
        ortak_yetki_var_mi(katilim$Rol[1], "katilimci_yonet")
      benim_id <- current_user_id()

      tagList(lapply(seq_len(nrow(df)), function(i) {
        satir <- df[i, , drop = FALSE]
        durum <- kullanici_canli_durumu(as.integer(satir$KullaniciID[1]))

        yonet_dugmesi <- NULL
        if (yonetebilir &&
            !identical(as.integer(satir$KullaniciID[1]), as.integer(benim_id)) &&
            ortak_katilimci_yonetilebilir_mi(katilim$Rol[1], satir$Rol[1])) {
          yonet_dugmesi <- tags$button(
            type = "button",
            class = "btn-modern oo-btn-katilimci-yonet",
            `data-oo-kullanici-id` = as.character(satir$KullaniciID[1]),
            `data-oo-hedef-input` = ns("katilimci_yonet"),
            `aria-label` = "Katılımcıyı yönet",
            icon("user-gear")
          )
        }

        div(
          class = "oo-katilimci-satir",
          oo_katilimci_html(satir, canli_durum = durum),
          yonet_dugmesi
        )
      }))
    })

    output$belgeler_alani <- renderUI({
      df <- belgeler()

      if (!is.data.frame(df) || nrow(df) == 0L) {
        return(div(
          class = "oo-bos-durum oo-bos-belge",
          p("Bu odada henüz ortak belge üretilmedi.")
        ))
      }

      tagList(lapply(seq_len(nrow(df)), function(i) {
        oo_dosya_karti_html(df[i, , drop = FALSE], kopyala_input_id = ns("belge_kopyala"))
      }))
    })

    output$uretim_durumu_alani <- renderUI({
      yenile_sayaci()
      oturum_id <- aktif_oturum()
      if (is.null(oturum_id) || !ortak_db_aktif_uretim_var_mi(oturum_id)) {
        return(NULL)
      }

      div(
        class = "oo-uretim-durumu",
        role = "status",
        `aria-live` = "polite",
        icon("spinner", class = "fa-spin"),
        span("Yanıt üretimi sürüyor; tamamlanınca tüm katılımcılar görecek.")
      )
    })

    output$composer_uyari_alani <- renderUI({
      katilim <- benim_katilimim()
      if (is.null(katilim)) {
        return(NULL)
      }

      if (!ortak_yetki_var_mi(katilim$Rol[1], "oda_yaz")) {
        return(div(
          class = "oo-composer-uyari",
          icon("eye"),
          span("İzleyici rolündesiniz: odayı okuyabilirsiniz ancak mesaj yazamaz ve yapay zekâya soramazsınız.")
        ))
      }
      NULL
    })

    # --- Mesaj gönderme eylemleri --------------------------------------------

    mesaj_metnini_al <- function() {
      metin <- trimws(as.character(input$oda_mesaj_metni %||% "")[1])
      if (!nzchar(metin)) {
        oo_bildir("Önce bir mesaj yazın.", tur = "warning")
        return(NULL)
      }
      metin
    }

    observeEvent(input$odaya_yaz, {
      oturum_id <- aktif_oturum()
      req(oturum_id)

      metin <- mesaj_metnini_al()
      if (is.null(metin)) {
        return(invisible(NULL))
      }

      mesaj_id <- ortak_db_mesaj_ekle(
        oturum_id = oturum_id,
        gonderen_kullanici_id = current_user_id(),
        mesaj_turu = "OdaMesajı",
        mesaj_metni = metin
      )

      if (is.null(mesaj_id)) {
        oo_bildir("Mesaj gönderilemedi: bu odada yazma yetkiniz yok.", tur = "error")
        return(invisible(NULL))
      }

      ortak_db_olay_ekle(oturum_id, "MesajEklendi", current_user_id())
      updateTextAreaInput(session, "oda_mesaj_metni", value = "")
      oo_yenile()
    })

    observeEvent(input$yapay_zekaya_sor, {
      oturum_id <- aktif_oturum()
      req(oturum_id)

      metin <- mesaj_metnini_al()
      if (is.null(metin)) {
        return(invisible(NULL))
      }

      if (ortak_db_aktif_uretim_var_mi(oturum_id)) {
        oo_bildir("Yanıt üretimi sürüyor; lütfen mevcut yanıt tamamlanınca tekrar deneyin.", tur = "warning")
        return(invisible(NULL))
      }

      soru_id <- ortak_db_mesaj_ekle(
        oturum_id = oturum_id,
        gonderen_kullanici_id = current_user_id(),
        mesaj_turu = "YapayZekaSorusu",
        mesaj_metni = metin,
        llm_gonderildi = TRUE
      )

      if (is.null(soru_id)) {
        oo_bildir("Soru gönderilemedi: bu odada yapay zekâya sorma yetkiniz yok.", tur = "error")
        return(invisible(NULL))
      }

      updateTextAreaInput(session, "oda_mesaj_metni", value = "")
      oo_yenile()

      yz_yaniti_uret(oturum_id, soru_id, current_user_id())
    })

    # Yapay zekâ yanıtı: oda başına TEK üretim; kilit DB'de tutulur. LLM çağrısı
    # worker'da koşar; kalıcılık ve kilit bırakma ana süreçte yapılır.
    yz_yaniti_uret <- function(oturum_id, soru_id, soran_kullanici_id) {
      istek_id <- paste0(
        "oo_", oturum_id, "_", soru_id, "_",
        format(Sys.time(), "%H%M%S"), "_", sample.int(99999L, 1L)
      )

      if (!ortak_db_uretim_kilidi_al(oturum_id, soran_kullanici_id, istek_id, mesaj_id = soru_id)) {
        oo_bildir("Yanıt üretimi sürüyor; sorunuz odada kayıtlı kaldı.", tur = "warning")
        return(invisible(NULL))
      }

      ortak_db_olay_ekle(oturum_id, "YanıtBaşladı", soran_kullanici_id)

      tamamla <- function(yanit_metni, hata_metni = NULL) {
        if (!is.null(hata_metni)) {
          ortak_db_mesaj_ekle(
            oturum_id = oturum_id,
            gonderen_kullanici_id = NULL,
            mesaj_turu = "SistemMesajı",
            mesaj_metni = hata_metni
          )
          ortak_db_uretim_kilidi_birak(oturum_id, istek_id, sonuc_durumu = "Hata")
        } else {
          ortak_db_mesaj_ekle(
            oturum_id = oturum_id,
            gonderen_kullanici_id = NULL,
            mesaj_turu = "YapayZekaYanıtı",
            mesaj_metni = yanit_metni,
            bagli_mesaj_id = soru_id
          )
          ortak_db_uretim_kilidi_birak(oturum_id, istek_id, sonuc_durumu = "Tamamlandı")
          ortak_db_olay_ekle(oturum_id, "YanıtTamamlandı", soran_kullanici_id)
        }
        oo_yenile()
        invisible(NULL)
      }

      if (!exists("call_local_llm", mode = "function", inherits = TRUE)) {
        return(tamamla(NULL, hata_metni = "Yapay zekâ hizmeti bu ortamda yapılandırılmamış."))
      }

      # LLM bağlamı: yalnızca YZ soru/yanıt geçmişi (oda mesajları girmez).
      gecmis <- ortak_yz_sohbet_gecmisi(ortak_db_mesajlari_getir(oturum_id, soran_kullanici_id))

      model_id <- Sys.getenv("ORTAK_OTURUM_MODEL", unset = "")
      if (!nzchar(model_id) && exists("api_config", inherits = TRUE)) {
        model_id <- as.character(api_config$local_models[1] %||% "")
      }

      anahtar <- ""
      if (exists("mb_api_key_get_feature_key_value", mode = "function", inherits = TRUE)) {
        anahtar <- mb_api_key_get_feature_key_value(session = parent_session %||% session)
      }

      ayarlar <- list(
        model_selection = model_id,
        temperature = 0.4,
        enable_mcp_tools = FALSE,
        api_key_override = anahtar
      )

      if (exists("tracked_future_promise", mode = "function", inherits = TRUE)) {
        prom <- tracked_future_promise(
          task_fn = function() {
            call_local_llm(gecmis, ayarlar)
          },
          task_type = "ortak_oturum_llm",
          session_token = session$token
        )

        promises::then(
          prom,
          onFulfilled = function(yanit) {
            icerik <- as.character(yanit$content %||% "")[1]
            if (nzchar(icerik)) {
              tamamla(icerik)
            } else {
              tamamla(NULL, hata_metni = "Yapay zekâ boş yanıt döndürdü; lütfen tekrar deneyin.")
            }
          },
          onRejected = function(e) {
            tamamla(NULL, hata_metni = "Yapay zekâ yanıtı üretilemedi; lütfen tekrar deneyin.")
          }
        )
      } else {
        # Yedek yol (worker altyapısı olmayan izole bağlamlar): eşzamanlı çağrı.
        yanit <- tryCatch(call_local_llm(gecmis, ayarlar), error = function(e) NULL)
        icerik <- as.character(yanit$content %||% "")[1]
        if (nzchar(icerik)) {
          tamamla(icerik)
        } else {
          tamamla(NULL, hata_metni = "Yapay zekâ yanıtı üretilemedi; lütfen tekrar deneyin.")
        }
      }

      invisible(NULL)
    }

    # --- Katılımcı çağırma paneli (ayrı bağlayıcı dosyada) ---------------------

    ortakOturumInvitesBind(input, output, session, ctx = list(
      aktif_oturum = aktif_oturum,
      current_user_id = current_user_id,
      oturum_bilgisi = oturum_bilgisi,
      benim_katilimim = benim_katilimim,
      katilimcilar = katilimcilar,
      kullanici_canli_durumu = kullanici_canli_durumu,
      yenile_sayaci = yenile_sayaci,
      bildir = oo_bildir,
      yenile = oo_yenile
    ))

    # --- Oda yönetim eylemleri: tutanak indirme + herkes için arşivleme ----------

    # Tutanak dışa aktarma: yalnızca içerik erişimli katılımcıya gerçek içerik.
    output$oda_disa_aktar <- downloadHandler(
      filename = function() {
        sprintf("ortak_oturum_%s_tutanak.txt", as.character(aktif_oturum() %||% "0"))
      },
      content = function(file) {
        katilim <- isolate(benim_katilimim())
        oturum_id <- isolate(aktif_oturum())

        if (is.null(katilim) || is.null(oturum_id) ||
            !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1])) {
          # Yetkisiz indirme girişimi içerik sızdırmaz.
          ortak_tutanak_dosyaya_yaz("Bu tutanağı indirme yetkiniz yok.", file)
          return(invisible(NULL))
        }

        metin <- ortak_tutanak_metni(
          isolate(oturum_bilgisi()),
          ortak_db_mesajlari_getir(oturum_id, current_user_id()),
          ortak_db_dosyalar(oturum_id, current_user_id())
        )
        ortak_tutanak_dosyaya_yaz(metin, file)
      },
      contentType = "text/plain; charset=UTF-8"
    )

    # Oda düzeyi arşiv yalnızca oturum_kapat yetkisine (Sahip) görünür.
    output$oda_yonetim_aksiyonlari <- renderUI({
      katilim <- benim_katilimim()
      if (is.null(katilim) || !ortak_yetki_var_mi(katilim$Rol[1], "oturum_kapat")) {
        return(NULL)
      }

      actionButton(
        ns("oda_arsivle_herkes"),
        label = tagList(icon("box-archive"), span("Herkes İçin Arşivle")),
        class = "btn-modern oo-btn-arsivle-herkes",
        `aria-label` = "Ortak oturumu tüm katılımcılar için arşivle"
      )
    })

    observeEvent(input$oda_arsivle_herkes, {
      oturum_id <- aktif_oturum()
      req(oturum_id)

      if (isTRUE(ortak_db_oturum_durum_guncelle(oturum_id, current_user_id(), "Arşivlendi"))) {
        ortak_db_olay_ekle(oturum_id, "OturumArşivlendi", current_user_id())
        oo_bildir("Ortak oturum tüm katılımcılar için arşivlendi.")
        on_close()
      } else {
        oo_bildir("Oturum arşivlenemedi: yalnızca Sahip herkes için arşivleyebilir.", tur = "error")
      }
    })

    # --- Katılımcı yönetimi -----------------------------------------------------

    observeEvent(input$katilimci_yonet, {
      hedef_id <- suppressWarnings(as.integer(input$katilimci_yonet$id))
      req(!is.na(hedef_id))

      yonetilen_kullanici(hedef_id)

      katilim <- benim_katilimim()
      sahibim <- !is.null(katilim) &&
        identical(katilim$Rol[1], ortak_oturum_rolleri()[1])

      showModal(modalDialog(
        title = "Katılımcıyı Yönet",
        selectInput(
          ns("yeni_rol"),
          label = "Rol",
          choices = c("OturumYöneticisi", "Katılımcı", "İzleyici")
        ),
        footer = tagList(
          actionButton(ns("rol_kaydet"), "Rol Değiştir", class = "btn-primary"),
          if (sahibim) {
            actionButton(ns("sahiplik_devret"), "Sahipliği Devret", class = "btn-warning")
          } else {
            NULL
          },
          actionButton(ns("katilimci_cikar"), "Çıkar", class = "btn-danger"),
          modalButton("Vazgeç")
        )
      ))
    })

    observeEvent(input$sahiplik_devret, {
      oturum_id <- aktif_oturum()
      hedef_id <- yonetilen_kullanici()
      req(oturum_id, hedef_id)

      if (isTRUE(ortak_db_sahiplik_devret(oturum_id, current_user_id(), hedef_id))) {
        ortak_db_olay_ekle(oturum_id, "SahiplikDevredildi", current_user_id())
        oo_bildir("Sahiplik devredildi; yeni rolünüz: OturumYöneticisi.")
      } else {
        oo_bildir("Sahiplik devredilemedi: hedef katılımcı içerik erişimli olmalıdır.", tur = "error")
      }

      removeModal()
      oo_yenile()
    })

    observeEvent(input$rol_kaydet, {
      oturum_id <- aktif_oturum()
      hedef_id <- yonetilen_kullanici()
      req(oturum_id, hedef_id)

      basarili <- ortak_db_katilimci_rol_guncelle(
        oturum_id = oturum_id,
        yoneten_kullanici_id = current_user_id(),
        hedef_kullanici_id = hedef_id,
        yeni_rol = as.character(input$yeni_rol %||% "Katılımcı")[1]
      )

      if (isTRUE(basarili)) {
        ortak_db_olay_ekle(oturum_id, "RolDeğişti", current_user_id())
        oo_bildir("Katılımcı rolü güncellendi.")
      } else {
        oo_bildir("Rol güncellenemedi: yetkiniz yok veya katılımcı Sahip.", tur = "error")
      }

      removeModal()
      oo_yenile()
    })

    observeEvent(input$katilimci_cikar, {
      oturum_id <- aktif_oturum()
      hedef_id <- yonetilen_kullanici()
      req(oturum_id, hedef_id)

      katilim <- benim_katilimim()
      hedef_satir <- ortak_db_katilimci_getir(oturum_id, hedef_id)

      if (is.null(katilim) || is.null(hedef_satir) ||
          !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1]) ||
          !ortak_katilimci_yonetilebilir_mi(katilim$Rol[1], hedef_satir$Rol[1])) {
        oo_bildir("Katılımcı çıkarılamadı: yetkiniz yok.", tur = "error")
      } else {
        ortak_db_katilim_durumu_guncelle(oturum_id, hedef_id, "Çıkarıldı")
        ortak_db_olay_ekle(oturum_id, "KullanıcıAyrıldı", current_user_id())
        oo_bildir("Katılımcı odadan çıkarıldı.")
      }

      removeModal()
      oo_yenile()
    })

    # --- Belge kopyalama ve oda kapatma ------------------------------------------

    observeEvent(input$belge_kopyala, {
      dosya_id <- suppressWarnings(as.integer(input$belge_kopyala$id))
      req(!is.na(dosya_id))

      sonuc <- ortak_dosya_kisisel_kopyala(dosya_id, current_user_id())

      if (isTRUE(sonuc$basarili)) {
        ortak_db_olay_ekle(aktif_oturum(), "BelgeKopyalandı", current_user_id())
        oo_bildir(sonuc$mesaj)
      } else {
        oo_bildir(sonuc$mesaj, tur = "error")
      }
      oo_yenile()
    })

    observeEvent(input$oda_kapat, {
      on_close()
    })

    observeEvent(input$oda_ayril, {
      oturum_id <- aktif_oturum()
      req(oturum_id)

      # Sahiplik kuralı: odada her zaman en az bir Sahip kalmalıdır.
      katilim <- benim_katilimim()
      if (!is.null(katilim) && identical(katilim$Rol[1], ortak_oturum_rolleri()[1])) {
        oo_bildir(
          paste(
            "Sahip odadan ayrılamaz. Önce “Katılımcıyı Yönet > Sahipliği Devret”",
            "ile sahipliği devredin ya da odayı herkes için arşivleyin."
          ),
          tur = "warning"
        )
        return(invisible(NULL))
      }

      ortak_db_katilim_durumu_guncelle(oturum_id, current_user_id(), "Ayrıldı")
      ortak_db_olay_ekle(oturum_id, "KullanıcıAyrıldı", current_user_id())
      oo_bildir("Ortak oturumdan ayrıldınız.")
      on_close()
    })

    list(yenile = oo_yenile)
  })
}
