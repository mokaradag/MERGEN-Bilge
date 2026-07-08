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
    secili_model <- reactiveVal("")
    secili_persona <- reactiveVal("")
    # Kompakt rol sinyali: model/persona açılır menüleri yalnızca ROL değişince
    # yeniden çizilsin diye (4 sn yoklamada değil); menü seçimi/odaklanması bozulmaz.
    oda_rol <- reactiveVal("")

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

    # Oda değiştiğinde model ve persona seçimini oturum kaydından çöz (varsa).
    observeEvent(aktif_oturum(), {
      oturum_id <- aktif_oturum()
      secili_model("")
      secili_persona("")
      if (is.null(oturum_id)) {
        return(invisible(NULL))
      }
      # Persona odanın kaydından okunur; yoksa oturum kimliğinden deterministik
      # varsayılana düşer (persona metadata'sı olmayan eski oturumlar için).
      bilgi <- ortak_db_oturum_getir(oturum_id)
      persona_secim <- if (!is.null(bilgi)) as.character(bilgi$SecilenPersona[1] %||% "") else ""
      secili_persona(ortak_oturum_persona_kimligi(persona_secim, oturum_id))
    }, ignoreNULL = FALSE)

    # Rol sinyalini yalnızca gerçekten değiştiğinde güncelle (menü stabilitesi).
    observe({
      katilim <- benim_katilimim()
      yeni <- if (is.null(katilim)) "" else as.character(katilim$Rol[1] %||% "")
      if (!identical(isolate(oda_rol()), yeni)) {
        oda_rol(yeni)
      }
    })

    # Odanın etkin personası (yoklamayla tazelenir): mesaj avatarları/adları tüm
    # katılımcılarda güncel kalsın diye oturum kaydından çözülür.
    etkin_persona <- reactive({
      yenile_sayaci()
      oturum_id <- aktif_oturum()
      if (is.null(oturum_id)) {
        return(ortak_oturum_persona_gorunumu(NULL))
      }
      bilgi <- oturum_bilgisi()
      persona_secim <- if (!is.null(bilgi)) as.character(bilgi$SecilenPersona[1] %||% "") else ""
      ortak_oturum_persona_gorunumu(persona_secim, oturum_id)
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

    # Kullanıcı şu an BU odaya mı bakıyor? (yeşil "bu odada" göstergesi için)
    kullanici_bu_odada_mi <- function(kullanici_id) {
      durumlar <- canli_durumlar()
      oturum_id <- aktif_oturum()
      if (is.null(oturum_id) || !is.data.frame(durumlar) || nrow(durumlar) == 0L ||
          !"SonGorulenOrtakOturumID" %in% names(durumlar)) {
        return(FALSE)
      }
      satir <- durumlar[durumlar$KullaniciID == kullanici_id, , drop = FALSE]
      if (nrow(satir) == 0L) {
        return(FALSE)
      }
      identical(
        suppressWarnings(as.integer(satir$SonGorulenOrtakOturumID[1])),
        suppressWarnings(as.integer(oturum_id))
      ) && identical(as.character(satir$CanliDurum[1]), "Çevrimİçi")
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
      persona <- etkin_persona()
      tagList(lapply(seq_len(nrow(df)), function(i) {
        oo_mesaj_html(df[i, , drop = FALSE], aktif_kullanici_id = benim_id, persona = persona)
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
          oo_katilimci_html(
            satir,
            canli_durum = durum,
            ayni_odada = kullanici_bu_odada_mi(as.integer(satir$KullaniciID[1]))
          ),
          yonet_dugmesi
        )
      }))
    })

    # Odanın etkin AI modelini seçen kompakt açılır menü (Yapılandırma'ya
    # gitmeden değiştirilir; ana uygulamayla aynı model listesini kullanır).
    # Yalnızca ODA veya ROL değişince yeniden çizilir; 4 sn yoklamada değil
    # (seçim/odak bozulmaz).
    output$oda_model_secim_alani <- renderUI({
      aktif_oturum()
      rol <- oda_rol()
      if (!ortak_yetki_var_mi(rol, "yapay_zeka_sor")) {
        return(NULL)
      }

      modeller <- if (exists("api_config", inherits = TRUE)) {
        as.character(api_config$local_models %||% character(0))
      } else {
        character(0)
      }
      modeller <- modeller[nzchar(modeller)]

      if (length(modeller) == 0L) {
        return(tags$span(class = "oo-composer-model-yok", "Varsayılan model"))
      }

      secili <- as.character(isolate(secili_model()) %||% "")[1]
      if (!nzchar(secili)) {
        secili <- modeller[1]
      }

      div(
        class = "oo-composer-secim oo-composer-secim-model",
        tags$span(class = "oo-composer-secim-ikon", icon("microchip"), `aria-hidden` = "true"),
        selectInput(
          ns("oda_model_secimi"),
          label = NULL,
          choices = modeller,
          selected = secili,
          width = "180px"
        )
      )
    })

    observeEvent(input$oda_model_secimi, {
      deger <- as.character(input$oda_model_secimi %||% "")[1]
      if (nzchar(deger)) {
        secili_model(deger)
      }
    }, ignoreInit = TRUE)

    # Persona açılır menüsü: yalnızca katilimci_yonet yetkisi olan rol (Sahip /
    # Oturum Yöneticisi) personayı değiştirebilir. Rol değişince yeniden çizilir.
    output$oda_persona_secim_alani <- renderUI({
      rol <- oda_rol()
      secili <- as.character(secili_persona() %||% "")[1]
      if (!nzchar(secili)) {
        secili <- ortak_oturum_persona_kimligi(NULL, aktif_oturum())
      }

      # Yetkisi olmayan katılımcı için salt-okunur persona rozeti gösterilir.
      if (!ortak_yetki_var_mi(rol, "katilimci_yonet")) {
        gorunum <- ortak_oturum_persona_gorunumu(secili)
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

      div(
        class = "oo-composer-secim oo-composer-secim-persona",
        tags$span(class = "oo-composer-secim-ikon", icon("user-astronaut"), `aria-hidden` = "true"),
        selectInput(
          ns("oda_persona_secimi"),
          label = NULL,
          choices = ortak_persona_secenekleri(),
          selected = secili,
          width = "200px"
        )
      )
    })

    observeEvent(input$oda_persona_secimi, {
      deger <- ortak_oturum_persona_kimligi(input$oda_persona_secimi, aktif_oturum())
      oturum_id <- aktif_oturum()
      req(oturum_id)

      if (identical(deger, as.character(isolate(secili_persona()) %||% "")[1])) {
        return(invisible(NULL))
      }

      if (isTRUE(ortak_db_persona_guncelle(oturum_id, current_user_id(), deger))) {
        secili_persona(deger)
        gorunum <- ortak_oturum_persona_gorunumu(deger)
        oo_bildir(sprintf("Yapay zekâ personası değiştirildi: %s", gorunum$ad))
        oo_yenile()
      } else {
        oo_bildir("Persona değiştirilemedi: yetkiniz yok veya bu özellik henüz kurulmadı.", tur = "warning")
      }
    }, ignoreInit = TRUE)

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

    # NOT: uretim_durumu_alani çıktısı (süren üretim + kısmi yanıt + kuyruk)
    # yapay zekâ üretim motoruna (ortakOturumYzBind) taşınmıştır.

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

    # Yapay zekâ üretim motoru (soru gönderme + kuyruk + artımlı yayın +
    # BilgeYolaç köprüsü) ayrı bağlayıcıdadır; motor nesnesi paylaşılan
    # eylem yüzeyidir. yapay_zekaya_sor eylemi soruyu motora devreder.
    motor <- new.env(parent = emptyenv())

    oda_ctx <- list(
      aktif_oturum = aktif_oturum,
      current_user_id = current_user_id,
      oturum_bilgisi = oturum_bilgisi,
      benim_katilimim = benim_katilimim,
      katilimcilar = katilimcilar,
      kullanici_canli_durumu = kullanici_canli_durumu,
      yenile_sayaci = yenile_sayaci,
      secili_model = secili_model,
      etkin_persona = etkin_persona,
      parent_session = parent_session,
      bildir = oo_bildir,
      yenile = oo_yenile
    )

    ortakOturumYzBind(input, output, session, ctx = oda_ctx, motor = motor)
    ortakOturumBilgeYolacBind(input, output, session, ctx = oda_ctx, motor = motor)

    observeEvent(input$yapay_zekaya_sor, {
      oturum_id <- aktif_oturum()
      req(oturum_id)

      metin <- mesaj_metnini_al()
      if (is.null(metin)) {
        return(invisible(NULL))
      }

      updateTextAreaInput(session, "oda_mesaj_metni", value = "")
      motor$soru_gonder(oturum_id, current_user_id(), metin)
    })

    # --- Katılımcı çağırma paneli (ayrı bağlayıcı dosyada) ---------------------

    ortakOturumInvitesBind(input, output, session, ctx = oda_ctx)

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
        class = "oo-oda-btn oo-oda-btn-notr oo-btn-arsivle-herkes",
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

      katilim_listesi <- katilimcilar()
      hedef_ad <- if (is.data.frame(katilim_listesi) && nrow(katilim_listesi) > 0L) {
        eslesen <- katilim_listesi[katilim_listesi$KullaniciID == hedef_id, , drop = FALSE]
        if (nrow(eslesen) > 0L) as.character(eslesen$KaynakAdi[1] %||% "") else ""
      } else {
        ""
      }

      showModal(modalDialog(
        title = "Katılımcıyı Yönet",
        size = "m",
        div(
          class = "oo-katilimci-yonet-modal",
          if (nzchar(hedef_ad)) {
            p(class = "oo-yonet-hedef",
              tagList(icon("user"), tags$strong(HTML(htmltools::htmlEscape(hedef_ad)))))
          } else {
            NULL
          },
          selectInput(
            ns("yeni_rol"),
            label = "Rol",
            choices = ortak_rol_secenekleri(),
            selectize = FALSE
          ),
          p(class = "oo-yonet-notu",
            "Rol değişikliği veya çıkarma işlemi anında uygulanır.")
        ),
        footer = tagList(
          actionButton(ns("rol_kaydet"), tagList(icon("save"), span("Rol Değiştir")),
                       class = "oo-oda-btn oo-oda-btn-birincil"),
          if (sahibim) {
            actionButton(ns("sahiplik_devret"), tagList(icon("crown"), span("Sahipliği Devret")),
                         class = "oo-oda-btn oo-oda-btn-uyari")
          } else {
            NULL
          },
          actionButton(ns("katilimci_cikar"), tagList(icon("user-minus"), span("Çıkar")),
                       class = "oo-oda-btn oo-oda-btn-tehlike"),
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
        oo_bildir("Sahiplik devredildi; yeni rolünüz: Oturum Yöneticisi.")
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
