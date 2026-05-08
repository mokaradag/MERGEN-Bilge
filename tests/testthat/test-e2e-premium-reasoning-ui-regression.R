# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-premium-reasoning-ui-regression.R
# Açıklama: Premium reasoning / thinking UI için deterministik E2E benzeri
#           yarış durumu regresyon testleri. Gerçek tarayıcı, LLM, SSE, DB veya
#           public internet gerektirmez.
# ==============================================================================

.find_e2e_reasoning_repo_root <- function() {
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

  stop("Reasoning E2E test repo kökünü bulamadı. Testi repo kökünden çalıştırın.", call. = FALSE)
}

repo_root_reasoning_e2e <- .find_e2e_reasoning_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_reasoning_e2e, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_reasoning_e2e <- resolve_repo_root_for_tests()

if (!exists("e2e_reasoning_new_state", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(
      repo_root_reasoning_e2e,
      "tests",
      "testthat",
      "helper_e2e_reasoning_ui_harness.R"
    ),
    encoding = "UTF-8",
    local = globalenv()
  )
}

.e2e_reasoning_read_ascii_contract <- function(...) {
  path <- file.path(repo_root_reasoning_e2e, ...)
  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  # JS/R dosyalarındaki Türkçe yorumlar Windows VM'de native encoding kaynaklı
  # uyarı üretmesin diye bu test yalnızca ASCII sözleşme token'larını arar.
  raw_data[raw_data == as.raw(0L)] <- as.raw(0x20)
  raw_data[as.integer(raw_data) > 127L] <- as.raw(0x20)

  txt <- rawToChar(raw_data)
  Encoding(txt) <- "UTF-8"
  txt
}

