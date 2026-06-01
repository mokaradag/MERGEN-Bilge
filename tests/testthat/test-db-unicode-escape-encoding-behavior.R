# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-unicode-escape-encoding-behavior.R
# Açıklama: R/helpers_db_unicode_escape.R içindeki
#           db_unicode_escape_scalar_for_encoding yardımcısının DAVRANIŞSAL
#           testleri. Bu, DB istemci kodlamasının temsil edemediği Unicode
#           karakterleri ASCII jetonlara ([[MERGEN-U+...]]) çeviren güvenlik
#           sınırının çekirdek fonksiyonudur ve doğrudan çağrılarak test
#           edilmiyordu:
#             - NA/boş girdi değişmeden döner
#             - ASCII metin değişmeden döner
#             - WINDOWS-1254'ün desteklediği Türkçe karakterler korunur
#             - desteklenmeyen karakter (emoji) ASCII jetona kaçışlanır
#             - UTF-8 istemci kodlamasında emoji korunur
#           Sözleşme gereği tüm ASCII-olmayan fikstürler intToUtf8 ile
#           deterministik kurulur. Shiny/DB/ağ GEREKMEZ; yalnızca base R.
# ==============================================================================

.dbesc_source_once <- function() {
  if (exists("db_unicode_escape_scalar_for_encoding", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_db_unicode_escape.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Kod noktalarından parser-güvenli karakter dizisi üretir.
.dbesc_cp <- function(...) intToUtf8(as.integer(c(...)))

# ------------------------------------------------------------------------------
# Boş / NA / ASCII
# ------------------------------------------------------------------------------
testthat::test_that("db_unicode_escape_scalar_for_encoding NA/boş/ASCII girdiyi değiştirmez", {
  .dbesc_source_once()
  testthat::expect_true(is.na(db_unicode_escape_scalar_for_encoding(NA_character_, "WINDOWS-1254")))
  testthat::expect_identical(db_unicode_escape_scalar_for_encoding("", "WINDOWS-1254"), "")
  testthat::expect_identical(
    db_unicode_escape_scalar_for_encoding("plain ascii 123", "WINDOWS-1254"),
    "plain ascii 123"
  )
})

# ------------------------------------------------------------------------------
# WINDOWS-1254 destekli Türkçe
# ------------------------------------------------------------------------------
testthat::test_that("db_unicode_escape_scalar_for_encoding WINDOWS-1254 destekli Türkçe karakterleri korur", {
  .dbesc_source_once()
  # "Türkçe ç ğ ı ş ö ü" tüm karakterleri WINDOWS-1254 tarafından desteklenir
  turkce <- .dbesc_cp(
    0x0054, 0x00FC, 0x0072, 0x006B, 0x00E7, 0x0065, 0x0020,
    0x00E7, 0x0020, 0x011F, 0x0020, 0x0131, 0x0020,
    0x015F, 0x0020, 0x00F6, 0x0020, 0x00FC
  )
  out <- db_unicode_escape_scalar_for_encoding(turkce, "WINDOWS-1254")
  testthat::expect_identical(enc2utf8(out), enc2utf8(turkce))
  # Hiç kaçış jetonu eklenmemeli
  testthat::expect_false(grepl("[[MERGEN-U+", out, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Desteklenmeyen karakter -> ASCII jeton
# ------------------------------------------------------------------------------
testthat::test_that("db_unicode_escape_scalar_for_encoding desteklenmeyen emoji'yi ASCII jetona kaçışlar", {
  .dbesc_source_once()
  roket <- .dbesc_cp(0x1F680)  # roket emoji, WINDOWS-1254 tarafından temsil edilemez
  testthat::expect_identical(
    db_unicode_escape_scalar_for_encoding(roket, "WINDOWS-1254"),
    "[[MERGEN-U+1F680]]"
  )

  # Metin içine gömülü emoji yalnızca ilgili kod noktasını kaçışlar
  gomulu <- paste0("Ata", roket, "son")
  testthat::expect_identical(
    db_unicode_escape_scalar_for_encoding(gomulu, "WINDOWS-1254"),
    "Ata[[MERGEN-U+1F680]]son"
  )
})

testthat::test_that("db_unicode_escape_scalar_for_encoding UTF-8 istemci kodlamasında emoji'yi korur", {
  .dbesc_source_once()
  roket <- .dbesc_cp(0x1F680)
  out <- db_unicode_escape_scalar_for_encoding(roket, "UTF-8")
  testthat::expect_identical(enc2utf8(out), enc2utf8(roket))
  testthat::expect_false(grepl("[[MERGEN-U+", out, fixed = TRUE))
})
