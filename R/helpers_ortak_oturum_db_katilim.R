# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_db_katilim.R
# Açıklama: Ortak Oturumlar katılım katmanı: katılımcı CRUD, davetler,
#           uygulama içi bildirimler, canlı durum (kalp atışı) ve davet paneli
#           için kullanıcı arama. Çekirdek altyapı (.oo_db_*) helpers_ortak_
#           oturum_db.R içindedir ve bu dosyadan ÖNCE yüklenir.
#
# Sözleşmeler:
#   * Her okuma/yazma kullanıcı-kimliği doğrulamalıdır; katılımcı olmayan
#     kullanıcı oda verisi okuyamaz (yetki sunucu tarafında da denetlenir).
#   * Davet kabulü olmadan içerik erişimi verilmez; davet yalnızca metadata
#     görünürlüğü sağlar (ortak_icerik_erisimi_var_mi sözleşmesi).
#   * E-posta bu katmandan GÖNDERİLMEZ; yalnızca taslak durumu kaydedilir.
# ==============================================================================

#' Katılımcı satırını okur (yetkilendirme ilkeli: yoksa NULL).
ortak_db_katilimci_getir <- function(oturum_id, kullanici_id, conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  if (is.na(oturum_id) || is.na(kullanici_id)) {
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
        "SELECT KatilimciID, OrtakOturumID, KullaniciID, Rol, KatilimDurumu,",
        "KullaniciGorunumDurumu, DavetEdenKullaniciID, KatilmaZamani",
        "FROM MB_OrtakOturum_Katilimcilar",
        "WHERE OrtakOturumID = ? AND KullaniciID = ?"
      ),
      params = list(oturum_id, kullanici_id)
    ),
    fallback = NULL,
    uyari = "Ortak oturum katılımcısı okunamadı:"
  )

  if (is.null(sonuc) || nrow(sonuc) == 0L) {
    return(NULL)
  }
  sonuc
}

#' Oturumun katılımcı listesi (kullanıcı görünen adlarıyla).
#' Yalnızca içerik erişimi olan (Katıldı) istekli kullanıcılara sunulmalıdır;
#' bu yetki denetimi çağıran modüldedir.
ortak_db_katilimci_listesi <- function(oturum_id, conn = NULL) {
  bos <- data.frame()

  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
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
        "SELECT k.KatilimciID, k.KullaniciID, k.Rol, k.KatilimDurumu,",
        "k.KullaniciGorunumDurumu, k.KatilmaZamani, k.SonGorulmeZamani,",
        "u.KaynakAdi, u.KullaniciAdi, u.Email",
        "FROM MB_OrtakOturum_Katilimcilar k",
        "JOIN MB_Users u ON u.UserID = k.KullaniciID",
        "WHERE k.OrtakOturumID = ?",
        "ORDER BY k.KatilmaZamani ASC, k.OlusturmaZamani ASC"
      ),
      params = list(oturum_id)
    ),
    fallback = bos,
    uyari = "Ortak oturum katılımcı listesi okunamadı:"
  )

  .oo_db_restore_visible(sonuc, c("KaynakAdi"))
}

