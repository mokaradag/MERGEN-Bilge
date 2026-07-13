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

# Dizin oluşturma + gevşek varlık kontrolü (Windows/UNC güvenli). Tekil oturum
# yolu (mergen_user_upload_dir) fs tabanlı oluşturma + path_exists_relaxed
# kullanır; base dir.create/dir.exists UNC/VM yollarında yanlış negatif
# verebildiği için ortak oturum kökleri de aynı kanıtlanmış deseni izler.
.oo_dizin_olustur_ve_dogrula <- function(yol) {
  yol <- as.character(yol %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) {
    return(FALSE)
  }

  tryCatch(
    fs::dir_create(yol, recurse = TRUE),
    error = function(e) {
      tryCatch(
        dir.create(yol, showWarnings = FALSE, recursive = TRUE),
        error = function(e2) NULL
      )
    }
  )

  if (exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
    var_mi <- tryCatch(isTRUE(path_exists_relaxed(yol)), error = function(e) FALSE)
    if (var_mi) {
      return(TRUE)
    }
  }

  isTRUE(tryCatch(dir.exists(yol), error = function(e) FALSE)) ||
    isTRUE(tryCatch(fs::dir_exists(yol), error = function(e) FALSE))
}

# Ortak belge kök dizini (MERGEN dosya kökü altında). Yoksa oluşturur.
# Yapılandırılmış dosya kökü erişilemezse (ör. ulaşılamayan UNC paylaşımı)
# kanıtlanmış erişilebilir MCP taban köküne düşülür; böylece üretilen belge
# kaydı, çalışma alanı ve "Kendi Dosyalarıma Kaydet" akışları kök yüzünden
# sessizce çökmez. Düşüş bir kez uyarı olarak loglanır.
ortak_oturum_dosya_koku <- function(oturum_id) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(NULL)
  }

  files_root <- getOption("mergen.files_root", NULL)
  if (is.null(files_root) || !nzchar(as.character(files_root)[1])) {
    files_root <- Sys.getenv("MERGEN_FILES_ROOT", unset = "")
  }

  alt_yol <- file.path("ortak_oturumlar", sprintf("oturum_%d", oturum_id))

  if (nzchar(as.character(files_root)[1])) {
    kok <- file.path(as.character(files_root)[1], alt_yol)
    if (.oo_dizin_olustur_ve_dogrula(kok)) {
      return(kok)
    }
    .oo_db_log_warn(
      "Ortak belge kökü dosya kökü altında oluşturulamadı;",
      "MCP taban köküne düşülüyor (MERGEN_FILES_ROOT erişilebilirliğini doğrulayın)."
    )
  }

  yedek_taban <- if (exists("resolve_mcp_base_dir", mode = "function", inherits = TRUE)) {
    tryCatch(resolve_mcp_base_dir(), error = function(e) "")
  } else if (exists("MERGEN_UPLOADS_DIR", inherits = TRUE)) {
    as.character(get("MERGEN_UPLOADS_DIR", inherits = TRUE))[1]
  } else {
    ""
  }

  if (!nzchar(as.character(yedek_taban %||% "")[1])) {
    return(NULL)
  }

  kok <- file.path(as.character(yedek_taban)[1], alt_yol)
  if (.oo_dizin_olustur_ve_dogrula(kok)) {
    return(kok)
  }
  NULL
}

# Yol, ortak belge kökünün İÇİNDE mi? Traversal/dış yol reddedilir.
.oo_dosya_karsilastirma_yolu <- function(yol) {
  yol <- as.character(yol %||% "")[1]
  if (!nzchar(yol)) {
    return("")
  }

  # Windows'ta hedef dosya henüz yokken normalizePath(mustWork = FALSE)
  # ebeveyn dizinle farklı kısa/uzun yol biçimi üretebilir. Bu nedenle
  # var olan ebeveyni normalize edip dosya adını onun altına ekliyoruz.
  if (!file.exists(yol) && dir.exists(dirname(yol))) {
    ebeveyn <- tryCatch(
      normalizePath(dirname(yol), winslash = "/", mustWork = TRUE),
      error = function(e) ""
    )
    if (nzchar(ebeveyn)) {
      return(enc2utf8(file.path(ebeveyn, basename(yol))))
    }
  }

  out <- tryCatch(
    normalizePath(yol, winslash = "/", mustWork = FALSE),
    error = function(e) ""
  )

  enc2utf8(out)
}

