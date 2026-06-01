# ==============================================================================
# Dosya Yolu: tests/testthat/test-utils-common-text-behavior.R
# Açıklama: R/utils_common.R içindeki, mevcut test-utils-common-behavior.R
#           tarafından doğrudan ÇAĞRILMAYAN saf yardımcıların DAVRANIŞSAL testleri:
#             - normalize_utf8_text (NULL/NA/boş/BOM/Türkçe/vektör + UTF-8 işareti)
#             - format_timestamp (GG.AA.YYYY - SS:DD biçimi)
#           (resolve_effective_user_id zaten test-effective-user-id.R kapsar.)
#           Saf base R (iconv / format / Sys.time); ağ/DB/Shiny/paket GEREKMEZ.
# ==============================================================================

.utilscommontext_source_once <- function() {
  if (!exists("normalize_utf8_text", envir = globalenv(),
              mode = "function", inherits = TRUE) ||
      !exists("format_timestamp", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "utils_common.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# normalize_utf8_text
# ------------------------------------------------------------------------------
testthat::test_that("normalize_utf8_text NULL/boş/NA kenar durumlarını kurallı döndürür", {
  .utilscommontext_source_once()
  testthat::expect_identical(normalize_utf8_text(NULL), "")
  testthat::expect_identical(normalize_utf8_text(character(0)), character(0))
  # NA -> "" (boş dizeye normalize edilir).
  testthat::expect_identical(normalize_utf8_text(NA_character_), "")
  # Boş dize aynen "" kalır.
  testthat::expect_identical(normalize_utf8_text(""), "")
})

testthat::test_that("normalize_utf8_text geçerli Türkçe metni korur ve UTF-8 işaretler", {
  .utilscommontext_source_once()
  metin <- "Türkçe çğıöşü ÇĞİÖŞÜ"
  donen <- normalize_utf8_text(metin)
  testthat::expect_identical(enc2utf8(donen), enc2utf8(metin))
  testthat::expect_identical(Encoding(donen), "UTF-8")
})

testthat::test_that("normalize_utf8_text baştaki BOM (U+FEFF) karakterini kaldırır", {
  .utilscommontext_source_once()
  # BOM, parser-güvenli biçimde deterministik olarak üretilir (görünmez literal yerine).
  bom_li_metin <- paste0(intToUtf8(0xFEFF), "merhaba")
  testthat::expect_identical(normalize_utf8_text(bom_li_metin), "merhaba")
})

testthat::test_that("normalize_utf8_text vektörü ve NA konumlarını korur", {
  .utilscommontext_source_once()
  girdi <- c("abc", NA, "def")
  donen <- normalize_utf8_text(girdi)
  testthat::expect_length(donen, 3L)
  testthat::expect_identical(donen[1], "abc")
  testthat::expect_identical(donen[2], "")   # NA -> ""
  testthat::expect_identical(donen[3], "def")
})

testthat::test_that("normalize_utf8_text sayısal girdiyi karaktere çevirir", {
  .utilscommontext_source_once()
  testthat::expect_identical(normalize_utf8_text(c(1L, 2L, 3L)), c("1", "2", "3"))
})

# ------------------------------------------------------------------------------
# format_timestamp
# ------------------------------------------------------------------------------
testthat::test_that("format_timestamp GG.AA.YYYY - SS:DD biçiminde tek dize döndürür", {
  .utilscommontext_source_once()
  ts <- format_timestamp()
  testthat::expect_length(ts, 1L)
  testthat::expect_true(is.character(ts))
  testthat::expect_match(
    ts,
    "^[0-9]{2}\\.[0-9]{2}\\.[0-9]{4} - [0-9]{2}:[0-9]{2}$",
    perl = TRUE
  )
})
