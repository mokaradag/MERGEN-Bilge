# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-request-lifecycle-contract.R
# Açıklama: send_message request lifecycle helper sözleşmelerini doğrular.
# ==============================================================================

repo_root_send_message_lifecycle <- resolve_repo_root_for_tests()
source(file.path(repo_root_send_message_lifecycle, "R/utils_common.R"), encoding = "UTF-8", local = globalenv())
source(
  file.path(repo_root_send_message_lifecycle, "R/helpers_send_message_request_lifecycle.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_send_message_lifecycle, "R/helpers_send_message_core.R"),
  encoding = "UTF-8",
  local = globalenv()
)

test_that("send message request state current, stopped ve stale ayrımını korur", {
  current_id <- "req_current"
  active_request_id <- function(value) {
    if (missing(value)) current_id else current_id <<- value
  }

  expect_identical(
    mergen_send_message_request_state(active_request_id, "req_current", function() FALSE),
    "current"
  )

  expect_identical(
    mergen_send_message_request_state(active_request_id, "req_current", function() TRUE),
    "stopped"
  )

  expect_identical(
    mergen_send_message_request_state(active_request_id, "req_old", function() FALSE),
    "stale"
  )

  expect_false(mergen_is_current_request(active_request_id, "req_old", function() FALSE))
})

test_that("typing wrapper cleanup stale istekte yeni wrapper'ı kaldırmaz", {
  current_id <- "req_new"
  removed_selectors <- character(0)

  active_request_id <- function(value) {
    if (missing(value)) {
      current_id
    } else {
      current_id <<- value
    }
  }

  remove_ui_fn <- function(selector, immediate = FALSE) {
    removed_selectors <<- c(removed_selectors, selector)
    invisible(TRUE)
  }

  expect_false(mergen_remove_typing_wrapper_if_safe(
    active_request_id = active_request_id,
    req_id = "req_old",
    remove_ui_fn = remove_ui_fn
  ))

  expect_identical(removed_selectors, character(0))

  expect_true(mergen_remove_typing_wrapper_if_safe(
    active_request_id = active_request_id,
    req_id = "req_new",
    remove_ui_fn = remove_ui_fn
  ))

  expect_identical(removed_selectors, "#typing-animation-wrapper")
})

test_that("stale cleanup yeni request wrapper'ını kaldırmadan state temizler", {
  values <- new.env(parent = emptyenv())
  values$typing <- TRUE

  reset_count <- 0L
  remove_count <- 0L

  active_request_id <- function() "req_newer"

  reset_chat_state_fn <- function() {
    reset_count <<- reset_count + 1L
    invisible(TRUE)
  }

  remove_ui_fn <- function(selector, immediate = FALSE) {
    remove_count <<- remove_count + 1L
    invisible(TRUE)
  }

  mergen_cleanup_send_message(
    values = values,
    reset_chat_state_fn = reset_chat_state_fn,
    remove_typing_wrapper = TRUE,
    active_request_id = active_request_id,
    req_id = "req_old",
    remove_ui_fn = remove_ui_fn
  )

  expect_false(values$typing)
  expect_identical(reset_count, 1L)
  expect_identical(remove_count, 0L)
})

test_that("active_request_id hata verdiğinde typing wrapper güvenli şekilde korunur", {
  removed_selectors <- character(0)

  remove_ui_fn <- function(selector, immediate = FALSE) {
    removed_selectors <<- c(removed_selectors, selector)
    invisible(TRUE)
  }

  expect_false(mergen_remove_typing_wrapper_if_safe(
    active_request_id = function() stop("aktif istek okunamadı", call. = FALSE),
    req_id = "req_active",
    remove_ui_fn = remove_ui_fn
  ))

  expect_identical(removed_selectors, character(0))
})

test_that("aktif isteğin cleanup akışı typing durumunu temizler ve wrapper'ı kaldırır", {
  values <- new.env(parent = emptyenv())
  values$typing <- TRUE

  reset_count <- 0L
  remove_count <- 0L

  active_request_id <- function() "req_active"

  reset_chat_state_fn <- function() {
    reset_count <<- reset_count + 1L
    invisible(TRUE)
  }

  remove_ui_fn <- function(selector, immediate = FALSE) {
    expect_identical(selector, "#typing-animation-wrapper")
    remove_count <<- remove_count + 1L
    invisible(TRUE)
  }

  mergen_cleanup_send_message(
    values = values,
    reset_chat_state_fn = reset_chat_state_fn,
    remove_typing_wrapper = TRUE,
    active_request_id = active_request_id,
    req_id = "req_active",
    remove_ui_fn = remove_ui_fn
  )

  expect_false(values$typing)
  expect_identical(reset_count, 1L)
  expect_identical(remove_count, 1L)
})

test_that("deferred stream persist sadece aktif ve finalize edilmemiş istek için çalışır", {
  current_id <- "req_live"
  active_request_id <- function(value) {
    if (missing(value)) current_id else current_id <<- value
  }

  stream_env <- new.env(parent = emptyenv())
  stream_env$finalized <- FALSE

  expect_true(mergen_should_run_deferred_stream_persist(active_request_id, "req_live", stream_env))

  current_id <- "req_newer"
  expect_false(mergen_should_run_deferred_stream_persist(active_request_id, "req_live", stream_env))

  current_id <- "req_live"
  stream_env$finalized <- TRUE
  expect_false(mergen_should_run_deferred_stream_persist(active_request_id, "req_live", stream_env))
})

test_that("prompt snapshot list ve string girdilerde dosya sayısını sabitler", {
  files <- list(
    "rapor.xlsx" = list(path = "rapor.xlsx"),
    "özet.pdf" = list(path = "özet.pdf")
  )

  snapshot <- mergen_build_send_message_prompt_snapshot(
    list(text = "  Merhaba dünya  "),
    session_files = function() files
  )

  expect_identical(snapshot$user_message_text, "Merhaba dünya")
  expect_identical(snapshot$uploaded_names, c("rapor.xlsx", "özet.pdf"))
  expect_identical(snapshot$uploaded_count, 2L)
  expect_identical(snapshot$current_session_files, files)
})

test_that("chat creation defer kararı yalnızca güvenli true-streaming sohbet yolunda aktiftir", {
  current_settings <- list(enable_streaming = TRUE)
  settings_data <- list(enable_tts_audio = FALSE)

  expect_true(mergen_should_defer_chat_creation("none", 0L, current_settings, settings_data))
  expect_true(mergen_should_defer_chat_creation("coding", 0L, current_settings, settings_data))
  expect_false(mergen_should_defer_chat_creation("mcp_excel", 0L, current_settings, settings_data))
  expect_false(mergen_should_defer_chat_creation("none", 1L, current_settings, settings_data))
  expect_false(mergen_should_defer_chat_creation("none", 0L, list(enable_streaming = FALSE), settings_data))
  expect_false(mergen_should_defer_chat_creation("none", 0L, current_settings, list(enable_tts_audio = TRUE)))
})

test_that("thinking panel plan gerçek streaming dışındaki yollarda simulated kalır", {
  old_resolve_exists <- exists("resolve_tool_model_for_family", envir = globalenv(), inherits = FALSE)
  old_thinking_exists <- exists("is_thinking_model", envir = globalenv(), inherits = FALSE)
  old_resolve <- if (old_resolve_exists) get("resolve_tool_model_for_family", envir = globalenv()) else NULL
  old_thinking <- if (old_thinking_exists) get("is_thinking_model", envir = globalenv()) else NULL

  on.exit({
    if (old_resolve_exists) {
      assign("resolve_tool_model_for_family", old_resolve, envir = globalenv())
    } else {
      rm("resolve_tool_model_for_family", envir = globalenv())
    }

    if (old_thinking_exists) {
      assign("is_thinking_model", old_thinking, envir = globalenv())
    } else {
      rm("is_thinking_model", envir = globalenv())
    }
  }, add = TRUE)

  assign("resolve_tool_model_for_family", function(tool_family, fallback_model) "qwen-reason", envir = globalenv())
  assign("is_thinking_model", function(model_id) identical(model_id, "qwen-reason"), envir = globalenv())

  streaming_plan <- mergen_build_thinking_panel_plan(
    tool_family = "none",
    settings_data = list(
      model_selection = "fallback",
      enable_streaming = TRUE,
      enable_tts_audio = FALSE,
      enable_typing_indicator = FALSE
    )
  )

  expect_true(streaming_plan$show_thinking_wrapper)
  expect_false(streaming_plan$panel_simulated)

  tts_plan <- mergen_build_thinking_panel_plan(
    tool_family = "none",
    settings_data = list(
      model_selection = "fallback",
      enable_streaming = TRUE,
      enable_tts_audio = TRUE,
      enable_typing_indicator = FALSE
    )
  )

  expect_true(tts_plan$show_thinking_wrapper)
  expect_true(tts_plan$panel_simulated)
})