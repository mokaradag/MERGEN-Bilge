# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_db_davet.R
# Açıklama: Ortak Oturumlar davet/bildirim/canlı durum katmanı: davet CRUD,
#           uygulama içi bildirimler, kalp atışı (heartbeat) ve davet paneli
#           kullanıcı arama. Katılımcı CRUD helpers_ortak_oturum_db_katilim.R,
#           çekirdek altyapı (.oo_db_*) helpers_ortak_oturum_db.R içindedir.
#
# Sözleşmeler:
#   * Davet kabulü olmadan içerik erişimi verilmez; davet yalnızca metadata
#     görünürlüğü sağlar (ortak_icerik_erisimi_var_mi sözleşmesi).
#   * E-posta bu katmandan GÖNDERİLMEZ; yalnızca taslak hazırlama zamanı
#     kaydedilir (ortak_db_davet_gonderim_isaretle).
#   * Bildirim gövdesine oda içeriği yazılmaz; yalnızca davet metadata'sı taşınır.
# ==============================================================================

#' Davet oluşturur: davet kaydı + katılımcı satırı (DavetEdildi) + bildirim.
#'
#' @return Davet kimliği (integer) veya NULL.
ortak_db_davet_olustur <- function(oturum_id,
                                   davet_eden_kullanici_id,
                                   davet_edilen_kullanici_id,
                                   rol = "Katılımcı",
                                   davet_yontemi = "Mergenİçi",
                                   davet_edilen_eposta = NULL,
                                   conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  davet_eden <- .oo_db_pos_int(davet_eden_kullanici_id)
  davet_edilen <- .oo_db_pos_int(davet_edilen_kullanici_id)

  # Sahip rolü davetle verilemez; sahiplik yalnızca açık sahiplik devriyle yapılır.
  davetle_verilebilir_roller <- setdiff(ortak_oturum_rolleri(), "Sahip")

  if (is.na(oturum_id) || is.na(davet_eden) || is.na(davet_edilen) ||
      !(rol %in% davetle_verilebilir_roller) ||
      !(davet_yontemi %in% ortak_davet_yontemleri())) {
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  if (!.oo_db_oturum_aktif_mi(handle$conn, oturum_id)) {
    .oo_db_log_warn("Aktif olmayan ortak oturuma davet oluşturma reddedildi:", oturum_id)
    return(NULL)
  }

  simdi <- .oo_db_now()

  .oo_db_try({
    # Yetki: davet eden, içerik erişimli ve davet_et yetkili olmalıdır.
    davet_eden_satir <- ortak_db_katilimci_getir(oturum_id, davet_eden, conn = handle$conn)
    if (is.null(davet_eden_satir) ||
        !ortak_icerik_erisimi_var_mi(davet_eden_satir$KatilimDurumu[1]) ||
        !ortak_yetki_var_mi(davet_eden_satir$Rol[1], "davet_et")) {
      return(NULL)
    }

    DBI::dbWithTransaction(handle$conn, {
      davet_id <- .oo_db_insert_returning_id(
        conn = handle$conn,
        insert_sql_tsql = paste(
          "INSERT INTO MB_OrtakOturum_Davetler",
          "(OrtakOturumID, DavetEdilenKullaniciID, DavetEdilenEposta,",
          " DavetEdenKullaniciID, Rol, DavetYontemi, DavetDurumu, OlusturmaZamani)",
          "OUTPUT INSERTED.DavetID AS id",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        insert_sql_plain = paste(
          "INSERT INTO MB_OrtakOturum_Davetler",
          "(OrtakOturumID, DavetEdilenKullaniciID, DavetEdilenEposta,",
          " DavetEdenKullaniciID, Rol, DavetYontemi, DavetDurumu, OlusturmaZamani)",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        id_column = "DavetID",
        params = normalize_db_params(list(
          oturum_id,
          davet_edilen,
          normalize_db_technical_value(as.character(davet_edilen_eposta %||% NA_character_)[1]),
          davet_eden,
          normalize_db_technical_value(rol),
          normalize_db_technical_value(davet_yontemi),
          normalize_db_technical_value(ortak_davet_durumlari()[1]),
          simdi
        ))
      )

      katilim_ok <- ortak_db_katilimci_ekle(
        oturum_id = oturum_id,
        kullanici_id = davet_edilen,
        rol = rol,
        davet_eden_kullanici_id = davet_eden,
        katilim_durumu = "DavetEdildi",
        conn = handle$conn
      )

      if (!isTRUE(katilim_ok)) {
        stop("Davet katılımcı satırı oluşturulamadı.", call. = FALSE)
      }

      davet_id
    })
  },
  fallback = NULL,
  uyari = "Ortak oturum daveti oluşturulamadı:")
}

#' Kullanıcının bekleyen davetleri (davet metadata görünümü; içerik değil).
ortak_db_davetlerim <- function(kullanici_id, conn = NULL) {
  bos <- data.frame()

  kullanici_id <- .oo_db_pos_int(kullanici_id)
  if (is.na(kullanici_id)) {
    return(bos)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT d.DavetID, d.OrtakOturumID, d.Rol, d.DavetYontemi, d.DavetDurumu,",
        "d.OlusturmaZamani, o.Baslik, o.KaynakTuru, o.OturumDurumu,",
        "u.KaynakAdi AS DavetEdenAdi,",
        "(SELECT COUNT(*) FROM MB_OrtakOturum_Katilimcilar k2",
        " WHERE k2.OrtakOturumID = d.OrtakOturumID AND k2.KatilimDurumu = ?) AS KatilimciSayisi",
        "FROM MB_OrtakOturum_Davetler d",
        "JOIN MB_OrtakOturumlar o ON o.OrtakOturumID = d.OrtakOturumID",
        "JOIN MB_Users u ON u.UserID = d.DavetEdenKullaniciID",
        "WHERE d.DavetEdilenKullaniciID = ? AND d.DavetDurumu = ?",
        "ORDER BY d.OlusturmaZamani DESC"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value("Katıldı"),
        kullanici_id,
        normalize_db_technical_value("Bekliyor")
      ))
    ),
    fallback = bos,
    uyari = "Davet listesi okunamadı:"
  )

  .oo_db_restore_visible(sonuc, c("Baslik", "DavetEdenAdi"))
}

