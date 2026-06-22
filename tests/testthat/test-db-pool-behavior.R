# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-pool-behavior.R
# Açıklama: İşlem-güvenli DB bağlantı havuzu katmanının (R/helpers_db_pool.R)
#           davranış testleri. GERÇEK bir DBI arka ucu (RSQLite, bellek/temp
#           dosya) üzerinde çalışır; gerçek SQL Server/ODBC GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Havuz varsayılan KAPALI; env/option ile açılır.
#   - init/close BİR KEZ semantiği + güvenli (başlatma uygulamayı kırmaz).
#   - with_db_connection ödünç alır ve HER DURUMDA iade eder (sızıntı yok).
#   - with_db_transaction başarıda commit, hatada rollback yapar ve hatayı
#     yeniden fırlatır; her iki durumda bağlantı iade edilir (sızıntı yok).
#   - İşlem yalıtımı: rollback satır bırakmaz, commit kalıcıdır.
#   - Türkçe/UTF-8 metin havuzlu yazma/okuma boyunca korunur.
#   - İşlem yolu havuz NESNESİNİ bağlantı gibi kullanmaz (gerçek checkout).
#   - Havuz kapalıyken doğrudan bağlantı yoluna düşülür (fallback).
#   - db_pool_status_snapshot ham DSN/secret içermez.
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

# SQLite havuzu üreten bir factory döner. Tüm ödünç bağlantılar AYNI dosya-DB'yi
# paylaşır (":memory:" her bağlantıda ayrı DB olurdu).
.db_pool_test_sqlite_factory <- function(dbfile) {
  function() {
    pool::dbPool(
      drv = RSQLite::SQLite(),
      dbname = dbfile,
      minSize = 1L,
      maxSize = 4L
    )
  }
}

# Havuzu force ile başlatır, kod bloğunu çalıştırır, sonra her durumda kapatır
# ve global durumu/`.GlobalEnv$pool`'u eski haline döndürür.
.with_test_db_pool <- function(code) {
  dbfile <- tempfile(fileext = ".sqlite")

  pool_existed <- exists("pool", envir = globalenv(), inherits = FALSE)
  old_pool <- if (pool_existed) get("pool", envir = globalenv(), inherits = FALSE) else NULL

  db_pool_reset_stats()
  on.exit({
    suppressWarnings(try(close_db_pool_once(), silent = TRUE))
    db_pool_reset_stats()
    if (pool_existed) {
      assign("pool", old_pool, envir = globalenv())
    } else if (exists("pool", envir = globalenv(), inherits = FALSE)) {
      rm("pool", envir = globalenv())
    }
    suppressWarnings(unlink(dbfile))
  }, add = TRUE)

  p <- init_db_pool_once("primary",
                         factory = .db_pool_test_sqlite_factory(dbfile),
                         force = TRUE)
  testthat::expect_true(inherits(p, "Pool"))

  # Şema: lane-yerel SQLite SQL (üretim T-SQL DEĞİL).
  with_db_connection(function(conn) {
    DBI::dbExecute(conn, "CREATE TABLE IF NOT EXISTS mb_test (id INTEGER, txt TEXT)")
  })

  code(dbfile)
}

# ------------------------------------------------------------------------------
test_that("havuz varsayılan KAPALI; env/option ile açılır", {
  withr::with_envvar(list(MERGEN_DB_POOL_ENABLED = NA), {
    withr::with_options(list(mergen.db.pool_enabled = NULL), {
      expect_false(is_db_pool_enabled())
    })
  })

  withr::with_envvar(list(MERGEN_DB_POOL_ENABLED = "true"), {
    expect_true(is_db_pool_enabled())
  })
  withr::with_envvar(list(MERGEN_DB_POOL_ENABLED = "0"), {
    expect_false(is_db_pool_enabled())
  })
  withr::with_envvar(list(MERGEN_DB_POOL_ENABLED = NA), {
    withr::with_options(list(mergen.db.pool_enabled = TRUE), {
      expect_true(is_db_pool_enabled())
    })
  })
})

