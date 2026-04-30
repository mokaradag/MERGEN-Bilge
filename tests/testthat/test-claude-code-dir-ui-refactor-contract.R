# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-dir-ui-refactor-contract.R
# Açıklama: Bilge Yolaç dizin gezgini UI/refresher yardımcıları sözleşmesini korur.
# ==============================================================================

.read_repo_text_cc_dir_ui_contract <- function(path) {
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

.extract_safe_source_paths_cc_dir_ui <- function(text) {
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

.source_claude_code_dir_ui_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  source(
    file.path(repo_root, "R", "helpers_claude_code_dir_ui.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Claude Code dizin gezgini yardımcıları ayrı dosyada tutulur", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(repo_root, "R", "helpers_claude_code_dir_ui.R")))

  helper_text <- .read_repo_text_cc_dir_ui_contract("R/helpers_claude_code_dir_ui.R")
  module_text <- .read_repo_text_cc_dir_ui_contract("R/module_claude_code.R")

  moved_functions <- c(
    "cc_create_dir_refresh_guard",
    "cc_format_dir_file_size",
    "cc_dir_item_tooltip",
    "cc_build_dir_item_ui",
    "cc_build_dir_contents_ui"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, helper_text, perl = TRUE),
      info = sprintf("%s R/helpers_claude_code_dir_ui.R içinde tanımlı olmalıdır.", fn)
    )
  }

  expect_true(
    grepl("cc_build_dir_contents_ui\\(icerik,\\s*ns\\s*=\\s*ns\\)", module_text, perl = TRUE),
    info = "module_claude_code.R dizin içeriği markup üretimini helper'a devretmelidir."
  )

  expect_true(
    grepl("dir_refresh_guard\\$is_latest\\(refresh_id\\)", module_text, perl = TRUE),
    info = "module_claude_code.R stale dizin refresh sonuçlarını uygulamadan önce token kontrolü yapmalıdır."
  )
})

test_that("Claude Code dizin helper source sırası korunur", {
  global_text <- .read_repo_text_cc_dir_ui_contract("global.R")
  paths <- .extract_safe_source_paths_cc_dir_ui(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_claude_code_session_context.R")))
  expect_false(is.na(pos("R/helpers_claude_code_dir_ui.R")))
  expect_false(is.na(pos("R/helpers_claude_code_process.R")))
  expect_false(is.na(pos("R/module_claude_code.R")))

  expect_lt(
    pos("R/helpers_claude_code_session_context.R"),
    pos("R/helpers_claude_code_dir_ui.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_dir_ui.R"),
    pos("R/helpers_claude_code_process.R")
  )

  expect_lt(
    pos("R/helpers_claude_code_dir_ui.R"),
    pos("R/module_claude_code.R")
  )
})

test_that("Claude Code dizin refresh guard eski istekleri reddeder", {
  test_env <- .source_claude_code_dir_ui_for_test()

  guard <- test_env$cc_create_dir_refresh_guard()
  first <- guard$next_id()
  second <- guard$next_id()

  expect_false(guard$is_latest(first))
  expect_true(guard$is_latest(second))
  expect_equal(guard$current_id(), second)
})

test_that("Claude Code dizin UI helperları mevcut markup sözleşmesini korur", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("htmltools")

  test_env <- .source_claude_code_dir_ui_for_test()
  ns <- shiny::NS("cc")

  expect_equal(test_env$cc_format_dir_file_size(512), "512 B")
  expect_equal(test_env$cc_format_dir_file_size(2048), "2 KB")
  expect_equal(test_env$cc_format_dir_file_size(2 * 1048576), "2 MB")
  expect_equal(test_env$cc_format_dir_file_size(NA_real_), "")

  contents <- list(
    success = TRUE,
    items = list(
      list(
        ad = "sistem.txt",
        gorunen_ad = "yüklenen.txt",
        yol = "C:/tmp/sistem.txt",
        tip = "dosya",
        boyut = 512
      ),
      list(
        ad = "src",
        gorunen_ad = "src",
        yol = "C:/tmp/src",
        tip = "klasor",
        boyut = NA_real_
      )
    ),
    toplam = 2L
  )

  html <- htmltools::renderTags(
    test_env$cc_build_dir_contents_ui(contents, ns = ns)
  )$html

  expect_true(grepl("cc-dir-list", html, fixed = TRUE))
  expect_true(grepl("yüklenen.txt", html, fixed = TRUE))
  expect_true(grepl("Yüklenen ad: yüklenen.txt", html, fixed = TRUE))
  expect_true(grepl("cc-dir-clickable", html, fixed = TRUE))
  expect_true(grepl("cc-dir_navigate", html, fixed = TRUE))
})