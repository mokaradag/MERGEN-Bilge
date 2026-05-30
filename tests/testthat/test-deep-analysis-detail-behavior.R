# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-detail-behavior.R
# Açıklama: Derin analiz detay seviyesi yapılandırma yardımcılarının davranışsal
#           testleri. get_analysis_detail_config (seviye arama + bilinmeyen
#           seviyede 'standart' fallback) ve get_analysis_detail_instruction
#           (talimat metni seçimi) doğrulanır. ASCII çapaları kullanılır.
#           DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.deep_analysis_detail_source_once <- function() {
  if (exists("get_analysis_detail_config", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("get_analysis_detail_instruction", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_deep_analysis.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("get_analysis_detail_config bilinen seviyeleri döner", {
  .deep_analysis_detail_source_once()

  ozet <- get_analysis_detail_config("ozet")
  testthat::expect_identical(ozet$id, "ozet")
  testthat::expect_equal(ozet$max_tokens, 1500)

  detayli <- get_analysis_detail_config("detayli")
  testthat::expect_identical(detayli$id, "detayli")
  testthat::expect_equal(detayli$max_tokens, 4096)
})

testthat::test_that("get_analysis_detail_config bilinmeyen seviyede standart'a düşer", {
  .deep_analysis_detail_source_once()

  config <- get_analysis_detail_config("bilinmeyen_seviye")
  testthat::expect_identical(config$id, "standart")
})

testthat::test_that("get_analysis_detail_instruction seviyeye uygun talimat döndürür", {
  .deep_analysis_detail_source_once()

  # ozet talimatı '5-8 cümle' sınırı içerir.
  testthat::expect_true(grepl("5-8", enc2utf8(get_analysis_detail_instruction("ozet")), fixed = TRUE))

  # detayli talimatı 'Tablolar' anahtarını içerir.
  testthat::expect_true(grepl("Tablolar", enc2utf8(get_analysis_detail_instruction("detayli")), fixed = TRUE))

  # Bilinmeyen seviye -> standart talimatı ('1-2 paragraf').
  testthat::expect_true(grepl("1-2", enc2utf8(get_analysis_detail_instruction("bilinmeyen")), fixed = TRUE))
})