.e2e_reasoning_expect_tokens <- function(text, tokens, label) {
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

test_that("premium reasoning lifecycle is request-scoped and idempotent", {
  state <- e2e_reasoning_new_state()

  state <- e2e_reasoning_start(
    state,
    req_id = "req_1",
    model = list(label = "Gemma 4 31B")
  )

  state <- e2e_reasoning_start(
    state,
    req_id = "req_1",
    model = list(label = "Gemma 4 31B")
  )

  expect_identical(e2e_reasoning_count_live_panels(state), 1L)
  expect_identical(state$model_label, "Gemma 4 31B")
  expect_identical(state$status, "preparing")

  state <- e2e_reasoning_delta(
    state,
    req_id = "req_1",
    delta = "Plan: önce bağlamı ayır.\n"
  )

  expect_identical(state$status, "live")
  expect_identical(state$reasoning_buffer, "Plan: önce bağlamı ayır.\n")
  expect_identical(e2e_reasoning_count_live_panels(state), 1L)

  state <- e2e_reasoning_stream_start(
    state,
    req_id = "req_1",
    msg_id = "msg_1"
  )

  expect_identical(state$status, "streaming")
  expect_identical(e2e_reasoning_count_live_panels(state), 1L)
  expect_identical(state$live_panels[[1]]$kind, "bubble")
  expect_identical(state$live_panels[[1]]$msg_id, "msg_1")

  state <- e2e_reasoning_reset(
    state,
    req_id = "req_1",
    outcome = "completed"
  )

  state <- e2e_reasoning_reset(
    state,
    req_id = "req_1",
    outcome = "completed"
  )

  expect_identical(state$status, "idle")
  expect_identical(e2e_reasoning_count_live_panels(state), 0L)
  expect_identical(e2e_reasoning_count_archived_panels(state), 1L)
  expect_identical(state$persisted_reasoning, "Plan: önce bağlamı ayır.\n")
  expect_true(any(grepl("already_finalized:req_1", state$events, fixed = TRUE)))
})

test_that("stale reasoning callbacks cannot contaminate the active request", {
  state <- e2e_reasoning_new_state()

  state <- e2e_reasoning_start(state, req_id = "req_old", model = "Eski Model")
  state <- e2e_reasoning_delta(state, req_id = "req_old", delta = "Eski düşünce\n")

  state <- e2e_reasoning_start(state, req_id = "req_new", model = "Yeni Model")
  state <- e2e_reasoning_delta(state, req_id = "req_old", delta = "Sızmaması gereken metin\n")
  state <- e2e_reasoning_stream_start(state, req_id = "req_old", msg_id = "msg_old")

  state <- e2e_reasoning_delta(state, req_id = "req_new", delta = "Yeni düşünce\n")
  state <- e2e_reasoning_visible_delta(state, req_id = "req_new", delta = "Görünür yanıt")

  expect_identical(state$active_req_id, "req_new")
  expect_identical(state$reasoning_buffer, "Yeni düşünce\n")
  expect_identical(state$visible_answer, "Görünür yanıt")
  expect_false(grepl("Eski düşünce", state$reasoning_buffer, fixed = TRUE))
  expect_false(grepl("Sızmaması gereken", state$reasoning_buffer, fixed = TRUE))

  expect_true(any(grepl("reasoning_delta_ignored:stale:req_old", state$events, fixed = TRUE)))
  expect_true(any(grepl("stream_start_ignored:stale:req_old", state$events, fixed = TRUE)))
})

test_that("simulated reasoning is removed on stream start and is never persisted", {
  state <- e2e_reasoning_new_state()

  state <- e2e_reasoning_start(
    state,
    req_id = "req_sim",
    model = "Non-thinking Model",
    simulated = TRUE
  )

  expect_true(state$simulated)
  expect_identical(e2e_reasoning_count_live_panels(state), 1L)
  expect_true(grepl(
    "simulated_phase:question_analysis",
    state$reasoning_buffer,
    fixed = TRUE
  ))
  expect_null(state$persisted_reasoning)

  state <- e2e_reasoning_stream_start(
    state,
    req_id = "req_sim",
    msg_id = "msg_sim"
  )

  expect_identical(state$status, "idle")
  expect_identical(e2e_reasoning_count_live_panels(state), 0L)
  expect_identical(e2e_reasoning_count_archived_panels(state), 0L)
  expect_identical(state$reasoning_buffer, "")
  expect_null(state$persisted_reasoning)
  expect_true(any(grepl("simulated_reasoning_removed_on_stream_start", state$events, fixed = TRUE)))
})

test_that("visible answer content and reasoning trace stay separate through finalization", {
  state <- e2e_reasoning_new_state()

  state <- e2e_reasoning_start(state, req_id = "req_sep", model = "Thinking Model")
  state <- e2e_reasoning_delta(state, req_id = "req_sep", delta = "Gizli düşünce akışı\n")
  state <- e2e_reasoning_stream_start(state, req_id = "req_sep", msg_id = "msg_sep")
  state <- e2e_reasoning_visible_delta(state, req_id = "req_sep", delta = "Merhaba ")
  state <- e2e_reasoning_visible_delta(state, req_id = "req_sep", delta = "sonuç")
  state <- e2e_reasoning_reset(state, req_id = "req_sep", outcome = "completed")

  expect_identical(state$visible_answer, "Merhaba sonuç")
  expect_identical(state$persisted_reasoning, "Gizli düşünce akışı\n")
  expect_false(grepl("Gizli düşünce", state$visible_answer, fixed = TRUE))
  expect_identical(state$archived_panels[[1]]$content, "Gizli düşünce akışı\n")
  expect_identical(state$archived_panels[[1]]$data_state, "completed")
})

test_that("premium reasoning JS and true streaming server contracts remain wired", {
  reasoning_js <- .e2e_reasoning_read_ascii_contract("www", "js", "premium_reasoning.js")
  streaming_js <- .e2e_reasoning_read_ascii_contract("www", "js", "streaming_manager.js")
  true_streaming_r <- .e2e_reasoning_read_ascii_contract("R", "server_handler_true_streaming.R")

  .e2e_reasoning_expect_tokens(
    reasoning_js,
    c(
      "window.PremiumReasoning",
      "start: start",
      "onStreamStart: onStreamStart",
      "onResetChatState: onResetChatState",
      "onReasoningDelta: onReasoningDelta",
      "simulatedMode",
      "cleanup(true)",
      "migrateToBubble",
      "fadeOutAndRemove(shellPanel)",
      "Shiny.addCustomMessageHandler(\"streamingReasoningDelta\""
    ),
    "premium_reasoning.js sozlesmesi eksik:"
  )

  .e2e_reasoning_expect_tokens(
    streaming_js,
    c(
      "messageDiv.__streamingState",
      "streamingDelta",
      "finalizeStreamingMessage",
      "state.accumulatedText += delta",
      "messageDiv.innerHTML = data.html"
    ),
    "streaming_manager.js sozlesmesi eksik:"
  )

  .e2e_reasoning_expect_tokens(
    true_streaming_r,
    c(
      "stream_env$accumulated_reasoning",
      "stream_env$finalized",
      "premiumReasoningStreamStart",
      "streamingReasoningDelta",
      "finalizeStreamingMessage",
      "reasoning_content",
      "reasoning_trace_value"
    ),
    "server_handler_true_streaming.R reasoning/streaming sozlesmesi eksik:"
  )
})