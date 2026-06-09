# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-query-selection-refactor-contract.R
# Açıklama: Proje/Kaynak Analizi "Akıllı Sorgu Seçici" sezgisel skorlama ve skor
#           tablosu yardımcılarının büyük modülden ayrıldığını, kaynak sırasını ve
#           modülün artık taşınan helper'ları içermediğini doğrular.
# ==============================================================================

.read_repo_text_pk_qsel <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(abs_path, open = "rb")
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

.source_pk_qsel_env <- function() {
  pk_env <- new.env(parent = globalenv())

  pk_env$`%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0) y else x
  }

  source(
    file.path(repo_root_for_tests, "R", "helpers_pk_analysis_query_selection.R"),
    encoding = "UTF-8",
    local = pk_env
  )

  pk_env
}

test_that("helpers_pk_analysis_query_selection.R exists and exposes extracted helpers", {
  helper_path <- file.path(
    repo_root_for_tests, "R", "helpers_pk_analysis_query_selection.R"
  )

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_pk_analysis_query_selection.R dosyası eklenmelidir."
  )

  pk_env <- .source_pk_qsel_env()

  expected_functions <- c(
    "pk_init_query_score_table",
    "pk_score_query_relevance",
    "pk_compute_heuristic_query_scores",
    "print_score_table"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = pk_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik PK sorgu-seçimi helper: %s", fn)
    )
  }
})

test_that("runtime manifest sources query-selection helper after filters and before module", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_pk_analysis_filters.R",
      "R/helpers_pk_analysis_query_selection.R",
      "R/module_proje_kaynak_analizi.R"
    ),
    label = "Kaynak sırası filters -> query_selection -> module olmalıdır:"
  )
})

test_that("module_proje_kaynak_analizi.R no longer owns extracted query-selection helpers", {
  module_txt <- .read_repo_text_pk_qsel("R/module_proje_kaynak_analizi.R")

  forbidden_inline_defs <- c(
    "print_score_table <- function",
    "pk_init_query_score_table <- function",
    "pk_score_query_relevance <- function",
    "pk_compute_heuristic_query_scores <- function"
  )

  for (pattern in forbidden_inline_defs) {
    expect_false(
      grepl(pattern, module_txt, fixed = TRUE),
      info = sprintf(
        "Bu helper artık R/helpers_pk_analysis_query_selection.R içinde olmalıdır: %s",
        pattern
      )
    )
  }

  expect_true(
    grepl("helpers_pk_analysis_query_selection.R", module_txt, fixed = TRUE),
    info = paste(
      "module dosyası doğrudan source edildiğinde PK sorgu-seçimi helper",
      "fallback'ini korumalıdır."
    )
  )

  # select_smart_query orkestratörü modülde kalmalı (helper'a taşınmamalı).
  expect_true(
    grepl("select_smart_query <- function", module_txt, fixed = TRUE),
    info = "select_smart_query orkestratörü modülde kalmalıdır."
  )
})

test_that("helpers_pk_analysis_query_selection.R remains side-effect-light", {
  txt <- .read_repo_text_pk_qsel("R/helpers_pk_analysis_query_selection.R")

  expect_false(
    grepl("observeEvent\\s*\\(|renderUI\\s*\\(|shiny::runApp", txt, perl = TRUE),
    info = "PK sorgu-seçimi helper dosyası Shiny observer/render/runtime içermemelidir."
  )

  expect_false(
    grepl("dbConnect\\s*\\(|odbc::", txt, perl = TRUE),
    info = "PK sorgu-seçimi helper dosyası canlı DB bağlantısı açmamalıdır."
  )

  expect_false(
    grepl("call_local_llm\\s*\\(", txt, perl = TRUE),
    info = "PK sorgu-seçimi helper dosyası LLM çağrısı başlatmamalıdır."
  )
})
