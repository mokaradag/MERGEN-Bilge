# ==============================================================================
# Dosya Yolu: tests/testthat/helper_file_store_isolated_env.R
# Açıklama: config_file_store.R dosyasını global test ortamını kirletmeden
# izole bir environment içine source etmeye yarayan yardımcı test fonksiyonları.
# helper_load_file_store.R mevcut davranışı korur; bu helper ise env override
# testleri için taze ve izole bir yükleme sağlar.
# ==============================================================================

# config_file_store.R'yi izole bir environment içine yükler.
# Böylece MERGEN_FILES_ROOT / MERGEN_UPLOADS_DIR / MERGEN_INDEX_PATH gibi
# ortam değişkeni override'ları her testte temiz bir yükleme ile doğrulanabilir.
load_config_file_store_in_isolated_env <- function(parent = globalenv()) {
  test_env <- new.env(parent = parent)

  required_pkgs <- c("fs", "jsonlite", "openssl", "later")
  for (pkg in required_pkgs) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "Test ortamında '%s' paketi yüklü olmalıdır (izole config_file_store yüklemesi için).",
        pkg
      ))
    }
  }

  source(
    file.path(repo_root_for_tests, "R", "utils_common.R"),
    encoding = "UTF-8",
    local = test_env
  )

  source(
    file.path(repo_root_for_tests, "R", "utils_path_helpers.R"),
    encoding = "UTF-8",
    local = test_env
  )

  source(
    file.path(repo_root_for_tests, "R", "utils_atomic_write.R"),
    encoding = "UTF-8",
    local = test_env
  )

  source(
    file.path(repo_root_for_tests, "R", "config_file_store.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}