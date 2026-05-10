# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-bootstrap-refactor-contract.R
# Açıklama: MCP bootstrap/fallback source sorumluluğunun helpers_mcp_tools
#           monolitinden ayrı dosyada kaldığını doğrular.
# ==============================================================================

.read_repo_text_quiet_mcp_bootstrap <- function(path) {
  repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function")) {
    resolve_repo_root_for_tests()
  } else {
    normalizePath(".", winslash = "/", mustWork = TRUE)
  }

  full_path <- file.path(repo_root, path)
  size <- suppressWarnings(file.info(full_path)$size[1])

  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  raw_data <- raw_data[raw_data != as.raw(0)]
  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "UTF-8"
  txt <- enc2utf8(txt)
  gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
}

local({
  gerekli_dosyalar <- c(
    file.path(repo_root_for_tests, "R", "utils_common.R"),
    file.path(repo_root_for_tests, "R", "utils_path_helpers.R"),
    file.path(repo_root_for_tests, "R", "helpers_files_path.R"),
    file.path(repo_root_for_tests, "R", "helpers_files.R"),
    file.path(repo_root_for_tests, "R", "utils_excel_reader.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_context.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_bootstrap.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_tools.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_chart_tools.R")
  )

  for (dosya in gerekli_dosyalar) {
    source(dosya, encoding = "UTF-8", local = globalenv())
  }
})

test_that("MCP bootstrap sorumluluğu ayrı dosyada tutulur", {
  tools_txt <- .read_repo_text_quiet_mcp_bootstrap("R/helpers_mcp_tools.R")
  bootstrap_txt <- .read_repo_text_quiet_mcp_bootstrap("R/helpers_mcp_bootstrap.R")

  moved_defs <- c(
    "mcp_tools_find_support_file <- function",
    "helpers_mcp_tools$path_exists_relaxed <- function",
    "helpers_mcp_tools$resolve_readable_path <- function",
    "helpers_mcp_tools$normalize_excel_path <- function",
    "mcp_tools_bootstrap_ready <- function"
  )

  bootstrap_has_defs <- vapply(
    moved_defs,
    function(x) grepl(x, bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(bootstrap_has_defs),
    info = paste("Eksik MCP bootstrap tanımları:", paste(moved_defs[!bootstrap_has_defs], collapse = ", "))
  )

  expect_true(
    grepl("R/helpers_mcp_bootstrap.R", tools_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_tools.R tekil source bağlamları için bootstrap dosyasını güvenli şekilde yüklemelidir."
  )

  forbidden_inline_defs <- c(
    "helpers_mcp_tools$path_exists_relaxed <- function",
    "helpers_mcp_tools$resolve_readable_path <- function",
    "helpers_mcp_tools$normalize_excel_path <- function"
  )

  tools_has_inline_defs <- vapply(
    forbidden_inline_defs,
    function(x) grepl(x, tools_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_false(
    any(tools_has_inline_defs),
    info = "MCP bootstrap/yol fallback tanımları helpers_mcp_tools.R içine geri taşınmamalıdır."
  )

  expect_source_manifest_contains_for_tests(
    "R/helpers_mcp_bootstrap.R",
    label = "helpers_mcp_bootstrap.R runtime manifestinde açıkça yüklenmelidir:"
  )
})

test_that("MCP bootstrap source edildiğinde worker ortamı sözleşmesi hazır olur", {
  expect_true(exists("mcp_tools_bootstrap_ready", mode = "function", inherits = TRUE))
  expect_true(isTRUE(mcp_tools_bootstrap_ready()))

  expected_functions <- c(
    "mcp_debug_log",
    "get_session_user_id",
    "path_exists_relaxed",
    "normalize_excel_path",
    "resolve_readable_path",
    "safe_read_excel_table",
    "safe_read_table_generic",
    "create_md_table",
    "ensure_session_file_registry",
    "register_uploaded_file",
    "resolve_file_argument",
    "extract_mcp_file_schema",
    "find_matching_column",
    "normalize_args",
    "normalize_chart_type",
    "prettify_column_name",
    "analyze_uploaded_file",
    "get_column_statistics",
    "sql_query_uploaded_file",
    "safe_has_duckdb",
    "prepare_chart_data"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = helpers_mcp_tools, inherits = FALSE),
      info = sprintf("%s helpers_mcp_tools ortamında bulunmalıdır.", fn)
    )

    expect_true(
      is.function(get(fn, envir = helpers_mcp_tools, inherits = FALSE)),
      info = sprintf("%s helpers_mcp_tools ortamında fonksiyon olmalıdır.", fn)
    )
  }
})