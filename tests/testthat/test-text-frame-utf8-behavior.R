# ==============================================================================
# Dosya Yolu: tests/testthat/test-text-frame-utf8-behavior.R
# Açıklama: R/utils_text_encoding.R içindeki normalize_text_frame_utf8
#           yardımcısının DAVRANIŞSAL testleri. Diğer text-encoding davranış
#           testleri skaler/ağaç normalizasyonunu kapsar; data.frame sütun
#           normalizasyonu doğrudan çağrılarak test edilmiyordu:
#             - data.frame olmayan girdi değişmeden döner
#             - karakter sütunları UTF-8 olarak işaretlenir/normalize edilir
#             - factor seviyeleri normalize edilir, factor kalır
#             - sayısal/diğer sütunlar korunur
#             - repair_mojibake = TRUE mojibake'i onarır; FALSE korur
#           Türkçe/mojibake fikstürleri parser-güvenli Unicode inşasıyla kurulur
#           (intToUtf8). Shiny/DB/ağ GEREKMEZ; yalnızca base R.
# ==============================================================================

.textframe_source_once <- function() {
  if (exists("normalize_text_frame_utf8", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Kod noktalarından parser-güvenli karakter dizisi üretir.
.tf_cp <- function(...) intToUtf8(as.integer(c(...)))

# ------------------------------------------------------------------------------
# data.frame olmayan girdi
# ------------------------------------------------------------------------------
testthat::test_that("normalize_text_frame_utf8 data.frame olmayan girdiyi değiştirmeden döndürür", {
  .textframe_source_once()
  liste <- list(a = 1, b = "x")
  testthat::expect_identical(normalize_text_frame_utf8(liste), liste)
  testthat::expect_null(normalize_text_frame_utf8(NULL))
})

# ------------------------------------------------------------------------------
# Karakter ve sayısal sütunlar
# ------------------------------------------------------------------------------
testthat::test_that("normalize_text_frame_utf8 karakter sütununu UTF-8'e normalize eder, sayısalı korur", {
  .textframe_source_once()
  cagri <- .tf_cp(0x00C7, 0x0061, 0x011F, 0x0072, 0x0131)  # Çağrı
  omer  <- .tf_cp(0x00D6, 0x006D, 0x0065, 0x0072)          # Ömer

  df <- data.frame(
    num = c(1L, 2L),
    txt = c(cagri, omer),
    stringsAsFactors = FALSE
  )
  out <- normalize_text_frame_utf8(df)

  testthat::expect_identical(Encoding(out$txt[1]), "UTF-8")
  testthat::expect_identical(enc2utf8(out$txt), enc2utf8(c(cagri, omer)))
  # Sayısal sütun içerik olarak korunur
  testthat::expect_identical(out$num, c(1L, 2L))
})

# ------------------------------------------------------------------------------
# Factor seviyeleri
# ------------------------------------------------------------------------------
testthat::test_that("normalize_text_frame_utf8 factor seviyelerini normalize eder ve factor olarak korur", {
  .textframe_source_once()
  sube  <- .tf_cp(0x015E, 0x0075, 0x0062, 0x0065)  # Şube
  genel <- .tf_cp(0x0047, 0x0065, 0x006E, 0x0065, 0x006C)  # Genel

  df <- data.frame(f = factor(c(sube, genel, sube)), stringsAsFactors = FALSE)
  out <- normalize_text_frame_utf8(df)

  testthat::expect_true(is.factor(out$f))
  testthat::expect_identical(
    enc2utf8(levels(out$f)),
    enc2utf8(sort(c(sube, genel)))
  )
})

# ------------------------------------------------------------------------------
# Mojibake onarımı (opt-in)
# ------------------------------------------------------------------------------
testthat::test_that("normalize_text_frame_utf8 repair_mojibake bayrağına saygı duyar", {
  .textframe_source_once()
  moji <- .tf_cp(0x00C3, 0x00A7)  # "Ã§" (UTF-8 ç baytlarının latin1 yorumu)
  ceedilla <- .tf_cp(0x00E7)      # "ç"

  df <- data.frame(t = moji, stringsAsFactors = FALSE)

  # repair_mojibake = TRUE -> "Ã§" onarılıp "ç" olur
  onarildi <- normalize_text_frame_utf8(df, repair_mojibake = TRUE)
  testthat::expect_identical(enc2utf8(onarildi$t[1]), enc2utf8(ceedilla))

  # repair_mojibake = FALSE (varsayılan) -> değer korunur (yalnızca UTF-8 işaretlenir)
  korundu <- normalize_text_frame_utf8(df, repair_mojibake = FALSE)
  testthat::expect_identical(enc2utf8(korundu$t[1]), enc2utf8(moji))
})
