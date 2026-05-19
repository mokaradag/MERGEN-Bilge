# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-path-fallback-contract.R
# Açıklama: MCP helper ortamının worker/izole test bağlamında da path normalize
#           yardımcısına sahip olduğunu statik olarak doğrular.
# ==============================================================================

.read_repo_text_quiet_mcp_path <- function(path) {
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
  gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
}

test_that("MCP bootstrap normalize_excel_path için yerel fallback tanımlar", {
  txt <- .read_repo_text_quiet_mcp_path("R/helpers_mcp_bootstrap.R")

  beklenenler <- c(
    '.mcp_bootstrap_has_tool_function("normalize_excel_path")',
    "helpers_mcp_tools$normalize_excel_path <- function(path, must_exist = FALSE)",
    "helpers_mcp_tools$resolve_readable_path(p)",
    "helpers_mcp_tools$path_exists_relaxed(resolved)"
  )

  bulunanlar <- vapply(
    beklenenler,
    function(x) grepl(x, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    info = paste(
      "MCP bootstrap path fallback sözleşmesi eksik:",
      paste(beklenenler[!bulunanlar], collapse = ", ")
    )
  )
})