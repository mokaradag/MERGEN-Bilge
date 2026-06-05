# ==============================================================================
# Dosya Yolu: tests/testthat/helper_load_file_store.R
# Açıklama: Dosya deposu (config_file_store.R) fonksiyonlarını testlere izole
#           geçici dizinlerle sunar. Test koşumunda MERGEN_FILES_ROOT,
#           MERGEN_UPLOADS_DIR, MERGEN_INDEX_PATH ve MCP_FILES_BASE kesin olarak
#           tempdir altına alınır; böylece gerçek ağ/paylaşım/repo yollarına
#           index.json veya atomic_*.tmp yazılmaya çalışılmaz.
# ==============================================================================

# ------------------------------------------------------------------------------
# Repo kökü fallback'i
# ------------------------------------------------------------------------------

if (!exists("repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
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

  repo_root_for_tests <- resolve_repo_root_for_tests()
}

# ------------------------------------------------------------------------------
# Test ortamı placeholder'ları
# ------------------------------------------------------------------------------

.file_store_set_env_if_blank <- function(name, value) {
  current <- Sys.getenv(name, "")
  if (!nzchar(current)) {
    do.call(Sys.setenv, stats::setNames(list(value), name))
  }
}

.file_store_set_env_if_blank("LOCAL_LLM_ENDPOINT", "http://test.local/v1")
.file_store_set_env_if_blank("DB_DSN", "test-dsn")
.file_store_set_env_if_blank("AI_KEYS_MASTER", "test-master-key-0123456789")
Sys.setenv(MERGEN_DISABLE_FUTURES = "true", MERGEN_RUN_APP = "false")

# ------------------------------------------------------------------------------
# File Store test yollarını zorla
# ------------------------------------------------------------------------------

.file_store_test_root <- function() {
  if (exists(".test_temp_root", envir = globalenv(), inherits = FALSE)) {
    return(get(".test_temp_root", envir = globalenv(), inherits = FALSE))
  }

  fallback <- file.path(tempdir(), "mergen-tests-file-store")
  dir.create(fallback, recursive = TRUE, showWarnings = FALSE)
  fallback
}

.file_store_normalize_test_path <- function(path) {
  path <- gsub("\\\\", "/", as.character(path)[1], fixed = TRUE)
  suppressWarnings(normalizePath(path, winslash = "/", mustWork = FALSE))
}

.file_store_force_test_paths <- function() {
  root <- .file_store_test_root()

  files_root <- .file_store_normalize_test_path(file.path(root, "files_root"))
  uploads_dir <- .file_store_normalize_test_path(file.path(root, "mergen_uploads"))
  mcp_base_dir <- .file_store_normalize_test_path(file.path(root, "mcp_base"))
  index_path <- .file_store_normalize_test_path(file.path(files_root, "index.json"))

  dir.create(files_root, recursive = TRUE, showWarnings = FALSE)
  dir.create(uploads_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(mcp_base_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(index_path), recursive = TRUE, showWarnings = FALSE)

  Sys.setenv(
    MERGEN_FILES_ROOT = files_root,
    MERGEN_UPLOADS_DIR = uploads_dir,
    MERGEN_INDEX_PATH = index_path,
    MERGEN_MCP_BASE_DIR = mcp_base_dir,
    MCP_FILES_BASE = mcp_base_dir
  )

  assign("MERGEN_FILES_ROOT", files_root, envir = globalenv())
  assign("MERGEN_UPLOADS_DIR", uploads_dir, envir = globalenv())
  assign("MERGEN_INDEX_PATH", index_path, envir = globalenv())
  assign("MERGEN_MCP_BASE_DIR", mcp_base_dir, envir = globalenv())

  options(
    mergen.files_root = files_root,
    mergen.index_path = index_path,
    mergen.mcp_base_dir = mcp_base_dir
  )

  invisible(TRUE)
}

.file_store_force_test_paths()

# ------------------------------------------------------------------------------
# Bağımlılık kontrolü
# ------------------------------------------------------------------------------

required_pkgs <- c("fs", "jsonlite", "openssl", "later")

for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf(
      "Test ortamında '%s' paketi yüklü olmalıdır (config_file_store.R gerektirir).",
      pkg
    ))
  }
}

# ------------------------------------------------------------------------------
# File Store yardımcılarını daima taze test yollarıyla yükle
# ------------------------------------------------------------------------------

source(
  file.path(repo_root_for_tests, "R", "utils_common.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_for_tests, "R", "utils_path_helpers.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_for_tests, "R", "helpers_files_path.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_for_tests, "R", "utils_atomic_write.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# config_file_store.R source edilmeden hemen önce yolları tekrar sabitle.
.file_store_force_test_paths()

source(
  file.path(repo_root_for_tests, "R", "config_file_store.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_for_tests, "R", "config_file_store_index_mutation.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_for_tests, "R", "config_file_store_listing_helpers.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_for_tests, "R", "config_file_store_registry.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# Source sonrası config_file_store.R'nin ürettiği global değişkenleri tekrar
# test temp dizinlerine eşitle. Böylece önceden yüklenmiş/global state kaçmaz.
.file_store_force_test_paths()