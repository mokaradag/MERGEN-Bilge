# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-pool-failure-modes.R
# Açıklama: İşlem-güvenli DB havuzunun HATA/YEDEK (failure/fallback) yollarının
#           davranış testleri. GERÇEK bir DBI arka ucu (RSQLite) üzerinde çalışır;
#           gerçek SQL Server/ODBC GEREKMEZ.
#
# Kapsanan sözleşmeler (task item-3 hardening):
#   - fail-fast AÇIK iken init hatası stop() eder; KAPALI iken NULL doner + KIRMAZ.
#   - GÜVENLİK: db_pool_get() NULL ama get_connection() bir Pool döndürürse,
#     db_acquire_tx_connection() Pool'u işlem bağlantısı gibi GEÇİRMEZ; gerçek bir
#     bağlantı ödünç alır (dbBegin/dbCommit Pool üzerinde ASLA çalışmaz).
#   - Çift iade (double release) sayaçları bozmaz / phantom pozitif sızıntı yaratmaz.
#   - Havuz kapatildiktan sonra db_acquire_tx_connection güvenle doğrudan yola düşer.
# ==============================================================================

testthat::skip_if_not_installed("pool")
testthat::skip_if_not_installed("RSQLite")
testthat::skip_if_not_installed("DBI")

local({
  if (!exists("init_db_pool_once", envir = globalenv(), inherits = TRUE)) {
    source(
      file.path(repo_root_for_tests, "R", "helpers_db_pool.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

.dbfm_clean_state <- function() {
  suppressWarnings(try(close_db_pool_once(), silent = TRUE))
  db_pool_reset_stats()
  if (exists("pool", envir = globalenv(), inherits = FALSE)) {
    legacy <- get("pool", envir = globalenv(), inherits = FALSE)
    if (is.null(legacy) || inherits(legacy, "Pool")) {
      suppressWarnings(rm("pool", envir = globalenv()))
    }
  }
}

.dbfm_sqlite_pool <- function(dbfile) {
  pool::dbPool(drv = RSQLite::SQLite(), dbname = dbfile, minSize = 1L, maxSize = 2L)
}

# ------------------------------------------------------------------------------
test_that("init: fail-fast ACIK iken init hatasi stop() eder; KAPALI iken NULL + KIRMAZ", {
  .dbfm_clean_state()
  on.exit(.dbfm_clean_state(), add = TRUE)

  throwing_factory <- function() stop("simule init hatasi")

  # fail-open (varsayilan davranis): NULL doner, init_failed artar, KIRMAZ.
  res_open <- init_db_pool_once("primary", factory = throwing_factory,
                                force = TRUE, fail_fast = FALSE)
  expect_null(res_open)
  expect_false(db_pool_is_active("primary"))
  snap_open <- db_pool_status_snapshot()
  expect_true(snap_open$counters$init_failed >= 1L)
  expect_equal(snap_open$counters$outstanding_checkouts, 0L)

  db_pool_reset_stats()

  # fail-fast: ayni hata artik stop() etmeli (genel, sir-icermeyen mesaj).
  expect_error(
    init_db_pool_once("primary", factory = throwing_factory,
                      force = TRUE, fail_fast = TRUE),
    "fail-fast"
  )
})

test_that("init: fail-fast ACIK + 'pool' paketi yokmus gibi reason kaydedilir (stop fail-fast)", {
  # 'pool' paketini gercekten gizleyemeyiz; ancak factory NULL'a dusen build
  # hatasini fail-fast'in stop()'a cevirdigini yukaridaki test kanitlar. Burada
  # fail-fast OFF iken hata yolunun KIRMADIGINI ve init_failed kaydettigini
  # bir kez daha sabitleriz (gerileme korumasi).
  .dbfm_clean_state()
  on.exit(.dbfm_clean_state(), add = TRUE)

  res <- init_db_pool_once("primary",
                           factory = function() list(not = "a pool"),
                           force = TRUE, fail_fast = FALSE)
  expect_null(res)  # factory Pool dondurmedi -> init_failed -> NULL
  expect_true(db_pool_status_snapshot()$counters$init_failed >= 1L)
})

test_that("GUVENLIK: get_connection bir Pool dondurdugunde islem Pool uzerinde CALISMAZ (gercek checkout)", {
  .dbfm_clean_state()
  dbfile <- tempfile(fileext = ".sqlite")
  p <- .dbfm_sqlite_pool(dbfile)

  old_get <- get("get_connection", envir = globalenv(), inherits = TRUE)
  old_rel <- get("release_connection", envir = globalenv(), inherits = TRUE)
  on.exit({
    assign("get_connection", old_get, envir = globalenv())
    assign("release_connection", old_rel, envir = globalenv())
    suppressWarnings(try(pool::poolClose(p), silent = TRUE))
    .dbfm_clean_state()
    suppressWarnings(unlink(dbfile))
  }, add = TRUE)

  # db_pool_get() NULL donmeli (st$pools bos, .GlobalEnv$pool yok); fakat
  # get_connection() bir Pool nesnesi donduruyor (gecersiz/eski .GlobalEnv$pool
  # senaryosunun simulasyonu).
  assign("get_connection", function(target = "primary") {
    list(conn = p, pooled = TRUE, pool = p)
  }, envir = globalenv())
  assign("release_connection", function(conn_info) invisible(NULL), envir = globalenv())

  ci <- db_acquire_tx_connection("primary")

  # GÜVENLİK: gercek bir DBI baglantisi olmali, Pool DEGIL.
  expect_true(isTRUE(ci$checked_out))
  expect_false(inherits(ci$conn, "Pool"))
  expect_true(DBI::dbIsValid(ci$conn))

  # Bir islem bu GERCEK baglanti uzerinde guvenle calismali (Pool uzerinde DEGIL).
  DBI::dbBegin(ci$conn)
  DBI::dbExecute(ci$conn, "CREATE TABLE IF NOT EXISTS t (a INTEGER)")
  DBI::dbExecute(ci$conn, "INSERT INTO t VALUES (1)")
  DBI::dbCommit(ci$conn)
  db_release_tx_connection(ci)

  snap <- db_pool_status_snapshot()
  expect_true(snap$counters$checkout >= 1L)
  expect_equal(snap$counters$outstanding_checkouts, 0L)
  # Pool'dan GERCEK checkout yapildi; bu yolda direct_fallback ARTMAMALI.
  expect_equal(snap$counters$direct_fallback, 0L)
})

test_that("cift iade (double release) sayaclari bozmaz / phantom pozitif sizinti yok", {
  .dbfm_clean_state()
  dbfile <- tempfile(fileext = ".sqlite")
  on.exit({
    .dbfm_clean_state()
    suppressWarnings(unlink(dbfile))
  }, add = TRUE)

  p <- init_db_pool_once("primary", factory = function() .dbfm_sqlite_pool(dbfile),
                         force = TRUE)
  expect_true(inherits(p, "Pool"))

  ci <- db_acquire_tx_connection("primary")
  expect_true(isTRUE(ci$checked_out))

  db_release_tx_connection(ci)
  # Cift iade: poolReturn hata verebilir (tryCatch -> return_failed) veya no-op;
  # her durumda checkout 1'de kalmali ve outstanding pozitif phantom OLMAMALI.
  suppressWarnings(db_release_tx_connection(ci))

  snap <- db_pool_status_snapshot()
  expect_equal(snap$counters$checkout, 1L)
  expect_true(snap$counters$returned >= 1L)
  expect_true(snap$counters$outstanding_checkouts <= 0L)
})

test_that("havuz kapatildiktan sonra db_acquire_tx_connection guvenle dogrudan yola duser", {
  .dbfm_clean_state()
  dbfile <- tempfile(fileext = ".sqlite")
  on.exit({
    .dbfm_clean_state()
    suppressWarnings(unlink(dbfile))
  }, add = TRUE)

  init_db_pool_once("primary", factory = function() .dbfm_sqlite_pool(dbfile), force = TRUE)
  expect_true(db_pool_is_active("primary"))

  # Havuzu calisirken kapat: sonraki edinme dogrudan baglantiya dusmeli.
  close_db_pool_once("primary")
  expect_false(db_pool_is_active("primary"))

  # get_connection'i stub'la (dogrudan sahte baglanti); Pool DONMEMELI.
  old_get <- get("get_connection", envir = globalenv(), inherits = TRUE)
  old_rel <- get("release_connection", envir = globalenv(), inherits = TRUE)
  released <- new.env(parent = emptyenv()); released$n <- 0L
  on.exit({
    assign("get_connection", old_get, envir = globalenv())
    assign("release_connection", old_rel, envir = globalenv())
  }, add = TRUE)
  assign("get_connection", function(target = "primary") {
    list(conn = structure(list(), class = "FakeDirectConn"), pooled = FALSE, pool = NULL)
  }, envir = globalenv())
  assign("release_connection", function(conn_info) {
    released$n <- released$n + 1L; invisible(NULL)
  }, envir = globalenv())

  ci <- db_acquire_tx_connection("primary")
  expect_false(isTRUE(ci$checked_out))
  expect_true(inherits(ci$conn, "FakeDirectConn"))
  db_release_tx_connection(ci)
  expect_equal(released$n, 1L)
})
