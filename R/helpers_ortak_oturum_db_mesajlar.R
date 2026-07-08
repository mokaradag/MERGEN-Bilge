# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_db_mesajlar.R
# Açıklama: Ortak Oturumlar mesaj katmanı: oda içi yazışma / yapay zekâ soru
#           ve yanıtlarının kalıcılığı, oda başına TEK aktif üretim kilidi,
#           oturum olay günlüğü ve ortak Bilge Yolaç oturum/çalıştırma kaydı.
#           Çekirdek altyapı (.oo_db_*) helpers_ortak_oturum_db.R içindedir.
#
# Sözleşmeler:
#   * OdaMesajı ASLA LLM tetiklemez; tek LLM tetikleyici yol YapayZekaSorusu'dur
#     (ortak_mesaj_yonlendirme_plani sözleşmesi). Bu katman yalnızca kalıcılık
#     ve kilit yönetir; LLM çağrısının kendisi modül tarafındadır.
#   * MesajSirasi üretimde UPDLOCK/HOLDLOCK ile yarışsız artar (MB_Messages
#     MessageOrder sözleşmesiyle aynı desen); SQLite dalı yalnızca test içindir.
#   * Yazma yetkisi sunucu tarafında da doğrulanır: katılımcı değilse veya rol
#     izin vermiyorsa kayıt reddedilir (fail-closed).
# ==============================================================================

# Bir sonraki mesaj sırasını yarış-korumalı okur (işlem içinde çağrılır).
.oo_db_sonraki_mesaj_sirasi <- function(conn, oturum_id) {
  if (.oo_db_is_sqlite(conn)) {
    res <- DBI::dbGetQuery(
      conn,
      "SELECT COALESCE(MAX(MesajSirasi), 0) + 1 AS sonraki FROM MB_OrtakOturum_Mesajlar WHERE OrtakOturumID = ?",
      params = list(oturum_id)
    )
  } else {
    res <- DBI::dbGetQuery(
      conn,
      paste(
        "SELECT ISNULL(MAX(MesajSirasi), 0) + 1 AS sonraki",
        "FROM MB_OrtakOturum_Mesajlar WITH (UPDLOCK, HOLDLOCK)",
        "WHERE OrtakOturumID = ?"
      ),
      params = list(oturum_id)
    )
  }

  as.integer(res$sonraki[1])
}

