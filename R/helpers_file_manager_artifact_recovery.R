# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_artifact_recovery.R
# Açıklama: Dosya Yönetimi kalıcı-depo yan etki kurtarma sınırı.
#
# NEDEN AYRI DOSYA: yükleme commit'i ATOMİK DEĞİLDİR (önce oturum kaydı ve
# tablo satırı değişir, sonra hata verebilir) ve silme yolundaki varlık
# denetimi UNC/ağ paylaşımı kesintisinde KESİN DEĞİLDİR. Her iki kurtarma da
# aynı sözleşmeye dayanır: doğrulanmamış kökle asla `unlink()` yapılmaz ve
# belirsiz durumda indeks kaydı KORUNUR. R/helpers_file_manager_upload_runtime.R
# ve R/helpers_file_manager_delete_runtime.R bakım borcu tavanındadır; bu yüzden
# ortak kurtarma mantığı burada tutulur ve ikisinden de ÖNCE yüklenir.
# ==============================================================================

# Varlık denetimi sonucu: TRUE / FALSE / NA (kesin değil).
fm_path_exists_certain <- function(path_exists_fn, candidate) {
  sonuc <- try(path_exists_fn(candidate), silent = TRUE)
  if (inherits(sonuc, "try-error")) return(NA)
  # Sonda erişilemeyen paylaşımda NA döndürebilir; `isTRUE(NA)` bunu KESİN
  # FALSE'a çeviriyor ve dosya "yok" sayılıp indeks kaydı siliniyordu.
  if (length(sonuc) != 1L || !is.logical(sonuc) || is.na(sonuc)) return(NA)
  isTRUE(sonuc)
}

# Silme adayı tek, NA olmayan, boş olmayan bir metin olmalıdır. NA alanda
# `!nzchar(NA)` NA döner ve çağıranın `if` koşulu hata verirdi.
fm_valid_delete_candidate <- function(candidate) {
  !is.null(candidate) && length(candidate) == 1L && is.character(candidate) &&
    !is.na(candidate) && nzchar(candidate)
}

# Tek bir silme denemesi yapar. `durum` ORTAMDIR; sonuç alanları yerinde
# güncellenir (deleted_physical / deleted_path / delete_failed / belirsiz).
# Kararlar: kök dışı -> başarısız; varlık ya da silme sonrası durum NA -> KESİN
# DEĞİL (indeks kaydı korunur); yalnızca doğrulanmış silme "silindi" sayılır.
fm_attempt_delete_candidate <- function(durum, candidate, source_label,
                                        kullanici_koku, path_exists_fn,
                                        unlink_fn, fm_debug) {
  if (!fm_valid_delete_candidate(candidate)) return(FALSE)

  var_mi <- fm_path_exists_certain(path_exists_fn, candidate)
  if (is.na(var_mi)) durum$belirsiz <- TRUE
  if (!isTRUE(var_mi)) return(FALSE)

  sil <- function() {
    if (!isTRUE(mergen_path_inside_root(candidate, kullanici_koku))) {
      durum$delete_failed <- TRUE
      fm_debug("delete_physical_failed", sprintf("%s kök dışında: %s", source_label, candidate))
      return(FALSE)
    }

    sonuc <- try(unlink_fn(candidate, force = TRUE), silent = TRUE)
    kontrol <- fm_path_exists_certain(path_exists_fn, candidate)
    if (is.na(kontrol)) {
      durum$belirsiz <- TRUE
      fm_debug("delete_physical_unknown", sprintf("%s sonrası belirsiz: %s", source_label, candidate))
      return(FALSE)
    }

    if (inherits(sonuc, "try-error") ||
        (is.numeric(sonuc) && length(sonuc) == 1L && sonuc != 0) ||
        isTRUE(kontrol)) {
      durum$delete_failed <- TRUE
      fm_debug("delete_physical_failed", sprintf("%s ile silinemedi: %s", source_label, candidate))
      return(FALSE)
    }

    durum$deleted_physical <- TRUE
    durum$deleted_path <- candidate
    fm_debug("delete_physical", sprintf("%s ile silindi: %s", source_label, candidate))
    TRUE
  }

  # Kapsama denetimi ve `unlink()` AYNI paylaşılan kilit altında çalışır: yol
  # tabanlı silme ata bileşenlerini İZLER; iki adım arasında bir ata dizin
  # bağlantı/junction ile takas edilirse kök DIŞINDAKİ bir dosya silinebiliyordu
  # (TOCTOU). Base R tanıtıcı-bağıl `unlinkat` sunmadığı için pencere tamamen
  # kapatılamaz; kilit onu daraltır ve kaçış tespit edilirse silme HİÇ denenmez.
  # `require_lock = FALSE`: kilit alınamayan ortamda davranış bugünküyle aynıdır.
  if (exists(".file_store_with_index_lock", mode = "function", inherits = TRUE)) {
    .file_store_with_index_lock(sil(), require_lock = FALSE)
  } else {
    sil()
  }
}