#' Davete yanıt: kabul (Katıldı) veya red (Reddetti). Davet + katılımcı +
#' bildirim durumları tek işlemde tutarlı güncellenir.
ortak_db_davet_yanitla <- function(davet_id, kullanici_id, kabul, conn = NULL) {
  davet_id <- .oo_db_pos_int(davet_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  if (is.na(davet_id) || is.na(kullanici_id)) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  yeni_davet_durumu <- if (isTRUE(kabul)) "Katıldı" else "Reddetti"
  simdi <- .oo_db_now()

  sonuc <- .oo_db_try({
    DBI::dbWithTransaction(handle$conn, {
      davet <- DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT DavetID, OrtakOturumID, DavetEdilenKullaniciID, DavetDurumu",
          "FROM MB_OrtakOturum_Davetler WHERE DavetID = ?"
        ),
        params = list(davet_id)
      )

      # Yalnızca davetin sahibi ve yalnızca Bekliyor durumundaki davet yanıtlanır.
      if (nrow(davet) == 0L ||
          !identical(as.integer(davet$DavetEdilenKullaniciID[1]), kullanici_id) ||
          !identical(davet$DavetDurumu[1], "Bekliyor")) {
        FALSE
      } else {
        kabul_zamani <- if (isTRUE(kabul)) simdi else NA_character_

        davet_ok <- DBI::dbExecute(
          handle$conn,
          paste(
            "UPDATE MB_OrtakOturum_Davetler SET DavetDurumu = ?,",
            "SonCevapZamani = ?, KabulZamani = ? WHERE DavetID = ?"
          ),
          params = normalize_db_params(list(
            normalize_db_technical_value(yeni_davet_durumu),
            simdi,
            kabul_zamani,
            davet_id
          ))
        ) > 0L

        katilim_ok <- ortak_db_katilim_durumu_guncelle(
          oturum_id = as.integer(davet$OrtakOturumID[1]),
          kullanici_id = kullanici_id,
          yeni_durum = yeni_davet_durumu,
          conn = handle$conn
        )

        if (!isTRUE(davet_ok) || !isTRUE(katilim_ok)) {
          stop("Davet yanıtı tutarlı güncellenemedi.", call. = FALSE)
        }

        TRUE
      }
    })
  },
  fallback = FALSE,
  uyari = "Ortak oturum daveti yanıtlanamadı:")

  invisible(isTRUE(sonuc))
}

