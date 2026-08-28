# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-sql-declare-batch-contract.R
# Açıklama: Salt-okunur scalar DECLARE öneki için dar regresyon sözleşmesi.
# ==============================================================================

.pk_declare_gate_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  for (.pk_kaynak_dosya in c("helpers_pk_sql_statements.R", "helpers_pk_sql_readonly.R", "helpers_pk_sql_local_temp_batch.R")) source(file.path(repo_root, "R", .pk_kaynak_dosya),
         encoding = "UTF-8", local = env)
  env
}

test_that("scalar DECLARE oneki + tek SELECT salt-okunur kabul edilir", {
  env <- .pk_declare_gate_env()
  sql <- paste(
    "DECLARE @CutoffDate DATE = DATEADD(day, -90, GETDATE());",
    "DECLARE @Today DATE = CAST(GETDATE() AS date);",
    "SELECT DATEDIFF(day, @CutoffDate, @Today) AS GecenSureGun;",
    sep = "\n"
  )

  sonuc <- env$pk_sql_classify_readonly(sql)
  expect_true(isTRUE(sonuc$allowed))
  expect_identical(sonuc$statement_kind, "declare_select_batch")
  expect_identical(sonuc$statement_count, 3L)

  nocount <- env$pk_sql_classify_readonly(paste(
    "SET NOCOUNT ON;",
    "DECLARE @Today DATE = CAST(GETDATE() AS date);",
    "SELECT @Today AS Bugun;",
    sep = "\n"
  ))
  expect_true(isTRUE(nocount$allowed))
  expect_identical(nocount$statement_kind, "declare_select_batch")
})

test_that("DECLARE istisnasi mevcut fail-closed ratchetleri gevsetmez", {
  env <- .pk_declare_gate_env()
  guvensiz <- c(
    "DECLARE @x BIGINT = NEXT VALUE FOR dbo.S; SELECT @x;",
    "DECLARE @t TABLE (x INT); SELECT x FROM @t;",
    "DECLARE @c CURSOR; SELECT 1;",
    "DECLARE @x INT = 1; UPDATE SentetikTablo SET x = 2; SELECT @x;",
    "DECLARE @x INT = 1; SELECT 1; SELECT 2;",
    "DECLARE @x INT = 1; EXEC dbo.SentetikYordam;"
  )

  for (sql in guvensiz) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_false(isTRUE(sonuc$allowed), info = sql)
  }
})

test_that("ayrilmis kelimeyle ADLANDIRILMIS yerel degisken REDDEDILMEZ (PR #705 P2)", {
  env <- .pk_declare_gate_env()

  # Jeton deseni `@` sigilini disarida biraktigi icin `@Open` jetonu `OPEN`
  # olarak okunuyor ve AYRILMIS ifade baslatici listesine dusuyordu; tamamen
  # salt-okunur bir kutuphane sorgusu guvenlik gerekcesiyle REDDEDILIYORDU.
  for (ad in c("Open", "Close", "If", "While", "Return", "Break", "Continue", "Goto")) {
    sql <- sprintf("DECLARE @%s INT = 1;\nSELECT @%s AS a;", ad, ad)
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_true(isTRUE(sonuc$allowed), info = ad)
    expect_identical(sonuc$statement_kind, "declare_select_batch")
  }

  # GERCEK ikinci ust duzey ifade REDDEDILMEYE devam eder.
  expect_false(isTRUE(env$pk_sql_classify_readonly(
    "SELECT 1 AS a\nDISABLE TRIGGER ALL ON DATABASE"
  )$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly(
    "SELECT 1 AS a\nIF 1=1 SELECT 2"
  )$allowed))
})
