# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_files.R
# Açıklama: Ortak Oturum belgeleri: ortak belge kökü çözümleme, üretilen
#           dosyanın ortak oda belgesi olarak kaydı, katılımcı bazlı kopya
#           durumu ve "Kendi Dosyalarıma Kaydet" (kişisel klasöre kopyalama).
#
# Sözleşmeler:
#   * Üretilen belge ÖNCE ortak oda belgesidir; hiçbir katılımcının kişisel
#     klasörüne otomatik yazılmaz. Kopya yalnızca kullanıcının açık
#     "Kendi Dosyalarıma Kaydet" eylemiyle oluşur.
#   * Ortak belgeler yapılandırılmış MERGEN dosya kökü altındaki
#     ortak_oturumlar/oturum_<id>/ dizininde saklanır; kök dışına yazma ve
#     path traversal reddedilir (fail-closed).
#   * Kişisel kopya, mevcut Dosya Yönetimi sözleşmesiyle kaydedilir
#     (global_register_file), böylece dosya kullanıcının normal
#     "Dosyalarım" listesinde görünür.
#   * DB'ye dosya içeriği yazılmaz; yalnızca metadata saklanır.
# ==============================================================================

# Ortak belge kök dizini (MERGEN dosya kökü altında). Yoksa oluşturur.
ortak_oturum_dosya_koku <- function(oturum_id) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(NULL)
  }

  files_root <- getOption("mergen.files_root", NULL)
  if (is.null(files_root) || !nzchar(as.character(files_root)[1])) {
    files_root <- Sys.getenv("MERGEN_FILES_ROOT", unset = "")
  }
  if (!nzchar(as.character(files_root)[1])) {
    return(NULL)
  }

  kok <- file.path(as.character(files_root)[1], "ortak_oturumlar", sprintf("oturum_%d", oturum_id))
  dir.create(kok, showWarnings = FALSE, recursive = TRUE)

  if (!dir.exists(kok)) {
    return(NULL)
  }
  kok
}

# Yol, ortak belge kökünün İÇİNDE mi? Traversal/dış yol reddedilir.
.oo_dosya_kok_icinde_mi <- function(yol, kok) {
  if (is.null(yol) || is.null(kok) || !nzchar(yol) || !nzchar(kok)) {
    return(FALSE)
  }

  yol_norm <- tryCatch(
    normalizePath(yol, winslash = "/", mustWork = FALSE),
    error = function(e) ""
  )
  kok_norm <- tryCatch(
    normalizePath(kok, winslash = "/", mustWork = FALSE),
    error = function(e) ""
  )

  if (!nzchar(yol_norm) || !nzchar(kok_norm)) {
    return(FALSE)
  }

  startsWith(paste0(yol_norm, "/"), paste0(kok_norm, "/"))
}

# Güvenli hedef dosya adı: yol ayracı/traversal temizlenir, çakışmada sayaç eklenir.
.oo_dosya_hedef_adi <- function(hedef_dizin, dosya_adi) {
  ad <- basename(as.character(dosya_adi %||% "")[1])
  ad <- gsub("[\\\\/]+", "_", ad)
  if (!nzchar(ad) || ad %in% c(".", "..")) {
    ad <- sprintf("ortak_belge_%s.dat", format(Sys.time(), "%Y%m%d%H%M%S"))
  }

  hedef <- file.path(hedef_dizin, ad)
  sayac <- 1L

  while (file.exists(hedef) && sayac < 100L) {
    govde <- tools::file_path_sans_ext(ad)
    uzanti <- tools::file_ext(ad)
    yeni_ad <- if (nzchar(uzanti)) {
      sprintf("%s_(%d).%s", govde, sayac, uzanti)
    } else {
      sprintf("%s_(%d)", govde, sayac)
    }
    hedef <- file.path(hedef_dizin, yeni_ad)
    sayac <- sayac + 1L
  }

  hedef
}

