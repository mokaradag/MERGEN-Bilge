# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-duckdb-sandbox-behavior.R
# Açıklama: MCP SQL/grafik araçlarının kullandığı DuckDB bağlantısının
#           SERTLEŞTİRİLMİŞ olduğunu doğrular. sql / filter_sql metinleri
#           LLM kontrollüdür; harici erişim kapatılmazsa read_csv_auto,
#           read_parquet, ATTACH, COPY ... TO ve INSTALL/LOAD ile sunucu
#           dosyaları okunabilir/yazılabilirdi. Gerçek dosya sistemine yazma
#           yapılmaz; yalnızca okuma denemesinin REDDEDİLDİĞİ doğrulanır.
# ==============================================================================

testthat::test_that("open_sandboxed_duckdb harici dosya erişimini engeller ve ayarı kilitler", {
  testthat::skip_if_not_installed("duckdb")
  testthat::skip_if_not_installed("DBI")

  # helpers_mcp_basic_tools.R bootstrap kapısı helpers_mcp_tools'u GLOBAL
  # ortamda arar; kısa ömürlü bir ortam konur ve sonra geri alınır.
  onceki_var <- exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)
  onceki <- if (onceki_var) get("helpers_mcp_tools", envir = globalenv()) else NULL
  arac_env <- new.env(parent = emptyenv())
  assign("helpers_mcp_tools", arac_env, envir = globalenv())
  withr::defer({
    if (onceki_var) {
      assign("helpers_mcp_tools", onceki, envir = globalenv())
    } else {
      rm("helpers_mcp_tools", envir = globalenv())
    }
  })

  env <- new.env(parent = globalenv())
  env$helpers_mcp_tools <- arac_env
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$log_warn <- function(...) invisible(NULL)

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_mcp_basic_tools.R"),
    encoding = "UTF-8",
    local = env
  )

  con <- arac_env$open_sandboxed_duckdb()
  testthat::expect_false(is.null(con))
  withr::defer(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))

  # Var olan gerçek bir dosya kullanılır; engelleme "dosya yok" ile karışmasın.
  hedef <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("a,b", "1,2"), hedef)
  testthat::expect_true(file.exists(hedef))

  okuma <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT * FROM read_csv_auto('%s')",
        gsub("'", "''", hedef, fixed = TRUE)
      )
    ),
    error = function(e) conditionMessage(e)
  )
  testthat::expect_true(is.character(okuma))
  testthat::expect_match(okuma, "disabled by configuration|Permission", ignore.case = TRUE)

  # Sorgu kısıtlamayı geri açamamalıdır.
  acma <- tryCatch(
    DBI::dbExecute(con, "SET enable_external_access = true"),
    error = function(e) conditionMessage(e)
  )
  testthat::expect_true(is.character(acma))
  testthat::expect_match(acma, "locked", ignore.case = TRUE)

  # Bellek içi tablo üzerinde normal sorgular çalışmaya devam etmelidir.
  DBI::dbWriteTable(con, "t", data.frame(x = 1:3), temporary = TRUE, overwrite = TRUE)
  testthat::expect_equal(nrow(DBI::dbGetQuery(con, "SELECT * FROM t WHERE x > 1")), 2L)
})
