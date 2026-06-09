# ==============================================================================
# Dosya Yolu: tests/testthat/test-upload-validator-branches.R
# Aciklama: validate_uploaded_file() icindeki ek dallari dogrular:
# - not_readable
# - basename fallback
# - uzanti normalize etme
# ==============================================================================

load_upload_env_for_tests <- function() {
  upload_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root_for_tests, "R", "utils_upload_validator.R"),
    encoding = "UTF-8",
    local = upload_env
  )

  upload_env
}

.make_dummy_upload_file <- function(size_bytes = 128L, filename = "RAPOR.PDF") {
  gecici_dir <- withr::local_tempdir(pattern = "upload-validator-", .local_envir = parent.frame())
  hedef <- file.path(gecici_dir, filename)

  con <- file(hedef, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(raw(size_bytes), con)

  hedef
}

test_that("validate_uploaded_file basename fallback ile calisabilir", {
  upload_env <- load_upload_env_for_tests()
  f <- .make_dummy_upload_file(size_bytes = 256L, filename = "RAPOR.PDF")

  sonuc <- upload_env$validate_uploaded_file(
    path = f,
    filename = NULL,
    allowed_ext = c(".pdf", ".docx")
  )

  expect_true(sonuc$ok)
  expect_null(sonuc$error)
  expect_null(sonuc$code)
})

test_that("validate_uploaded_file uzanti listesini normalize eder", {
  upload_env <- load_upload_env_for_tests()
  f <- .make_dummy_upload_file(size_bytes = 256L, filename = "RAPOR.PDF")

  sonuc <- upload_env$validate_uploaded_file(
    path = f,
    filename = "RAPOR.PDF",
    allowed_ext = c(".PDF", ".DOCX")
  )

  expect_true(sonuc$ok)
})

test_that("validate_uploaded_file okunamayan dosyada not_readable doner", {
  upload_env <- load_upload_env_for_tests()
  f <- .make_dummy_upload_file(size_bytes = 256L, filename = "RAPOR.PDF")

  assign(
    "file.access",
    function(names, mode = 0L) 1L,
    envir = upload_env
  )

  sonuc <- upload_env$validate_uploaded_file(
    path = f,
    filename = "RAPOR.PDF"
  )

  expect_false(sonuc$ok)
  expect_equal(sonuc$code, "not_readable")
})

test_that("validate_uploaded_file file.info boyutu NA ise sifir gibi ele alir", {
  upload_env <- load_upload_env_for_tests()
  f <- .make_dummy_upload_file(size_bytes = 256L, filename = "RAPOR.PDF")

  assign(
    "file.info",
    function(...) data.frame(size = NA_real_),
    envir = upload_env
  )

  sonuc <- upload_env$validate_uploaded_file(
    path = f,
    filename = "RAPOR.PDF",
    max_size_mb = 1L,
    allowed_ext = c("pdf")
  )

  expect_true(sonuc$ok)
})