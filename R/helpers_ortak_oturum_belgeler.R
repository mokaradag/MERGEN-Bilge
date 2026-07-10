# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_belgeler.R
# Açıklama: Ortak Oturum PAYLAŞILAN belge girdileri: katılımcı yüklemeleri,
#           belge seçimi (yapay zekâ bağlamına dahil etme), belge silme ve
#           seçili belgelerden LLM bağlam metni üretimi. Üretilen (Bilge Yolaç)
#           belgelerin kaydı ve "Kendi Dosyalarıma Kaydet" akışı
#           R/helpers_ortak_oturum_files.R içinde kalır.
#
# Sözleşmeler:
#   * Yüklemeler tekil oturum yüklemeleriyle AYNI doğrulama sınırından geçer:
#     validate_uploaded_file (boyut/uzantı/traversal/UTF-8) + merkezi
#     getOption("mergen.upload_max_mb", 25L) sınırı + fm_normal_allowed_extensions.
#   * Fiziksel dosyalar mergen_uploads (MCP taban) altında oturuma özel
#     deterministik klasörde saklanır: <mcp_base>/ortak_oturum_<id>/ —
#     kullanıcı klasörlerinin (user_<id>) ortak oturum karşılığı.
#   * Her sunucu eylemi fail-closed yetki doğrulamasından geçer: katılımcı +
#     içerik erişimi (Katıldı) + yapay_zeka_sor yetkisi. UI gizlemesi tek
#     başına güvenlik değildir.
#   * DDL DEĞİŞMEZ: yükleme kaynağı ve seçim durumu MB_OrtakOturum_Dosyalar
#     tablosunun mevcut MetaJson kolonunda taşınır; DosyaDurumu/DosyaSahipligi
#     CHECK kısıtlarındaki mevcut Türkçe değerler aynen kullanılır.
#   * Yalnızca SEÇİLİ belgeler yapay zekâ bağlamına girer.
# ==============================================================================

# Oturuma özel yükleme kökü (mergen_uploads / MCP taban altında, user_<id>
# klasörlerinin ortak karşılığı). Yoksa oluşturur; oluşturulamazsa NULL döner.
ortak_oturum_yukleme_koku <- function(oturum_id) {
  oturum_id <- .oo_db_pos_int(oturum_id)
  if (is.na(oturum_id)) {
    return(NULL)
  }

  # Testler kökü deterministik geçici dizine yönlendirebilir; üretimde MCP
  # taban (mergen_uploads / MCP_FILES_BASE) kullanılır.
  taban <- as.character(getOption("mergen.ortak_yukleme_taban", "") %||% "")[1]
  if (!nzchar(taban)) {
    taban <- if (exists("resolve_mcp_base_dir", mode = "function", inherits = TRUE)) {
      tryCatch(resolve_mcp_base_dir(), error = function(e) "")
    } else if (exists("MERGEN_UPLOADS_DIR", inherits = TRUE)) {
      as.character(get("MERGEN_UPLOADS_DIR", inherits = TRUE))[1]
    } else {
      ""
    }
  }

  if (is.null(taban) || !nzchar(as.character(taban)[1])) {
    return(NULL)
  }

  kok <- file.path(as.character(taban)[1], sprintf("ortak_oturum_%d", oturum_id))
  dir.create(kok, showWarnings = FALSE, recursive = TRUE)

  if (!dir.exists(kok)) {
    return(NULL)
  }
  kok
}

# Ortak belge yüklemelerinde izin verilen uzantılar: tekil oturum yükleme
# politikasıyla AYNI kaynak (fm_normal_allowed_extensions). Yardımcı izole
# test bağlamlarında yüklü değilse aynı listeye güvenli düşülür.
ortak_belge_izinli_uzantilar <- function() {
  if (exists("fm_normal_allowed_extensions", mode = "function", inherits = TRUE)) {
    return(fm_normal_allowed_extensions())
  }
  c(
    "txt", "pdf", "docx", "xlsx", "xls", "csv", "json",
    "r", "py", "md", "log", "xml", "html",
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"
  )
}

