# ==============================================================================
# Dosya Yolu: tests/testthat/test-upload-validator.R
# Açıklama: validate_uploaded_file() fonksiyonunun path traversal reddi, boyut
# sınırı, uzantı beyaz listesi ve UTF-8 güvenliği davranışını doğrulayan
# birim testleri.
# ==============================================================================

local({
  if (!exists("validate_uploaded_file", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "utils_upload_validator.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

# Test yardımcıları.
.make_dummy_file <- function(size_bytes = 128L, filename = "deneme.docx") {
  gecici_dir <- tempfile("upload_")
  dir.create(gecici_dir, recursive = TRUE)
  hedef <- file.path(gecici_dir, filename)
  con <- file(hedef, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(raw(size_bytes), con)
  hedef
}

test_that("validate_uploaded_file geçerli dosyayı kabul eder", {
  f <- .make_dummy_file(size_bytes = 256L, filename = "rapor.docx")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  sonuc <- validate_uploaded_file(f, max_size_mb = 50L,
                                   allowed_ext = c("docx", "xlsx", "pdf"))
  expect_true(sonuc$ok)
  expect_null(sonuc$error)
})

test_that("validate_uploaded_file var olmayan yolu reddeder", {
  sonuc <- validate_uploaded_file("/tmp/kesinlikle_yok_12345.xlsx")
  expect_false(sonuc$ok)
  expect_equal(sonuc$code, "missing_path")
})

test_that("validate_uploaded_file NULL/boş yolu reddeder", {
  expect_equal(validate_uploaded_file(NULL)$code, "missing_path")
  expect_equal(validate_uploaded_file("")$code,    "missing_path")
})

test_that("validate_uploaded_file boyut sınırını aşan dosyayı reddeder", {
  # 2 MB'lik dosya, sınır 1 MB
  f <- .make_dummy_file(size_bytes = 2L * 1024L * 1024L, filename = "buyuk.bin")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  sonuc <- validate_uploaded_file(f, max_size_mb = 1L)
  expect_false(sonuc$ok)
  expect_equal(sonuc$code, "too_large")
})

test_that("validate_uploaded_file uzantı beyaz listesi dışını reddeder", {
  f <- .make_dummy_file(size_bytes = 64L, filename = "script.exe")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  sonuc <- validate_uploaded_file(
    f,
    allowed_ext = c("docx", "xlsx", "pdf")
  )
  expect_false(sonuc$ok)
  expect_equal(sonuc$code, "ext_not_allowed")
})

test_that("validate_uploaded_file path traversal girişini reddeder", {
  f <- .make_dummy_file(size_bytes = 64L, filename = "normal.txt")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  # Path traversal desenleri
  for (kotu_ad in c("../kacis.txt", "..\\kacis.txt", "klasor/alt.txt",
                     "klasor\\alt.txt", "/etc/passwd", "C:\\windows\\run.bat")) {
    sonuc <- validate_uploaded_file(f, filename = kotu_ad)
    expect_false(sonuc$ok, info = sprintf("Reddedilmeli: %s", kotu_ad))
    expect_equal(sonuc$code, "bad_filename",
                 info = sprintf("Kod eşleşmesi: %s", kotu_ad))
  }
})

test_that("validate_uploaded_file NUL bayt içeren dosya adını reddeder", {
  f <- .make_dummy_file(size_bytes = 64L, filename = "normal.txt")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  sonuc <- validate_uploaded_file(
    f,
    filename = paste0("guvenli", rawToChar(as.raw(0x00)), ".txt")
  )

  expect_false(sonuc$ok)
  expect_equal(sonuc$code, "bad_filename")
})

test_that("validate_uploaded_file beyaz liste uzantılarını noktalı ve büyük harfli kabul eder", {
  f <- .make_dummy_file(size_bytes = 64L, filename = "normal.txt")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  sonuc <- validate_uploaded_file(
    f,
    filename = "Özet-Rapor.PDF",
    allowed_ext = c(".pdf", ".docx")
  )

  expect_true(sonuc$ok)
  expect_null(sonuc$code)
})

test_that("validate_uploaded_file boyut sınırı NULL olunca atlar", {
  f <- .make_dummy_file(size_bytes = 10L * 1024L * 1024L, filename = "orta.bin")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  sonuc <- validate_uploaded_file(f, max_size_mb = NULL, allowed_ext = NULL)
  expect_true(sonuc$ok)
})

test_that("validate_uploaded_file Türkçe dosya adını korur", {
  f <- .make_dummy_file(size_bytes = 64L, filename = "Özet-Çalışma.docx")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  sonuc <- validate_uploaded_file(
    f,
    filename = "Özet-Çalışma.docx",
    allowed_ext = c("docx")
  )
  expect_true(sonuc$ok)
})

test_that("validate_uploaded_file geçersiz UTF-8 dosya adını reddeder", {
  f <- .make_dummy_file(size_bytes = 64L, filename = "normal.txt")
  on.exit(unlink(dirname(f), recursive = TRUE, force = TRUE))

  bad_byte <- rawToChar(as.raw(0xff))
  Encoding(bad_byte) <- "UTF-8"
  bad_name <- paste0(bad_byte, ".txt")
  Encoding(bad_name) <- "UTF-8"

  sonuc <- validate_uploaded_file(
    f,
    filename = bad_name,
    allowed_ext = c("txt")
  )

  expect_false(sonuc$ok)
  expect_equal(sonuc$code, "bad_encoding")
})