test_that("db_pool_config env override + korumacı varsayılanlar", {
  withr::with_envvar(list(
    MERGEN_DB_POOL_ENABLED = "true",
    MERGEN_DB_POOL_MIN_SIZE = "2",
    MERGEN_DB_POOL_MAX_SIZE = "12",
    MERGEN_DB_POOL_IDLE_TIMEOUT = "120",
    MERGEN_DB_POOL_VALIDATION_INTERVAL = "30"
  ), {
    cfg <- db_pool_config()
    expect_true(cfg$enabled)
    expect_equal(cfg$min_size, 2L)
    expect_equal(cfg$max_size, 12L)
    expect_equal(cfg$idle_timeout_sec, 120)
    expect_equal(cfg$validation_interval_sec, 30)
  })

  withr::with_envvar(list(
    MERGEN_DB_POOL_ENABLED = NA, MERGEN_DB_POOL_MIN_SIZE = NA,
    MERGEN_DB_POOL_MAX_SIZE = NA, MERGEN_DB_POOL_IDLE_TIMEOUT = NA,
    MERGEN_DB_POOL_VALIDATION_INTERVAL = NA
  ), {
    cfg <- db_pool_config()
    expect_false(cfg$enabled)
    expect_equal(cfg$min_size, 1L)
    expect_equal(cfg$max_size, 8L)
  })
})

test_that("init_db_pool_once havuz kapalıyken sessizce atlar (NULL)", {
  withr::with_envvar(list(MERGEN_DB_POOL_ENABLED = "false"), {
    res <- init_db_pool_once("primary")
    expect_null(res)
    expect_false(db_pool_is_active("primary"))
  })
})

test_that("init_db_pool_once force + factory ile havuz kurar ve BİR KEZ semantiği", {
  .with_test_db_pool(function(dbfile) {
    expect_true(db_pool_is_active("primary"))
    first <- db_pool_get("primary")
    # İkinci çağrı yeni havuz kurmaz; aynı nesneyi döndürür.
    second <- init_db_pool_once("primary",
                                factory = .db_pool_test_sqlite_factory(dbfile),
                                force = TRUE)
    expect_identical(first, second)
  })
})

test_that("with_db_connection ödünç alır ve iade eder (sızıntı yok)", {
  .with_test_db_pool(function(dbfile) {
    res <- with_db_connection(function(conn) {
      DBI::dbGetQuery(conn, "SELECT 1 AS ok")$ok[1]
    })
    expect_equal(res, 1L)

    snap <- db_pool_status_snapshot()
    expect_equal(snap$counters$outstanding_checkouts, 0L)
    expect_true(snap$counters$checkout >= 1L)
    expect_equal(snap$counters$checkout, snap$counters$returned)
  })
})

test_that("with_db_transaction commit yapar ve satır kalıcıdır", {
  .with_test_db_pool(function(dbfile) {
    with_db_transaction(function(conn) {
      DBI::dbExecute(conn, "INSERT INTO mb_test (id, txt) VALUES (?, ?)",
                     params = list(1L, "kalici"))
    })
    n <- with_db_connection(function(conn) {
      DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM mb_test")$n[1]
    })
    expect_equal(n, 1L)

    snap <- db_pool_status_snapshot()
    expect_true(snap$counters$tx_commit >= 1L)
    expect_equal(snap$counters$outstanding_checkouts, 0L)
  })
})

test_that("with_db_transaction hata durumunda rollback yapar ve hatayı fırlatır", {
  .with_test_db_pool(function(dbfile) {
    expect_error(
      with_db_transaction(function(conn) {
        DBI::dbExecute(conn, "INSERT INTO mb_test (id, txt) VALUES (?, ?)",
                       params = list(2L, "rollback"))
        stop("kasitli hata")
      }),
      "kasitli hata"
    )

    # Rollback sonrası satır KALMAMALI.
    n <- with_db_connection(function(conn) {
      DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM mb_test")$n[1]
    })
    expect_equal(n, 0L)

    snap <- db_pool_status_snapshot()
    expect_true(snap$counters$tx_rollback >= 1L)
    # Hata yolunda da bağlantı iade edilmiş olmalı (sızıntı yok).
    expect_equal(snap$counters$outstanding_checkouts, 0L)
  })
})

test_that("Türkçe/UTF-8 metin havuzlu yazma/okuma boyunca korunur", {
  .with_test_db_pool(function(dbfile) {
    tr <- "Türkçe çğıİöşü başkent"
    param_val <- if (exists("normalize_db_visible_value", mode = "function", inherits = TRUE)) {
      normalize_db_visible_value(tr)
    } else {
      enc2utf8(tr)
    }
    with_db_transaction(function(conn) {
      DBI::dbExecute(conn, "INSERT INTO mb_test (id, txt) VALUES (?, ?)",
                     params = list(10L, param_val))
    })
    got <- with_db_connection(function(conn) {
      DBI::dbGetQuery(conn, "SELECT txt FROM mb_test WHERE id = 10")$txt[1]
    })
    expect_equal(enc2utf8(got), enc2utf8(tr))
  })
})

