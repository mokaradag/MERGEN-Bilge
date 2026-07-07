# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_db.R
# Açıklama: Ortak Oturumlar DB çekirdeği: bağlantı/erişilebilirlik altyapısı,
#           MB_OrtakOturumlar oturum kayıtları ve kullanıcı bazlı liste okuma.
#           Katılımcı/davet/bildirim/canlı durum katmanı
#           R/helpers_ortak_oturum_db_katilim.R, mesaj/kilit/olay katmanı
#           R/helpers_ortak_oturum_db_mesajlar.R içindedir.
#
# Sözleşmeler:
#   * Kişisel MB_Chats / MB_Messages / MB_ClaudeCode_* tablolarına YAZMAZ.
#   * Tablolar henüz kurulmamışsa (aşamalı devreye alma) tüm fonksiyonlar
#     güvenli boş/NULL/FALSE döner; uygulama çökmez.
#   * Yalnızca parametreli SQL; kullanıcıya görünen metin
#     normalize_db_visible_value(), Türkçe iş kuralı sabitleri (enum)
#     normalize_db_technical_value() üzerinden bağlanır.
#   * Testler gerçek SQLite bağlantısı enjekte edebilir; üretim yolu T-SQL
#     (OUTPUT INSERTED) kalır. SQLite dalı YALNIZCA çevrimdışı testler içindir.
#   * Kurulum betiği: docs/sql/2026-07-ortak-oturumlar.sql (uygulama açılışında
#     OTOMATİK ÇALIŞTIRILMAZ; bkz. RUNBOOK.md).
# ==============================================================================

.oo_db_state <- new.env(parent = emptyenv())

.oo_db_log_warn <- function(...) {
  msg <- paste(..., collapse = " ")
  if (exists("log_warn", mode = "function", inherits = TRUE)) {
    # logger glue çözümlemesine takılmaması için süslü parantezler temizlenir.
    log_warn(gsub("[{}]", "", msg))
  } else {
    warning(msg, call. = FALSE)
  }
  invisible(NULL)
}

# Merkezi güvenli değerlendirme: hata durumunda fallback döner ve loglar.
.oo_db_try <- function(expr, fallback = NULL, uyari = NULL) {
  tryCatch(expr, error = function(e) {
    if (!is.null(uyari)) {
      .oo_db_log_warn(uyari, conditionMessage(e))
    }
    fallback
  })
}

ortak_db_reset_availability_cache <- function() {
  .oo_db_state$available <- NULL
  .oo_db_state$checked_at <- NULL
  invisible(NULL)
}

# Bağlantı edinme: conn enjekte edilmişse sahiplik çağırandadır (release no-op).
.oo_db_acquire <- function(conn = NULL, tx = FALSE) {
  if (!is.null(conn)) {
    return(list(conn = conn, mode = "injected", info = NULL))
  }

  if (isTRUE(tx) &&
      exists("db_acquire_tx_connection", mode = "function", inherits = TRUE)) {
    conn_info <- db_acquire_tx_connection("primary")
    return(list(conn = conn_info$conn, mode = "tx", info = conn_info))
  }

  conn_info <- get_connection()
  list(conn = conn_info$conn, mode = "plain", info = conn_info)
}

.oo_db_release <- function(handle) {
  if (is.null(handle) || identical(handle$mode, "injected")) {
    return(invisible(NULL))
  }

  if (identical(handle$mode, "tx")) {
    db_release_tx_connection(handle$info)
  } else {
    release_connection(handle$info)
  }

  invisible(NULL)
}

# SQLite lehçe tespiti: yalnızca çevrimdışı testlerde TRUE olur.
.oo_db_is_sqlite <- function(conn) {
  isTRUE(inherits(conn, "SQLiteConnection")) ||
    any(grepl("sqlite", class(conn), ignore.case = TRUE))
}

.oo_db_now <- function() {
  format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

# Pozitif tam sayı normalizasyonu; geçersiz değer NA döner (fail-closed).
.oo_db_pos_int <- function(value) {
  value <- suppressWarnings(as.integer(value %||% NA_integer_)[1])
  if (is.na(value) || value <= 0L) {
    return(NA_integer_)
  }
  value
}

# Okuma sınırı: kullanıcıya görünen metin kolonlarını DB-safe Unicode escape
# belirteçlerinden geri açar (teknik kolonlara dokunmaz).
.oo_db_restore_visible <- function(df, columns) {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    return(df)
  }

  if (!exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    return(df)
  }

  for (kolon in intersect(columns, names(df))) {
    if (is.character(df[[kolon]])) {
      df[[kolon]] <- normalize_db_read_visible_value(df[[kolon]])
    }
  }

  df
}