.oo_dosya_kok_icinde_mi <- function(yol, kok) {
  if (is.null(yol) || is.null(kok) || !nzchar(yol) || !nzchar(kok)) {
    return(FALSE)
  }

  yol_norm <- .oo_dosya_karsilastirma_yolu(yol)
  kok_norm <- .oo_dosya_karsilastirma_yolu(kok)

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
#' belge köküne kopyalar ve metadata satırı ekler. Bilge Yolaç çalıştırmaları
#' kullanıcı tarafından seçilen proje dizinlerinde de koşabildiği için burada
#' katılımcı yüklemeleriyle aynı dosya doğrulama sınırı uygulanır; aksi halde
#' ajan çıktısı adı altında çalıştırılabilir/çok büyük/denetim karakterli dosya
#' tüm odaya belge olarak açılabilir.
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

  kaynak_bilgi <- suppressWarnings(file.info(kaynak_yol))
  if (!is.data.frame(kaynak_bilgi) ||
      nrow(kaynak_bilgi) == 0L ||
      isTRUE(kaynak_bilgi$isdir[1])) {
    return(NULL)
  }

  # Üretilen dosya olarak görünen sembolik bağlantıları paylaşma. Bilge Yolaç
  # özel proje dizininde çalışırken bir bağlantı çalışma alanı içinde görünse de
  # hedefi kullanıcı/oda kapsamı dışındaki hassas bir dosya olabilir;
  # file.copy() bağlantı hedefini kopyalayarak bu dosyayı tüm odaya açabilir.
  baglanti_hedefi <- tryCatch(Sys.readlink(kaynak_yol), error = function(e) "")
  if (length(baglanti_hedefi) > 0L && nzchar(as.character(baglanti_hedefi[1]))) {
    .oo_db_log_warn("Sembolik bağlantı ortak belge olarak kaydedilemez; kayıt reddedildi.")
    return(NULL)
  }

  kaynak_yol <- tryCatch(
    normalizePath(kaynak_yol, winslash = "/", mustWork = TRUE),
    error = function(e) kaynak_yol
  )

  kok <- ortak_oturum_dosya_koku(oturum_id)
  if (is.null(kok)) {
    return(NULL)
  }

  ad <- as.character(dosya_adi %||% basename(kaynak_yol))[1]

  if (exists("validate_uploaded_file", mode = "function", inherits = TRUE)) {
    izinli_uzantilar <- if (exists("ortak_belge_izinli_uzantilar", mode = "function", inherits = TRUE)) {
      ortak_belge_izinli_uzantilar()
    } else {
      c(
        "txt", "pdf", "docx", "xlsx", "xls", "csv", "json",
        "r", "py", "md", "log", "xml", "html",
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"
      )
    }
    dogrulama <- validate_uploaded_file(
      path = kaynak_yol,
      filename = ad,
      max_size_mb = getOption("mergen.upload_max_mb", 25L),
      allowed_ext = izinli_uzantilar
    )
    if (!isTRUE(dogrulama$ok)) {
      .oo_db_log_warn(paste(
        "Üretilen ortak belge doğrulaması başarısız; kayıt reddedildi:",
        as.character(dogrulama$error %||% dogrulama$code %||% "bilinmeyen")
      ))
      return(NULL)
    }
  }

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
    .oo_db_try(unlink(hedef), fallback = NULL)
    return(NULL)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  boyut <- suppressWarnings(as.numeric(file.info(hedef)$size[1]))
  uzanti <- tolower(tools::file_ext(hedef))

  dosya_id <- .oo_db_try({
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

  if (is.null(dosya_id)) {
    .oo_db_try(unlink(hedef), fallback = NULL)
  }

  dosya_id
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
          "f.DosyaBoyutu, f.DosyaDurumu, f.OlusturmaZamani, f.MetaJson,",
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

  # Görünen ad okunurken DB-safe kaçış belirteçleri geri açılır.
  dosya <- .oo_db_restore_visible(dosya, "DosyaAdi")

  oturum_id <- as.integer(dosya$OrtakOturumID[1])

  # Yetki: içerik erişimli katılımcı + belge_kopyala yetkisi (fail-closed).
  katilimci <- ortak_db_katilimci_getir(oturum_id, kullanici_id, conn = handle$conn)
  if (is.null(katilimci) ||
      !ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) ||
      !ortak_yetki_var_mi(katilimci$Rol[1], "belge_kopyala")) {
    return(basarisiz("Bu belgeyi kopyalama yetkiniz yok.", durum = "Reddetti"))
  }

  # Fiziksel kaynak ortak belge köklerinin İÇİNDE olmalıdır (traversal
  # koruması). Üretilen belgeler dosya kökünde, katılımcı yüklemeleri
  # oturuma özel yükleme kökünde durur; ikisi de meşru kaynaktır.
  kok <- ortak_oturum_dosya_koku(oturum_id)
  yukleme_koku <- if (exists("ortak_oturum_yukleme_koku", mode = "function", inherits = TRUE)) {
    ortak_oturum_yukleme_koku(oturum_id)
  } else {
    NULL
  }
  kaynak <- as.character(dosya$DosyaYolu[1])
  kok_icinde <- (!is.null(kok) && .oo_dosya_kok_icinde_mi(kaynak, kok)) ||
    (!is.null(yukleme_koku) && .oo_dosya_kok_icinde_mi(kaynak, yukleme_koku))
  if (!isTRUE(kok_icinde) || !file.exists(kaynak)) {
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

  # Aşama 1: kullanıcının KENDİ yükleme klasörüne GERÇEK fiziksel kopya.
  # Not: global_register_file, MCP tabanı altındaki kaynakları "zaten depoda"
  # sayıp kopyasız indeksleyebiliyordu; katılımcı yüklemeleri MCP tabanındaki
  # ortak klasörde durduğu için kişisel "kopya" ortak dosyayı paylaşıyordu
  # (ortak belge silinince kişisel kayıt da kırılıyordu). Bu yüzden fiziksel
  # kopya burada açıkça kullanıcı kovasına yapılır; kayıt fonksiyonu yalnızca
  # indeksleme için kullanılır.
  hedef_dizin <- .oo_db_try(
    if (exists("mergen_user_upload_dir", mode = "function", inherits = TRUE)) {
      mergen_user_upload_dir(kullanici_id)
    } else {
      NULL
    },
    fallback = NULL,
    uyari = "Kişisel yükleme klasörü çözümlenemedi:"
  )

  if (is.null(hedef_dizin) || !nzchar(as.character(hedef_dizin %||% "")[1]) ||
      !.oo_dizin_olustur_ve_dogrula(hedef_dizin)) {
    .oo_db_try(.oo_dosya_kopya_durum_yaz(
      handle$conn, ortak_dosya_id, kullanici_id,
      durum = "Hata", hata_mesaji = "Kişisel dosya klasörü hazırlanamadı."
    ), fallback = NULL)
    return(basarisiz("Kişisel dosya klasörünüz hazırlanamadı; sistem yöneticinize başvurun."))
  }

  gorunen_ad <- as.character(dosya$DosyaAdi[1] %||% basename(kaynak))[1]
  hedef_yol <- .oo_dosya_hedef_adi(hedef_dizin, gorunen_ad)

  kopyalandi <- .oo_db_try(
    isTRUE(file.copy(kaynak, hedef_yol, overwrite = FALSE)) && file.exists(hedef_yol),
    fallback = FALSE,
    uyari = "Ortak belge kişisel fiziksel kopyası başarısız:"
  )
  if (!isTRUE(kopyalandi)) {
    .oo_db_try(.oo_dosya_kopya_durum_yaz(
      handle$conn, ortak_dosya_id, kullanici_id,
      durum = "Hata", hata_mesaji = "Fiziksel kopyalama başarısız."
    ), fallback = NULL)
    return(basarisiz("Belge kişisel klasörünüze kopyalanamadı (disk/izin sorunu olabilir)."))
  }

  # Aşama 2: Dosya Yönetimi indeksine kayıt (görünen ad korunur). Hedef zaten
  # kullanıcı kovasında olduğundan kayıt fonksiyonu ikinci kopya üretmez.
  indekslendi <- .oo_db_try({
    if (exists("global_register_file", mode = "function", inherits = TRUE)) {
      global_register_file(
        src_path = hedef_yol,
        filename = gorunen_ad,
        user_id = kullanici_id
      )
      TRUE
    } else {
      FALSE
    }
  },
  fallback = FALSE,
  uyari = "Ortak belge kişisel indeks kaydı başarısız:")

  if (!isTRUE(indekslendi)) {
    # Fiziksel kopya başarılı; indeks kaydı düşse bile dosya klasör taramasıyla
    # görünür kalır. Kullanıcıya başarısızlık olarak bildirilmez, loglanır.
    .oo_db_log_warn("Kişisel kopya indekslenemedi; dosya yine de kullanıcı klasöründe.")
  }

  # Aşama 3: kopya durumu (best-effort). Durum satırı yazılamazsa (ör. eski
  # şemada MB_OrtakOturum_DosyaKopyalari eksikse) kopyalama BAŞARISIZ SAYILMAZ;
  # yalnızca "Dosyalarımda" rozeti bir sonraki görünümde eksik kalır.
  durum_yazildi <- .oo_db_try({
    .oo_dosya_kopya_durum_yaz(
      handle$conn, ortak_dosya_id, kullanici_id,
      durum = "Kopyalandı", kullanici_yolu = hedef_yol
    )
    TRUE
  },
  fallback = FALSE,
  uyari = "Ortak belge kopya durumu yazılamadı (kopya başarılı):")

  list(
    basarili = TRUE,
    durum = "Kopyalandı",
    mesaj = if (isTRUE(durum_yazildi)) {
      "Belge kişisel dosyalarınıza kopyalandı."
    } else {
      "Belge kişisel dosyalarınıza kopyalandı (kopya durumu kaydedilemedi; kurulum betiğini doğrulayın)."
    },
    hedef_yol = hedef_yol
  )
}
