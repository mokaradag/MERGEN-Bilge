# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_db_bilge_yolac.R
# Açıklama: Ortak Bilge Yolaç DB katmanı: ortak oturuma 1:1 bağlı çalışma alanı
#           oturum kaydı ve çalıştırma (komut + nihai yanıt + üretilen dosya
#           metadata) kalıcılığı. Çekirdek altyapı (.oo_db_*)
#           helpers_ortak_oturum_db.R içindedir ve bu dosyadan ÖNCE yüklenir.
#
# Sözleşmeler:
#   * Gizli değer veya ikili dosya içeriği DB'ye yazılmaz; yalnızca metadata.
#   * Çalıştırma sırası (CalistirmaSirasi) yarış-korumalı artar.
#   * Bu dosya helpers_ortak_oturum_db_mesajlar.R'den ayrılmıştır (maintainability
#     ratchet): mesaj/kilit katmanı ile Bilge Yolaç oturum/çalıştırma katmanı
#     ayrı sorumluluklardır.
# ==============================================================================

#' Ortak Bilge Yolaç oturum kaydı oluşturur (ortak oturuma 1:1 bağlı).
ortak_db_by_oturum_olustur <- function(ortak_oturum_id,
                                       calisma_dizini = NULL,
                                       model = NULL,
                                       karakter = NULL,
                                       conn = NULL) {
  ortak_oturum_id <- .oo_db_pos_int(ortak_oturum_id)
  if (is.na(ortak_oturum_id)) {
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  .oo_db_try({
    .oo_db_insert_returning_id(
      conn = handle$conn,
      insert_sql_tsql = paste(
        "INSERT INTO MB_OrtakBilgeYolac_Oturumlar",
        "(OrtakOturumID, OrtakCalismaDizini, Model, Karakter, OturumDurumu, OlusturmaZamani)",
        "OUTPUT INSERTED.OrtakBilgeYolacOturumID AS id",
        "VALUES (?, ?, ?, ?, ?, ?)"
      ),
      insert_sql_plain = paste(
        "INSERT INTO MB_OrtakBilgeYolac_Oturumlar",
        "(OrtakOturumID, OrtakCalismaDizini, Model, Karakter, OturumDurumu, OlusturmaZamani)",
        "VALUES (?, ?, ?, ?, ?, ?)"
      ),
      id_column = "OrtakBilgeYolacOturumID",
      params = normalize_db_params(list(
        ortak_oturum_id,
        normalize_db_technical_value(as.character(calisma_dizini %||% NA_character_)[1]),
        normalize_db_technical_value(as.character(model %||% NA_character_)[1]),
        normalize_db_technical_value(as.character(karakter %||% NA_character_)[1]),
        normalize_db_technical_value("Aktif"),
        .oo_db_now()
      ))
    )
  },
  fallback = NULL,
  uyari = "Ortak Bilge Yolaç oturumu oluşturulamadı:")
}

#' Ortak oturuma bağlı Bilge Yolaç oturum kaydını okur.
ortak_db_by_oturum_getir <- function(ortak_oturum_id, conn = NULL) {
  ortak_oturum_id <- .oo_db_pos_int(ortak_oturum_id)
  if (is.na(ortak_oturum_id)) {
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
        "SELECT OrtakBilgeYolacOturumID, OrtakOturumID, OrtakCalismaDizini,",
        "Model, Karakter, ClaudeCliSessionID, OturumDurumu, SonCalistirmaZamani",
        "FROM MB_OrtakBilgeYolac_Oturumlar WHERE OrtakOturumID = ?"
      ),
      params = list(ortak_oturum_id)
    ),
    fallback = NULL
  )

  if (is.null(sonuc) || nrow(sonuc) == 0L) {
    return(NULL)
  }
  sonuc
}

#' Ortak Bilge Yolaç oturum metadata'sını günceller (model / çalışma dizini /
#' CLI oturum kimliği). Yalnızca verilen alanlar güncellenir; NULL alanlara
#' dokunulmaz. Gizli değer yazılmaz.
ortak_db_by_oturum_guncelle <- function(ortak_oturum_id,
                                        model = NULL,
                                        calisma_dizini = NULL,
                                        cli_session_id = NULL,
                                        conn = NULL) {
  ortak_oturum_id <- .oo_db_pos_int(ortak_oturum_id)
  if (is.na(ortak_oturum_id)) {
    return(invisible(FALSE))
  }

  atamalar <- character(0)
  params <- list()

  if (!is.null(model)) {
    atamalar <- c(atamalar, "Model = ?")
    params[[length(params) + 1L]] <- normalize_db_technical_value(as.character(model)[1])
  }
  if (!is.null(calisma_dizini)) {
    atamalar <- c(atamalar, "OrtakCalismaDizini = ?")
    params[[length(params) + 1L]] <- normalize_db_technical_value(as.character(calisma_dizini)[1])
  }
  if (!is.null(cli_session_id)) {
    atamalar <- c(atamalar, "ClaudeCliSessionID = ?")
    params[[length(params) + 1L]] <- normalize_db_technical_value(as.character(cli_session_id)[1])
  }

  if (length(atamalar) == 0L) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  params[[length(params) + 1L]] <- ortak_oturum_id

  sonuc <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      paste0(
        "UPDATE MB_OrtakBilgeYolac_Oturumlar SET ",
        paste(atamalar, collapse = ", "),
        " WHERE OrtakOturumID = ?"
      ),
      params = normalize_db_params(params)
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak Bilge Yolaç oturumu güncellenemedi:")

  invisible(isTRUE(sonuc))
}