# Oda yeni yazma/LLM/davet işlemlerine açık mı? Arşivlendi/Kapandı fail-closed.
.oo_db_oturum_aktif_mi <- function(conn, oturum_id) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(FALSE)
  }

  sonuc <- .oo_db_try(
    DBI::dbGetQuery(
      conn,
      "SELECT OturumDurumu FROM MB_OrtakOturumlar WHERE OrtakOturumID = ?",
      params = normalize_db_params(list(oturum_id))
    ),
    fallback = NULL,
    uyari = "Ortak oturum durumu doğrulanamadı:"
  )

  is.data.frame(sonuc) &&
    nrow(sonuc) == 1L &&
    identical(as.character(sonuc$OturumDurumu[1]), "Aktif")
}

# INSERT sonrası üretilen kimliği lehçeye göre okur (üretim: OUTPUT INSERTED).
.oo_db_insert_returning_id <- function(conn, insert_sql_tsql, insert_sql_plain,
                                       id_column, params) {
  if (.oo_db_is_sqlite(conn)) {
    DBI::dbExecute(conn, insert_sql_plain, params = params)
    res <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() AS id")
    return(as.integer(res$id[1]))
  }

  res <- DBI::dbGetQuery(conn, insert_sql_tsql, params = params)
  if (nrow(res) == 0L) {
    stop(sprintf("INSERT %s kimlik dondurmedi.", id_column), call. = FALSE)
  }
  as.integer(res[[1]][1])
}

#' Ortak Oturum tabloları erişilebilir mi? (TRUE kalıcı, FALSE 60 sn önbellek)
ortak_db_tablolar_hazir_mi <- function(conn = NULL, force_refresh = FALSE) {
  cached <- .oo_db_state$available

  if (!isTRUE(force_refresh) && !is.null(cached)) {
    if (isTRUE(cached)) {
      return(TRUE)
    }

    checked_at <- .oo_db_state$checked_at
    if (!is.null(checked_at) &&
        as.numeric(difftime(Sys.time(), checked_at, units = "secs")) < 60) {
      return(FALSE)
    }
  }

  handle <- .oo_db_try(
    .oo_db_acquire(conn),
    fallback = NULL,
    uyari = "Ortak Oturum tabloları için DB bağlantısı alınamadı:"
  )

  ok <- FALSE

  if (!is.null(handle)) {
    on.exit(.oo_db_release(handle), add = TRUE)

    ok <- .oo_db_try({
      gerekli_tablolar <- c(
        "MB_OrtakOturumlar",
        "MB_OrtakOturum_Katilimcilar",
        "MB_OrtakOturum_Davetler",
        "MB_Kullanici_CanliDurum",
        "MB_Bildirimler",
        "MB_OrtakOturum_Mesajlar",
        "MB_OrtakOturum_YapayZekaKuyrugu",
        "MB_OrtakOturum_AktifUretimler",
        "MB_OrtakBilgeYolac_Oturumlar",
        "MB_OrtakBilgeYolac_Calistirmalar",
        "MB_OrtakOturum_Dosyalar",
        "MB_OrtakOturum_DosyaKopyalari",
        "MB_OrtakOturum_Olaylar"
      )

      all(vapply(
        gerekli_tablolar,
        function(tablo) isTRUE(DBI::dbExistsTable(handle$conn, tablo)),
        logical(1)
      ))
    },
    fallback = FALSE,
    uyari = "Ortak Oturum tabloları kontrol edilemedi:")
  }

  .oo_db_state$available <- isTRUE(ok)
  .oo_db_state$checked_at <- Sys.time()

  isTRUE(ok)
}

