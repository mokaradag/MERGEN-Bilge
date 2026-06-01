# ==============================================================================
# Dosya Yolu: tests/testthat/test-text-encoding-log-frame-behavior.R
# Açıklama: R/utils_text_encoding.R içindeki, mevcut
#           test-text-encoding-mojibake-behavior.R tarafından çağrılmayan
#           yardımcıların DAVRANIŞSAL testleri:
#             - normalize_text_for_log (mojibake onarımı + ANSI temizleme)
#             - read_text_lines_utf8 (bayt-güvenli UTF-8 dosya okuma)
#             - mark_text_tree_utf8 (özyinelemeli UTF-8 işaretleme)
#           ANSI ESC karakteri, parser-güvenli biçimde intToUtf8(27) ile üretilir.
#           Saf base R (iconv/readBin); ağ/DB/Shiny GEREKMEZ.
# ==============================================================================

.utelog_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("normalize_text_for_log",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

.utelog_esc <- intToUtf8(27L)  # ANSI ESC (U+001B)

# ------------------------------------------------------------------------------
# normalize_text_for_log
# ------------------------------------------------------------------------------
testthat::test_that("normalize_text_for_log mojibake'yi onarır ve ANSI dizilerini temizler", {
  .utelog_source_once()
  # Mojibake onarımı (repair_mojibake = TRUE).
  testthat::expect_identical(normalize_text_for_log("TÃ¼rkiye"), "Türkiye")
  # ANSI renk dizileri temizlenir (strip_ansi = TRUE).
  ansi_metin <- paste0(.utelog_esc, "[31mhata", .utelog_esc, "[0m")
  testthat::expect_identical(normalize_text_for_log(ansi_metin), "hata")
  # Birleşik: mojibake + ANSI.
  birlesik <- paste0(.utelog_esc, "[1m", "NasÄ±l", .utelog_esc, "[0m")
  testthat::expect_identical(normalize_text_for_log(birlesik), "Nasıl")
})

testthat::test_that("normalize_text_for_log NULL/karakter-olmayanı değiştirmez", {
  .utelog_source_once()
  testthat::expect_null(normalize_text_for_log(NULL))
  testthat::expect_identical(normalize_text_for_log(123L), 123L)
})

# ------------------------------------------------------------------------------
# read_text_lines_utf8
# ------------------------------------------------------------------------------
testthat::test_that("read_text_lines_utf8 UTF-8 dosyayı satırlara böler ve Türkçeyi korur", {
  .utelog_source_once()
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)
  con <- file(tmp, open = "wb")
  writeBin(charToRaw(enc2utf8("Türkçe satır\nİkinci satır")), con)
  close(con)

  satirlar <- read_text_lines_utf8(tmp)
  testthat::expect_length(satirlar, 2L)
  testthat::expect_identical(enc2utf8(satirlar[1]), enc2utf8("Türkçe satır"))
  testthat::expect_identical(enc2utf8(satirlar[2]), enc2utf8("İkinci satır"))
})

testthat::test_that("read_text_lines_utf8 eksik/boş dosyada character(0) döner", {
  .utelog_source_once()
  testthat::expect_identical(
    read_text_lines_utf8(file.path(tempdir(), "olmayan_dosya_xyz_123.txt")),
    character(0)
  )
  bos <- tempfile(fileext = ".txt")
  file.create(bos)
  on.exit(unlink(bos), add = TRUE)
  testthat::expect_identical(read_text_lines_utf8(bos), character(0))
})

# ------------------------------------------------------------------------------
# mark_text_tree_utf8
# ------------------------------------------------------------------------------
testthat::test_that("mark_text_tree_utf8 karakter vektörünü UTF-8 işaretler", {
  .utelog_source_once()
  donen <- mark_text_tree_utf8("Türkçe")
  testthat::expect_identical(Encoding(donen), "UTF-8")
})

testthat::test_that("mark_text_tree_utf8 liste ve data.frame içindeki metni özyinelemeli işaretler", {
  .utelog_source_once()
  # Liste: ASCII-olmayan öğe UTF-8 işaretlenir.
  liste <- mark_text_tree_utf8(list(a = "Çağrı", b = 1L))
  testthat::expect_identical(Encoding(liste$a), "UTF-8")
  testthat::expect_identical(liste$b, 1L)  # sayısal dokunulmaz

  # data.frame: karakter sütun işaretlenir, sayısal korunur.
  df <- data.frame(Ad = "Ömer", Sira = 2L, stringsAsFactors = FALSE)
  donen_df <- mark_text_tree_utf8(df)
  testthat::expect_identical(Encoding(donen_df$Ad), "UTF-8")
  testthat::expect_identical(donen_df$Sira, 2L)
})
