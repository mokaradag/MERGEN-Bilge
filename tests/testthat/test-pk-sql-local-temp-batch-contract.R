# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-sql-local-temp-batch-contract.R
# Açıklama: SQL Server yerel #temp analitik batch istisnasi. Mevcut D23 ve
#           Faz 3b salt-okunur ratchet'leri DEGISTIRILMEZ; metadata icin batch
#           calistirilmaz, kanitlanmis staging zinciri esdeger CTE'ye cevrilir.
# ==============================================================================

.pk_local_temp_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  source(file.path(repo_root, "R", "helpers_pk_sql_readonly.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "tools", "pk", "helpers_meta_generator_fetch.R"),
         encoding = "UTF-8", local = env)
  env
}

.pk_local_temp_read_bytes <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(txt)) "" else enc2utf8(txt)
}

.pk_safe_local_temp_batch <- function() {
  paste(
    "/* sentetik yerel temp analizi */",
    "IF OBJECT_ID('tempdb..#BaseData') IS NOT NULL DROP TABLE #BaseData;",
    "SELECT s.ProjectId, s.ActivityId, s.Value INTO #BaseData FROM dbo.SourceData AS s;",
    "IF OBJECT_ID('tempdb..#Counts') IS NOT NULL DROP TABLE #Counts;",
    paste0(
      "SELECT ProjectId, ActivityId, COUNT(*) AS N INTO #Counts ",
      "FROM #BaseData GROUP BY ProjectId, ActivityId;"
    ),
    paste0(
      "SELECT b.ProjectId, b.ActivityId, c.N FROM #BaseData AS b ",
      "INNER JOIN #Counts AS c ON c.ProjectId=b.ProjectId AND c.ActivityId=b.ActivityId;"
    ),
    "DROP TABLE #BaseData;",
    "DROP TABLE #Counts;",
    sep = "\n"
  )
}

.pk_indexed_local_temp_batch <- function() {
  paste(
    paste0(
      "SELECT e.ObjectId AS EPSObjectId, p.ObjectId AS ProjectObjectId ",
      "INTO #AktifProjeler FROM dbo.EPS e ",
      "INNER JOIN dbo.Project p ON e.ObjectId=p.ParentEPSObjectId;"
    ),
    "CREATE CLUSTERED INDEX IX_Aktif_ProjectObjectId ON #AktifProjeler(ProjectObjectId);",
    paste0(
      "CREATE NONCLUSTERED INDEX IX_Aktif_EPS ON #AktifProjeler(EPSObjectId) ",
      "INCLUDE (ProjectObjectId);"
    ),
    paste0(
      "SELECT r.ObjectId AS AssignmentObjectId, ap.ProjectObjectId, ap.EPSObjectId ",
      "INTO #Atamalar FROM dbo.resourceAssignment r ",
      "INNER JOIN #AktifProjeler ap ON r.ProjectObjectId=ap.ProjectObjectId;"
    ),
    "CREATE CLUSTERED INDEX IX_Atama_AssignmentId ON #Atamalar(AssignmentObjectId);",
    paste0(
      "SELECT a.ProjectObjectId, a.EPSObjectId, YEAR(s.StartDate) AS Yil, ",
      "SUM(s.ActualUnits) AS ToplamIscilik_Ham INTO #ProjeYillikOzet ",
      "FROM dbo.spread s INNER JOIN #Atamalar a ",
      "ON s.ResourceAssignmentObjectId=a.AssignmentObjectId ",
      "GROUP BY a.ProjectObjectId, a.EPSObjectId, YEAR(s.StartDate);"
    ),
    paste0(
      "CREATE NONCLUSTERED INDEX IX_Ozet_EPS_Yil ON #ProjeYillikOzet(EPSObjectId, Yil) ",
      "INCLUDE (ToplamIscilik_Ham);"
    ),
    paste0(
      "WITH SonucHazirlik AS (SELECT EPSObjectId, ProjectObjectId, Yil, ",
      "ToplamIscilik_Ham FROM #ProjeYillikOzet) ",
      "SELECT EPSObjectId, ProjectObjectId, Yil, ToplamIscilik_Ham FROM SonucHazirlik;"
    ),
    "DROP TABLE IF EXISTS #AktifProjeler, #Atamalar, #ProjeYillikOzet;",
    sep = "\n"
  )
}

