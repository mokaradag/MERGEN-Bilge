# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-sql-execute-bounded-behavior.R
# Açıklama: Faz 6 (§5.10) — SINIRLI, KESİLEBİLİR SQL getiriminin davranış
#           testleri. GERÇEK bir DBI arka ucu (RSQLite, bellek içi) kullanılır;
#           SQL Server, ODBC, DSN veya ağ GEREKMEZ (repo emsali:
#           test-ortak-oturum-db-behavior.R, test-db-pool-behavior.R).
#
# Kanıtlanan sözleşmeler:
#   - Parça parça getirim tam sonucu üretir (satır/sütun sözleşmesi korunur).
#   - Getirimin ORTASINDA gelen iptal görülür ve TİPLİ durum döner.
#   - Son tarih dolması iptal ile KARIŞTIRILMAZ.
#   - Tavanı aşacak parça KABUL EDİLMEDEN durulur; veri DÖNMEZ.
#   - Sonuç kümesi HER çıkış yolunda kapatılır (bağlantı temiz kalır).
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  for (dosya in c("helpers_pk_async_cancel.R", "helpers_pk_result_size.R",
                  "helpers_pk_sql_execute.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

.pk_sql_test_conn <- function(rows = 1000L) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbWriteTable(
    conn, "veri",
    data.frame(
      id = seq_len(rows),
      ad = paste0("Proje ", seq_len(rows)),
      tutar = as.numeric(seq_len(rows)) * 1.5,
      stringsAsFactors = FALSE
    )
  )
  conn
}

# Temizlik sözleşmesinin kanıtı: `DBI::dbClearResult()` çağrı sayacı.
# `DBI::dbListResults()` KULLANILMAZ — kullanımdan kaldırılmıştır ve katı test
# koşucusu (stop_on_warning = TRUE) uyarıda kırılır.
.pk_clear_calls <- new.env(parent = emptyenv())

# Sayacı ÇAĞIRAN testin kapsamında kurar; test bitince binding geri alınır.
.pk_arm_clear_counter <- function(env = parent.frame()) {
  .pk_clear_calls$n <- 0L
  gercek <- DBI::dbClearResult
  testthat::local_mocked_bindings(
    dbClearResult = function(res, ...) {
      .pk_clear_calls$n <- .pk_clear_calls$n + 1L
      gercek(res, ...)
    },
    .package = "DBI",
    .env = env
  )
  invisible(TRUE)
}

test_that("parça parça getirim TAM sonucu üretir", {
  skip_if_not_installed("RSQLite")
  .pk_arm_clear_counter()
  skip_if_not_installed("DBI")

  conn <- .pk_sql_test_conn(1000L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  sonuc <- pk_sql_execute_bounded(
    conn, "SELECT * FROM veri ORDER BY id",
    unicode_param = FALSE, chunk_rows = 250L, max_result_mb = 512
  )

  expect_equal(sonuc$status, "ok")
  expect_equal(sonuc$rows, 1000L)
  expect_equal(nrow(sonuc$data), 1000L)
  expect_equal(names(sonuc$data), c("id", "ad", "tutar"))
  expect_equal(sonuc$data$id[1], 1L)
  expect_equal(sonuc$data$id[1000], 1000L)
  expect_true(sonuc$chunks >= 4L)
  expect_gte(.pk_clear_calls$n, 1L)
})

test_that("boş sonuç sütun sözleşmesini korur", {
  skip_if_not_installed("RSQLite")
  .pk_arm_clear_counter()

  conn <- .pk_sql_test_conn(10L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  sonuc <- pk_sql_execute_bounded(
    conn, "SELECT * FROM veri WHERE id < 0",
    unicode_param = FALSE, chunk_rows = 100L, max_result_mb = 512
  )

  expect_equal(sonuc$status, "ok")
  expect_equal(sonuc$rows, 0L)
  expect_true(is.data.frame(sonuc$data))
  expect_gte(.pk_clear_calls$n, 1L)
})

test_that("Türkçe metin parça getiriminde bozulmadan döner", {
  skip_if_not_installed("RSQLite")

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  turkce <- c(
    "İstanbul Projesi",           # I with dot above
    "Çankaya Şube",          # C-cedilla, S-cedilla
    "Kayıt Özeti",           # dotless i, O-umlaut
    "Ğaziantep Yatırım" # G-breve
  )
  DBI::dbWriteTable(conn, "t", data.frame(ad = turkce, stringsAsFactors = FALSE))

  sonuc <- pk_sql_execute_bounded(
    conn, "SELECT ad FROM t", unicode_param = FALSE,
    chunk_rows = 2L, max_result_mb = 512
  )

  expect_equal(sonuc$status, "ok")
  expect_equal(sonuc$rows, 4L)
  expect_equal(sonuc$data$ad, turkce)
})

test_that("getirimin ORTASINDA gelen iptal görülür ve veri DÖNMEZ", {
  skip_if_not_installed("RSQLite")
  .pk_arm_clear_counter()

  conn <- .pk_sql_test_conn(1000L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  cagri <- 0L
  sonuc <- pk_sql_execute_bounded(
    conn, "SELECT * FROM veri ORDER BY id",
    unicode_param = FALSE, chunk_rows = 100L, max_result_mb = 512,
    stage_gate = function() {
      cagri <<- cagri + 1L
      # İlk kapı geçer, ikinci parçadan sonra iptal edilir.
      if (cagri >= 3L) list(halt = TRUE, status = "cancelled") else list(halt = FALSE, status = "ok")
    }
  )

  expect_equal(sonuc$status, "cancelled")
  expect_null(sonuc$data)
  expect_equal(sonuc$rows, 0L)
  # KRİTİK: sonuç kümesi kapatılmış olmalıdır (bağlantı sızmaz).
  expect_gte(.pk_clear_calls$n, 1L)
})

test_that("son tarih dolması iptal ile KARIŞTIRILMAZ", {
  skip_if_not_installed("RSQLite")
  .pk_arm_clear_counter()

  conn <- .pk_sql_test_conn(500L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  sonuc <- pk_sql_execute_bounded(
    conn, "SELECT * FROM veri", unicode_param = FALSE,
    chunk_rows = 50L, max_result_mb = 512,
    stage_gate = function() list(halt = TRUE, status = "deadline")
  )

  expect_equal(sonuc$status, "deadline")
  expect_null(sonuc$data)
  expect_gte(.pk_clear_calls$n, 1L)
})

test_that("gerçek iptal jetonu getirimi durdurur (dosya tabanlı sinyal)", {
  skip_if_not_installed("RSQLite")
  .pk_arm_clear_counter()

  kok <- file.path(tempdir(), paste0("pk_sql_cancel_", as.integer(runif(1, 1, 1e9))))
  dir.create(kok, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  conn <- .pk_sql_test_conn(300L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  jeton <- pk_cancel_token_path("sql_iptal", base_dir = kok)
  pk_cancel_token_signal(jeton)

  sonuc <- pk_sql_execute_bounded(
    conn, "SELECT * FROM veri", unicode_param = FALSE,
    chunk_rows = 50L, max_result_mb = 512,
    stage_gate = function() pk_async_stage_gate(jeton, NULL)
  )

  expect_equal(sonuc$status, "cancelled")
  expect_gte(.pk_clear_calls$n, 1L)
})

test_that("tavanı aşacak parça KABUL EDİLMEDEN durulur", {
  skip_if_not_installed("RSQLite")
  .pk_arm_clear_counter()

  conn <- .pk_sql_test_conn(20000L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # Çok küçük bir tavan: ilk parçalar bile bütçeyi hızla doldurur.
  sonuc <- pk_sql_execute_bounded(
    conn, "SELECT * FROM veri", unicode_param = FALSE,
    chunk_rows = 5000L, max_result_mb = 0.05
  )

  expect_equal(sonuc$status, "too_large")
  expect_null(sonuc$data)
  expect_equal(sonuc$error, "would_exceed_max_result_mb")
  expect_gte(.pk_clear_calls$n, 1L)
})

test_that("boş SQL ve NULL bağlantı TİPLİ hata döner (stop atmaz)", {
  skip_if_not_installed("RSQLite")

  conn <- .pk_sql_test_conn(5L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  bos <- pk_sql_execute_bounded(conn, "   ", unicode_param = FALSE)
  expect_equal(bos$status, "error")
  expect_true(grepl("Bos SQL", bos$error, fixed = TRUE))

  baglantisiz <- pk_sql_execute_bounded(NULL, "SELECT 1", unicode_param = FALSE)
  expect_equal(baglantisiz$status, "error")
})

test_that("geçersiz SQL TİPLİ hata döner ve sonuç kümesi sızmaz", {
  skip_if_not_installed("RSQLite")
  .pk_arm_clear_counter()

  conn <- .pk_sql_test_conn(5L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  sonuc <- pk_sql_execute_bounded(
    conn, "SELECT * FROM olmayan_tablo", unicode_param = FALSE
  )
  expect_equal(sonuc$status, "error")
  expect_true(nzchar(sonuc$error))
  expect_gte(.pk_clear_calls$n, 1L)
})

test_that("ifade zaman aşımı uygulanamadığında analiz iptal EDİLMEZ", {
  skip_if_not_installed("RSQLite")

  conn <- .pk_sql_test_conn(5L)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # SQLite `SET LOCK_TIMEOUT` desteklemez: mekanizma "none" döner ama HATA ATMAZ.
  plan <- pk_sql_apply_statement_timeout(conn, 30L)
  expect_false(plan$applied)
  expect_equal(plan$mechanism, "none")
  expect_equal(plan$timeout_sec, 30L)

  # Geçersiz zaman aşımı da sessizce yok sayılır.
  expect_false(pk_sql_apply_statement_timeout(conn, 0L)$applied)
  expect_false(pk_sql_apply_statement_timeout(conn, NA)$applied)
  expect_false(pk_sql_apply_statement_timeout(NULL, 30L)$applied)
})
