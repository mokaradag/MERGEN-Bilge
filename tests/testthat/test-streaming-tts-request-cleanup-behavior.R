test_that("TTS sohbet değişimi ve senkron gönderim hatasında yalnız kendi durumunu bırakır", {
  for (change in c("chat", "dispatch", "newer")) {
    env <- new.env(parent = globalenv())
    source(file.path(resolve_repo_root_for_tests(), "R", "server_handler_streaming_tts.R"),
           encoding = "UTF-8", local = env)
    env$log_debug <- env$log_warn <- env$log_ai_usage <- function(...) NULL
    env$mergen_log_llm_request_debug <- function(...) NULL
    shiny::testServer(function(input, output, session) NULL, {
      session$userData$user_id <- 7L
      active <- shiny::reactiveVal("A")
      stopped <- shiny::reactiveVal(FALSE)
      values <- shiny::reactiveValues(current_chat_id = "chat_A", is_sending = TRUE)
      resolve_worker <- NULL
      resets <- 0L
      cleanup <- function(...) {
        expect_null(shiny::isolate(active()))
        resets <<- resets + 1L
        values$is_sending <- FALSE
      }
      ctx <- list(session = session, values = values, active_request_id = active,
        stop_generation = stopped, request_id = "A", settings_data = list(),
        current_settings = list(), model_selected = "m", messages_to_process = list(),
        user_prompt_msg = list(db_id = 1L), current_user_id = 7L, chat_id_val = "chat_A",
        cleanup_send_message = cleanup, abort_send_message = function(...) cleanup(),
        perf_tracker = list(track_error = function(...) NULL),
        ai_processor = list(call_llm_streaming = function(...) {
          if (change == "dispatch") stop("gönderim hatası")
          promises::promise(function(resolve, reject) resolve_worker <<- resolve)
        }))
      env$handle_streaming_tts_mode(ctx)
      if (change != "dispatch") {
        values$current_chat_id <- "chat_B"
        if (change == "newer") { active("B"); session$userData$llm_request_owner <- "B" }
        resolve_worker(list(success = TRUE, content = "eski yanıt", duration = 1))
      }
      for (i in 1:50) later::run_now(0)
      if (change == "newer") {
        expect_identical(shiny::isolate(active()), "B")
        expect_true(shiny::isolate(values$is_sending))
        expect_identical(resets, 0L)
      } else {
        expect_null(shiny::isolate(active()))
        expect_false(shiny::isolate(values$is_sending))
        expect_gte(resets, 1L)
      }
      expect_length(ls(session$userData$kimlik_kancalari), 0L)
    })
  }
})

test_that("bekleyen TTS sırasında Stop ve sohbet değişimi istek sahipliğini bırakır", {
  for (change in c("stop", "chat", "newer")) {
    env <- new.env(parent = globalenv())
    source(file.path(resolve_repo_root_for_tests(), "R/helpers_async_result_guard.R"), local = env)
    shiny::testServer(function(input, output, session) NULL, {
      session$userData$user_id <- 7L
      session$userData$llm_request_owner <- "A"
      active <- shiny::reactiveVal("A")
      stopped <- shiny::reactiveVal(FALSE)
      values <- shiny::reactiveValues(current_chat_id = "chat_A", is_sending = TRUE)
      releases <- 0L
      env$mergen_send_message_release_values_token <- function(...) releases <<- releases + 1L
      remove <- env$mergen_bind_request_owner_cleanup(session, active, "A",
        function() values$is_sending <- FALSE, values, stopped)
      pending_current <- session$userData$llm_worker_guard
      expect_true(pending_current())
      if (change == "stop") { stopped(TRUE); active("cancelled_A") }
      if (change == "chat") values$current_chat_id <- "chat_B"
      if (change == "newer") { active("B"); session$userData$llm_request_owner <- "B" }
      session$flushReact()
      expect_false(pending_current())
      if (change == "newer") {
        expect_identical(shiny::isolate(active()), "B")
        expect_identical(releases, 0L)
      } else {
        expect_null(shiny::isolate(active()))
        expect_false(shiny::isolate(values$is_sending))
        expect_identical(releases, 1L)
      }
      expect_length(ls(session$userData$kimlik_kancalari), 0L)
      remove()
      expect_lte(releases, 1L)
    })
  }
})

test_that("TTS takip sorusu doğrulanmış gövdeyi kullanır ve PK reddini atlar", {
  for (validated in c(TRUE, FALSE)) {
    env <- new.env(parent = globalenv())
    source(file.path(resolve_repo_root_for_tests(), "R/server_handler_streaming_tts.R"), local = env)
    env$log_debug <- env$log_warn <- env$log_ai_usage <- env$dbg_dump <- function(...) NULL
    env$mergen_log_llm_request_debug <- function(...) NULL
    env$normalize_character_id <- identity
    env$mergen_speech_voice_mode <- function() "legacy_alias"
    env$get_characters_data <- function() NULL
    bodies <- character()
    env$mergen_stream_dispatch_followups <- function(session, id, user, body, ...) bodies <<- c(bodies, body)
    shiny::testServer(function(input, output, session) NULL, {
      session$userData$user_id <- 7L
      active <- shiny::reactiveVal("A"); stopped <- shiny::reactiveVal(FALSE)
      values <- shiny::reactiveValues(current_chat_id = "chat_A", is_sending = TRUE)
      ctx <- list(session = session, values = values, active_request_id = active,
        stop_generation = stopped, request_id = "A", settings_data = list(enable_tts_audio = FALSE),
        current_settings = list(selected_character = "emre"), model_selected = "m", messages_to_process = list(),
        user_prompt_msg = list(db_id = 1L), current_user_id = 7L, chat_id_val = "chat_A",
        cleanup_send_message = function(...) values$is_sending <- FALSE,
        perf_tracker = list(track_request = function(...) NULL, track_error = function(...) NULL),
        ai_processor = list(call_llm_streaming = function(...) promises::promise_resolve(
          list(success = TRUE, content = "ham yanıt", duration = 1))),
        simulate_streaming_stoppable_fn = function(..., on_complete) on_complete(list(id = "answer",
          content = "gövde ve kaynak dipnotu", followup_content = "doğrulanmış gövde", followup_validated = validated)))
      env$handle_streaming_tts_mode(ctx)
      for (i in 1:50) later::run_now(0)
      expect_identical(bodies, if (validated) "doğrulanmış gövde" else character())
    })
  }
})
