# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-process-refactor-contract.R
# Açıklama: Bilge Yolaç process/CLI helper refactor sözleşmesini korur.
# ==============================================================================

.read_repo_text_cc_process_contract <- function(path) {
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

.extract_safe_source_paths_cc_process <- function(text) {
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

.source_claude_code_process_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$log_info <- function(...) invisible(NULL)
  test_env$log_warn <- function(...) invisible(NULL)
  test_env$log_error <- function(...) invisible(NULL)
  test_env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  test_env$claude_code_config <- list(default_workdir = "")

  source(
    file.path(repo_root, "R", "utils_text_encoding.R"),
    encoding = "UTF-8",
    local = test_env
  )

  source(
    file.path(repo_root, "R", "helpers_claude_code_process.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Claude Code process yardımcıları ayrı dosyaya taşınmıştır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(repo_root, "R", "helpers_claude_code_process.R")))

  process_text <- .read_repo_text_cc_process_contract(
    "R/helpers_claude_code_process.R"
  )
  old_text <- .read_repo_text_cc_process_contract(
    "R/helpers_claude_code.R"
  )

  moved_functions <- c(
    "resolve_node_path",
    "escape_non_ascii",
    "ensure_utf8",
    "is_windows_unc_path",
    "normalize_cmd_workdir",
    "resolve_windows_cmd_path",
    "get_safe_processx_launch_workdir",
    "build_windows_cmd_invocation_line",
    "build_processx_command",
    "parse_claude_code_json_output",
    "get_safe_claude_cli_workdir"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, process_text, perl = TRUE),
      info = sprintf("%s R/helpers_claude_code_process.R içinde tanımlı olmalıdır.", fn)
    )

    expect_false(
      grepl(pattern, old_text, perl = TRUE),
      info = sprintf("%s R/helpers_claude_code.R içine geri taşınmamalıdır.", fn)
    )
  }

  expect_true(
    grepl("run_claude_code\\s*<-\\s*function\\s*\\(", old_text, perl = TRUE),
    info = "run_claude_code() bu fazda ana helpers_claude_code.R içinde kalmalıdır."
  )
})

test_that("Claude Code process helper source sırası korunur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_session_context.R",
      "R/helpers_claude_code_process.R",
      "R/helpers_claude_code_runtime_workdir.R",
      "R/helpers_claude_code_security_policy.R",
      "R/helpers_claude_code.R",
      "R/helpers_claude_code_streaming.R"
    ),
    label = "Claude Code process helper source sırası bozulmuş:"
  )
})

test_that("Claude Code process helper dosyası parse ve source edilebilir kalır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_process.R"),
    encoding = "UTF-8"
  ))

  expect_silent(.source_claude_code_process_for_test())
})

test_that("Claude Code process helper temel davranışları korunur", {
  test_env <- .source_claude_code_process_for_test()

  expect_equal(test_env$ensure_utf8("abc"), "abc")
  expect_equal(test_env$escape_non_ascii("abc"), "abc")
  expect_equal(
    test_env$ensure_utf8("Ã§ ÄŸ Ä± Ä° Ã¶ ÅŸ Ã¼"),
    "ç ğ ı İ ö ş ü"
  )

  expect_false(test_env$is_windows_unc_path("/tmp/test"))
  
  if (.Platform$OS.type == "windows") {
    expect_true(test_env$is_windows_unc_path("//rehisds/uygulamalar/Primavera"))
    expect_true(test_env$is_windows_unc_path("/rehisds/uygulamalar/Primavera"))
  }

  cmd_workdir <- test_env$normalize_cmd_workdir("C:/tmp/test")

  expect_false(
    grepl("/", cmd_workdir, fixed = TRUE),
    info = "normalize_cmd_workdir() ileri slash karakterlerini Windows ayırıcısına çevirmelidir."
  )

  expect_match(
    cmd_workdir,
    "^C:\\\\+tmp\\\\+test$",
    info = "normalize_cmd_workdir() sürücü ve yol bileşenlerini korumalıdır."
  )

  tmp <- withr::local_tempdir()
  resolved <- test_env$get_safe_claude_cli_workdir(tmp)

  expect_equal(
    normalizePath(resolved, winslash = "/", mustWork = TRUE),
    normalizePath(tmp, winslash = "/", mustWork = TRUE)
  )

  cmd <- test_env$build_processx_command(
    cli_path = "claude",
    args = c("--version"),
    workdir = tmp
  )

  expect_equal(cmd$command, "claude")
  expect_equal(cmd$args, c("--version"))
  expect_null(cmd$env)
  expect_equal(cmd$wd, tmp)
})

test_that("Windows .cmd çalıştırması processx'e problemli wd vermez", {
  test_env <- .source_claude_code_process_for_test()

  skip_if_not(.Platform$OS.type == "windows")

  komut <- test_env$build_processx_command(
    cli_path = "C:/ProgramData/npm/claude.cmd",
    args = c("--print", "--", "dosyaları incele"),
    workdir = "//rehisds/uygulamalar/Primavera/PY"
  )

  expect_match(tolower(komut$command), "cmd\\.exe$")
  expect_true(any(komut$args == "/c"))
  expect_false(any(komut$args == "/s"))
  expect_match(paste(komut$args, collapse = " "), "pushd")
  expect_match(paste(komut$args, collapse = " "), "call")
  expect_false(test_env$is_windows_unc_path(komut$wd))
  expect_true(dir.exists(komut$wd))
})

test_that("Claude Code JSON çıktı ayrıştırma sözleşmesi korunur", {
  test_env <- .source_claude_code_process_for_test()

  jsonl <- paste(
    jsonlite::toJSON(
      list(type = "text", content = "Merhaba "),
      auto_unbox = TRUE
    ),
    jsonlite::toJSON(
      list(
        type = "text",
		content = paste0(
		  intToUtf8(c(0x00C3, 0x2021)),
		  "al",
		  intToUtf8(c(0x00C4, 0x00B1)),
		  intToUtf8(c(0x00C5, 0x0178)),
		  "ma ",
		  intToUtf8(c(0x00F0, 0x0178, 0x0161, 0x20AC))
		)
      ),
      auto_unbox = TRUE
    ),
    jsonlite::toJSON(
      list(type = "result", result = "Dünya", session_id = "abc123"),
      auto_unbox = TRUE
    ),
    sep = "\n"
  )

  parsed <- test_env$parse_claude_code_json_output(jsonl)

  expect_equal(parsed$text_output, paste0("Merhaba Çalışma ", intToUtf8(0x1F680)))
  expect_equal(parsed$session_id, "abc123")
  expect_type(parsed$tool_uses, "list")
})