# ==============================================================================
# Dosya Yolu: tests/testthat/test-atomic-write.R
# Aciklama: atomic_write_text ve atomic_write_json yardimcilarinin basari,
# temizlik ve UTF-8 koruma davranislarini dogrulayan birim testleri.
# NOT:
# - Bu test dosyasi ASCII-guvenli tutulur.
# - Turkce metinler \u kacis dizileri ile tanimlanir.
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

read_utf8_text_strict <- function(path) {
  paste(
    readLines(path, encoding = "UTF-8", warn = FALSE),
    collapse = "\n"
  )
}

test_that("atomic_write_text hedef dosyayi atomik olarak uretir", {
  gecici_dir <- tempfile("atomic_")
  dir.create(gecici_dir, recursive = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE), add = TRUE)

  hedef <- file.path(gecici_dir, "ornek.txt")
  beklenen <- paste0(
    "\u0130stanbul \u00C7al\u0131\u015Fmas\u0131",
    "\n",
    "Sat\u0131r 2"
  )

  atomic_write_text(beklenen, hedef)
  expect_true(file.exists(hedef))

  okunan <- read_utf8_text_strict(hedef)

  expect_equal(enc2utf8(okunan), enc2utf8(beklenen))
})

test_that("atomic_write_text gecici dosyayi arkada birakmaz", {
  gecici_dir <- tempfile("atomic_clean_")
  dir.create(gecici_dir, recursive = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE), add = TRUE)

  hedef <- file.path(gecici_dir, "ornek.txt")
  atomic_write_text("deneme", hedef)

  artik <- list.files(
    gecici_dir,
    pattern = "^atomic_.*\\.tmp$",
    full.names = FALSE
  )

  expect_equal(length(artik), 0)
})

test_that("atomic_write_text gecersiz parametrelerde hata verir", {
  expect_error(atomic_write_text(NULL, tempfile()), "content")
  expect_error(atomic_write_text("x", ""), "final_path")
  expect_error(atomic_write_text("x", character(0)), "final_path")
})

test_that("atomic_write_json yazdigini jsonlite ile geri okunabilir", {
  gecici_dir <- tempfile("atomic_json_")
  dir.create(gecici_dir, recursive = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE), add = TRUE)

  hedef <- file.path(gecici_dir, "veri.json")

  veri <- list(
    ad = "\u00D6zet \u00C7al\u0131\u015Fma",
    adet = 3L,
    etiketler = c("t\u00FCrk\u00E7e", "rapor")
  )

  atomic_write_json(veri, hedef)

  geri <- jsonlite::fromJSON(hedef, simplifyVector = TRUE)
  expect_equal(enc2utf8(geri$ad), enc2utf8("\u00D6zet \u00C7al\u0131\u015Fma"))
  expect_equal(geri$adet, 3L)
  expect_equal(
    sort(enc2utf8(geri$etiketler)),
    sort(enc2utf8(c("t\u00FCrk\u00E7e", "rapor")))
  )
})

test_that("atomic_write_json cok buyuk ama basit yapiyi bozmadan yazar", {
  gecici_dir <- tempfile("atomic_big_")
  dir.create(gecici_dir, recursive = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE), add = TRUE)

  hedef <- file.path(gecici_dir, "buyuk.json")

  buyuk_liste <- as.list(seq_len(1000L))
  names(buyuk_liste) <- sprintf("kayit_%04d", seq_len(1000L))

  atomic_write_json(buyuk_liste, hedef)

  geri <- jsonlite::fromJSON(hedef, simplifyVector = FALSE)
  expect_equal(length(geri), 1000L)
  expect_equal(geri[["kayit_0500"]], 500L)
})