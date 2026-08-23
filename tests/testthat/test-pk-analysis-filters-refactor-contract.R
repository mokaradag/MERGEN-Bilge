# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-filters-refactor-contract.R
# Açıklama: Proje/Kaynak Analizi filtre yardımcılarının büyük modülden ayrıldığını,
#           kaynak sırasını ve durdurma sonrası eski LLM sonucunun uygulanmadığını
#           doğrular.
# ==============================================================================

.read_repo_text_pk_filters <- function(rel_path) {
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

.source_pk_filter_env <- function(call_local_llm_fn = NULL) {
  pk_env <- new.env(parent = globalenv())

  pk_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  pk_env$api_config <- list(local_models = c("test-filter-model"))

  pk_env$resolve_local_llm_credentials <- function(model) {
    list(default_api_key = "test-api-key")
  }

  pk_env$call_local_llm <- call_local_llm_fn %||% function(messages, options) {
    list(
      content = paste0(
        "{\"filters\":[{\"column\":\"Durum\",\"value\":\"1\",",
        "\"operation\":\"exact_match\"}],",
        "\"aggregation\":\"count\",\"group_column\":null}"
      )
    )
  }

  source(
    file.path(repo_root_for_tests, "R", "helpers_pk_analysis_core.R"),
    encoding = "UTF-8",
    local = pk_env
  )

  # İZOLE YÜKLEME: taban dosya manifest sırasına göre AÇIKÇA önce gelir.
  source(
    file.path(repo_root_for_tests, "R", "helpers_pk_analysis_filters_base.R"),
    encoding = "UTF-8",
    local = pk_env
  )

  source(
    file.path(repo_root_for_tests, "R", "helpers_pk_analysis_filters.R"),
    encoding = "UTF-8",
    local = pk_env
  )

  pk_env
}

test_that("helpers_pk_analysis_filters.R exists and exposes extracted public helpers", {
  helper_path <- file.path(repo_root_for_tests, "R", "helpers_pk_analysis_filters.R")

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_pk_analysis_filters.R dosyası eklenmelidir."
  )

  pk_env <- .source_pk_filter_env()

  expected_functions <- c(
    "extract_filter_criteria_from_prompt",
    "apply_smart_filters"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = pk_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik PK filtre helper: %s", fn)
    )
  }
})

test_that("runtime manifest sources PK filter helpers after core and before module", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_pk_analysis_core.R",
      "R/helpers_pk_analysis_filters.R",
      "R/module_proje_kaynak_analizi.R"
    ),
    label = "Kaynak sırası core -> filters -> module olmalıdır:"
  )
})

test_that("module_proje_kaynak_analizi.R no longer owns extracted filter helpers", {
  module_txt <- .read_repo_text_pk_filters("R/module_proje_kaynak_analizi.R")

  forbidden_inline_defs <- c(
    "extract_filter_criteria_from_prompt <- function",
    "apply_smart_filters <- function"
  )

  for (pattern in forbidden_inline_defs) {
    expect_false(
      grepl(pattern, module_txt, fixed = TRUE),
      info = sprintf("Bu helper artık R/helpers_pk_analysis_filters.R içinde olmalıdır: %s", pattern)
    )
  }

  expect_true(
    grepl("helpers_pk_analysis_filters.R", module_txt, fixed = TRUE),
    info = "module dosyası doğrudan source edildiğinde PK filter helper fallback'ini korumalıdır."
  )
})

test_that("apply_smart_filters keeps Turkish text, exact filters and aggregation behavior stable", {
  pk_env <- .source_pk_filter_env()

  sample_df <- data.frame(
    ProjeKodu = c("P1111", "P2222", "P3333"),
    MasrafYeri = c("Elektronik Tasarım Müdürlüğü", "Mekanik Tasarım", "Elektronik Tasarım Müdürlüğü"),
    Durum = c("1", "0", "1"),
    Butce = c(10, 20, 30),
    stringsAsFactors = FALSE
  )

  filtered <- pk_env$apply_smart_filters(
    sample_df,
    list(
      filters = list(list(
        column = "MasrafYeri",
        value = "elektronik tasarım",
        operation = "contains"
      )),
      aggregation = NULL,
      group_column = NULL
    ),
    "Elektronik Tasarım Müdürlüğündeki projeleri listele"
  )

  expect_equal(nrow(filtered), 2L)
  expect_true(all(filtered$MasrafYeri == "Elektronik Tasarım Müdürlüğü"))

  counted <- pk_env$apply_smart_filters(
    sample_df,
    list(
      filters = list(list(
        column = "Durum",
        value = "1",
        operation = "exact_match"
      )),
      aggregation = "count",
      group_column = NULL
    ),
    "Aktif projeler kaç tane?"
  )

  expect_equal(counted$Sonuc[1], "Filtrelenen Kayıt Sayısı")
  expect_equal(counted$Adet[1], 2L)

  grouped <- pk_env$apply_smart_filters(
    sample_df,
    list(
      filters = list(),
      aggregation = "group_by",
      group_column = "Durum"
    ),
    "Duruma göre dağılım"
  )

  expect_equal(sum(grouped$N), 3L)
})

test_that("extract_filter_criteria_from_prompt ignores stale LLM result when stop is raised after request", {
  stopped <- FALSE

  pk_env <- .source_pk_filter_env(call_local_llm_fn = function(messages, options) {
    stopped <<- TRUE
    list(
      content = paste0(
        "{\"filters\":[{\"column\":\"Durum\",\"value\":\"1\",",
        "\"operation\":\"exact_match\"}],",
        "\"aggregation\":\"count\",\"group_column\":null}"
      )
    )
  })

  result <- pk_env$extract_filter_criteria_from_prompt(
    user_prompt = "Aktif projeler kaç tane?",
    data_context = data.frame(Durum = c("1", "0"), stringsAsFactors = FALSE),
    available_columns = "Durum",
    conn = NULL,
    session = NULL,
    stop_check = function() stopped
  )

  expect_equal(result$filters, list())
  expect_null(result$aggregation)
})

test_that("helpers_pk_analysis_filters.R remains side-effect-light", {
  txt <- .read_repo_text_pk_filters("R/helpers_pk_analysis_filters.R")

  expect_false(
    grepl("observeEvent\\s*\\(|renderUI\\s*\\(|shiny::runApp", txt, perl = TRUE),
    info = "PK filter helper dosyası Shiny observer/render/runtime davranışı içermemelidir."
  )

  expect_false(
    grepl("dbConnect\\s*\\(|odbc::", txt, perl = TRUE),
    info = "PK filter helper dosyası canlı DB bağlantısı açmamalıdır."
  )
})