#' Ortak oturuma mesaj ekler (oda mesajı / YZ sorusu / YZ yanıtı / sistem).
#' Hedef, saf yönlendirme planından türetilir; çağıranın hedef seçmesine izin
#' verilmez. Kullanıcı kaynaklı türlerde rol yetkisi zorunludur.
#'
#' @return Mesaj kimliği (integer) veya reddedildiğinde/başarısızlıkta NULL.
ortak_db_mesaj_ekle <- function(oturum_id,
                                gonderen_kullanici_id,
                                mesaj_turu,
                                mesaj_metni,
                                bagli_mesaj_id = NULL,
                                llm_gonderildi = FALSE,
                                olusturma_zamani = NULL,
                                persona_id = NULL,
                                conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(NULL)
  }

  plan <- ortak_mesaj_yonlendirme_plani(mesaj_turu)
  if (!isTRUE(plan$gecerli)) {
    .oo_db_log_warn("Geçersiz ortak mesaj türü reddedildi:", mesaj_turu)
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  gonderen <- .oo_db_pos_int(gonderen_kullanici_id)
  kullanici_kaynakli <- mesaj_turu %in% c("OdaMesajı", "YapayZekaSorusu")

  if (isTRUE(kullanici_kaynakli) && !.oo_db_oturum_aktif_mi(handle$conn, oturum_id)) {
    .oo_db_log_warn("Aktif olmayan ortak oturuma kullanıcı mesajı reddedildi. Oturum:", oturum_id)
    return(NULL)
  }

  .oo_db_try({
    if (kullanici_kaynakli) {
      # Fail-closed yazma yetkisi: katılımcı + içerik erişimi + rol yetkisi.
      if (is.na(gonderen)) {
        return(NULL)
      }

      katilimci <- ortak_db_katilimci_getir(oturum_id, gonderen, conn = handle$conn)
      gereken_yetki <- if (identical(mesaj_turu, "YapayZekaSorusu")) "yapay_zeka_sor" else "oda_yaz"

      if (is.null(katilimci) ||
          !ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) ||
          !ortak_yetki_var_mi(katilimci$Rol[1], gereken_yetki)) {
        .oo_db_log_warn("Ortak oturum mesajı yetki nedeniyle reddedildi. Oturum:", oturum_id)
        return(NULL)
      }
    }

    # Geçmiş kopyalama akışı orijinal zaman damgasını koruyabilir; geçersiz/boş
    # değer şimdiki zamana düşer.
    kayit_zamani <- as.character(olusturma_zamani %||% NA_character_)[1]
    if (is.na(kayit_zamani) || !nzchar(kayit_zamani)) {
      kayit_zamani <- .oo_db_now()
    }

    DBI::dbWithTransaction(handle$conn, {
      sira <- .oo_db_sonraki_mesaj_sirasi(handle$conn, oturum_id)

      meta_json <- NULL
      persona_kimligi <- tolower(trimws(as.character(persona_id %||% "")[1]))
      if (identical(mesaj_turu, "YapayZekaYanıtı") &&
          persona_kimligi %in% c("emre", "selin", "deniz", "can", "ipek")) {
        meta_json <- jsonlite::toJSON(
          list(persona_id = persona_kimligi),
          auto_unbox = TRUE, null = "null"
        )
      }

      mesaj_id <- .oo_db_insert_returning_id(
        conn = handle$conn,
        insert_sql_tsql = paste(
          "INSERT INTO MB_OrtakOturum_Mesajlar",
          "(OrtakOturumID, GonderenKullaniciID, MesajTuru, Hedef, MesajMetni,",
          " BagliMesajID, MesajSirasi, LLMGonderildiMi, OlusturmaZamani, MetaJson)",
          "OUTPUT INSERTED.OrtakMesajID AS id",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        insert_sql_plain = paste(
          "INSERT INTO MB_OrtakOturum_Mesajlar",
          "(OrtakOturumID, GonderenKullaniciID, MesajTuru, Hedef, MesajMetni,",
          " BagliMesajID, MesajSirasi, LLMGonderildiMi, OlusturmaZamani, MetaJson)",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        id_column = "OrtakMesajID",
        params = normalize_db_params(list(
          oturum_id,
          gonderen,
          normalize_db_technical_value(mesaj_turu),
          normalize_db_technical_value(plan$hedef),
          normalize_db_visible_value(as.character(mesaj_metni %||% NA_character_)[1]),
          .oo_db_pos_int(bagli_mesaj_id),
          sira,
          as.integer(isTRUE(llm_gonderildi)),
          kayit_zamani,
          normalize_db_technical_value(as.character(meta_json %||% NA_character_)[1])
        ))
      )

      .oo_db_oturum_dokun(handle$conn, oturum_id)

      mesaj_id
    })
  },
  fallback = NULL,
  uyari = "Ortak oturum mesajı kaydedilemedi:")
}

#' Oturum mesajlarını okur. İçerik erişimi olmayan kullanıcıya boş döner
#' (fail-closed okuma sınırı).
ortak_db_mesajlari_getir <- function(oturum_id,
                                     kullanici_id,
                                     limit = 500L,
                                     conn = NULL) {
  bos <- data.frame()

  oturum_id <- .oo_db_pos_int(oturum_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  if (is.na(oturum_id) || is.na(kullanici_id)) {
    return(bos)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try({
    katilimci <- ortak_db_katilimci_getir(oturum_id, kullanici_id, conn = handle$conn)

    if (is.null(katilimci) ||
        !ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) ||
        !ortak_yetki_var_mi(katilimci$Rol[1], "oku")) {
      bos
    } else {
      df <- DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT m.OrtakMesajID, m.GonderenKullaniciID, m.MesajTuru, m.Hedef,",
          "m.MesajMetni, m.BagliMesajID, m.MesajSirasi, m.LLMGonderildiMi,",
          "m.OlusturmaZamani, m.MetaJson, u.KaynakAdi AS GonderenAdi,",
          "u.Sicil AS GonderenSicil",
          "FROM MB_OrtakOturum_Mesajlar m",
          "LEFT JOIN MB_Users u ON u.UserID = m.GonderenKullaniciID",
          "WHERE m.OrtakOturumID = ?",
          "ORDER BY m.MesajSirasi ASC"
        ),
        params = list(oturum_id)
      )

      limit <- suppressWarnings(as.integer(limit)[1])
      if (!is.na(limit) && limit > 0L && nrow(df) > limit) {
        df <- df[seq(nrow(df) - limit + 1L, nrow(df)), , drop = FALSE]
      }

      df
    }
  },
  fallback = bos,
  uyari = "Ortak oturum mesajları okunamadı:")

  .oo_db_restore_visible(sonuc, c("MesajMetni", "GonderenAdi"))
}