# MetaJson ayrıştırma (SAF): kaynak (KatilimciYuklemesi / boş = üretilen) ve
# seçim durumu. Bozuk/boş JSON güvenli varsayılana düşer (seçili değil).
ortak_belge_meta <- function(meta_json) {
  varsayilan <- list(kaynak = "", secili = FALSE)

  ham <- as.character(meta_json %||% "")[1]
  if (is.na(ham) || !nzchar(ham) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return(varsayilan)
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(ham, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (!is.list(parsed)) {
    return(varsayilan)
  }

  list(
    kaynak = as.character(parsed$kaynak %||% "")[1],
    secili = isTRUE(as.logical(parsed$secili %||% FALSE)[1])
  )
}

# MetaJson üretimi (SAF): ASCII alan adları, deterministik biçim.
.oo_belge_meta_json <- function(kaynak, secili, yukleyen = NULL) {
  govde <- list(
    kaynak = as.character(kaynak %||% "")[1],
    secili = isTRUE(secili)
  )
  yukleyen <- .oo_db_pos_int(yukleyen)
  if (!is.na(yukleyen)) {
    govde$yukleyen <- yukleyen
  }
  as.character(jsonlite::toJSON(govde, auto_unbox = TRUE, null = "null"))[1]
}

# Belge eylemleri için ortak fail-closed yetki denetimi: katılımcı + içerik
# erişimi (Katıldı) + yapay_zeka_sor yetkisi ("Yapay Zekâya Sor" basabilen
# kullanıcı belge yükleyebilir/seçebilir/kaldırabilir).
.oo_belge_yetkili_mi <- function(conn, oturum_id, kullanici_id) {
  katilimci <- ortak_db_katilimci_getir(oturum_id, kullanici_id, conn = conn)

  !is.null(katilimci) &&
    ortak_icerik_erisimi_var_mi(katilimci$KatilimDurumu[1]) &&
    ortak_yetki_var_mi(katilimci$Rol[1], "yapay_zeka_sor")
}

#' Katılımcı yüklemesini ortak oturum belgesi olarak kaydeder.
#'
#' Tekil oturum yüklemeleriyle aynı doğrulama zinciri uygulanır
#' (validate_uploaded_file: boyut/uzantı/traversal/UTF-8), dosya oturuma özel
#' yükleme köküne kopyalanır ve metadata MetaJson kaynak işaretiyle yazılır.
#' Yeni yüklenen belge varsayılan olarak SEÇİLİDİR (bağlama dahil).
#'
#' @return list(basarili, mesaj, dosya_id)
ortak_db_belge_yukle <- function(oturum_id,
                                 kullanici_id,
                                 kaynak_yol,
                                 dosya_adi = NULL,
                                 conn = NULL) {
  basarisiz <- function(mesaj) {
    list(basarili = FALSE, mesaj = mesaj, dosya_id = NULL)
  }

  oturum_id <- .oo_db_pos_int(oturum_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  kaynak_yol <- as.character(kaynak_yol %||% "")[1]
  ad <- as.character(dosya_adi %||% basename(kaynak_yol))[1]

  if (is.na(oturum_id) || is.na(kullanici_id) || !nzchar(kaynak_yol)) {
    return(basarisiz("Geçersiz oturum, kullanıcı veya dosya bilgisi."))
  }

  # Tekil oturum yüklemeleriyle AYNI sunucu tarafı güven sınırı.
  dogrulama <- validate_uploaded_file(
    path = kaynak_yol,
    filename = ad,
    max_size_mb = getOption("mergen.upload_max_mb", 25L),
    allowed_ext = ortak_belge_izinli_uzantilar()
  )
  if (!isTRUE(dogrulama$ok)) {
    return(basarisiz(dogrulama$error %||% "Dosya doğrulaması başarısız."))
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(basarisiz("Veritabanı bağlantısı alınamadı."))
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  if (!.oo_db_oturum_aktif_mi(handle$conn, oturum_id)) {
    return(basarisiz("Aktif olmayan ortak oturuma belge yüklenemez."))
  }

  if (!.oo_belge_yetkili_mi(handle$conn, oturum_id, kullanici_id)) {
    return(basarisiz("Bu odada belge yükleme yetkiniz yok."))
  }

  kok <- ortak_oturum_yukleme_koku(oturum_id)
  if (is.null(kok)) {
    return(basarisiz("Ortak belge klasörü hazırlanamadı."))
  }

  hedef <- .oo_dosya_hedef_adi(kok, ad)
  if (!.oo_dosya_kok_icinde_mi(hedef, kok)) {
    .oo_db_log_warn("Ortak belge yükleme hedefi kök dışında; reddedildi.")
    return(basarisiz("Dosya adı güvenli bir hedefe çözümlenemedi."))
  }

  kopyalandi <- .oo_db_try(
    file.copy(kaynak_yol, hedef, overwrite = FALSE),
    fallback = FALSE,
    uyari = "Ortak belge fiziksel kopyası başarısız:"
  )
  if (!isTRUE(kopyalandi)) {
    return(basarisiz("Dosya ortak belge klasörüne kopyalanamadı."))
  }

  boyut <- suppressWarnings(as.numeric(file.info(hedef)$size[1]))
  uzanti <- tolower(tools::file_ext(hedef))

  dosya_id <- .oo_db_try({
    .oo_db_insert_returning_id(
      conn = handle$conn,
      insert_sql_tsql = paste(
        "INSERT INTO MB_OrtakOturum_Dosyalar",
        "(OrtakOturumID, OrtakCalistirmaID, UretenKullaniciID, DosyaAdi,",
        " DosyaYolu, DosyaTuru, DosyaBoyutu, DosyaDurumu, DosyaSahipligi,",
        " OlusturmaZamani, MetaJson)",
        "OUTPUT INSERTED.OrtakDosyaID AS id",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      insert_sql_plain = paste(
        "INSERT INTO MB_OrtakOturum_Dosyalar",
        "(OrtakOturumID, OrtakCalistirmaID, UretenKullaniciID, DosyaAdi,",
        " DosyaYolu, DosyaTuru, DosyaBoyutu, DosyaDurumu, DosyaSahipligi,",
        " OlusturmaZamani, MetaJson)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      id_column = "OrtakDosyaID",
      params = normalize_db_params(list(
        oturum_id,
        NA_integer_,
        kullanici_id,
        normalize_db_visible_value(basename(hedef)),
        normalize_db_technical_value(hedef),
        normalize_db_technical_value(uzanti),
        boyut,
        normalize_db_technical_value("Üretildi"),
        normalize_db_technical_value("OrtakOturumDosyası"),
        .oo_db_now(),
        normalize_db_technical_value(
          .oo_belge_meta_json("KatilimciYuklemesi", secili = TRUE, yukleyen = kullanici_id)
        )
      ))
    )
  },
  fallback = NULL,
  uyari = "Ortak belge yükleme metadata kaydı başarısız:")

  if (is.null(dosya_id)) {
    .oo_db_try(unlink(hedef), fallback = NULL)
    return(basarisiz("Belge kaydedilemedi; lütfen tekrar deneyin."))
  }

  # Odaya görünür belge bildirimi (sistem kaynaklı; yükleme yetkisi doğrulandı).
  yukleyen_ad <- .oo_db_try({
    satir <- DBI::dbGetQuery(
      handle$conn,
      "SELECT KaynakAdi FROM MB_Users WHERE UserID = ?",
      params = list(kullanici_id)
    )
    if (nrow(satir) > 0L) as.character(satir$KaynakAdi[1]) else ""
  }, fallback = "")
  yukleyen_ad <- normalize_db_read_visible_value(as.character(yukleyen_ad %||% "")[1])

  bildirim <- if (nzchar(yukleyen_ad) && !is.na(yukleyen_ad)) {
    sprintf("%s ortak belge yükledi: %s", yukleyen_ad, basename(hedef))
  } else {
    sprintf("Ortak belge yüklendi: %s", basename(hedef))
  }

  ortak_db_mesaj_ekle(
    oturum_id = oturum_id,
    gonderen_kullanici_id = NULL,
    mesaj_turu = "BelgeBildirimi",
    mesaj_metni = bildirim,
    conn = handle$conn
  )
  ortak_db_olay_ekle(oturum_id, "BelgeÜretildi", kullanici_id, conn = handle$conn)

  list(
    basarili = TRUE,
    mesaj = sprintf("Belge yüklendi: %s", basename(hedef)),
    dosya_id = dosya_id
  )
}

#' Ortak belgeyi kaldırır (soft delete + güvenli fiziksel silme).
#' Yalnızca yetkili katılımcı (yapay_zeka_sor) kaldırabilir; dosya kökleri
#' dışındaki yollar ASLA silinmez (fail-closed).
#'
#' @return list(basarili, mesaj)
ortak_db_belge_sil <- function(ortak_dosya_id, kullanici_id, conn = NULL) {
  basarisiz <- function(mesaj) list(basarili = FALSE, mesaj = mesaj)

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
    return(basarisiz("Ortak belge bulunamadı veya zaten kaldırılmış."))
  }

  oturum_id <- as.integer(dosya$OrtakOturumID[1])
  if (!.oo_db_oturum_aktif_mi(handle$conn, oturum_id)) {
    return(basarisiz("Aktif olmayan ortak oturumda belge kaldırılamaz."))
  }

  if (!.oo_belge_yetkili_mi(handle$conn, oturum_id, kullanici_id)) {
    return(basarisiz("Bu belgeyi kaldırma yetkiniz yok."))
  }

  guncellendi <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      "UPDATE MB_OrtakOturum_Dosyalar SET DosyaDurumu = ? WHERE OrtakDosyaID = ?",
      params = normalize_db_params(list(
        normalize_db_technical_value("Silindi"),
        ortak_dosya_id
      ))
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak belge kaldırma güncellemesi başarısız:")

  if (!isTRUE(guncellendi)) {
    return(basarisiz("Belge kaldırılamadı; lütfen tekrar deneyin."))
  }

  # Fiziksel silme yalnızca belge köklerinin İÇİNDEKİ gerçek dosyalar için
  # (traversal/dış yol koruması); başarısızlık kaydı geri almaz (best-effort).
  yol <- as.character(dosya$DosyaYolu[1] %||% "")[1]
  yukleme_koku <- ortak_oturum_yukleme_koku(oturum_id)
  uretim_koku <- ortak_oturum_dosya_koku(oturum_id)
  kok_icinde <- (!is.null(yukleme_koku) && .oo_dosya_kok_icinde_mi(yol, yukleme_koku)) ||
    (!is.null(uretim_koku) && .oo_dosya_kok_icinde_mi(yol, uretim_koku))

  if (isTRUE(kok_icinde) && nzchar(yol) && file.exists(yol)) {
    .oo_db_try(unlink(yol), fallback = NULL)
  }

  list(basarili = TRUE, mesaj = "Ortak belge kaldırıldı.")
}

#' Belgenin yapay zekâ bağlamı seçim durumunu günceller (paylaşılan durum:
#' tüm katılımcılar aynı seçimi görür). Yalnızca yetkili katılımcı değiştirir.
#'
#' @return TRUE/FALSE
ortak_db_belge_secim_guncelle <- function(ortak_dosya_id,
                                          kullanici_id,
                                          secili,
                                          conn = NULL) {
  ortak_dosya_id <- .oo_db_pos_int(ortak_dosya_id)
  kullanici_id <- .oo_db_pos_int(kullanici_id)
  if (is.na(ortak_dosya_id) || is.na(kullanici_id)) {
    return(FALSE)
  }

  handle <- .oo_db_try(.oo_db_acquire(conn), fallback = NULL)
  if (is.null(handle)) {
    return(FALSE)
  }
  on.exit(.oo_db_release(handle), add = TRUE)

  dosya <- .oo_db_try(
    DBI::dbGetQuery(
      handle$conn,
      paste(
        "SELECT OrtakOturumID, DosyaDurumu, MetaJson",
        "FROM MB_OrtakOturum_Dosyalar WHERE OrtakDosyaID = ?"
      ),
      params = list(ortak_dosya_id)
    ),
    fallback = NULL
  )

  if (is.null(dosya) || nrow(dosya) == 0L ||
      !identical(dosya$DosyaDurumu[1], "Üretildi")) {
    return(FALSE)
  }

  oturum_id <- as.integer(dosya$OrtakOturumID[1])
  if (!.oo_db_oturum_aktif_mi(handle$conn, oturum_id)) {
    return(FALSE)
  }

  if (!.oo_belge_yetkili_mi(handle$conn, oturum_id, kullanici_id)) {
    return(FALSE)
  }

  eski_meta <- ortak_belge_meta(dosya$MetaJson[1])
  yeni_meta <- .oo_belge_meta_json(eski_meta$kaynak, secili = isTRUE(secili))

  sonuc <- .oo_db_try({
    DBI::dbExecute(
      handle$conn,
      "UPDATE MB_OrtakOturum_Dosyalar SET MetaJson = ? WHERE OrtakDosyaID = ?",
      params = normalize_db_params(list(
        normalize_db_technical_value(yeni_meta),
        ortak_dosya_id
      ))
    ) > 0L
  },
  fallback = FALSE,
  uyari = "Ortak belge seçim güncellemesi başarısız:")

  isTRUE(sonuc)
}


#' Oturumun seçili belge kimliklerini döndürür. Soru MetaJson anlık görüntüsü
#' için kullanılır; kuyruktaki sorular daha sonra çalışsa bile aynı belge
#' kümesini kullanır.
ortak_db_secili_belge_idleri <- function(oturum_id, kullanici_id, conn = NULL) {
  df <- ortak_db_secili_belgeler(oturum_id, kullanici_id, conn = conn)
  if (!is.data.frame(df) || nrow(df) == 0L || !("OrtakDosyaID" %in% names(df))) {
    return(integer(0))
  }

  ids <- suppressWarnings(as.integer(df$OrtakDosyaID))
  ids[!is.na(ids) & ids > 0L]
}

#' Belge bağlam anlık görüntüsünü soru MetaJson'undan okur.
ortak_belge_meta_secili_idleri <- function(meta_json) {
  ham <- as.character(meta_json %||% "")[1]
  if (is.na(ham) || !nzchar(ham) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return(NULL)
  }

  parsed <- tryCatch(jsonlite::fromJSON(ham, simplifyVector = TRUE), error = function(e) NULL)
  ids <- if (is.list(parsed) && is.list(parsed$belgeler)) parsed$belgeler$secili_ids else NULL
  if (is.null(ids)) {
    return(NULL)
  }

  ids <- suppressWarnings(as.integer(ids))
  ids <- ids[!is.na(ids) & ids > 0L]
  unique(ids)
}

#' Oturum belgelerini verilen anlık görüntü kimlikleriyle sınırlar.
ortak_db_belgeler_idlerle <- function(oturum_id, kullanici_id, belge_ids, conn = NULL) {
  ids <- suppressWarnings(as.integer(belge_ids %||% integer(0)))
  ids <- unique(ids[!is.na(ids) & ids > 0L])
  if (length(ids) == 0L) {
    return(data.frame())
  }

  df <- ortak_db_dosyalar(oturum_id, kullanici_id, conn = conn)
  if (!is.data.frame(df) || nrow(df) == 0L || !("OrtakDosyaID" %in% names(df))) {
    return(data.frame())
  }

  mevcut <- suppressWarnings(as.integer(df$OrtakDosyaID))
  df[!is.na(mevcut) & mevcut %in% ids, , drop = FALSE]
}

#' Oturumun bağlama dahil (seçili) belgelerini döndürür. İçerik erişimi
#' olmayan kullanıcıya boş döner (fail-closed; ortak_db_dosyalar üzerinden).
ortak_db_secili_belgeler <- function(oturum_id, kullanici_id, conn = NULL) {
  df <- ortak_db_dosyalar(oturum_id, kullanici_id, conn = conn)
  if (!is.data.frame(df) || nrow(df) == 0L || !("MetaJson" %in% names(df))) {
    return(data.frame())
  }

  secili <- vapply(seq_len(nrow(df)), function(i) {
    isTRUE(ortak_belge_meta(df$MetaJson[i])$secili)
  }, logical(1))

  df[secili, , drop = FALSE]
}

# Tek belgeyi metne çevirir (SAF-ish; dosya okur, ağ/DB yok). Tekil oturum
# yükleme akışıyla aynı ayrıştırıcı (readFileContentToString) tercih edilir.
.oo_belge_dosya_oku <- function(ad, yol) {
  if (!nzchar(as.character(yol %||% "")[1]) || !file.exists(yol)) {
    return("[Belge fiziksel olarak bulunamadı]")
  }

  if (exists("readFileContentToString", mode = "function", inherits = TRUE)) {
    return(tryCatch(
      readFileContentToString(list(name = ad, datapath = yol)),
      error = function(e) "[Belge içeriği okunamadı]"
    ))
  }

  tryCatch({
    baytlar <- readBin(yol, what = "raw", n = min(file.info(yol)$size, 200000))
    iconv(rawToChar(baytlar), from = "UTF-8", to = "UTF-8", sub = "byte")
  }, error = function(e) "[Belge içeriği okunamadı]")
}

#' Seçili belgelerden LLM bağlam metni üretir. Toplam bütçe dosya sayısına
#' bölünür (dosya başına en az 4000 karakter — tekil oturum "none" dalı ile
#' aynı bütçe deseni). Belge yoksa NULL döner.
#'
#' @return list(metin, adlar) veya NULL
ortak_belge_baglam_metni <- function(belgeler_df, toplam_butce = 90000L) {
  if (!is.data.frame(belgeler_df) || nrow(belgeler_df) == 0L) {
    return(NULL)
  }

  n <- nrow(belgeler_df)
  dosya_basi <- max(4000L, as.integer(floor(toplam_butce / n)))

  adlar <- character(0)
  bloklar <- character(0)

  for (i in seq_len(n)) {
    ad <- as.character(belgeler_df$DosyaAdi[i] %||% "belge")[1]
    yol <- as.character(belgeler_df$DosyaYolu[i] %||% "")[1]

    icerik <- .oo_belge_dosya_oku(ad, yol)
    if (!is.character(icerik) || length(icerik) == 0L) {
      icerik <- "[Belge içeriği okunamadı]"
    }
    icerik <- icerik[1]
    if (nchar(icerik) > dosya_basi) {
      icerik <- paste0(substr(icerik, 1L, dosya_basi), "\n... [Belge kısaltıldı]")
    }

    adlar <- c(adlar, ad)
    bloklar <- c(bloklar, sprintf("[BELGE %d: %s]\n%s", i, ad, icerik))
  }

  if (length(bloklar) == 0L) {
    return(NULL)
  }

  kaynakca <- paste(paste0(seq_along(adlar), ") ", adlar), collapse = "\n")

  metin <- paste0(
    "Bu ortak oturuma katılımcılar tarafından paylaşılan ve bağlama dahil edilen belgeler aşağıdadır. ",
    "Soruları yanıtlarken bu belge içeriklerini kullan ve yararlandığın belgeleri yanıtın sonunda ",
    "'Kaynakça:' bölümünde listele.\n\n",
    paste(bloklar, collapse = "\n\n"),
    "\n\nKaynakça listesi için belge adları:\n", kaynakca
  )

  list(metin = metin, adlar = adlar)
}

#' Seçili belgelerden LLM sistem mesajı üretir; seçili belge yoksa NULL.
#' Üretim motoru bu mesajı persona sistem mesajından SONRA geçmişe ekler.
ortak_belge_baglam_sistem_mesaji <- function(oturum_id, kullanici_id, conn = NULL, belge_ids = NULL) {
  secili <- if (is.null(belge_ids)) {
    ortak_db_secili_belgeler(oturum_id, kullanici_id, conn = conn)
  } else {
    ortak_db_belgeler_idlerle(oturum_id, kullanici_id, belge_ids, conn = conn)
  }
  baglam <- ortak_belge_baglam_metni(secili)
  if (is.null(baglam)) {
    return(NULL)
  }

  list(role = "system", content = baglam$metin)
}
