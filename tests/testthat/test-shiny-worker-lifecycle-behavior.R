suppressMessages(library(promises))

.lifecycle_env <- function(files) {
  env <- new.env(parent = globalenv())
  for (file in files) source(file.path(resolve_repo_root_for_tests(), "R", file),
                            encoding = "UTF-8", local = env)
  env
}

.lifecycle_drain <- function() {
  for (i in 1:50) later::run_now(0)
}

test_that("geç SSE sonucu yeni isteği, sohbeti veya sahibi değiştirmez", {
  for (change in c("request", "chat", "owner")) {
    env <- .lifecycle_env(c("helpers_async_result_guard.R", "helpers_streaming_io.R",
                            "helpers_streaming_poll_lifecycle.R", "server_handler_true_streaming.R"))
    env$normalize_character_id <- identity
    env$get_characters_data <- function() NULL
    env$format_timestamp <- function() "zaman"
    env$mergen_true_streaming_worker_globals <- function(...) list()
    env$log_info <- env$log_warn <- function(...) NULL
    rec <- new.env()
    rec$resets <- 0L
    rec$writes <- 0L
    env$save_message_safely <- function(...) { rec$writes <- rec$writes + 1L; 1L }
    env$tracked_future_promise <- function(task_fn, ...) {
      rec$stream <- environment(task_fn)$stream_env
      promises::promise(function(resolve, reject) { rec$resolve <- resolve })
    }
    shiny::testServer(function(input, output, session) {
      session$userData$user_id <- 7L
    session$userData$kimlik_sahibi <- 7L
      session$userData$kimlik_sahibi <- 7L
      values <- shiny::reactiveValues(current_chat_id = "chat_A", messages = list(),
                                     typing = TRUE, is_sending = TRUE)
      active <- shiny::reactiveVal("A")
      stopped <- shiny::reactiveVal(FALSE)
      ctx <- list(session = session, output = output, values = values,
                  settings_data = list(), current_settings = list(), active_request_id = active,
                  stop_generation = stopped, request_id = "A", model_selected = "m",
                  stream_profile = list(), chat_history = list(),
                  reset_chat_state_fn = function() { rec$resets <- rec$resets + 1L })
      shiny::isolate(env$handle_true_streaming_mode(ctx))
      if (change == "request") { active("B"); session$userData$llm_request_owner <- "B" }
      if (change == "chat") values$current_chat_id <- "chat_B"
      if (change == "owner") { session$userData$user_id <- 8L; session$userData$kimlik_nesli <- 1L }
      values$messages <- list(list(id = "B", content = "Yeni sohbet"))
      rec$resolve(list(success = TRUE, content = "A kullanıcısının özel yanıtı"))
      .lifecycle_drain()
      session$flushReact()
      expect_identical(shiny::isolate(values$messages[[1]]$content), "Yeni sohbet")
      expect_true(shiny::isolate(values$is_sending))
      expect_true(shiny::isolate(values$typing))
      expect_identical(rec$resets, 0L)
      expect_identical(rec$writes, 0L)
      expect_false(file.exists(rec$stream$stream_file))
      expect_false(file.exists(rec$stream$stop_file))
    }, {})
  }
})

test_that("Yolaç sahip geçişi süreci durdurur ve eski devam bağlarını siler", {
  env <- .lifecycle_env(c("helpers_user_session_identity.R", "helpers_async_result_guard.R",
                          "helpers_claude_code_run_lifecycle.R", "helpers_claude_code_session_persistence.R",
                          "helpers_claude_code_workbench_session_api.R"))
  env$cc_release_runtime_lease <- function(...) NULL
  rv <- new.env()
  killed <- FALSE
  rv$active_process <- list(kill = function() killed <<- TRUE)
  rv$is_running <- TRUE
  rv$cli_session_id <- "A-cli"
  rv$conversation_context <- list("A-gizli")
  rv$output_history <- list("A-gecmis")
  rv$active_runtime_workdir <- "A-runtime"
  rv$active_runtime_source <- "A-source"
  rv$claude_session_record_id <- 42L
  rv$stream_env <- new.env()
  rv$stream_env$output_sync_guard <- tempfile()
  file.create(rv$stream_env$output_sync_guard)
  old_stream <- rv$stream_env
  refresh <- 0L
  shiny::testServer(function(input, output, session) {
    session$userData$user_id <- 7L
    session$userData$kimlik_sahibi <- 7L
    env$cc_mark_active_run(rv, "A", session)
    env$cc_bind_workbench_owner_lifecycle(session, identity, rv,
                                        list(next_id = function() refresh <<- refresh + 1L))
    session$userData$user_id <- 8L
    env$mergen_session_owner_transition(session$userData, 7L, 8L)
    expect_true(killed)
    expect_false(env$cc_is_active_run(rv, "A"))
    expect_false(rv$is_running)
    expect_null(rv$active_runtime_workdir)
    expect_null(rv$active_runtime_source)
    expect_null(rv$cli_session_id)
    expect_null(rv$claude_session_record_id)
    expect_length(rv$output_history, 0L)
    expect_length(rv$conversation_context, 0L)
    expect_false(file.exists(old_stream$output_sync_guard))
    expect_gt(refresh, 0L)
  }, {})
})

