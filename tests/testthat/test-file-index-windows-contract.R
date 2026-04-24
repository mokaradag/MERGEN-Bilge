# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-index-windows-contract.R
# Açıklama: Dosya indeks mekanizmasının Windows VM, Türkçe dosya adı ve eksik
# klasör senaryolarında deterministik ve güvenli davranmasını doğrular.
# ==============================================================================

test_that(".build_basename_index eksik klasörde çökmeden boş indeks döndürür", {
  missing_dir <- file.path(tempdir(), paste0("missing-index-dir-", sample.int(1e6, 1)))

  idx <- .build_basename_index(missing_dir, force = TRUE)

  expect_type(idx, "list")
  expect_true("ts" %in% names(idx))
  expect_true("map" %in% names(idx))
  expect_type(idx$map, "list")
  expect_equal(length(idx$map), 0L)
})

test_that("dosya indeksi Türkçe dosya adını UTF-8 koruyarak bulur", {
  root <- withr::local_tempdir(pattern = "mergen-file-index-")
  nested <- file.path(root, "alt_klasor")
  dir.create(nested, recursive = TRUE, showWarnings = FALSE)

  file_name <- "Çalışma Planı.xlsx"
  file_path <- file.path(nested, file_name)
  writeBin(charToRaw("dummy"), file_path)

  idx <- .build_basename_index(root, force = TRUE)
  expected_key <- tolower(basename(file_path))

  expect_true(expected_key %in% names(idx$map))

  hit <- .search_from_index(root, file_name)

  expect_true(path_exists_relaxed(hit))
  expect_identical(
    normalizePath(hit, winslash = "/", mustWork = TRUE),
    normalizePath(file_path, winslash = "/", mustWork = TRUE)
  )
})

test_that("dosya indeksi aynı içerik için deterministik isim sırası üretir", {
  root <- withr::local_tempdir(pattern = "mergen-file-index-deterministic-")
  dir.create(file.path(root, "b"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "a"), recursive = TRUE, showWarnings = FALSE)

  writeBin(charToRaw("1"), file.path(root, "b", "rapor.pdf"))
  writeBin(charToRaw("2"), file.path(root, "a", "rapor.pdf"))

  idx1 <- .build_basename_index(root, force = TRUE)
  idx2 <- .build_basename_index(root, force = TRUE)

  expect_equal(names(idx1$map), names(idx2$map))
  expect_equal(idx1$map[["rapor.pdf"]], idx2$map[["rapor.pdf"]])
})