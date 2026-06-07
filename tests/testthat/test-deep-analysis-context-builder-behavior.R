# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-context-builder-behavior.R
# Açıklama: build_deep_analysis_context saf kurucusunun davranışını doğrular:
#           başarısız-yalnız hata mesajı, başarılı data_analysis bağlamı,
#           çoklu sorgu max_tokens ölçeklemesi (8192 tavanı) ve başarısız notu.
#           Çevrimdışı/deterministik; gerçek DB/LLM yok.
# ==============================================================================

repo_root_dac <- resolve_repo_root_for_tests()

.dac_env <- new.env(parent = globalenv())
.dac_env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
suppressWarnings(source(
  file.path(repo_root_dac, "R/helpers_deep_analysis.R"),
  encoding = "UTF-8", local = .dac_env
))

.dac_ok <- function(nm) {
  list(success = TRUE, query_name = nm, query_desc = "açıklama",
       row_count = 5L, relevance = 50, summary_text = "özet metni", preview_json = "[]")
}

test_that("başarılı sorgu yoksa error_message döner ve başarısızları listeler", {
  qr <- list(
    list(success = FALSE, query_name = "Sorgu1", error_msg = "hata-bir"),
    list(success = FALSE, query_name = "Sorgu2", error_msg = "hata-iki")
  )
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "X", max_tokens = 3000))
  expect_identical(out$type, "error_message")
  expect_true(grepl("Hiçbir sorgu başarılı", out$content, fixed = TRUE))
  expect_true(grepl("Sorgu1", out$content, fixed = TRUE))
  expect_true(grepl("hata-bir", out$content, fixed = TRUE))
})

test_that("tek başarılı sorgu data_analysis döner, max_tokens=base", {
  qr <- list(.dac_ok("Maliyet"))
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "DETAY-YONERGE", max_tokens = 3000))
  expect_identical(out$type, "data_analysis")
  expect_equal(out$query_count, 1L)
  expect_equal(out$max_tokens, 3000)   # tek sorgu: ölçekleme yok
  expect_true(grepl("Maliyet", out$user_context, fixed = TRUE))
  expect_true(grepl("DETAY-YONERGE", out$prompt_context, fixed = TRUE))
})

test_that("çoklu sorgu max_tokens'ı ölçekler", {
  qr <- list(.dac_ok("A"), .dac_ok("B"), .dac_ok("C"))  # 3 sorgu -> 1 + 2*0.3 = 1.6
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "", max_tokens = 3000))
  expect_equal(out$query_count, 3L)
  expect_equal(out$max_tokens, as.integer(3000 * 1.6))  # 4800
})

test_that("çok sayıda sorguda max_tokens 8192 tavanını aşmaz", {
  qr <- lapply(1:10, function(i) .dac_ok(paste0("Q", i)))  # 1 + 9*0.3 = 3.7 -> 11100 -> tavan
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "", max_tokens = 3000))
  expect_equal(out$max_tokens, 8192)
})

test_that("başarılı + başarısız karışımı başarısız notu ekler", {
  qr <- list(
    .dac_ok("OK"),
    list(success = FALSE, query_name = "FAIL", error_msg = "neden-x")
  )
  out <- .dac_env$build_deep_analysis_context(qr, "soru", list(instruction = "", max_tokens = 3000))
  expect_identical(out$type, "data_analysis")
  expect_equal(out$query_count, 1L)
  expect_true(grepl("BAŞARISIZ SORGULAR", out$user_context, fixed = TRUE))
  expect_true(grepl("FAIL", out$user_context, fixed = TRUE))
  expect_true(grepl("neden-x", out$user_context, fixed = TRUE))
})
