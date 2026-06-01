# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-second-pass-contract.R
# Açıklama:   MCP araç sonuçları sonrası ikinci LLM geçişinin SSE ve güvenli
#             non-streaming geri dönüş davranışını model adlarından bağımsız
#             olarak doğrular.
# ==============================================================================

.find_repo_root_llm_worker_second_pass <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

repo_root_llm_worker_second_pass <- .find_repo_root_llm_worker_second_pass()

assign(
  "%||%",
  function(x, y) if (is.null(x)) y else x,
  envir = globalenv()
)

assign(
  "log_info",
  function(...) invisible(NULL),
  envir = globalenv()
)

assign(
  "log_warn",
  function(...) invisible(NULL),
  envir = globalenv()
)

assign(
  "should_omit_temperature",
  function(model_id) {
    identical(model_id, "temperature-omitting-test-model")
  },
  envir = globalenv()
)

assign(
  "format_answer_from_tool_results",
  function(tool_results_raw) {
    "Araç sonucu yedek yanıtı"
  },
  envir = globalenv()
)

assign(
  "extract_llm_content_and_sources",
  function(parsed, model_id = NULL) {
    list(
      content = parsed$content %||% "",
      reasoning = parsed$reasoning %||% ""
    )
  },
  envir = globalenv()
)

