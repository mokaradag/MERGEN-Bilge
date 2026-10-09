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