#' Üretilen dosyayı ortak oda belgesi olarak kaydeder: fiziksel dosyayı ortak
#' belge köküne kopyalar ve metadata satırı ekler.
#'
#' @return Ortak dosya kimliği (integer) veya NULL.
ortak_db_dosya_kaydet <- function(oturum_id,
                                  kaynak_yol,
                                  dosya_adi = NULL,
                                  ureten_kullanici_id = NULL,
                                  ortak_calistirma_id = NULL,
                                  conn = NULL) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  kaynak_yol <- as.character(kaynak_yol %||% "")[1]

  if (is.na(oturum_id) || !nzchar(kaynak_yol) || !file.exists(kaynak_yol)) {
    return(NULL)
  }

  kok <- ortak_oturum_dosya_koku(oturum_id)
  if (is.null(kok)) {
    return(NULL)
  }

  ad <- as.character(dosya_adi %||% basename(kaynak_yol))[1]
  hedef <- .oo_dosya_hedef_adi(kok, ad)

  if (!.oo_dosya_kok_icinde_mi(hedef, kok)) {
    .oo_db_log_warn("Ortak belge hedefi kök dışında; kayıt reddedildi.")
    return(NULL)
  }

  kopyalandi <- .oo_db_try(
    file.copy(kaynak_yol, hedef, overwrite = FALSE),
    fallback = FALSE,
    uyari = "Ortak belge fiziksel kopyası başarısız:"
  )
  if (!isTRUE(kopyalandi)) {
    return(NULL)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  boyut <- suppressWarnings(as.numeric(file.info(hedef)$size[1]))
  uzanti <- tolower(tools::file_ext(hedef))

  .oo_db_try({
    .oo_db_insert_returning_id(
      conn = handle$conn,
      insert_sql_tsql = paste(
        "INSERT INTO MB_OrtakOturum_Dosyalar",
        "(OrtakOturumID, OrtakCalistirmaID, UretenKullaniciID, DosyaAdi,",
        " DosyaYolu, DosyaTuru, DosyaBoyutu, DosyaDurumu, DosyaSahipligi, OlusturmaZamani)",
        "OUTPUT INSERTED.OrtakDosyaID AS id",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      insert_sql_plain = paste(
        "INSERT INTO MB_OrtakOturum_Dosyalar",
        "(OrtakOturumID, OrtakCalistirmaID, UretenKullaniciID, DosyaAdi,",
        " DosyaYolu, DosyaTuru, DosyaBoyutu, DosyaDurumu, DosyaSahipligi, OlusturmaZamani)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      id_column = "OrtakDosyaID",
      params = normalize_db_params(list(
        oturum_id,
        .oo_db_pos_int(ortak_calistirma_id),
        .oo_db_pos_int(ureten_kullanici_id),
        normalize_db_visible_value(basename(hedef)),
        normalize_db_technical_value(hedef),
        normalize_db_technical_value(uzanti),
        boyut,
        normalize_db_technical_value("Üretildi"),
        normalize_db_technical_value("OrtakOturumDosyası"),
        .oo_db_now()
      ))
    )
  },
  fallback = NULL,
  uyari = "Ortak belge metadata kaydı başarısız:")
}

#' Oturumun ortak belgeleri (istek yapan kullanıcının kopya durumuyla).
#' İçerik erişimi olmayan kullanıcıya boş döner (fail-closed).
ortak_db_dosyalar <- function(oturum_id, kullanici_id, conn = NULL) {
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
        !ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1])) {
      bos
    } else {
      DBI::dbGetQuery(
        handle$conn,
        paste(
          "SELECT f.OrtakDosyaID, f.DosyaAdi, f.DosyaYolu, f.DosyaTuru,",
          "f.DosyaBoyutu, f.DosyaDurumu, f.OlusturmaZamani,",
          "u.KaynakAdi AS UretenAdi, k.KopyalamaDurumu",
          "FROM MB_OrtakOturum_Dosyalar f",
          "LEFT JOIN MB_Users u ON u.UserID = f.UretenKullaniciID",
          "LEFT JOIN MB_OrtakOturum_DosyaKopyalari k",
          "  ON k.OrtakDosyaID = f.OrtakDosyaID AND k.KullaniciID = ?",
          "WHERE f.OrtakOturumID = ? AND f.DosyaDurumu = ?",
          "ORDER BY f.OlusturmaZamani DESC"
        ),
        params = normalize_db_params(list(
          kullanici_id,
          oturum_id,
          normalize_db_technical_value("Üretildi")
        ))
      )
    }
  },
  fallback = bos,
  uyari = "Ortak belgeler okunamadı:")

  .oo_db_restore_visible(sonuc, c("DosyaAdi", "UretenAdi"))
}

