# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-second-pass-flow-behavior.R
# Açıklama: helpers_llm_worker_second_pass.R içinde MEVCUT testlerin kapsamadığı
#           gerçek akış dallarını doldurur:
#             * llm_worker_call_second_pass_non_streaming() GERÇEK httr davranışı
#               (mevcut sözleşme testi bu fonksiyonu hep STUB'lar): 200 -> success
#               + içerik/reasoning; 200 dışı -> success=FALSE + status + error_body.
#             * llm_worker_run_mcp_second_pass() NON-SSE yolu (üretimdeki yaygın
#               varsayılan; sözleşme testi yalnızca SSE-açık yolu kapsar):
#               non-stream başarı -> ok=TRUE/ai2; non-stream hata -> ok=FALSE/yedek.
#             * SSE başarısız -> non-stream retry de başarısız -> ok=FALSE/yedek,
#               reasoning_content stream reasoning'inden taşınır.
#           Gerçek ağ/LLM GEREKMEZ; httr namespace local_mocked_bindings ile,
#           SSE işçisi + non-streaming yardımcısı deterministik stub'lanır.
# ==============================================================================

testthat::local_edition(3)

testthat::skip_if_not_installed("httr")
testthat::skip_if_not_installed("jsonlite")

.sp_env <- new.env(parent = globalenv())
.sp_env$`%||%` <- function(x, y) if (is.null(x)) y else x
.sp_env$log_info <- function(...) invisible(NULL)
.sp_env$log_warn <- function(...) invisible(NULL)
.sp_env$should_omit_temperature <- function(model, config = NULL) FALSE
.sp_env$llm_worker_chat_history_to_messages <- function(ch) ch
.sp_env$merge_system_messages_to_front <- function(payload) payload
.sp_env$format_answer_from_tool_results <- function(tool_results_raw) "araç sonucu yedeği"
.sp_env$extract_llm_content_and_sources <- function(parsed, model_id = NULL) {
  list(
    content = if (is.null(parsed$content)) "" else parsed$content,
    reasoning = if (is.null(parsed$reasoning)) "" else parsed$reasoning
  )
}

source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_worker_second_pass.R"),
  encoding = "UTF-8",
  local = .sp_env
)

# Stub edilmeden ÖNCE gerçek non-streaming yardımcısını sakla (B/C testleri override
# eder ve geri yükler; A testleri gerçek davranışı sınar).
.sp_real_non_stream <- .sp_env$llm_worker_call_second_pass_non_streaming

.sp_run_args <- function(settings) {
  list(
    chat_history = list(list(role = "user", content = "Excel dosyasını özetle")),
    selected_model = "runtime-model",
    settings = settings,
    api_endpoint = "http://local/api",
    api_key = "anahtar",
    temp_value = 0.4,
    tool_results_raw = list(list(text = "araç çıktısı")),
    chart_blocks_text = "",
    charts_to_store = list(),
    add_fallback_chart = function(x) x,
    worker_start_time = Sys.time()
  )
}

test_that("non-streaming çağrısı 200'de success + içerik/reasoning döndürür", {
  testthat::local_mocked_bindings(
    POST = function(url, ...) structure(list(), class = "sp_fake_resp"),
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) {
      if (identical(as, "parsed")) list(content = "Nihai kullanıcı yanıtı", reasoning = "düşünce izi") else ""
    },
    .package = "httr"
  )

  out <- .sp_real_non_stream(
    api_endpoint = "http://local/api",
    hdrs = list(`Content-Type` = "application/json"),
    body = list(model = "runtime-model"),
    selected_model = "runtime-model"
  )

  expect_true(isTRUE(out$success))
  expect_identical(out$status, 200L)
  expect_identical(out$content, "Nihai kullanıcı yanıtı")
  expect_identical(out$reasoning, "düşünce izi")
  expect_identical(out$error_body, "")
})

test_that("non-streaming çağrısı 200 dışı durumda success=FALSE + status + error_body döndürür", {
  testthat::local_mocked_bindings(
    POST = function(url, ...) structure(list(), class = "sp_fake_resp"),
    status_code = function(resp) 500L,
    content = function(x, as = NULL, ...) "Sunucu hatası gövdesi",
    .package = "httr"
  )

  out <- .sp_real_non_stream(
    api_endpoint = "http://local/api",
    hdrs = list(`Content-Type` = "application/json"),
    body = list(model = "runtime-model"),
    selected_model = "runtime-model"
  )

  expect_false(isTRUE(out$success))
  expect_identical(out$status, 500L)
  expect_identical(out$error_body, "Sunucu hatası gövdesi")
  expect_identical(out$content, "")
})

test_that("non-streaming çağrısı verilen timeout_sec'i httr::POST'a iletir (varsayılan 300sn)", {
  captured <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    POST = function(url, ...) {
      dots <- list(...)
      req_configs <- Filter(function(x) inherits(x, "request"), dots)
      captured$timeout_ms <- vapply(req_configs, function(x) {
        tm <- x$options$timeout_ms
        if (is.null(tm)) NA_real_ else as.numeric(tm)
      }, numeric(1))
      structure(list(), class = "sp_fake_resp")
    },
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) {
      if (identical(as, "parsed")) list(content = "yanıt", reasoning = "") else ""
    },
    .package = "httr"
  )

  # Varsayılan (parametre verilmezse) eski 300sn davranışı korunmalı.
  .sp_real_non_stream(
    api_endpoint = "http://local/api",
    hdrs = list(`Content-Type` = "application/json"),
    body = list(model = "runtime-model"),
    selected_model = "runtime-model"
  )
  expect_true(any(captured$timeout_ms == 300000, na.rm = TRUE))

  # Uzatılmış zaman aşımı (ör. MERGEN_LLM_TIMEOUT_SEC=1800) doğru şekilde iletilmeli.
  .sp_real_non_stream(
    api_endpoint = "http://local/api",
    hdrs = list(`Content-Type` = "application/json"),
    body = list(model = "runtime-model"),
    selected_model = "runtime-model",
    timeout_sec = 1800
  )
  expect_true(any(captured$timeout_ms == 1800000, na.rm = TRUE))
})

