# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-streaming-client-request-id-regression.R
# Açıklama: True SSE ve premium reasoning istemci mesajlarında request-id
#           sözleşmesini statik ve deterministik olarak doğrular.
# ==============================================================================

.find_e2e_client_request_repo_root <- function() {
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
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Client request-id E2E test repo kokunu bulamadi.", call. = FALSE)
}

repo_root_client_request_e2e <- .find_e2e_client_request_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_client_request_e2e, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_client_request_e2e <- resolve_repo_root_for_tests()

.e2e_client_request_read_ascii <- function(...) {
  path <- file.path(repo_root_client_request_e2e, ...)
  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadi: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  # Windows VM native encoding farklari bu testte yalnizca ASCII token
  # sozlesmesi arandigi icin temizlenir.
  raw_data[raw_data == as.raw(0L)] <- as.raw(0x20)
  raw_data[as.integer(raw_data) > 127L] <- as.raw(0x20)

  txt <- rawToChar(raw_data)
  Encoding(txt) <- "UTF-8"
  txt
}

.e2e_client_request_expect_tokens <- function(text, tokens, label) {
  found <- vapply(
    tokens,
    function(token) {
      isTRUE(grepl(token, text, fixed = TRUE, useBytes = TRUE))
    },
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(label, paste(tokens[!found], collapse = ", "))
  )
}

test_that("server true streaming custom messages carry requestId to the browser", {
  true_streaming_r <- .e2e_client_request_read_ascii(
    "R",
    "server_handler_true_streaming.R"
  )

  .e2e_client_request_expect_tokens(
    true_streaming_r,
    c(
      "req_id <- ctx$request_id %||% mergen_new_send_message_request_id()",
      "premiumReasoningStreamStart",
      "initStreamingMessage",
      "streamingReasoningDelta",
      "streamingDelta",
      "streamingUpdate",
      "finalizeStreamingMessage",
      "requestId = stream_env$req_id"
    ),
    "server_handler_true_streaming.R request-id sozlesmesi eksik:"
  )
})

test_that("send-message setup reuses one request id for reasoning shell and true stream", {
  send_message_r <- .e2e_client_request_read_ascii("R", "server_send_message.R")
  lifecycle_r <- .e2e_client_request_read_ascii(
    "R",
    "helpers_send_message_thinking_panel.R"
  )

  .e2e_client_request_expect_tokens(
    send_message_r,
    c(
      "req_id <- mergen_new_send_message_request_id()",
      "mergen_show_send_message_thinking_wrapper(",
      "request_id = req_id",
      "handle_true_streaming_mode(true_stream_ctx)",
      "active_request_id(req_id)"
    ),
    "server_send_message.R request-id sozlesmesi eksik:"
  )

  .e2e_client_request_expect_tokens(
    lifecycle_r,
    c(
      "request_id = NULL",
      "premiumReasoningStart",
      "requestId = request_id"
    ),
    "helpers_send_message_thinking_panel.R reasoning request-id sozlesmesi eksik:"
  )
})

test_that("streaming_manager ignores stale payloads and finalizes once per request", {
  streaming_js <- .e2e_client_request_read_ascii("www", "js", "streaming_manager.js")

  .e2e_client_request_expect_tokens(
    streaming_js,
    c(
      "requestId: ''",
      "finalized: false",
      "normalizeRequestId",
      "isStaleStreamingPayload",
      "state.requestId = normalizeRequestId(data.requestId)",
      "state.finalized = false",
      "if (state.finalized || isStaleStreamingPayload(state, data)) return;",
      "if (isStaleStreamingPayload(state, data) || state.finalized) return;",
      "state.finalized = true"
    ),
    "streaming_manager.js stale request/finalize sozlesmesi eksik:"
  )
})

test_that("premium reasoning client ignores stale request callbacks", {
  reasoning_js <- .e2e_client_request_read_ascii("www", "js", "premium_reasoning.js")

  .e2e_client_request_expect_tokens(
    reasoning_js,
    c(
      "var requestId = null;",
      "sanitizeRequestId",
      "payloadMatchesActiveRequest",
      "requestId = sanitizeRequestId(config && config.requestId)",
      "if (!payload || !payloadMatchesActiveRequest(payload)) return;",
      "if (!payloadMatchesActiveRequest(payload)) return;",
      "requestId = null;"
    ),
    "premium_reasoning.js request-id stale callback sozlesmesi eksik:"
  )
})