source(
  file.path(repo_root_llm_worker_second_pass, "R", "helpers_llm_worker_payload.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_llm_worker_second_pass, "R", "helpers_llm_worker_second_pass.R"),
  encoding = "UTF-8",
  local = globalenv()
)

test_that("ikinci geçiş mesajları system mesajlarını tek blokta öne alır", {
  history <- list(
    list(role = "user", content = "Kullanıcı sorusu"),
    list(role = "system", content = "Kural 1"),
    list(role = "assistant", content = "Araçlar kullanıldı"),
    list(role = "system", content = "Kural 2")
  )

  out <- llm_worker_second_pass_messages(history)
  roles <- vapply(out, `[[`, character(1), "role")

  expect_identical(roles, c("system", "user", "assistant"))
  expect_identical(out[[1]]$content, "Kural 1\n\nKural 2")
})

test_that("ikinci geçiş gövdesi model adından bağımsız doğru istek oluşturur", {
  body <- llm_worker_second_pass_body(
    selected_model = "runtime-model-under-test",
    messages_payload = list(list(role = "user", content = "Merhaba")),
    temp_value = 0.4
  )

  expect_identical(body$model, "runtime-model-under-test")
  expect_false(isTRUE(body$stream))
  expect_identical(body$temperature, 0.4)

  body_without_temperature <- llm_worker_second_pass_body(
    selected_model = "temperature-omitting-test-model",
    messages_payload = list(list(role = "user", content = "Merhaba")),
    temp_value = 0.4
  )

  expect_null(body_without_temperature$temperature)
})

test_that("SSE yalnızca düşünce döndürürse mesaj gövdesine basılmaz ve non-streaming cevaba düşülür", {
  old_sse_exists <- exists("call_local_llm_sse_worker", envir = globalenv(), inherits = FALSE)
  old_sse <- if (old_sse_exists) get("call_local_llm_sse_worker", envir = globalenv()) else NULL

  old_non_stream <- get("llm_worker_call_second_pass_non_streaming", envir = globalenv())

  on.exit({
    if (old_sse_exists) {
      assign("call_local_llm_sse_worker", old_sse, envir = globalenv())
    } else if (exists("call_local_llm_sse_worker", envir = globalenv(), inherits = FALSE)) {
      rm("call_local_llm_sse_worker", envir = globalenv())
    }

    assign(
      "llm_worker_call_second_pass_non_streaming",
      old_non_stream,
      envir = globalenv()
    )
  }, add = TRUE)

  captured <- new.env(parent = emptyenv())
  captured$non_stream_called <- FALSE

  assign(
    "call_local_llm_sse_worker",
    function(chat_history, current_settings, stream_file, stop_file = NULL) {
      captured$chat_history <- chat_history
      captured$sse_settings <- current_settings

      list(
        success = TRUE,
        content = "Thinking Process:\n1. Bu yalnızca düşünce metnidir.",
        reasoning = "Thinking Process:\n1. Bu yalnızca düşünce metnidir.",
        error = NULL
      )
    },
    envir = globalenv()
  )

  assign(
    "llm_worker_call_second_pass_non_streaming",
    function(api_endpoint, hdrs, body, selected_model) {
      captured$non_stream_called <- TRUE
      captured$non_stream_body <- body

      list(
        success = TRUE,
        status = 200L,
        error_body = "",
        content = "Nihai kullanıcı yanıtı",
        reasoning = ""
      )
    },
    envir = globalenv()
  )

  out <- llm_worker_run_mcp_second_pass(
    chat_history = list(
      list(role = "system", content = "Kural 1"),
      list(role = "user", content = "Excel dosyasını özetle"),
      list(role = "assistant", content = "[Araçlar kullanıldı]"),
      list(role = "system", content = "Kural 2")
    ),
    selected_model = "runtime-model-under-test",
    settings = list(
      enable_mcp_reasoning_stream = TRUE,
      mcp_reasoning_stream_file = tempfile("mcp_reasoning_test_"),
      api_key_override = ""
    ),
    api_endpoint = "http://test.invalid/v1/chat/completions",
    api_key = "test-key",
    temp_value = 0.4,
    tool_results_raw = list(list(text = "araç sonucu")),
    chart_blocks_text = "",
    charts_to_store = list(),
    add_fallback_chart = function(x) x,
    worker_start_time = Sys.time()
  )

  expect_true(isTRUE(out$ok))
  expect_identical(out$ai2, "Nihai kullanıcı yanıtı")
  expect_true(isTRUE(captured$non_stream_called))

  expect_false(isTRUE(captured$sse_settings$enable_mcp_tools))
  expect_false(isTRUE(captured$sse_settings$allow_reasoning_fallback_override))

  sse_roles <- vapply(captured$chat_history, `[[`, character(1), "role")
  expect_identical(sse_roles, c("system", "user", "assistant"))
  expect_true(grepl("Kural 1\n\nKural 2", captured$chat_history[[1]]$content, fixed = TRUE))
})

test_that("SSE gerçek yanıt döndürürse non-streaming geri dönüş çağrılmaz", {
  old_sse_exists <- exists("call_local_llm_sse_worker", envir = globalenv(), inherits = FALSE)
  old_sse <- if (old_sse_exists) get("call_local_llm_sse_worker", envir = globalenv()) else NULL

  old_non_stream <- get("llm_worker_call_second_pass_non_streaming", envir = globalenv())

  on.exit({
    if (old_sse_exists) {
      assign("call_local_llm_sse_worker", old_sse, envir = globalenv())
    } else if (exists("call_local_llm_sse_worker", envir = globalenv(), inherits = FALSE)) {
      rm("call_local_llm_sse_worker", envir = globalenv())
    }

    assign(
      "llm_worker_call_second_pass_non_streaming",
      old_non_stream,
      envir = globalenv()
    )
  }, add = TRUE)

  assign(
    "call_local_llm_sse_worker",
    function(chat_history, current_settings, stream_file, stop_file = NULL) {
      list(
        success = TRUE,
        content = "Nihai SSE yanıtı",
        reasoning = "Canlı düşünce metni",
        error = NULL
      )
    },
    envir = globalenv()
  )

  assign(
    "llm_worker_call_second_pass_non_streaming",
    function(api_endpoint, hdrs, body, selected_model) {
      stop("SSE gerçek yanıt döndürdüğünde non-streaming geri dönüş çağrılmamalı.")
    },
    envir = globalenv()
  )

  out <- llm_worker_run_mcp_second_pass(
    chat_history = list(list(role = "user", content = "Excel dosyasını özetle")),
    selected_model = "runtime-model-under-test",
    settings = list(
      enable_mcp_reasoning_stream = TRUE,
      mcp_reasoning_stream_file = tempfile("mcp_reasoning_test_"),
      api_key_override = ""
    ),
    api_endpoint = "http://test.invalid/v1/chat/completions",
    api_key = "test-key",
    temp_value = 0.4,
    tool_results_raw = list(list(text = "araç sonucu")),
    chart_blocks_text = "",
    charts_to_store = list(),
    add_fallback_chart = function(x) x,
    worker_start_time = Sys.time()
  )

  expect_true(isTRUE(out$ok))
  expect_identical(out$ai2, "Nihai SSE yanıtı")
  expect_identical(out$reasoning2, "Canlı düşünce metni")
})

test_that("düşünceye benzeyen stream içeriği model adından bağımsız yakalanır", {
  expect_true(llm_worker_stream_content_looks_like_reasoning(
    stream_content = "Thinking Process:\n1. Analiz",
    stream_reasoning = "Thinking Process:\n1. Analiz"
  ))

  expect_true(llm_worker_stream_content_looks_like_reasoning(
    stream_content = "Okay, I will structure it logically.",
    stream_reasoning = "Başka düşünce metni"
  ))

  expect_false(llm_worker_stream_content_looks_like_reasoning(
    stream_content = "Yönetici Özeti\nBu nihai yanıttır.",
    stream_reasoning = "Düşünce metni"
  ))
})