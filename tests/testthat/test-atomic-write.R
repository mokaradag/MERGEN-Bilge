# ==============================================================================
# Dosya Yolu: tests/testthat/test-atomic-write.R
# Açıklama: atomic_write_text ve atomic_write_json yardımcılarının başarı/başarısız
# ve Türkçe UTF-8 içerik koruma regresyonlarını doğrulayan birim testleri.
# ==============================================================================

local({
  if (!exists("atomic_write_text", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "utils_atomic_write.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

test_that("atomic_write_text hedef dosyayı atomik olarak üretir", {
  gecici_dir <- tempfile("atomic_")
  dir.create(gecici_dir, recursive = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE))
  hedef <- file.path(gecici_dir, "ornek.txt")

  atomic_write_text("İstanbul Çalışması\nSatır 2", hedef)
  expect_true(file.exists(hedef))

  okunan <- paste(readLines(hedef, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  expect_equal(enc2utf8(okunan), enc2utf8("İstanbul Çalışması\nSatır 2"))
})

test_that("atomic_write_text geçici dosyayı arkada bırakmaz", {
  gecici_dir <- tempfile("atomic_clean_")
  dir.create(gecici_dir, recursive = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE))
  hedef <- file.path(gecici_dir, "ornek.txt")

  atomic_write_text("deneme", hedef)

  # Aynı dizinde .tmp uzantılı atomic_ öneki taşıyan artık dosya kalmamalı.
  artik <- list.files(gecici_dir, pattern = "^atomic_.*\\.tmp$", full.names = FALSE)
  expect_equal(length(artik), 0)
})

test_that("atomic_write_text geçersiz parametrelerde hata verir", {
  expect_error(atomic_write_text(NULL, tempfile()),    "content")
  expect_error(atomic_write_text("x", ""),             "final_path")
  expect_error(atomic_write_text("x", character(0)),   "final_path")
})

test_that("atomic_write_json yazdığını jsonlite ile geri okunabilir", {
  gecici_dir <- tempfile("atomic_json_")
  dir.create(gecici_dir, recursive = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE))
  hedef <- file.path(gecici_dir, "veri.json")

  veri <- list(
    ad = "Özet Çalışma",
    adet = 3L,
    etiketler = c("türkçe", "rapor")
  )
  atomic_write_json(veri, hedef)

  geri <- jsonlite::fromJSON(hedef, simplifyVector = TRUE)
  expect_equal(geri$ad, "Özet Çalışma")
  expect_equal(geri$adet, 3L)
  expect_equal(sort(geri$etiketler), sort(c("türkçe", "rapor")))
})

test_that("atomic_write_json çok büyük ama basit yapıyı bozmadan yazar", {
  gecici_dir <- tempfile("atomic_big_")
  dir.create(gecici_dir, recursive = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE))
  hedef <- file.path(gecici_dir, "buyuk.json")

  buyuk_liste <- as.list(seq_len(1000L))
  names(buyuk_liste) <- sprintf("kayit_%04d", seq_len(1000L))
  atomic_write_json(buyuk_liste, hedef)

  geri <- jsonlite::fromJSON(hedef, simplifyVector = FALSE)
  expect_equal(length(geri), 1000L)
  expect_equal(geri[["kayit_0500"]], 500L)
})