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
  bootstrap_txt <- .read_repo_text_quiet_mcp_chart("R/helpers_mcp_bootstrap.R")
  global_txt <- .read_repo_text_quiet_mcp_chart("global.R")

  expect_true(
    grepl("helpers_mcp_tools\\$prepare_chart_data <-", chart_txt, perl = TRUE, useBytes = TRUE),
    info = "prepare_chart_data tanımı R/helpers_mcp_chart_tools.R içinde olmalıdır."
  )

  expect_false(
    grepl("helpers_mcp_tools\\$prepare_chart_data <- function", tools_txt, perl = TRUE, useBytes = TRUE),
    info = "prepare_chart_data fonksiyonu helpers_mcp_tools.R içine geri taşınmamalıdır."
  )

  expect_true(
    grepl("R/helpers_mcp_chart_tools.R", bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R chart helper dosyasını izole/worker bağlamında yüklemelidir."
  )

  expect_true(
    grepl('safe_source("R/helpers_mcp_chart_tools.R"', global_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_chart_tools.R global.R manifestinde açıkça yüklenmelidir."
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
  global_txt <- .read_repo_text_quiet_mcp_chart("global.R")
  lines <- strsplit(global_txt, "\n", fixed = TRUE)[[1]]

  pos <- function(needle) {
    hit <- grep(needle, lines, fixed = TRUE, useBytes = TRUE)
    if (length(hit) == 0L) return(NA_integer_)
    hit[1]
  }

  basic_pos <- pos('safe_source("R/helpers_mcp_basic_tools.R"')
  chart_pos <- pos('safe_source("R/helpers_mcp_chart_tools.R"')
  chartlab_pos <- pos('safe_source("R/helpers_chartlab.R"')

  expect_false(is.na(basic_pos), info = "helpers_mcp_basic_tools.R manifestte olmalıdır.")
  expect_false(is.na(chart_pos), info = "helpers_mcp_chart_tools.R manifestte olmalıdır.")
  expect_false(is.na(chartlab_pos), info = "helpers_chartlab.R manifestte olmalıdır.")

  expect_lt(basic_pos, chart_pos)
  expect_lt(chart_pos, chartlab_pos)
})