#' Oda başına TEK aktif üretim kilidini almaya çalışır.
#'
#' Bayat kilit koruması: Çalışıyor görünen kilit, BaslamaZamani üzerinden
#' bayat_dakika süresini aştıysa terk edilmiş sayılır ve devralınır (üretimi
#' başlatan oturum çökmüş/kapanmış olabilir; oda süresiz kilitli kalmamalı).
#'
#' @return TRUE kilit alındıysa; FALSE başka bir üretim sürüyorsa/hatada.
ortak_db_uretim_kilidi_al <- function(oturum_id,
                                      baslatan_kullanici_id,
                                      istek_id,
                                      mesaj_id = NULL,
                                      bayat_dakika = 15L,
                                      conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  baslatan <- .oo_db_pos_int(baslatan_kullanici_id)
  istek_id <- as.character(istek_id %||% "")[1]

  if (is.na(oturum_id) || is.na(baslatan) || !nzchar(istek_id)) {
    return(FALSE)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(FALSE)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  if (!.oo_db_oturum_aktif_mi(handle$conn, oturum_id)) {
    .oo_db_log_warn("Aktif olmayan ortak oturumda üretim kilidi reddedildi. Oturum:", oturum_id)
    return(FALSE)
  }

  katilimci <- ortak_db_katilimci_getir(oturum_id, baslatan, conn = handle$conn)
  if (is.null(katilimci) ||
      !ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) ||
      !ortak_yetki_var_mi(katilimci$Rol[1], "yapay_zeka_sor")) {
    .oo_db_log_warn("Ortak oturum üretim kilidi yetki nedeniyle reddedildi. Oturum:", oturum_id)
    return(FALSE)
  }

  .oo_db_try({
    DBI::dbWithTransaction(handle$conn, {
      aktif_sql <- if (.oo_db_is_sqlite(handle$conn)) {
        "SELECT KilitDurumu, BaslamaZamani FROM MB_OrtakOturum_AktifUretimler WHERE OrtakOturumID = ?"
      } else {
        paste(
          "SELECT KilitDurumu, BaslamaZamani",
          "FROM MB_OrtakOturum_AktifUretimler WITH (UPDLOCK, HOLDLOCK)",
          "WHERE OrtakOturumID = ?"
        )
      }

      aktif <- DBI::dbGetQuery(
        handle$conn,
        aktif_sql,
        params = normalize_db_params(list(oturum_id))
      )

      calisiyor <- nrow(aktif) > 0L && identical(aktif$KilitDurumu[1], "Çalışıyor")

      if (calisiyor) {
        # Bayat kilit denetimi: başlama zamanı eşiği aştıysa devralınır.
        baslama <- suppressWarnings(as.POSIXct(
          as.character(aktif$BaslamaZamani[1]), tz = "UTC"
        ))
        yas_dakika <- if (length(baslama) == 1L && !is.na(baslama)) {
          as.numeric(difftime(Sys.time(), baslama, units = "mins"))
        } else {
          Inf
        }
        if (!is.na(yas_dakika) && yas_dakika >= as.numeric(bayat_dakika)) {
          .oo_db_log_warn("Bayat ortak üretim kilidi devralındı. Oturum:", oturum_id)
          calisiyor <- FALSE
        }
      }

      if (calisiyor) {
        # Başka bir katılımcının yanıt üretimi sürüyor.
        FALSE
      } else {
        if (nrow(aktif) > 0L) {
          # Tamamlanmış/iptal edilmiş eski kilit satırı işlem kilidi altında yeniden kullanılır.
			simdi <- .oo_db_now()
			ortak_mesaj_id <- .oo_db_pos_int(mesaj_id)

			tryCatch(
			  DBI::dbExecute(
				handle$conn,
				paste(
				  "UPDATE MB_OrtakOturum_AktifUretimler SET BaslatanKullaniciID = ?,",
				  "OrtakMesajID = ?, IstekID = ?, KilitDurumu = ?, BaslamaZamani = ?,",
				  "GuncellemeZamani = ?, KismiYanit = NULL WHERE OrtakOturumID = ?"
				),
				params = normalize_db_params(list(
				  baslatan,
				  ortak_mesaj_id,
				  normalize_db_technical_value(istek_id),
				  normalize_db_technical_value("Çalışıyor"),
				  simdi,
				  simdi,
				  oturum_id
				))
			  ),
			  error = function(e) {
				DBI::dbExecute(
				  handle$conn,
				  paste(
					"UPDATE MB_OrtakOturum_AktifUretimler SET BaslatanKullaniciID = ?,",
					"OrtakMesajID = ?, IstekID = ?, KilitDurumu = ?, BaslamaZamani = ?,",
					"GuncellemeZamani = ? WHERE OrtakOturumID = ?"
				  ),
				  params = normalize_db_params(list(
					baslatan,
					ortak_mesaj_id,
					normalize_db_technical_value(istek_id),
					normalize_db_technical_value("Çalışıyor"),
					simdi,
					simdi,
					oturum_id
				  ))
				)
			  }
			)
        } else {
          DBI::dbExecute(
            handle$conn,
            paste(
              "INSERT INTO MB_OrtakOturum_AktifUretimler",
              "(OrtakOturumID, BaslatanKullaniciID, OrtakMesajID, IstekID,",
              " KilitDurumu, BaslamaZamani)",
              "VALUES (?, ?, ?, ?, ?, ?)"
            ),
            params = normalize_db_params(list(
              oturum_id,
              baslatan,
              .oo_db_pos_int(mesaj_id),
              normalize_db_technical_value(istek_id),
              normalize_db_technical_value("Çalışıyor"),
              .oo_db_now()
            ))
          )
        }
        TRUE
      }
    })
  },
  fallback = FALSE,
  uyari = "Ortak oturum üretim kilidi alınamadı:")
}

