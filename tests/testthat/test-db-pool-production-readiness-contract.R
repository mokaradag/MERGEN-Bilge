# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-pool-production-readiness-contract.R
# Açıklama: İşlem-güvenli DB havuzunun ÜRETİM HAZIRLIĞI sözleşmeleri. Gerçek SQL
#           Server GEREKMEZ; bu testler havuzun GÖZLEMLENEBİLİRLİK + GÜVENLİK
#           kontratlarını (snapshot tamlığı/kararlılığı/sir-guvenligi, fail-fast
#           yapilandirmasi, /readyz entegrasyonu ve VM preflight betiginin statik
#           sözleşmesini) doğrular.
#
# Kapsanan sözleşmeler:
#   - db_pool_status_snapshot() task item-4'teki TÜM alanları içerir.
#   - Snapshot init ÖNCESİ kararlı (bos havuz, outstanding=0).
#   - Snapshot basarisiz init SONRASI kararli + sir-guvenli.
#   - db_pool_config()$fail_fast env > option > FALSE ile cozulur.
#   - /readyz hazirlik yuku db_pool blogunu sir-guvenli icerir.
#   - run_vm_db_pool_preflight_real.R: var, ASCII-only, quit() yok, guard'li,
#     ham DSN basmaz.
# ==============================================================================

testthat::skip_if_not_installed("DBI")

