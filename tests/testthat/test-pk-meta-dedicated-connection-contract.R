# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-meta-dedicated-connection-contract.R
# Açıklama: Faz 3b metadata üreticisi DB izolasyonu ve NOCOUNT descriptor
#           uyumluluğu regresyonları. Gerçek DB/ODBC bağlantısı açmaz.
#
#           Windows VM notu: bu dosyanın eski bir kopyası `helpers_pk_sql_readonly.R`
#           dosyasını kardeş `helpers_pk_sql_statements.R` OLMADAN yüklüyor ve
#           `.pkgd_descriptor_sql()` -> `pk_sql_classify_readonly()` çağrısı
#           ".pk_sql_extra_top_level_statement fonksiyonu bulunamadı" ile düşüyordu.
#           Yükleme zinciri artık diğer üretici testleriyle (manifest sırasıyla)
#           aynıdır; sınıflandırıcı ayrıca tek başına da yüklenebilir (bkz.
#           test-pk-sql-readonly-bootstrap-contract.R).
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  # Çalışma zamanı sözleşmesi: manifest sırası (statements, readonly'den ÖNCE).
  for (dosya in c(
    "helpers_pk_ascii_tokens.R",
    "helpers_pk_text_turkish.R",
    "helpers_pk_config.R",
    "helpers_pk_query_meta_schema.R",
    "helpers_pk_query_meta_access.R",
    "helpers_pk_query_meta_layers.R",
    "helpers_pk_query_meta.R",
    "helpers_pk_sql_statements.R", "helpers_pk_sql_readonly.R",
    "helpers_pk_sql_local_temp_batch.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }

  # VM aracı (manifest dışı); giriş noktası tools/pk/generate_query_meta.R sırası.
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

test_that("descriptor noktali virgulsuz ikinci ifadeyi de kapida reddeder", {
  # Kardeş yardımcı (`.pk_sql_extra_top_level_statement`) yüklü olmalıdır;
  # aksi halde kapı hata verir, metin degistirilmeden donmez.
  sql <- "SET NOCOUNT ON; SELECT 1 AS a\nSELECT 2 AS b"
  expect_identical(.pkgd_descriptor_sql(sql), sql)
})

test_that("metadata default connection uygulama poolunu devralmaz", {
  govde <- paste(deparse(body(pkg_default_connect_fn)), collapse = "\n")

  expect_true(grepl("DBI::dbConnect", govde, fixed = TRUE))
  expect_true(grepl("odbc::odbc", govde, fixed = TRUE))
  expect_false(grepl("get_connection", govde, fixed = TRUE))
  expect_false(grepl("db_acquire_tx_connection", govde, fixed = TRUE))
})

# Metin taraması tek başına yetmez: `DBI::dbConnect()` ölü kodda kalıp fonksiyon
# BAŞKA bir tutamaç döndürse ya da release hiç `dbDisconnect()` çağırmasa bu
# sözleşme yine geçerdi. Varsayılan yaşam döngüsü GERÇEKTEN çalıştırılır.
test_that("varsayilan baglanti yasam dongusu adanmis tutamac uretir ve kapatir", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("odbc")

  withr::local_envvar(c(DB_DSN = "MergenTestDSN"))

  sahte_conn <- structure(list(id = "adanmis"), class = "MergenSahteConn")
  gorulen_args <- NULL
  kapatilan <- list()

  testthat::local_mocked_bindings(
    odbc = function(...) structure(list(), class = "MergenSahteDriver"),
    .package = "odbc"
  )
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) {
      gorulen_args <<- list(drv = drv, args = list(...))
      sahte_conn
    },
    dbDisconnect = function(conn, ...) {
      kapatilan[[length(kapatilan) + 1L]] <<- conn
      invisible(TRUE)
    },
    .package = "DBI"
  )

  handle <- pkg_default_connect_fn("primary", timeout_sec = 5)

  expect_identical(handle$conn, sahte_conn)
  expect_false(isTRUE(handle$pooled))
  expect_true(isTRUE(handle$pkg_meta_dedicated))
  expect_identical(gorulen_args$args$dsn, "MergenTestDSN")

  pkg_default_release_fn(handle, timeout_sec = 5)
  expect_length(kapatilan, 1L)
  expect_identical(kapatilan[[1]], sahte_conn)

  # Havuzdan ödünç alınmış (adanmış olmayan) tutamaç bu yoldan KAPATILMAZ.
  pkg_default_release_fn(list(conn = sahte_conn, pooled = TRUE), timeout_sec = 5)
  expect_length(kapatilan, 1L)
})

test_that("metadata dedicated connection kendi fiziksel baglantisini kapatir", {
  govde <- paste(deparse(body(pkg_default_release_fn)), collapse = "\n")

  expect_true(grepl("pkg_meta_dedicated", govde, fixed = TRUE))
  expect_true(grepl("DBI::dbDisconnect", govde, fixed = TRUE))
})