#' Davet e-posta taslağının hazırlandığını işaretler (gönderim İZLEMESİ değildir;
#' otomatik e-posta gönderimi yoktur).
ortak_db_davet_gonderim_isaretle <- function(davet_id, conn = NULL) {
  davet_id <- .oo_db_pos_int(davet_id)
  if (is.na(davet_id)) {
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
      "UPDATE MB_OrtakOturum_Davetler SET SonGonderimZamani = ? WHERE DavetID = ?",
      params = normalize_db_params(list(.oo_db_now(), davet_id))
    ) > 0L
  },
  fallback = FALSE)

  invisible(isTRUE(sonuc))
}

#' Uygulama içi bildirim ekler (davet/çağrı). Bildirim gövdesine oda içeriği
#' YAZILMAZ; yalnızca davet metadata'sı taşınır.
ortak_db_bildirim_ekle <- function(alici_kullanici_id,
                                   bildirim_turu,
                                   baslik,
                                   mesaj = NULL,
                                   gonderen_kullanici_id = NULL,
                                   ilgili_oturum_id = NULL,
                                   conn = NULL) {
  alici <- .oo_db_pos_int(alici_kullanici_id)
  if (is.na(alici) || !nzchar(as.character(baslik %||% "")[1])) {
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
        "INSERT INTO MB_Bildirimler",
        "(AliciKullaniciID, GonderenKullaniciID, BildirimTuru, Baslik, Mesaj,",
        " IlgiliOturumID, OkunduMu, Durum, OlusturmaZamani)",
        "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)"
      ),
      params = normalize_db_params(list(
        alici,
        .oo_db_pos_int(gonderen_kullanici_id),
        normalize_db_technical_value(as.character(bildirim_turu)[1]),
        normalize_db_visible_value(as.character(baslik)[1]),
        normalize_db_visible_value(as.character(mesaj %||% NA_character_)[1]),
        .oo_db_pos_int(ilgili_oturum_id),
        normalize_db_technical_value("Bekliyor"),
        .oo_db_now()
      ))
    )
    TRUE
  },
  fallback = FALSE,
  uyari = "Bildirim eklenemedi:")

  invisible(isTRUE(sonuc))
}

#' Kullanıcının okunmamış bildirimleri.
ortak_db_bildirimlerim <- function(kullanici_id, conn = NULL) {
  bos <- data.frame()

  kullanici_id <- .oo_db_pos_int(kullanici_id)
  if (is.na(kullanici_id)) {
    return(bos)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT BildirimID, GonderenKullaniciID, BildirimTuru, Baslik, Mesaj,",
        "IlgiliOturumID, Durum, OlusturmaZamani",
        "FROM MB_Bildirimler",
        "WHERE AliciKullaniciID = ? AND OkunduMu = 0",
        "ORDER BY OlusturmaZamani DESC"
      ),
      params = list(kullanici_id)
    ),
    fallback = bos,
    uyari = "Bildirimler okunamadı:"
  )

  .oo_db_restore_visible(sonuc, c("Baslik", "Mesaj"))
}

#' Bildirimi okundu olarak işaretler (yalnızca alıcı işaretleyebilir).
ortak_db_bildirim_okundu <- function(bildirim_id, kullanici_id, conn = NULL) {
  bildirim_id <- .oo_db_pos_int(bildirim_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  if (is.na(bildirim_id) || is.na(kullanici_id)) {
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
        "UPDATE MB_Bildirimler SET OkunduMu = 1, OkunmaZamani = ?",
        "WHERE BildirimID = ? AND AliciKullaniciID = ?"
      ),
      params = normalize_db_params(list(.oo_db_now(), bildirim_id, kullanici_id))
    ) > 0L
  },
  fallback = FALSE)

  invisible(isTRUE(sonuc))
}