#' Alınmış aktif üretim kilidini, sonradan oluşturulan soru mesajına bağlar.
#' Kilit yalnızca aynı IstekID hâlâ Çalışıyor ise güncellenir.
ortak_db_uretim_kilidi_mesaj_bagla <- function(oturum_id,
                                               istek_id,
                                               mesaj_id,
                                               conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  mesaj_id <- .oo_db_pos_int(mesaj_id)
  istek_id <- as.character(istek_id %||% "")[1]

  if (is.na(oturum_id) || is.na(mesaj_id) || !nzchar(istek_id)) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_OrtakOturum_AktifUretimler",
        "SET OrtakMesajID = ?, GuncellemeZamani = ?",
        "WHERE OrtakOturumID = ? AND IstekID = ? AND KilitDurumu = ?"
      ),
      params = normalize_db_params(list(
        mesaj_id,
        .oo_db_now(),
        oturum_id,
        normalize_db_technical_value(istek_id),
        normalize_db_technical_value("Çalışıyor")
      ))
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak oturum üretim kilidi soru mesajına bağlanamadı:")

  invisible(isTRUE(sonuc))
}

#' Üretim kilidini bırakır. Yalnızca kilidi alan istek (IstekID) bırakabilir;
#' eski/yarış halindeki bir istek yeni kilidi ezemez.
ortak_db_uretim_kilidi_birak <- function(oturum_id,
                                         istek_id,
                                         sonuc_durumu = "Tamamlandı",
                                         conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  istek_id <- as.character(istek_id %||% "")[1]

  if (is.na(oturum_id) || !nzchar(istek_id) ||
      !(sonuc_durumu %in% c("Tamamlandı", "İptalEdildi", "Hata"))) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_OrtakOturum_AktifUretimler SET KilitDurumu = ?,",
        "GuncellemeZamani = ? WHERE OrtakOturumID = ? AND IstekID = ?"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value(sonuc_durumu),
        .oo_db_now(),
        oturum_id,
        normalize_db_technical_value(istek_id)
      ))
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak oturum üretim kilidi bırakılamadı:")

  invisible(isTRUE(sonuc))
}

