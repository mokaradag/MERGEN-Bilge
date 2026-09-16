# ==============================================================================
# Dosya Yolu: tests/testthat/test-upload-validator-edge-cases.R
# Açıklama: validate_uploaded_file() için sınır durumlarını test eder.
# Amaç: upload doğrulayıcının hatalı parametrelerde çökmeden yapısal ret
#       döndürmesini ve güvenli varsayılanlara düşmesini garanti etmektir.
# ==============================================================================

.find_repo_root <- function() {
  adaylar <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (aday in adaylar) {
    if (file.exists(file.path(aday, "app.R")) &&
        dir.exists(file.path(aday, "R"))) {
      return(aday)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.repo_root <- .find_repo_root()

if (!exists("validate_uploaded_file", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(.repo_root, "R", "utils_upload_validator.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

.make_temp_upload <- function(name = "deneme.txt", content = "mergen") {
  path <- tempfile(fileext = paste0(".", tools::file_ext(name)))
  writeLines(content, path, useBytes = TRUE)
  path
}

test_that("validate_uploaded_file filename character(0) geldiğinde basename'e düşer", {
  path <- .make_temp_upload("guvenli.txt")

  sonuc <- validate_uploaded_file(
    path = path,
    filename = character(0),
    max_size_mb = 1,
    allowed_ext = "txt"
  )

  expect_true(sonuc$ok)
  expect_null(sonuc$code)
})

test_that("validate_uploaded_file filename NA geldiğinde basename'e düşer", {
  path <- .make_temp_upload("guvenli.txt")

  sonuc <- validate_uploaded_file(
    path = path,
    filename = NA_character_,
    max_size_mb = 1,
    allowed_ext = "txt"
  )

  expect_true(sonuc$ok)
  expect_null(sonuc$code)
})

test_that("validate_uploaded_file çoklu filename vektöründe ilk güvenli değeri kullanır", {
  path <- .make_temp_upload("guvenli.txt")

  sonuc <- validate_uploaded_file(
    path = path,
    filename = c("rapor.txt", "../evil.txt"),
    max_size_mb = 1,
    allowed_ext = "txt"
  )

  expect_true(sonuc$ok)
  expect_null(sonuc$code)
})

test_that("validate_uploaded_file geçersiz max_size_mb için yapısal ret döndürür", {
  path <- .make_temp_upload("guvenli.txt")

  sonuc <- validate_uploaded_file(
    path = path,
    filename = "guvenli.txt",
    max_size_mb = "abc",
    allowed_ext = "txt"
  )

  expect_false(sonuc$ok)
  expect_equal(sonuc$code, "bad_max_size")
})

test_that("validate_uploaded_file sıfır veya negatif max_size_mb için yapısal ret döndürür", {
  path <- .make_temp_upload("guvenli.txt")

  sonuc_sifir <- validate_uploaded_file(
    path = path,
    filename = "guvenli.txt",
    max_size_mb = 0,
    allowed_ext = "txt"
  )

  sonuc_negatif <- validate_uploaded_file(
    path = path,
    filename = "guvenli.txt",
    max_size_mb = -1,
    allowed_ext = "txt"
  )

  expect_false(sonuc_sifir$ok)
  expect_equal(sonuc_sifir$code, "bad_max_size")

  expect_false(sonuc_negatif$ok)
  expect_equal(sonuc_negatif$code, "bad_max_size")
})

test_that("validate_uploaded_file allowed_ext değerlerinde nokta ve büyük harfi normalize eder", {
  path <- .make_temp_upload("guvenli.txt")

  sonuc <- validate_uploaded_file(
    path = path,
    filename = "guvenli.txt",
    max_size_mb = 1,
    allowed_ext = c(".TXT", "PDF")
  )

  expect_true(sonuc$ok)
  expect_null(sonuc$code)
})

test_that("validate_uploaded_file path traversal isimlerini reddetmeye devam eder", {
  path <- .make_temp_upload("guvenli.txt")

  kotu_isimler <- c(
    "../evil.txt",
    "..\\evil.txt",
    "C:\\temp\\evil.txt",
    "/tmp/evil.txt",
    "alt/evil.txt"
  )

  for (isim in kotu_isimler) {
    sonuc <- validate_uploaded_file(
      path = path,
      filename = isim,
      max_size_mb = 1,
      allowed_ext = "txt"
    )

    expect_false(sonuc$ok)
    expect_equal(sonuc$code, "bad_filename")
  }
})

# Windows'ta ad bileşeninde geçersiz olan karakterler doğrulamadan GEÇMEMELİDİR;
# `:` sürücü öneki denetimine takılmadığı için kalıcı kopyalama aşamasında
# hata veriyordu.
test_that("Windows'ta geçersiz ad karakterleri reddedilir", {
  path <- .make_temp_upload("guvenli.txt")

  kotu_isimler <- c(
    "rapor:final.txt",
    "rapor<1>.txt",
    "rapor|1.txt",
    "rapor?.txt",
    "rapor*.txt",
    "rapor\".txt"
  )

  for (isim in kotu_isimler) {
    sonuc <- validate_uploaded_file(
      path = path,
      filename = isim,
      max_size_mb = 1,
      allowed_ext = "txt"
    )

    expect_false(sonuc$ok, info = isim)
    expect_equal(sonuc$code, "bad_filename", info = isim)
  }
})