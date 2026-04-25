# ==============================================================================
# Dosya Yolu: tests/testthat/test-safe-source-encoding-contract.R
# Açıklama: Windows VM üzerinde kaynak dosya yükleme kodlama dayanıklılığını
# doğrular. Amaç, UTF-8 BOM ve Türkçe karakter içeren dosyaların safe_source()
# ile sorunsuz yüklenmesini garanti altına almaktır.
# ==============================================================================

test_that("safe_source UTF-8 BOM ve Türkçe karakter içeren dosyayı yükler", {
  repo_root <- resolve_repo_root_for_tests()

  source(
    file.path(repo_root, "R", "utils_safe_source.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  tmp_dir <- tempfile("safe-source-bom-")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  target_file <- file.path(tmp_dir, "turkce_bom_test.R")

  code <- paste0(
    "turkce_deger <- \"İşçi, görüş, çağrı, Ülgen, Mergen\"\n",
    "turkce_fonksiyon <- function() turkce_deger\n"
  )

  raw_code <- charToRaw(enc2utf8(code))
  bom <- as.raw(c(0xEF, 0xBB, 0xBF))

  con <- file(target_file, open = "wb")
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  writeBin(c(bom, raw_code), con)
  close(con)

  env <- new.env(parent = globalenv())

  expect_no_error(
    safe_source(target_file, encoding = "UTF-8", envir = env)
  )

  expect_true(exists("turkce_deger", envir = env, inherits = FALSE))
  expect_true(exists("turkce_fonksiyon", envir = env, inherits = FALSE))

  expect_identical(
    get("turkce_fonksiyon", envir = env)(),
    "İşçi, görüş, çağrı, Ülgen, Mergen"
  )
})

test_that("safe_source normal parse hatasını encoding fallback diye yutmaz", {
  repo_root <- resolve_repo_root_for_tests()

  source(
    file.path(repo_root, "R", "utils_safe_source.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  tmp_dir <- tempfile("safe-source-parse-error-")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  target_file <- file.path(tmp_dir, "broken_code.R")

  writeLines(
    c(
      "x <- 1",
      "if (TRUE) {",
      "  y <- 2"
      # Kapanış süslü parantezi bilerek yok.
    ),
    target_file,
    useBytes = TRUE
  )

  env <- new.env(parent = globalenv())

  expect_error(
    safe_source(target_file, encoding = "UTF-8", envir = env)
  )
})