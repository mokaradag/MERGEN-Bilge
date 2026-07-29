# ==============================================================================
# Dosya Yolu: R/bootstrap_log_path.R
# Açıklama: MERGEN_LOG_DIR için ortak, erken ve Windows/UNC güvenli onarım katmanı.
# ==============================================================================

mergen_log_path_has_strong_mojibake <- function(path, repaired = NULL) {
  if (is.null(path) || !length(path)) {
    return(FALSE)
  }

  path <- enc2utf8(as.character(path[[1]]))
  if (is.na(path) || !nzchar(path)) {
    return(FALSE)
  }

  if (!is.null(repaired) && identical(enc2utf8(as.character(repaired[[1]])), path)) {
    return(FALSE)
  }

  codepoints <- tryCatch(
    utf8ToInt(path),
    error = function(e) integer(0)
  )

  # C3/C4/C5 öncüleri, Latin harfleri için yaygın UTF-8 -> Windows-1252/Latin-1
  # bozulmalarını taşır (örn. CafÃ©, GeliÅŸtirme ve çift-geçişli türevleri).
  # Tek C2 + sembol dizisi (örn. Â©) ise gerçek bir klasör adı da olabilir;
  # yalnız başına güçlü kanıt sayılmaz.
  any(codepoints %in% c(0x00C3L, 0x00C4L, 0x00C5L))
}

repair_mergen_log_dir <- function(path, max_passes = 2L) {
  if (is.null(path) || !length(path)) {
    return("")
  }

  path <- enc2utf8(trimws(as.character(path[[1]])))
  if (is.na(path) || !nzchar(path)) {
    return(path)
  }

  if (!exists("repair_text_mojibake", mode = "function", inherits = TRUE) ||
      !exists("text_has_mojibake", mode = "function", inherits = TRUE)) {
    stop(
      "MERGEN_LOG_DIR onarımı için R/utils_text_encoding.R önce yüklenmelidir.",
      call. = FALSE
    )
  }

  max_passes <- suppressWarnings(as.integer(max_passes[[1]]))
  if (is.na(max_passes) || max_passes < 1L) {
    max_passes <- 1L
  }

  repaired <- repair_text_mojibake(path, max_passes = max_passes)
  if (any(text_has_mojibake(repaired))) {
    stop(
      sprintf("MERGEN_LOG_DIR %d geçişte onarılamadı.", max_passes),
      call. = FALSE
    )
  }

  if (identical(repaired, path)) {
    return(path)
  }

  original_exists <- dir.exists(path)
  repaired_exists <- dir.exists(repaired)
  strong_evidence <- mergen_log_path_has_strong_mojibake(path, repaired)

  # Güçlü kanıt varsa, önceki sürüm bozuk klasörü daha önce oluşturmuş olsa bile
  # doğru hedefe geç. Belirsiz tek C2 dizilerinde ise yalnızca onarılmış hedef
  # zaten mevcutsa yön değiştir; ilk çalıştırmada geçerli bir klasör adını bozma.
  if (isTRUE(strong_evidence) || (!isTRUE(original_exists) && isTRUE(repaired_exists))) {
    return(enc2utf8(repaired))
  }

  path
}

normalize_mergen_log_dir_env <- function(max_passes = 2L) {
  configured <- Sys.getenv("MERGEN_LOG_DIR", "")
  repaired <- repair_mergen_log_dir(configured, max_passes = max_passes)

  if (!identical(repaired, trimws(configured))) {
    Sys.setenv(MERGEN_LOG_DIR = repaired)
  }

  invisible(repaired)
}
