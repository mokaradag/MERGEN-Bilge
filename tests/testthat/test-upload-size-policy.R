# ==============================================================================
# Dosya Yolu: tests/testthat/test-upload-size-policy.R
# Açıklama: Üretim dosya yükleme boyut sınırının 25 MB varsayılanını doğrular.
# Büyük dosya gerçek içerikle oluşturulmaz; dosya bağlantısında seek kullanılarak
# hızlı ve düşük maliyetli test yapılır.
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

.with_options <- function(new_options, code) {
  eski <- options()
  on.exit(options(eski), add = TRUE)
  do.call(options, new_options)
  force(code)
}

.create_file_with_size <- function(path, size_bytes) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)

  seek(con, where = size_bytes - 1L, origin = "start")
  writeBin(as.raw(0), con)

  invisible(path)
}

test_that("varsayılan upload sınırı 25 MB olarak ayarlanabilir", {
  .with_options(list(mergen.upload_max_mb = 25L), {
    expect_equal(getOption("mergen.upload_max_mb"), 25L)
  })
})

test_that("25 MB altındaki dosya kabul edilir", {
  .with_options(list(mergen.upload_max_mb = 25L), {
    path <- tempfile(fileext = ".txt")
    .create_file_with_size(path, 24L * 1024L * 1024L)

    sonuc <- validate_uploaded_file(
      path = path,
      filename = "kabul.txt",
      allowed_ext = "txt"
    )

    expect_true(sonuc$ok)
    expect_null(sonuc$code)
  })
})

test_that("25 MB üstündeki dosya reddedilir", {
  .with_options(list(mergen.upload_max_mb = 25L), {
    path <- tempfile(fileext = ".txt")
    .create_file_with_size(path, 26L * 1024L * 1024L)

    sonuc <- validate_uploaded_file(
      path = path,
      filename = "buyuk.txt",
      allowed_ext = "txt"
    )

    expect_false(sonuc$ok)
    expect_equal(sonuc$code, "too_large")
  })
})