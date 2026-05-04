# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-security-summary-contract.R
# Açıklama: Proje/Kaynak Analizi RLS/özet helper extraction ve SSO readiness
#           sözleşmelerini doğrular. Canlı DB veya Shiny app başlatmaz.
# ==============================================================================

.pk_read_repo_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

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

.pk_extract_safe_source_paths <- function(text) {
  m <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, m)[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) {
    return(character(0))
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

.pk_count_file_functions <- function(text) {
  # Maintainability contract for extracted helper files should count public /
  # top-level assigned helper functions, not local anonymous callbacks inside
  # lapply/vapply or nested implementation details.
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]

  hits <- grepl(
    "^[[:alnum:]_\\.]+\\s*<-\\s*function\\s*\\(",
    lines,
    perl = TRUE,
    useBytes = TRUE
  )

  sum(hits)
}

.pk_load_security_summary_helper <- function() {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  helper_env$`%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0L) {
      return(y)
    }
    if (length(x) == 1L && is.na(x)) {
      return(y)
    }
    x
  }

  source(
    file.path(repo_root, "R", "helpers_pk_analysis_core.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  source(
    file.path(repo_root, "R", "helpers_pk_analysis_security_summary.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  helper_env
}

test_that("Proje/Kaynak Analizi security-summary helper global.R içinde doğru sırada yüklenir", {
  global_text <- .pk_read_repo_text("global.R")
  paths <- .pk_extract_safe_source_paths(global_text)

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/helpers_pk_analysis_core.R")))
  expect_false(is.na(pos("R/helpers_pk_analysis_security_summary.R")))
  expect_false(is.na(pos("R/helpers_pk_analysis_filters.R")))
  expect_false(is.na(pos("R/module_proje_kaynak_analizi.R")))

  expect_lt(
    pos("R/helpers_pk_analysis_core.R"),
    pos("R/helpers_pk_analysis_security_summary.R")
  )

  expect_lt(
    pos("R/helpers_pk_analysis_security_summary.R"),
    pos("R/helpers_pk_analysis_filters.R")
  )

  expect_lt(
    pos("R/helpers_pk_analysis_security_summary.R"),
    pos("R/module_proje_kaynak_analizi.R")
  )
})

test_that("Proje/Kaynak Analizi helper extraction maintainability kazanımı korunur", {
  module_text <- .pk_read_repo_text("R/module_proje_kaynak_analizi.R")
  helper_text <- .pk_read_repo_text("R/helpers_pk_analysis_security_summary.R")

  module_lines <- length(strsplit(module_text, "\n", fixed = TRUE)[[1]])
  helper_lines <- length(strsplit(helper_text, "\n", fixed = TRUE)[[1]])
  helper_functions <- .pk_count_file_functions(helper_text)

  expect_true(
    module_lines <= 799L,
    info = sprintf(
      "R/module_proje_kaynak_analizi.R RLS/özet extraction sonrası 800 satır altı kalmalıdır: %d > 799.",
      module_lines
    )
  )

  expect_true(
    helper_lines <= 400L,
    info = sprintf(
      "R/helpers_pk_analysis_security_summary.R küçük helper dosyası olarak kalmalıdır: %d > 400.",
      helper_lines
    )
  )

  expect_true(
    helper_functions <= 5L,
    info = sprintf(
      "R/helpers_pk_analysis_security_summary.R fonksiyon sayısı kontrollü kalmalıdır: %d > 5.",
      helper_functions
    )
  )
})

test_that("resolve_pk_analysis_username SSO hazır değilken Unknown ile RLS'e düşmez", {
  helper_env <- .pk_load_security_summary_helper()

  session <- list(userData = new.env(parent = emptyenv()))
  session$userData$sso_active <- TRUE
  session$userData$auth_initialized <- FALSE

  result <- helper_env$resolve_pk_analysis_username(session)

  expect_false(result$ready)
  expect_equal(result$username, "Unknown")
  expect_equal(result$reason, "auth_not_ready")

  session$userData$auth_initialized <- TRUE
  session$userData$system_username <- "deneme.kullanici"

  result_ready <- helper_env$resolve_pk_analysis_username(session)

  expect_true(result_ready$ready)
  expect_equal(result_ready$username, "deneme.kullanici")
  expect_null(result_ready$reason)
})

test_that("apply_rls_to_data rol ve kolon sözleşmesini korur", {
  helper_env <- .pk_load_security_summary_helper()

  sample_data <- data.frame(
    MasrafYeri = c("A", "B", "A"),
    ProjeKodu = c("P1", "P2", "P3"),
    EPSKodu = c("E1", "E1", "E2"),
    Deger = c(10, 20, 30),
    stringsAsFactors = FALSE
  )

  rls_cols <- list(
    masraf_yeri_col = "MasrafYeri",
    proje_kodu_col = "ProjeKodu",
    eps_kodu_col = "EPSKodu"
  )

  admin_data <- helper_env$apply_rls_to_data(
    sample_data,
    user_info = list(Yetki = "ADMIN"),
    rls_cols = rls_cols
  )

  expect_equal(nrow(admin_data), 3L)

  py_data <- helper_env$apply_rls_to_data(
    sample_data,
    user_info = list(
      Yetki = "PY",
      allowed_depts = "A",
      allowed_projects = "P3"
    ),
    rls_cols = rls_cols
  )

  expect_equal(nrow(py_data), 1L)
  expect_equal(py_data$ProjeKodu, "P3")

  eps_data <- helper_env$apply_rls_to_data(
    sample_data,
    user_info = list(
      Yetki = "KY-P",
      allowed_depts = NULL,
      allowed_eps = "E1"
    ),
    rls_cols = rls_cols
  )

  expect_equal(nrow(eps_data), 2L)
  expect_true(all(eps_data$EPSKodu == "E1"))
})

test_that("generate_statistical_summary filtre ve pre-aggregated uyarılarını korur", {
  helper_env <- .pk_load_security_summary_helper()

  sample_data <- data.frame(
    Proje = c("Alfa", "Beta", "Alfa"),
    Saat = c(10, 20, 30),
    ToplamSaat = c(100, 100, 100),
    Tarih = as.Date(c("2024-01-01", "2024-01-02", "2024-01-03")),
    stringsAsFactors = FALSE
  )

  result <- helper_env$generate_statistical_summary(
    sample_data,
    rls_total_rows = 5,
    user_filter_applied = TRUE,
    pre_aggregated_columns = "ToplamSaat"
  )

  expect_equal(result$row_count, 3L)
  expect_equal(nrow(result$preview_data), 3L)
  expect_true(grepl("FİLTRELEME UYARISI", result$summary_text, fixed = TRUE))
  expect_true(grepl("ÖNCEDEN TOPLULAŞTIRILMIŞ SÜTUN UYARISI", result$summary_text, fixed = TRUE))
  expect_true(grepl("SAYISAL SUTUNLAR OZETI", result$summary_text, fixed = TRUE))
})