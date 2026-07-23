# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-call-behavior.R
# Açıklama: call_llm_worker (R/helpers_llm_worker.R) MCP araç destekli LLM işçi
#           fonksiyonunun ARAÇSIZ (enable_tools=FALSE) yolunu ve HATA NORMALİZASYON
#           sınırını davranışsal olarak sınar. İkinci-geçiş/araç-yürütme zinciri
#           ayrı, ağır bir yoldur; bu test onu mock dışı bırakır ve şunları kilitler:
#             * araçsız mutlu yol: içerik + sayısal süre + boş chart_store döner,
#             * düşünen-model reasoning metni reasoning_content olarak üst katmana taşınır,
#             * içerik+araç-çağrısı yoksa EMPTY_RESPONSE,
#             * HTTP 429/401/403/5xx/diğer -> RATE_LIMIT/AUTH_ERROR/SERVER_ERROR/API_ERROR,
#             * beklenmeyen genel hata -> UNKNOWN_ERROR,
#             * zaman aşımı -> TIMEOUT.
#           Gerçek ağ/LLM/DB GEREKMEZ; httr namespace'i local_mocked_bindings ile
#           taklit edilir, saf payload yardımcıları deterministik stub'lanır.
# ==============================================================================

testthat::local_edition(3)

testthat::skip_if_not_installed("httr")
testthat::skip_if_not_installed("jsonlite")

# call_llm_worker, enclosing env'de çözülen çok sayıda yardımcıya bağlıdır.
# İzole, deterministik bir env kurup gerçek fonksiyonu source ederiz.
.clw_env <- new.env(parent = globalenv())
.clw_env$`%||%` <- function(a, b) if (is.null(a)) b else a
.clw_env$mergen_debug_cat <- function(...) invisible(NULL)
.clw_env$log_info <- function(...) invisible(NULL)
.clw_env$should_omit_temperature <- function(model) FALSE
.clw_env$apply_model_request_overrides <- function(body, model) body
# Saf payload yardımcıları: araçsız yol için yeterli minimal davranış.
.clw_env$llm_worker_chat_history_to_messages <- function(ch) ch
.clw_env$llm_worker_merge_system_messages_to_front <- function(payload) payload
.clw_env$llm_worker_has_chart_intent <- function(ch) FALSE
.clw_env$llm_worker_detect_chart_type_from_text <- function(...) NULL
.clw_env$llm_worker_add_fallback_chart <- function(x) x
.clw_env$llm_worker_build_chart_summary <- function(...) ""
.clw_env$llm_worker_build_auto_insight <- function(...) ""
.clw_env$strip_planner_text <- function(x) x
# Varsayılan içerik ayrıştırıcı (testler içinde gerektiğinde override edilir).
.clw_env$extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
  list(content = "varsayilan", reasoning = "")
}

source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_worker.R"),
  encoding = "UTF-8",
  local = .clw_env
)

# Araçsız çağrı için minimal ayarlar ve sohbet geçmişi.
.clw_settings <- function(...) {
  modifyList(list(model_selection = "model-x"), list(...))
}
.clw_history <- function() list(list(role = "user", content = "soru"))

# Belirli bir HTTP durum kodu + parse edilmiş yanıt için httr mock'larını kurar.
# local_mocked_bindings çağrı çerçevesine bağlandığından, doğrudan test_that
# içinde çağrılmalıdır; bu yüzden bu yardımcı yalnızca mock değerlerini üretir.
.clw_response <- structure(list(), class = "clw_fake_response")

test_that("araçsız mutlu yol: içerik + sayısal süre + boş chart_store döner", {
  .clw_env$extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
    list(content = "Merhaba dünya", reasoning = "")
  }
  testthat::local_mocked_bindings(
    POST = function(url, ...) .clw_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) list(id = "x") else "",
    .package = "httr"
  )

  out <- .clw_env$call_llm_worker(
    chat_history = .clw_history(),
    settings = .clw_settings(),
    api_endpoint = "http://local/api",
    enable_tools = FALSE
  )

  expect_type(out, "list")
  expect_identical(out$content, "Merhaba dünya")
  expect_true(is.numeric(out$duration) && out$duration >= 0)
  expect_identical(out$chart_store, list())
  # reasoning boşsa reasoning_content alanı NULL olmalı.
  expect_null(out$reasoning_content)
})