#' Odada süren aktif yanıt üretimi var mı?
ortak_db_aktif_uretim_var_mi <- function(oturum_id, conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(FALSE)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(FALSE)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  .oo_db_try({
    aktif <- DBI::dbGetQuery(
      handle$conn,
      "SELECT KilitDurumu FROM MB_OrtakOturum_AktifUretimler WHERE OrtakOturumID = ?",
      params = list(oturum_id)
    )
    nrow(aktif) > 0L && identical(aktif$KilitDurumu[1], "Çalışıyor")
  },
  fallback = FALSE)
}

#' Oturum olay günlüğüne kayıt ekler (denetim izi).
ortak_db_olay_ekle <- function(oturum_id,
                               olay_turu,
                               tetikleyen_kullanici_id = NULL,
                               payload_json = NULL,
                               conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id) || !nzchar(as.character(olay_turu %||% "")[1])) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      paste(
        "INSERT INTO MB_OrtakOturum_Olaylar",
        "(OrtakOturumID, OlayTuru, TetikleyenKullaniciID, PayloadJson, OlusturmaZamani)",
        "VALUES (?, ?, ?, ?, ?)"
      ),
      params = normalize_db_params(list(
        oturum_id,
        normalize_db_technical_value(as.character(olay_turu)[1]),
        .oo_db_pos_int(tetikleyen_kullanici_id),
        normalize_db_technical_value(as.character(payload_json %||% NA_character_)[1]),
        .oo_db_now()
      ))
    )
    TRUE
  },
  fallback = FALSE,
  uyari = "Ortak oturum olayı yazılamadı:")

  invisible(isTRUE(sonuc))
}

#' Mesaj veri çerçevesinden LLM sohbet geçmişi üretir (SAF yardımcı).
#' Yalnızca YapayZekaSorusu / YapayZekaYanıtı satırları bağlama girer;
#' OdaMesajı satırları LLM bağlamına dahil EDİLMEZ. Dönen rol adları
#' ("user"/"assistant") OpenAI protokol tanımlayıcılarıdır; DB'de saklanan iş
#' kuralı değerleri değildir.
ortak_yz_sohbet_gecmisi <- function(mesajlar_df, ek_baglam_metni = NULL) {
  gecmis <- list()

  if (is.character(ek_baglam_metni) && length(ek_baglam_metni) > 0L) {
    ek <- paste(ek_baglam_metni[nzchar(ek_baglam_metni)], collapse = "\n")
    if (nzchar(ek)) {
      gecmis[[length(gecmis) + 1L]] <- list(
        role = "system",
        content = paste(
          "Katılımcıların yapay zekâ sorusuna eklediği oda mesajı bağlamı:",
          ek,
          sep = "\n"
        )
      )
    }
  }

  if (!is.data.frame(mesajlar_df) || nrow(mesajlar_df) == 0L) {
    return(gecmis)
  }

  # Bağlam sıfırlama: en SON "bağlam sıfırlandı" sistem işaretinden önceki tüm
  # yapay zekâ soru/yanıt satırları bağlama alınmaz. Böylece kullanıcı odadan
  # ayrılmadan yeni bir bağlam başlatabilir; görünür transkript korunur.
  baslangic <- 1L
  if (exists("ortak_baglam_sifirlama_notu", mode = "function", inherits = TRUE)) {
    sifirlama_notu <- ortak_baglam_sifirlama_notu()
    turler <- as.character(mesajlar_df$MesajTuru)
    metinler <- as.character(mesajlar_df$MesajMetni %||% "")
    isaret <- which(turler == "SistemMesajı" & metinler == sifirlama_notu)
    if (length(isaret) > 0L) {
      baslangic <- max(isaret) + 1L
    }
  }

  for (i in seq(baslangic, nrow(mesajlar_df))) {
    if (i > nrow(mesajlar_df) || i < 1L) {
      next
    }
    tur <- as.character(mesajlar_df$MesajTuru[i])
    metin <- as.character(mesajlar_df$MesajMetni[i] %||% "")

    if (!nzchar(metin) || is.na(metin)) {
      next
    }

    if (identical(tur, "YapayZekaSorusu")) {
      gecmis[[length(gecmis) + 1L]] <- list(role = "user", content = metin)
    } else if (identical(tur, "YapayZekaYanıtı")) {
      gecmis[[length(gecmis) + 1L]] <- list(role = "assistant", content = metin)
    }
  }

  gecmis
}