test_that("çalışan Yolaç kaydı görünüm detach edilse de aynı kayda yazılır", {
  env <- .lifecycle_env("helpers_claude_code_session_persistence.R")
  saved <- list()
  env$cc_db_claude_tables_available <- function(...) TRUE
  env$cc_db_save_run <- function(...) { saved[[length(saved) + 1L]] <<- list(...); 1L }
  env$cc_db_update_session_resume_state <- function(...) TRUE
  for (status in c("success", "failed", "stopped")) {
    rv <- new.env()
    rv$claude_session_record_id <- 42L
    rv$active_persist_record_id <- 42L
    run <- list(persist_record_id = 42L, user_id = 7L, prompt = "soru")
    env$cc_persist_detach_session(rv)
    rv$claude_session_record_id <- 99L
    expect_true(env$cc_persist_run_result(rv, run, status, "yanıt"))
    expect_identical(tail(saved, 1)[[1]]$session_record_id, 42L)
  }
})

test_that("non-streaming işçi canlı oturum taşımaz ve grafikleri erken uygulamaz", {
  env <- .lifecycle_env("module_ai_processing.R")
  env$resolve_local_llm_credentials <- function(...) list(endpoint = "http://localhost", allow_user_key = FALSE)
  env$api_config <- list(local_models = "m")
  globals_names <- c("call_llm_worker", "call_local_llm_sse_worker", "llm_worker_run_mcp_second_pass",
    "llm_worker_second_pass_messages", "llm_worker_second_pass_body", "llm_worker_second_pass_headers",
    "llm_worker_second_pass_fallback_response", "llm_worker_call_second_pass_non_streaming",
    "llm_worker_stream_content_looks_like_reasoning", "format_answer_from_tool_results",
    "get_local_model_capabilities", "should_omit_temperature", "should_allow_reasoning_fallback",
    "apply_model_request_overrides", "normalize_llm_text_node", "extract_first_nonempty_llm_text",
    "extract_llm_text_bundle", "extract_llm_delta_bundle", "resolve_local_llm_endpoint",
    "extract_llm_content_and_sources", "normalize_llm_scalar_content", "strip_planner_text",
    "decode_utf8_raw_chunk", "create_utf8_stream_decoder", "find_last_utf8_boundary", "parse_llm_sse_event",
    "extract_llm_delta_text", "extract_llm_event_sources", "append_stream_delta_line",
    "append_stream_reasoning_line", "streaming_should_stop")
  for (name in globals_names) env[[name]] <- function(...) NULL
  rec <- new.env()
  env$tracked_future_promise <- function(task_fn, globals, ...) {
    rec$globals <- globals
    rec$task_env <- environment(task_fn)
    promises::promise(function(resolve, reject) rec$resolve <- resolve)
  }
  shiny::testServer(env$aiProcessingServer, {
    session$userData$chart_store <- list(existing = "B-chart")
    p <- session$returned$call_llm_non_streaming(list(), list(model_selection = "m", shiny_session = session))
    expect_null(rec$globals$settings_copy$shiny_session)
    expect_false("session" %in% ls(rec$task_env, all.names = TRUE))
    rec$resolve(list(ai_text = list(content = "A", chart_store = list(private = "A-chart")), duration = 1))
    .lifecycle_drain()
    expect_identical(session$userData$chart_store, list(existing = "B-chart"))
  })
})

