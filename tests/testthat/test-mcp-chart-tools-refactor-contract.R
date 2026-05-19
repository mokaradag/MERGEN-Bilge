# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-chart-tools-refactor-contract.R
# Açıklama: MCP grafik aracının helpers_mcp_tools monolitinden ayrıldığını ve
#           kaynak/bootstrap sözleşmesinin korunduğunu doğrular.
# ==============================================================================

.read_repo_text_quiet_mcp_chart <- function(path) {
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

test_that("MCP chart tool ayrı dosyada tutulur", {
  chart_txt <- .read_repo_text_quiet_mcp_chart("R/helpers_mcp_chart_tools.R")
  tools_txt <- .read_repo_text_quiet_mcp_chart("R/helpers_mcp_tools.R")

  expect_true(
    grepl("helpers_mcp_tools\\$prepare_chart_data <-", chart_txt, perl = TRUE, useBytes = TRUE),
    info = "prepare_chart_data tanımı R/helpers_mcp_chart_tools.R içinde olmalıdır."
  )

  expect_false(
    grepl("helpers_mcp_tools\\$prepare_chart_data <- function", tools_txt, perl = TRUE, useBytes = TRUE),
    info = "prepare_chart_data fonksiyonu helpers_mcp_tools.R içine geri taşınmamalıdır."
  )

  expect_source_manifest_contains_for_tests(
    "R/helpers_mcp_chart_tools.R",
    label = "helpers_mcp_chart_tools.R runtime manifestinde açıkça yüklenmelidir:"
  )
})

test_that("MCP chart tool üretim loglarını raw cat ile kirletmez", {
  chart_txt <- .read_repo_text_quiet_mcp_chart("R/helpers_mcp_chart_tools.R")

  expect_true(
    grepl("mcp_debug_log", chart_txt, fixed = TRUE, useBytes = TRUE),
    info = "Chart tool debug çıktıları mcp_debug_log üzerinden geçmelidir."
  )

  expect_false(
    grepl("cat(\"[CHART", chart_txt, fixed = TRUE, useBytes = TRUE),
    info = "Chart tool içinde raw cat('[CHART ...') debug çıktısı olmamalıdır."
  )

  expect_false(
    grepl("cat(\"[CHART_SMART_MATCH", chart_txt, fixed = TRUE, useBytes = TRUE),
    info = "Chart smart-match debug çıktısı raw cat ile yazılmamalıdır."
  )
})

test_that("MCP chart helper source sırası temel araçlardan sonra ChartLab'den önce gelir", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_mcp_basic_tools.R",
      "R/helpers_mcp_chart_tools.R",
      "R/helpers_chartlab_spec.R",
      "R/helpers_chartlab.R"
    ),
    label = "MCP chart helper source sırası bozulmuş:"
  )
})