# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-quick-actions-streaming-regression.R
# Açıklama: Hızlı işlem ve gerçek SSE akış yarış durumları için ilk E2E benzeri
#           deterministik regresyon dilimi. Gerçek DB/LLM/TTS/STT/image endpoint
#           gerektirmez.
# ==============================================================================

.find_e2e_repo_root <- function() {
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

  stop("E2E test repo kökünü bulamadı. Testi repo kökünden çalıştırın.", call. = FALSE)
}

repo_root_e2e <- .find_e2e_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_e2e, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_e2e <- resolve_repo_root_for_tests()

if (!exists("e2e_regression_config", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_e2e, "tests", "testthat", "helper_e2e_race_harness.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

source(file.path(repo_root_e2e, "R", "utils_common.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_e2e, "R", "helpers_api_model_config.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_e2e, "R", "helpers_quick_action_intro_messages.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_e2e, "R", "helpers_llm_stream_io.R"), encoding = "UTF-8", local = globalenv())
source(file.path(repo_root_e2e, "R", "helpers_send_message_request_lifecycle.R"), encoding = "UTF-8", local = globalenv())

.e2e_quick_read_ascii <- function(...) {
  path <- file.path(repo_root_e2e, ...)
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
  raw_data[raw_data == as.raw(0L)] <- as.raw(0x20)
  raw_data[as.integer(raw_data) > 127L] <- as.raw(0x20)

  txt <- rawToChar(raw_data)
  Encoding(txt) <- "UTF-8"
  txt
}

.e2e_quick_expect_tokens <- function(text, tokens, label) {
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

test_that("quick action config exposes every first-slice journey action", {
  config <- e2e_regression_config()
  actions <- build_main_actions_data_from_config(config)

  ids <- vapply(actions, function(action) action$id %||% "", character(1))

  expect_setequal(
    ids,
    c(
      "project-process",
      "app-expert",
      "resource-analysis",
      "excel-analysis",
      "image-creation",
      "coding-support",
      "summarization"
    )
  )

  excel_cfg <- get_tool_mode_config(
    "excel-analysis",
    by = "quick_action_id",
    config = config
  )

  expect_identical(excel_cfg$setting_flag, "enable_mcp_tools")
  expect_identical(excel_cfg$model_id, "technical name 4")

  excel_action <- actions[[match("excel-analysis", ids)]]
  expect_identical(excel_action$model_value, "technical name 4")
})

test_that("quick action click selects tool/model, hides welcome, avoids LLM and persistence", {
  state <- e2e_new_quick_action_state()
  state <- e2e_apply_quick_action(state, "excel-analysis", user_name = "Ayşe")

  expect_false(state$values$show_welcome)
  expect_identical(e2e_active_flags(state), "enable_mcp_tools")
  expect_identical(state$settings$model_selection, "technical name 4")
  expect_identical(state$llm_calls, 0L)

  expect_length(state$values$messages, 1L)

  msg <- state$values$messages[[1]]
  expect_identical(msg$type, "ai")
  expect_true(grepl("Excel Analizi", msg$content, fixed = TRUE))
  expect_true(grepl("Ayşe", msg$content, fixed = TRUE))
  expect_false(msg$persist_to_db)
  expect_false(msg$add_to_saved_chats)
  expect_false(msg$include_in_context)
})

test_that("rapid quick action clicks converge to one active mode without sending prompt", {
  state <- e2e_new_quick_action_state()

  state <- e2e_apply_quick_action(state, "coding-support", user_name = "İdil")
  state <- e2e_apply_quick_action(state, "resource-analysis", user_name = "İdil")
  state <- e2e_apply_quick_action(state, "resource-analysis", user_name = "İdil")

  expect_identical(e2e_active_flags(state), "enable_rdata_tools")
  expect_identical(state$settings$model_selection, "technical name 3")
  expect_identical(state$llm_calls, 0L)

  intro_messages_are_safe <- vapply(
    state$values$messages,
    function(msg) {
      identical(msg$type, "ai") &&
        isFALSE(msg$persist_to_db) &&
        isFALSE(msg$add_to_saved_chats) &&
        isFALSE(msg$include_in_context)
    },
    logical(1)
  )

  expect_true(all(intro_messages_are_safe))
  expect_lte(length(state$values$messages), 3L)
})

test_that("quick action client gate suppresses same rapid double click before Shiny event", {
  guard <- e2e_new_quick_action_client_guard(debounce_ms = 600L)

  guard <- e2e_record_quick_action_client_click(
    guard,
    action_id = "resource-analysis",
    model = "technical name 3",
    timestamp_ms = 1000
  )

  guard <- e2e_record_quick_action_client_click(
    guard,
    action_id = "resource-analysis",
    model = "technical name 3",
    timestamp_ms = 1200
  )

  guard <- e2e_record_quick_action_client_click(
    guard,
    action_id = "excel-analysis",
    model = "technical name 4",
    timestamp_ms = 1300
  )

  guard <- e2e_record_quick_action_client_click(
    guard,
    action_id = "resource-analysis",
    model = "technical name 3",
    timestamp_ms = 1801
  )

  expect_identical(guard$suppressed, 1L)
  expect_equal(length(guard$forwarded), 3L)

  forwarded_ids <- vapply(guard$forwarded, `[[`, character(1), "action_id")
  expect_identical(
    forwarded_ids,
    c("resource-analysis", "excel-analysis", "resource-analysis")
  )

  state <- e2e_new_quick_action_state()
  for (event in guard$forwarded) {
    state <- e2e_apply_quick_action(
      state,
      action_id = event$action_id,
      user_name = "İdil"
    )
  }

  expect_identical(state$llm_calls, 0L)
  expect_identical(e2e_active_flags(state), "enable_rdata_tools")
  expect_identical(state$settings$model_selection, "technical name 3")
  expect_equal(length(state$values$messages), 3L)

  intro_messages_are_safe <- vapply(
    state$values$messages,
    function(msg) {
      identical(msg$type, "ai") &&
        isFALSE(msg$persist_to_db) &&
        isFALSE(msg$add_to_saved_chats) &&
        isFALSE(msg$include_in_context)
    },
    logical(1)
  )

  expect_true(all(intro_messages_are_safe))
})

test_that("quick action browser handler keeps duplicate-click debounce before Shiny event", {
  js <- .e2e_quick_read_ascii("www", "js", "shiny_message_handlers.js")

  .e2e_quick_expect_tokens(
    js,
    c(
      "QUICK_ACTION_DEBOUNCE_MS",
      "lastQuickActionSignature",
      "lastQuickActionAt",
      "resetQuickActionButton",
      "var signature = actionId + '|' + model",
      "lastQuickActionSignature === signature",
      "now - lastQuickActionAt",
      "btn.disabled = true",
      "btn.setAttribute('aria-disabled', 'true')",
      "window.setTimeout(function()",
      "resetQuickActionButton(btn)",
      "Shiny.setInputValue('quick_template'"
    ),
    "shiny_message_handlers.js hizli islem debounce sozlesmesi eksik:"
  )

  guard_pos <- regexpr(
    "lastQuickActionSignature === signature",
    js,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  send_pos <- regexpr(
    "Shiny.setInputValue('quick_template'",
    js,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  expect_true(guard_pos > 0L)
  expect_true(send_pos > 0L)
  expect_true(
    guard_pos < send_pos,
    info = "Ayni hizli islem debounce kontrolu Shiny olayindan once yapilmalidir."
  )
})

test_that("quick action followed immediately by prompt sends exactly one user request", {
  state <- e2e_new_quick_action_state()

  state <- e2e_apply_quick_action(state, "summarization", user_name = "İpek")
  state <- e2e_send_prompt_after_quick_action(
    state,
    "Yüklediğim PDF için kısa özet çıkar."
  )

  expect_identical(state$llm_calls, 1L)
  expect_identical(e2e_active_flags(state), "enable_summarization_tools")
  expect_identical(state$settings$model_selection, "technical name 2")

  message_types <- vapply(state$values$messages, `[[`, character(1), "type")
  expect_identical(sum(message_types == "user"), 1L)

  context_flags <- vapply(
    state$values$messages,
    function(msg) isTRUE(msg$include_in_context),
    logical(1)
  )

  expect_identical(sum(context_flags), 1L)
  expect_true(any(grepl(
    "İpek",
    vapply(state$values$messages, `[[`, character(1), "content"),
    fixed = TRUE
  )))
})

test_that("stream file deltas keep visible answer and reasoning trace separate", {
  stream_path <- tempfile("e2e_stream_", fileext = ".jsonl")
  on.exit(try(unlink(stream_path, force = TRUE), silent = TRUE), add = TRUE)

  append_stream_delta_line(stream_path, "Merhaba ")
  append_stream_reasoning_line(stream_path, "Gizli plan: önce bağlam.\n")
  append_stream_delta_line(stream_path, "İğdır sonucu")

  collected <- e2e_collect_stream_payloads(stream_path)

  expect_identical(collected$visible, "Merhaba İğdır sonucu")
  expect_identical(collected$reasoning, "Gizli plan: önce bağlam.\n")
  expect_false(grepl("Gizli plan", collected$visible, fixed = TRUE))

  payload_types <- vapply(collected$payloads, `[[`, character(1), "type")
  expect_identical(payload_types, c("delta", "reasoning_delta", "delta"))
})

test_that("stream finalization is request-scoped and idempotent", {
  current_id <- "req_1"
  stop_flag <- FALSE

  active_request_id <- function(value) {
    if (missing(value)) {
      current_id
    } else {
      current_id <<- value
    }
  }

  stop_generation <- function(value) {
    if (missing(value)) {
      stop_flag
    } else {
      stop_flag <<- value
    }
  }

  stream <- e2e_new_stream_state("req_1")

  stream <- e2e_apply_stream_result_once(
    stream_state = stream,
    active_request_id = active_request_id,
    req_id = "req_1",
    content = "İlk final",
    reasoning = "Ayrı düşünce",
    stop_generation = stop_generation
  )

  stream <- e2e_apply_stream_result_once(
    stream_state = stream,
    active_request_id = active_request_id,
    req_id = "req_1",
    content = "İkinci final",
    reasoning = "İkinci düşünce",
    stop_generation = stop_generation
  )

  expect_identical(stream$finalize_count, 1L)
  expect_identical(stream$visible, "İlk final")
  expect_identical(stream$reasoning, "Ayrı düşünce")
  expect_identical(stream$saved_chat_updates, 1L)
  expect_identical(stream$last_skip_reason, "already_finalized")

  active_request_id("req_2")

  stale_stream <- e2e_new_stream_state("req_1")
  stale_stream <- e2e_apply_stream_result_once(
    stream_state = stale_stream,
    active_request_id = active_request_id,
    req_id = "req_1",
    content = "Eski final",
    reasoning = NULL,
    stop_generation = stop_generation
  )

  expect_identical(stale_stream$finalize_count, 0L)
  expect_identical(stale_stream$last_skip_reason, "stale")
})

test_that("stop generation flag is reset for next request and cannot poison it", {
  current_id <- "req_old"
  stop_flag <- FALSE

  active_request_id <- function(value) {
    if (missing(value)) {
      current_id
    } else {
      current_id <<- value
    }
  }

  stop_generation <- function(value) {
    if (missing(value)) {
      stop_flag
    } else {
      stop_flag <<- value
    }
  }

  expect_identical(
    mergen_send_message_request_state(active_request_id, "req_old", stop_generation),
    "current"
  )

  stop_generation(TRUE)

  expect_identical(
    mergen_send_message_request_state(active_request_id, "req_old", stop_generation),
    "stopped"
  )

  active_request_id("req_new")
  stop_generation(FALSE)

  expect_identical(
    mergen_send_message_request_state(active_request_id, "req_new", stop_generation),
    "current"
  )

  expect_identical(
    mergen_send_message_request_state(active_request_id, "req_old", stop_generation),
    "stale"
  )
})

test_that("simulated reasoning phases are never persisted as real reasoning", {
  expect_null(
    e2e_persisted_reasoning_or_null(
      "→ Soru çözümleniyor…\n→ Bağlam toplanıyor…",
      simulated = TRUE
    )
  )

  expect_identical(
    e2e_persisted_reasoning_or_null("Gerçek reasoning", simulated = FALSE),
    "Gerçek reasoning"
  )

  expect_null(e2e_persisted_reasoning_or_null("", simulated = FALSE))
})