# Kopya durum satırını yazar/günceller (kullanıcı+dosya başına tek satır).
.oo_dosya_kopya_durum_yaz <- function(conn, ortak_dosya_id, kullanici_id,
                                      durum, kullanici_yolu = NULL,
                                      hata_mesaji = NULL) {
  kopyalama_zamani <- if (identical(durum, "Kopyalandı")) .oo_db_now() else NA_character_

  guncellenen <- DBI::dbExecute(
    conn,
    paste(
      "UPDATE MB_OrtakOturum_DosyaKopyalari SET KopyalamaDurumu = ?,",
      "KullaniciDosyaYolu = ?, KopyalamaZamani = ?, HataMesaji = ?",
      "WHERE OrtakDosyaID = ? AND KullaniciID = ?"
    ),
    params = normalize_db_params(list(
      normalize_db_technical_value(durum),
      normalize_db_technical_value(as.character(kullanici_yolu %||% NA_character_)[1]),
      kopyalama_zamani,
      normalize_db_visible_value(as.character(hata_mesaji %||% NA_character_)[1]),
      ortak_dosya_id,
      kullanici_id
    ))
  )

  if (guncellenen == 0L) {
    DBI::dbExecute(
      conn,
      paste(
        "INSERT INTO MB_OrtakOturum_DosyaKopyalari",
        "(OrtakDosyaID, KullaniciID, KullaniciDosyaYolu, KopyalamaDurumu,",
        " KopyalamaZamani, HataMesaji)",
        "VALUES (?, ?, ?, ?, ?, ?)"
      ),
      params = normalize_db_params(list(
        ortak_dosya_id,
        kullanici_id,
        normalize_db_technical_value(as.character(kullanici_yolu %||% NA_character_)[1]),
        normalize_db_technical_value(durum),
        kopyalama_zamani,
        normalize_db_visible_value(as.character(hata_mesaji %||% NA_character_)[1])
      ))
    )
  }

  invisible(NULL)
}

