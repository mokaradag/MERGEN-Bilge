# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_bilge_yolac.R
# Açıklama: Ortak Bilge Yolaç çalışma alanı bağlayıcısı; yalnızca KaynakTuru =
#           BilgeYolaç odalarında görünür (oda sunucu modülünden çağrılır).
#           Tek kullanıcılı deneyimin oda sürümü: düzenlenebilir Proje Dizini,
#           model katmanları, Hazır Senaryolar, Dizin İçeriği, Eklentiler ve
#           run_claude_code() canlı çalıştırma köprüsü. Panel/kart HTML
#           üreticileri ve dizin güvenlik kapısı
#           R/helpers_ortak_oturum_by_calisma_alani.R içindedir.
#
# Sözleşmeler (ayrıntı: CLAUDE.md + docs/ortak-oturumlar.md):
#   * Panel iskeleti yalnızca oda/erişim sinyali değişince yeniden çizilir;
#     yoklama iç kartları tazeler — aç/kapa tercihi (varsayılan KAPALI) korunur.
#   * Dizin değiştirme / dosya kopyalama yalnızca yazma yetkili rollere açıktır;
#     özel proje dizini ortak_by_ozel_dizin_dogrula fail-closed kapısından geçer
#     (yönetilen köklere — başka oda / kişisel kova — işaret edilemez).
#   * CLI yoksa sahte başarı ÜRETİLMEZ; sorular normal LLM yoluna düşer.
#   * Kişisel dosyalar OTOMATİK kopyalanmaz. Mini oyun ortak moda taşınmaz.
# ==============================================================================

# Oda başına paylaşılan Bilge Yolaç çalışma alanı dizini (yoksa oluşturur).
ortak_by_calisma_alani <- function(oturum_id) {
  kok <- ortak_oturum_dosya_koku(oturum_id)
  if (is.null(kok)) {
    return(NULL)
  }

  ws <- file.path(kok, "calisma_alani")
  dir.create(ws, showWarnings = FALSE, recursive = TRUE)
  if (!dir.exists(ws)) {
    return(NULL)
  }
  ws
}

# Çalışma alanının dosya anlık görüntüsü (üretilen dosya tespiti için).
.oo_by_dosya_goruntusu <- function(ws) {
  if (is.null(ws) || !dir.exists(ws)) {
    return(character(0))
  }
  tryCatch(
    list.files(ws, recursive = TRUE, full.names = TRUE, all.files = FALSE),
    error = function(e) character(0)
  )
}