# Commit başarısız olduğunda worker'ın kalıcı klasöre YAZDIĞI kopyayı kaldırır.
# Kök çözülemez veya yol kök dışındaysa dosya olduğu gibi bırakılır.
# Dönüş: TRUE (temizlendi ya da temizlenecek bir şey yok), FALSE (bilinçli
# olarak bırakıldı), NA (KESİN DEĞİL: depo erişilemiyor).
fm_cleanup_orphan_upload <- function(dest, fm_debug = NULL,
                                     get_user_upload_dir_fn = NULL,
                                     path_exists_fn = path_exists_relaxed) {
  yol <- as.character(dest %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) return(invisible(TRUE))

  # Çözümleyici modül closure'ında tanımlıdır; ad ile arandığında bulunamıyor,
  # yardımcı FALSE dönüyor ve yetim kopya kalıcı depoda kalıyordu.
  cozumleyici <- if (is.function(get_user_upload_dir_fn)) {
    get_user_upload_dir_fn
  } else if (exists("get_user_upload_dir", mode = "function", inherits = TRUE)) {
    get("get_user_upload_dir", mode = "function", inherits = TRUE)
  } else {
    NULL
  }

  if (!is.function(cozumleyici)) {
    if (is.function(fm_debug)) fm_debug("upload_orphan_keep", "çözümleyici yok")
    return(invisible(FALSE))
  }

  kok <- try(as.character(cozumleyici())[1], silent = TRUE)
  if (inherits(kok, "try-error") || is.na(kok) || !nzchar(kok)) {
    if (is.function(fm_debug)) fm_debug("upload_orphan_keep", "kullanıcı kökü çözülemedi")
    return(invisible(FALSE))
  }
  # Hedefin YOKLUĞU yalnızca kullanıcı kökü ERİŞİLEBİLİRKEN kanıttır: geçici
  # bir UNC kesintisinde `file.exists()` FALSE döndüğü için yetim kopya diskte
  # dururken temizlik "başarılı" raporlanıyordu.
  var_mi <- fm_path_exists_certain(path_exists_fn, yol)
  if (!isTRUE(var_mi)) {
    kok_var <- fm_path_exists_certain(path_exists_fn, kok)
    if (is.na(var_mi) || !isTRUE(kok_var)) {
      if (is.function(fm_debug)) fm_debug("upload_orphan_unknown", "kalıcı depo erişilemiyor")
      return(invisible(NA))
    }
    return(invisible(TRUE))
  }

  if (!isTRUE(mergen_path_inside_root(yol, kok))) {
    if (is.function(fm_debug)) fm_debug("upload_orphan_keep", "kök dışında")
    return(invisible(FALSE))
  }

  try(unlink(yol, force = TRUE), silent = TRUE)
  kalan <- fm_path_exists_certain(path_exists_fn, yol)
  if (is.na(kalan)) {
    if (is.function(fm_debug)) fm_debug("upload_orphan_unknown", "silme sonrası belirsiz")
    return(invisible(NA))
  }
  if (is.function(fm_debug)) fm_debug("upload_orphan_cleanup", basename(yol))
  invisible(!isTRUE(kalan))
}