#' Ortak Bilge Yolaç çalıştırması kaydeder (komut + nihai yanıt + metadata).
#' Gizli değer veya ikili dosya içeriği yazılmaz.
ortak_db_by_calistirma_kaydet <- function(ortak_by_oturum_id,
                                          komutu_veren_kullanici_id,
                                          komut,
                                          nihai_yanit = NULL,
                                          durum = "Tamamlandı",
                                          uretilen_dosyalar_json = NULL,
                                          sure_saniye = NULL,
                                          conn = NULL) {
  ortak_by_oturum_id <- .oo_db_pos_int(ortak_by_oturum_id)
  komutu_veren <- .oo_db_pos_int(komutu_veren_kullanici_id)

  if (is.na(ortak_by_oturum_id) || is.na(komutu_veren) ||
      !nzchar(as.character(komut %||% "")[1]) ||
      !(durum %in% c("Çalışıyor", "Tamamlandı", "Başarısız", "Durduruldu"))) {
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  .oo_db_try({
    DBI::dbWithTransaction(handle$conn, {
      sira_res <- DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT COALESCE(MAX(CalistirmaSirasi), 0) + 1 AS sonraki",
          "FROM MB_OrtakBilgeYolac_Calistirmalar WHERE OrtakBilgeYolacOturumID = ?"
        ),
        params = list(ortak_by_oturum_id)
      )

      calistirma_id <- .oo_db_insert_returning_id(
        conn = handle$conn,
        insert_sql_tsql = paste(
          "INSERT INTO MB_OrtakBilgeYolac_Calistirmalar",
          "(OrtakBilgeYolacOturumID, KomutuVerenKullaniciID, Komut, NihaiYanit,",
          " Durum, UretilenDosyalarJson, CalistirmaSirasi, SureSaniye, OlusturmaZamani)",
          "OUTPUT INSERTED.OrtakCalistirmaID AS id",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        insert_sql_plain = paste(
          "INSERT INTO MB_OrtakBilgeYolac_Calistirmalar",
          "(OrtakBilgeYolacOturumID, KomutuVerenKullaniciID, Komut, NihaiYanit,",
          " Durum, UretilenDosyalarJson, CalistirmaSirasi, SureSaniye, OlusturmaZamani)",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        id_column = "OrtakCalistirmaID",
        params = normalize_db_params(list(
          ortak_by_oturum_id,
          komutu_veren,
          normalize_db_visible_value(as.character(komut)[1]),
          normalize_db_visible_value(as.character(nihai_yanit %||% NA_character_)[1]),
          normalize_db_technical_value(durum),
          normalize_db_technical_value(as.character(uretilen_dosyalar_json %||% NA_character_)[1]),
          as.integer(sira_res$sonraki[1]),
          suppressWarnings(as.numeric(sure_saniye %||% NA_real_)[1]),
          .oo_db_now()
        ))
      )

      DBI::dbExecute(
        handle$conn,
        "UPDATE MB_OrtakBilgeYolac_Oturumlar SET SonCalistirmaZamani = ? WHERE OrtakBilgeYolacOturumID = ?",
        params = normalize_db_params(list(.oo_db_now(), ortak_by_oturum_id))
      )

      calistirma_id
    })
  },
  fallback = NULL,
  uyari = "Ortak Bilge Yolaç çalıştırması kaydedilemedi:")
}

#' Ortak Bilge Yolaç çalıştırma listesi (zaman çizelgesi görünümü).
ortak_db_by_calistirmalar <- function(ortak_by_oturum_id, conn = NULL) {
  bos <- data.frame()

  ortak_by_oturum_id <- .oo_db_pos_int(ortak_by_oturum_id)
  if (is.na(ortak_by_oturum_id)) {
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
        "SELECT c.OrtakCalistirmaID, c.KomutuVerenKullaniciID, c.Komut,",
        "c.NihaiYanit, c.Durum, c.UretilenDosyalarJson, c.CalistirmaSirasi,",
        "c.SureSaniye, c.OlusturmaZamani, u.KaynakAdi AS KomutuVerenAdi",
        "FROM MB_OrtakBilgeYolac_Calistirmalar c",
        "LEFT JOIN MB_Users u ON u.UserID = c.KomutuVerenKullaniciID",
        "WHERE c.OrtakBilgeYolacOturumID = ?",
        "ORDER BY c.CalistirmaSirasi ASC"
      ),
      params = list(ortak_by_oturum_id)
    ),
    fallback = bos,
    uyari = "Ortak Bilge Yolaç çalıştırmaları okunamadı:"
  )

  .oo_db_restore_visible(sonuc, c("Komut", "NihaiYanit", "KomutuVerenAdi"))
}
