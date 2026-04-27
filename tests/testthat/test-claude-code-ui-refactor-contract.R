# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-ui-refactor-contract.R
# Açıklama: Bilge Yolaç UI refactor sözleşmesini korur.
# ==============================================================================

.read_repo_text_cc_ui_contract <- function(path) {
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

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.extract_safe_source_paths_cc_ui <- function(text) {
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

test_that("Bilge Yolaç UI ayrı dosyaya taşınmıştır", {
  repo_root <- resolve_repo_root_for_tests()

  ui_path <- file.path(repo_root, "R", "module_claude_code_ui.R")
  server_path <- file.path(repo_root, "R", "module_claude_code.R")

  expect_true(file.exists(ui_path))
  expect_true(file.exists(server_path))

  ui_text <- .read_repo_text_cc_ui_contract("R/module_claude_code_ui.R")
  server_text <- .read_repo_text_cc_ui_contract("R/module_claude_code.R")

  expect_true(
    grepl("claudeCodeUI\\s*<-\\s*function\\s*\\(", ui_text, perl = TRUE),
    info = "claudeCodeUI() artık R/module_claude_code_ui.R içinde tanımlanmalıdır."
  )

  expect_false(
    grepl("claudeCodeUI\\s*<-\\s*function\\s*\\(", server_text, perl = TRUE),
    info = "claudeCodeUI() R/module_claude_code.R içine geri taşınmamalıdır."
  )

  expect_true(
    grepl("claudeCodeServer\\s*<-\\s*function\\s*\\(", server_text, perl = TRUE),
    info = "claudeCodeServer() R/module_claude_code.R içinde kalmalıdır."
  )

  expect_false(
    grepl("claudeCodeServer\\s*<-\\s*function\\s*\\(", ui_text, perl = TRUE),
    info = "Sunucu mantığı UI dosyasına taşınmamalıdır."
  )
})

test_that("Bilge Yolaç UI source sırası korunuyor", {
  global_text <- .read_repo_text_cc_ui_contract("global.R")
  paths <- .extract_safe_source_paths_cc_ui(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/module_claude_code_plugins.R")))
  expect_false(is.na(pos("R/module_claude_code_ui.R")))
  expect_false(is.na(pos("R/module_claude_code_akis.R")))
  expect_false(is.na(pos("R/module_claude_code.R")))

  expect_lt(
    pos("R/module_claude_code_plugins.R"),
    pos("R/module_claude_code_ui.R")
  )

  expect_lt(
    pos("R/module_claude_code_ui.R"),
    pos("R/module_claude_code.R")
  )
})

test_that("Bilge Yolaç UI ve server dosyaları parse edilebilir kalır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_silent(parse(
    file.path(repo_root, "R", "module_claude_code_ui.R"),
    encoding = "UTF-8"
  ))

  expect_silent(parse(
    file.path(repo_root, "R", "module_claude_code.R"),
    encoding = "UTF-8"
  ))
})