# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-debug-output-contract.R
# Açıklama: MCP çözümleme debug çıktılarının raw cat() yerine kontrollü debug
#           logger üzerinden geçmesini zorunlu kılar.
# ==============================================================================

.read_repo_text_quiet_mcp_debug <- function(path) {
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

.extract_function_block <- function(txt, start_marker, end_marker) {
  start <- regexpr(start_marker, txt, fixed = TRUE, useBytes = TRUE)

  expect_true(
    as.integer(start[1]) > 0L,
    info = paste("Başlangıç işareti bulunamadı:", start_marker)
  )

  after_start <- substr(txt, start[1], nchar(txt, type = "bytes"))
  end <- regexpr(end_marker, after_start, fixed = TRUE, useBytes = TRUE)

  if (as.integer(end[1]) <= 0L) {
    return(after_start)
  }

  substr(after_start, 1L, end[1] - 1L)
}

test_that("MCP debug helper tanımlıdır ve env/option ile kapatılabilir", {
  txt <- .read_repo_text_quiet_mcp_debug("R/helpers_mcp_context.R")

  beklenenler <- c(
    "helpers_mcp_tools$mcp_debug_enabled <- function()",
    'Sys.getenv("MERGEN_MCP_DEBUG", "false")',
    'getOption("mergen.mcp.debug", FALSE)',
    "helpers_mcp_tools$mcp_debug_log <- function(...)",
    "log_debug(msg)"
  )

  bulunanlar <- vapply(
    beklenenler,
    function(x) grepl(x, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    info = paste("Eksik MCP debug helper kayıtları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
})

test_that("resolve_file_argument raw cat() ile konsola yazmaz", {
  tools_txt <- .read_repo_text_quiet_mcp_debug("R/helpers_mcp_tools.R")
  bootstrap_txt <- .read_repo_text_quiet_mcp_debug("R/helpers_mcp_bootstrap.R")
  resolver_txt <- .read_repo_text_quiet_mcp_debug("R/helpers_mcp_file_resolver.R")

  expect_true(
    grepl("R/helpers_mcp_bootstrap.R", tools_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_tools.R, izole source bağlamlarında MCP bootstrap dosyasını yüklemelidir."
  )

  expect_true(
    grepl("R/helpers_mcp_file_resolver.R", bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R, izole source bağlamlarında dosya çözümleyici helper dosyasını yüklemelidir."
  )

  block <- .extract_function_block(
    resolver_txt,
    "helpers_mcp_tools$resolve_file_argument <- function(arg, session = NULL)",
    ".mcp_file_resolver_fns <- c("
  )

  expect_false(
    grepl("cat\\s*\\(", block, perl = TRUE, useBytes = TRUE),
    info = "resolve_file_argument içinde raw cat() kalmamalı; helpers_mcp_tools$mcp_debug_log kullanılmalı."
  )

  expect_true(
    grepl("helpers_mcp_tools$mcp_debug_log(", block, fixed = TRUE, useBytes = TRUE),
    info = "resolve_file_argument debug mesajlarını mcp_debug_log üzerinden vermelidir."
  )
})