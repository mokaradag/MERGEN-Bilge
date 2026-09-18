# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-query-selection-behavior.R
# Açıklama: Proje/Kaynak Analizi sezgisel sorgu skorlama mantığının davranışını
#           karakterize eder. Bu kurallar daha önce büyük modül içinde gömülüydü
#           ve testsizdi. Beklenen skorlar, orijinal formülden elle hesaplanmıştır
#           (isim alt-dize +50, isim kelime eşleşmesi ×10, açıklama kelime
#           eşleşmesi ×2, alan bonusu +8, max'a göre %100 normalizasyon,
#           THRESHOLD_RAW=2 / THRESHOLD_PCT=30).
# Bu test saf/yan-etkisizdir: DB, LLM, Shiny, tarayıcı veya ağ gerektirmez.
# ==============================================================================

.source_pk_qsel_behavior_env <- function() {
  pk_env <- new.env(parent = globalenv())

  pk_env$`%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0) y else x
  }

  source(
    file.path(repo_root_for_tests, "R", "helpers_pk_analysis_query_selection.R"),
    encoding = "UTF-8",
    local = pk_env
  )

  pk_env
}

test_that("pk_init_query_score_table iskeleti doğru şekil ve %||% id fallback'i üretir", {
  pk_env <- .source_pk_qsel_behavior_env()

  library <- list(
    list(id = NULL, name = "Birinci Sorgu", description = "d1"),
    list(id = "B2", name = "İkinci Sorgu", description = "d2")
  )

  skeleton <- pk_env$pk_init_query_score_table(library)

  expect_equal(
    colnames(skeleton),
    c("query_id", "query_name", "ai_score", "heuristic_score", "final_score")
  )
  expect_equal(nrow(skeleton), 2L)
  # id eksikse satır indeksi (as.character(i)) fallback olarak kullanılır
  expect_equal(skeleton$query_id, c("1", "B2"))
  expect_equal(skeleton$query_name, c("Birinci Sorgu", "İkinci Sorgu"))
  expect_true(all(skeleton$ai_score == 0))
  expect_true(all(skeleton$heuristic_score == 0))
  expect_true(all(skeleton$final_score == 0))
})

test_that("pk_score_query_relevance isim kelimesi + açıklama + alan bonuslarını toplar", {
  pk_env <- .source_pk_qsel_behavior_env()

  q <- list(name = "Bütçe Analizi", description = "proje bütçe ve maliyet raporu")
  prompt_clean <- "proje bütçe durumu nedir"
  prompt_words <- c("proje", "bütçe", "durumu", "nedir")

  # 10 (isim kelimesi 'bütçe') + 4 (açıklama 'proje','bütçe') + 8 (bütçe alan) + 8 (proje alan) = 30
  expect_equal(
    pk_env$pk_score_query_relevance(q, prompt_clean, prompt_words),
    30
  )
})

test_that("pk_score_query_relevance tam isim alt-dize eşleşmesinde +50 verir", {
  pk_env <- .source_pk_qsel_behavior_env()

  q <- list(name = "Bütçe", description = "x")
  prompt_clean <- "proje bütçe durumu"
  prompt_words <- c("proje", "bütçe", "durumu")

  # 50 (alt-dize 'bütçe') + 10 (isim kelimesi 'bütçe') = 60; açıklama 'x' alan bonusu vermez
  expect_equal(
    pk_env$pk_score_query_relevance(q, prompt_clean, prompt_words),
    60
  )
})

test_that("pk_score_query_relevance hiç eşleşme yoksa 0 verir", {
  pk_env <- .source_pk_qsel_behavior_env()

  q <- list(name = "Zaman", description = "tarih süre")
  prompt_clean <- "xyz abc"
  prompt_words <- c("xyz", "abc")

  expect_equal(
    pk_env$pk_score_query_relevance(q, prompt_clean, prompt_words),
    0
  )
})

test_that("pk_compute_heuristic_query_scores normalize eder ve eşik kararını üretir", {
  pk_env <- .source_pk_qsel_behavior_env()

  library <- list(
    list(id = "A", name = "Bütçe", description = "bütçe maliyet"),
    list(id = "B", name = "Zaman", description = "tarih süre")
  )

  res <- pk_env$pk_compute_heuristic_query_scores("bütçe maliyet durumu", library)

  # A: 50 (alt-dize 'bütçe') + 10 (isim 'bütçe') + 4 (açıklama 'bütçe','maliyet')
  #    + 8 (bütçe alan) = 72; B: 0
  # max=72 -> normalize: A=100, B=0
  expect_equal(res$all_scores$heuristic_score, c(100, 0))
  expect_equal(res$all_scores$final_score, c(100, 0))
  expect_equal(res$all_scores$ai_score, c(0, 0))
  expect_equal(res$best_idx, 1L)
  expect_equal(res$max_score_raw, 72)
  expect_equal(res$max_score_pct, 100)
  expect_true(res$passes_threshold)
})

test_that("pk_compute_heuristic_query_scores tüm skorlar 0 ise eşiği geçmez", {
  pk_env <- .source_pk_qsel_behavior_env()

  library <- list(
    list(id = "A", name = "Zaman", description = "tarih süre"),
    list(id = "B", name = "Kaynak", description = "personel ekip")
  )

  res <- pk_env$pk_compute_heuristic_query_scores("xyz abc def", library)

  expect_equal(res$all_scores$final_score, c(0, 0))
  expect_equal(res$max_score_raw, 0)
  expect_false(res$passes_threshold)
})