test_that("istek gövdesi max_tokens alanını içerir (varsayılan 32768, settings geçersiz kılabilir)", {
  .clw_env$extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
    list(content = "Merhaba", reasoning = "")
  }
  captured <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    POST = function(url, ..., body = NULL) {
      captured$body <- jsonlite::fromJSON(body)
      .clw_response
    },
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) list(id = "x") else "",
    .package = "httr"
  )

  # Varsayılan: settings$max_output_tokens verilmemişse 32768 kullanılmalı
  # (streaming/non-streaming yollarıyla aynı varsayılan sözleşme).
  .clw_env$call_llm_worker(
    chat_history = .clw_history(),
    settings = .clw_settings(),
    api_endpoint = "http://local/api",
    enable_tools = FALSE
  )
  expect_identical(as.integer(captured$body$max_tokens), 32768L)

  # SQL Analizi/Kod Uzmanı gibi araçların ayarladığı özel limit uç noktaya
  # gerçekten iletilmeli (önceden bu worker yolu max_tokens'i hiç göndermiyordu).
  .clw_env$call_llm_worker(
    chat_history = .clw_history(),
    settings = .clw_settings(max_output_tokens = 9999L),
    api_endpoint = "http://local/api",
    enable_tools = FALSE
  )
  expect_identical(as.integer(captured$body$max_tokens), 9999L)
})

test_that("düşünen-model reasoning metni reasoning_content olarak taşınır", {
  .clw_env$extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
    list(content = "Yanıt gövdesi", reasoning = "iç düşünce izi")
  }
  testthat::local_mocked_bindings(
    POST = function(url, ...) .clw_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) list(id = "x") else "",
    .package = "httr"
  )

  out <- .clw_env$call_llm_worker(
    chat_history = .clw_history(),
    settings = .clw_settings(),
    api_endpoint = "http://local/api",
    enable_tools = FALSE
  )

  expect_identical(out$content, "Yanıt gövdesi")
  expect_identical(out$reasoning_content, "iç düşünce izi")
})

test_that("içerik ve araç çağrısı yoksa EMPTY_RESPONSE fırlatır", {
  .clw_env$extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
    list(content = "", reasoning = "")
  }
  testthat::local_mocked_bindings(
    POST = function(url, ...) .clw_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) list(id = "x") else "",
    .package = "httr"
  )

  expect_error(
    capture.output(.clw_env$call_llm_worker(
      chat_history = .clw_history(),
      settings = .clw_settings(),
      api_endpoint = "http://local/api",
      enable_tools = FALSE
    )),
    "EMPTY_RESPONSE"
  )
})

test_that("HTTP 429 -> RATE_LIMIT olarak normalize edilir", {
  testthat::local_mocked_bindings(
    POST = function(url, ...) .clw_response,
    status_code = function(resp) 429L,
    content = function(x, as = NULL, ...) "limit",
    .package = "httr"
  )
  expect_error(
    capture.output(.clw_env$call_llm_worker(.clw_history(), .clw_settings(), "http://local/api", enable_tools = FALSE)),
    "RATE_LIMIT"
  )
})

test_that("HTTP 401/403 -> AUTH_ERROR olarak normalize edilir", {
  testthat::local_mocked_bindings(
    POST = function(url, ...) .clw_response,
    status_code = function(resp) 401L,
    content = function(x, as = NULL, ...) "unauthorized",
    .package = "httr"
  )
  expect_error(
    capture.output(.clw_env$call_llm_worker(.clw_history(), .clw_settings(), "http://local/api", enable_tools = FALSE)),
    "AUTH_ERROR"
  )
})

test_that("HTTP 5xx -> SERVER_ERROR olarak normalize edilir", {
  testthat::local_mocked_bindings(
    POST = function(url, ...) .clw_response,
    status_code = function(resp) 503L,
    content = function(x, as = NULL, ...) "down",
    .package = "httr"
  )
  expect_error(
    capture.output(.clw_env$call_llm_worker(.clw_history(), .clw_settings(), "http://local/api", enable_tools = FALSE)),
    "SERVER_ERROR"
  )
})

test_that("diğer 4xx -> API_ERROR olarak normalize edilir", {
  testthat::local_mocked_bindings(
    POST = function(url, ...) .clw_response,
    status_code = function(resp) 418L,
    content = function(x, as = NULL, ...) "teapot",
    .package = "httr"
  )
  expect_error(
    capture.output(.clw_env$call_llm_worker(.clw_history(), .clw_settings(), "http://local/api", enable_tools = FALSE)),
    "API_ERROR"
  )
})

test_that("beklenmeyen genel hata -> UNKNOWN_ERROR olarak sarmalanır", {
  .clw_env$extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
    stop("beklenmeyen ayrıştırma hatası")
  }
  testthat::local_mocked_bindings(
    POST = function(url, ...) .clw_response,
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) if (identical(as, "parsed")) list(id = "x") else "",
    .package = "httr"
  )
  expect_error(
    capture.output(.clw_env$call_llm_worker(.clw_history(), .clw_settings(), "http://local/api", enable_tools = FALSE)),
    "UNKNOWN_ERROR"
  )
})

test_that("istek zaman aşımı -> TIMEOUT olarak normalize edilir", {
  testthat::local_mocked_bindings(
    POST = function(url, ...) stop("Timeout was reached"),
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) "",
    .package = "httr"
  )
  expect_error(
    capture.output(.clw_env$call_llm_worker(.clw_history(), .clw_settings(), "http://local/api", enable_tools = FALSE)),
    "TIMEOUT"
  )
})