ortakOturumBilgeYolacBind <- function(input, output, session, ctx, motor) {
  ns <- session$ns

  by_model <- reactiveVal("")
  dizin_yenile <- reactiveVal(0L)

  # Kompakt sinyaller: panel iskeleti yalnızca bu değerler GERÇEKTEN
  # değişince yeniden çizilir (4 sn yoklama panelin aç/kapa DOM durumunu
  # sıfırlamasın diye gövde ayrı iç çıktılara bölünmüştür).
  by_odasi_sinyali <- reactiveVal(FALSE)
  by_erisim_sinyali <- reactiveVal(FALSE)
  by_yazabilir_sinyali <- reactiveVal(FALSE)
  by_kayit_dizin_rv <- reactiveVal("")
  by_kayit_model_rv <- reactiveVal("")

  cli_yolu <- function() {
    if (!exists("resolve_claude_cli_path", mode = "function", inherits = TRUE)) {
      return(NULL)
    }
    tryCatch(
      resolve_claude_cli_path(claude_code_config$cli_path),
      error = function(e) NULL
    )
  }

  by_odasi_mi <- reactive({
    bilgi <- ctx$oturum_bilgisi()
    !is.null(bilgi) && identical(as.character(bilgi$KaynakTuru[1]), "BilgeYolaç")
  })

  by_tetik <- function() {
    if (is.function(ctx$by_yenile_sayaci)) {
      ctx$by_yenile_sayaci()
    } else {
      ctx$yenile_sayaci()
    }
  }

  by_kaydi <- reactive({
    ctx$yenile_sayaci()
    oturum_id <- ctx$aktif_oturum()
    if (is.null(oturum_id) || !by_odasi_mi()) {
      return(NULL)
    }
    ortak_db_by_oturum_getir(oturum_id)
  })

  # BY oturum kaydı garantile (eski odalarda kayıt eksik olabilir).
  by_kaydi_garantile <- function(oturum_id, ws = NULL) {
    kayit <- ortak_db_by_oturum_getir(oturum_id)
    if (is.null(kayit)) {
      ortak_db_by_oturum_olustur(oturum_id, calisma_dizini = ws)
      kayit <- ortak_db_by_oturum_getir(oturum_id)
    }
    kayit
  }

  model_katmanlari <- function() {
    if (!exists("read_claude_settings_json", mode = "function", inherits = TRUE) ||
        !exists("build_model_tier_choices", mode = "function", inherits = TRUE)) {
      return(list())
    }
    tryCatch(
      build_model_tier_choices(read_claude_settings_json()$models),
      error = function(e) list()
    )
  }

  calisma_alani_yazabilir <- function() {
    katilim <- ctx$benim_katilimim()
    !is.null(katilim) && ortak_by_calisma_alani_yazabilir_mi(katilim$Rol[1])
  }

  # Etkin çalışma dizini: kayıttaki özel dizin (varsa/erişilebilirse) veya
  # paylaşılan otomatik oda klasörü. Reaktif olmayan bağlamlardan da çağrılır.
  etkin_dizin_bilgisi <- function(oturum_id) {
    kayit_dizini <- shiny::isolate(by_kayit_dizin_rv())
    ortak_by_etkin_calisma_dizini(kayit_dizini, oturum_id)
  }

  # Kompakt sinyal güncelleyicileri (identical değişim kapısı).
  observe({
    yeni_oda <- isTRUE(by_odasi_mi())
    katilim <- ctx$benim_katilimim()
    yeni_erisim <- !is.null(katilim) &&
      ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1])
    yeni_yazma <- !is.null(katilim) &&
      ortak_by_calisma_alani_yazabilir_mi(katilim$Rol[1])

    if (!identical(isolate(by_odasi_sinyali()), yeni_oda)) by_odasi_sinyali(yeni_oda)
    if (!identical(isolate(by_erisim_sinyali()), yeni_erisim)) by_erisim_sinyali(yeni_erisim)
    if (!identical(isolate(by_yazabilir_sinyali()), yeni_yazma)) by_yazabilir_sinyali(yeni_yazma)
  })

  observe({
    kayit <- by_kaydi()
    dizin <- if (!is.null(kayit)) as.character(kayit$OrtakCalismaDizini[1] %||% "") else ""
    if (is.na(dizin)) dizin <- ""
    model <- if (!is.null(kayit)) as.character(kayit$Model[1] %||% "") else ""
    if (is.na(model)) model <- ""

    if (!identical(isolate(by_kayit_dizin_rv()), dizin)) by_kayit_dizin_rv(dizin)
    if (!identical(isolate(by_kayit_model_rv()), model)) by_kayit_model_rv(model)
  })

  # --- Panel iskeleti (statik; varsayılan KAPALI) -------------------------------
  # İskelet yalnızca oda/erişim sinyalleri değişince yeniden çizilir; yoklama
  # yalnızca iç kart çıktılarını tazeler (aç/kapa tercihi korunur).

  output$by_alani <- renderUI({
    oturum_id <- ctx$aktif_oturum()
    if (is.null(oturum_id) || !by_odasi_sinyali() || !by_erisim_sinyali()) {
      return(NULL)
    }

    senaryolar <- if (exists("claude_code_scenarios", inherits = TRUE)) {
      claude_code_scenarios
    } else {
      list()
    }

    oo_by_panel_iskeleti_html(ns, senaryolar = senaryolar)
  })

  output$by_durum_rozeti <- renderUI({
    req(by_odasi_sinyali())
    dizin_yenile()

    cli <- cli_yolu()
    oo_by_durum_rozeti_html(!is.null(cli) && nzchar(cli))
  })

  # --- Proje Dizini kartı --------------------------------------------------------

  output$by_proje_dizini_karti <- renderUI({
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id, by_odasi_sinyali())

    bilgi <- ortak_by_etkin_calisma_dizini(by_kayit_dizin_rv(), oturum_id)
    yol <- as.character(bilgi$yol %||% "")[1]

    oo_by_kart_html(
      "Proje Dizini", "folder-open",
      oo_by_proje_dizini_govde_html(
        girdi_id = ns("by_workdir_girdisi"),
        uygula_id = ns("by_workdir_uygula"),
        sifirla_id = ns("by_workdir_sifirla"),
        yol = yol,
        ozel = isTRUE(bilgi$ozel),
        yazabilir = by_yazabilir_sinyali()
      )
    )
  })

  observeEvent(input$by_workdir_uygula, {
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    if (!calisma_alani_yazabilir()) {
      ctx$bildir("Proje dizinini yalnızca Sahip ve Oturum Yöneticisi değiştirebilir.", tur = "error")
      return(invisible(NULL))
    }

    yol <- trimws(as.character(input$by_workdir_girdisi %||% "")[1])
    if (!nzchar(yol)) {
      ctx$bildir("Önce bir proje dizini yolu yazın.", tur = "warning")
      return(invisible(NULL))
    }

    # Yazılan yol zaten paylaşılan oda klasörüyse özel dizin kaydı tutulmaz.
    otomatik <- ortak_by_calisma_alani(oturum_id)
    if (!is.null(otomatik) && .ortak_by_kok_icinde_mi(yol, otomatik) &&
        .ortak_by_kok_icinde_mi(otomatik, yol)) {
      ortak_db_by_oturum_guncelle(oturum_id, calisma_dizini = "")
      ctx$bildir("Oda paylaşılan klasöründe çalışmaya devam edecek.")
      ctx$yenile()
      return(invisible(NULL))
    }

    dogrulama <- ortak_by_ozel_dizin_dogrula(
      yol, oturum_id,
      user_id = ctx$current_user_id()
    )

    if (!isTRUE(dogrulama$ok)) {
      ctx$bildir(as.character(dogrulama$error %||% "Proje dizini doğrulanamadı."), tur = "error")
      return(invisible(NULL))
    }

    by_kaydi_garantile(oturum_id, NULL)
    ortak_db_by_oturum_guncelle(oturum_id, calisma_dizini = dogrulama$path)
    # Dizin değişikliği tüm odayı etkiler; katılımcılara görünür sistem notu düşer.
    ortak_db_mesaj_ekle(
      oturum_id = oturum_id,
      gonderen_kullanici_id = NULL,
      mesaj_turu = "SistemMesajı",
      mesaj_metni = sprintf("Bilge Yolaç proje dizini güncellendi: %s", dogrulama$path)
    )
    ctx$bildir("Proje dizini güncellendi; sonraki çalıştırmalar bu dizinde koşacak.")
    dizin_yenile(isolate(dizin_yenile()) + 1L)
    ctx$yenile()
  })

  observeEvent(input$by_workdir_sifirla, {
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    if (!calisma_alani_yazabilir()) {
      ctx$bildir("Proje dizinini yalnızca Sahip ve Oturum Yöneticisi değiştirebilir.", tur = "error")
      return(invisible(NULL))
    }

    by_kaydi_garantile(oturum_id, NULL)
    ortak_db_by_oturum_guncelle(oturum_id, calisma_dizini = "")
    ortak_db_mesaj_ekle(
      oturum_id = oturum_id,
      gonderen_kullanici_id = NULL,
      mesaj_turu = "SistemMesajı",
      mesaj_metni = "Bilge Yolaç proje dizini paylaşılan oda klasörüne döndürüldü."
    )
    ctx$bildir("Proje dizini paylaşılan oda klasörüne döndürüldü.")
    dizin_yenile(isolate(dizin_yenile()) + 1L)
    ctx$yenile()
  })

  # --- Model kartı -----------------------------------------------------------------

  output$by_model_karti <- renderUI({
    req(by_odasi_sinyali())

    secili <- as.character(by_model() %||% "")[1]
    if (!nzchar(secili)) {
      secili <- by_kayit_model_rv()
    }

    oo_by_kart_html(
      "Model", "microchip",
      oo_by_model_govde_html(
        katmanlar = model_katmanlari(),
        secili = secili,
        hedef_input_id = ns("by_model_sec")
      )
    )
  })

  # --- Dizin içeriği -------------------------------------------------------------

  output$by_dizin_yolu_alani <- renderUI({
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id, by_odasi_sinyali())

    bilgi <- ortak_by_etkin_calisma_dizini(by_kayit_dizin_rv(), oturum_id)
    yol <- as.character(bilgi$yol %||% "")[1]

    tags$code(
      class = "oo-by-dizin-yolu oo-by-dizin-yolu-kompakt",
      title = yol,
      HTML(htmltools::htmlEscape(if (nzchar(yol) && !is.na(yol)) yol else "Çalışma alanı hazır değil"))
    )
  })

  output$by_dizin_icerigi <- renderUI({
    by_tetik()
    dizin_yenile()

    oturum_id <- ctx$aktif_oturum()
    req(oturum_id, by_odasi_sinyali())

    ws <- ortak_by_etkin_calisma_dizini(by_kayit_dizin_rv(), oturum_id)$yol
    if (is.null(ws) || !nzchar(as.character(ws)[1])) {
      return(div(class = "oo-bos-durum oo-bos-belge", p("Çalışma alanı hazır değil.")))
    }

    listeleme <- if (exists("list_directory_contents", mode = "function", inherits = TRUE)) {
      list_directory_contents(ws, max_items = 50L, user_id = ctx$current_user_id())
    } else {
      list(success = FALSE, items = list())
    }

    if (!isTRUE(listeleme$success) || length(listeleme$items) == 0L) {
      return(div(
        class = "oo-bos-durum oo-bos-belge",
        p("Çalışma alanı henüz boş. Dosya kopyalayın ya da Bilge Yolaç'a ürettirin.")
      ))
    }

    oo_by_dizin_satirlari_html(listeleme$items)
  })

  observeEvent(input$by_dizin_yenile, {
    dizin_yenile(isolate(dizin_yenile()) + 1L)
  })

  # --- Dosya alma eylemleri (yalnızca yetkili roller) -------------------------------

  output$by_dosya_eylem_karti <- renderUI({
    req(by_odasi_sinyali(), by_yazabilir_sinyali())

    oo_by_kart_html(
      "Dosya Aktarımı", "file-import",
      div(
        class = "oo-by-dosya-eylemleri",
        actionButton(
          ns("by_dosyalarimi_kopyala"),
          label = tagList(icon("copy"), span("Yükleme Klasörümü Çalışma Alanına Kopyala")),
          class = "oo-oda-btn oo-oda-btn-ikincil oo-by-kopyala-btn",
          title = "Dosya Yönetimi klasörünüzdeki dosyaları odanın çalışma alanına kopyalar (açık eylem; otomatik kopya yapılmaz)"
        ),
        div(
          class = "oo-by-yerel-yukleme",
          fileInput(
            ns("by_yerel_dosyalar"),
            label = NULL,
            multiple = TRUE,
            buttonLabel = tagList(icon("upload"), span("Yerel Klasörünü Çalışma Alanına Kopyala")),
            placeholder = "Dosya seçilmedi"
          )
        )
      )
    )
  })

  # --- Eklentiler (salt-okunur envanter) -------------------------------------------

  output$by_eklentiler <- renderUI({
    req(by_odasi_sinyali())

    tarama <- if (exists("scan_local_plugins", mode = "function", inherits = TRUE)) {
      tryCatch(scan_local_plugins(), error = function(e) list(success = FALSE, plugins = list()))
    } else {
      list(success = FALSE, plugins = list())
    }

    pluginler <- if (isTRUE(tarama$success)) tarama$plugins else list()
    bilesenler <- if (exists("claude_code_plugin_bilesenler", inherits = TRUE)) {
      claude_code_plugin_bilesenler
    } else {
      list()
    }

    oo_by_eklenti_listesi_html(pluginler, bilesenler)
  })

  # --- Çalıştırma geçmişi -----------------------------------------------------------

  output$by_calistirma_gecmisi <- renderUI({
    by_tetik()
    req(by_odasi_sinyali())

    kayit <- by_kaydi()
    if (is.null(kayit)) {
      return(div(class = "oo-by-eklenti-yok", "Henüz çalıştırma yok."))
    }

    oo_by_gecmis_listesi_html(
      ortak_db_by_calistirmalar(as.integer(kayit$OrtakBilgeYolacOturumID[1]))
    )
  })

  # --- Model / senaryo eylemleri -----------------------------------------------------

  observeEvent(input$by_model_sec, {
    deger <- as.character(input$by_model_sec$id %||% "")[1]
    req(nzchar(deger))

    katilim <- ctx$benim_katilimim()
    if (is.null(katilim) ||
        !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1]) ||
        !ortak_by_calistirabilir_mi(katilim$Rol[1])) {
      ctx$bildir("Bilge Yolaç modelini değiştirme yetkiniz yok.", tur = "error")
      return(invisible(NULL))
    }

    by_model(deger)

    oturum_id <- ctx$aktif_oturum()
    if (!is.null(oturum_id)) {
      by_kaydi_garantile(oturum_id, NULL)
      ortak_db_by_oturum_guncelle(oturum_id, model = deger)
    }

    ctx$bildir("Bilge Yolaç modeli güncellendi; sonraki çalıştırmalarda kullanılacak.")
    ctx$yenile()
  })

  lapply(
    if (exists("claude_code_scenarios", inherits = TRUE)) claude_code_scenarios else list(),
    function(senaryo) {
      observeEvent(input[[paste0("by_senaryo_", senaryo$id)]], {
        if (nzchar(senaryo$sablon)) {
          updateTextAreaInput(session, "oda_mesaj_metni", value = senaryo$sablon)
        }
      })
    }
  )

  # --- Çalışma alanına dosya alma -----------------------------------------------------

  ws_kopyala <- function(kaynak_yollar, kaynak_adlar) {
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    if (!calisma_alani_yazabilir()) {
      ctx$bildir("Paylaşılan çalışma alanını yalnızca Sahip ve Oturum Yöneticisi değiştirebilir.", tur = "error")
      return(invisible(0L))
    }

    ws <- etkin_dizin_bilgisi(oturum_id)$yol
    if (is.null(ws) || !nzchar(as.character(ws)[1])) {
      ctx$bildir("Çalışma alanı oluşturulamadı.", tur = "error")
      return(invisible(0L))
    }

    kopyalanan <- 0L
    for (i in seq_along(kaynak_yollar)) {
      yol <- kaynak_yollar[i]
      if (!file.exists(yol) || dir.exists(yol)) {
        next
      }
      hedef <- .oo_dosya_hedef_adi(ws, kaynak_adlar[i])
      if (!.oo_dosya_kok_icinde_mi(hedef, ws)) {
        next
      }
      if (isTRUE(tryCatch(file.copy(yol, hedef, overwrite = FALSE), error = function(e) FALSE))) {
        kopyalanan <- kopyalanan + 1L
      }
    }

    if (kopyalanan > 0L) {
      ortak_db_olay_ekle(oturum_id, "BelgeÜretildi", ctx$current_user_id())
      dizin_yenile(isolate(dizin_yenile()) + 1L)
    }

    invisible(kopyalanan)
  }

  observeEvent(input$by_dosyalarimi_kopyala, {
    uid <- ctx$current_user_id()
    kaynak_dizin <- if (exists("mergen_user_upload_dir", mode = "function", inherits = TRUE)) {
      tryCatch(mergen_user_upload_dir(uid), error = function(e) NULL)
    } else {
      NULL
    }

    if (is.null(kaynak_dizin) || !dir.exists(kaynak_dizin)) {
      ctx$bildir("Yükleme klasörünüz bulunamadı.", tur = "warning")
      return(invisible(NULL))
    }

    dosyalar <- list.files(kaynak_dizin, full.names = TRUE)
    dosyalar <- dosyalar[!dir.exists(dosyalar)]

    if (length(dosyalar) == 0L) {
      ctx$bildir("Yükleme klasörünüzde kopyalanacak dosya yok.", tur = "warning")
      return(invisible(NULL))
    }

    adet <- ws_kopyala(dosyalar, basename(dosyalar))
    ctx$bildir(sprintf("%d dosya paylaşılan çalışma alanına kopyalandı.", adet))
  })

  observeEvent(input$by_yerel_dosyalar, {
    dosyalar <- input$by_yerel_dosyalar
    req(is.data.frame(dosyalar), nrow(dosyalar) > 0L)

    adet <- ws_kopyala(dosyalar$datapath, dosyalar$name)
    ctx$bildir(sprintf("%d dosya paylaşılan çalışma alanına kopyalandı.", adet))
  })

  # --- Canlı çalıştırma köprüsü (motor sözleşmesi) -------------------------------------

  # @return TRUE: çalıştırma başlatıldı (motor beklemeye geçer);
  #         FALSE: köprü kullanılamıyor (motor normal LLM'e düşer).
  motor$by_calistir <- function(oturum_id, soru_id, soran_id, istek_id,
                                komut = NULL, kuyruk_id = NULL, persona_id = NULL) {
    if (!exists("run_claude_code", mode = "function", inherits = TRUE) ||
        !exists("tracked_future_promise", mode = "function", inherits = TRUE)) {
      return(FALSE)
    }

    cli <- cli_yolu()

    # Etkin çalışma dizini kayıttan çözülür; özel dizin çalıştırma anında da
    # fail-closed doğrulanır (yetki/politika sonradan değişmiş olabilir).
    kayit <- by_kaydi_garantile(oturum_id, NULL)
    kayit_dizini <- if (!is.null(kayit)) as.character(kayit$OrtakCalismaDizini[1] %||% "") else ""
    if (is.na(kayit_dizini)) kayit_dizini <- ""

    dizin_bilgisi <- ortak_by_etkin_calisma_dizini(kayit_dizini, oturum_id)
    ws <- dizin_bilgisi$yol

    if (isTRUE(dizin_bilgisi$ozel)) {
      dogrulama <- ortak_by_ozel_dizin_dogrula(ws, oturum_id, user_id = soran_id)
      if (!isTRUE(dogrulama$ok)) {
        ws <- ortak_by_calisma_alani(oturum_id)
        dizin_bilgisi$ozel <- FALSE
        if (exists("log_warn", mode = "function", inherits = TRUE)) {
          tryCatch(
            log_warn("[ORTAK_BY] Özel proje dizini doğrulanamadı; paylaşılan oda klasörüne düşüldü."),
            error = function(e) NULL
          )
        }
      }
    }

    if (is.null(ws)) {
      return(FALSE)
    }

    if (is.null(cli) || !nzchar(cli)) {
      # Sahte başarı üretme: durumu odaya açıkça bildir, normal LLM'e düş.
      ortak_db_mesaj_ekle(
        oturum_id = oturum_id,
        gonderen_kullanici_id = NULL,
        mesaj_turu = "SistemMesajı",
        mesaj_metni = "Claude Code CLI bu ortamda bağlı değil; soru genel yapay zekâ modeliyle yanıtlanıyor."
      )
      return(FALSE)
    }

    komut_metni <- as.character(komut %||% "")[1]
    if (!nzchar(komut_metni)) {
      return(FALSE)
    }

    calistirma_prompt <- komut_metni
    persona_kimligi <- ortak_oturum_persona_kimligi(persona_id, oturum_id)
    persona_sistem <- ortak_oturum_persona_sistem_prompt(persona_kimligi, oturum_id)
    if (nzchar(persona_sistem)) {
      calistirma_prompt <- paste(
        persona_sistem,
        "Bilge Yolaç/Claude Code yanıtını ve çalışma özetini bu persona talimatıyla uyumlu üret.",
        komut_metni,
        sep = "\n\n"
      )
    }

    if (is.null(kayit)) {
      return(FALSE)
    }

    by_id <- as.integer(kayit$OrtakBilgeYolacOturumID[1])
    cli_session <- as.character(kayit$ClaudeCliSessionID[1] %||% "")
    if (is.na(cli_session) || !nzchar(cli_session)) {
      cli_session <- NULL
    }

    model_secimi <- as.character(shiny::isolate(by_model()) %||% "")[1]
    if (!nzchar(model_secimi)) {
      kayit_model <- as.character(kayit$Model[1] %||% "")
      if (!is.na(kayit_model) && nzchar(kayit_model)) {
        model_secimi <- kayit_model
      } else {
        model_secimi <- NULL
      }
    }

    anahtar <- if (exists("mb_api_key_get_feature_key_value", mode = "function", inherits = TRUE)) {
      mb_api_key_get_feature_key_value(session = ctx$parent_session %||% session)
    } else {
      NULL
    }

    onceki_dosyalar <- .oo_by_dosya_goruntusu(ws)
    baslangic <- Sys.time()
    zaman_asimi <- claude_code_config$timeout_seconds %||% 600L

    # Paylaşılan otomatik klasörde çalışırken kayıt dizini görünürlük için
    # güncellenir; özel dizin kaydı kullanıcı eylemiyle yönetilir (ezilmez).
    if (!isTRUE(dizin_bilgisi$ozel)) {
      ortak_db_by_oturum_guncelle(oturum_id, calisma_dizini = ws)
    }

    prom <- tracked_future_promise(
      task_fn = function() {
        run_claude_code(
          prompt = calistirma_prompt,
          workdir = ws,
          model = model_secimi,
          timeout_sec = zaman_asimi,
          session_id = cli_session,
          cli_path = cli,
          api_key = anahtar
        )
      },
      task_type = "ortak_by_calistirma",
      session_token = session$token
    )

    promises::then(
      prom,
      onFulfilled = function(sonuc) {
        by_tamamla(
          oturum_id = oturum_id, soru_id = soru_id, soran_id = soran_id,
          istek_id = istek_id, komut = komut_metni, sonuc = sonuc, ws = ws,
          by_id = by_id, onceki_dosyalar = onceki_dosyalar,
          baslangic = baslangic, kuyruk_id = kuyruk_id,
          persona_id = persona_kimligi
        )
      },
      onRejected = function(e) {
        ortak_db_by_calistirma_kaydet(
          ortak_by_oturum_id = by_id,
          komutu_veren_kullanici_id = soran_id,
          komut = komut_metni,
          durum = "Başarısız",
          sure_saniye = as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
        )
        motor$tamamla(
          oturum_id, soru_id, istek_id,
          hata_metni = "Bilge Yolaç çalıştırması başarısız oldu; lütfen tekrar deneyin.",
          kuyruk_id = kuyruk_id, soran_id = soran_id,
          persona_id = persona_kimligi
        )
      }
    )

    TRUE
  }

  # Çalıştırma sonucu: çalıştırma kaydı + üretilen ortak belgeler + yanıt mesajı.
  by_tamamla <- function(oturum_id, soru_id, soran_id, istek_id, komut, sonuc,
                         ws, by_id, onceki_dosyalar, baslangic, kuyruk_id,
                         persona_id = NULL) {
    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
    basarili <- isTRUE(sonuc$success)

    yeni_dosyalar <- setdiff(.oo_by_dosya_goruntusu(ws), onceki_dosyalar)

    uretilen_json <- if (length(yeni_dosyalar) > 0L) {
      tryCatch(
        as.character(jsonlite::toJSON(basename(yeni_dosyalar), auto_unbox = FALSE)),
        error = function(e) NULL
      )
    } else {
      NULL
    }

    calistirma_id <- ortak_db_by_calistirma_kaydet(
      ortak_by_oturum_id = by_id,
      komutu_veren_kullanici_id = soran_id,
      komut = komut,
      nihai_yanit = if (basarili) as.character(sonuc$output %||% "")[1] else NULL,
      durum = if (basarili) "Tamamlandı" else "Başarısız",
      uretilen_dosyalar_json = uretilen_json,
      sure_saniye = sure
    )

    # Üretilen dosyalar ortak oda belgesi olur + odaya belge bildirimi düşer.
    for (dosya in yeni_dosyalar) {
      dosya_id <- ortak_db_dosya_kaydet(
        oturum_id = oturum_id,
        kaynak_yol = dosya,
        ureten_kullanici_id = soran_id,
        ortak_calistirma_id = calistirma_id
      )
      if (!is.null(dosya_id)) {
        ortak_db_mesaj_ekle(
          oturum_id = oturum_id,
          gonderen_kullanici_id = NULL,
          mesaj_turu = "BelgeBildirimi",
          mesaj_metni = sprintf("Yeni ortak belge üretildi: %s", basename(dosya))
        )
        ortak_db_olay_ekle(oturum_id, "BelgeÜretildi", soran_id)
      }
    }

    # CLI oturum kimliği korunur (devam eden konuşma bağlamı).
    yeni_cli_session <- as.character(sonuc$session_id %||% "")[1]
    if (!is.na(yeni_cli_session) && nzchar(yeni_cli_session)) {
      ortak_db_by_oturum_guncelle(oturum_id, cli_session_id = yeni_cli_session)
    }

    if (basarili) {
      cikti <- as.character(sonuc$output %||% "")[1]
      if (!nzchar(trimws(cikti))) {
        cikti <- "Bilge Yolaç çalıştırması tamamlandı."
      }
      motor$tamamla(
        oturum_id, soru_id, istek_id,
        yanit_metni = cikti,
        kuyruk_id = kuyruk_id, soran_id = soran_id,
        persona_id = persona_id
      )
    } else {
      # Ham CLI/altyapı tanılaması odaya sızmasın: güvenli yanıt süzgeci
      # (ayrıntı sunucu günlüğünde; oda genel Türkçe mesaj görür).
      hata <- as.character(sonuc$error %||% "")[1]
      if (nchar(hata) > 240L) {
        hata <- paste0(substr(hata, 1L, 240L), "…")
      }
      if (exists("oo_arac_oda_guvenli_yanit", mode = "function", inherits = TRUE)) {
        hata <- oo_arac_oda_guvenli_yanit(hata)
      }
      motor$tamamla(
        oturum_id, soru_id, istek_id,
        hata_metni = paste("Bilge Yolaç çalıştırması başarısız:", hata),
        kuyruk_id = kuyruk_id, soran_id = soran_id,
        persona_id = persona_id
      )
    }

    dizin_yenile(isolate(dizin_yenile()) + 1L)
    invisible(NULL)
  }

  invisible(TRUE)
}