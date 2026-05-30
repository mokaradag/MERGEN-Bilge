# ==============================================================================
# Dosya Yolu: tests/testthat/test-model-capability-overrides-behavior.R
# Açıklama: R/helpers_api_model_config.R model yetenek/istek-override DAVRANIŞSAL
#           testleri. Düşünme (thinking) yeteneği yalnızca config'te açıkça
#           bildirilen modeller için belirlenir (model adı regex'i YOK), ve
#           request_overrides body'ye derin birleştirme ile eklenir. Testler
#           sentetik bir config geçirir; global api_config/ağ/LLM GEREKMEZ.
# ==============================================================================

.modelcaps_source_once <- function() {
  if (exists("get_local_model_capabilities", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_api_model_config.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

.fake_model_config <- function() {
  list(
    local_model_capabilities = list(
      "gemma-thinker" = list(
        thinking = TRUE,
        omit_temperature = TRUE,
        request_overrides = list(
          chat_template_kwargs = list(enable_thinking = TRUE)
        )
      ),
      "plain-model" = list(thinking = FALSE),
      "temp-omit"   = list(omit_temperature = TRUE),
      "reasoner"    = list(stream_reasoning = TRUE, allow_reasoning_fallback = TRUE)
    )
  )
}

testthat::test_that("merge_named_list_deep iç içe listeleri derinlemesine birleştirir", {
  .modelcaps_source_once()
  testthat::expect_identical(
    merge_named_list_deep(list(a = 1), list(b = 2)),
    list(a = 1, b = 2)
  )
  # Çakışan skalar anahtar üzerine yazılır.
  testthat::expect_identical(merge_named_list_deep(list(a = 1), list(a = 2)), list(a = 2))
  # İç içe liste derin birleşir (x'in benzersiz anahtarları korunur).
  merged <- merge_named_list_deep(
    list(opts = list(x = 1, y = 2)),
    list(opts = list(y = 3, z = 4))
  )
  testthat::expect_identical(merged$opts$x, 1)
  testthat::expect_identical(merged$opts$y, 3)
  testthat::expect_identical(merged$opts$z, 4)
  # Boş/liste-olmayan y, x'i değiştirmez.
  testthat::expect_identical(merge_named_list_deep(list(a = 1), list()), list(a = 1))
  testthat::expect_identical(merge_named_list_deep(list(a = 1), NULL), list(a = 1))
  # Liste-olmayan x boş listeye normalize edilir.
  testthat::expect_identical(merge_named_list_deep(NULL, list(a = 1)), list(a = 1))
})

testthat::test_that("get_local_model_capabilities bilinen modelde yetenekleri, bilinmeyende varsayılanı döndürür", {
  .modelcaps_source_once()
  cfg <- .fake_model_config()
  caps <- get_local_model_capabilities("gemma-thinker", cfg)
  testthat::expect_true(isTRUE(caps$thinking))
  testthat::expect_true(isTRUE(caps$omit_temperature))

  # Bilinmeyen model: tüm yetenekler varsayılan (FALSE / boş override).
  unknown <- get_local_model_capabilities("yok-boyle-model", cfg)
  testthat::expect_false(isTRUE(unknown$thinking))
  testthat::expect_identical(unknown$request_overrides, list())

  # NULL model_id güvenle boş kimliğe düşer (varsayılanlar).
  testthat::expect_false(isTRUE(get_local_model_capabilities(NULL, cfg)$thinking))
})

testthat::test_that("is_thinking_model yalnızca config'te bildirilen modellerde TRUE döner", {
  .modelcaps_source_once()
  cfg <- .fake_model_config()
  testthat::expect_true(is_thinking_model("gemma-thinker", cfg))
  testthat::expect_false(is_thinking_model("plain-model", cfg))
  testthat::expect_false(is_thinking_model("unknown", cfg))
  # Düşünme model adı regex'inden DEĞİL config'ten gelir: "qwen3-thinking" gibi
  # bir ad config'te yoksa thinking FALSE olmalı.
  testthat::expect_false(is_thinking_model("qwen3-thinking-reasoning-r1", cfg))
})

testthat::test_that("should_omit_temperature omit_temperature VEYA thinking olduğunda TRUE döner", {
  .modelcaps_source_once()
  cfg <- .fake_model_config()
  testthat::expect_true(should_omit_temperature("gemma-thinker", cfg))  # her ikisi
  testthat::expect_true(should_omit_temperature("temp-omit", cfg))      # yalnız omit
  testthat::expect_false(should_omit_temperature("plain-model", cfg))
  testthat::expect_false(should_omit_temperature("reasoner", cfg))
})

testthat::test_that("should_stream_reasoning ve should_allow_reasoning_fallback bayrakları doğru okur", {
  .modelcaps_source_once()
  cfg <- .fake_model_config()
  testthat::expect_true(should_stream_reasoning("reasoner", cfg))
  testthat::expect_false(should_stream_reasoning("plain-model", cfg))
  testthat::expect_true(should_allow_reasoning_fallback("reasoner", cfg))
  testthat::expect_false(should_allow_reasoning_fallback("gemma-thinker", cfg))
})

testthat::test_that("apply_model_request_overrides request_overrides'ı body'ye derin ekler", {
  .modelcaps_source_once()
  cfg <- .fake_model_config()

  body <- list(model = "gemma-thinker", messages = list())
  out <- apply_model_request_overrides(body, "gemma-thinker", cfg)
  testthat::expect_true(isTRUE(out$chat_template_kwargs$enable_thinking))
  testthat::expect_identical(out$model, "gemma-thinker")    # mevcut alanlar korunur
  testthat::expect_true("messages" %in% names(out))

  # Override'ı olmayan model: body değişmez.
  body2 <- list(model = "plain-model", temperature = 0.5)
  testthat::expect_identical(apply_model_request_overrides(body2, "plain-model", cfg), body2)

  # body'de aynı üst anahtar zaten varsa derin birleşir (mevcut alt anahtar korunur).
  body3 <- list(chat_template_kwargs = list(foo = 1L))
  out3 <- apply_model_request_overrides(body3, "gemma-thinker", cfg)
  testthat::expect_identical(out3$chat_template_kwargs$foo, 1L)
  testthat::expect_true(isTRUE(out3$chat_template_kwargs$enable_thinking))
})
