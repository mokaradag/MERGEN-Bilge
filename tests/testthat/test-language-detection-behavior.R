# ==============================================================================
# Dosya Yolu: tests/testthat/test-language-detection-behavior.R
# Açıklama: Kod/dil tespit yardımcılarının davranışsal testleri. Yalnızca
#           kesin/erken-dönüş senaryoları doğrulanır; karmaşık satır-oylama
#           dalları test edilmez. Girdiler ASCII tutularak Windows/Türkçe
#           grepl uyarı riski önlenir. DB, LLM, tarayıcı gerektirmez.
# ==============================================================================

.language_helpers_source_once <- function() {
  if (exists("detect_code_content", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("detect_language", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_language.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("detect_code_content boş/NULL girdide FALSE döner", {
  .language_helpers_source_once()

  testthat::expect_false(detect_code_content(NULL))
  testthat::expect_false(detect_code_content(""))
  testthat::expect_false(detect_code_content("   "))
})

testthat::test_that("detect_code_content güçlü kod göstergelerini yakalar", {
  .language_helpers_source_once()

  # Python fonksiyon tanımı güçlü göstergedir.
  testthat::expect_true(detect_code_content("def calculate(x):\n    return x * 2"))
  # SQL SELECT ... FROM bileşik kalıbı güçlü göstergedir.
  testthat::expect_true(detect_code_content("SELECT name FROM employees"))
})

testthat::test_that("detect_code_content düz metni kod saymaz", {
  .language_helpers_source_once()

  # Tek kelime / yapısal karakter içermeyen tek satır kod değildir.
  testthat::expect_false(detect_code_content("Merhaba"))
  testthat::expect_false(detect_code_content("Bu normal bir cumledir"))
})

testthat::test_that("detect_language düz metni text olarak döndürür", {
  .language_helpers_source_once()

  testthat::expect_identical(
    detect_language("Merhaba nasilsin bugun hava guzel"),
    "text"
  )
})

testthat::test_that("detect_language baskın kod kalıplarında doğru dili seçer", {
  .language_helpers_source_once()

  # def + import + self -> ezici biçimde Python.
  testthat::expect_identical(
    detect_language("def foo():\n    import os\n    self.x = 1"),
    "python"
  )

  # SELECT/FROM/WHERE -> kod olarak tespit edilmeli (text değil).
  sql_dili <- detect_language("SELECT id, name FROM users WHERE active = 1")
  testthat::expect_false(identical(sql_dili, "text"))
})