test_that("kanitlanmis yerel #temp analitik batch kabul edilir", {
  env <- .pk_local_temp_env()
  sql <- .pk_safe_local_temp_batch()

  plan <- env$pk_sql_analyze_local_temp_batch(sql)
  expect_true(isTRUE(plan$ok))
  expect_identical(length(plan$temp_names), 2L)
  expect_identical(length(plan$staging_sql), 2L)
  expect_true(grepl("#BaseData", plan$result_sql, fixed = TRUE))
  expect_true(grepl("#Counts", plan$result_sql, fixed = TRUE))

  sonuc <- env$pk_sql_classify_readonly(sql)
  expect_true(isTRUE(sonuc$allowed))
  expect_identical(sonuc$statement_kind, "local_temp_batch")
  expect_identical(sonuc$statement_count, 7L)
})

test_that("SSMS tipi indeksli yerel-temp batch kabul edilir", {
  env <- .pk_local_temp_env()
  sql <- .pk_indexed_local_temp_batch()

  plan <- env$pk_sql_analyze_local_temp_batch(sql)
  expect_true(isTRUE(plan$ok))
  expect_identical(plan$temp_names,
                   c("#AktifProjeler", "#Atamalar", "#ProjeYillikOzet"))
  expect_identical(length(plan$staging_sql), 3L)
  expect_true(grepl("WITH SonucHazirlik", plan$result_sql, fixed = TRUE))

  sonuc <- env$pk_sql_classify_readonly(sql)
  expect_true(isTRUE(sonuc$allowed))
  expect_identical(sonuc$statement_kind, "local_temp_batch")
  expect_identical(sonuc$statement_count, 9L)
})

test_that("mevcut D23 yasak anahtar kelime ratchet'i aynen korunur", {
  env <- .pk_local_temp_env()
  for (kelime in c("MERGE", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP",
                   "ALTER", "EXEC", "INTO", "SET", "OPENROWSET", "BULK")) {
    expect_true(kelime %in% env$PK_SQL_FORBIDDEN_KEYWORDS,
                info = sprintf("D23 ratchet anahtar kelimesi kayboldu: %s", kelime))
  }

  nocount <- env$pk_sql_classify_readonly("SET NOCOUNT ON; SELECT * FROM dbo.T")
  expect_true(isTRUE(nocount$allowed))
})

test_that("kalici veya global temp yazimi yerel-temp istisnasini acamaz", {
  env <- .pk_local_temp_env()

  kalici_into <- paste(
    "IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;",
    "SELECT * INTO dbo.RealTable FROM dbo.SourceData;",
    "SELECT * FROM #T;",
    "DROP TABLE #T;",
    sep = "\n"
  )
  global_into <- paste(
    "IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;",
    "SELECT * INTO ##GlobalT FROM dbo.SourceData;",
    "SELECT * FROM #T;",
    "DROP TABLE #T;",
    sep = "\n"
  )

  expect_false(isTRUE(env$pk_sql_classify_readonly(kalici_into)$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly(global_into)$allowed))
})

test_that("yerel staging kalici DML EXEC veya sequence mutasyonunu gizleyemez", {
  env <- .pk_local_temp_env()

  taban <- c(
    "IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;",
    "SELECT Id INTO #T FROM dbo.SourceData;"
  )
  son <- c("SELECT * FROM #T;", "DROP TABLE #T;")

  guvensiz <- list(
    update = c(taban, "UPDATE dbo.RealTable SET X=1;", son),
    exec = c(taban, "EXEC dbo.RealProc;", son),
    sequence = c(
      "IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;",
      "SELECT NEXT VALUE FOR dbo.Seq AS Id INTO #T FROM dbo.SourceData;",
      son
    )
  )

  for (ad in names(guvensiz)) {
    sonuc <- env$pk_sql_classify_readonly(paste(guvensiz[[ad]], collapse = "\n"))
    expect_false(isTRUE(sonuc$allowed), info = ad)
  }
})