#' Katılımcı ekler ya da mevcut satırı davet durumuna geri çeker (upsert).
ortak_db_katilimci_ekle <- function(oturum_id,
                                    kullanici_id,
                                    rol,
                                    davet_eden_kullanici_id = NULL,
                                    katilim_durumu = "DavetEdildi",
                                    conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)

  if (is.na(oturum_id) || is.na(kullanici_id) ||
      !(rol %in% ortak_oturum_rolleri()) ||
      !(katilim_durumu %in% ortak_katilim_durumlari())) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  simdi <- .oo_db_now()
  katilma_zamani <- if (identical(katilim_durumu, "Katıldı")) simdi else NA_character_

  sonuc <- .oo_db_try({
    guncellenen <- DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_OrtakOturum_Katilimcilar",
        "SET Rol = ?, KatilimDurumu = ?, KullaniciGorunumDurumu = ?,",
        "DavetEdenKullaniciID = ?, DavetZamani = ?, KatilmaZamani = ?",
        "WHERE OrtakOturumID = ? AND KullaniciID = ?"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value(rol),
        normalize_db_technical_value(katilim_durumu),
        normalize_db_technical_value(ortak_gorunum_durumlari()[1]),
        .oo_db_pos_int(davet_eden_kullanici_id),
        simdi,
        katilma_zamani,
        oturum_id,
        kullanici_id
      ))
    )

    if (guncellenen == 0L) {
      DBI::dbExecute(
        handle$conn,
        paste(
          "INSERT INTO MB_OrtakOturum_Katilimcilar",
          "(OrtakOturumID, KullaniciID, Rol, KatilimDurumu, KullaniciGorunumDurumu,",
          " DavetEdenKullaniciID, DavetZamani, KatilmaZamani, OlusturmaZamani)",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        params = normalize_db_params(list(
          oturum_id,
          kullanici_id,
          normalize_db_technical_value(rol),
          normalize_db_technical_value(katilim_durumu),
          normalize_db_technical_value(ortak_gorunum_durumlari()[1]),
          .oo_db_pos_int(davet_eden_kullanici_id),
          simdi,
          katilma_zamani,
          simdi
        ))
      )
    }
    TRUE
  },
  fallback = FALSE,
  uyari = "Ortak oturum katılımcısı eklenemedi:")

  invisible(isTRUE(sonuc))
}

#' Katılım durumunu günceller (Katıldı/Reddetti/Çıkarıldı/Ayrıldı).
ortak_db_katilim_durumu_guncelle <- function(oturum_id,
                                             kullanici_id,
                                             yeni_durum,
                                             conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)

  if (is.na(oturum_id) || is.na(kullanici_id) ||
      !(yeni_durum %in% ortak_katilim_durumlari())) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  simdi <- .oo_db_now()
  gorunum_durumu <- if (identical(yeni_durum, "Katıldı")) {
    "Görünüyor"
  } else if (yeni_durum %in% c("Ayrıldı", "Çıkarıldı", "Reddetti")) {
    "Ayrıldı"
  } else {
    NA_character_
  }

  set_katilma <- if (identical(yeni_durum, "Katıldı")) ", KatilmaZamani = ?" else ""
  set_gorunum <- if (!is.na(gorunum_durumu)) ", KullaniciGorunumDurumu = ?" else ""

  params <- list(normalize_db_technical_value(yeni_durum))
  if (nzchar(set_katilma)) {
    params[[length(params) + 1L]] <- simdi
  }
  if (nzchar(set_gorunum)) {
    params[[length(params) + 1L]] <- normalize_db_technical_value(gorunum_durumu)
  }
  params[[length(params) + 1L]] <- oturum_id
  params[[length(params) + 1L]] <- kullanici_id

  sonuc <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      paste0(
        "UPDATE MB_OrtakOturum_Katilimcilar SET KatilimDurumu = ?",
        set_katilma,
        set_gorunum,
        " WHERE OrtakOturumID = ? AND KullaniciID = ?"
      ),
      params = normalize_db_params(params)
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak oturum katılım durumu güncellenemedi:")

  invisible(isTRUE(sonuc))
}

#' Katılımcı rolünü günceller. Sahip rolü değiştirilemez (fail-closed) ve
#' işlemi yapanın rol_degistir/katilimci_yonet yetkisi işlem içinde doğrulanır.
ortak_db_katilimci_rol_guncelle <- function(oturum_id,
                                            yoneten_kullanici_id,
                                            hedef_kullanici_id,
                                            yeni_rol,
                                            conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  yoneten <- .oo_db_pos_int(yoneten_kullanici_id)
  hedef <- .oo_db_pos_int(hedef_kullanici_id)

  if (is.na(oturum_id) || is.na(yoneten) || is.na(hedef) ||
      !(yeni_rol %in% ortak_oturum_rolleri()) ||
      identical(yeni_rol, ortak_oturum_rolleri()[1])) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  sonuc <- .oo_db_try({
    yoneten_satir <- ortak_db_katilimci_getir(oturum_id, yoneten, conn = handle$conn)
    hedef_satir <- ortak_db_katilimci_getir(oturum_id, hedef, conn = handle$conn)

    if (is.null(yoneten_satir) || is.null(hedef_satir) ||
        !ortak_icerik_erisimi_var_mi(yoneten_satir$KatilimDurumu[1]) ||
        !ortak_katilimci_yonetilebilir_mi(yoneten_satir$Rol[1], hedef_satir$Rol[1])) {
      FALSE
    } else {
      DBI::dbExecute(
        handle$conn,
        "UPDATE MB_OrtakOturum_Katilimcilar SET Rol = ? WHERE OrtakOturumID = ? AND KullaniciID = ?",
        params = normalize_db_params(list(
          normalize_db_technical_value(yeni_rol),
          oturum_id,
          hedef
        ))
      ) > 0L
    }
  },
  fallback = FALSE,
  uyari = "Ortak oturum katılımcı rolü güncellenemedi:")

  invisible(isTRUE(sonuc))
}