# Commit hatasında geri almayı çalıştırır ve KISMİ geri almayı kullanıcıya
# bildirir. `process_uploaded_file()` HATA FIRLATMADAN da NULL dönebildiği için
# hem `try-error` hem NULL yolu aynı kurtarmayı kullanır.
fm_report_upload_rollback <- function(sonuc, ctx, etiket, ayrinti = "") {
  if (is.function(ctx$fm_debug)) {
    ad <- as.character(sonuc$name %||% "")[1]
    ctx$fm_debug(etiket, if (nzchar(ayrinti)) sprintf("%s -> %s", ad, ayrinti) else ad)
  }
  geri_alma <- fm_rollback_failed_upload(sonuc, ctx)
  if (!isTRUE(geri_alma$ok)) showToast(ctx$session, geri_alma$message, "warning")
  invisible(geri_alma)
}

# Dosya-başına commit hatasında UYGULANMIŞ yan etkileri geri alır: oturum
# kaydı + tablo satırı + kalıcı depodaki yetim kopya.
fm_rollback_failed_upload <- function(sonuc, ctx) {
  basarisiz <- character(0)

  if (is.function(ctx$rollback_uploaded_file)) {
    geri <- try(ctx$rollback_uploaded_file(sonuc$name), silent = TRUE)
    if (inherits(geri, "try-error") || !isTRUE(geri)) {
      basarisiz <- c(basarisiz, "oturum_kaydi")
    }
  }

  temiz <- try(
    fm_cleanup_orphan_upload(
      sonuc$dest, ctx$fm_debug,
      get_user_upload_dir_fn = ctx$get_user_upload_dir
    ),
    silent = TRUE
  )
  # Hedef hiç kopyalanmadıysa temizlenecek bir şey yoktur. BELİRSİZ sonuç (NA:
  # kalıcı depo erişilemiyor) BAŞARI SAYILMAZ; aksi hâlde UNC kesintisinde
  # diskte duran kopya "temizlendi" olarak raporlanıyordu.
  if (inherits(temiz, "try-error") || !isTRUE(temiz)) {
    basarisiz <- c(basarisiz, "yetim_kopya")
  }

  # Geri alma adımlarının GERÇEK sonucu döndürülür; koşulsuz TRUE, yetim kopya
  # ya da yarıda kalmış oturum kaydını görünmez yapıyordu.
  if (length(basarisiz)) {
    if (is.function(ctx$fm_debug)) {
      ctx$fm_debug("upload_rollback_failed", paste(basarisiz, collapse = ","))
    }
    return(invisible(list(
      ok = FALSE,
      failed_steps = basarisiz,
      message = sprintf(
        "Dosya artığı temizlenemedi: %s (%s)",
        as.character(sonuc$name %||% "")[1], paste(basarisiz, collapse = ", ")
      )
    )))
  }

  invisible(list(ok = TRUE, failed_steps = character(0), message = ""))
}

# Modül tarafındaki geri alma closure'ını üretir; module_file_manager.R bunu
# satır içi tanımlamak yerine buradan alır.
fm_make_upload_rollback <- function(unregister_fn, remove_row_fn) {
  function(filename) {
    a <- try(unregister_fn(filename), silent = TRUE)
    b <- try(remove_row_fn(filename, quiet = TRUE), silent = TRUE)
    # Callback hataları bastırılıp TRUE dönüldüğünde yarıda kalan oturum kaydı
    # ve tablo satırı görünmez kalıyordu.
    invisible(!inherits(a, "try-error") && !inherits(b, "try-error"))
  }
}

# Kalıcı kovayı güvenli temizler: hata ve kısmi temizlik FALSE olarak döner.
# Modül gözlemcisi hatayı bastırıp oturum durumunu temizlemeye devam ediyordu.
fm_clear_user_bucket_safely <- function(uid, fm_debug = NULL) {
  if (is.null(uid)) return(invisible(TRUE))
  sonuc <- tryCatch(
    suppressWarnings(mergen_clear_user_bucket(uid)),
    error = function(e) {
      if (is.function(fm_debug)) fm_debug("clear_files_failed", conditionMessage(e))
      FALSE
    }
  )
  invisible(isTRUE(sonuc))
}
