# ==============================================================================
# Dosya Yolu: tests/testthat/test-mailto-encoding.R
# Açıklama:   Yardım Merkezi e-posta destek bağlantısının Türkçe karakterleri
#             Outlook/mailto sınırında UTF-8 percent-encoding ile koruduğunu sınar.
# ==============================================================================

testthat::test_that("mailto gövdesi Türkçe karakterleri UTF-8 percent-encoding ile korur", {
  encoded <- mergen_mailto_percent_encode("İyi çalışmalar dilerim,")

  testthat::expect_equal(
    encoded,
    "%C4%B0yi%20%C3%A7al%C4%B1%C5%9Fmalar%20dilerim%2C"
  )

  # Windows-1254 baytları mailto içine kaçmamalıdır.
  testthat::expect_false(grepl("%DD|%E7|%FD|%FE", encoded, ignore.case = TRUE))
})

testthat::test_that("mailto href konu ve gövde alanlarını güvenli ayırır", {
  href <- mergen_mailto_href(
    to = "destek@mergen.ai",
    subject = "MERGEN Bilge - Destek Talebi",
    body = paste0(
      "Merhaba MERGEN Bilge Destek Ekibi,\n\n",
      "Aşağıdaki konu hakkında desteğinize ihtiyacım bulunmaktadır:\n\n",
      "İyi çalışmalar dilerim,"
    )
  )

  testthat::expect_true(startsWith(href, "mailto:destek@mergen.ai?subject="))
  testthat::expect_true(grepl("&body=", href, fixed = TRUE))
  testthat::expect_true(grepl("%C4%B0yi%20%C3%A7al%C4%B1%C5%9Fmalar", href))
  testthat::expect_false(grepl("%DD|%E7|%FD|%FE", href, ignore.case = TRUE))
})