# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-analyze-visualize-refactor-contract.R
# Açıklama: MCP R-first analiz/görselleştirme aracının monolitten ayrıldığını
#           ve üretim log/debug sözleşmesini koruduğunu doğrular.
# ==============================================================================

.read_repo_text_quiet_mcp_analyze <- function(path) {
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

test_that("MCP analyze/visualize tool ayrı dosyada tutulur", {
  analyze_txt <- .read_repo_text_quiet_mcp_analyze("R/helpers_mcp_analyze_visualize.R")
  tools_txt <- .read_repo_text_quiet_mcp_analyze("R/helpers_mcp_tools.R")
  bootstrap_txt <- .read_repo_text_quiet_mcp_analyze("R/helpers_mcp_bootstrap.R")
  global_txt <- .read_repo_text_quiet_mcp_analyze("global.R")

  expect_true(
    grepl("helpers_mcp_tools\\$analyze_and_visualize <-", analyze_txt, perl = TRUE, useBytes = TRUE),
    info = "analyze_and_visualize tanımı R/helpers_mcp_analyze_visualize.R içinde olmalıdır."
  )

  expect_false(
    grepl("helpers_mcp_tools\\$analyze_and_visualize <- function", tools_txt, perl = TRUE, useBytes = TRUE),
    info = "analyze_and_visualize fonksiyonu helpers_mcp_tools.R içine geri taşınmamalıdır."
  )

  expect_true(
    grepl("R/helpers_mcp_analyze_visualize.R", bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_bootstrap.R analyze/visualize helper dosyasını izole/worker bağlamında yüklemelidir."
  )

  expect_true(
    grepl("\"analyze_and_visualize\"", bootstrap_txt, fixed = TRUE, useBytes = TRUE),
    info = "mcp_tools_bootstrap_ready() analyze_and_visualize public fonksiyonunu doğrulamalıdır."
  )

  expect_true(
    grepl('safe_source("R/helpers_mcp_analyze_visualize.R"', global_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_mcp_analyze_visualize.R global.R manifestinde açıkça yüklenmelidir."
  )
})

test_that("MCP analyze/visualize tool raw SMART_MATCH cat çıktısı üretmez", {
  analyze_txt <- .read_repo_text_quiet_mcp_analyze("R/helpers_mcp_analyze_visualize.R")

  expect_true(
    grepl("mcp_debug_log", analyze_txt, fixed = TRUE, useBytes = TRUE),
    info = "Analyze/visualize smart-match debug çıktıları mcp_debug_log üzerinden geçmelidir."
  )

  expect_false(
    grepl("cat(\"[SMART_MATCH", analyze_txt, fixed = TRUE, useBytes = TRUE),
    info = "Analyze/visualize içinde raw cat(\"[SMART_MATCH ...\") debug çıktısı olmamalıdır."
  )

  expect_false(
    grepl("cat('[SMART_MATCH", analyze_txt, fixed = TRUE, useBytes = TRUE),
    info = "Analyze/visualize içinde raw cat('[SMART_MATCH ...') debug çıktısı olmamalıdır."
  )
})

test_that("MCP analyze/visualize helper kaynak sırası chart aracından sonra ChartLab'den önce gelir", {
  global_txt <- .read_repo_text_quiet_mcp_analyze("global.R")
  lines <- strsplit(global_txt, "\n", fixed = TRUE)[[1]]

  pos <- function(needle) {
    hit <- grep(needle, lines, fixed = TRUE, useBytes = TRUE)
    if (length(hit) == 0L) return(NA_integer_)
    hit[1]
  }

  basic_pos <- pos('safe_source("R/helpers_mcp_basic_tools.R"')
  chart_pos <- pos('safe_source("R/helpers_mcp_chart_tools.R"')
  analyze_pos <- pos('safe_source("R/helpers_mcp_analyze_visualize.R"')
  chartlab_pos <- pos('safe_source("R/helpers_chartlab.R"')

  expect_false(is.na(basic_pos), info = "helpers_mcp_basic_tools.R manifestte olmalıdır.")
  expect_false(is.na(chart_pos), info = "helpers_mcp_chart_tools.R manifestte olmalıdır.")
  expect_false(is.na(analyze_pos), info = "helpers_mcp_analyze_visualize.R manifestte olmalıdır.")
  expect_false(is.na(chartlab_pos), info = "helpers_chartlab.R manifestte olmalıdır.")

  expect_lt(basic_pos, chart_pos)
  expect_lt(chart_pos, analyze_pos)
  expect_lt(analyze_pos, chartlab_pos)
})