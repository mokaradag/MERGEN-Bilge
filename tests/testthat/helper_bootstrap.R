# ==============================================================================
# Dosya Yolu: tests/testthat/helper_bootstrap.R
# Açıklama: Test ortamı için zorunlu çevre değişkenlerini, fallback yardımcı
# fonksiyonları ve testlerde kullanılan R yardımcı dosyalarını yükler.
# ==============================================================================

# Testlerde paralel/uygulama ayağa kaldırma davranışını devre dışı bırakır.
Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false"
)

# `%||%` operatörü henüz tanımlı değilse test bağlamı için minimal sürümünü ekler.
if (!exists("%||%")) {
  `%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }
}

# Log fonksiyonları yoksa test çıktısını kirletmeyen no-op sürümler tanımlanır.
if (!exists("log_info"))  log_info  <- function(...) invisible(NULL)
if (!exists("log_warn"))  log_warn  <- function(...) invisible(NULL)
if (!exists("log_error")) log_error <- function(...) invisible(NULL)

# Dosya/klasör varlığını gevşek şekilde kontrol eden yardımcı fonksiyon.
if (!exists("path_exists_relaxed")) {
  path_exists_relaxed <- function(path) {
    isTRUE(file.exists(path)) || isTRUE(dir.exists(path))
  }
}

# Repo kökünü test çalıştırma dizinine göre güvenli şekilde tespit eder.
resolve_repo_root_for_tests <- function() {
  candidates <- c(".", "..", "../..")

  for (cand in candidates) {
    app_path <- file.path(cand, "app.R")
    r_dir <- file.path(cand, "R")

    if (file.exists(app_path) && dir.exists(r_dir)) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Test helper repo kökünü bulamadı. Çalışma dizinini kontrol edin.")
}

# Bulunan repo kökü üzerinden testlerin ihtiyaç duyduğu yardımcı dosyaları yükler.
.repo_root <- resolve_repo_root_for_tests()

source(file.path(.repo_root, "R", "utils_safe_source.R"), encoding = "UTF-8", local = globalenv())
source(file.path(.repo_root, "R", "helpers_worker_monitor.R"), encoding = "UTF-8", local = globalenv())
source(file.path(.repo_root, "R", "helpers_database.R"), encoding = "UTF-8", local = globalenv())
source(file.path(.repo_root, "R", "utils_file_index.R"), encoding = "UTF-8", local = globalenv())
source(file.path(.repo_root, "R", "utils_rate_limiter.R"), encoding = "UTF-8", local = globalenv())
