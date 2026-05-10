# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-file-resolver-refactor-contract.R
# Açıklama: MCP dosya kayıt/çözümleme yardımcılarının helpers_mcp_tools
#           monolitinden ayrı dosyada kaldığını doğrular.
# ==============================================================================

.read_repo_text_quiet_mcp_resolver <- function(path) {
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
    file.path(repo_root_for_tests, "R", "helpers_mcp_table_readers.R"),
    file.path(repo_root_for_tests, "R", "helpers_mcp_file_resolver.R")
  )

  for (dosya in gerekli_dosyalar) {
    source(dosya, encoding = "UTF-8", local = globalenv())
  }
})

test_that("MCP dosya çözümleyici ayrı dosyada tutulur", {
  tools_txt <- .read_repo_text_quiet_mcp_resolver("R/helpers_mcp_tools.R")
  bootstrap_txt <- .read_repo_text_quiet_mcp_resolver("R/helpers_mcp_bootstrap.R")
  resolver_txt <- .read_repo_text_quiet_mcp_resolver("R/helpers_mcp_file_resolver.R")

  expected_defs <- c(
    "helpers_mcp_tools$ensure_session_file_registry <- function",
    "helpers_mcp_tools$register_uploaded_file <- function",
    "helpers_mcp_tools$resolve_file_argument <- function"
  )

  tools_has_defs <- vapply(
    expected_defs,
    function(x) grepl(x, tools_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  resolver_has_defs <- vapply(
    expected_defs,
    function(x) grepl(x, resolver_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_false(
    any(tools_has_defs),
    info = "MCP dosya kayıt/çözümleme fonksiyonları helpers_mcp_tools.R içine geri taşınmamalıdır."
  )

  expect_true(
    all(resolver_has_defs),
    info = paste(
      "Eksik MCP dosya çözümleyici tanımları:",
      paste(expected_defs[!resolver_has_defs], collapse = ", ")
    )
  )

  expect_true(
    grepl("R/helpers_mcp_bootstrap.R", tools_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_tools.R izole source bağlamları için MCP bootstrap dosyasını güvenli şekilde yüklemelidir."
  )

  expect_true(
    grepl("R/helpers_mcp_file_resolver.R", bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R izole source bağlamları için resolver dosyasını güvenli şekilde yüklemelidir."
  )

  expect_source_manifest_contains_for_tests(
    "R/helpers_mcp_file_resolver.R",
    label = "helpers_mcp_file_resolver.R runtime manifestinde açıkça yüklenmelidir:"
  )
})

test_that("MCP dosya çözümleyici worker ortamı için helpers_mcp_tools ortamına bağlanır", {
  expect_true(exists("resolve_file_argument", envir = helpers_mcp_tools, inherits = FALSE))
  expect_true(is.function(helpers_mcp_tools$resolve_file_argument))

  expect_identical(
    environment(helpers_mcp_tools$resolve_file_argument),
    helpers_mcp_tools,
    info = "resolve_file_argument MCP/worker bağlamında helpers_mcp_tools ortamında çalışmalıdır."
  )

  expect_true(
    exists("path_exists_relaxed", envir = environment(helpers_mcp_tools$resolve_file_argument), inherits = TRUE),
    info = "resolve_file_argument çalışırken path_exists_relaxed görünür olmalıdır."
  )

  expect_true(
    exists("get_session_user_id", envir = environment(helpers_mcp_tools$resolve_file_argument), inherits = TRUE),
    info = "resolve_file_argument çalışırken get_session_user_id görünür olmalıdır."
  )
})

test_that("MCP cross-bucket dosya çözümleme varsayılan olarak kapalıdır", {
  resolver_txt <- .read_repo_text_quiet_mcp_resolver("R/helpers_mcp_file_resolver.R")

  expect_true(
    grepl("mergen.mcp.allow_cross_bucket_lookup", resolver_txt, fixed = TRUE, useBytes = TRUE),
    info = "Cross-bucket dosya çözümleme açık opt-in option ile korunmalıdır."
  )

  expect_true(
    grepl("MERGEN_MCP_ALLOW_CROSS_BUCKET_LOOKUP", resolver_txt, fixed = TRUE, useBytes = TRUE),
    info = "Cross-bucket dosya çözümleme açık opt-in env flag ile korunmalıdır."
  )

  expect_true(
    grepl("Cross-bucket index lookup skipped", resolver_txt, fixed = TRUE, useBytes = TRUE),
    info = "Varsayılan kapalı cross-bucket yolu debug log ile görünür kalmalıdır."
  )
})