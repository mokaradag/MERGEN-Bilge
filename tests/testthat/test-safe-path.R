# ==============================================================================
# Dosya Yolu: tests/testthat/test-safe-path.R
# Açıklama: safe_join_path() fonksiyonunun path traversal reddi, mutlak yol
# kaçışı reddi, NUL bayt reddi, Windows backslash ve Türkçe karakter
# desteğini doğrulayan birim testleri.
# ==============================================================================

local({
  if (!exists("safe_join_path", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "utils_safe_path.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

# Test için geçici bir taban dizini.
.make_temp_base <- function() {
  gecici_dir <- tempfile("safepath_")
  dir.create(gecici_dir, recursive = TRUE)
  gecici_dir
}

test_that("safe_join_path geçerli alt yolu birleştirir", {
  base <- .make_temp_base()
  on.exit(unlink(base, recursive = TRUE, force = TRUE))

  sonuc <- safe_join_path(base, "klasor/alt/dosya.txt")
  expect_false(is.null(sonuc))
  expect_true(endsWith(gsub("\\\\", "/", sonuc, fixed = FALSE),
                       "klasor/alt/dosya.txt"))
})

test_that("safe_join_path '..' ile kaçışı reddeder", {
  base <- .make_temp_base()
  on.exit(unlink(base, recursive = TRUE, force = TRUE))

  expect_null(safe_join_path(base, "../kacak.txt"))
  expect_null(safe_join_path(base, "alt/../../kacak.txt"))
  expect_null(safe_join_path(base, "..\\kacak.txt"))
})

test_that("safe_join_path mutlak yol girişini reddeder", {
  base <- .make_temp_base()
  on.exit(unlink(base, recursive = TRUE, force = TRUE))

  expect_null(safe_join_path(base, "/etc/passwd"))
  expect_null(safe_join_path(base, "C:/Windows/System32/config.sys"))
  expect_null(safe_join_path(base, "c:\\Windows\\regedit.exe"))
})

test_that("safe_join_path NUL bayt içeren segmenti reddeder", {
  base <- .make_temp_base()
  on.exit(unlink(base, recursive = TRUE, force = TRUE))

  kotu <- paste0("dosya", rawToChar(as.raw(0L)), ".txt")
  expect_null(safe_join_path(base, kotu))
})

test_that("safe_join_path NULL/boş/NA girişi reddeder", {
  base <- .make_temp_base()
  on.exit(unlink(base, recursive = TRUE, force = TRUE))

  expect_null(safe_join_path(base, NULL))
  expect_null(safe_join_path(base, ""))
  expect_null(safe_join_path(base, NA_character_))
  expect_null(safe_join_path(NULL, "dosya.txt"))
})

test_that("safe_join_path Windows ters slashlarını normalize eder", {
  base <- .make_temp_base()
  on.exit(unlink(base, recursive = TRUE, force = TRUE))

  # Güvenli ama Windows tarzı ayraç
  sonuc <- safe_join_path(base, "klasor\\alt\\ornek.docx")
  expect_false(is.null(sonuc))
  expect_true(endsWith(gsub("\\\\", "/", sonuc, fixed = FALSE),
                       "klasor/alt/ornek.docx"))
})

test_that("safe_join_path Türkçe karakterli güvenli yolu kabul eder", {
  base <- .make_temp_base()
  on.exit(unlink(base, recursive = TRUE, force = TRUE))

  sonuc <- safe_join_path(base, "İstanbul/Özet-Çalışma.docx")
  expect_false(is.null(sonuc))
  expect_true(grepl("İstanbul", sonuc, fixed = TRUE))
  expect_true(grepl("Özet-Çalışma.docx", sonuc, fixed = TRUE))
})
