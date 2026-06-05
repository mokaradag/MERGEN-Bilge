# ==============================================================================
# Dosya Yolu: tests/testthat/helper_zz_file_store_runtime_reset.R
# Açıklama: File Store testlerinde stale/global MERGEN_* yollarının gerçek
#           repo, ağ paylaşımı veya kullanıcı dizinlerine sızmasını engeller.
#           Bu helper alfabetik olarak en sonda yüklenir ve config_file_store
#           runtime'ını izole geçici test dizinlerine yeniden bağlar.
# ==============================================================================

reset_file_store_runtime_for_tests <- function(root = NULL) {
  # ---------------------------------------------------------------------------
  # Repo kökü
  # ---------------------------------------------------------------------------
  repo_root <- if (exists("repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
    get("repo_root_for_tests", envir = globalenv(), inherits = FALSE)
  } else {
    candidates <- c(".", "..", "../..")
    found <- NULL

    for (cand in candidates) {
      if (file.exists(file.path(cand, "app.R")) &&
          dir.exists(file.path(cand, "R"))) {
        found <- normalizePath(cand, winslash = "/", mustWork = TRUE)
        break
      }
    }

    if (is.null(found)) {
      stop("File Store test helper repo kökünü bulamadı.", call. = FALSE)
    }

    found
  }

  # ---------------------------------------------------------------------------
  # Test kökü
  # ---------------------------------------------------------------------------
  if (is.null(root) || !nzchar(as.character(root)[1])) {
    root <- if (exists(".test_temp_root", envir = globalenv(), inherits = FALSE)) {
      get(".test_temp_root", envir = globalenv(), inherits = FALSE)
    } else {
      file.path(tempdir(), "mergen-tests-file-store-runtime")
    }
  }

  root <- normalizePath(root, winslash = "/", mustWork = FALSE)

  files_root <- normalizePath(file.path(root, "files_root"), winslash = "/", mustWork = FALSE)
  uploads_dir <- normalizePath(file.path(root, "mergen_uploads"), winslash = "/", mustWork = FALSE)
  mcp_base_dir <- normalizePath(file.path(root, "mcp_base"), winslash = "/", mustWork = FALSE)
  index_path <- normalizePath(file.path(files_root, "index.json"), winslash = "/", mustWork = FALSE)

  dir.create(files_root, recursive = TRUE, showWarnings = FALSE)
  dir.create(uploads_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(mcp_base_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(index_path), recursive = TRUE, showWarnings = FALSE)

  files_root <- normalizePath(files_root, winslash = "/", mustWork = TRUE)
  uploads_dir <- normalizePath(uploads_dir, winslash = "/", mustWork = TRUE)
  mcp_base_dir <- normalizePath(mcp_base_dir, winslash = "/", mustWork = TRUE)
  index_path <- normalizePath(index_path, winslash = "/", mustWork = FALSE)

  # ---------------------------------------------------------------------------
  # Zorunlu test env değerleri
  # ---------------------------------------------------------------------------
  Sys.setenv(
    MERGEN_DISABLE_FUTURES = "true",
    MERGEN_RUN_APP = "false",
    LOCAL_LLM_ENDPOINT = if (nzchar(Sys.getenv("LOCAL_LLM_ENDPOINT", ""))) {
      Sys.getenv("LOCAL_LLM_ENDPOINT")
    } else {
      "http://test.local/v1"
    },
    DB_DSN = if (nzchar(Sys.getenv("DB_DSN", ""))) {
      Sys.getenv("DB_DSN")
    } else {
      "test-dsn"
    },
    AI_KEYS_MASTER = if (nzchar(Sys.getenv("AI_KEYS_MASTER", ""))) {
      Sys.getenv("AI_KEYS_MASTER")
    } else {
      "test-master-key-0123456789"
    },
    MERGEN_FILES_ROOT = files_root,
    MERGEN_UPLOADS_DIR = uploads_dir,
    MERGEN_INDEX_PATH = index_path,
    MERGEN_MCP_BASE_DIR = mcp_base_dir,
    MCP_FILES_BASE = mcp_base_dir
  )

  # ---------------------------------------------------------------------------
  # Global değişken ve option'ları da aynı değerlere zorla
  # ---------------------------------------------------------------------------
  assign("MERGEN_FILES_ROOT", files_root, envir = globalenv())
  assign("MERGEN_UPLOADS_DIR", uploads_dir, envir = globalenv())
  assign("MERGEN_INDEX_PATH", index_path, envir = globalenv())
  assign("MERGEN_MCP_BASE_DIR", mcp_base_dir, envir = globalenv())

  options(
    mergen.files_root = files_root,
    mergen.index_path = index_path,
    mergen.mcp_base_dir = mcp_base_dir
  )

  # Log fonksiyonları yoksa sessiz test stub'ları.
  if (!exists("log_info", envir = globalenv(), mode = "function", inherits = TRUE)) {
    assign("log_info", function(...) invisible(NULL), envir = globalenv())
  }
  if (!exists("log_warn", envir = globalenv(), mode = "function", inherits = TRUE)) {
    assign("log_warn", function(...) invisible(NULL), envir = globalenv())
  }
  if (!exists("log_error", envir = globalenv(), mode = "function", inherits = TRUE)) {
    assign("log_error", function(...) invisible(NULL), envir = globalenv())
  }
  if (!exists("log_debug", envir = globalenv(), mode = "function", inherits = TRUE)) {
    assign("log_debug", function(...) invisible(NULL), envir = globalenv())
  }

  # ---------------------------------------------------------------------------
  # File Store runtime'ını test yollarıyla taze yükle
  # ---------------------------------------------------------------------------
  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "utils_text_encoding.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "utils_path_helpers.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_files_path.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "utils_atomic_write.R"), encoding = "UTF-8", local = globalenv())

  # config_file_store.R source edilmeden hemen önce tekrar sabitle.
  Sys.setenv(
    MERGEN_FILES_ROOT = files_root,
    MERGEN_UPLOADS_DIR = uploads_dir,
    MERGEN_INDEX_PATH = index_path,
    MERGEN_MCP_BASE_DIR = mcp_base_dir,
    MCP_FILES_BASE = mcp_base_dir
  )

  source(file.path(repo_root, "R", "config_file_store.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "config_file_store_index_mutation.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "config_file_store_listing_helpers.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "config_file_store_registry.R"), encoding = "UTF-8", local = globalenv())

  # Source sonrası config_file_store.R'nin set ettiği değerleri bir kez daha
  # test temp dizinlerine eşitle.
  assign("MERGEN_FILES_ROOT", files_root, envir = globalenv())
  assign("MERGEN_UPLOADS_DIR", uploads_dir, envir = globalenv())
  assign("MERGEN_INDEX_PATH", index_path, envir = globalenv())
  assign("MERGEN_MCP_BASE_DIR", mcp_base_dir, envir = globalenv())

  options(
    mergen.files_root = files_root,
    mergen.index_path = index_path,
    mergen.mcp_base_dir = mcp_base_dir
  )

  # Güvenlik freni: test koşumunda index path gerçek repo/ağ yoluna düşmesin.
  bad_index <- grepl("MERGEN Bilge", index_path, fixed = TRUE) ||
    grepl("^//rehisds|^\\\\\\\\rehisds", index_path, ignore.case = TRUE)

  if (isTRUE(bad_index)) {
    stop(sprintf(
      "File Store test izolasyonu başarısız: MERGEN_INDEX_PATH gerçek/ağ yolda kaldı: %s",
      index_path
    ), call. = FALSE)
  }

  invisible(list(
    files_root = files_root,
    uploads_dir = uploads_dir,
    mcp_base_dir = mcp_base_dir,
    index_path = index_path
  ))
}

reset_file_store_runtime_for_tests()