test_that("yerel-temp indeks istisnasi kalici DDL veya hatali temizligi acamaz", {
  env <- .pk_local_temp_env()
  iyi <- .pk_indexed_local_temp_batch()

  kalici_indeks <- sub(
    "CREATE CLUSTERED INDEX IX_Aktif_ProjectObjectId ON #AktifProjeler\\(ProjectObjectId\\);",
    "CREATE CLUSTERED INDEX IX_Aktif_ProjectObjectId ON dbo.RealTable(ProjectObjectId);",
    iyi, perl = TRUE
  )
  global_indeks <- sub(
    "CREATE CLUSTERED INDEX IX_Aktif_ProjectObjectId ON #AktifProjeler\\(ProjectObjectId\\);",
    "CREATE CLUSTERED INDEX IX_Aktif_ProjectObjectId ON ##GlobalT(ProjectObjectId);",
    iyi, perl = TRUE
  )
  kalici_temizlik <- sub(
    "DROP TABLE IF EXISTS #AktifProjeler, #Atamalar, #ProjeYillikOzet;",
    "DROP TABLE IF EXISTS #AktifProjeler, #Atamalar, dbo.RealTable;",
    iyi, fixed = TRUE
  )

  expect_false(isTRUE(env$pk_sql_classify_readonly(kalici_indeks)$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly(global_indeks)$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly(kalici_temizlik)$allowed))
})

test_that("kurulum ve temizlik isimleri birebir yerel #temp plani olmalidir", {
  env <- .pk_local_temp_env()

  uyusmayan_predrop <- paste(
    "IF OBJECT_ID('tempdb..#A') IS NOT NULL DROP TABLE #B;",
    "SELECT Id INTO #A FROM dbo.SourceData;",
    "SELECT * FROM #A;",
    "DROP TABLE #A;",
    sep = "\n"
  )
  eksik_temizlik <- paste(
    "IF OBJECT_ID('tempdb..#A') IS NOT NULL DROP TABLE #A;",
    "SELECT Id INTO #A FROM dbo.SourceData;",
    "SELECT * FROM #A;",
    sep = "\n"
  )
  kalici_temizlik <- paste(
    "IF OBJECT_ID('tempdb..#A') IS NOT NULL DROP TABLE #A;",
    "SELECT Id INTO #A FROM dbo.SourceData;",
    "SELECT * FROM #A;",
    "DROP TABLE dbo.RealTable;",
    sep = "\n"
  )

  expect_false(isTRUE(env$pk_sql_classify_readonly(uyusmayan_predrop)$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly(eksik_temizlik)$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly(kalici_temizlik)$allowed))
})

test_that("yerel-temp batch tek bir final sonuc SELECT'i ile sinirlidir", {
  env <- .pk_local_temp_env()

  iki_sonuc <- paste(
    "IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;",
    "SELECT Id INTO #T FROM dbo.SourceData;",
    "SELECT * FROM #T;",
    "SELECT COUNT(*) AS N FROM #T;",
    "DROP TABLE #T;",
    sep = "\n"
  )
  go_batch <- paste(
    "IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;",
    "SELECT Id INTO #T FROM dbo.SourceData;",
    "GO",
    "SELECT * FROM #T;",
    "DROP TABLE #T;",
    sep = "\n"
  )

  expect_false(isTRUE(env$pk_sql_classify_readonly(iki_sonuc)$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly(go_batch)$allowed))
})

