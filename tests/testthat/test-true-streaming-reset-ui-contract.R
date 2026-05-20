# ==============================================================================
# Dosya Yolu: tests/testthat/test-true-streaming-reset-ui-contract.R
# Açıklama: True streaming stop/finalize akışının sunucu ve istemci tarafı
#           reset/finalize sözleşmesini statik ama odaklı şekilde korur.
#           Uygulamayı, DB'yi, LLM'i veya tarayıcıyı başlatmaz.
# ==============================================================================

.true_stream_contract_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("True streaming contract repo kökü bulunamadı.", call. = FALSE)
}

.true_stream_read_text <- function(...) {
  path <- file.path(.true_stream_contract_repo_root(), ...)
  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) return("")

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

.true_stream_expect_all <- function(text, tokens, label) {
  missing <- tokens[!vapply(
    tokens,
    function(token) grepl(token, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing,
    character(0),
    info = paste(label, paste(missing, collapse = ", "))
  )
}

testthat::test_that("true streaming server cleanup keeps UI reset contract", {
  server_text <- .true_stream_read_text("R", "server_handler_true_streaming.R")

  .true_stream_expect_all(
    server_text,
    c(
      "active_request_id(req_id)",
      "values$is_sending <- TRUE",
      "stop_generation(FALSE)",
      "stream_env$stop_file",
      "file.create(stream_env$stop_file)",
      "cleanup_streaming_state()",
      "ctx$reset_chat_state_fn()",
      "finalize_stream_message <- function",
      "finalize_error_or_abort <- function",
      "mergen_stream_abort_cleanup_plan",
      "remove_placeholder_message()",
      "session$sendCustomMessage(\"finalizeStreamingMessage\"",
      "enableActions = TRUE",
      "requestId = stream_env$req_id"
    ),
    "True streaming server reset/finalize sözleşmesi eksik:"
  )

  finalize_pos <- regexpr(
    "finalize_stream_message <- function",
    server_text,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  reset_pos <- regexpr(
    "ctx$reset_chat_state_fn()",
    server_text,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  testthat::expect_true(finalize_pos > 0L)
  testthat::expect_true(reset_pos > finalize_pos)
})

testthat::test_that("streaming JS finalizer restores sending UI affordances", {
  js_text <- .true_stream_read_text("www", "js", "streaming_manager.js")

  .true_stream_expect_all(
    js_text,
    c(
      "window.MergenStreamingSmoke",
      "handleInitStreamingMessage",
      "handleStreamingDelta",
      "handleFinalizeStreamingMessage",
      "isStaleStreamingPayload",
      "state.finalized = true",
      "messageDiv.dataset.streaming = \"false\"",
      "actionButtons.forEach",
      "btn.classList.remove('streaming-hidden')",
      "btn.style.display = 'inline-flex'",
      "btn.disabled = false",
      "followupBox.classList.remove('pending')"
    ),
    "Streaming JS finalize/reset sözleşmesi eksik:"
  )

  stale_check_pos <- regexpr(
    "if (state.finalized || isStaleStreamingPayload(state, data)) return;",
    js_text,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  delta_append_pos <- regexpr(
    "state.accumulatedText += delta;",
    js_text,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  testthat::expect_true(stale_check_pos > 0L)
  testthat::expect_true(delta_append_pos > stale_check_pos)
})