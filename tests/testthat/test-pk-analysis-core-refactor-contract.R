# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-core-refactor-contract.R
# Açıklama: Proje/Kaynak Analizi saf yardımcılarının module dosyasından ayrıldığını,
#           global.R kaynak sırasının doğru olduğunu ve yardımcıların temel
#           davranışlarının korunduğunu doğrular.
# ==============================================================================

.read_repo_text_pk_core <- function(rel_path) {
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

test_that("helpers_pk_analysis_core.R exists and exposes the extracted helpers", {
  helper_path <- file.path(repo_root_for_tests, "R", "helpers_pk_analysis_core.R")

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_pk_analysis_core.R dosyası eklenmelidir."
  )

  pk_env <- new.env(parent = globalenv())
  source(helper_path, encoding = "UTF-8", local = pk_env)

  expected_functions <- c(
    "summarize_columns_for_ai",
    "convert_date_columns",
    "normalize_pk_text_utf8",
    "normalize_pk_dataframe_utf8",
    "execute_pk_sql_unicode",
    "normalize_sql_server_identifiers"
  )

  for (fn in expected_functions) {
    expect_true(
      exists(fn, envir = pk_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik PK core helper: %s", fn)
    )
  }

  expect_true(
    exists("MAX_ANALYSIS_PROMPT_CHARS", envir = pk_env, inherits = FALSE),
    info = "MAX_ANALYSIS_PROMPT_CHARS yeni helper dosyasında tanımlı kalmalıdır."
  )

  expect_equal(
    get("MAX_ANALYSIS_PROMPT_CHARS", envir = pk_env),
    150000
  )
})

test_that("PK core helper behavior remains stable for summaries, dates and SQL identifiers", {
  pk_env <- new.env(parent = globalenv())
  source(
    file.path(repo_root_for_tests, "R", "helpers_pk_analysis_core.R"),
    encoding = "UTF-8",
    local = pk_env
  )

  sample_df <- data.frame(
    Sayisal = c(1, 2, NA, 4),
    Kategori = c("B", "A", "B", NA),
    Tarih = as.Date(c("2024-01-01", "2024-01-02", NA, "2024-01-04")),
    stringsAsFactors = FALSE
  )

  summary_text <- pk_env$summarize_columns_for_ai(sample_df)

  expect_match(summary_text, "Sayisal", fixed = TRUE)
  expect_match(summary_text, "Ort:", fixed = TRUE)
  expect_match(summary_text, "Kategori", fixed = TRUE)
  expect_match(summary_text, "Tarih", fixed = TRUE)

  date_df <- data.frame(
    Baslangic = c("01.02.2024", "02.02.2024", "hatalı"),
    stringsAsFactors = FALSE
  )

  converted <- pk_env$convert_date_columns(date_df, "Baslangic")
  expect_s3_class(converted$Baslangic, "Date")
  expect_equal(
    as.character(converted$Baslangic[1]),
    "2024-02-01"
  )

  turkish_text <- "İş Dağılım Ağacı"
  normalized <- pk_env$normalize_pk_text_utf8(turkish_text)
  expect_equal(enc2utf8(normalized), enc2utf8(turkish_text))

  sql <- "SELECT [Adı Soyadı], [Aktivite Türü] FROM dbo.Test"
  fixed_sql <- pk_env$normalize_sql_server_identifiers(sql)

  expect_match(fixed_sql, "SET QUOTED_IDENTIFIER ON;", fixed = TRUE)
  expect_match(fixed_sql, "\"Adı Soyadı\"", fixed = TRUE)
  expect_match(fixed_sql, "\"Aktivite Türü\"", fixed = TRUE)
})

test_that("global.R sources PK core before module_proje_kaynak_analizi.R", {
  global_txt <- .read_repo_text_pk_core("global.R")

  helper_pattern <- 'safe_source("R/helpers_pk_analysis_core.R"'
  module_pattern <- 'safe_source("R/module_proje_kaynak_analizi.R"'

  helper_pos <- regexpr(helper_pattern, global_txt, fixed = TRUE)[1]
  module_pos <- regexpr(module_pattern, global_txt, fixed = TRUE)[1]

	expect_true(
	  helper_pos > 0,
	  info = "global.R içinde R/helpers_pk_analysis_core.R source edilmelidir."
	)

	expect_true(
	  module_pos > 0,
	  info = "global.R içinde R/module_proje_kaynak_analizi.R source edilmelidir."
	)

	expect_true(
	  helper_pos < module_pos,
	  info = "PK core helper, module_proje_kaynak_analizi.R dosyasından önce yüklenmelidir."
	)
})

test_that("module_proje_kaynak_analizi.R no longer owns extracted pure helpers", {
  module_txt <- .read_repo_text_pk_core("R/module_proje_kaynak_analizi.R")

  forbidden_inline_defs <- c(
    "summarize_columns_for_ai <- function",
    "convert_date_columns <- function",
    "normalize_pk_text_utf8 <- function",
    "normalize_pk_dataframe_utf8 <- function",
    "execute_pk_sql_unicode <- function",
    "normalize_sql_server_identifiers <- function"
  )

  for (pattern in forbidden_inline_defs) {
    expect_false(
      grepl(pattern, module_txt, fixed = TRUE),
      info = sprintf(
        "Bu helper artık R/helpers_pk_analysis_core.R içinde olmalıdır: %s",
        pattern
      )
    )
  }

  expect_true(
    grepl("helpers_pk_analysis_core.R", module_txt, fixed = TRUE),
    info = "module dosyası doğrudan source edildiğinde PK core helper fallback'ini korumalıdır."
  )
})