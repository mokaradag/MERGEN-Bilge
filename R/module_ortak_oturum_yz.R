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
#     (R/module_ortak_oturum_by_calistirma.R); normal LLM'e SESSİZ DÜŞÜŞ YOKTUR.
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

  # İyimser üretim durumu: "Yapay Zekâya Sor" tıklanır tıklanmaz, kilit alma ve
  # bağlam kurma tamamlanmadan ÖNCE, üretim durumu metni anında görünsün diye
  # tutulan yerel bayrak (ana söyleşi hızıyla eşleşir).
  iyimser_uretim <- reactiveVal(NULL)

  # Başlatan oturumun CANLI ön izlemesi: DB tur gecikmesi olmadan kısmi yanıtı
  # anında gösterir. İstek kimliğiyle sıkı kapsamlıdır (bayat çalıştırma
  # önizlemesi yeni isteğe sızamaz); diğer katılımcılar DB yoklamasıyla görür.
  canli_onizleme <- reactiveVal(NULL)
  motor$canli_onizleme <- canli_onizleme

  # Soran kullanıcının görünen adı (katılımcı listesinden; yoksa boş).
  soran_adi <- function(uid) {
    liste <- ctx$katilimcilar()
    if (is.data.frame(liste) && nrow(liste) > 0L && "KullaniciID" %in% names(liste)) {
      eslesen <- liste[liste$KullaniciID == suppressWarnings(as.integer(uid)), , drop = FALSE]
      if (nrow(eslesen) > 0L) {
        return(as.character(eslesen$KaynakAdi[1] %||% "")[1])
      }
    }
    ""
  }

  # NOT: İstek kimliği üreticisi (ortak_yz_yeni_istek_id) kuyruk DB katmanındadır.

  # Odanın etkin modeli: hızlı model seçimi > ORTAK_OTURUM_MODEL > ilk model.
  # Model seçimi (secili_model) bir reactiveVal'dir; bu yardımcı hem gözlemci
  # (reaktif bağlam) hem de ertelenmiş üretim (session$onFlushed) ve kuyruk
  # tamamlama (promise callback) yollarından çağrılır. onFlushed/promise
  # callback'leri reaktif ALAN içinde ama reaktif BAĞLAM (consumer) DIŞINDA
  # koşar; reactiveVal'ı doğrudan okumak orada "reactive context yok" hatasıyla
  # patlar ve "Yapay zekâ yanıtı başlatılamadı" olarak yüzeye çıkardı. Okuma bu
  # yüzden isolate ile sarılır (repo sözleşmesi: erteleme öncesi reaktifi yakala).
  etkin_model <- function() {
    secim <- as.character(shiny::isolate(ctx$secili_model()) %||% "")[1]
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
    # Araç seçimi + seçili belge anlık görüntüsü soru mesajının MetaJson'una
    # yazılır: üretim (doğrudan veya kalıcı kuyruk devralması) bağlamı HER
    # ZAMAN soru satırından okur. BilgeYolaç odasında yardımcı, araç planını
    # atlar ve belge kümesini BOŞ sabitler (UI ile tutarlı dürüst davranış).
    bilgi <- shiny::isolate(ctx$oturum_bilgisi())
    by_odasi <- !is.null(bilgi) &&
      identical(as.character(bilgi$KaynakTuru[1] %||% ""), "BilgeYolaç")

    arac_meta_ekstra <- oo_arac_soru_meta_hazirla(
      oturum_id, uid,
      by_odasi = by_odasi,
      arac_meta_fn = motor$arac_meta_listesi
    )

    soru_id <- ortak_db_mesaj_ekle(
      oturum_id = oturum_id,
      gonderen_kullanici_id = uid,
      mesaj_turu = "YapayZekaSorusu",
      mesaj_metni = metin,
      llm_gonderildi = TRUE,
      meta_ekstra = arac_meta_ekstra
    )

    if (is.null(soru_id)) {
      ctx$bildir("Soru gönderilemedi: bu odada yapay zekâya sorma yetkiniz yok.", tur = "error")
      return(invisible(FALSE))
    }

    # İyimser UI: soru balonu + "üretiliyor" durumu ANINDA görünsün.
    iyimser_uretim(list(ad = soran_adi(uid), ts = Sys.time()))
    ctx$yenile()

    # Kilit/kuyruk REZERVASYONU ilk flush'tan ÖNCE SENKRON yapılır. İki katılımcı
    # aynı odada neredeyse aynı anda "Yapay Zekâya Sor" derse, iki YapayZekaSorusu
    # satırı da eklenmiş ama henüz kilitlenip kuyruklanmamış olabilir. Rezervasyon
    # onFlushed'a ertelenirse geç eklenen callback kilidi önce kapabilir ve aktif
    # yanıt (ortak_yz_sohbet_gecmisi üzerinden) başka katılımcının bekleyen
    # sorusuna karşı üretilebilir. Bu nedenle yalnızca pahalı bağlam kurma + worker
    # gönderimi (motor$uret) sonraki flush'a ertelenir; kilit/kuyruk kararı burada
    # anında verilir.
    istek_id <- ortak_yz_yeni_istek_id(oturum_id)
    iyimser_uretim(NULL)

    kilit_alindi <- tryCatch(
      ortak_db_uretim_kilidi_al(
        oturum_id = oturum_id,
        baslatan_kullanici_id = uid,
        istek_id = istek_id,
        mesaj_id = soru_id
      ),
      error = function(e) NA
    )

    if (isTRUE(is.na(kilit_alindi))) {
      ctx$bildir("Yapay zekâ yanıtı başlatılamadı; lütfen tekrar deneyin.", tur = "error")
      ctx$yenile()
      return(invisible(FALSE))
    }

    if (!isTRUE(kilit_alindi)) {
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
      return(invisible(TRUE))
    }

    # Kilit alındı: arayüzü tazele, yalnızca ağır üretim işini (bağlam + worker)
    # sonraki flush'a ertele. Ertelenmiş iş başarısız olursa kilit bırakılır ki
    # oda kalıcı olarak "üretiliyor" durumunda takılı kalmasın.
    ctx$yenile()

    calisma <- function() {
      tryCatch(
        motor$uret(oturum_id, soru_id, uid, istek_id, metin),
        error = function(e) {
          ortak_db_uretim_kilidi_birak(oturum_id, istek_id, sonuc_durumu = "Hata")
          ctx$bildir("Yapay zekâ yanıtı başlatılamadı; lütfen tekrar deneyin.", tur = "error")
          ctx$yenile()
        }
      )
    }

    # Etkileşimli oturumda arayüzü önce boyayıp ağır işi sonraki flush'a ertele;
    # test/etkileşimsiz bağlamda onFlushed yoksa doğrudan çalıştır.
    if (!is.null(session) && is.function(session$onFlushed)) {
      session$onFlushed(calisma, once = TRUE)
    } else {
      calisma()
    }

    invisible(TRUE)
  }

  # --- Üretim yönlendirme: BilgeYolaç köprüsü veya normal LLM ------------------

  motor$uret <- function(oturum_id, soru_id, soran_id, istek_id,
                         metin = NULL, kuyruk_id = NULL) {
    ortak_db_olay_ekle(oturum_id, "YanıtBaşladı", soran_id)

    bilgi <- ortak_db_oturum_getir(oturum_id)
    by_odasi <- !is.null(bilgi) && identical(as.character(bilgi$KaynakTuru[1]), "BilgeYolaç")
    persona_secim <- if (!is.null(bilgi)) as.character(bilgi$SecilenPersona[1] %||% "") else ""
    persona_kimligi <- ortak_oturum_persona_kimligi(persona_secim, oturum_id)

    if (by_odasi) {
      # BilgeYolaç odası bir KODLAMA AJANI odasıdır: normal sohbet LLM'ine
      # SESSİZ DÜŞÜŞ YOKTUR; köprü yoksa da ajan çalışmış gibi yapılmaz.
      if (is.function(motor$by_calistir)) {
        basladi <- motor$by_calistir(oturum_id, soru_id, soran_id, istek_id, metin, kuyruk_id, persona_kimligi)
        if (isTRUE(basladi)) {
          return(invisible(NULL))
        }
      }

      motor$tamamla(
        oturum_id, soru_id, istek_id,
        hata_metni = ortak_by_kopru_kullanilamiyor_mesaji(),
        kuyruk_id = kuyruk_id, soran_id = soran_id,
        persona_id = persona_kimligi
      )
      return(invisible(NULL))
    }

    motor$llm_uret(oturum_id, soru_id, soran_id, istek_id, kuyruk_id, persona_kimligi)
    invisible(NULL)
  }

  # --- Tamamlama + kuyruk zinciri ---------------------------------------------

	motor$tamamla <- function(oturum_id, soru_id, istek_id,
							  yanit_metni = NULL, hata_metni = NULL,
							  kuyruk_id = NULL, soran_id = NULL,
                              persona_id = NULL) {
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
        bagli_mesaj_id = soru_id,
        persona_id = persona_id
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
    iyimser_uretim(NULL)
    canli_onizleme(NULL)
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

    istek_id <- ortak_yz_yeni_istek_id(oturum_id)
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

  motor$llm_uret <- function(oturum_id, soru_id, soran_id, istek_id, kuyruk_id = NULL, persona_kimligi = NULL) {
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

	# Soru metni + araç seçimi soru SATIRINDAN okunur (tek doğruluk kaynağı):
	# kalıcı kuyruk soruyu daha sonra devraldığında da doğru araç uygulanır.
	soru_metni <- ""
	arac_meta <- NULL
	belge_ids_snapshot <- NULL

	if (is.data.frame(mesaj_df) &&
		nrow(mesaj_df) > 0L &&
		all(c("OrtakMesajID", "MesajSirasi") %in% names(mesaj_df))) {
	  aktif_soru <- mesaj_df[
		as.character(mesaj_df$OrtakMesajID) == as.character(soru_id),
		,
		drop = FALSE
	  ]

	  if (nrow(aktif_soru) > 0L) {
		soru_metni <- as.character(aktif_soru$MesajMetni[1] %||% "")[1]
		if ("MetaJson" %in% names(aktif_soru)) {
		  if (exists("oo_arac_meta_parse", mode = "function", inherits = TRUE)) {
		    arac_meta <- oo_arac_meta_parse(aktif_soru$MetaJson[1])
		  }
		  if (exists("ortak_belge_meta_secili_idleri", mode = "function", inherits = TRUE)) {
		    belge_ids_snapshot <- ortak_belge_meta_secili_idleri(aktif_soru$MetaJson[1])
		  }
		}
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

	# Araç yürütme planı: soru satırındaki araç seçimini modele/yola çevirir.
	# Araç modülü yoksa (izole test) araçsız normal plan uygulanır.
	plan <- if (exists("oo_arac_uretim_plani", mode = "function", inherits = TRUE)) {
	  oo_arac_uretim_plani(arac_meta)
	} else {
	  list(family = "", yol = "normal", model_id = "", belge_baglami = TRUE,
	       sistem_notu = "", mcp_araclari = FALSE)
	}

	# Özetleme/Excel araçları seçili belge kümesine ihtiyaç duyar (soru anındaki
	# anlık görüntü). Belge çözümü + gerçek belge sayısıyla özetleme notu
	# yenilemesi uretim yardımcısına delege edilir (motor bakım bütçesi).
	secili_belgeler_df <- NULL
	if (exists("oo_arac_uretim_belge_hazirla", mode = "function", inherits = TRUE)) {
	  hazir <- oo_arac_uretim_belge_hazirla(plan, oturum_id, soran_id, belge_ids_snapshot)
	  plan <- hazir$plan
	  secili_belgeler_df <- hazir$belgeler_df
	}

	# Sistem mesajı katmanları (persona -> ortak belgeler -> araç notu -> sohbet
	# geçmişi) saf yardımcıya delege edilir (motor bakım bütçesi).
	persona_kimligi <- ortak_oturum_persona_kimligi(persona_kimligi, oturum_id)
	gecmis <- oo_arac_uretim_baglam_katmanla(
	  gecmis, plan, oturum_id, soran_id,
	  belge_ids_snapshot = belge_ids_snapshot,
	  persona_kimligi = persona_kimligi
	)

    sse_hazir <- exists("call_local_llm_sse_worker", mode = "function", inherits = TRUE) &&
      exists("mergen_true_streaming_worker_globals", mode = "function", inherits = TRUE) &&
      exists("tracked_future_promise", mode = "function", inherits = TRUE)

    bitir <- function(yanit_metni = NULL, hata_metni = NULL) {
      motor$tamamla(
        oturum_id, soru_id, istek_id,
        yanit_metni = yanit_metni, hata_metni = hata_metni,
        kuyruk_id = kuyruk_id, soran_id = soran_id,
        persona_id = persona_kimligi
      )
    }

    # --- Langflow araç yolu (Süreç Yönetimi / Uygulama Uzmanı) ------------------
    if (identical(plan$yol, "langflow")) {
      lf <- if (exists("oo_arac_langflow_cagrisi_hazirla", mode = "function", inherits = TRUE)) {
        oo_arac_langflow_cagrisi_hazirla(plan, soran_id, oturum_id)
      } else {
        NULL
      }

      if (is.null(lf)) {
        bitir(hata_metni = paste(
          "\U000026A0\U0000FE0F Bu araç için kurumsal Langflow yapılandırması eksik.",
          "Lütfen sistem yöneticisiyle iletişime geçin."
        ))
      } else {
        oo_arac_langflow_uret(lf, soru_metni, session$token, bitir)
      }
      return(invisible(NULL))
    }

    # --- Proje ve Kaynak Analizi araç yolu --------------------------------------
    # Tekil oturumdaki send_message boru hattıyla aynı: bağlam kurulur, sistem
    # mesajı eklenir, son kullanıcı içeriği analiz bağlamıyla değiştirilir.
    # RLS kimliği soruyu soran katılımcıya bağlanır; kuyruğu boşaltan Shiny
    # session farklı olsa bile yanıt odadaki tüm katılımcılara görünür (ortak oda iş modeli).
    sql_max_tokens <- NULL
    if (identical(plan$yol, "sql") &&
        exists("oo_arac_sql_baglami_kur", mode = "function", inherits = TRUE)) {
      sql_session <- if (exists("oo_arac_soran_session", mode = "function", inherits = TRUE)) {
        oo_arac_soran_session(
          oturum_id = oturum_id,
          soran_id = soran_id,
          current_session = ctx$parent_session %||% session,
          katilimcilar = tryCatch(ctx$katilimcilar(), error = function(e) NULL)
        )
      } else {
        ctx$parent_session %||% session
      }

      sql_baglam <- oo_arac_sql_baglami_kur(
        soru_metni, gecmis,
        sql_session,
        arac_meta
      )

      if (!is.null(sql_baglam$dogrudan_yanit)) {
        bitir(yanit_metni = sql_baglam$dogrudan_yanit)
        return(invisible(NULL))
      }

      if (nzchar(as.character(sql_baglam$sistem %||% "")[1])) {
        gecmis <- c(list(list(role = "system", content = sql_baglam$sistem)), gecmis)
      }
      if (nzchar(as.character(sql_baglam$kullanici %||% "")[1])) {
        kullanici_indeksleri <- which(vapply(
          gecmis, function(m) identical(m$role, "user"), logical(1)
        ))
        if (length(kullanici_indeksleri) > 0L) {
          gecmis[[max(kullanici_indeksleri)]]$content <- sql_baglam$kullanici
        }
      }
      sql_max_tokens <- sql_baglam$max_tokens
    }

    # Model: araç etkinse aracın modeli (Derin Düşünme çözümü dahil), değilse
    # odanın seçili modeli.
    ayarlar <- list(
      model_selection = if (nzchar(as.character(plan$model_id %||% "")[1])) {
        plan$model_id
      } else {
        etkin_model()
      },
      temperature = 0.4,
      enable_mcp_tools = FALSE,
      api_key_override = api_anahtari()
    )
    if (!is.null(sql_max_tokens)) {
      ayarlar$max_output_tokens <- sql_max_tokens
    }

    # --- Excel Analizi (MCP araç) yolu ------------------------------------------
    # Tekil oturumla aynı gerçek araç yürütmesi: call_llm_worker seçili ortak
    # Excel belgelerinden kurulan kayıt görüntüsüyle MCP araçlarını (dosya
    # analizi, kolon istatistiği, SQL, grafik üretimi) çalıştırır. Grafikler
    # yanıt metnine gömülü ```chartlab blokları olarak döner ve her katılımcının
    # oturumunda render edilir. Asenkron zincir uretim yardımcısındadır
    # (motorun bakım bütçesini korumak için; oo_arac_langflow_uret ile aynı desen).
    if (isTRUE(plan$mcp_araclari)) {
      if (exists("oo_arac_mcp_uret", mode = "function", inherits = TRUE)) {
        oo_arac_mcp_uret(
          gecmis, ayarlar, secili_belgeler_df,
          soran_id = soran_id,
          session_token = session$token,
          bitir_fn = bitir
        )
      } else {
        bitir(hata_metni = "Excel Analizi altyapısı bu ortamda yüklü değil; lütfen tekrar deneyin.")
      }
      return(invisible(NULL))
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
      # Başlatan oturum kısmi yanıtı ANINDA görür (DB tur gecikmesi olmadan);
      # istek kimliği bayat önizleme sızıntısına karşı kapsar.
      canli_onizleme(list(istek_id = isolate(uretim$istek_id), metin = kismi))
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

	  # Değişime duyarlı veri deposundan okunur (yalnızca gerçek değişimde render).
	  detay <- ctx$aktif_uretim()
	  calisiyor <- !is.null(detay) && identical(as.character(detay$KilitDurumu[1]), "Çalışıyor")
	  bekleyenler <- ctx$bekleyenler()
	  bekleyen_var <- is.data.frame(bekleyenler) && nrow(bekleyenler) > 0L

	  # İyimser durum: kilit henüz alınmadan gösterilen "üretiliyor" metni. Gerçek
	  # üretim başlayınca (calisiyor) veya 15 sn geçince yok sayılır.
	  iyimser <- iyimser_uretim()
	  iyimser_aktif <- !calisiyor && is.list(iyimser) &&
		as.numeric(difftime(Sys.time(), iyimser$ts, units = "secs")) < 15

	  if (!calisiyor && !bekleyen_var && !iyimser_aktif) {
		return(NULL)
	  }

    kismi_alani <- NULL
    durum_metni <- NULL
    durdur_alani <- NULL

    # BilgeYolaç odasında canlı ilerleme, ajan çıktısı yüzeyiyle (terminal
    # dili) gösterilir ve yetkili katılımcıya Durdur eylemi sunulur.
    bilgi <- ctx$oturum_bilgisi()
    by_odasi <- !is.null(bilgi) &&
      identical(as.character(bilgi$KaynakTuru[1] %||% ""), "BilgeYolaç")

    if (!calisiyor && iyimser_aktif) {
      durum_metni <- ortak_sunum_uretim_durum_metni(iyimser$ad, by_odasi = by_odasi)
    }

    sure_alani <- NULL

    if (calisiyor) {
      durum_metni <- ortak_sunum_uretim_durum_metni(detay$BaslatanAdi[1], by_odasi = by_odasi)

      if (by_odasi && is.function(motor$by_durdur_ui)) {
        durdur_alani <- motor$by_durdur_ui(detay)
      }

      # Geçen süre + canlı önizleme kararları saf sunum yardımcılarındadır.
      gecen_sn <- ortak_sunum_gecen_saniye(detay$BaslamaZamani[1])
      if (!is.na(gecen_sn)) {
        sure_alani <- tags$span(
          class = "oo-uretim-sure",
          `data-oo-gecen` = as.character(gecen_sn),
          `aria-label` = "Geçen süre",
          sprintf("%d sn", gecen_sn)
        )
      }

      kismi <- ortak_sunum_canli_onizleme_metni(
        detay$KismiYanit[1], canli_onizleme(), detay$IstekID[1]
      )

      kismi_alani <- oo_uretim_kismi_html(kismi, by_odasi = by_odasi)
    }

    kuyruk_alani <- oo_uretim_kuyruk_html(if (bekleyen_var) bekleyenler else NULL)

    div(
      class = "oo-uretim-durumu",
      role = "status",
      `aria-live` = "polite",
      if (calisiyor || iyimser_aktif) {
        div(
          class = "oo-uretim-ust",
          icon("spinner", class = "fa-spin"),
          span(durum_metni),
          sure_alani,
          durdur_alani
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