# ==============================================================================
# Dosya Yolu: R/module_ortak_oturum_yz.R
# Açıklama: Ortak Oturum yapay zekâ üretim motoru bağlayıcısı. Oda sunucu
#           modülünden (R/module_ortak_oturum_room.R) çağrılır ve aynı modül
#           input/output bağlamını paylaşır. Sorumluluklar:
#             * Soru gönderme: kilit alınamazsa kalıcı KUYRUĞA ekleme
#               (MB_OrtakOturum_YapayZekaKuyrugu) — soru kaybolmaz.
#             * Üretim: SSE işçisiyle artımlı yayın (kısmi yanıt DB üzerinden
#               tüm katılımcılara yayınlanır); SSE yoksa non-streaming düşüş.
#             * Tamamlanınca kuyruğun başındaki soruyu devralma (zincir).
#             * Üretim durumu paneli: süren üretim + kısmi yanıt + kuyruk.
#
# Sözleşmeler:
#   * OdaMesajı ASLA LLM tetiklemez; tek LLM yolu YapayZekaSorusu'dur.
#   * Ortak sayfalarda SES YOKTUR: bu motor TTS/AI Uzman konuşması tetiklemez.
#   * LLM çağrısı worker'da koşar (tracked_future_promise); DB kalıcılığı ve
#     kilit bırakma ana süreçteki promise callback'indedir.
#   * BilgeYolaç odalarında üretim, motor$by_calistir köprüsüne devredilir
#     (R/module_ortak_oturum_bilge_yolac.R); köprü yoksa/CLI kapalıysa
#     normal LLM yoluna güvenli düşüş yapılır.
# ==============================================================================

