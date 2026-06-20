# ==============================================================================
# Dosya Yolu: tests/testthat/helper_bootstrap.R
# Açıklama: Test ortamı için zorunlu çevre değişkenlerini, fallback yardımcı
# fonksiyonları ve testlerde kullanılan R yardımcı dosyalarını yükler.
# ==============================================================================

# Test ortamı değişkenlerini yalnızca test koşumu süresince uygular.
.testthat_teardown_env <- testthat::teardown_env()

withr::local_envvar(
  c(
    MERGEN_DISABLE_FUTURES = "true",
    MERGEN_RUN_APP = "false"
  ),
  .local_envir = .testthat_teardown_env
)

# config_file_store.R zorunlu ortam değişkenlerini aradığı için test koşumunda
# sadece placeholder değerler ayarlanır. Gerçek değer gerektiren testler bu
# değişkenleri kendi scope'unda tekrar ayarlayabilir.
.set_env_if_missing <- function(name, value) {
  mevcut_deger <- Sys.getenv(name, unset = NA_character_)
  deger_var_mi <- !is.na(mevcut_deger) && nzchar(mevcut_deger)

  if (!deger_var_mi) {
    withr::local_envvar(
      stats::setNames(value, name),
      .local_envir = .testthat_teardown_env
    )
  }
}

.set_env_if_missing("LOCAL_LLM_ENDPOINT", "http://test.local/v1")
.set_env_if_missing("DB_DSN",             "test-dsn")
.set_env_if_missing("AI_KEYS_MASTER",     "test-master-key-0123456789")

.test_temp_root <- withr::local_tempdir(
  pattern = "mergen-tests-",
  .local_envir = .testthat_teardown_env
)

.test_files_root <- file.path(.test_temp_root, "files_root")
.test_uploads_dir <- file.path(.test_temp_root, "mergen_uploads")
.test_mcp_base_dir <- file.path(.test_temp_root, "mcp_base")
.test_logs_dir <- file.path(.test_temp_root, "logs")
.test_index_path <- file.path(.test_files_root, "index.json")

dir.create(.test_files_root, recursive = TRUE, showWarnings = FALSE)
dir.create(.test_uploads_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(.test_mcp_base_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(.test_logs_dir, recursive = TRUE, showWarnings = FALSE)

withr::local_envvar(
  c(
    MERGEN_FILES_ROOT = .test_files_root,
    MERGEN_UPLOADS_DIR = .test_uploads_dir,
    MERGEN_INDEX_PATH = .test_index_path,
    MERGEN_MCP_BASE_DIR = .test_mcp_base_dir,
    MCP_FILES_BASE = .test_mcp_base_dir,
    MERGEN_LOG_DIR = .test_logs_dir
  ),
  .local_envir = .testthat_teardown_env
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
register_test_stub("log_debug", function(...) invisible(NULL))

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
source(file.path(repo_root_for_tests, "R", "utils_text_encoding.R"), encoding = "UTF-8", local = .test_global)
# Performans ölçüm yardımcısı: üretim manifesti bu dosyayı loglamadan hemen
# sonra yükler. Test bootstrap'ı da aynı sırayı yansıtır ki opt-in [PERF]
# kancaları (örn. DB bağlantı süreleri) izole testlerde de görünür olsun.
source(file.path(repo_root_for_tests, "R", "helpers_performance_instrumentation.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_mailto_encoding.R"), encoding = "UTF-8", local = .test_global)
# Persona kimliği tek kaynağı; normalize_character_id / get_character_record
# gibi yardımcılar downstream helper'lar ve testler tarafından kullanılır.
source(file.path(repo_root_for_tests, "R", "config_characters.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_worker_monitor.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_db_unicode_escape.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_db_encoding.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_db_connection.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_db_validation.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_chat_message_formatting.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_db_chat_read_queries.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_db_chat_readers.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_db_chat_mutations.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_database.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "utils_file_index.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_file_manager_policy.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_file_manager_context_policy.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_file_manager_table.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_file_manager_refresh_guard.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_file_manager_session_registry.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_file_manager_runtime.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_file_manager_storage.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_claude_code_session_context.R"), encoding = "UTF-8", local = .test_global)
source(file.path(repo_root_for_tests, "R", "helpers_claude_code_dir_ui.R"), encoding = "UTF-8", local = .test_global)