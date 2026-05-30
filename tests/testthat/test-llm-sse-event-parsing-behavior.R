# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-sse-event-parsing-behavior.R
# Açıklama: R/helpers_llm_sse_events.R salt-okunur SSE ayrıştırma yardımcılarının
#           DAVRANIŞSAL testleri: .llm_sse_safe_get (güvenli iç içe yol erişimi),
#           .llm_sse_split_content_node (multimodal content/reasoning ayrımı) ve
#           extract_llm_event_sources (kaynak çıkarımı). Girdiler önceden
#           ayrıştırılmış R listeleridir; jsonlite/ağ/LLM GEREKMEZ. Bağımlı metin
#           yardımcıları (normalize_llm_text_node vb.) için response_postprocess
#           ve api_model_config önce kaynaklanır.
# ==============================================================================

.ssevents_source_once <- function() {
  if (exists(".llm_sse_split_content_node", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("extract_llm_event_sources", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  root <- resolve_repo_root_for_tests()
  if (!exists("normalize_llm_text_node", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_llm_response_postprocess.R"),
           encoding = "UTF-8", local = globalenv())
  }
  # extract_llm_content_and_sources, içerik boşsa should_allow_reasoning_fallback
  # çağırır. Tüm fixture'larımız içerik içerdiği için bu yola girilmez; yine de
  # fonksiyon adının çözünür olması için api_model_config kaynaklanır.
  if (!exists("should_allow_reasoning_fallback", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_api_model_config.R"),
           encoding = "UTF-8", local = globalenv())
  }
  source(file.path(root, "R", "helpers_llm_sse_events.R"),
         encoding = "UTF-8", local = globalenv())
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# .llm_sse_safe_get
# ------------------------------------------------------------------------------
testthat::test_that(".llm_sse_safe_get iç içe string yolu izler", {
  .ssevents_source_once()
  x <- list(a = list(b = list(c = 99L)))
  testthat::expect_identical(.llm_sse_safe_get(x, list("a", "b", "c")), 99L)
  # Boş yol => kök nesnenin kendisi.
  testthat::expect_identical(.llm_sse_safe_get(x, list()), x)
})

testthat::test_that(".llm_sse_safe_get sayısal indeks ile liste elemanına erişir", {
  .ssevents_source_once()
  x <- list(items = list(10L, 20L, 30L))
  testthat::expect_identical(.llm_sse_safe_get(x, list("items", 2L)), 20L)
  testthat::expect_identical(.llm_sse_safe_get(x, list("items", 2)), 20L)  # double indeks
  # Aralık dışı / 0 / negatif indeks => NULL.
  testthat::expect_null(.llm_sse_safe_get(x, list("items", 5L)))
  testthat::expect_null(.llm_sse_safe_get(x, list("items", 0L)))
  testthat::expect_null(.llm_sse_safe_get(x, list("items", -1L)))
})

testthat::test_that(".llm_sse_safe_get eksik/geçersiz yollarda NULL döner", {
  .ssevents_source_once()
  x <- list(a = 1L)
  # Olmayan anahtar.
  testthat::expect_null(.llm_sse_safe_get(x, list("yok")))
  # Ara düğüm liste değil (atomic) => NULL.
  testthat::expect_null(.llm_sse_safe_get(x, list("a", "b")))
  # NULL / liste-olmayan kök => NULL.
  testthat::expect_null(.llm_sse_safe_get(NULL, list("a")))
  testthat::expect_null(.llm_sse_safe_get(5L, list("a")))
  # Boş / NA string anahtar => NULL.
  testthat::expect_null(.llm_sse_safe_get(x, list("")))
  testthat::expect_null(.llm_sse_safe_get(x, list(NA_character_)))
  # İsimsiz listeye string anahtar => NULL.
  testthat::expect_null(.llm_sse_safe_get(list(list(1L, 2L)), list(1L, "a")))
})

# ------------------------------------------------------------------------------
# .llm_sse_split_content_node
# ------------------------------------------------------------------------------
testthat::test_that(".llm_sse_split_content_node NULL ve atomic düğümleri ele alır", {
  .ssevents_source_once()
  testthat::expect_identical(
    .llm_sse_split_content_node(NULL),
    list(content = "", reasoning = "")
  )
  # Düz string => content; reasoning boş.
  testthat::expect_identical(
    .llm_sse_split_content_node("Merhaba"),
    list(content = "Merhaba", reasoning = "")
  )
  # Atomic sayısal => karaktere çevrilir.
  testthat::expect_identical(
    .llm_sse_split_content_node(42L),
    list(content = "42", reasoning = "")
  )
})

testthat::test_that(".llm_sse_split_content_node düz string parçalarını birleştirir", {
  .ssevents_source_once()
  res <- .llm_sse_split_content_node(list("Mer", "ha", "ba"))
  testthat::expect_identical(res$content, "Merhaba")
  testthat::expect_identical(res$reasoning, "")
})

testthat::test_that(".llm_sse_split_content_node tipli blokları content/reasoning olarak ayırır", {
  .ssevents_source_once()
  node <- list(
    list(type = "text", text = "Görünür cevap"),
    list(type = "reasoning", text = "İç düşünce")
  )
  res <- .llm_sse_split_content_node(node)
  testthat::expect_identical(res$content, "Görünür cevap")
  testthat::expect_identical(res$reasoning, "İç düşünce")
})

testthat::test_that(".llm_sse_split_content_node thinking/thought tiplerini reasoning sayar", {
  .ssevents_source_once()
  # 'thinking' alanı ve 'thinking' tipi reasoning'e gider.
  res <- .llm_sse_split_content_node(list(list(type = "thinking", thinking = "tahmin")))
  testthat::expect_identical(res$content, "")
  testthat::expect_identical(res$reasoning, "tahmin")

  # Boş metinli bloklar atlanır; sadece dolu içerik kalır.
  res2 <- .llm_sse_split_content_node(list(
    list(type = "text", text = ""),
    list(type = "text", text = "dolu")
  ))
  testthat::expect_identical(res2$content, "dolu")
  testthat::expect_identical(res2$reasoning, "")
})

# ------------------------------------------------------------------------------
# extract_llm_event_sources (içerik daima dolu => reasoning-fallback yoluna girilmez)
# ------------------------------------------------------------------------------
testthat::test_that("extract_llm_event_sources message.sources alanını çıkarır", {
  .ssevents_source_once()
  ev <- list(choices = list(list(message = list(
    content = "cevap", sources = list("s1", "s2")
  ))))
  testthat::expect_identical(extract_llm_event_sources(ev), list("s1", "s2"))
})

testthat::test_that("extract_llm_event_sources top-level ve delta kaynaklarını çıkarır", {
  .ssevents_source_once()
  # Üst düzey sources.
  ev_top <- list(content = "x", sources = list("a"))
  testthat::expect_identical(extract_llm_event_sources(ev_top), list("a"))

  # delta.sources.
  ev_delta <- list(choices = list(list(delta = list(
    content = "d", sources = list("ds")
  ))))
  testthat::expect_identical(extract_llm_event_sources(ev_delta), list("ds"))

  # choice düzeyi sources.
  ev_choice <- list(choices = list(list(text = "t", sources = list("cs"))))
  testthat::expect_identical(extract_llm_event_sources(ev_choice), list("cs"))
})

testthat::test_that("extract_llm_event_sources kaynak yoksa NULL döner; message delta'ya üstün gelir", {
  .ssevents_source_once()
  # Kaynak yok => NULL.
  ev_none <- list(choices = list(list(message = list(content = "cevap"))))
  testthat::expect_null(extract_llm_event_sources(ev_none))

  # Hem message hem delta sources varsa message kazanır.
  ev_both <- list(choices = list(list(
    message = list(content = "m", sources = list("msg-src")),
    delta = list(content = "d", sources = list("delta-src"))
  )))
  testthat::expect_identical(extract_llm_event_sources(ev_both), list("msg-src"))
})
