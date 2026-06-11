# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-store-index-lock-behavior.R
# Açıklama: Dosya deposu indeks kilidi davranış sözleşmesi.
#           - Normal yol: kilit alınır, ifade çalışır, kilit temizlenir.
#           - Eski (stale) kilit: çökmüş süreçten kalan kilit dizini yaşına
#             bakılarak kırılır; mutasyonlar kalıcı 5 sn gecikme + kalıcı
#             kilitsiz moda düşmez.
#           - Taze kilit: belgelenmiş erişilebilirlik-öncelikli davranış
#             korunur; timeout sonrası ifade yine de çalışır ve taze kilit
#             dizinine dokunulmaz.
#           Gerçek DB, ağ, tarayıcı veya LLM gerektirmez; tüm yollar
#           helper_load_file_store.R tarafından tempdir altına alınmıştır.
# ==============================================================================

.lock_test_lock_dir <- function() {
  paste0(MERGEN_INDEX_PATH, ".lock")
}

.lock_test_cleanup <- function() {
  unlink(.lock_test_lock_dir(), recursive = TRUE, force = TRUE)
}

test_that("kilit serbestken ifade kilit altinda calisir ve kilit temizlenir", {
  .lock_test_cleanup()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()
  lock_seen_during_expr <- FALSE

  result <- .file_store_with_index_lock({
    lock_seen_during_expr <- dir.exists(lock_dir)
    "calisti"
  })

  expect_identical(result, "calisti")
  expect_true(lock_seen_during_expr, info = "İfade çalışırken kilit dizini mevcut olmalıdır.")
  expect_false(dir.exists(lock_dir), info = "İfade bittikten sonra kilit dizini temizlenmelidir.")
})

test_that("eski (stale) kilit kirilir ve mutasyon kilidi devralir", {
  .lock_test_cleanup()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()

  # Çökmüş bir sürecin bıraktığı eski kilidi simüle et: kilit dizinini oluştur
  # ve mtime değerini stale eşiğinin (test için 1 sn) gerisine çek.
  dir.create(lock_dir, recursive = TRUE, showWarnings = FALSE)
  eski_zaman <- Sys.time() - 3600
  expect_true(
    suppressWarnings(Sys.setFileTime(lock_dir, eski_zaman)),
    info = "Test ortamında kilit dizini mtime ayarlanabilmelidir."
  )

  start_time <- Sys.time()
  result <- .file_store_with_index_lock(
    {
      "stale-kirildi"
    },
    timeout_sec = 5,
    poll_sec = 0.01,
    stale_lock_sec = 1
  )
  gecen_sure <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  expect_identical(result, "stale-kirildi")
  expect_false(
    dir.exists(lock_dir),
    info = "Eski kilit kırıldıktan ve ifade bittikten sonra kilit dizini kalmamalıdır."
  )
  expect_lt(
    gecen_sure,
    4,
    label = "Eski kilit kırma süresi (timeout'a kadar beklememeli)"
  )
})

test_that("taze kilit belgelenmis erisebilirlik-oncelikli davranisi korur", {
  .lock_test_cleanup()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()

  # Başka bir sürecin AKTİF (taze) kilidini simüle et: mtime şu an.
  dir.create(lock_dir, recursive = TRUE, showWarnings = FALSE)

  result <- .file_store_with_index_lock(
    {
      "kilitsiz-devam"
    },
    timeout_sec = 0.2,
    poll_sec = 0.05,
    stale_lock_sec = 3600
  )

  expect_identical(
    result,
    "kilitsiz-devam",
    info = "Taze kilit timeout'unda ifade yine de çalışmalıdır (mevcut davranış korunur)."
  )
  expect_true(
    dir.exists(lock_dir),
    info = "Taze (aktif) kilit dizini kırılmamalı; sahibinin temizlemesi beklenir."
  )
})

test_that("mutasyon yardimcisi stale kilit sonrasi indeks kaydini kaybetmez", {
  .lock_test_cleanup()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()

  # Eski kilit mevcutken gerçek bir indeks mutasyonu çalıştır.
  dir.create(lock_dir, recursive = TRUE, showWarnings = FALSE)
  suppressWarnings(Sys.setFileTime(lock_dir, Sys.time() - 3600))

  marker_key <- paste0("stale_lock_probe_", as.integer(Sys.time()))

  sonuc <- .file_store_mutate_index(function(idx) {
    idx[[marker_key]] <- list(probe = TRUE)
    idx
  })

  expect_true(
    is.list(sonuc) && !is.null(sonuc[[marker_key]]),
    info = "Stale kilit senaryosunda mutasyon sonucu kaybolmamalıdır."
  )

  yeniden_yuklenen <- .load_index()
  expect_true(
    !is.null(yeniden_yuklenen[[marker_key]]),
    info = "Mutasyon, indeks dosyasına kalıcı olarak yazılmış olmalıdır."
  )

  # Temizlik: probe kaydını indeksten kaldır.
  .file_store_mutate_index(function(idx) {
    idx[[marker_key]] <- NULL
    idx
  })
})