#' "Kendi Dosyalarıma Kaydet": ortak belgeyi kullanıcının kişisel klasörüne
#' kopyalar ve Dosya Yönetimi indeksine kaydeder.
#'
#' Yetki: yalnızca içerik erişimi (Katıldı) ve belge_kopyala yetkisi olan
#' katılımcı kopyalayabilir. Zaten kopyalanmışsa yeniden kopyalanmaz.
#'
#' @return list(basarili, durum, mesaj, hedef_yol)
ortak_dosya_kisisel_kopyala <- function(ortak_dosya_id, kullanici_id, conn = NULL) {
  basarisiz <- function(mesaj, durum = "Hata") {
    list(basarili = FALSE, durum = durum, mesaj = mesaj, hedef_yol = NULL)
  }

  ortak_dosya_id <- .oo_db_pos_int(ortak_dosya_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  if (is.na(ortak_dosya_id) || is.na(kullanici_id)) {
    return(basarisiz("Geçersiz belge veya kullanıcı kimliği."))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(basarisiz("Veritabanı bağlantısı alınamadı."))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  dosya <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT OrtakDosyaID, OrtakOturumID, DosyaAdi, DosyaYolu, DosyaDurumu",
        "FROM MB_OrtakOturum_Dosyalar WHERE OrtakDosyaID = ?"
      ),
      params = list(ortak_dosya_id)
    ),
    fallback = NULL
  )

  if (is.null(dosya) || nrow(dosya) == 0L ||
      !identical(dosya$DosyaDurumu[1], "Üretildi")) {
    return(basarisiz("Ortak belge bulunamadı veya erişime kapatıldı."))
  }

  oturum_id <- as.integer(dosya$OrtakOturumID[1])

  # Yetki: içerik erişimli katılımcı + belge_kopyala yetkisi (fail-closed).
  katilimci <- ortak_db_katilimci_getir(oturum_id, kullanici_id, conn = handle$conn)
  if (is.null(katilimci) ||
      !ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) ||
      !ortak_yetki_var_mi(katilimci$Rol[1], "belge_kopyala")) {
    return(basarisiz("Bu belgeyi kopyalama yetkiniz yok.", durum = "Reddetti"))
  }

  # Fiziksel kaynak ortak belge kökünün içinde olmalıdır (traversal koruması).
  kok <- ortak_oturum_dosya_koku(oturum_id)
  kaynak <- as.character(dosya$DosyaYolu[1])
  if (is.null(kok) || !.oo_dosya_kok_icinde_mi(kaynak, kok) || !file.exists(kaynak)) {
    return(basarisiz("Ortak belge fiziksel olarak doğrulanamadı."))
  }

  # Zaten kopyalanmışsa gereksiz ikinci kopya üretilmez.
  mevcut <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT KopyalamaDurumu FROM MB_OrtakOturum_DosyaKopyalari",
        "WHERE OrtakDosyaID = ? AND KullaniciID = ?"
      ),
      params = list(ortak_dosya_id, kullanici_id)
    ),
    fallback = NULL
  )

  if (!is.null(mevcut) && nrow(mevcut) > 0L &&
      identical(mevcut$KopyalamaDurumu[1], "Kopyalandı")) {
    return(list(
      basarili = TRUE,
      durum = "Kopyalandı",
      mesaj = "Belge zaten kişisel dosyalarınıza kopyalanmış.",
      hedef_yol = NULL
    ))
  }

  # Kişisel klasöre kopyala ve Dosya Yönetimi indeksine kaydet.
  sonuc <- .oo_db_try({
    if (!exists("global_register_file", mode = "function", inherits = TRUE)) {
      stop("Dosya Yönetimi kayıt fonksiyonu bulunamadı.", call. = FALSE)
    }

    kayit <- global_register_file(
      src_path = kaynak,
      filename = as.character(dosya$DosyaAdi[1]),
      user_id = kullanici_id
    )

    hedef_yol <- if (is.list(kayit)) {
      as.character(kayit$stored_path %||% kayit$path %||% NA_character_)[1]
    } else if (is.character(kayit)) {
      kayit[1]
    } else {
      NA_character_
    }

    if (is.na(hedef_yol) || !nzchar(hedef_yol) || !file.exists(hedef_yol)) {
      stop("Kişisel dosya kaydı geçerli bir hedef dosya üretmedi.", call. = FALSE)
    }

    .oo_dosya_kopya_durum_yaz(
      handle$conn, ortak_dosya_id, kullanici_id,
      durum = "Kopyalandı", kullanici_yolu = hedef_yol
    )

    list(
      basarili = TRUE,
      durum = "Kopyalandı",
      mesaj = "Belge kişisel dosyalarınıza kopyalandı.",
      hedef_yol = hedef_yol
    )
  },
  fallback = NULL,
  uyari = "Ortak belge kişisel kopyalama başarısız:")

  if (is.null(sonuc)) {
    .oo_db_try(.oo_dosya_kopya_durum_yaz(
      handle$conn, ortak_dosya_id, kullanici_id,
      durum = "Hata", hata_mesaji = "Kopyalama sırasında hata oluştu."
    ), fallback = NULL)
    return(basarisiz("Belge kopyalanırken hata oluştu."))
  }

  sonuc
}
