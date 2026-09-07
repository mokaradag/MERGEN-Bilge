# ==============================================================================
# Dosya Yolu: tests/testthat/test-atomic-write-fallback.R
# Aciklama: atomic_write_text() icindeki rename->copy fallback yolunu ve
# tam-basarisizlik hata yolunu dogrular.
# ==============================================================================

load_atomic_env_for_tests <- function() {
  atomic_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root_for_tests, "R", "utils_atomic_write.R"),
    encoding = "UTF-8",
    local = atomic_env
  )

  atomic_env
}

read_file_text_utf8 <- function(path) {
  raw_to_read <- readBin(path, what = "raw", n = file.info(path)$size)
  rawToChar(raw_to_read)
}

test_that("atomic_write_text file.rename basarisiz olursa file.copy fallback kullanir", {
  atomic_env <- load_atomic_env_for_tests()
  gecici_dir <- withr::local_tempdir(pattern = "atomic-fallback-")
  hedef <- file.path(gecici_dir, "ornek.txt")

  copied <- FALSE

  assign(
    "file.rename",
    function(from, to) FALSE,
    envir = atomic_env
  )

  assign(
    "file.copy",
    function(from, to, overwrite = FALSE, ...) {
      copied <<- TRUE
      base::file.copy(from, to, overwrite = overwrite, ...)
    },
    envir = atomic_env
  )

  expect_no_error(
    atomic_env$atomic_write_text("mergen-fallback-ok", hedef)
  )

  expect_true(copied)
  expect_true(file.exists(hedef))
  expect_equal(read_file_text_utf8(hedef), "mergen-fallback-ok")

  artik <- list.files(
    gecici_dir,
    pattern = "^atomic_.*\\.tmp$",
    full.names = FALSE
  )
  expect_equal(length(artik), 0)
})

test_that("atomic_write_text rename ve copy birlikte basarisiz olursa net hata verir", {
  atomic_env <- load_atomic_env_for_tests()
  gecici_dir <- withr::local_tempdir(pattern = "atomic-hard-fail-")
  hedef <- file.path(gecici_dir, "ornek.txt")

  assign(
    "file.rename",
    function(from, to) FALSE,
    envir = atomic_env
  )

  assign(
    "file.copy",
    function(from, to, overwrite = FALSE, ...) FALSE,
    envir = atomic_env
  )

  expect_error(
    atomic_env$atomic_write_text("x", hedef),
    "hedefe taşıma başarısız"
  )
})