#' Kullanıcı bazlı görünüm durumu (KullanıcıArşivledi/Görünüyor). Yalnızca o
#' kullanıcının listesini etkiler; oda herkese arşivlenmez.
ortak_db_kullanici_gorunum_guncelle <- function(oturum_id,
                                                kullanici_id,
                                                gorunum_durumu,
                                                conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)

  if (is.na(oturum_id) || is.na(kullanici_id) ||
      !(gorunum_durumu %in% ortak_gorunum_durumlari())) {
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
        "UPDATE MB_OrtakOturum_Katilimcilar SET KullaniciGorunumDurumu = ?",
        "WHERE OrtakOturumID = ? AND KullaniciID = ?"
      ),
      params = normalize_db_params(list(
        normalize_db_technical_value(gorunum_durumu),
        oturum_id,
        kullanici_id
      ))
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak oturum görünüm durumu güncellenemedi:")

  invisible(isTRUE(sonuc))
}


#' Sahipliği devreder: hedef katılımcı Sahip olur, mevcut Sahip
#' OturumYöneticisi'ne düşer (tek işlemde; her odada en az bir Sahip kalır).
ortak_db_sahiplik_devret <- function(oturum_id,
                                     mevcut_sahip_id,
                                     yeni_sahip_id,
                                     conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  mevcut_sahip_id <- .oo_db_pos_int(mevcut_sahip_id)
  yeni_sahip_id <- .oo_db_pos_int(yeni_sahip_id)

  if (is.na(oturum_id) || is.na(mevcut_sahip_id) || is.na(yeni_sahip_id) ||
      identical(mevcut_sahip_id, yeni_sahip_id)) {
    return(invisible(FALSE))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn, tx = TRUE), fallback = NULL)
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  roller <- ortak_oturum_rolleri()

  sonuc <- .oo_db_try({
    mevcut <- ortak_db_katilimci_getir(oturum_id, mevcut_sahip_id, conn = handle$conn)
    hedef <- ortak_db_katilimci_getir(oturum_id, yeni_sahip_id, conn = handle$conn)

    # Yalnızca gerçek Sahip devredebilir; hedef içerik erişimli katılımcı olmalı.
    if (is.null(mevcut) || is.null(hedef) ||
        !identical(mevcut$Rol[1], roller[1]) ||
        !ortak_icerik_erisimi_var_mi(mevcut$KatilimDurumu[1]) ||
        !ortak_icerik_erisimi_var_mi(hedef$KatilimDurumu[1])) {
      FALSE
    } else {
      DBI::dbWithTransaction(handle$conn, {
        DBI::dbExecute(
          handle$conn,
          "UPDATE MB_OrtakOturum_Katilimcilar SET Rol = ? WHERE OrtakOturumID = ? AND KullaniciID = ?",
          params = normalize_db_params(list(
            normalize_db_technical_value(roller[1]),
            oturum_id,
            yeni_sahip_id
          ))
        )
        DBI::dbExecute(
          handle$conn,
          "UPDATE MB_OrtakOturum_Katilimcilar SET Rol = ? WHERE OrtakOturumID = ? AND KullaniciID = ?",
          params = normalize_db_params(list(
            normalize_db_technical_value(roller[2]),
            oturum_id,
            mevcut_sahip_id
          ))
        )
        TRUE
      })
    }
  },
  fallback = FALSE,
  uyari = "Ortak oturum sahiplik devri başarısız:")

  invisible(isTRUE(sonuc))
}
