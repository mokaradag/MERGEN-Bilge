# ==============================================================================
# Dosya Yolu: tests/testthat/test-split-text-and-code-behavior.R
# Açıklama: R/helpers_language.R split_text_and_code DAVRANIŞSAL testleri. Bu
#           sezgisel ayrıştırıcı, "önce düz metin sonra kod" kalıbını tespit
#           eder; aksi durumlarda (backtick bloğu, <=2 satır, tamamı kod, tamamı
#           metin, ilk satır kod, parça çok kısa) NULL döndürür. Sınıflandırma
#           ignore.case regex kullandığından fixture'lar ASCII tutulur (Türkçe
#           locale tolower farklılıklarından kaçınmak için). Saf base R.
# ==============================================================================

.splitcode_source_once <- function() {
  if (exists("split_text_and_code", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_language.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("split_text_and_code ayrıştırılamayan girdilerde NULL döner", {
  .splitcode_source_once()
  # Markdown kod bloğu (```): normal ayrıştırıcıya bırakılır.
  testthat::expect_null(split_text_and_code("acikla\n```\ncode\n```"))
  # 2 veya daha az satır.
  testthat::expect_null(split_text_and_code("satir1\nSELECT * FROM t WHERE id=1"))
  testthat::expect_null(split_text_and_code(""))
  # Tamamı metin.
  testthat::expect_null(
    split_text_and_code("Bu bir cumledir\nBu da baska bir cumle\nUcuncu cumle burada")
  )
  # Tamamı kod.
  testthat::expect_null(
    split_text_and_code("SELECT * FROM a WHERE x = 1\nINNER JOIN b ON a.id = b.id\nGROUP BY x")
  )
  # İlk anlamlı satır kod ise ayırma yapılmaz.
  testthat::expect_null(
    split_text_and_code("SELECT * FROM users WHERE id = 1\nBu sorgu kullanicilari listeler\nbaska aciklama metni")
  )
})

testthat::test_that("split_text_and_code 'önce metin sonra kod' kalıbını yapısal olarak ayırır", {
  .splitcode_source_once()
  giris <- paste(
    "Bu sorgu kullanicilari listeler",
    "Asagidaki komutu calistirin",
    "SELECT * FROM users WHERE id = 1",
    sep = "\n"
  )
  res <- split_text_and_code(giris)

  testthat::expect_true(is.list(res))
  testthat::expect_named(res, c("text_before", "code", "text_after"))
  testthat::expect_identical(
    res$text_before,
    "Bu sorgu kullanicilari listeler\nAsagidaki komutu calistirin"
  )
  testthat::expect_identical(res$code, "SELECT * FROM users WHERE id = 1")
  # Bu yardımcı yalnızca metin->kod ayırır; text_after daima boştur.
  testthat::expect_identical(res$text_after, "")
})
