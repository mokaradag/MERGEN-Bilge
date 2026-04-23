# ==============================================================================
# Dosya Yolu: tests/scripts/run_hardening_gate_local.R
# Açıklama: Yerel hardening kapısı. Önce CI-benzeri parse/smoke/testthat
# akışını çalıştırır. Eğer gerçek ortam değişkenleri mevcutsa ek olarak gerçek
# Windows VM preflight betiğini de tetikler.
# ==============================================================================

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)

if (!file.exists(file.path(repo_root, "app.R"))) {
  stop("run_hardening_gate_local.R repo kökünden çalıştırılmalıdır.", call. = FALSE)
}

required_real_vars <- c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")
real_env_snapshot <- Sys.getenv(required_real_vars, unset = "")
real_env_available <- all(nzchar(real_env_snapshot))

source("tests/scripts/run_ci_local.R", encoding = "UTF-8")

if (isTRUE(real_env_available)) {
  do.call(Sys.setenv, as.list(stats::setNames(real_env_snapshot, required_real_vars)))
  cat("INFO: Gerçek ortam değişkenleri bulundu; VM preflight çalıştırılıyor.\n")
  source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")
} else {
  missing_vars <- required_real_vars[!nzchar(real_env_snapshot)]
  cat(sprintf(
    "INFO: Gerçek ortam değişkenleri eksik olduğu için VM preflight atlandı: %s\n",
    paste(missing_vars, collapse = ", ")
  ))
}

cat("OK: Yerel hardening kapısı başarıyla tamamlandı.\n")