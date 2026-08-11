# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-multi-query-behavior.R
# Açıklama: helpers_deep_analysis.R içindeki find_multiple_queries_with_ai
#           davranışını doğrular. Bu fonksiyon LLM'den JSON eşleşme listesi alıp
#           kütüphane sorgularına eşler: tekrarlı match_id'leri eler, güven<30
#           sorguları atar, azalan güven sırasına göre sıralar ve max_queries
#           uygular. call_local_llm + resolve_local_llm_credentials env'e stub
#           edilir; gerçek LLM/ağ yoktur. Çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: helpers_deep_analysis.R'yi yalıtılmış ortama yükler; LLM çağrısı
# ve kimlik bilgisi çözücüsü stub edilir. mergen.filter_model option'ı set
# edildiği için api_config'e dokunulmaz (getOption default'u tembel kalır).
.multiQueryEnv <- function(llm_content) {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  # Faz 6: derin sıralı-küme tavanı yapılandırmadan gelir (pk_deep_max_queries);
  # izole test GERÇEK sahip dosyaları yükler.
  for (yardimci in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                     "helpers_pk_result_size.R", "helpers_pk_sql_execute.R",
                     "helpers_deep_analysis_reconcile.R")) {
    source(file.path(kok, "R", yardimci), encoding = "UTF-8", local = env)
  }
  source(file.path(kok, "R", "helpers_deep_analysis.R"), encoding = "UTF-8", local = env)
  env$resolve_local_llm_credentials <- function(model) list(default_api_key = "ph-key")
  env$call_local_llm <- function(messages, settings) llm_content
  env
}

# Üç sorguluk örnek kütüphane
.testLibrary <- function() {
  list(
    list(name = "Personel Listesi", description = "Çalışan kayıtları"),
    list(name = "Satış Raporu", description = "Aylık satış"),
    list(name = "Stok Durumu", description = "Depo stok seviyeleri")
  )
}

test_that("find_multiple_queries_with_ai LLM NULL dönerse NULL döndürür", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv(NULL)
  res <- env$find_multiple_queries_with_ai("soru", .testLibrary(), session = NULL)
  expect_null(res)
})

test_that("find_multiple_queries_with_ai boş matches için NULL döndürür", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv('{"matches": []}')
  res <- env$find_multiple_queries_with_ai("soru", .testLibrary(), session = NULL)
  expect_null(res)
})

test_that("find_multiple_queries_with_ai geçerli eşleşmeleri sorgulara eşler ve alanları doldurur", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv(
    '{"matches":[{"match_id":2,"confidence":90,"reason":"satış ilgili"},{"match_id":1,"confidence":60,"reason":"personel"}]}'
  )
  res <- env$find_multiple_queries_with_ai("satış ve personel", .testLibrary(), session = NULL)
  expect_length(res, 2L)
  # Türkçe yorum: azalan güven sırası -> önce confidence 90 (Satış Raporu)
  expect_identical(res[[1]]$name, "Satış Raporu")
  expect_equal(res[[1]]$relevance_score, 90)
  expect_identical(res[[1]]$selection_method, "ai_deep")
  expect_identical(res[[1]]$selection_reason, "satış ilgili")
  expect_identical(res[[2]]$name, "Personel Listesi")
  expect_equal(res[[2]]$relevance_score, 60)
})

test_that("find_multiple_queries_with_ai güven<30 olan eşleşmeleri eler", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv(
    '{"matches":[{"match_id":1,"confidence":29,"reason":"zayıf"},{"match_id":3,"confidence":80,"reason":"stok"}]}'
  )
  res <- env$find_multiple_queries_with_ai("stok", .testLibrary(), session = NULL)
  expect_length(res, 1L)
  expect_identical(res[[1]]$name, "Stok Durumu")
})

test_that("find_multiple_queries_with_ai tekrarlı match_id'leri eler", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv(
    '{"matches":[{"match_id":2,"confidence":70},{"match_id":2,"confidence":95}]}'
  )
  res <- env$find_multiple_queries_with_ai("satış", .testLibrary(), session = NULL)
  # Türkçe yorum: aynı sorgu yalnızca bir kez seçilir (ilk geçerli)
  expect_length(res, 1L)
  expect_identical(res[[1]]$name, "Satış Raporu")
  expect_equal(res[[1]]$relevance_score, 70)
})

test_that("find_multiple_queries_with_ai aralık dışı match_id'i yok sayar", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv(
    '{"matches":[{"match_id":99,"confidence":90},{"match_id":0,"confidence":90},{"match_id":1,"confidence":50}]}'
  )
  res <- env$find_multiple_queries_with_ai("soru", .testLibrary(), session = NULL)
  expect_length(res, 1L)
  expect_identical(res[[1]]$name, "Personel Listesi")
})

test_that("find_multiple_queries_with_ai max_queries sınırını uygular", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv(
    '{"matches":[{"match_id":1,"confidence":90},{"match_id":2,"confidence":80},{"match_id":3,"confidence":70}]}'
  )
  res <- env$find_multiple_queries_with_ai("hepsi", .testLibrary(), session = NULL, max_queries = 2)
  expect_length(res, 2L)
  # Türkçe yorum: en yüksek 2 güven kalmalı
  expect_identical(res[[1]]$name, "Personel Listesi")
  expect_identical(res[[2]]$name, "Satış Raporu")
})

test_that("find_multiple_queries_with_ai markdown JSON çitlerini temizler", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv(
    "```json\n{\"matches\":[{\"match_id\":3,\"confidence\":75}]}\n```"
  )
  res <- env$find_multiple_queries_with_ai("stok", .testLibrary(), session = NULL)
  expect_length(res, 1L)
  expect_identical(res[[1]]$name, "Stok Durumu")
})

test_that("find_multiple_queries_with_ai geçersiz JSON'da NULL döndürür", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv("{bu gecerli json degil")
  res <- env$find_multiple_queries_with_ai("soru", .testLibrary(), session = NULL)
  expect_null(res)
})

test_that("find_multiple_queries_with_ai list($content) dönüşünü de işler", {
  withr::local_options(mergen.filter_model = "test-model")
  env <- .multiQueryEnv(list(content = '{"matches":[{"match_id":1,"confidence":55}]}'))
  res <- env$find_multiple_queries_with_ai("personel", .testLibrary(), session = NULL)
  expect_length(res, 1L)
  expect_identical(res[[1]]$name, "Personel Listesi")
})
