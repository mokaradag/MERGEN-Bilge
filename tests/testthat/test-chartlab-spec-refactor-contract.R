# ==============================================================================
# Dosya Yolu: tests/testthat/test-chartlab-spec-refactor-contract.R
# Açıklama: ChartLab saf spec/mapping/agregasyon yardımcılarının helpers_chartlab.R
#           dışına ayrıldığını ve davranış sözleşmesini koruduğunu doğrular.
# ==============================================================================

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }
}

.chartlab_refactor_repo_root <- function() {
  if (exists("resolve_repo_root_for_tests", mode = "function")) {
    return(resolve_repo_root_for_tests())
  }

  candidates <- c(".", "..", "../..")

  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_chartlab_refactor_text <- function(path) {
  full_path <- file.path(.chartlab_refactor_repo_root(), path)
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

.source_chartlab_spec_for_contract <- function() {
  source(
    file.path(.chartlab_refactor_repo_root(), "R", "helpers_chartlab_spec.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

test_that("ChartLab spec helper ayrı ve küçük dosyada tutulur", {
  helper_txt <- .read_chartlab_refactor_text("R/helpers_chartlab_spec.R")
  chartlab_txt <- .read_chartlab_refactor_text("R/helpers_chartlab.R")

  expect_true(
    grepl("chartlab_auto_guess_spec <- function", helper_txt, fixed = TRUE),
    info = "chartlab_auto_guess_spec R/helpers_chartlab_spec.R içinde olmalıdır."
  )

  expect_true(
    grepl("chartlab_aggregate_values <- function", helper_txt, fixed = TRUE),
    info = "chartlab_aggregate_values R/helpers_chartlab_spec.R içinde olmalıdır."
  )

  expect_false(
    grepl("auto_guess <- function", chartlab_txt, fixed = TRUE),
    info = "wire_chart_output() içinde inline auto_guess helper'ı geri büyümemelidir."
  )

  expect_false(
    grepl("normalize_chart_type <- function", chartlab_txt, fixed = TRUE),
    info = "Chart type normalizasyonu helpers_chartlab.R içine geri taşınmamalıdır."
  )
})

test_that("ChartLab helper Türkçe alias ve geçersiz mapping davranışını korur", {
  .source_chartlab_spec_for_contract()

  df <- data.frame(
    Tarih = as.Date(c("2026-01-01", "2026-01-02")),
    Deger = c(10, 20),
    Grup = c("A", "B"),
    stringsAsFactors = FALSE
  )

  spec <- list(
    type = "çizgi grafiği",
    data = df,
    mapping = list(x = "YOK", y = "Deger", group = "Grup"),
    params = list()
  )

  guessed <- chartlab_auto_guess_spec(spec)

  expect_identical(guessed$type, "line")
  expect_identical(guessed$mapping$x, "Tarih")
  expect_identical(guessed$mapping$y, "Deger")
  expect_identical(guessed$mapping$group, "Grup")
})

test_that("ChartLab agregasyon helper'ı mevcut motor davranışını korur", {
  .source_chartlab_spec_for_contract()

  values <- c(1, 2, NA, 4)

  expect_equal(chartlab_aggregate_values(values, "sum"), 7)
  expect_equal(chartlab_aggregate_values(values, "mean"), mean(values, na.rm = TRUE))
  expect_equal(chartlab_aggregate_values(values, "median"), stats::median(values, na.rm = TRUE))
  expect_equal(chartlab_aggregate_values(values, "min"), 1)
  expect_equal(chartlab_aggregate_values(values, "max"), 4)
  expect_equal(chartlab_aggregate_values(values, "count"), 3)
  expect_equal(chartlab_aggregate_values(values, "bilinmeyen"), 7)
})