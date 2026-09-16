# ==============================================================================
# Dosya Yolu: tests/testthat/test-vm-isolated-runner-locale-contract.R
# Aciklama: VM kanit kosucusunun Windows'ta LC_CTYPE'i zorlamadigini dogrular.
# ==============================================================================

testthat::test_that("Windows izole testthat kosucusu LC_CTYPE degerini zorlamaz", {
  yol <- file.path(
    resolve_repo_root_for_tests(),
    "tests", "scripts", "run_full_testthat_isolated.R"
  )

  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- rawToChar(ham)
  Encoding(metin) <- "UTF-8"

  koruma <- regexpr("if (.Platform$OS.type != 'windows') {", metin, fixed = TRUE)[1]
  locale_cagrisi <- regexpr("Sys.setlocale('LC_CTYPE'", metin, fixed = TRUE)[1]

  testthat::expect_gt(koruma, 0L)
  testthat::expect_gt(locale_cagrisi, koruma)
})