test_that("tek işçi meşgulken büyük DOCX gönderimi olay döngüsünü açık tutar", {
  env <- .lifecycle_env(c("helpers_worker_monitor.R", "helpers_async_result_guard.R"))
  cl <- parallel::makePSOCKcluster(1L)
  withr::defer(parallel::stopCluster(cl))
  old_plan <- future::plan(future::cluster, workers = cl)
  withr::defer(future::plan(old_plan))
  future::value(future::future(Sys.getpid()))
  path <- tempfile(fileext = ".docx")
  withr::defer(unlink(path))
  writeBin(as.raw(rep(65L, 11L * 1024L * 1024L)), path)
  busy <- future::future(Sys.sleep(2))
  started <- Sys.time()
  done <- NULL
  failure <- NULL
  p <- env$mergen_dispatch_docx_preview(path, "docx-test")
  promises::then(p, function(value) done <<- value, function(error) failure <<- error)
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 1.3)
  heartbeat <- FALSE
  later::later(function() heartbeat <<- TRUE, 0)
  later::run_now(0)
  expect_true(heartbeat)
  expect_false(future::resolved(busy))
  future::value(busy)
  deadline <- Sys.time() + 15
  while (is.null(done) && is.null(failure) && Sys.time() < deadline) later::run_now(0.05)
  expect_null(failure)
  expect_gt(nchar(done %||% ""), 10L * 1024L * 1024L)
})

test_that("indeks kilidini bekleyen işçi UI ve alım yuvasını erken bırakmaz", {
  env <- .lifecycle_env(c("helpers_worker_monitor.R", "helpers_file_ingestion_index_worker.R"))
  cl <- parallel::makePSOCKcluster(1L)
  withr::defer(parallel::stopCluster(cl))
  old_plan <- future::plan(future::cluster, workers = cl)
  withr::defer(future::plan(old_plan))
  future::value(future::future(Sys.getpid()))
  marker <- tempfile()
  withr::defer(unlink(marker))
  env$file_ingestion_worker_globals <- function() list(
    file_ingestion_commit_index = function(results, user_id) {
      writeLines(as.character(Sys.getpid()), results[[1]]$marker)
      Sys.sleep(0.8)
      list(indexed = "rapor.txt", ms = 800)
    }
  )
  bundle <- env$file_ingestion_worker_globals()
  environment(bundle$file_ingestion_commit_index) <- baseenv()
  env$file_ingestion_worker_globals <- function() bundle
  released <- FALSE
  applied <- FALSE
  env$file_ingestion_release_slot <- function() released <<- TRUE
  env$file_ingestion_pump <- function() NULL
  env$file_ingestion_fail_job <- function(job, error) stop(error)
  env$file_ingestion_apply_commit <- function(...) { applied <<- TRUE; released <<- TRUE }
  controller <- new.env()
  controller$epoch <- 1L
  job <- list(controller = controller, epoch = 1L, user_id = "7", session_token = "index-test")
  env$file_ingestion_finish_job(job, list(list(marker = marker)))
  heartbeat <- FALSE
  later::later(function() heartbeat <<- TRUE, 0)
  later::run_now(0)
  expect_true(heartbeat)
  expect_false(released)
  expect_false(applied)
  deadline <- Sys.time() + 15
  while (!applied && Sys.time() < deadline) later::run_now(0.05)
  expect_true(applied)
  expect_false(identical(readLines(marker), as.character(Sys.getpid())))
})