test_that("llm_worker_run_mcp_second_pass verilen timeout_sec'i gerçek non-streaming çağrısına iletir (NON-SSE yol)", {
  captured <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    POST = function(url, ...) {
      dots <- list(...)
      req_configs <- Filter(function(x) inherits(x, "request"), dots)
      captured$timeout_ms <- vapply(req_configs, function(x) {
        tm <- x$options$timeout_ms
        if (is.null(tm)) NA_real_ else as.numeric(tm)
      }, numeric(1))
      structure(list(), class = "sp_fake_resp")
    },
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) {
      if (identical(as, "parsed")) list(content = "yanıt", reasoning = "") else ""
    },
    .package = "httr"
  )

  # SSE kapalı -> NON-SSE yol, gerçek (stub'lanmamış) non-streaming yardımcısı çağrılır.
  args <- .sp_run_args(settings = list())
  args$timeout_sec <- 1800
  do.call(.sp_env$llm_worker_run_mcp_second_pass, args)

  expect_true(any(captured$timeout_ms == 1800000, na.rm = TRUE))
})

test_that("llm_worker_run_mcp_second_pass settings$max_output_tokens'ı gerçek non-streaming gövdesine iletir (NON-SSE yol)", {
  captured <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    POST = function(url, ..., body = NULL) {
      captured$body <- jsonlite::fromJSON(body)
      structure(list(), class = "sp_fake_resp")
    },
    status_code = function(resp) 200L,
    content = function(x, as = NULL, ...) {
      if (identical(as, "parsed")) list(content = "yanıt", reasoning = "") else ""
    },
    .package = "httr"
  )

  # SQL Analizi/Kod Uzmanı tool_family'sinin ayarladığı özel limit örneği
  # (varsayılan 32768'den farklı bir değer, iletimin gerçekten çalıştığını
  # kanıtlamak için).
  args <- .sp_run_args(settings = list(max_output_tokens = 9999L))
  do.call(.sp_env$llm_worker_run_mcp_second_pass, args)

  expect_identical(as.integer(captured$body$max_tokens), 9999L)
})

test_that("NON-SSE yol: non-streaming başarısı ok=TRUE + ai2 + reasoning döndürür", {
  .sp_env$llm_worker_call_second_pass_non_streaming <- function(api_endpoint, hdrs, body, selected_model, timeout_sec = 300) {
    list(success = TRUE, status = 200L, error_body = "", content = "Non-SSE final yanıt", reasoning = "r1")
  }
  on.exit(.sp_env$llm_worker_call_second_pass_non_streaming <- .sp_real_non_stream, add = TRUE)

  # enable_mcp_reasoning_stream yok -> SSE devre dışı -> non-SSE yolu.
  out <- do.call(.sp_env$llm_worker_run_mcp_second_pass, .sp_run_args(settings = list()))

  expect_true(isTRUE(out$ok))
  expect_identical(out$ai2, "Non-SSE final yanıt")
  expect_identical(out$reasoning2, "r1")
})

test_that("NON-SSE yol: non-streaming hatası ok=FALSE + araç-sonucu yedeği döndürür", {
  .sp_env$llm_worker_call_second_pass_non_streaming <- function(api_endpoint, hdrs, body, selected_model, timeout_sec = 300) {
    list(success = FALSE, status = 503L, error_body = "down", content = "", reasoning = "")
  }
  on.exit(.sp_env$llm_worker_call_second_pass_non_streaming <- .sp_real_non_stream, add = TRUE)

  out <- do.call(.sp_env$llm_worker_run_mcp_second_pass, .sp_run_args(settings = list()))

  expect_false(isTRUE(out$ok))
  expect_identical(out$response$content, "araç sonucu yedeği")
  expect_null(out$response$reasoning_content)
})

test_that("SSE başarısız + non-streaming retry de başarısız -> ok=FALSE/yedek, reasoning taşınır", {
  .sp_env$call_local_llm_sse_worker <- function(chat_history, current_settings, stream_file, stop_file = NULL) {
    list(success = FALSE, content = "", reasoning = "canlı düşünce metni", error = "sse-boom")
  }
  .sp_env$llm_worker_call_second_pass_non_streaming <- function(api_endpoint, hdrs, body, selected_model, timeout_sec = 300) {
    list(success = FALSE, status = 500L, error_body = "retry-down", content = "", reasoning = "")
  }
  on.exit({
    .sp_env$llm_worker_call_second_pass_non_streaming <- .sp_real_non_stream
    if (exists("call_local_llm_sse_worker", envir = .sp_env, inherits = FALSE)) {
      rm("call_local_llm_sse_worker", envir = .sp_env)
    }
  }, add = TRUE)

  settings <- list(
    enable_mcp_reasoning_stream = TRUE,
    mcp_reasoning_stream_file = tempfile("sp_reasoning_"),
    api_key_override = ""
  )
  out <- do.call(.sp_env$llm_worker_run_mcp_second_pass, .sp_run_args(settings = settings))

  expect_false(isTRUE(out$ok))
  expect_identical(out$response$content, "araç sonucu yedeği")
  # SSE'den gelen canlı düşünce, yedek yanıta reasoning_content olarak taşınmalı.
  expect_identical(out$response$reasoning_content, "canlı düşünce metni")
})
