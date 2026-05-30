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

.dbesc_u <- function(codepoint) {
  intToUtf8(as.integer(codepoint))
}

testthat::test_that("db_unicode_escape_token kod noktasını ASCII belirtece çevirir", {
  .dbesc_source_once()
  testthat::expect_identical(db_unicode_escape_token(0x1F680), "[[MERGEN-U+1F680]]")
  testthat::expect_identical(db_unicode_escape_token(0xE7), "[[MERGEN-U+E7]]")
})

testthat::test_that("db_unicode_codepoint_supported_by_encoding kodlama kapsamını doğru raporlar", {
  .dbesc_source_once()
  e_acute <- utf8ToInt(.dbesc_u(0x00E9))

  # ASCII: yalnızca temel ASCII desteklenir.
  testthat::expect_true(db_unicode_codepoint_supported_by_encoding(utf8ToInt("A"), "ASCII"))
  testthat::expect_false(db_unicode_codepoint_supported_by_encoding(e_acute, "ASCII"))
  testthat::expect_false(db_unicode_codepoint_supported_by_encoding(0x1F680, "ASCII"))

  # latin1: e-acute desteklenir, emoji desteklenmez.
  testthat::expect_true(db_unicode_codepoint_supported_by_encoding(e_acute, "latin1"))
  testthat::expect_false(db_unicode_codepoint_supported_by_encoding(0x1F680, "latin1"))
  testthat::expect_false(db_unicode_codepoint_supported_by_encoding(NA, "ASCII"))
})

testthat::test_that("db_unicode_escape_for_client_encoding desteklenmeyen karakteri kaçırır, desteklenenleri korur", {
  .dbesc_source_once()
  rocket <- .dbesc_u(0x1F680)
  e_acute <- .dbesc_u(0x00E9)
  cafe_accented <- paste0("Caf", e_acute)

  # ASCII istemci kodlaması: emoji kaçar, ASCII metin aynı kalır.
  testthat::expect_identical(
    db_unicode_escape_for_client_encoding(paste0("Cafe", rocket), "ASCII"),
    "Cafe[[MERGEN-U+1F680]]"
  )

  # latin1 istemci kodlaması: e-acute korunur, emoji kaçar.
  testthat::expect_identical(
    db_unicode_escape_for_client_encoding(paste0(cafe_accented, rocket), "latin1"),
    paste0(cafe_accented, "[[MERGEN-U+1F680]]")
  )

  # NA ve boş kodlama güvenli işlenir.
  testthat::expect_identical(
    db_unicode_escape_for_client_encoding(c("A", NA), "ASCII"),
    c("A", NA)
  )
  testthat::expect_identical(
    db_unicode_escape_for_client_encoding(paste0("A", rocket), ""),
    paste0("A", rocket)
  )
})

testthat::test_that("db_unicode_escape_for_client_encoding UTF-8 istemcisinde dokunmaz", {
  .dbesc_source_once()
  rocket <- .dbesc_u(0x1F680)

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
    db_unicode_escape_for_client_encoding(paste0("A", rocket), "UTF-8"),
    paste0("A", rocket)
  )
})

testthat::test_that("db_unicode_restore_escapes belirteçleri orijinal karaktere geri açar", {
  .dbesc_source_once()
  rocket <- .dbesc_u(0x1F680)
  u_diaeresis <- .dbesc_u(0x00FC)
  plain_text <- paste0("d", u_diaeresis, "z metin")

  testthat::expect_identical(db_unicode_restore_escapes("[[MERGEN-U+1F680]]"), rocket)
  testthat::expect_identical(
    db_unicode_restore_escapes("Merhaba [[MERGEN-U+1F680]] dunya"),
    paste0("Merhaba ", rocket, " dunya")
  )

  # Belirteç yoksa metin değişmez.
  testthat::expect_identical(db_unicode_restore_escapes(plain_text), plain_text)
})

testthat::test_that("kaçış + geri açma tam tur eder (round-trip)", {
  .dbesc_source_once()
  rocket <- .dbesc_u(0x1F680)
  chart <- .dbesc_u(0x1F4CA)
  original <- paste0("Veri", rocket, "Analizi-", chart)

  escaped <- db_unicode_escape_for_client_encoding(original, "ASCII")

  # Kaçış sonrası ASCII güvenli olmalı (yüksek bayt içermemeli).
  testthat::expect_false(any(utf8ToInt(escaped) > 127L))
  testthat::expect_identical(db_unicode_restore_escapes(escaped), original)
})

testthat::test_that("normalize_db_read_visible_value ve frame okuma sınırında geri açar", {
  .dbesc_source_once()
  rocket <- .dbesc_u(0x1F680)

  testthat::expect_identical(
    normalize_db_read_visible_value("Mesaj [[MERGEN-U+1F680]]"),
    paste0("Mesaj ", rocket)
  )

  df <- data.frame(
    MessageContent = c("A [[MERGEN-U+1F680]]", "B"),
    MessageID = c("1", "2"),
    stringsAsFactors = FALSE
  )
  out <- normalize_db_read_visible_frame(df)
  testthat::expect_identical(out$MessageContent[1], paste0("A ", rocket))
  testthat::expect_identical(out$MessageID, c("1", "2"))  # teknik kolon değişmez
})