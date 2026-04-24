# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-reasoning-request-overrides.R
# Açıklama: Thinking/reasoning modeller için model bazlı request_overrides
# sözleşmesini doğrular. Özellikle gemma benzeri modellerde
# chat_template_kwargs$enable_thinking alanının future worker'a ulaşması
# korunmalıdır.
# ==============================================================================

.read_repo_file_bytes_for_reasoning_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  # UTF-8 BOM varsa kaldır.
  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  raw_data <- raw_data[raw_data != as.raw(0)]

  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "bytes"

  txt <- gsub("\r\n", "\n", txt, fixed = TRUE, useBytes = TRUE)
  txt <- gsub("\r", "\n", txt, fixed = TRUE, useBytes = TRUE)

  txt
}

test_that("thinking model request_overrides body içine derin merge edilir", {
  expect_true(
    exists("get_local_model_capabilities", mode = "function", inherits = TRUE),
    info = "get_local_model_capabilities fonksiyonu yüklü olmalı."
  )

  expect_true(
    exists("apply_model_request_overrides", mode = "function", inherits = TRUE),
    info = "apply_model_request_overrides fonksiyonu yüklü olmalı."
  )

  fake_config <- list(
    local_model_capabilities = list(
      "gemma-thinking-test" = list(
        thinking = TRUE,
        omit_temperature = TRUE,
        stream_reasoning = TRUE,
        allow_reasoning_fallback = TRUE,
        request_overrides = list(
          chat_template_kwargs = list(
            enable_thinking = TRUE
          )
        )
      )
    )
  )

  body <- list(
    model = "gemma-thinking-test",
    messages = list(list(role = "user", content = "test")),
    stream = TRUE,
    max_tokens = 128L,
    chat_template_kwargs = list(
      existing_value = "korunmalı"
    )
  )

  merged <- apply_model_request_overrides(
    body = body,
    model_id = "gemma-thinking-test",
    config = fake_config
  )

  expect_true(is.list(merged$chat_template_kwargs))
  expect_true(isTRUE(merged$chat_template_kwargs$enable_thinking))
  expect_identical(merged$chat_template_kwargs$existing_value, "korunmalı")

  # Ana istek alanları override sırasında kaybolmamalı.
  expect_identical(merged$model, "gemma-thinking-test")
  expect_true(isTRUE(merged$stream))
  expect_identical(merged$max_tokens, 128L)
})

test_that("request_overrides tanımlı değilse body aynen kalır", {
  fake_config <- list(
    local_model_capabilities = list(
      "plain-model-test" = list(
        thinking = FALSE,
        omit_temperature = FALSE,
        stream_reasoning = FALSE,
        allow_reasoning_fallback = FALSE
      )
    )
  )

  body <- list(
    model = "plain-model-test",
    messages = list(list(role = "user", content = "test")),
    stream = TRUE,
    max_tokens = 64L
  )

  merged <- apply_model_request_overrides(
    body = body,
    model_id = "plain-model-test",
    config = fake_config
  )

  expect_identical(merged, body)
})

test_that("true SSE worker model request_overrides fonksiyonunu kullanır", {
  txt <- .read_repo_file_bytes_for_reasoning_contract("R/helpers_llm_sse.R")

  expect_true(
    grepl(
      "apply_model_request_overrides\\s*\\(\\s*body\\s*,\\s*selected_model",
      txt,
      perl = TRUE,
      useBytes = TRUE
    ),
    info = "R/helpers_llm_sse.R içinde SSE body'ye apply_model_request_overrides(body, selected_model) uygulanmalı."
  )
})

test_that("future worker globals apply_model_request_overrides fonksiyonunu taşır", {
  txt <- .read_repo_file_bytes_for_reasoning_contract("R/server_handler_true_streaming.R")

  expect_true(
    grepl(
      "apply_model_request_overrides\\s*=\\s*apply_model_request_overrides",
      txt,
      perl = TRUE,
      useBytes = TRUE
    ),
    info = "R/server_handler_true_streaming.R globals listesinde apply_model_request_overrides taşınmalı."
  )
})

test_that("reasoning debug çıktıları üretimde varsayılan olarak kapalıdır", {
  txt <- .read_repo_file_bytes_for_reasoning_contract("R/helpers_llm_sse.R")

  expect_true(
    grepl(
      "MERGEN_REASONING_DEBUG",
      txt,
      fixed = TRUE,
      useBytes = TRUE
    ),
    info = "Reasoning debug çıktıları ortam değişkeniyle kontrol edilmeli."
  )

  expect_true(
    grepl(
      "reasoning_debug_enabled\\s*<-\\s*isTRUE\\s*\\(\\s*as\\.logical\\s*\\(\\s*Sys\\.getenv\\s*\\(\\s*['\"]MERGEN_REASONING_DEBUG['\"]\\s*,\\s*['\"]FALSE['\"]\\s*\\)",
      txt,
      perl = TRUE,
      useBytes = TRUE
    ),
    info = "Reasoning debug varsayılanı FALSE olmalı."
  )
})