ortakOturumYzBind <- function(input, output, session, ctx, motor) {
  ns <- session$ns

  # Bu oturumun sürdürdüğü aktif üretimin istemci-yerel durumu (kısmi yayın).
  uretim <- reactiveValues(
    aktif = FALSE,
    stream_file = NULL,
    istek_id = NULL,
    oturum_id = NULL,
    son_yayin = ""
  )

  yeni_istek_id <- function(oturum_id) {
    paste0(
      "oo_", oturum_id, "_",
      format(Sys.time(), "%Y%m%d%H%M%S"), "_",
      sample.int(999999L, 1L)
    )
  }

  # Odanın etkin modeli: hızlı model seçimi > ORTAK_OTURUM_MODEL > ilk model.
  etkin_model <- function() {
    secim <- as.character(ctx$secili_model() %||% "")[1]
    if (nzchar(secim)) {
      return(secim)
    }

    model_id <- Sys.getenv("ORTAK_OTURUM_MODEL", unset = "")
    if (!nzchar(model_id) && exists("api_config", inherits = TRUE)) {
      model_id <- as.character(api_config$local_models[1] %||% "")
    }
    model_id
  }

  api_anahtari <- function() {
    if (exists("mb_api_key_get_feature_key_value", mode = "function", inherits = TRUE)) {
      mb_api_key_get_feature_key_value(session = ctx$parent_session %||% session)
    } else {
      ""
    }
  }

  # --- Soru gönderme: kilit + kalıcı kuyruk -----------------------------------

  motor$soru_gonder <- function(oturum_id, uid, metin) {
    soru_id <- ortak_db_mesaj_ekle(
      oturum_id = oturum_id,
      gonderen_kullanici_id = uid,
      mesaj_turu = "YapayZekaSorusu",
      mesaj_metni = metin,
      llm_gonderildi = TRUE
    )

    if (is.null(soru_id)) {
      ctx$bildir("Soru gönderilemedi: bu odada yapay zekâya sorma yetkiniz yok.", tur = "error")
      return(invisible(FALSE))
    }

    istek_id <- yeni_istek_id(oturum_id)

    if (ortak_db_uretim_kilidi_al(
      oturum_id = oturum_id,
      baslatan_kullanici_id = uid,
      istek_id = istek_id,
      mesaj_id = soru_id
    )) {
      ctx$yenile()
      motor$uret(oturum_id, soru_id, uid, istek_id, metin)
    } else {
      kuyruk_id <- ortak_db_kuyruk_ekle(oturum_id, soru_id)
		if (is.null(kuyruk_id)) {
		  ctx$bildir(
			"Yanıt üretimi sürüyor; sorunuz kalıcı kuyruğa alınamadı ve yapay zekâ bağlamından çıkarıldı. Lütfen yeniden gönderin.",
			tur = "warning"
		  )
		} else {
		  ctx$bildir("Yanıt üretimi sürüyor; sorunuz sıraya alındı ve otomatik yanıtlanacak.")
		}
      ctx$yenile()
    }

    invisible(TRUE)
  }

  # --- Üretim yönlendirme: BilgeYolaç köprüsü veya normal LLM ------------------

  motor$uret <- function(oturum_id, soru_id, soran_id, istek_id,
                         metin = NULL, kuyruk_id = NULL) {
    ortak_db_olay_ekle(oturum_id, "YanıtBaşladı", soran_id)

    bilgi <- ortak_db_oturum_getir(oturum_id)
    by_odasi <- !is.null(bilgi) && identical(as.character(bilgi$KaynakTuru[1]), "BilgeYolaç")

    if (by_odasi && is.function(motor$by_calistir)) {
      basladi <- motor$by_calistir(oturum_id, soru_id, soran_id, istek_id, metin, kuyruk_id)
      if (isTRUE(basladi)) {
        return(invisible(NULL))
      }
      # CLI köprüsü kullanılamıyor: normal LLM yoluna güvenli düşüş.
    }

    motor$llm_uret(oturum_id, soru_id, soran_id, istek_id, kuyruk_id)
    invisible(NULL)
  }

  # --- Tamamlama + kuyruk zinciri ---------------------------------------------

	motor$tamamla <- function(oturum_id, soru_id, istek_id,
							  yanit_metni = NULL, hata_metni = NULL,
							  kuyruk_id = NULL, soran_id = NULL) {
	  aktif_detay <- ortak_db_aktif_uretim_detay(oturum_id)
	  aktif_istek <- if (!is.null(aktif_detay)) {
		as.character(aktif_detay$IstekID[1] %||% "")
	  } else {
		""
	  }
	  aktif_durum <- if (!is.null(aktif_detay)) {
		as.character(aktif_detay$KilitDurumu[1] %||% "")
	  } else {
		""
	  }

	  if (!identical(aktif_istek, as.character(istek_id %||% "")[1]) ||
		  !identical(aktif_durum, "Çalışıyor")) {
		uretim$aktif <- FALSE
		uretim$stream_file <- NULL
		uretim$son_yayin <- ""
		return(invisible(NULL))
	  }

	  if (!is.null(hata_metni)) {
		ortak_db_mesaj_ekle(
		  oturum_id = oturum_id,
		  gonderen_kullanici_id = NULL,
		  mesaj_turu = "SistemMesajı",
		  mesaj_metni = hata_metni
		)
      ortak_db_uretim_kilidi_birak(oturum_id, istek_id, sonuc_durumu = "Hata")
      if (!is.null(kuyruk_id)) {
        ortak_db_kuyruk_tamamla(kuyruk_id, "Hata")
      }
    } else {
      ortak_db_mesaj_ekle(
        oturum_id = oturum_id,
        gonderen_kullanici_id = NULL,
        mesaj_turu = "YapayZekaYanıtı",
        mesaj_metni = yanit_metni,
        bagli_mesaj_id = soru_id
      )
      ortak_db_uretim_kilidi_birak(oturum_id, istek_id, sonuc_durumu = "Tamamlandı")
      if (!is.null(kuyruk_id)) {
        ortak_db_kuyruk_tamamla(kuyruk_id, "Tamamlandı")
      }
      ortak_db_olay_ekle(oturum_id, "YanıtTamamlandı", soran_id)
    }

    uretim$aktif <- FALSE
    uretim$stream_file <- NULL
    uretim$son_yayin <- ""
    ctx$yenile()

    motor$kuyruk_isle(oturum_id)
    invisible(NULL)
  }

  # Kuyruğun başındaki bekleyen soruyu devral ve üretimi başlat.
  motor$kuyruk_isle <- function(oturum_id) {
    sonraki <- ortak_db_kuyruk_sonraki_al(oturum_id)
    if (is.null(sonraki)) {
      return(invisible(NULL))
    }

    istek_id <- yeni_istek_id(oturum_id)
    kilit_ok <- ortak_db_uretim_kilidi_al(
      oturum_id = oturum_id,
      baslatan_kullanici_id = sonraki$soran_id,
      istek_id = istek_id,
      mesaj_id = sonraki$mesaj_id
    )

    if (!isTRUE(kilit_ok)) {
      # Yetki/katılım değişmişse bu kayıt artık çalıştırılamaz; başta bekletmek
      # kuyruğu kalıcı olarak tıkayacağı için Hata ile kapatılır.
      katilimci <- ortak_db_katilimci_getir(oturum_id, sonraki$soran_id)
      yetki_devam_ediyor <- !is.null(katilimci) &&
        ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) &&
        ortak_yetki_var_mi(katilimci$Rol[1], "yapay_zeka_sor")

      if (!isTRUE(yetki_devam_ediyor)) {
        ortak_db_kuyruk_tamamla(sonraki$kuyruk_id, "Hata")
        ortak_db_mesaj_ekle(
          oturum_id = oturum_id,
          gonderen_kullanici_id = NULL,
          mesaj_turu = "SistemMesajı",
          mesaj_metni = "Sıradaki yapay zekâ sorusu yanıtlanmadı: soruyu soran kullanıcının oda erişimi veya yapay zekâya sorma yetkisi artık geçerli değil.",
          bagli_mesaj_id = sonraki$mesaj_id
        )
        motor$kuyruk_isle(oturum_id)
      } else {
        # Başka bir oturum kilidi kaptı: kayıt tekrar Bekliyor'a döner (kaybolmaz).
        ortak_db_kuyruk_beklet(sonraki$kuyruk_id)
      }

      return(invisible(NULL))
    }

    motor$uret(
      oturum_id, sonraki$mesaj_id, sonraki$soran_id, istek_id,
      metin = sonraki$mesaj_metni, kuyruk_id = sonraki$kuyruk_id
    )
    invisible(NULL)
  }

  # --- Normal LLM üretimi (SSE artımlı yayın + non-streaming düşüş) ------------

  motor$llm_uret <- function(oturum_id, soru_id, soran_id, istek_id, kuyruk_id = NULL) {
    if (!exists("call_local_llm", mode = "function", inherits = TRUE)) {
      return(motor$tamamla(
        oturum_id, soru_id, istek_id,
        hata_metni = "Yapay zekâ hizmeti bu ortamda yapılandırılmamış.",
        kuyruk_id = kuyruk_id, soran_id = soran_id
      ))
    }

	# LLM bağlamı: yalnızca bu soruya kadar olan YZ soru/yanıt geçmişi.
	# Kuyrukta arkadan gelen YapayZekaSorusu satırları henüz yanıtlanmadığı için
	# bu üretimin bağlamına girmemeli.
	mesaj_df <- ortak_db_mesajlari_getir(oturum_id, soran_id)

	if (is.data.frame(mesaj_df) &&
		nrow(mesaj_df) > 0L &&
		all(c("OrtakMesajID", "MesajSirasi") %in% names(mesaj_df))) {
	  aktif_soru <- mesaj_df[
		as.character(mesaj_df$OrtakMesajID) == as.character(soru_id),
		,
		drop = FALSE
	  ]

	  if (nrow(aktif_soru) > 0L) {
		soru_sirasi <- suppressWarnings(as.numeric(aktif_soru$MesajSirasi[1]))
		mesaj_siralari <- suppressWarnings(as.numeric(mesaj_df$MesajSirasi))

		if (!is.na(soru_sirasi)) {
		  mesaj_df <- mesaj_df[
			!is.na(mesaj_siralari) & mesaj_siralari <= soru_sirasi,
			,
			drop = FALSE
		  ]
		}
	  }
	}

	gecmis <- ortak_yz_sohbet_gecmisi(mesaj_df)

    ayarlar <- list(
      model_selection = etkin_model(),
      temperature = 0.4,
      enable_mcp_tools = FALSE,
      api_key_override = api_anahtari()
    )

    sse_hazir <- exists("call_local_llm_sse_worker", mode = "function", inherits = TRUE) &&
      exists("mergen_true_streaming_worker_globals", mode = "function", inherits = TRUE) &&
      exists("tracked_future_promise", mode = "function", inherits = TRUE)

    bitir <- function(yanit_metni = NULL, hata_metni = NULL) {
      motor$tamamla(
        oturum_id, soru_id, istek_id,
        yanit_metni = yanit_metni, hata_metni = hata_metni,
        kuyruk_id = kuyruk_id, soran_id = soran_id
      )
    }

    if (sse_hazir) {
      # Artımlı yayın: işçi delta satırlarını akış dosyasına yazar; bu oturum
      # dosyayı okuyup kısmi yanıtı kilit satırına yazar, tüm katılımcılar
      # yoklamayla görür.
      stream_file <- file.path(
        tempdir(),
        paste0("oo_stream_", gsub("[^A-Za-z0-9_]", "", istek_id), ".jsonl")
      )
      file.create(stream_file, showWarnings = FALSE)

      uretim$aktif <- TRUE
      uretim$stream_file <- stream_file
      uretim$istek_id <- istek_id
      uretim$oturum_id <- oturum_id
      uretim$son_yayin <- ""

      prom <- tracked_future_promise(
        task_fn = function() {
          call_local_llm_sse_worker(
            chat_history_for_sse,
            settings_for_sse,
            stream_file_for_sse,
            stop_file_for_sse
          )
        },
        task_type = "ortak_oturum_llm",
        session_token = session$token,
        globals = mergen_true_streaming_worker_globals(
          chat_history_for_sse = gecmis,
          settings_for_sse = ayarlar,
          stream_file_for_sse = stream_file,
          stop_file_for_sse = NULL
        )
      )

      promises::then(
        prom,
        onFulfilled = function(yanit) {
          icerik <- as.character(yanit$content %||% "")[1]
          if (nzchar(icerik)) {
            bitir(yanit_metni = icerik)
          } else {
            bitir(hata_metni = "Yapay zekâ boş yanıt döndürdü; lütfen tekrar deneyin.")
          }
          unlink(stream_file)
        },
        onRejected = function(e) {
          bitir(hata_metni = "Yapay zekâ yanıtı üretilemedi; lütfen tekrar deneyin.")
          unlink(stream_file)
        }
      )

      return(invisible(NULL))
    }

    # SSE altyapısı olmayan bağlamlar: mevcut non-streaming davranış.
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
            bitir(yanit_metni = icerik)
          } else {
            bitir(hata_metni = "Yapay zekâ boş yanıt döndürdü; lütfen tekrar deneyin.")
          }
        },
        onRejected = function(e) {
          bitir(hata_metni = "Yapay zekâ yanıtı üretilemedi; lütfen tekrar deneyin.")
        }
      )
    } else {
      yanit <- tryCatch(call_local_llm(gecmis, ayarlar), error = function(e) NULL)
      icerik <- as.character(yanit$content %||% "")[1]
      if (nzchar(icerik)) {
        bitir(yanit_metni = icerik)
      } else {
        bitir(hata_metni = "Yapay zekâ yanıtı üretilemedi; lütfen tekrar deneyin.")
      }
    }

    invisible(NULL)
  }

  # --- Kısmi yanıt yayıncısı: akış dosyasını 2 sn'de bir DB'ye yansıt -----------

  observe({
    req(isTRUE(uretim$aktif), uretim$stream_file)
    invalidateLater(2000, session)

    satirlar <- tryCatch(
      readLines(uretim$stream_file, warn = FALSE, encoding = "UTF-8"),
      error = function(e) character(0)
    )
    if (length(satirlar) == 0L) {
      return(invisible(NULL))
    }

	kismi <- if (exists("mergen_stream_classify_poll_lines", mode = "function", inherits = TRUE)) {
	  sinif <- mergen_stream_classify_poll_lines(satirlar)
	  as.character(sinif$delta_text %||% "")[1]
	} else {
	  ""
	}

    if (nzchar(kismi) && !identical(kismi, isolate(uretim$son_yayin))) {
      uretim$son_yayin <- kismi
      ortak_db_uretim_kismi_yanit_guncelle(
        isolate(uretim$oturum_id),
        isolate(uretim$istek_id),
        kismi
      )
    }

    invisible(NULL)
  })

  # --- Üretim durumu paneli: süren üretim + kısmi yanıt + kuyruk ----------------

	output$uretim_durumu_alani <- renderUI({
	  ctx$yenile_sayaci()
	  oturum_id <- ctx$aktif_oturum()
	  if (is.null(oturum_id)) {
		return(NULL)
	  }

	  # P2 privacy guard: active production details and queue contents are room
	  # content. A user who was removed while the room is still open must not keep
	  # seeing partial answers, asker names, or queued question snippets.
	  katilim <- ctx$benim_katilimim()
	  if (is.null(katilim) ||
		  !ortak_icerik_erisimi_var_mi(katilim$KatilimDurumu[1]) ||
		  !ortak_yetki_var_mi(katilim$Rol[1], "oku")) {
		return(NULL)
	  }

	  detay <- ortak_db_aktif_uretim_detay(oturum_id)
	  calisiyor <- !is.null(detay) && identical(as.character(detay$KilitDurumu[1]), "Çalışıyor")
	  bekleyenler <- ortak_db_kuyruk_bekleyenler(oturum_id)
	  bekleyen_var <- is.data.frame(bekleyenler) && nrow(bekleyenler) > 0L

	  if (!calisiyor && !bekleyen_var) {
		return(NULL)
	  }

    kismi_alani <- NULL
    durum_metni <- NULL

    if (calisiyor) {
      baslatan <- as.character(detay$BaslatanAdi[1] %||% "")
      durum_metni <- if (nzchar(baslatan) && !is.na(baslatan)) {
        sprintf("%s sordu · yanıt üretiliyor, tamamlanınca tüm katılımcılar görecek.", baslatan)
      } else {
        "Yanıt üretiliyor; tamamlanınca tüm katılımcılar görecek."
      }

      kismi <- as.character(detay$KismiYanit[1] %||% "")
      if (!is.na(kismi) && nzchar(kismi)) {
        kismi_alani <- div(
          class = "oo-kismi-yanit",
          `aria-label` = "Üretilmekte olan yanıtın canlı ön izlemesi",
          tags$span(class = "oo-kismi-yanit-metin", HTML(htmltools::htmlEscape(kismi))),
          tags$span(class = "oo-kismi-imlec", "▌")
        )
      }
    }

    kuyruk_alani <- NULL
    if (bekleyen_var) {
      kuyruk_alani <- div(
        class = "oo-kuyruk-listesi",
        tags$span(
          class = "oo-kuyruk-baslik",
          sprintf("Sırada %d soru bekliyor:", nrow(bekleyenler))
        ),
        tagList(lapply(seq_len(min(nrow(bekleyenler), 5L)), function(i) {
          soran <- as.character(bekleyenler$SoranAdi[i] %||% "Katılımcı")
          soru <- as.character(bekleyenler$MesajMetni[i] %||% "")
          if (nchar(soru) > 90L) {
            soru <- paste0(substr(soru, 1L, 90L), "…")
          }
          div(
            class = "oo-kuyruk-satiri",
            tags$span(class = "oo-kuyruk-sira", sprintf("%d.", i)),
            tags$span(class = "oo-kuyruk-soran", HTML(htmltools::htmlEscape(soran))),
            tags$span(class = "oo-kuyruk-soru", HTML(htmltools::htmlEscape(soru)))
          )
        }))
      )
    }

    div(
      class = "oo-uretim-durumu",
      role = "status",
      `aria-live` = "polite",
      if (calisiyor) {
        div(
          class = "oo-uretim-ust",
          icon("spinner", class = "fa-spin"),
          span(durum_metni)
        )
      } else {
        NULL
      },
      kismi_alani,
      kuyruk_alani
    )
  })

  invisible(TRUE)
}
