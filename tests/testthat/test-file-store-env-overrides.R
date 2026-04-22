# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-store-env-overrides.R
# Açıklama: config_file_store.R içindeki MERGEN_FILES_ROOT,
# MERGEN_UPLOADS_DIR ve MERGEN_INDEX_PATH ortam değişkeni override'larının
# gerçekten dikkate alındığını doğrulayan regresyon testleri.
# ==============================================================================

test_that("config_file_store ortam değişkeni override'larini kullanir", {
  # config_file_store.R source edilirken global options yazıldığı için
  # mevcut değerleri test sonunda geri yükle.
  withr::local_options(list(
    mergen.files_root = getOption("mergen.files_root"),
    mergen.index_path = getOption("mergen.index_path"),
    mergen.mcp_base_dir = getOption("mergen.mcp_base_dir")
  ))

  gecici_kok <- withr::local_tempdir(pattern = "mergen-file-store-env-")

  beklenen_files_root <- file.path(gecici_kok, "custom-files-root")
  beklenen_uploads_dir <- file.path(gecici_kok, "custom-uploads-root")
  beklenen_index_path <- file.path(gecici_kok, "custom-state", "index.json")

  dir.create(dirname(beklenen_index_path), recursive = TRUE, showWarnings = FALSE)

  withr::local_envvar(c(
    MERGEN_FILES_ROOT = beklenen_files_root,
    MERGEN_UPLOADS_DIR = beklenen_uploads_dir,
    MERGEN_INDEX_PATH = beklenen_index_path,
    MCP_FILES_BASE = ""  # resolve_mcp_base_dir fallback'i deterministik olsun
  ))

  cfg_env <- load_config_file_store_in_isolated_env()

  expect_true(exists("MERGEN_FILES_ROOT", envir = cfg_env, inherits = FALSE))
  expect_true(exists("MERGEN_UPLOADS_DIR", envir = cfg_env, inherits = FALSE))
  expect_true(exists("MERGEN_INDEX_PATH", envir = cfg_env, inherits = FALSE))
  expect_true(exists("MERGEN_MCP_BASE_DIR", envir = cfg_env, inherits = FALSE))

  expected_files_root_norm <- cfg_env$normalize_utf8_path(
    beklenen_files_root,
    mustWork = TRUE
  )
  expected_uploads_dir_norm <- cfg_env$normalize_utf8_path(
    beklenen_uploads_dir,
    mustWork = TRUE
  )
  expected_index_path_norm <- cfg_env$normalize_utf8_path(
    beklenen_index_path,
    mustWork = FALSE
  )

  expect_identical(cfg_env$MERGEN_FILES_ROOT, expected_files_root_norm)
  expect_identical(cfg_env$MERGEN_UPLOADS_DIR, expected_uploads_dir_norm)
  expect_identical(cfg_env$MERGEN_INDEX_PATH, expected_index_path_norm)

  # MCP_FILES_BASE boş bırakıldığında mevcut davranış gereği uploads dir'e düşmeli.
  expect_identical(cfg_env$MERGEN_MCP_BASE_DIR, expected_uploads_dir_norm)

  expect_true(dir.exists(cfg_env$MERGEN_FILES_ROOT))
  expect_true(dir.exists(cfg_env$MERGEN_UPLOADS_DIR))

  # config_file_store.R'nin set ettiği global options da aynı değerleri göstermeli.
  expect_identical(getOption("mergen.files_root"), expected_files_root_norm)
  expect_identical(getOption("mergen.index_path"), expected_index_path_norm)
  expect_identical(getOption("mergen.mcp_base_dir"), expected_uploads_dir_norm)
})

test_that("izole yuklemeler onceki file-store durumunu birbirine sizdirmaz", {
  withr::local_options(list(
    mergen.files_root = getOption("mergen.files_root"),
    mergen.index_path = getOption("mergen.index_path"),
    mergen.mcp_base_dir = getOption("mergen.mcp_base_dir")
  ))

  kok_1 <- tempfile("mergen-file-store-env-a-")
  kok_2 <- tempfile("mergen-file-store-env-b-")

  dir.create(kok_1, recursive = TRUE, showWarnings = FALSE)
  dir.create(kok_2, recursive = TRUE, showWarnings = FALSE)

  withr::local_envvar(c(
    MERGEN_FILES_ROOT = file.path(kok_1, "files-root"),
    MERGEN_UPLOADS_DIR = file.path(kok_1, "uploads-root"),
    MERGEN_INDEX_PATH = file.path(kok_1, "state", "index.json"),
    MCP_FILES_BASE = ""
  ))
  env_a <- load_config_file_store_in_isolated_env()

  withr::local_envvar(c(
    MERGEN_FILES_ROOT = file.path(kok_2, "files-root"),
    MERGEN_UPLOADS_DIR = file.path(kok_2, "uploads-root"),
    MERGEN_INDEX_PATH = file.path(kok_2, "state", "index.json"),
    MCP_FILES_BASE = ""
  ))
  env_b <- load_config_file_store_in_isolated_env()

  expect_false(identical(env_a$MERGEN_FILES_ROOT, env_b$MERGEN_FILES_ROOT))
  expect_false(identical(env_a$MERGEN_UPLOADS_DIR, env_b$MERGEN_UPLOADS_DIR))
  expect_false(identical(env_a$MERGEN_INDEX_PATH, env_b$MERGEN_INDEX_PATH))
})