test_that("Faz 3b yerel-temp metadata'sini sorguyu calistirmadan CTE'ye cevirir", {
  env <- .pk_local_temp_env()
  sql <- .pk_safe_local_temp_batch()
  donusen <- env$.pkgn_local_temp_describe_sql(sql)

  expect_true(grepl("^WITH __pk_meta_local_temp_001 AS", donusen, perl = TRUE))
  expect_true(grepl("__pk_meta_local_temp_002 AS", donusen, fixed = TRUE))
  expect_false(grepl("#BaseData", donusen, fixed = TRUE))
  expect_false(grepl("#Counts", donusen, fixed = TRUE))
  expect_false(grepl("INTO", donusen, ignore.case = TRUE, perl = TRUE))
  expect_false(grepl("DROP TABLE", donusen, ignore.case = TRUE, perl = TRUE))
  expect_true(grepl("FROM __pk_meta_local_temp_001", donusen, fixed = TRUE))
  expect_true(grepl("JOIN __pk_meta_local_temp_002", donusen, fixed = TRUE))
})

test_that("indeksli yerel-temp metadata CTE'ye doner ve indeksleri calistirmaz", {
  env <- .pk_local_temp_env()
  sql <- .pk_indexed_local_temp_batch()
  donusen <- env$.pkgn_local_temp_describe_sql(sql)

  expect_true(grepl("^WITH __pk_meta_local_temp_001 AS", donusen, perl = TRUE))
  expect_true(grepl("__pk_meta_local_temp_003 AS", donusen, fixed = TRUE))
  expect_true(grepl("SonucHazirlik AS", donusen, fixed = TRUE))
  expect_false(grepl("#AktifProjeler", donusen, fixed = TRUE))
  expect_false(grepl("#Atamalar", donusen, fixed = TRUE))
  expect_false(grepl("#ProjeYillikOzet", donusen, fixed = TRUE))
  expect_false(grepl("CREATE[ \\t\\r\\n]+(?:CLUSTERED|NONCLUSTERED)[ \\t\\r\\n]+INDEX",
                     donusen, ignore.case = TRUE, perl = TRUE))
  expect_false(grepl("DROP TABLE", donusen, ignore.case = TRUE, perl = TRUE))
  expect_true(grepl("FROM __pk_meta_local_temp_003", donusen, fixed = TRUE))
})

test_that("describe enjeksiyonu CTE metnini, sample yolu ise orijinal SQL'i korur", {
  env <- .pk_local_temp_env()
  sql <- .pk_safe_local_temp_batch()
  gorulen <- NULL

  describe_fn <- function(conn, sql) {
    gorulen <<- sql
    list(list(name = "ProjectId", system_type_name = "int", max_length = 4))
  }
  sonuc <- env$.pkgn_describe(
    list(sql = sql), list(sql_timeout_sec = 30),
    conn = structure(list(), class = "fake_conn"), describe_fn = describe_fn
  )

  expect_true(is.list(sonuc))
  expect_true(grepl("^WITH __pk_meta_local_temp_001 AS", gorulen, perl = TRUE))

  fetch_metin <- .pk_local_temp_read_bytes("tools/pk/helpers_meta_generator_fetch.R")
  expect_true(grepl("positional = list(conn, query$sql, config$sample_rows)",
                    fetch_metin, fixed = TRUE, useBytes = TRUE))
})

test_that("Faz 3b kalici DB yazma ratchet'i degismemistir", {
  for (rel in c("tools/pk/helpers_meta_generator_db.R",
                "tools/pk/helpers_meta_generator_fetch.R")) {
    metin <- .pk_local_temp_read_bytes(rel)
    for (yasak in c("dbExecute(", "dbWriteTable(", "dbRemoveTable(",
                    "dbCreateTable(", "dbAppendTable(", "sqlAppendTable(")) {
      expect_false(grepl(yasak, metin, fixed = TRUE, useBytes = TRUE),
                   info = sprintf("%s icinde yasak DB yazma API'si: %s", rel, yasak))
    }
  }
})