test_that("işlem yolu havuz NESNESİNİ değil gerçek bir bağlantı ödünç alır", {
  .with_test_db_pool(function(dbfile) {
    ci <- db_acquire_tx_connection("primary")
    on.exit(db_release_tx_connection(ci), add = TRUE)
    expect_true(isTRUE(ci$checked_out))
    # Ödünç alınan, Pool nesnesi DEĞİL gerçek bir DBI bağlantısıdır.
    expect_false(inherits(ci$conn, "Pool"))
    expect_true(DBI::dbIsValid(ci$conn))
  })
})

test_that("close_db_pool_once havuzu kapatır ve durum pasifleşir", {
  dbfile <- tempfile(fileext = ".sqlite")
  pool_existed <- exists("pool", envir = globalenv(), inherits = FALSE)
  old_pool <- if (pool_existed) get("pool", envir = globalenv(), inherits = FALSE) else NULL
  on.exit({
    if (pool_existed) assign("pool", old_pool, envir = globalenv())
    else if (exists("pool", envir = globalenv(), inherits = FALSE)) rm("pool", envir = globalenv())
    db_pool_reset_stats()
    suppressWarnings(unlink(dbfile))
  }, add = TRUE)

  init_db_pool_once("primary",
                    factory = .db_pool_test_sqlite_factory(dbfile),
                    force = TRUE)
  expect_true(db_pool_is_active("primary"))

  close_db_pool_once("primary")
  expect_false(db_pool_is_active("primary"))
  # Geriye dönük .GlobalEnv$pool temizlenmeli.
  legacy <- if (exists("pool", envir = globalenv(), inherits = FALSE)) {
    get("pool", envir = globalenv(), inherits = FALSE)
  } else NULL
  expect_false(inherits(legacy, "Pool"))
})

test_that("havuz kapalıyken db_acquire_tx_connection doğrudan bağlantıya düşer", {
  # get_connection'ı stub'la; havuz yokken bu yol kullanılmalı.
  old_get <- get("get_connection", envir = globalenv(), inherits = TRUE)
  old_rel <- get("release_connection", envir = globalenv(), inherits = TRUE)
  released <- new.env(parent = emptyenv()); released$n <- 0L
  on.exit({
    assign("get_connection", old_get, envir = globalenv())
    assign("release_connection", old_rel, envir = globalenv())
    db_pool_reset_stats()
  }, add = TRUE)

  db_pool_reset_stats()
  assign("get_connection", function(target = "primary") {
    list(conn = structure(list(), class = "FakeDirectConn"), pooled = FALSE, pool = NULL)
  }, envir = globalenv())
  assign("release_connection", function(conn_info) {
    released$n <- released$n + 1L
    invisible(NULL)
  }, envir = globalenv())

  ci <- db_acquire_tx_connection("primary")
  expect_false(isTRUE(ci$checked_out))
  expect_true(inherits(ci$conn, "FakeDirectConn"))

  db_release_tx_connection(ci)
  expect_equal(released$n, 1L)

  snap <- db_pool_status_snapshot()
  expect_true(snap$counters$direct_fallback >= 1L)
})

test_that("db_pool_status_snapshot ham DSN/secret içermez ve yapısaldır", {
  .with_test_db_pool(function(dbfile) {
    with_db_connection(function(conn) DBI::dbGetQuery(conn, "SELECT 1"))
    snap <- db_pool_status_snapshot()
    expect_true(is.list(snap))
    for (field in c("enabled", "config", "active_targets", "pools", "counters")) {
      expect_true(field %in% names(snap), info = field)
    }
    # Ham DSN/secret sızıntısı olmamalı (snapshot JSON'unda).
    snap_txt <- jsonlite::toJSON(snap, auto_unbox = TRUE, null = "null")
    expect_false(grepl("dbname", snap_txt, fixed = TRUE))
    expect_false(grepl(dbfile, snap_txt, fixed = TRUE))
    expect_false(grepl("DB_DSN", snap_txt, fixed = TRUE))
  })
})
