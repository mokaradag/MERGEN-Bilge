# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-runtime-workdir-contract.R
# Açıklama: Bilge Yolaç runtime çalışma dizini helper extraction ve eşzamanlı
#           çalıştırma güvenliği sözleşmesini doğrular.
# ==============================================================================

.read_repo_text_cc_runtime_workdir_contract <- function(path) {
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

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.extract_safe_source_paths_cc_runtime_workdir <- function(text) {
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

.source_cc_runtime_workdir_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$log_info <- function(...) invisible(NULL)
  test_env$log_warn <- function(...) invisible(NULL)
  test_env$log_error <- function(...) invisible(NULL)
  test_env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  test_env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = must_exist)
  }

  source(
    file.path(repo_root, "R", "helpers_claude_code_runtime_workdir.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Claude Code runtime workdir yardımcıları ayrı dosyaya taşınmıştır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(
    repo_root,
    "R",
    "helpers_claude_code_runtime_workdir.R"
  )))

  runtime_text <- .read_repo_text_cc_runtime_workdir_contract(
    "R/helpers_claude_code_runtime_workdir.R"
  )
  old_text <- .read_repo_text_cc_runtime_workdir_contract(
    "R/helpers_claude_code.R"
  )

  moved_functions <- c(
    "get_user_workspace",
    "is_problematic_windows_workdir",
    "mirror_directory_to_local_workspace",
    "prepare_claude_runtime_workdir",
    "sync_claude_runtime_workdir_back"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, runtime_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_runtime_workdir.R içinde tanımlı olmalıdır.",
        fn
      )
    )

    expect_false(
      grepl(pattern, old_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code.R içine geri taşınmamalıdır.",
        fn
      )
    )
  }
})

test_that("Claude Code runtime workdir helper source sırası korunur", {
  global_text <- .read_repo_text_cc_runtime_workdir_contract("global.R")
  paths <- .extract_safe_source_paths_cc_runtime_workdir(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_claude_code_process.R")))
  expect_false(is.na(pos("R/helpers_claude_code_runtime_workdir.R")))
  expect_false(is.na(pos("R/helpers_claude_code.R")))
  expect_false(is.na(pos("R/helpers_claude_code_server_setup.R")))

  expect_lt(
    pos("R/helpers_claude_code_process.R"),
    pos("R/helpers_claude_code_runtime_workdir.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_runtime_workdir.R"),
    pos("R/helpers_claude_code.R")
  )

  expect_lt(
    pos("R/helpers_claude_code.R"),
    pos("R/helpers_claude_code_server_setup.R")
  )
})

test_that("Claude Code runtime workdir helper dosyası parse ve source edilebilir kalır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_runtime_workdir.R"),
    encoding = "UTF-8"
  ))

  expect_silent(.source_cc_runtime_workdir_for_test())
})

test_that("runtime workdir aynalama çalışma başına benzersiz dizin kullanır", {
  test_env <- .source_cc_runtime_workdir_for_test()

  source_dir <- withr::local_tempdir()
  writeLines("merhaba", file.path(source_dir, "girdi.txt"), useBytes = TRUE)

  # Test platformu Windows olmasa bile problemli path dalını sözleşme olarak
  # doğrulamak için bu helper test ortamında zorlanır.
  test_env$is_problematic_windows_workdir <- function(path) TRUE

  first <- test_env$prepare_claude_runtime_workdir(
    source_dir,
    user_id = 42L,
    runtime_token = "request-a"
  )

  second <- test_env$prepare_claude_runtime_workdir(
    source_dir,
    user_id = 42L,
    runtime_token = "request-b"
  )

  expect_true(isTRUE(first$mirrored))
  expect_true(isTRUE(second$mirrored))

  expect_true(dir.exists(first$runtime_workdir))
  expect_true(dir.exists(second$runtime_workdir))

  expect_false(
    identical(first$runtime_workdir, second$runtime_workdir),
    info = "Aynı kullanıcı için farklı çalışma istekleri aynı runtime klasörünü paylaşmamalıdır."
  )

  expect_false(
    grepl("/active_dir$", first$runtime_workdir),
    info = "Eski paylaşılan active_dir runtime klasörü yeniden kullanılmamalıdır."
  )

  expect_false(
    grepl("/active_dir$", second$runtime_workdir),
    info = "Eski paylaşılan active_dir runtime klasörü yeniden kullanılmamalıdır."
  )

  expect_true(file.exists(file.path(first$runtime_workdir, "girdi.txt")))
  expect_true(file.exists(file.path(second$runtime_workdir, "girdi.txt")))
})

test_that("module_claude_code.R çalışma request kimliğini runtime workdir token olarak geçirir", {
  module_text <- .read_repo_text_cc_runtime_workdir_contract(
    "R/module_claude_code.R"
  )

  expect_true(
    grepl(
      "prepare_claude_runtime_workdir\\s*\\([\\s\\S]*runtime_token\\s*=\\s*run_request_id",
      module_text,
      perl = TRUE
    ),
    info = paste(
      "R/module_claude_code.R prepare_claude_runtime_workdir() çağrısında",
      "runtime_token = run_request_id geçmelidir."
    )
  )
})