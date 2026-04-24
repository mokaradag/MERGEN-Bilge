# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-sse-delta-reasoning-contract.R
# Açıklama: SSE delta ayrıştırıcısının reasoning alanlarını yakaladığını ve
# atomic vector içeren uç yanıtlarında çökmediğini doğrular.
# ==============================================================================

test_that("extract_llm_delta_bundle standart content deltasını ayrıştırır", {
  event <- list(
    id = "evt-1",
    object = "chat.completion.chunk",
    choices = list(
      list(
        delta = list(
          content = "Merhaba"
        )
      )
    )
  )

  out <- extract_llm_delta_bundle(event)

  expect_identical(out$content, "Merhaba")
  expect_identical(out$reasoning, "")
})

test_that("extract_llm_delta_bundle Kimi tarzı reasoning deltasını ayrıştırır", {
  event <- list(
    id = "evt-2",
    object = "chat.completion.chunk",
    choices = list(
      list(
        delta = list(
          reasoning = "Önce problemi anlıyorum."
        )
      )
    )
  )

  out <- extract_llm_delta_bundle(event)

  expect_identical(out$content, "")
  expect_identical(out$reasoning, "Önce problemi anlıyorum.")
})

test_that("extract_llm_delta_bundle reasoning_content alanını ayrıştırır", {
  event <- list(
    choices = list(
      list(
        delta = list(
          reasoning_content = "Bu ayrı reasoning kanalından geldi.",
          content = ""
        )
      )
    )
  )

  out <- extract_llm_delta_bundle(event)

  expect_identical(out$content, "")
  expect_identical(out$reasoning, "Bu ayrı reasoning kanalından geldi.")
})

test_that("extract_llm_delta_bundle atomic delta/message yapılarında çökmez", {
  event <- list(
    id = "evt-atomic",
    choices = list(
      list(
        delta = "atomic-delta",
        message = "atomic-message"
      )
    )
  )

  expect_error(
    out <- extract_llm_delta_bundle(event),
    NA
  )

  expect_true(is.list(out))
  expect_true("content" %in% names(out))
  expect_true("reasoning" %in% names(out))
})