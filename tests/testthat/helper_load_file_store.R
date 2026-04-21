# ==============================================================================
# Dosya Yolu: tests/testthat/helper_load_file_store.R
# Açıklama: Dosya deposu (config_file_store.R) fonksiyonlarını testlere sunar.
# testthat helper dosyaları tüm test dosyalarından önce otomatik kaynaklanır.
# Bu helper yalnızca ilk çağrıda dosya deposunu global ortama yükler.
# ==============================================================================

if (!exists("mergen_register_uploaded_file", envir = globalenv(), inherits = FALSE)) {
  # utils_common.R içinde tanımlı %||%, normalize_utf8_text vb. gereklidir.
  source(
    file.path(repo_root_for_tests, "R", "utils_common.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  # config_packages.R kısmen sourece edilmiş olabilir; yardımcı paketler
  # doğrudan require edilmeden config_file_store.R kendi sourcing sırasında
  # fs ve jsonlite kullanır. Test ortamında bu paketler mevcut olmalı.
  required_pkgs <- c("fs", "jsonlite")
  for (pkg in required_pkgs) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "Test ortamında '%s' paketi yüklü olmalıdır (config_file_store.R gerektirir).",
        pkg
      ))
    }
  }

  # Path yardımcıları config_file_store.R'den önce yüklenmelidir.
  source(
    file.path(repo_root_for_tests, "R", "utils_path_helpers.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  # config_file_store.R gc scheduler'ı MERGEN_DISABLE_FUTURES=true iken
  # başlatmaz; helper_bootstrap.R bu değişkeni zaten ayarlamıştır.
  source(
    file.path(repo_root_for_tests, "R", "config_file_store.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}
