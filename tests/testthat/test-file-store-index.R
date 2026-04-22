# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-store-index.R
# Aciklama: .save_index / .load_index atomik yazim ve bozuk JSON dayanikliligi
# regresyonlarini koruyan testleri icerir.
# NOT:
# - Bu test dosyasi ASCII-guvenli tutulur.
# - Turkce metinler \\u kacis dizileri ile tanimlanir.
# ==============================================================================

test_that(".save_index yazdigini .load_index geri okur", {
  eski_yol <- MERGEN_INDEX_PATH
  gecici_dir <- tempfile("indextest_")
  dir.create(gecici_dir, recursive = TRUE)
  gecici_yol <- file.path(gecici_dir, "index.json")

  assign("MERGEN_INDEX_PATH", gecici_yol, envir = globalenv())
  on.exit({
    assign("MERGEN_INDEX_PATH", eski_yol, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  ornek_idx <- list(
    "42" = list(
      "rapor.docx" = list(
        path = file.path(gecici_dir, "rapor.docx"),
        display = "Rapor.docx"
      )
    )
  )

  .save_index(ornek_idx)
  expect_true(file.exists(gecici_yol))

  geri_okunan <- .load_index()
  expect_true(is.list(geri_okunan))
  expect_true(!is.null(geri_okunan[["42"]]))
  expect_equal(
    tolower(geri_okunan[["42"]][["rapor.docx"]]$display),
    "rapor.docx"
  )
})

test_that(".load_index dosya yoksa bos liste dondurur", {
  eski_yol <- MERGEN_INDEX_PATH
  gecici_dir <- tempfile("indexnone_")
  dir.create(gecici_dir, recursive = TRUE)
  gecici_yol <- file.path(gecici_dir, "index.json")

  assign("MERGEN_INDEX_PATH", gecici_yol, envir = globalenv())
  on.exit({
    assign("MERGEN_INDEX_PATH", eski_yol, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  sonuc <- .load_index()
  expect_true(is.list(sonuc))
  expect_equal(length(sonuc), 0)
})

test_that(".load_index bozuk JSON'da bos listeye duser ve yedek alir", {
  eski_yol <- MERGEN_INDEX_PATH
  gecici_dir <- tempfile("indexcorrupt_")
  dir.create(gecici_dir, recursive = TRUE)
  gecici_yol <- file.path(gecici_dir, "index.json")

  writeLines("{ bu tamamen bozuk json ", gecici_yol, useBytes = TRUE)

  assign("MERGEN_INDEX_PATH", gecici_yol, envir = globalenv())
  on.exit({
    assign("MERGEN_INDEX_PATH", eski_yol, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  sonuc <- .load_index()
  expect_true(is.list(sonuc))
  expect_equal(length(sonuc), 0)

  yedekler <- list.files(
    gecici_dir,
    pattern = "^index\\.json\\.corrupt_\\d+$",
    full.names = FALSE
  )
  expect_true(length(yedekler) >= 1L)
})

test_that(".save_index + .load_index Turkce display adlarini bozmaz", {
  eski_yol <- MERGEN_INDEX_PATH
  gecici_dir <- tempfile("indexutf8_")
  dir.create(gecici_dir, recursive = TRUE)
  gecici_yol <- file.path(gecici_dir, "index.json")

  assign("MERGEN_INDEX_PATH", gecici_yol, envir = globalenv())
  on.exit({
    assign("MERGEN_INDEX_PATH", eski_yol, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  turkce_display <- "\u00d6zet-\u00c7al\u0131\u015fma.docx"

  ornek_idx <- list(
    "7" = list(
      "ozet-calisma.docx" = list(
        path = file.path(gecici_dir, "ozet.docx"),
        display = turkce_display
      )
    )
  )

  .save_index(ornek_idx)
  geri_okunan <- .load_index()

  display_geri <- geri_okunan[["7"]][["ozet-calisma.docx"]]$display
  expect_identical(enc2utf8(display_geri), enc2utf8(turkce_display))
})