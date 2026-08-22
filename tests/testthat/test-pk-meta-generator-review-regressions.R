# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-meta-generator-review-regressions.R
# Açıklama: Regresyon testleri, tamamen cevrimdisidir; gercek DB/ODBC/LLM
#			gerektirmez.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  for (dosya in c(
    "helpers_pk_ascii_tokens.R",
    "helpers_pk_text_turkish.R",
    "helpers_pk_config.R",
    "helpers_pk_query_meta_schema.R",
    "helpers_pk_query_meta_access.R",
    "helpers_pk_query_meta.R",
    "helpers_pk_sql_statements.R", "helpers_pk_sql_readonly.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }

  for (dosya in c(
    "helpers_meta_generator_config.R",
    "helpers_meta_generator_schema.R",
    "helpers_meta_generator_render.R",
    "helpers_meta_generator_redact.R",
    "helpers_meta_generator_findings.R",
    "helpers_meta_generator_health.R",
    "helpers_meta_generator_state.R",
    "helpers_meta_generator_db.R",
    "helpers_meta_generator_fetch.R",
    "helpers_meta_generator_run.R",
    "helpers_meta_generator_lock.R",
    "helpers_meta_generator_commit.R"
  )) {
    source(file.path(repo_root, "tools", "pk", dosya), encoding = "UTF-8", local = globalenv())
  }
})

.pk711_cfg <- function(mode = "describe") {
  list(
    mode = mode,
    sql_timeout_sec = 5,
    sample_rows = 10L,
    max_result_mb = 1,
    sample_unicode = TRUE,
    high_cardinality_threshold = 100L
  )
}

.pk711_descriptor <- function(name, type, max_length = 50) {
  list(list(name = name, system_type_name = type, max_length = max_length))
}

test_that("declared date_columns are applied to the effective schema", {
  query <- list(
    id = "q_date",
    name = "date conversion",
    db_target = "primary",
    sql = "SELECT Tarih FROM T",
    date_columns = "Tarih"
  )

  sonuc <- pkgn_fetch_schema(
    query = query,
    config = .pk711_cfg("describe"),
    conn = TRUE,
    describe_fn = function(conn, sql, timeout_sec = NULL) {
      .pk711_descriptor("Tarih", "varchar(10)", 10)
    },
    sample_fn = function(...) stop("sample should not run")
  )

  expect_true(sonuc$ok)
  expect_identical(sonuc$schema[["Tarih"]], "Date")
  # Native evidence remains native; only the runtime-effective R schema changes.
  expect_match(sonuc$source_types[["Tarih"]], "varchar", ignore.case = TRUE)
})

test_that("date and sample-safety policy changes invalidate stale fingerprints", {
  query <- list(
    id = "q_fp",
    db_target = "primary",
    sql = "SELECT Tarih FROM T",
    date_columns = "Tarih",
    meta_sample_safe = FALSE
  )

  kaynak_once <- pkgh_source_fingerprint(query)
  durum_once <- pkgh_state_fingerprint(query, .pk711_cfg("sample"))

  query$date_columns <- "BaskaTarih"
  expect_false(identical(pkgh_source_fingerprint(query), kaynak_once))

  query$date_columns <- "Tarih"
  query$meta_sample_safe <- TRUE
  expect_false(identical(pkgh_state_fingerprint(query, .pk711_cfg("sample")), durum_once))
})

test_that("production sample mode fails closed without explicit safe curation", {
  query <- list(
    id = "q_unsafe",
    name = "unsafe sample",
    db_target = "primary",
    sql = "SELECT * FROM VeryLargeTable"
  )

  sonuc <- pkgn_fetch_schema(
    query = query,
    config = .pk711_cfg("sample"),
    conn = TRUE,
    describe_fn = function(conn, sql, timeout_sec = NULL) NULL,
    sample_fn = pkg_default_sample_fn
  )

  expect_false(sonuc$ok)
  expect_identical(sonuc$code, "sample_not_server_bounded")

  query$meta_sample_safe <- TRUE
  expect_true(.pkgn_default_sample_is_explicitly_safe(query, pkg_default_sample_fn))
})

test_that("unsafe sample refusal counts as a schema failure", {
  query <- list(id = "q_unsafe", name = "unsafe sample", db_target = "primary")
  kayit <- pkgh_query_record(
    query, "failed", "sample",
    findings = list(pkgh_finding(
      "sample_not_server_bounded", "attention", "sample execution refused"
    ))
  )

  expect_true(kayit$schema_failure)
  expect_true(kayit$tier0)
})

test_that("metadata and health replacement fallbacks never copy over live files", {
  render_kod <- paste(deparse(body(.pkgr_replace_with_backup)), collapse = "\n")
  health_kod <- paste(c(
    deparse(body(.pkgh_replace_with_backup)),
    deparse(body(.pkgh_atomic_write_bytes))
  ), collapse = "\n")

  expect_false(grepl("file.copy", render_kod, fixed = TRUE))
  expect_false(grepl("file.copy", health_kod, fixed = TRUE))
  expect_true(grepl("file.rename", render_kod, fixed = TRUE))
  expect_true(grepl("file.rename", health_kod, fixed = TRUE))
})

test_that("run-lock release restores bootstrap-mutated process state", {
  eski_option <- getOption("pk711.process.state", NULL)
  eski_log <- Sys.getenv("MERGEN_LOG_DIR", unset = NA_character_)
  on.exit({
    options(pk711.process.state = eski_option)
    if (is.na(eski_log)) Sys.unsetenv("MERGEN_LOG_DIR") else Sys.setenv(MERGEN_LOG_DIR = eski_log)
  }, add = TRUE)

  options(pk711.process.state = "before")
  Sys.setenv(MERGEN_LOG_DIR = "before")

  lock_path <- file.path(tempdir(), paste0("pk711-lock-", Sys.getpid(), "-", sample.int(1e6, 1)))
  kilit <- pkgc_acquire_run_lock(lock_path, stale_sec = 3600)
  expect_true(kilit$ok)

  options(pk711.process.state = "after")
  options(pk711.added.by.bootstrap = TRUE)
  Sys.setenv(MERGEN_LOG_DIR = "after")

  expect_true(pkgc_release_run_lock(kilit))
  expect_identical(getOption("pk711.process.state"), "before")
  expect_null(getOption("pk711.added.by.bootstrap", NULL))
  expect_identical(Sys.getenv("MERGEN_LOG_DIR", unset = NA_character_), "before")
})
