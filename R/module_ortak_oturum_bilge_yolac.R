# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_bilge_yolac.R
# Açıklama: Ortak Bilge Yolaç çalışma alanı bağlayıcısı. Oda sunucu modülünden
#           (R/module_ortak_oturum_room.R) çağrılır; yalnızca KaynakTuru =
#           BilgeYolaç odalarında görünür. Tek kullanıcılı Bilge Yolaç
#           deneyiminin ortak oda sürümü:
#             * Proje Dizini: oda başına PAYLAŞILAN çalışma alanı
#               (ortak belge kökü altında calisma_alani/).
#             * Model katmanları: Hızlı / Dengeli / Güçlü (settings.json).
#             * Hazır Senaryolar: tek kullanıcılı senaryo şablonları.
#             * Dizin İçeriği: paylaşılan çalışma alanı listesi.
#             * Eklentiler: bilge_yolac_plugins salt-okunur envanteri.
#             * Canlı çalıştırma köprüsü: run_claude_code() paylaşılan çalışma
#               alanında koşar; çalıştırma MB_OrtakBilgeYolac_Calistirmalar'a,
#               üretilen dosyalar ortak belge deposuna yazılır.
#           Mini oyun BİLİNÇLİ olarak ortak moda taşınmaz.
#
# Sözleşmeler:
#   * Çalışma alanı mutasyonu (klasör kopyalama/dosya yükleme) yalnızca
#     ortak_by_calisma_alani_yazabilir_mi (Sahip/Oturum Yöneticisi) rollerine
#     açıktır; çalıştırma ortak_by_calistirabilir_mi (yapay_zeka_sor) ister.
#   * CLI bu ortamda yoksa sahte başarı ÜRETİLMEZ: durum rozeti "CLI bağlı
#     değil" gösterir ve sorular normal LLM yoluna düşer (motor sözleşmesi).
#   * Kişisel dosyalar OTOMATİK kopyalanmaz; yalnızca açık kullanıcı eylemiyle
#     paylaşılan çalışma alanına alınır.
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
    by_tetik()
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

  # --- Çalışma alanı paneli -----------------------------------------------------

  output$by_alani <- renderUI({
    if (!by_odasi_mi()) {
      return(NULL)
    }

    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    katilim <- ctx$benim_katilimim()
    if (is.null(katilim) || !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1])) {
      return(NULL)
    }

    ws <- ortak_by_calisma_alani(oturum_id)
    cli <- cli_yolu()
    cli_bagli <- !is.null(cli) && nzchar(cli)

    kayit <- by_kaydi()
    secili <- as.character(by_model() %||% "")[1]
    if (!nzchar(secili) && !is.null(kayit)) {
      kayit_model <- as.character(kayit$Model[1] %||% "")
      if (!is.na(kayit_model) && nzchar(kayit_model)) {
        secili <- kayit_model
      }
    }

    katmanlar <- model_katmanlari()

    div(
      class = "oo-by-panel",
      div(
        class = "oo-by-baslik",
        tags$button(
          type = "button",
          class = "oo-by-toggle",
          `data-oo-toggle-by` = "1",
          `aria-label` = "Bilge Yolaç çalışma alanı panelini aç/kapat",
          icon("chevron-down", class = "oo-by-toggle-ikon")
        ),
        icon("robot", class = "oo-by-baslik-ikon"),
        span(class = "oo-by-baslik-metin", "Bilge Yolaç Çalışma Alanı"),
        if (cli_bagli) {
          tags$span(class = "oo-rozet oo-rozet-cli-bagli",
                    tagList(icon("plug"), span("CLI Bağlı")))
        } else {
          tags$span(
            class = "oo-rozet oo-rozet-cli-yok",
            title = "Claude Code CLI bu ortamda bulunamadı; sorular genel yapay zekâ modeliyle yanıtlanır.",
            tagList(icon("plug-circle-xmark"), span("CLI Bağlı Değil"))
          )
        }
      ),
      div(
        class = "oo-by-govde",

        # Proje dizini + model katmanları
        div(
          class = "oo-by-ust-satir",
          div(
            class = "oo-by-proje-dizini",
            span(class = "oo-by-alan-etiket", tagList(icon("folder-tree"), span("Proje Dizini"))),
            tags$code(class = "oo-by-dizin-yolu", title = ws %||% "",
                      HTML(htmltools::htmlEscape(ws %||% "Çalışma alanı oluşturulamadı")))
          ),
          div(
            class = "oo-by-model-secim",
            span(class = "oo-by-alan-etiket", tagList(icon("microchip"), span("Model"))),
            if (length(katmanlar) == 0L) {
              tags$span(class = "oo-by-model-yok", "Model katmanı bulunamadı (settings.json)")
            } else {
              tagList(lapply(seq_along(katmanlar), function(i) {
                katman <- katmanlar[[i]]
                aktif <- identical(as.character(katman$deger %||% ""), secili) ||
                  (!nzchar(secili) && i == 1L)
                tags$button(
                  type = "button",
                  class = paste("oo-by-model-btn", if (aktif) "oo-by-model-aktif" else NULL),
                  title = katman$aciklama %||% "",
                  `data-oo-model-deger` = as.character(katman$deger %||% ""),
                  `data-oo-hedef-input` = ns("by_model_sec"),
                  `data-oo-kullanici-id` = as.character(katman$deger %||% ""),
                  HTML(htmltools::htmlEscape(katman$etiket %||% "Model"))
                )
              }))
            }
          )
        ),

        # Senaryolar + dizin içeriği
        div(
          class = "oo-by-orta-satir",
          div(
            class = "oo-by-senaryolar",
            span(class = "oo-by-alan-etiket", tagList(icon("wand-magic-sparkles"), span("Hazır Senaryolar"))),
            div(
              class = "oo-by-senaryo-grid",
              lapply(claude_code_scenarios, function(senaryo) {
                actionButton(
                  ns(paste0("by_senaryo_", senaryo$id)),
                  label = tagList(icon(senaryo$ikon), span(senaryo$baslik)),
                  class = "oo-by-senaryo-btn",
                  title = senaryo$aciklama
                )
              })
            )
          ),
          div(
            class = "oo-by-dizin",
            div(
              class = "oo-by-dizin-baslik",
              span(class = "oo-by-alan-etiket", tagList(icon("folder-open"), span("Dizin İçeriği"))),
              actionButton(
                ns("by_dizin_yenile"),
                label = NULL,
                icon = icon("sync"),
                class = "oo-by-mini-btn",
                `aria-label` = "Dizin içeriğini yenile"
              )
            ),
            div(class = "oo-by-dizin-listesi", uiOutput(ns("by_dizin_icerigi")))
          )
        ),

        # Çalışma alanına dosya alma eylemleri (yalnızca yetkili roller)
        if (calisma_alani_yazabilir()) {
          div(
            class = "oo-by-dosya-eylemleri",
            actionButton(
              ns("by_dosyalarimi_kopyala"),
              label = tagList(icon("copy"), span("Yükleme Klasörümü Çalışma Alanına Kopyala")),
              class = "oo-oda-btn oo-oda-btn-ikincil oo-by-kopyala-btn",
              title = "Dosya Yönetimi klasörünüzdeki dosyaları paylaşılan çalışma alanına kopyalar (açık eylem; otomatik kopya yapılmaz)"
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
        } else {
          NULL
        },

        # Eklentiler + çalıştırma geçmişi
        div(
          class = "oo-by-alt-satir",
          div(
            class = "oo-by-eklentiler",
            span(class = "oo-by-alan-etiket", tagList(icon("puzzle-piece"), span("Eklentiler"))),
            uiOutput(ns("by_eklentiler"))
          ),
          div(
            class = "oo-by-gecmis",
            span(class = "oo-by-alan-etiket", tagList(icon("clock-rotate-left"), span("Çalıştırma Geçmişi"))),
            uiOutput(ns("by_calistirma_gecmisi"))
          )
        )
      )
    )
  })

  # --- Dizin içeriği -------------------------------------------------------------

  output$by_dizin_icerigi <- renderUI({
    by_tetik()
    dizin_yenile()

    oturum_id <- ctx$aktif_oturum()
    req(oturum_id, by_odasi_mi())

    ws <- ortak_by_calisma_alani(oturum_id)
    if (is.null(ws)) {
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

    tagList(lapply(listeleme$items, function(oge) {
      klasor <- identical(as.character(oge$tip %||% ""), "klasor")
      ad <- as.character(oge$gorunen_ad %||% oge$ad %||% "")[1]
      boyut <- as.character(oge$boyut %||% "")[1]

      div(
        class = "oo-by-dizin-satiri",
        icon(if (klasor) "folder" else "file-lines", class = "oo-by-dizin-ikon"),
        tags$span(class = "oo-by-dizin-ad", title = ad, HTML(htmltools::htmlEscape(ad))),
        if (nzchar(boyut) && !is.na(boyut)) {
          tags$span(class = "oo-by-dizin-boyut", HTML(htmltools::htmlEscape(boyut)))
        } else {
          NULL
        }
      )
    }))
  })

  observeEvent(input$by_dizin_yenile, {
    dizin_yenile(isolate(dizin_yenile()) + 1L)
  })

  # --- Eklentiler (salt-okunur envanter) -------------------------------------------

  output$by_eklentiler <- renderUI({
    req(by_odasi_mi())

    tarama <- if (exists("scan_local_plugins", mode = "function", inherits = TRUE)) {
      tryCatch(scan_local_plugins(), error = function(e) list(success = FALSE, plugins = list()))
    } else {
      list(success = FALSE, plugins = list())
    }

    if (!isTRUE(tarama$success) || length(tarama$plugins) == 0L) {
      return(div(class = "oo-by-eklenti-yok", "Kurulu eklenti bulunamadı."))
    }

    tagList(lapply(tarama$plugins, function(p) {
      div(
        class = "oo-by-eklenti-satiri",
        title = as.character(p$description %||% ""),
        icon("puzzle-piece", class = "oo-by-eklenti-ikon"),
        tags$span(class = "oo-by-eklenti-ad", HTML(htmltools::htmlEscape(as.character(p$name %||% "")))),
        tags$span(
          class = "oo-by-eklenti-bilesen",
          HTML(htmltools::htmlEscape(paste(
            vapply(as.character(p$components %||% character(0)), function(b) {
              tanim <- claude_code_plugin_bilesenler[[b]]
              if (is.list(tanim)) tanim$etiket %||% b else b
            }, character(1)),
            collapse = " · "
          )))
        )
      )
    }))
  })

  # --- Çalıştırma geçmişi -----------------------------------------------------------

  output$by_calistirma_gecmisi <- renderUI({
    by_tetik()
    req(by_odasi_mi())

    kayit <- by_kaydi()
    if (is.null(kayit)) {
      return(div(class = "oo-by-eklenti-yok", "Henüz çalıştırma yok."))
    }

    calistirmalar <- ortak_db_by_calistirmalar(as.integer(kayit$OrtakBilgeYolacOturumID[1]))
    if (!is.data.frame(calistirmalar) || nrow(calistirmalar) == 0L) {
      return(div(class = "oo-by-eklenti-yok", "Henüz çalıştırma yok."))
    }

    # En yeni 5 çalıştırma üstte
    calistirmalar <- calistirmalar[order(calistirmalar$CalistirmaSirasi, decreasing = TRUE), , drop = FALSE]
    calistirmalar <- utils::head(calistirmalar, 5L)

    tagList(lapply(seq_len(nrow(calistirmalar)), function(i) {
      satir <- calistirmalar[i, , drop = FALSE]
      durum <- as.character(satir$Durum[1] %||% "")
      komut <- as.character(satir$Komut[1] %||% "")
      if (nchar(komut) > 70L) {
        komut <- paste0(substr(komut, 1L, 70L), "…")
      }
      veren <- as.character(satir$KomutuVerenAdi[1] %||% "")
      sure <- suppressWarnings(as.numeric(satir$SureSaniye[1]))

      durum_sinifi <- switch(
        durum,
        "Tamamlandı" = "oo-by-durum-tamam",
        "Çalışıyor" = "oo-by-durum-calisiyor",
        "oo-by-durum-hata"
      )

      div(
        class = "oo-by-gecmis-satiri",
        tags$span(class = paste("oo-rozet", durum_sinifi), HTML(htmltools::htmlEscape(durum))),
        tags$span(class = "oo-by-gecmis-komut", title = as.character(satir$Komut[1] %||% ""),
                  HTML(htmltools::htmlEscape(komut))),
        tags$span(
          class = "oo-by-gecmis-meta",
          HTML(htmltools::htmlEscape(paste(
            Filter(nzchar, c(
              veren,
              if (!is.na(sure)) sprintf("%.0f sn", sure) else ""
            )),
            collapse = " · "
          )))
        )
      )
    }))
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
      by_kaydi_garantile(oturum_id, ortak_by_calisma_alani(oturum_id))
      ortak_db_by_oturum_guncelle(oturum_id, model = deger)
    }

    ctx$bildir("Bilge Yolaç modeli güncellendi; sonraki çalıştırmalarda kullanılacak.")
    ctx$yenile()
  })

  lapply(claude_code_scenarios, function(senaryo) {
    observeEvent(input[[paste0("by_senaryo_", senaryo$id)]], {
      if (nzchar(senaryo$sablon)) {
        updateTextAreaInput(session, "oda_mesaj_metni", value = senaryo$sablon)
      }
    })
  })

  # --- Çalışma alanına dosya alma -----------------------------------------------------

  ws_kopyala <- function(kaynak_yollar, kaynak_adlar) {
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    if (!calisma_alani_yazabilir()) {
      ctx$bildir("Paylaşılan çalışma alanını yalnızca Sahip ve Oturum Yöneticisi değiştirebilir.", tur = "error")
      return(invisible(0L))
    }

    ws <- ortak_by_calisma_alani(oturum_id)
    if (is.null(ws)) {
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
    ws <- ortak_by_calisma_alani(oturum_id)

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

    kayit <- by_kaydi_garantile(oturum_id, ws)
    if (is.null(kayit)) {
      return(FALSE)
    }

    by_id <- as.integer(kayit$OrtakBilgeYolacOturumID[1])
    cli_session <- as.character(kayit$ClaudeCliSessionID[1] %||% "")
    if (is.na(cli_session) || !nzchar(cli_session)) {
      cli_session <- NULL
    }

    model_secimi <- as.character(by_model() %||% "")[1]
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

    ortak_db_by_oturum_guncelle(oturum_id, calisma_dizini = ws)

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
      hata <- as.character(sonuc$error %||% "")[1]
      if (nchar(hata) > 240L) {
        hata <- paste0(substr(hata, 1L, 240L), "…")
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
