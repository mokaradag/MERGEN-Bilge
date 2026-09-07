# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_delete_runtime.R
# Açıklama: Dosya Yönetimi silme akışında fiziksel dosya ve indeks temizliği.
#           Aday başına silme kararı R/helpers_file_manager_artifact_recovery.R
#           içindedir (bu dosya bakım borcu tavanındadır).
# ==============================================================================

fm_delete_persisted_file_artifacts <- function(
  info,
  uid,
  get_user_upload_dir,
  fm_debug = function(...) invisible(NULL),
  path_exists_fn = path_exists_relaxed,
  unlink_fn = unlink,
  resolve_fn = resolve_uploaded_file,
  remove_index_fn = mergen_remove_from_index
) {
  # `info$name` NA ya da çok elemanlı olabilir; `nzchar(NA)` NA döndürüp
  # "missing value where TRUE/FALSE needed" hatasıyla silme akışını yarıda
  # kesiyor ve indeks kaydı da temizlenmiyordu.
  file_name <- as.character(if (is.null(info$name)) "" else info$name)[1]
  if (length(file_name) != 1L || is.na(file_name)) file_name <- ""

  # Varlık denetimi KESİN DEĞİL (ör. geçici UNC kesintisi): indeks kaydı korunur.
  durum <- new.env(parent = emptyenv())
  durum$deleted_physical <- FALSE
  durum$deleted_path <- NA_character_
  durum$delete_failed <- FALSE
  durum$belirsiz <- FALSE

  # Silme yalnızca KULLANICININ KENDİ yükleme kökü altında yapılır (yol tabanlı
  # `unlink()` ata bileşenlerini izler). Kök ÇÖZÜLEMEZSE doğrulanmamış kökle
  # silme hiç denenmez ve indeks kaydı korunur (bkz. mergen_path_inside_root).
  kullanici_koku <- try(as.character(get_user_upload_dir())[1], silent = TRUE)
  if (inherits(kullanici_koku, "try-error") || is.na(kullanici_koku) || !nzchar(kullanici_koku)) {
    fm_debug("delete_physical_failed", "kullanıcı yükleme kökü çözülemedi")
    return(invisible(list(deleted_physical = FALSE, deleted_path = NA_character_,
                          delete_failed = TRUE, file_name = file_name, uid = uid)))
  }

  dene <- function(candidate, source_label) {
    fm_attempt_delete_candidate(
      durum = durum, candidate = candidate, source_label = source_label,
      kullanici_koku = kullanici_koku, path_exists_fn = path_exists_fn,
      unlink_fn = unlink_fn, fm_debug = fm_debug
    )
  }

  for (candidate in c(info$persisted_path, info$datapath, info$path)) {
    if (dene(candidate, "doğrudan")) break
  }

  if (!durum$deleted_physical && nzchar(file_name)) {
    persisted <- tryCatch(resolve_fn(file_name, user_id = uid), error = function(e) NULL)
    dene(persisted, "resolve")
  }

  if (!durum$deleted_physical && !is.null(uid) && nzchar(file_name)) {
    dene(file.path(kullanici_koku, basename(file_name)), "fallback")
  }

  # Kökün KENDİSİ erişilemiyorsa dosya silinmiş değildir. KESİN FALSE (kök
  # gerçekten yok) belirsizlik DEĞİLDİR; aksi hâlde indeks kaydı temizlenemezdi.
  kok_var_mi <- fm_path_exists_certain(path_exists_fn, kullanici_koku)
  if (!durum$deleted_physical && !durum$delete_failed && is.na(kok_var_mi)) {
    durum$belirsiz <- TRUE
    fm_debug("delete_physical_unknown", "kullanıcı kökü erişilemiyor")
  }

  # Silme başarısız ya da varlık denetimi kesin değilse indeks kaydı korunur.
  korunsun <- (durum$delete_failed || durum$belirsiz) && !durum$deleted_physical
  if (!is.null(uid) && nzchar(file_name) && !korunsun) {
    # İndeks temizliği BAŞARISIZ olabilir (kilit/yazma hatası). `try()` bunu
    # yutuyordu: dosya silinmiş ama BAYAT indeks kaydı dururken başarı
    # bildiriliyordu; sonuç denetlenir ve çağıran bilgilendirilir.
    if (inherits(try(remove_index_fn(uid, file_name), silent = TRUE), "try-error")) {
      korunsun <- TRUE
      fm_debug("delete_index_failed", "indeks kaydı temizlenemedi")
    }
  }

  invisible(list(
    deleted_physical = durum$deleted_physical,
    deleted_path = durum$deleted_path,
    delete_failed = korunsun,
    file_name = file_name,
    uid = uid
  ))
}
