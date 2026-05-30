# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-unicode-escape-behavior.R
# Açıklama: R/helpers_db_unicode_escape.R DB-güvenli Unicode kaçış/geri açma
#           davranışsal testleri. DB istemci kodlamasının temsil edemediği
#           karakterler (ör. emoji) [[MERGEN-U+...]] ASCII belirtecine çevrilir
#           ve okuma sınırında geri açılır. Türkçe metin bütünlüğü korunur.
#           Platformlar arası belirlilik için ASCII/latin1 kodlamaları kullanılır
#           (iconv her sistemde destekler). Gerçek üretim fonksiyonları çağrılır.
# ==============================================================================

.dbesc_source_once <- function() {
  if (exists("db_unicode_escape_for_client_encoding", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_db_unicode_escape.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("db_unicode_escape_token kod noktasını ASCII belirtece çevirir", {
  .dbesc_source_once()
  testthat::expect_identical(db_unicode_escape_token(0x1F680), "[[MERGEN-U+1F680]]")
  testthat::expect_identical(db_unicode_escape_token(0xE7), "[[MERGEN-U+E7]]")
})

testthat::test_that("db_unicode_codepoint_supported_by_encoding kodlama kapsamını doğru raporlar", {
  .dbesc_source_once()
  # ASCII: yalnızca temel ASCII desteklenir.
  testthat::expect_true(db_unicode_codepoint_supported_by_encoding(utf8ToInt("A"), "ASCII"))
  testthat::expect_false(db_unicode_codepoint_supported_by_encoding(utf8ToInt("é"), "ASCII"))
  testthat::expect_false(db_unicode_codepoint_supported_by_encoding(0x1F680, "ASCII"))
  # latin1: é desteklenir, emoji desteklenmez.
  testthat::expect_true(db_unicode_codepoint_supported_by_encoding(utf8ToInt("é"), "latin1"))
  testthat::expect_false(db_unicode_codepoint_supported_by_encoding(0x1F680, "latin1"))
  testthat::expect_false(db_unicode_codepoint_supported_by_encoding(NA, "ASCII"))
})

testthat::test_that("db_unicode_escape_for_client_encoding desteklenmeyen karakteri kaçırır, desteklenenleri korur", {
  .dbesc_source_once()
  # ASCII istemci kodlaması: emoji kaçar, ASCII metin aynı kalır.
  testthat::expect_identical(
    db_unicode_escape_for_client_encoding("Cafe\U0001F680", "ASCII"),
    "Cafe[[MERGEN-U+1F680]]"
  )
  # latin1 istemci kodlaması: é korunur, emoji kaçar.
  testthat::expect_identical(
    db_unicode_escape_for_client_encoding("Café\U0001F680", "latin1"),
    "Café[[MERGEN-U+1F680]]"
  )
  # NA ve boş kodlama güvenli işlenir.
  testthat::expect_identical(
    db_unicode_escape_for_client_encoding(c("A", NA), "ASCII"),
    c("A", NA)
  )
  testthat::expect_identical(
    db_unicode_escape_for_client_encoding("A\U0001F680", ""),
    "A\U0001F680"
  )
})

testthat::test_that("db_unicode_escape_for_client_encoding UTF-8 istemcisinde dokunmaz", {
  .dbesc_source_once()
  # UTF-8 istemci kodlamasında kaçış uygulanmamalı.
  had <- exists("db_client_encoding_is_utf8", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("db_client_encoding_is_utf8", envir = globalenv()) else NULL
  assign("db_client_encoding_is_utf8",
         function(x) toupper(as.character(x)[1]) %in% c("UTF-8", "UTF8"),
         envir = globalenv())
  on.exit({
    if (had) assign("db_client_encoding_is_utf8", old, envir = globalenv())
    else if (exists("db_client_encoding_is_utf8", envir = globalenv(), inherits = FALSE)) {
      rm(list = "db_client_encoding_is_utf8", envir = globalenv())
    }
  }, add = TRUE)

  testthat::expect_identical(
    db_unicode_escape_for_client_encoding("A\U0001F680", "UTF-8"),
    "A\U0001F680"
  )
})

testthat::test_that("db_unicode_restore_escapes belirteçleri orijinal karaktere geri açar", {
  .dbesc_source_once()
  testthat::expect_identical(db_unicode_restore_escapes("[[MERGEN-U+1F680]]"), "\U0001F680")
  testthat::expect_identical(
    db_unicode_restore_escapes("Merhaba [[MERGEN-U+1F680]] dunya"),
    "Merhaba \U0001F680 dunya"
  )
  # Belirteç yoksa metin değişmez.
  testthat::expect_identical(db_unicode_restore_escapes("düz metin"), "düz metin")
})

testthat::test_that("kaçış + geri açma tam tur eder (round-trip)", {
  .dbesc_source_once()
  original <- "Veri\U0001F680Analizi-\U0001F4CA"  # iki emoji
  escaped <- db_unicode_escape_for_client_encoding(original, "ASCII")
  # Kaçış sonrası ASCII güvenli olmalı (yüksek bayt içermemeli).
  testthat::expect_false(any(utf8ToInt(escaped) > 127L))
  testthat::expect_identical(db_unicode_restore_escapes(escaped), original)
})

testthat::test_that("normalize_db_read_visible_value ve frame okuma sınırında geri açar", {
  .dbesc_source_once()
  testthat::expect_identical(
    normalize_db_read_visible_value("Mesaj [[MERGEN-U+1F680]]"),
    "Mesaj \U0001F680"
  )
  df <- data.frame(
    MessageContent = c("A [[MERGEN-U+1F680]]", "B"),
    MessageID = c("1", "2"),
    stringsAsFactors = FALSE
  )
  out <- normalize_db_read_visible_frame(df)
  testthat::expect_identical(out$MessageContent[1], "A \U0001F680")
  testthat::expect_identical(out$MessageID, c("1", "2"))  # teknik kolon değişmez
})
