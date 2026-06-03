# ==============================================================================
# Dosya Yolu: tests/testthat/test-version-history-resolver-behavior.R
# Açıklama: R/config_version_history.R resolve_version_history_md_path() yol
#           çözümleyicisinin davranışsal testleri. CLAUDE.md sözleşmesi: önce
#           cwd'deki yerel version_history.md, sonra üst dizinlere doğru arama;
#           bulunamazsa start_dir altındaki varsayılan yola düşer.
# ==============================================================================

testthat::local_edition(3)

.vh_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "config_version_history.R"),
  encoding = "UTF-8",
  local = .vh_env
)

test_that("resolve_version_history_md_path cwd'deki yerel version_history.md'yi tercih eder", {
  tmp <- withr::local_tempdir()
  yol <- file.path(tmp, "version_history.md")
  writeLines("# v1.0", yol)

  sonuc <- .vh_env$resolve_version_history_md_path(tmp)

  expect_true(file.exists(sonuc))
  expect_equal(basename(sonuc), "version_history.md")
  expect_equal(
    normalizePath(sonuc, winslash = "/"),
    normalizePath(yol, winslash = "/")
  )
})

test_that("resolve_version_history_md_path üst dizinlere doğru arayarak depo kökündekini bulur", {
  # tests/testthat alt dizininden yukarı arama depo kökündeki dosyayı bulmalı.
  alt_dizin <- file.path(repo_root_for_tests, "tests", "testthat")
  sonuc <- .vh_env$resolve_version_history_md_path(alt_dizin)

  expect_true(file.exists(sonuc))
  expect_equal(basename(sonuc), "version_history.md")
})

test_that("resolve_version_history_md_path dosya yoksa start_dir altındaki varsayılana düşer", {
  tmp <- withr::local_tempdir()  # /tmp altında, üst zincirde version_history.md yok
  sonuc <- .vh_env$resolve_version_history_md_path(tmp)

  expect_equal(sonuc, file.path(tmp, "version_history.md"))
  expect_false(file.exists(sonuc))
})
