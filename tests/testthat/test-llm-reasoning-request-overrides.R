# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-reasoning-request-overrides.R
# Açıklama: Thinking/reasoning modeller için model bazlı request_overrides
# sözleşmesini doğrular. Özellikle gemma benzeri modellerde
# chat_template_kwargs$enable_thinking alanının future worker'a ulaşması
# korunmalıdır.
# ==============================================================================

.bootstrap_llm_reasoning_override_contract <- function() {
  helper_candidates <- c(
    "tests/testthat/helper_bootstrap.R",
    "testthat/helper_bootstrap.R",
    "helper_bootstrap.R"
  )

  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) {
    source(helper_path, encoding = "UTF-8", local = globalenv())
  }

  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() {
      candidates <- c(".", "..", "../..")
      for (cand in candidates) {
        if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
          return(normalizePath(cand, winslash = "/", mustWork = TRUE))
        }
      }
      stop("Repo kökü bulunamadı. Test çalışma dizinini kontrol edin.", call. = FALSE)
    }
  }

  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(x, y) if (is.null(x)) y else x
  }

  if (!exists("log_info", mode = "function", inherits = TRUE)) {
    log_info <<- function(...) invisible(NULL)
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn <<- function(...) invisible(NULL)
  }
  if (!exists("log_debug", mode = "function", inherits = TRUE)) {
    log_debug <<- function(...) invisible(NULL)
  }

  # config_api.R .Renviron ve indeks hazırlığına bakabildiği için testte güvenli
  # placeholder ortam değişkenleri açıkça verilir.
  Sys.setenv(
    MERGEN_RUN_APP = "false",
    MERGEN_DISABLE_FUTURES = "true",
    LOCAL_LLM_ENDPOINT = Sys.getenv("LOCAL_LLM_ENDPOINT", "http://test.local/v1"),
    DB_DSN = Sys.getenv("DB_DSN", "test-dsn"),
    AI_KEYS_MASTER = Sys.getenv("AI_KEYS_MASTER", "test-master-key-0123456789")
  )

  if (!exists(".build_basename_index", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "utils_file_index.R"),
           encoding = "UTF-8", local = globalenv())
  }

  source(file.path(repo_root, "R", "config_api.R"),
         encoding = "UTF-8", local = globalenv())

  invisible(TRUE)
}

.bootstrap_llm_reasoning_override_contract()

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
      "Sys\\.getenv\\s*\\(\\s*['\"]MERGEN_REASONING_DEBUG['\"]\\s*,\\s*['\"]FALSE['\"]\\s*\\)",
      txt,
      perl = TRUE,
      useBytes = TRUE
    ),
    info = "Reasoning debug varsayılanı FALSE olmalı."
  )
})

test_that("non-streaming LLM path model request_overrides fonksiyonunu kullanır", {
  txt <- .read_repo_file_bytes_for_reasoning_contract("R/helpers_llm_api.R")

  expect_true(
    grepl(
      "apply_model_request_overrides\\s*\\(\\s*body\\s*,\\s*selected_model",
      txt,
      perl = TRUE,
      useBytes = TRUE
    ),
    info = paste(
      "R/helpers_llm_api.R içinde non-streaming body'ye",
      "apply_model_request_overrides(body, selected_model) uygulanmalı.",
      "Aksi halde Thinking modeller SSE ve non-streaming yollarda farklı davranır."
    )
  )
})