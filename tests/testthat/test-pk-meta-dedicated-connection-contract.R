# ==============================================================================
# Faz 3b metadata DB izolasyonu ve NOCOUNT descriptor uyumlulugu regresyonlari.
# Gercek DB/ODBC baglantisi acmaz.
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
    "helpers_pk_sql_readonly.R"
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
    "helpers_meta_generator_db.R"
  )) {
    source(file.path(repo_root, "tools", "pk", dosya), encoding = "UTF-8", local = globalenv())
  }
})

test_that("descriptor yalniz onayli SET NOCOUNT ON onekini kaldirir", {
  sql <- paste0(
    "/* baslik */\r\n",
    "-- aciklama\r\n",
    "SET NOCOUNT ON;\r\n",
    "WITH c AS (SELECT 1 AS a) SELECT * FROM c OPTION (RECOMPILE);"
  )

  sonuc <- .pkgd_descriptor_sql(sql)
  expect_false(grepl("NOCOUNT", sonuc, ignore.case = TRUE))
  expect_true(grepl("^WITH", trimws(sonuc), ignore.case = TRUE))
  expect_true(grepl("OPTION \\(RECOMPILE\\)", sonuc, ignore.case = TRUE))
})

test_that("descriptor normalizasyonu read-only kapisini atlayamaz", {
  guvensiz <- c(
    "SET NOCOUNT OFF; SELECT 1",
    "SET ANSI_NULLS ON; SELECT 1",
    "SET NOCOUNT ON; DELETE FROM t",
    "SET NOCOUNT ON; SELECT 1; SELECT 2",
    "SET NOCOUNT ON; EXEC dbo.p"
  )

  for (sql in guvensiz) {
    expect_identical(.pkgd_descriptor_sql(sql), sql)
  }
})

test_that("metadata default connection uygulama poolunu devralmaz", {
  govde <- paste(deparse(body(pkg_default_connect_fn)), collapse = "\n")

  expect_true(grepl("DBI::dbConnect", govde, fixed = TRUE))
  expect_true(grepl("odbc::odbc", govde, fixed = TRUE))
  expect_false(grepl("get_connection", govde, fixed = TRUE))
  expect_false(grepl("db_acquire_tx_connection", govde, fixed = TRUE))
})

test_that("metadata dedicated connection kendi fiziksel baglantisini kapatir", {
  govde <- paste(deparse(body(pkg_default_release_fn)), collapse = "\n")

  expect_true(grepl("pkg_meta_dedicated", govde, fixed = TRUE))
  expect_true(grepl("DBI::dbDisconnect", govde, fixed = TRUE))
})
