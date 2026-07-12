# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_by_calistirma.R
# Açıklama: Ortak Bilge Yolaç CANLI çalıştırma köprüsü. Tek kullanıcılı
#           Bilge Yolaç'ın gerçek kodlama-ajanı boru hattını (stream-json /
#           processx: run_claude_code_streaming) oda semantiğiyle kullanır:
#             * Araç kullanımı / kabuk komutu / metin deltaları çalıştırma
#               sırasında ilerleme dosyasına yazılır; başlatan oturum bunları
#               KismiYanit üzerinden TÜM katılımcılara yayınlar.
#             * Bilge Yolaç odasında normal LLM'e SESSİZ DÜŞÜŞ YOKTUR: CLI
#               yoksa açık engelleyici mesaj verilir, komut sohbette kalır ve
#               kilidi bırakılır (ajan çalışmış gibi YAPILMAZ).
#             * Durdurma: oda-kapsamlı durdurma bayrak dosyası; başlatan veya
#               katılımcı yöneten roller durdurabilir (sunucu tarafı doğrulanır).
#           Oda sunucu modülünden (ortakOturumBilgeYolacBind) çağrılır ve aynı
#           input/output bağlamını paylaşır. Saf yardımcılar
#           R/helpers_ortak_oturum_by_calisma_alani.R içindedir.
# ==============================================================================

