# ==============================================================================
# Dosya Yolu: tests/testthat/helper-load-app.R
# Açıklama: testthat çalışırken gerekli yardımcı dosyaları yükler.
# Amaç tüm uygulamayı başlatmadan test edilen fonksiyonları erişilebilir kılmaktır.
# ==============================================================================

project_root <- normalizePath(
  file.path("..", ".."),
  winslash = "/",
  mustWork = TRUE
)

source(
  file.path(project_root, "R", "utils_common.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(project_root, "R", "helpers_send_message_core.R"),
  encoding = "UTF-8",
  local = globalenv()
)