#' Yeni ortak oturum oluşturur; oluşturanı Sahip rolüyle Katıldı olarak ekler.
#'
#' @return Ortak oturum kimliği (integer) veya başarısızlıkta NULL.
ortak_db_oturum_olustur <- function(kaynak_turu,
                                    baslik,
                                    olusturan_kullanici_id,
                                    paylasim_tipi = NULL,
                                    kaynak_id = NULL,
                                    conn = NULL) {
  olusturan <- .oo_db_pos_int(olusturan_kullanici_id)
  if (is.na(olusturan)) {
    return(NULL)
  }

  if (!(kaynak_turu %in% ortak_oturum_kaynak_turleri())) {
    .oo_db_log_warn("Geçersiz ortak oturum kaynak türü reddedildi:", kaynak_turu)
    return(NULL)
  }

  handle <- .oo_db_try(
    .oo_db_acquire(conn, tx = TRUE),
    fallback = NULL,
    uyari = "Ortak oturum oluşturma için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  simdi <- .oo_db_now()
  roller <- ortak_oturum_rolleri()
  durumlar <- ortak_oturum_durumlari()

  .oo_db_try({
    DBI::dbWithTransaction(handle$conn, {
      oturum_id <- .oo_db_insert_returning_id(
        conn = handle$conn,
        insert_sql_tsql = paste(
          "INSERT INTO MB_OrtakOturumlar",
          "(KaynakTuru, KaynakID, Baslik, OlusturanKullaniciID, OturumDurumu,",
          " PaylasimBaslangicTipi, SonEtkinlikZamani, OlusturmaZamani)",
          "OUTPUT INSERTED.OrtakOturumID AS id",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        insert_sql_plain = paste(
          "INSERT INTO MB_OrtakOturumlar",
          "(KaynakTuru, KaynakID, Baslik, OlusturanKullaniciID, OturumDurumu,",
          " PaylasimBaslangicTipi, SonEtkinlikZamani, OlusturmaZamani)",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        id_column = "OrtakOturumID",
        params = normalize_db_params(list(
          normalize_db_technical_value(kaynak_turu),
          .oo_db_pos_int(kaynak_id),
          normalize_db_visible_value(as.character(baslik %||% NA_character_)[1]),
          olusturan,
          normalize_db_technical_value(durumlar[1]),
          normalize_db_technical_value(as.character(paylasim_tipi %||% NA_character_)[1]),
          simdi,
          simdi
        ))
      )

      # Oluşturan kullanıcı Sahip rolüyle doğrudan Katıldı durumuna geçer.
      DBI::dbExecute(
        handle$conn,
        paste(
          "INSERT INTO MB_OrtakOturum_Katilimcilar",
          "(OrtakOturumID, KullaniciID, Rol, KatilimDurumu,",
          " KullaniciGorunumDurumu, KatilmaZamani, OlusturmaZamani)",
          "VALUES (?, ?, ?, ?, ?, ?, ?)"
        ),
        params = normalize_db_params(list(
          oturum_id,
          olusturan,
          normalize_db_technical_value(roller[1]),
          normalize_db_technical_value("Katıldı"),
          normalize_db_technical_value(ortak_gorunum_durumlari()[1]),
          simdi,
          simdi
        ))
      )

      oturum_id
    })
  },
  fallback = NULL,
  uyari = "Ortak oturum oluşturulamadı:")
}

#' Ortak oturum başlık kaydını okur (tek satır data.frame veya NULL).
ortak_db_oturum_getir <- function(oturum_id, conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT OrtakOturumID, KaynakTuru, KaynakID, Baslik,",
        "OlusturanKullaniciID, OturumDurumu, PaylasimBaslangicTipi,",
        "SonEtkinlikZamani, OlusturmaZamani",
        "FROM MB_OrtakOturumlar WHERE OrtakOturumID = ?"
      ),
      params = list(oturum_id)
    ),
    fallback = NULL,
    uyari = "Ortak oturum okunamadı:"
  )

  if (is.null(sonuc) || nrow(sonuc) == 0L) {
    return(NULL)
  }

  .oo_db_restore_visible(sonuc, c("Baslik"))
}

# Oturumun son etkinlik zamanını günceller (mesaj/çalıştırma sonrası).
.oo_db_oturum_dokun <- function(conn, oturum_id) {
  DBI::dbExecute(
    conn,
    "UPDATE MB_OrtakOturumlar SET SonEtkinlikZamani = ?, GuncellemeZamani = ? WHERE OrtakOturumID = ?",
    params = normalize_db_params(list(.oo_db_now(), .oo_db_now(), oturum_id))
  )
  invisible(NULL)
}