ortakOturumByCalistirmaBind <- function(input, output, session, ctx, motor, by_ctx) {
  ns <- session$ns

  # Başlatan oturumun sürdürdüğü aktif ajan çalıştırmasının yerel durumu.
  by_uretim <- reactiveValues(
    aktif = FALSE,
    ilerleme_dosyasi = NULL,
    durdurma_dosyasi = NULL,
    istek_id = NULL,
    oturum_id = NULL,
    son_yayin = ""
  )

  yayin_bitir <- function() {
    dosyalar <- c(
      isolate(by_uretim$ilerleme_dosyasi),
      isolate(by_uretim$durdurma_dosyasi)
    )
    for (d in dosyalar) {
      if (!is.null(d) && nzchar(as.character(d)[1])) {
        suppressWarnings(unlink(d))
      }
    }
    by_uretim$aktif <- FALSE
    by_uretim$ilerleme_dosyasi <- NULL
    by_uretim$durdurma_dosyasi <- NULL
    by_uretim$son_yayin <- ""
  }

  # Çalışma alanının dosya anlık görüntüsü (üretilen/değişen dosya tespiti).
  # Tek kullanıcılı Bilge Yolaç'ın mtime+size tabanlı tarayıcısı yüklüyse onu
  # kullanırız; ortak oda çalıştırmalarında ajan çoğu kez var olan dosyayı
  # günceller, yalnızca setdiff(yol) yapmak bu çıktıları katılımcılardan
  # gizler. İzole test/yükleme bağlamları için eski yol-listesi düşüşü korunur.
  dosya_goruntusu <- function(ws) {
    if (is.null(ws) || !dir.exists(ws)) {
      return(character(0))
    }
    if (exists("snapshot_claude_code_workdir_files", mode = "function", inherits = TRUE)) {
      goruntu <- tryCatch(
        snapshot_claude_code_workdir_files(ws, recursive = TRUE),
        error = function(e) NULL
      )
      if (!is.null(goruntu)) {
        return(goruntu)
      }
    }
    tryCatch(
      list.files(ws, recursive = TRUE, full.names = TRUE, all.files = FALSE),
      error = function(e) character(0)
    )
  }

  dosya_goruntusu_yollari <- function(goruntu) {
    if (is.null(goruntu) || !length(goruntu)) {
      return(character(0))
    }
    if (is.character(goruntu)) {
      return(goruntu)
    }
    if (!is.list(goruntu)) {
      return(character(0))
    }
    yollar <- vapply(goruntu, function(kayit) {
      if (is.list(kayit)) {
        as.character(kayit$path %||% "")[1]
      } else {
        ""
      }
    }, character(1))
    unique(Filter(nzchar, yollar))
  }

  dosya_goruntusu_farki <- function(onceki, ws) {
    if (exists("diff_claude_code_workdir_snapshot", mode = "function", inherits = TRUE) &&
        is.list(onceki)) {
      fark <- tryCatch(
        diff_claude_code_workdir_snapshot(onceki, ws, recursive = TRUE),
        error = function(e) NULL
      )
      if (!is.null(fark)) {
        return(as.character(fark))
      }
    }
    setdiff(dosya_goruntusu_yollari(dosya_goruntusu(ws)), dosya_goruntusu_yollari(onceki))
  }

  # --- Canlı çalıştırma köprüsü (motor sözleşmesi) -------------------------------
  # Bilge Yolaç odasında HER sonuç bu köprüde ele alınır ve TRUE döner: normal
  # LLM'e düşüş yoktur. Başarısız ön koşullar kilidi motor$tamamla ile bırakır.
  motor$by_calistir <- function(oturum_id, soru_id, soran_id, istek_id,
                                komut = NULL, kuyruk_id = NULL, persona_id = NULL) {
    persona_kimligi <- ortak_oturum_persona_kimligi(persona_id, oturum_id)

    bitir_hata <- function(metin) {
      motor$tamamla(
        oturum_id, soru_id, istek_id,
        hata_metni = metin,
        kuyruk_id = kuyruk_id, soran_id = soran_id,
        persona_id = persona_kimligi
      )
      TRUE
    }

    komut_metni <- as.character(komut %||% "")[1]
    if (!nzchar(komut_metni)) {
      return(bitir_hata(
        "Bilge Yolaç komut metni boş; lütfen komutu yeniden gönderin."
      ))
    }

    if (!exists("run_claude_code_streaming", mode = "function", inherits = TRUE) ||
        !exists("tracked_future_promise", mode = "function", inherits = TRUE)) {
      return(bitir_hata(paste(
        "Bilge Yolaç çalıştırma altyapısı bu ortamda yüklü değil;",
        "komut çalıştırılamadı. Komutunuz sohbette duruyor."
      )))
    }

    cli <- as.character(by_ctx$cli_yolu() %||% "")[1]
    if (is.na(cli) || !nzchar(cli)) {
      # Sessiz LLM düşüşü YOK: açık engelleyici durum + yeniden deneme yolu.
      return(bitir_hata(paste(
        "Claude Code CLI bu ortamda bağlı değil; Bilge Yolaç komutu çalıştırılamadı.",
        "Komutunuz sohbette duruyor; CLI bağlandıktan sonra yeniden gönderebilirsiniz."
      )))
    }

    kayit <- by_ctx$by_kaydi_garantile(oturum_id, NULL)
    if (is.null(kayit)) {
      return(bitir_hata(
        "Bilge Yolaç oturum kaydı hazırlanamadı; lütfen tekrar deneyin."
      ))
    }

    # Etkin çalışma dizini kayıttan çözülür; özel dizin çalıştırma anında da
    # fail-closed doğrulanır (yetki/politika sonradan değişmiş olabilir).
    kayit_dizini <- as.character(kayit$OrtakCalismaDizini[1] %||% "")
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

    if (is.null(ws) || !nzchar(as.character(ws)[1])) {
      return(bitir_hata(
        "Bilge Yolaç çalışma alanı hazırlanamadı; komut çalıştırılamadı."
      ))
    }

    calistirma_prompt <- komut_metni
    persona_sistem <- ortak_oturum_persona_sistem_prompt(persona_kimligi, oturum_id)
    if (nzchar(persona_sistem)) {
      calistirma_prompt <- paste(
        persona_sistem,
        "Bilge Yolaç/Claude Code yanıtını ve çalışma özetini bu persona talimatıyla uyumlu üret.",
        komut_metni,
        sep = "\n\n"
      )
    }

    by_id <- as.integer(kayit$OrtakBilgeYolacOturumID[1])
    cli_session <- as.character(kayit$ClaudeCliSessionID[1] %||% "")
    if (is.na(cli_session) || !nzchar(cli_session)) {
      cli_session <- NULL
    }

    model_secimi <- as.character(shiny::isolate(by_ctx$by_model()) %||% "")[1]
    if (!nzchar(model_secimi)) {
      kayit_model <- as.character(kayit$Model[1] %||% "")
      model_secimi <- if (!is.na(kayit_model) && nzchar(kayit_model)) kayit_model else NULL
    }

    anahtar <- if (exists("mb_api_key_get_feature_key_value", mode = "function", inherits = TRUE)) {
      mb_api_key_get_feature_key_value(session = ctx$parent_session %||% session)
    } else {
      NULL
    }

    onceki_dosyalar <- dosya_goruntusu(ws)
    baslangic <- Sys.time()
    zaman_asimi <- if (exists("claude_code_config", inherits = TRUE)) {
      claude_code_config$timeout_seconds %||% 600L
    } else {
      600L
    }

    # Paylaşılan otomatik klasörde çalışırken kayıt dizini görünürlük için
    # güncellenir; özel dizin kaydı kullanıcı eylemiyle yönetilir (ezilmez).
    if (!isTRUE(dizin_bilgisi$ozel)) {
      ortak_db_by_oturum_guncelle(oturum_id, calisma_dizini = ws)
    }

    # Oda-kapsamlı yan dosyalar: canlı ilerleme + durdurma bayrağı. Tüm
    # oturumlar (ve yatay ölçeklenen süreçler) aynı yolu türetebilir.
    ilerleme_dosyasi <- ortak_by_calistirma_yan_dosyasi(oturum_id, istek_id, "ilerleme")
    durdurma_dosyasi <- ortak_by_calistirma_yan_dosyasi(oturum_id, istek_id, "durdur")
    if (nzchar(ilerleme_dosyasi)) {
      file.create(ilerleme_dosyasi, showWarnings = FALSE)
    }
    if (nzchar(durdurma_dosyasi)) {
      suppressWarnings(unlink(durdurma_dosyasi))
    }

    by_uretim$aktif <- TRUE
    by_uretim$ilerleme_dosyasi <- ilerleme_dosyasi
    by_uretim$durdurma_dosyasi <- durdurma_dosyasi
    by_uretim$istek_id <- istek_id
    by_uretim$oturum_id <- oturum_id
    by_uretim$son_yayin <- ""
    ilerleme_durumu <- new.env(parent = emptyenv())
    ilerleme_durumu$araclar <- list()

    prom <- tracked_future_promise(
      task_fn = function() {
        run_claude_code_streaming(
          prompt = calistirma_prompt,
          workdir = ws,
          model = model_secimi,
          timeout_sec = zaman_asimi,
          session_id = cli_session,
          cli_path = cli,
          api_key = anahtar,
          stop_file = durdurma_dosyasi,
          on_chunk = function(parca) {
            # İşçi tarafı: parça, katılımcılara yayınlanacak ilerleme
            # kayıtlarına indirgenir ve ilerleme dosyasına JSONL yazılır.
            if (!nzchar(ilerleme_dosyasi)) {
              return(invisible(NULL))
            }
            kayitlar <- oo_by_ilerleme_kayitlari(parca, durum = ilerleme_durumu)
            for (k in kayitlar) {
              satir <- tryCatch(
                as.character(jsonlite::toJSON(k, auto_unbox = TRUE)),
                error = function(e) ""
              )
              if (nzchar(satir)) {
                cat(satir, "\n", sep = "", file = ilerleme_dosyasi, append = TRUE)
              }
            }
            invisible(NULL)
          }
        )
      },
      task_type = "ortak_by_calistirma",
      session_token = session$token
    )

    promises::then(
      prom,
      onFulfilled = function(sonuc) {
        yayin_bitir()
        tryCatch(
          by_tamamla(
            oturum_id = oturum_id, soru_id = soru_id, soran_id = soran_id,
            istek_id = istek_id, komut = komut_metni, sonuc = sonuc, ws = ws,
            by_id = by_id, onceki_dosyalar = onceki_dosyalar,
            baslangic = baslangic, kuyruk_id = kuyruk_id,
            persona_id = persona_kimligi
          ),
          error = function(e) {
            if (exists("log_error", mode = "function", inherits = TRUE)) {
              tryCatch(
                log_error(paste("[ORTAK_BY] Çalıştırma tamamlama hatası:", conditionMessage(e))),
                error = function(log_e) NULL
              )
            }
            motor$tamamla(
              oturum_id, soru_id, istek_id,
              hata_metni = "Bilge Yolaç çalıştırması tamamlandı ancak sonuç kaydı güvenli biçimde işlenemedi; kilit bırakıldı, lütfen tekrar deneyin.",
              kuyruk_id = kuyruk_id, soran_id = soran_id,
              persona_id = persona_kimligi
            )
          }
        )
      },
      onRejected = function(e) {
        yayin_bitir()
        tryCatch(
          ortak_db_by_calistirma_kaydet(
            ortak_by_oturum_id = by_id,
            komutu_veren_kullanici_id = soran_id,
            komut = komut_metni,
            durum = "Başarısız",
            sure_saniye = as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
          ),
          error = function(kayit_hatasi) {
            if (exists("log_error", mode = "function", inherits = TRUE)) {
              tryCatch(
                log_error(paste("[ORTAK_BY] Başarısız çalıştırma kaydı yazılamadı:", conditionMessage(kayit_hatasi))),
                error = function(log_e) NULL
              )
            }
            NULL
          }
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
    durduruldu <- isTRUE(sonuc$stopped)

    yeni_dosyalar <- dosya_goruntusu_farki(onceki_dosyalar, ws)

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
      durum = if (basarili) "Tamamlandı" else if (durduruldu) "Durduruldu" else "Başarısız",
      uretilen_dosyalar_json = uretilen_json,
      sure_saniye = sure
    )

    # Üretilen dosyalar ortak oda belgesi olur + odaya belge bildirimi düşer
    # (durdurulan çalıştırmada da o ana dek üretilen dosyalar paylaşılır).
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
    } else if (durduruldu) {
      motor$tamamla(
        oturum_id, soru_id, istek_id,
        hata_metni = "Bilge Yolaç çalıştırması durduruldu.",
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

    by_ctx$dizin_yenile_bump()
    invisible(NULL)
  }

  # --- Canlı ilerleme yayıncısı: ilerleme dosyasını KismiYanit'e yansıt ---------
  # Başlatan oturum okur; tüm katılımcılar odanın 4 sn yoklamasıyla görür.
  observe({
    req(isTRUE(by_uretim$aktif), by_uretim$ilerleme_dosyasi)
    invalidateLater(1500, session)

    satirlar <- tryCatch(
      readLines(by_uretim$ilerleme_dosyasi, warn = FALSE, encoding = "UTF-8"),
      error = function(e) character(0)
    )
    if (length(satirlar) == 0L) {
      return(invisible(NULL))
    }

    kismi <- oo_by_kismi_ilerleme_metni(satirlar)
    if (nzchar(kismi) && !identical(kismi, isolate(by_uretim$son_yayin))) {
      by_uretim$son_yayin <- kismi
      ortak_db_uretim_kismi_yanit_guncelle(
        isolate(by_uretim$oturum_id),
        isolate(by_uretim$istek_id),
        kismi
      )
    }

    invisible(NULL)
  })

  # --- Durdurma: buton (üretim paneli kancası) + sunucu tarafı doğrulama --------

  # Üretim durumu paneli (ortakOturumYzBind) BY odasında bu kancayı çizer.
  # Yalnızca başlatan katılımcı veya katılımcı yöneten roller görür; asıl
  # yetki denetimi durdurma gözlemcisinde SUNUCU tarafında yeniden yapılır.
  motor$by_durdur_ui <- function(detay) {
    bilgi <- ctx$oturum_bilgisi()
    if (is.null(bilgi) ||
        !identical(as.character(bilgi$KaynakTuru[1] %||% ""), "BilgeYolaç")) {
      return(NULL)
    }

    katilim <- ctx$benim_katilimim()
    if (is.null(katilim) || !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1])) {
      return(NULL)
    }

    baslatan_id <- suppressWarnings(as.integer(detay$BaslatanKullaniciID[1] %||% NA_integer_))
    ben <- suppressWarnings(as.integer(ctx$current_user_id()))
    yetkili <- (!is.na(baslatan_id) && identical(baslatan_id, ben)) ||
      ortak_yetki_var_mi(katilim$Rol[1], "katilimci_yonet")
    if (!isTRUE(yetkili)) {
      return(NULL)
    }

    actionButton(
      ns("by_calistirma_durdur"),
      label = tagList(icon("stop"), span("Durdur")),
      class = "oo-oda-btn oo-oda-btn-tehlike oo-by-durdur-btn",
      title = "Süren Bilge Yolaç çalıştırmasını durdur"
    )
  }

  observeEvent(input$by_calistirma_durdur, {
    oturum_id <- ctx$aktif_oturum()
    req(oturum_id)

    detay <- ortak_db_aktif_uretim_detay(oturum_id)
    if (is.null(detay) ||
        !identical(as.character(detay$KilitDurumu[1] %||% ""), "Çalışıyor")) {
      ctx$bildir("Durdurulacak aktif bir Bilge Yolaç çalıştırması yok.", tur = "warning")
      return(invisible(NULL))
    }

    # Fail-closed sunucu doğrulaması: başlatan veya katılımcı yöneten rol.
    katilim <- ortak_db_katilimci_getir(oturum_id, ctx$current_user_id())
    baslatan_id <- suppressWarnings(as.integer(detay$BaslatanKullaniciID[1] %||% NA_integer_))
    ben <- suppressWarnings(as.integer(ctx$current_user_id()))
    yetkili <- !is.null(katilim) &&
      ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1]) &&
      ((!is.na(baslatan_id) && identical(baslatan_id, ben)) ||
         ortak_yetki_var_mi(katilim$Rol[1], "katilimci_yonet"))

    if (!isTRUE(yetkili)) {
      ctx$bildir("Bu çalıştırmayı durdurma yetkiniz yok.", tur = "error")
      return(invisible(NULL))
    }

    istek <- as.character(detay$IstekID[1] %||% "")
    dosya <- ortak_by_calistirma_yan_dosyasi(oturum_id, istek, "durdur")
    if (!nzchar(dosya)) {
      ctx$bildir("Durdurma isteği hazırlanamadı.", tur = "error")
      return(invisible(NULL))
    }

    file.create(dosya, showWarnings = FALSE)
    ctx$bildir("Durdurma isteği gönderildi; çalıştırma güvenli biçimde sonlandırılıyor.")
  })

  # --- Kompozer model katmanları (Hızlı / Dengeli / Güçlü) ----------------------
  # BY odasında genel model açılır menüsü yerine tek kullanıcılı Bilge Yolaç
  # model katmanı deneyimi çizilir (araç seçici render'ı bu kancaya delege eder).
  motor$by_model_secici_ui <- function() {
    secili <- as.character(by_ctx$by_model() %||% "")[1]
    if (!nzchar(secili)) {
      secili <- as.character(by_ctx$by_kayit_model_rv() %||% "")[1]
    }

    div(
      class = "oo-by-composer-model",
      title = "Bilge Yolaç model katmanı: sonraki çalıştırmalarda kullanılır",
      tags$span(
        class = "oo-by-composer-model-etiket",
        tagList(icon("robot"), span("Bilge Yolaç"))
      ),
      oo_by_model_govde_html(
        katmanlar = by_ctx$model_katmanlari(),
        secili = secili,
        hedef_input_id = ns("by_model_sec")
      )
    )
  }

  invisible(TRUE)
}