test_that("takip üretimi ayrı süreçte çalışır ve bayat öneriler uygulanmaz", {
  env <- .lifecycle_env(c("helpers_worker_monitor.R", "helpers_streaming_io.R",
                          "helpers_runtime_metrics.R", "helpers_request_backpressure.R",
                          "helpers_stream_load_control.R", "helpers_followup_questions.R"))
  env$mb_api_key_get_effective_key_value <- function(...) "kişisel-anahtar"
  env$mergen_perf_now <- function() 0
  env$mergen_perf_log <- function(...) NULL
  env$mergen_send_message_release_slot <- function(...) NULL
  updates <- list()
  env$push_followup_update <- function(session, msg_id, suggestions, ...) updates[[length(updates) + 1L]] <<- suggestions
  builder <- function(...) { Sys.sleep(1); c(as.character(Sys.getpid()), "öneri") }
  environment(builder) <- baseenv()
  cl <- parallel::makePSOCKcluster(1L)
  withr::defer(parallel::stopCluster(cl))
  old_plan <- future::plan(future::cluster, workers = cl)
  withr::defer(future::plan(old_plan))
  future::value(future::future(Sys.getpid()))
  ud <- new.env()
  ud$user_id <- 7L
  ud$llm_request_owner <- "A"
  session <- list(userData = ud, token = "followup-test", input = list())
  dispatch <- function() env$mergen_stream_dispatch_followups(
    session, "msg", "soru", "yanıt", list(enable_followups = TRUE), list(), NULL, NULL,
    plan = list(enabled = TRUE, delay_seconds = 0, disable_under_backpressure = TRUE), build_fn = builder
  )
  dispatch()
  started <- Sys.time()
  later::run_now(0)
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 0.8)
  deadline <- Sys.time() + 15
  while (!length(updates) && Sys.time() < deadline) later::run_now(0.05)
  expect_length(updates, 1L)
  expect_false(identical(updates[[1]][1], as.character(Sys.getpid())))
  dispatch()
  later::run_now(0)
  ud$llm_request_owner <- "B"
  deadline <- Sys.time() + 1.5
  while (Sys.time() < deadline) later::run_now(0.05)
  expect_length(updates, 1L)
})

test_that("dizin işçisi reddedilince ana süreç dosya sistemini yeniden taramaz", {
  env <- .lifecycle_env(c("helpers_claude_code_server_setup.R", "helpers_user_session_identity.R",
                          "helpers_claude_code_workbench_session_api.R", "helpers_claude_code_session_persistence.R"))
  env$claude_code_scenarios <- list()
  env$SSO_ENABLED <- FALSE
  env$claude_code_config <- list(cli_path = "", default_workdir = "")
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$resolve_claude_cli_path <- function(...) ""
  env$cc_create_active_character_reactive <- function(...) function() list(id = "emre", accent = "blue", display_name = "Emre")
  env$cc_create_user_first_name_reactive <- function(...) function() "Ali"
  env$cc_require_ready_user_id <- function(...) list(ok = TRUE, user_id = 7L)
  env$cc_resolve_effective_user_id <- function(...) 7L
  env$cc_dir_listing_async_available <- function() TRUE
  env$cc_dir_listing_worker_globals <- function() list()
  env$cc_log_warn <- function(...) NULL
  scanned <- 0L
  env$list_directory_contents <- function(...) { scanned <<- scanned + 1L; stop("Ana süreçte tarama") }
  for (dispatch_error in c(FALSE, TRUE)) {
    env$tracked_future_promise <- function(...) {
      if (dispatch_error) stop("Gönderim hatası")
      promises::promise_reject(simpleError("İşçi hatası"))
    }
    shiny::testServer(function(input, output, session) {
      rv <- shiny::reactiveValues(connection_ok = TRUE)
      generation <- 0L
      api <- env$cc_bind_server_setup(input, output, session, identity, rv, function() 7L,
        dir_refresh_guard = list(next_id = function() { generation <<- generation + 1L; generation },
                                 is_latest = function(id) identical(id, generation)))
      api$observe_dir_contents("//sunucu/yavaş/dizin")
      .lifecycle_drain()
      expect_identical(scanned, 0L)
    }, {})
  }
})

test_that("Yolaç hazırlığı sırasında detach çalışan kayıt bağını değiştirmez", {
  env <- .lifecycle_env(c("helpers_claude_code_run_lifecycle.R", "helpers_claude_code_session_persistence.R"))
  env$cc_db_claude_tables_available <- function(...) TRUE
  env$cc_db_create_session <- function(...) 77L
  env$cc_db_generate_session_title <- function(...) "Başlık"
  rv <- new.env()
  rv$claude_session_record_id <- 42L
  env$cc_mark_active_run(rv, "A")
  env$cc_persist_detach_session(rv)
  expect_identical(env$cc_persist_session_begin(rv, 7L, "soru"), 42L)
  expect_null(rv$claude_session_record_id)
  env$cc_mark_active_run(rv, "B")
  expect_identical(env$cc_persist_session_begin(rv, 7L, "yeni"), 77L)
})

test_that("Yolaç promise koruması reaktif bağlam dışında güncel isteği okuyabilir", {
  env <- .lifecycle_env("helpers_claude_code_run_lifecycle.R")
  rv <- shiny::reactiveValues(active_request_id = "A")
  expect_true(env$cc_is_active_run(rv, "A"))
  expect_false(env$cc_is_active_run(rv, "B"))
})
