# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-model-runtime-contract.R
# Açıklama:   Mesaj gönderimi sırasında runtime model çözümleme ve MCP canlı
#             Düşünce Akışı hazırlığının model adlarından bağımsız sözleşmesini
#             doğrular.
# ==============================================================================

.find_repo_root_send_message_model_runtime <- function() {
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

repo_root_send_message_model_runtime <- .find_repo_root_send_message_model_runtime()

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

log_info <- function(...) invisible(NULL)

source(
  file.path(repo_root_send_message_model_runtime, "R", "helpers_send_message_model_runtime.R"),
  encoding = "UTF-8",
  local = globalenv()
)

test_that("Excel Derin Düşünme runtime modeli tek noktadan çözülür ve MCP reasoning stream açılır", {
  old_resolve_exists <- exists("resolve_runtime_model_for_request", envir = globalenv(), inherits = FALSE)
  old_resolve <- if (old_resolve_exists) get("resolve_runtime_model_for_request", envir = globalenv()) else NULL

  old_thinking_exists <- exists("is_thinking_model", envir = globalenv(), inherits = FALSE)
  old_thinking <- if (old_thinking_exists) get("is_thinking_model", envir = globalenv()) else NULL

  on.exit({
    if (old_resolve_exists) {
      assign("resolve_runtime_model_for_request", old_resolve, envir = globalenv())
    } else if (exists("resolve_runtime_model_for_request", envir = globalenv(), inherits = FALSE)) {
      rm("resolve_runtime_model_for_request", envir = globalenv())
    }

    if (old_thinking_exists) {
      assign("is_thinking_model", old_thinking, envir = globalenv())
    } else if (exists("is_thinking_model", envir = globalenv(), inherits = FALSE)) {
      rm("is_thinking_model", envir = globalenv())
    }
  }, add = TRUE)

  captured <- new.env(parent = emptyenv())

  assign(
    "resolve_runtime_model_for_request",
    function(tool_family,
             fallback_model = NULL,
             excel_deep_on = FALSE,
             excel_deep_level = "low",
             coding_deep_on = FALSE,
             coding_deep_level = "low",
             config = NULL) {
      captured$tool_family <- tool_family
      captured$fallback_model <- fallback_model
      captured$excel_deep_on <- excel_deep_on
      captured$excel_deep_level <- excel_deep_level
      captured$coding_deep_on <- coding_deep_on
      captured$coding_deep_level <- coding_deep_level

      "resolved-runtime-model"
    },
    envir = globalenv()
  )

  assign(
    "is_thinking_model",
    function(model_id) identical(model_id, "resolved-runtime-model"),
    envir = globalenv()
  )

  out <- mergen_prepare_send_message_model_runtime(
    input = list(
      chat_excel_deep_thinking = FALSE,
      chat_excel_deep_level = "high",
      chat_coding_deep_thinking = FALSE,
      chat_coding_deep_level = "low"
    ),
    settings_data = list(
      excel_deep_thinking = TRUE,
      excel_deep_level = "low",
      coding_deep_thinking = FALSE,
      coding_deep_level = "low",
      enable_tts_audio = FALSE
    ),
    current_settings = list(
      model_selection = "dropdown-fallback-model",
      enable_streaming = TRUE
    ),
    tool_family = "mcp_excel",
    req_id = "req_test_001"
  )

  expect_identical(out$model_selected, "resolved-runtime-model")
  expect_true(isTRUE(out$mcp_reasoning_stream_on))
  expect_true(isTRUE(out$current_settings$enable_mcp_reasoning_stream))
  expect_identical(out$current_settings$mcp_reasoning_request_id, "req_test_001")

  expect_identical(captured$tool_family, "mcp_excel")
  expect_identical(captured$fallback_model, "dropdown-fallback-model")
  expect_true(isTRUE(captured$excel_deep_on))
  expect_identical(captured$excel_deep_level, "low")
})

test_that("MCP reasoning stream düşünmeyen model veya TTS açıkken açılmaz", {
  old_resolve_exists <- exists("resolve_runtime_model_for_request", envir = globalenv(), inherits = FALSE)
  old_resolve <- if (old_resolve_exists) get("resolve_runtime_model_for_request", envir = globalenv()) else NULL

  old_thinking_exists <- exists("is_thinking_model", envir = globalenv(), inherits = FALSE)
  old_thinking <- if (old_thinking_exists) get("is_thinking_model", envir = globalenv()) else NULL

  on.exit({
    if (old_resolve_exists) {
      assign("resolve_runtime_model_for_request", old_resolve, envir = globalenv())
    } else if (exists("resolve_runtime_model_for_request", envir = globalenv(), inherits = FALSE)) {
      rm("resolve_runtime_model_for_request", envir = globalenv())
    }

    if (old_thinking_exists) {
      assign("is_thinking_model", old_thinking, envir = globalenv())
    } else if (exists("is_thinking_model", envir = globalenv(), inherits = FALSE)) {
      rm("is_thinking_model", envir = globalenv())
    }
  }, add = TRUE)

  assign(
    "resolve_runtime_model_for_request",
    function(...) "non-thinking-runtime-model",
    envir = globalenv()
  )

  assign(
    "is_thinking_model",
    function(model_id) FALSE,
    envir = globalenv()
  )

  out <- mergen_prepare_send_message_model_runtime(
    input = list(),
    settings_data = list(
      excel_deep_thinking = TRUE,
      excel_deep_level = "low",
      enable_tts_audio = FALSE
    ),
    current_settings = list(
      model_selection = "dropdown-fallback-model",
      enable_streaming = TRUE
    ),
    tool_family = "mcp_excel",
    req_id = "req_test_002"
  )

  expect_false(isTRUE(out$mcp_reasoning_stream_on))
  expect_false(isTRUE(out$current_settings$enable_mcp_reasoning_stream))

  assign(
    "is_thinking_model",
    function(model_id) TRUE,
    envir = globalenv()
  )

  out_tts <- mergen_prepare_send_message_model_runtime(
    input = list(),
    settings_data = list(
      excel_deep_thinking = TRUE,
      excel_deep_level = "low",
      enable_tts_audio = TRUE
    ),
    current_settings = list(
      model_selection = "dropdown-fallback-model",
      enable_streaming = TRUE
    ),
    tool_family = "mcp_excel",
    req_id = "req_test_003"
  )

  expect_false(isTRUE(out_tts$mcp_reasoning_stream_on))
  expect_false(isTRUE(out_tts$current_settings$enable_mcp_reasoning_stream))
})