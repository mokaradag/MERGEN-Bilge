# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-sse-delta-bundle-behavior.R
# Açıklama: R/helpers_llm_sse_events.R içindeki extract_llm_delta_bundle ve
#           parse_llm_sse_event fonksiyonlarının DAVRANIŞSAL testleri. Mevcut
#           test-llm-sse-events-behavior.R yalnızca extract_llm_delta_text'in
#           temel içerik yollarını kapsar; burada KAPSANMAYAN yollar test edilir:
#             - reasoning_content / reasoning / thinking / thought çıkarımı
#             - message vs delta vs üst-düzey öncelik yolları
#             - iç içe reasoning$content ve choices/delta text fallback
#             - multimodal (blok dizisi) content düğümü davranışı (karakterizasyon)
#             - parse_llm_sse_event: [DONE], boş, geçersiz JSON ve geçerli JSON
#           extract_llm_delta_bundle PARSE EDİLMİŞ R listesi alır; jsonlite GEREKMEZ.
#           Yalnızca parse_llm_sse_event JSON dalı jsonlite ister (gerektiğinde skip).
#           Shiny/DB/ağ/HTTP GEREKMEZ.
# ==============================================================================

.ssebundle_source_once <- function() {
  root <- resolve_repo_root_for_tests()
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  # extract_llm_delta_bundle, normalize_llm_text_node / extract_first_nonempty_llm_text'e bağlıdır.
  if (!exists("extract_first_nonempty_llm_text", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_llm_response_postprocess.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("extract_llm_delta_bundle", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_llm_sse_events.R"),
           encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# extract_llm_delta_bundle - içerik + reasoning çıkarımı
# ------------------------------------------------------------------------------
testthat::test_that("extract_llm_delta_bundle choices/delta içerik+reasoning_content çıkarır", {
  .ssebundle_source_once()
  ev <- list(choices = list(list(delta = list(
    content = "cevap",
    reasoning_content = "dusunce"
  ))))
  b <- extract_llm_delta_bundle(ev)
  testthat::expect_identical(b$content, "cevap")
  testthat::expect_identical(b$reasoning, "dusunce")
})

testthat::test_that("extract_llm_delta_bundle message.content + message.reasoning_content çıkarır", {
  .ssebundle_source_once()
  ev <- list(choices = list(list(message = list(
    content = "tam cevap",
    reasoning_content = "tam dusunce"
  ))))
  b <- extract_llm_delta_bundle(ev)
  testthat::expect_identical(b$content, "tam cevap")
  testthat::expect_identical(b$reasoning, "tam dusunce")
})

testthat::test_that("extract_llm_delta_bundle yalnızca reasoning içeren olayları yakalar", {
  .ssebundle_source_once()
  # Üst düzey delta$reasoning
  b1 <- extract_llm_delta_bundle(list(delta = list(reasoning = "sadece dusunce")))
  testthat::expect_identical(b1$content, "")
  testthat::expect_identical(b1$reasoning, "sadece dusunce")

  # delta$thinking
  b2 <- extract_llm_delta_bundle(list(delta = list(thinking = "dusunuyorum")))
  testthat::expect_identical(b2$reasoning, "dusunuyorum")

  # delta$thought
  b3 <- extract_llm_delta_bundle(list(delta = list(thought = "an dusunce")))
  testthat::expect_identical(b3$reasoning, "an dusunce")

  # Üst düzey reasoning_content
  b4 <- extract_llm_delta_bundle(list(reasoning_content = "ust dusunce"))
  testthat::expect_identical(b4$reasoning, "ust dusunce")
})

testthat::test_that("extract_llm_delta_bundle iç içe reasoning nesnesini düzleştirir", {
  .ssebundle_source_once()
  ev <- list(choices = list(list(delta = list(
    reasoning = list(content = "ic dusunce")
  ))))
  b <- extract_llm_delta_bundle(ev)
  testthat::expect_identical(b$content, "")
  testthat::expect_identical(b$reasoning, "ic dusunce")
})

testthat::test_that("extract_llm_delta_bundle choices text ve delta text fallback'lerini kullanır", {
  .ssebundle_source_once()
  # choices[[1]]$text
  testthat::expect_identical(
    extract_llm_delta_bundle(list(choices = list(list(text = "ham metin"))))$content,
    "ham metin"
  )
  # delta$text
  testthat::expect_identical(
    extract_llm_delta_bundle(list(delta = list(text = "delta metin")))$content,
    "delta metin"
  )
})

testthat::test_that("extract_llm_delta_bundle liste-olmayan/boş olaylarda boş paket döner", {
  .ssebundle_source_once()
  b1 <- extract_llm_delta_bundle("liste degil")
  testthat::expect_identical(b1$content, "")
  testthat::expect_identical(b1$reasoning, "")

  b2 <- extract_llm_delta_bundle(list())
  testthat::expect_identical(b2$content, "")
  testthat::expect_identical(b2$reasoning, "")
})

testthat::test_that("extract_llm_delta_text reasoning-only olayda görünür metin döndürmez", {
  .ssebundle_source_once()
  # Bilinçli sözleşme: görünür metin (content) reasoning'den ayrıdır.
  testthat::expect_identical(
    extract_llm_delta_text(list(delta = list(reasoning_content = "r"))),
    ""
  )
})

# ------------------------------------------------------------------------------
# extract_llm_delta_bundle - multimodal (blok dizisi) içerik düğümü
# Mevcut davranışın KARAKTERİZASYONU: content bir blok dizisi olduğunda
# normalize_llm_text_node tüm blokların $text alanlarını düzleştirip birleştirir.
# ------------------------------------------------------------------------------
testthat::test_that("extract_llm_delta_bundle metin blok dizisini birleştirir", {
  .ssebundle_source_once()
  ev <- list(choices = list(list(delta = list(content = list(
    list(type = "text", text = "Parça1 "),
    list(type = "text", text = "Parça2")
  )))))
  b <- extract_llm_delta_bundle(ev)
  testthat::expect_identical(b$content, "Parça1 Parça2")
  testthat::expect_identical(b$reasoning, "")
})

# ------------------------------------------------------------------------------
# parse_llm_sse_event - jsonlite gerektirmeyen dallar
# ------------------------------------------------------------------------------
testthat::test_that("parse_llm_sse_event [DONE] olayını işaretler", {
  .ssebundle_source_once()
  r1 <- parse_llm_sse_event("[DONE]")
  testthat::expect_true(isTRUE(r1$done))
  testthat::expect_null(r1$data)

  # 'data:' önekli [DONE] de aynı şekilde.
  r2 <- parse_llm_sse_event("data: [DONE]")
  testthat::expect_true(isTRUE(r2$done))
})

testthat::test_that("parse_llm_sse_event boş/boşluk olaylarda NULL döner", {
  .ssebundle_source_once()
  testthat::expect_null(parse_llm_sse_event(""))
  testthat::expect_null(parse_llm_sse_event("   \n  "))
  testthat::expect_null(parse_llm_sse_event("data:   "))
})

# ------------------------------------------------------------------------------
# parse_llm_sse_event - JSON dalı (jsonlite gerekir)
# ------------------------------------------------------------------------------
testthat::test_that("parse_llm_sse_event geçerli JSON 'data:' olayını ayrıştırır", {
  .ssebundle_source_once()
  testthat::skip_if_not_installed("jsonlite")

  r <- parse_llm_sse_event('data: {"choices":[{"delta":{"content":"hi"}}]}')
  testthat::expect_false(isTRUE(r$done))
  testthat::expect_true(is.list(r$data))
  # Ayrıştırılan nesne extract yardımcılarıyla uyumlu olmalı.
  testthat::expect_identical(extract_llm_delta_text(r$data), "hi")
})

testthat::test_that("parse_llm_sse_event geçersiz JSON'da NULL, öneksiz aday JSON'u ayrıştırır", {
  .ssebundle_source_once()
  testthat::skip_if_not_installed("jsonlite")

  testthat::expect_null(parse_llm_sse_event("data: {bozuk json"))

  # 'data:' öneki yoksa tüm metin aday JSON olarak denenir.
  r <- parse_llm_sse_event('{"content":"duz"}')
  testthat::expect_false(isTRUE(r$done))
  testthat::expect_identical(extract_llm_delta_text(r$data), "duz")
})