local({
  if (!exists("db_pool_status_snapshot", envir = globalenv(), inherits = TRUE)) {
    source(
      file.path(repo_root_for_tests, "R", "helpers_db_pool.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

# Temiz havuz durumu: acik havuzlari kapat + sayaclari sifirla.
.dbpr_clean_state <- function() {
  suppressWarnings(try(close_db_pool_once(), silent = TRUE))
  db_pool_reset_stats()
}

# ------------------------------------------------------------------------------
test_that("db_pool_status_snapshot tum uretim-gozlemlenebilirlik alanlarini icerir", {
  .dbpr_clean_state()
  on.exit(.dbpr_clean_state(), add = TRUE)

  snap <- db_pool_status_snapshot()
  expect_true(is.list(snap))

  # Üst seviye alanlar (task item-4).
  for (field in c("enabled", "fail_fast", "config", "active_targets", "pools", "counters")) {
    expect_true(field %in% names(snap), info = field)
  }

  # Sayaç alanlari: task item-4 listesinin TAMAMI.
  required_counters <- c(
    "init", "init_failed", "init_skipped", "closed",
    "checkout", "checkout_failed", "returned", "outstanding_checkouts",
    "tx_begin", "tx_commit", "tx_rollback", "direct_fallback"
  )
  for (cn in required_counters) {
    expect_true(cn %in% names(snap$counters), info = cn)
  }

  # Yapilandirma alanlari.
  for (cf in c("min_size", "max_size", "idle_timeout_sec", "validation_interval_sec")) {
    expect_true(cf %in% names(snap$config), info = cf)
  }
})

test_that("snapshot init ONCESI kararli: bos havuz, sizinti yok", {
  .dbpr_clean_state()
  on.exit(.dbpr_clean_state(), add = TRUE)

  snap <- db_pool_status_snapshot()
  expect_equal(length(snap$active_targets), 0L)
  expect_equal(snap$counters$outstanding_checkouts, 0L)
  expect_equal(snap$counters$checkout, 0L)
  expect_equal(snap$counters$returned, 0L)
  # Init yapilmadan da JSON'a guvenle serilesir (kirilgan/agir yol degil).
  expect_silent(jsonlite::toJSON(snap, auto_unbox = TRUE, null = "null"))
})

test_that("snapshot basarisiz init SONRASI kararli + sir-guvenli", {
  testthat::skip_if_not_installed("pool")
  .dbpr_clean_state()
  on.exit(.dbpr_clean_state(), add = TRUE)

  # Hata firlatan factory ile fail-open init: NULL doner, KIRMAZ.
  res <- init_db_pool_once("primary",
                           factory = function() stop("simule init hatasi"),
                           force = TRUE, fail_fast = FALSE)
  expect_null(res)

  snap <- db_pool_status_snapshot()
  expect_true(is.list(snap))
  # Havuz kaydedilmedi: aktif hedef yok, sizinti yok.
  expect_equal(length(snap$active_targets), 0L)
  expect_equal(snap$counters$outstanding_checkouts, 0L)
  expect_true(snap$counters$init_failed >= 1L)

  # Ham DSN/secret sizmamali.
  snap_txt <- jsonlite::toJSON(snap, auto_unbox = TRUE, null = "null")
  expect_false(grepl("DB_DSN", snap_txt, fixed = TRUE))
  expect_false(grepl("dbname", snap_txt, fixed = TRUE))
  expect_false(grepl("(?i)(password|secret|dsn=)", snap_txt, perl = TRUE))
})

test_that("db_pool_config()$fail_fast env > option > FALSE ile cozulur", {
  # Varsayilan: FALSE.
  withr::with_envvar(list(MERGEN_DB_POOL_FAIL_FAST = NA), {
    withr::with_options(list(mergen.db.pool_fail_fast = NULL), {
      expect_false(isTRUE(db_pool_config()$fail_fast))
    })
  })
  # Env TRUE.
  withr::with_envvar(list(MERGEN_DB_POOL_FAIL_FAST = "true"), {
    expect_true(isTRUE(db_pool_config()$fail_fast))
  })
  # Env FALSE (option TRUE'yu ezer).
  withr::with_envvar(list(MERGEN_DB_POOL_FAIL_FAST = "0"), {
    withr::with_options(list(mergen.db.pool_fail_fast = TRUE), {
      expect_false(isTRUE(db_pool_config()$fail_fast))
    })
  })
  # Env yok -> option.
  withr::with_envvar(list(MERGEN_DB_POOL_FAIL_FAST = NA), {
    withr::with_options(list(mergen.db.pool_fail_fast = TRUE), {
      expect_true(isTRUE(db_pool_config()$fail_fast))
    })
  })

  # Snapshot fail_fast alani config ile tutarli.
  withr::with_envvar(list(MERGEN_DB_POOL_FAIL_FAST = "true"), {
    expect_true(isTRUE(db_pool_status_snapshot()$fail_fast))
  })
})

test_that("/readyz hazirlik yuku db_pool blogunu sir-guvenli icerir", {
  testthat::skip_if_not_installed("jsonlite")
  routes_path <- file.path(repo_root_for_tests, "R", "helpers_app_http_routes.R")
  skip_if_not(file.exists(routes_path))

  env <- new.env(parent = globalenv())
  source(routes_path, local = env, encoding = "UTF-8")
  # db_pool_status_snapshot global olarak gorunur (helper_bootstrap + yukaridaki
  # local source); mergen_readiness_payload onu exists(..., inherits = TRUE) ile bulur.
  payload <- env$mergen_readiness_payload()
  expect_identical(payload$status, "ok")
  expect_true(!is.null(payload$db_pool))
  expect_true("counters" %in% names(payload$db_pool))
  expect_true("outstanding_checkouts" %in% names(payload$db_pool$counters))

  body <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", na = "null")
  expect_false(grepl("(?i)(password|secret|dsn=|bearer|api[_-]?key=)", body, perl = TRUE))
  expect_false(grepl("DB_DSN", body, fixed = TRUE))
})

test_that("run_vm_db_pool_preflight_real.R statik sozlesmesi (ASCII-only, quit yok, guard'li)", {
  script <- file.path(repo_root_for_tests, "tests", "scripts", "run_vm_db_pool_preflight_real.R")
  expect_true(file.exists(script))

  # Bayt-guvenli okuma (Windows VM uyumlu): ASCII-only dogrulamasi.
  raw_bytes <- readBin(script, what = "raw", n = file.info(script)$size)
  expect_false(any(as.integer(raw_bytes) > 127L),
               info = "Operasyonel giris betigi ASCII-only olmalidir (Turkce \\u kacisiyla).")

  txt <- iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")

  # quit() yok (source(...) ile guvenli olmali). Yorum satirlari TARANMAZ; aksi
  # halde "quit() yoktur" gibi aciklayici yorumlar yanlis-pozitif uretir
  # (repo sozlesmesi: tarama oncesi R yorumlarini yok say).
  code_only <- gsub("#.*$", "", strsplit(txt, "\n", fixed = TRUE)[[1]])
  expect_false(any(grepl("quit(", code_only, fixed = TRUE)),
               info = "Operasyonel betik gercek quit() cagrisi ICERMEMELI.")

  # Guard'lar ve fail-fast/yazma testi bayraklari referans edilir.
  expect_true(grepl("MERGEN_DB_POOL_ENABLED", txt, fixed = TRUE))
  expect_true(grepl("DB_DSN", txt, fixed = TRUE))
  expect_true(grepl("MERGEN_DB_POOL_WRITE_TEST", txt, fixed = TRUE))
  expect_true(grepl("MERGEN_DB_POOL_FAIL_FAST", txt, fixed = TRUE) ||
              grepl("fail_fast", txt, fixed = TRUE))

  # Havuz API'sini kullanir.
  expect_true(grepl("db_pool_status_snapshot", txt, fixed = TRUE))
  expect_true(grepl("with_db_transaction", txt, fixed = TRUE))
  expect_true(grepl("with_db_connection", txt, fixed = TRUE))

  # Ham DSN basmaz: yalniz boolean varlik raporlanir, secret redaksiyonu kullanilir.
  expect_true(grepl("db_dsn_present", txt, fixed = TRUE))
  expect_true(grepl("dbpf_redact", txt, fixed = TRUE))
})
