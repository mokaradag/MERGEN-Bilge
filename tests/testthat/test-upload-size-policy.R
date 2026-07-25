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

# Sınır DOSYA BAŞINADIR: Shiny fileInput her dosyayı ayrı HTTP isteğiyle yükler
# (shiny.js FileUploader dosya dizinini tek tek ilerletir), bu yüzden
# shiny.maxRequestSize toplam parti boyutuna değil tek dosyaya uygulanır.
# Bu sözleşme UI metni ("Dosya başına en fazla N MB") ile tutarlıdır.
test_that("boyut sınırı toplu yüklemede dosya BAŞINA uygulanır", {
  .with_options(list(mergen.upload_max_mb = 25L), {
    kucuk_bir <- tempfile(fileext = ".txt")
    kucuk_iki <- tempfile(fileext = ".txt")
    .create_file_with_size(kucuk_bir, 20L * 1024L * 1024L)
    .create_file_with_size(kucuk_iki, 20L * 1024L * 1024L)

    # Toplam 40 MB > 25 MB olmasına rağmen her dosya tek tek geçerlidir.
    expect_true(validate_uploaded_file(kucuk_bir, "bir.txt", allowed_ext = "txt")$ok)
    expect_true(validate_uploaded_file(kucuk_iki, "iki.txt", allowed_ext = "txt")$ok)
  })
})

test_that("shiny.maxRequestSize merkezi upload sınırından türetilir", {
  global_txt <- readLines(file.path(.repo_root, "global.R"), warn = FALSE, encoding = "UTF-8")
  global_txt <- paste(global_txt, collapse = "\n")

  expect_true(grepl("shiny.maxRequestSize = mergen_upload_max_mb \\* 1024\\^2", global_txt, perl = TRUE))
  expect_false(grepl("30 \\* 1024\\^2", global_txt, perl = TRUE))
})

test_that("tarayıcı tarafı koruma her dosyayı ayrı ayrı denetler", {
  ui_txt <- readLines(
    file.path(.repo_root, "R", "module_file_manager_ui.R"),
    warn = FALSE, encoding = "UTF-8"
  )
  ui_txt <- paste(ui_txt, collapse = "\n")

  expect_true(grepl("for (var i = 0; i < files.length; i++)", ui_txt, fixed = TRUE))
  expect_true(grepl("files[i].size > maxBytes", ui_txt, fixed = TRUE))
  expect_true(grepl("Dosya başına en fazla", ui_txt, fixed = TRUE))
})