#' Oda düzeyi durum değişikliği (Arşivlendi/Kapandı/Aktif) — herkes için geçerlidir.
#' Yalnızca oturum_kapat yetkisi olan rol (Sahip) için işlem yapar (fail-closed).
ortak_db_oturum_durum_guncelle <- function(oturum_id,
                                           kullanici_id,
                                           yeni_durum,
                                           conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)

  if (is.na(oturum_id) || is.na(kullanici_id) ||
      !(yeni_durum %in% ortak_oturum_durumlari())) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try({
    # Yetki kontrolü işlem içinde: yalnızca oturum_kapat yetkisi olan rol.
    katilimci <- DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT Rol, KatilimDurumu FROM MB_OrtakOturum_Katilimcilar",
        "WHERE OrtakOturumID = ? AND KullaniciID = ?"
      ),
      params = list(oturum_id, kullanici_id)
    )

    if (nrow(katilimci) == 0L ||
        !ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) ||
        !ortak_yetki_var_mi(katilimci$Rol[1], "oturum_kapat")) {
      FALSE
    } else {
      DBI::dbExecute(
        handle$conn,
        "UPDATE MB_OrtakOturumlar SET OturumDurumu = ?, GuncellemeZamani = ? WHERE OrtakOturumID = ?",
        params = normalize_db_params(list(
          normalize_db_technical_value(yeni_durum),
          .oo_db_now(),
          oturum_id
        ))
      )
      TRUE
    }
  },
  fallback = FALSE,
  uyari = "Ortak oturum durumu güncellenemedi:")

  invisible(isTRUE(sonuc))
}

#' Kullanıcının ortak oturum listesi (rol + sayaçlarla).
#'
#' Görünürlük kuralı R tarafında ortak_liste_gorunur_mu() ile uygulanır:
#' kullanıcı bazlı arşiv yalnızca o kullanıcının listesini etkiler.
ortak_db_oturum_listesi <- function(kullanici_id,
                                    kaynak_turu = NULL,
                                    arsiv_gorunumu = FALSE,
                                    sadece_davetler = FALSE,
                                    conn = NULL) {
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

  sonuc <- .oo_db_try({
    sql <- paste(
      "SELECT o.OrtakOturumID, o.KaynakTuru, o.Baslik, o.OturumDurumu,",
      "o.SonEtkinlikZamani, o.OlusturmaZamani, o.OlusturanKullaniciID,",
      "k.Rol, k.KatilimDurumu, k.KullaniciGorunumDurumu,",
      "(SELECT COUNT(*) FROM MB_OrtakOturum_Katilimcilar k2",
      " WHERE k2.OrtakOturumID = o.OrtakOturumID AND k2.KatilimDurumu = ?) AS KatilimciSayisi,",
      "(SELECT COUNT(*) FROM MB_OrtakOturum_Dosyalar d",
      " WHERE d.OrtakOturumID = o.OrtakOturumID AND d.DosyaDurumu = ?) AS BelgeSayisi",
      "FROM MB_OrtakOturumlar o",
      "JOIN MB_OrtakOturum_Katilimcilar k ON k.OrtakOturumID = o.OrtakOturumID",
      "WHERE k.KullaniciID = ?",
      "ORDER BY o.SonEtkinlikZamani DESC, o.OlusturmaZamani DESC"
    )

    df <- DBI::dbGetQuery(
      handle$conn,
      sql,
      params = normalize_db_params(list(
        normalize_db_technical_value("Katıldı"),
        normalize_db_technical_value("Üretildi"),
        kullanici_id
      ))
    )

    if (nrow(df) == 0L) {
      df
    } else if (isTRUE(sadece_davetler)) {
      # Davetlerim görünümü: yalnızca bekleyen davet satırları.
      df[df$KatilimDurumu == "DavetEdildi", , drop = FALSE]
    } else {
      gorunur <- vapply(
        seq_len(nrow(df)),
        function(i) {
          df$KatilimDurumu[i] == "Katıldı" && ortak_liste_gorunur_mu(
            df$KatilimDurumu[i],
            df$KullaniciGorunumDurumu[i],
            df$OturumDurumu[i],
            arsiv_gorunumu = arsiv_gorunumu
          )
        },
        logical(1)
      )
      df <- df[gorunur, , drop = FALSE]

      if (!is.null(kaynak_turu) && nrow(df) > 0L) {
        df <- df[df$KaynakTuru == kaynak_turu, , drop = FALSE]
      }

      df
    }
  },
  fallback = bos,
  uyari = "Ortak oturum listesi okunamadı:")

  .oo_db_restore_visible(sonuc, c("Baslik"))
}
