# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-upload-folder-refactor-contract.R
# Açıklama: Bilge Yolaç yükleme klasörü yardımcı refactor sözleşmesini korur.
# ==============================================================================

.read_repo_text_cc_upload_folder_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.extract_safe_source_paths_cc_upload_folder <- function(text) {
  m <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, m)[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) {
    return(character(0))
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

.source_cc_upload_folder_helper_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$path_exists_relaxed <- function(path) {
    isTRUE(file.exists(path)) || isTRUE(dir.exists(path))
  }

  test_env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = FALSE)
  }

  test_env$mergen_list_user_files <- function(user_id, prune_missing = FALSE) {
    data.frame(name = character(0), path = character(0), stringsAsFactors = FALSE)
  }

  test_env$mergen_user_upload_dir <- function(user_id) {
    file.path(tempdir(), sprintf("user_%s", user_id))
  }

  test_env$MERGEN_UPLOADS_DIR <- tempdir()

  source(
    file.path(repo_root, "R", "helpers_claude_code_upload_folder.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Claude Code upload-folder yardımcıları ayrı dosyaya taşınmıştır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(repo_root, "R", "helpers_claude_code_upload_folder.R")))
  expect_true(file.exists(file.path(repo_root, "R", "module_claude_code.R")))

  helper_text <- .read_repo_text_cc_upload_folder_contract(
    "R/helpers_claude_code_upload_folder.R"
  )
  module_text <- .read_repo_text_cc_upload_folder_contract(
    "R/module_claude_code.R"
  )
  setup_text <- .read_repo_text_cc_upload_folder_contract(
    "R/helpers_claude_code_server_setup.R"
  )

  moved_functions <- c(
    "cc_normalize_positive_user_id",
    "cc_resolve_existing_dir_relaxed",
    "cc_count_dir_items_relaxed",
    "cc_resolve_real_upload_folder"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, helper_text, perl = TRUE),
      info = sprintf("%s yeni upload-folder helper dosyasında tanımlı olmalıdır.", fn)
    )
  }

  old_local_functions <- c(
    "resolve_existing_dir_relaxed",
    "count_dir_items_relaxed",
    "resolve_real_upload_folder"
  )

  for (fn in old_local_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_false(
      grepl(pattern, module_text, perl = TRUE),
      info = sprintf("%s R/module_claude_code.R içine geri taşınmamalıdır.", fn)
    )
  }

  expect_true(
    grepl("cc_bind_server_setup\\s*\\(", module_text, perl = TRUE),
    info = "module_claude_code.R Bilge Yolaç setup sorumluluğunu helper'a devretmelidir."
  )

  expect_true(
    grepl("cc_resolve_real_upload_folder\\(", setup_text, perl = TRUE),
    info = "helpers_claude_code_server_setup.R yeni upload-folder helper'ı çağırmalıdır."
  )
})

test_that("Claude Code upload-folder source sırası korunuyor", {
  global_text <- .read_repo_text_cc_upload_folder_contract("global.R")
  paths <- .extract_safe_source_paths_cc_upload_folder(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_claude_code_upload_folder.R")))
  expect_false(is.na(pos("R/helpers_claude_code_model_config.R")))
  expect_false(is.na(pos("R/helpers_claude_code.R")))
  expect_false(is.na(pos("R/module_claude_code.R")))

  expect_lt(
    pos("R/helpers_ai_expert.R"),
    pos("R/helpers_claude_code_upload_folder.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_upload_folder.R"),
    pos("R/helpers_claude_code_model_config.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_upload_folder.R"),
    pos("R/module_claude_code.R")
  )
})

test_that("Claude Code upload-folder helper dosyası parse edilebilir kalır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_upload_folder.R"),
    encoding = "UTF-8"
  ))
})

test_that("Claude Code upload-folder helper geçersiz kullanıcıları ve oturum kayıtlarını güvenli işler", {
  test_env <- .source_cc_upload_folder_helper_for_test()

  expect_identical(test_env$cc_normalize_positive_user_id(0L), "")
  expect_identical(test_env$cc_normalize_positive_user_id("unknown"), "")
  expect_identical(test_env$cc_resolve_real_upload_folder("0"), "")

  tmp <- withr::local_tempdir()
  index_dir <- file.path(tmp, "index_dir")
  registry_dir <- file.path(tmp, "registry_dir")
  canonical_dir <- file.path(tmp, "uploads", "user_42")

  dir.create(index_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(registry_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(canonical_dir, recursive = TRUE, showWarnings = FALSE)

  file.create(file.path(index_dir, "rapor.txt"))
  file.create(file.path(registry_dir, "Çalışma.txt"))
  file.create(file.path(registry_dir, "ek.xlsx"))

  test_env$MERGEN_UPLOADS_DIR <- file.path(tmp, "uploads")
  test_env$mergen_user_upload_dir <- function(user_id) {
    canonical_dir
  }
  test_env$mergen_list_user_files <- function(user_id, prune_missing = FALSE) {
    data.frame(
      name = "rapor.txt",
      path = file.path(index_dir, "rapor.txt"),
      stringsAsFactors = FALSE
    )
  }

  registry <- list(
    "Çalışma.txt" = list(persisted_path = file.path(registry_dir, "Çalışma.txt")),
    "ek.xlsx" = list(path = file.path(registry_dir, "ek.xlsx"))
  )

  expect_equal(
    test_env$cc_resolve_real_upload_folder("42", session_file_registry = registry),
    normalizePath(registry_dir, winslash = "/", mustWork = FALSE)
  )
})