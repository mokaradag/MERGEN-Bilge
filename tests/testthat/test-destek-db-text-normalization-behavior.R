# ==============================================================================
# Dosya Yolu: tests/testthat/test-destek-db-text-normalization-behavior.R
# Açıklama: R/helpers_destek_database.R görünür-vs-teknik destek DB metin
#           normalizasyon yardımcılarının DAVRANIŞSAL testleri. Bu fonksiyonlar
#           mevcut testlerde HİÇ çağrılmıyordu:
#             - destek_normalize_visible_db_text  (mojibake ONARIR)
#             - destek_normalize_technical_db_text (mojibake ONARMAZ)
#             - destek_normalize_result_frame      (okuma çerçevesini onarır)
#           Destek geri bildirim/hata metinleri korumalı DB sınırıdır (CLAUDE.md).
#           Saf metin sınırı; DBI/ODBC/canlı DB GEREKMEZ.
# ==============================================================================

.destekdb_source_once <- function() {
  root <- resolve_repo_root_for_tests()
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "utils_text_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("destek_normalize_visible_db_text",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_destek_database.R"),
           encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# destek_normalize_visible_db_text (mojibake ONARIR)
# ------------------------------------------------------------------------------
testthat::test_that("destek_normalize_visible_db_text görünür mojibake'yi onarır", {
  .destekdb_source_once()
  testthat::expect_identical(destek_normalize_visible_db_text("TÃ¼rkiye"), "Türkiye")
  testthat::expect_identical(destek_normalize_visible_db_text("yardÄ±mcÄ±"), "yardımcı")
  # Zaten temiz Türkçe korunur.
  testthat::expect_identical(
    enc2utf8(destek_normalize_visible_db_text("İş Çözümü")),
    enc2utf8("İş Çözümü")
  )
})

testthat::test_that("destek_normalize_visible_db_text NULL/NA/boş için NA_character_ döner", {
  .destekdb_source_once()
  testthat::expect_identical(destek_normalize_visible_db_text(NULL), NA_character_)
  testthat::expect_identical(destek_normalize_visible_db_text(NA), NA_character_)
  testthat::expect_identical(destek_normalize_visible_db_text(character(0)), NA_character_)
})

# ------------------------------------------------------------------------------
# destek_normalize_technical_db_text (mojibake ONARMAZ)
# ------------------------------------------------------------------------------
testthat::test_that("destek_normalize_technical_db_text mojibake'yi ONARMAZ ama UTF-8 işaretler", {
  .destekdb_source_once()
  # Teknik alan (enum/yol vb.) ham bırakılır.
  testthat::expect_identical(destek_normalize_technical_db_text("TÃ¼rkiye"), "TÃ¼rkiye")
  testthat::expect_identical(destek_normalize_technical_db_text("acik"), "acik")
  testthat::expect_identical(Encoding(destek_normalize_technical_db_text("TÃ¼rkiye")), "UTF-8")
  # NULL/NA -> NA_character_.
  testthat::expect_identical(destek_normalize_technical_db_text(NULL), NA_character_)
  testthat::expect_identical(destek_normalize_technical_db_text(NA), NA_character_)
})

# ------------------------------------------------------------------------------
# destek_normalize_result_frame
# ------------------------------------------------------------------------------
testthat::test_that("destek_normalize_result_frame karakter sütunları onarır, sayısalı korur", {
  .destekdb_source_once()
  df <- data.frame(
    Aciklama = c("TÃ¼rkiye sorunu", "baÅŸka satir"),
    Sira = c(1L, 2L),
    stringsAsFactors = FALSE
  )
  donen <- destek_normalize_result_frame(df)
  testthat::expect_identical(donen$Aciklama[1], "Türkiye sorunu")
  testthat::expect_identical(donen$Aciklama[2], "başka satir")
  # Sayısal sütun değişmez.
  testthat::expect_identical(donen$Sira, c(1L, 2L))
})