#' Kalp atışı (heartbeat) yazar: kullanıcı+oturum anahtarı için upsert.
ortak_db_kalp_atisi <- function(kullanici_id,
                                oturum_anahtari,
                                sayfa = NULL,
                                gorulen_ortak_oturum_id = NULL,
                                conn = NULL) {
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  oturum_anahtari <- as.character(oturum_anahtari %||% "")[1]

  if (is.na(kullanici_id) || !nzchar(oturum_anahtari)) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  simdi <- .oo_db_now()
  durum <- ortak_canli_durumlar()[1]

  sonuc <- .oo_db_try({
    guncellenen <- DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_Kullanici_CanliDurum SET Sayfa = ?, SonKalpAtisiZamani = ?,",
        "Durum = ?, SonGorulenOrtakOturumID = ?",
        "WHERE KullaniciID = ? AND OturumAnahtari = ?"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value(as.character(sayfa %||% NA_character_)[1]),
        simdi,
        normalize_db_technical_value(durum),
        .oo_db_pos_int(gorulen_ortak_oturum_id),
        kullanici_id,
        normalize_db_technical_value(oturum_anahtari)
      ))
    )

    if (guncellenen == 0L) {
      DBI::dbExecute(
        handle$conn,
        paste(
          "INSERT INTO MB_Kullanici_CanliDurum",
          "(KullaniciID, OturumAnahtari, Sayfa, SonKalpAtisiZamani, Durum,",
          " SonGorulenOrtakOturumID, OlusturmaZamani)",
          "VALUES (?, ?, ?, ?, ?, ?, ?)"
        ),
        params = normalize_db_params(list(
          kullanici_id,
          normalize_db_technical_value(oturum_anahtari),
          normalize_db_technical_value(as.character(sayfa %||% NA_character_)[1]),
          simdi,
          normalize_db_technical_value(durum),
          .oo_db_pos_int(gorulen_ortak_oturum_id),
          simdi
        ))
      )
    }
    TRUE
  },
  fallback = FALSE,
  uyari = "Canlı durum kalp atışı yazılamadı:")

  invisible(isTRUE(sonuc))
}

#' Kullanıcı başına en güncel kalp atışını okur ve Türkçe canlı durumu
#' saf ortak_sunum_durumu() ile sınıflandırır. En güncel satırın
#' SonGorulenOrtakOturumID değeri de döner; böylece "bu odada çevrim içi"
#' göstergesi (yeşil nokta) üretilebilir.
ortak_db_canli_durumlar <- function(simdi = Sys.time(), conn = NULL) {
  bos <- data.frame()

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT c.KullaniciID, c.SonKalpAtisiZamani, c.SonGorulenOrtakOturumID",
        "FROM MB_Kullanici_CanliDurum c"
      )
    ),
    fallback = bos,
    uyari = "Canlı durumlar okunamadı:"
  )

  if (!is.data.frame(sonuc) || nrow(sonuc) == 0L) {
    return(bos)
  }

  # Kullanıcı başına EN GÜNCEL kalp atışı satırı (lehçe bağımsız: R tarafında).
  zamanlar <- suppressWarnings(as.POSIXct(
    as.character(sonuc$SonKalpAtisiZamani), tz = "UTC"
  ))
  sirali <- order(sonuc$KullaniciID, zamanlar, decreasing = TRUE)
  sonuc <- sonuc[sirali, , drop = FALSE]
  sonuc <- sonuc[!duplicated(sonuc$KullaniciID), , drop = FALSE]

  sonuc$CanliDurum <- vapply(
    as.character(sonuc$SonKalpAtisiZamani),
    ortak_sunum_durumu,
    character(1),
    simdi = simdi,
    USE.NAMES = FALSE
  )

  sonuc
}

#' Davet paneli için kullanıcı arama (ad/kullanıcı adı/e-posta/departman).
#' Sonuç yalnızca davet panelinde gösterilir; gizli alan içermez.
ortak_db_kullanici_arama <- function(arama = "", limit = 50L, conn = NULL) {
  bos <- data.frame()

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  arama <- trimws(as.character(arama %||% "")[1])
  desen <- paste0("%", arama, "%")

  sonuc <- .oo_db_try({
    if (nzchar(arama)) {
      DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT UserID, KullaniciAdi, KaynakAdi, Email, Departman",
          "FROM MB_Users",
          "WHERE KaynakAdi LIKE ? OR KullaniciAdi LIKE ? OR Email LIKE ? OR Departman LIKE ?",
          "ORDER BY KaynakAdi ASC"
        ),
        params = normalize_db_params(list(
          normalize_db_technical_value(desen),
          normalize_db_technical_value(desen),
          normalize_db_technical_value(desen),
          normalize_db_technical_value(desen)
        ))
      )
    } else {
      DBI::dbGetQuery(
        handle$conn,
        "SELECT UserID, KullaniciAdi, KaynakAdi, Email, Departman FROM MB_Users ORDER BY KaynakAdi ASC"
      )
    }
  },
  fallback = bos,
  uyari = "Davet paneli kullanıcı araması başarısız:")

  if (is.data.frame(sonuc) && nrow(sonuc) > 0L) {
    limit <- suppressWarnings(as.integer(limit)[1])
    if (!is.na(limit) && limit > 0L && nrow(sonuc) > limit) {
      sonuc <- sonuc[seq_len(limit), , drop = FALSE]
    }
  }

  .oo_db_restore_visible(sonuc, c("KaynakAdi", "Departman"))
}
