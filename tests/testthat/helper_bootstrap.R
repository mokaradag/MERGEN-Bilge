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

# Testlerde kullanılan yardımcılar global ortamda tutulur.
.test_global <- globalenv()

# Global ortama güvenli şekilde test stub'ı kaydeder.
register_test_stub <- function(name, value) {
  if (!exists(name, envir = .test_global, inherits = FALSE)) {
    assign(name, value, envir = .test_global)
  }
}

# `%||%` operatörü henüz tanımlı değilse minimal sürümü eklenir.
register_test_stub("%||%", function(x, y) {
  if (is.null(x)) y else x
})

# Log fonksiyonları yoksa test çıktısını kirletmeyen no-op sürümler tanımlanır.
register_test_stub("log_info", function(...) invisible(NULL))
register_test_stub("log_warn", function(...) invisible(NULL))
register_test_stub("log_error", function(...) invisible(NULL))

# Dosya/klasör varlığını gevşek şekilde kontrol eden yardımcı fonksiyon.
if (!exists("path_exists_relaxed", envir = .test_global, inherits = FALSE)) {
  assign("path_exists_relaxed", function(path) {
    isTRUE(file.exists(path)) || isTRUE(dir.exists(path))
  }, envir = .test_global)
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

# Test helper içinde tek ve açık bir repo kökü değişkeni kullanılır.
repo_root_for_tests <- resolve_repo_root_for_tests()

# Testlerde kullanılan yardımcı fonksiyon ve dosyaları global ortama yükler.
source(file.path(repo_root_for_tests, "R", "utils_safe_source.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_worker_monitor.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_database.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "utils_file_index.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "utils_rate_limiter.R"), encoding = "UTF-8", local = .test_global)