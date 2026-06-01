# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-turkish-decoding-behavior.R
# Açıklama: R/helpers_claude_code_workdir_snapshot.R içindeki Türkçe çözümleme
#           skorlayıcılarının DAVRANIŞSAL testleri. Bu fonksiyonlar doğrudan
#           çağrılarak test edilmiyordu:
#             - score_turkish_decoding_candidate: Türkçe karakter sayısı artı,
#               mojibake sekansı eksi 10 puan; NULL/NA/boş -> -1
#             - pick_best_turkish_decoding: ham baytları çeşitli kodlamalarla
#               çözüp en yüksek skorlu adayı seçer
#           Fikstürler parser-güvenli intToUtf8/iconv ile deterministik kurulur.
#           Shiny/DB/ağ GEREKMEZ; yalnızca base R.
# ==============================================================================

.ccdecode_source_once <- function() {
  if (exists("score_turkish_decoding_candidate", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("pick_best_turkish_decoding", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_workdir_snapshot.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Kod noktalarından parser-güvenli karakter dizisi üretir.
.ccd_cp <- function(...) intToUtf8(as.integer(c(...)))

# ------------------------------------------------------------------------------
# score_turkish_decoding_candidate
# ------------------------------------------------------------------------------
testthat::test_that("score_turkish_decoding_candidate NULL/NA/boş için -1 döner", {
  .ccdecode_source_once()
  testthat::expect_identical(score_turkish_decoding_candidate(NULL), -1L)
  testthat::expect_identical(score_turkish_decoding_candidate(NA), -1L)
  testthat::expect_identical(score_turkish_decoding_candidate(""), -1L)
})

testthat::test_that("score_turkish_decoding_candidate ASCII için 0, Türkçe karakter başına +1 verir", {
  .ccdecode_source_once()
  testthat::expect_identical(score_turkish_decoding_candidate("hello world"), 0L)
  # "Çağrı" -> Ç, ğ, ı ayırt edici karakterleri = 3 puan
  cagri <- .ccd_cp(0x00C7, 0x0061, 0x011F, 0x0072, 0x0131)
  testthat::expect_identical(score_turkish_decoding_candidate(cagri), 3L)
})

testthat::test_that("score_turkish_decoding_candidate mojibake sekansı başına -10 cezalandırır", {
  .ccdecode_source_once()
  # "Ã§" mojibake sekansı (U+00C3 U+00A7) -> 0 Türkçe - 10 = -10
  moji <- .ccd_cp(0x00C3, 0x00A7)
  testthat::expect_identical(score_turkish_decoding_candidate(moji), -10L)
  # "ÅŸ" mojibake (U+00C5 U+0178) -> -10
  moji2 <- .ccd_cp(0x00C5, 0x0178)
  testthat::expect_identical(score_turkish_decoding_candidate(moji2), -10L)
  # Karışık: "Çağrı" (3) + "Ã§" (-10) = -7
  karisik <- paste0(.ccd_cp(0x00C7, 0x0061, 0x011F, 0x0072, 0x0131), moji)
  testthat::expect_identical(score_turkish_decoding_candidate(karisik), -7L)
})

# ------------------------------------------------------------------------------
# pick_best_turkish_decoding
# ------------------------------------------------------------------------------
testthat::test_that("pick_best_turkish_decoding boş ham baytlar için NA döner", {
  .ccdecode_source_once()
  testthat::expect_true(is.na(pick_best_turkish_decoding(raw(0))))
})

testthat::test_that("pick_best_turkish_decoding WINDOWS-1254 baytlarını Türkçe metne çözer", {
  .ccdecode_source_once()
  # "Çağrı şehir" metnini WINDOWS-1254 baytlarına çevir, sonra en iyi çözümü iste
  metin <- .ccd_cp(
    0x00C7, 0x0061, 0x011F, 0x0072, 0x0131, 0x0020,  # Çağrı + boşluk
    0x015F, 0x0065, 0x0068, 0x0069, 0x0072            # şehir
  )
  ham <- iconv(metin, from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]]
  testthat::expect_false(is.null(ham))

  best <- pick_best_turkish_decoding(ham)
  # En yüksek skorlu çözüm Türkçe karakterleri geri kazanır
  testthat::expect_true(grepl("[çğışÇ]", best, perl = TRUE))
  # Mojibake jetonu içermemeli
  testthat::expect_false(grepl("Ã", best, fixed = TRUE))
})
