# ==============================================================================
# Dosya Yolu: tests/scripts/run_release_candidate_gate.R
# Açıklama: Üretim adayı kapısı. Yerel hardening kapısını çalıştırır, ardından
#           maintainability_report skorunu minimum eşik ile doğrular.
# ==============================================================================

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)

if (!file.exists(file.path(repo_root, "app.R")) ||
    !dir.exists(file.path(repo_root, "tests", "scripts"))) {
  stop(
    "run_release_candidate_gate.R repo kökünden çalıştırılmalıdır.",
    call. = FALSE
  )
}

source("tests/scripts/run_hardening_gate_local.R", encoding = "UTF-8")

maint_env <- new.env(parent = globalenv())
maint_result <- source(
  "tests/scripts/maintainability_report.R",
  encoding = "UTF-8",
  local = maint_env
)$value

maint_score <- attr(maint_result, "maintainability_score", exact = TRUE)

if (is.null(maint_score) || is.na(maint_score)) {
  stop(
    "Maintainability skoru okunamadı. tests/scripts/maintainability_report.R çıktısını kontrol edin.",
    call. = FALSE
  )
}

min_score_raw <- Sys.getenv("MERGEN_MIN_MAINTAINABILITY_SCORE", "19")
min_score <- suppressWarnings(as.integer(min_score_raw))

if (is.na(min_score) || min_score < 0L || min_score > 100L) {
  stop(
    sprintf(
      "MERGEN_MIN_MAINTAINABILITY_SCORE geçersiz: %s. 0-100 arası tam sayı beklenir.",
      min_score_raw
    ),
    call. = FALSE
  )
}

if (maint_score < min_score) {
  stop(
    sprintf(
      paste0(
        "Release candidate reddedildi: maintainability_score=%d/100, ",
        "beklenen minimum=%d/100. Refactor ratchet veya büyük dosya eşiklerini kontrol edin."
      ),
      maint_score,
      min_score
    ),
    call. = FALSE
  )
}

cat(sprintf(
  "OK: Release candidate kapısı başarıyla tamamlandı. Maintainability skoru: %d/100, minimum: %d/100.\n",
  maint_score,
  min_score
))