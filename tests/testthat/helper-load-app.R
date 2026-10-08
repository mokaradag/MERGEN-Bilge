# ==============================================================================
# Dosya Yolu: tests/testthat/helper-load-app.R
# Açıklama: testthat çalışırken gerekli yardımcı dosyaları yükler.
# Amaç tüm uygulamayı başlatmadan test edilen fonksiyonları erişilebilir kılmaktır.
# ==============================================================================

# Test yürütüm konumundan proje kökünü deterministik şekilde hesaplar.
project_root <- normalizePath(
  file.path("..", ".."),
  winslash = "/",
  mustWork = TRUE
)

# Temel ortak yardımcıları global test environment'ına alır.
source(
  file.path(project_root, "R", "utils_common.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(project_root, "R", "helpers_send_message_request_lifecycle.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# Send message çekirdek yardımcılarını testlerin erişimine açar.
source(
  file.path(project_root, "R", "helpers_send_message_core.R"),
  encoding = "UTF-8",
  local = globalenv()
)
source(file.path(project_root, "R", "helpers_user_session_identity.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(project_root, "R", "helpers_file_ingestion_identity.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(project_root, "R", "helpers_worker_cancellation.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(project_root, "R", "helpers_async_result_guard.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(project_root, "R", "helpers_followup_cancellation.R"),
       encoding = "UTF-8", local = globalenv())
source(file.path(project_root, "R", "helpers_chat_render_updates.R"),
       encoding = "UTF-8", local = globalenv())
