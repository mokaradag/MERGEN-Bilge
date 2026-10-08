testthat::local_edition(3)

.followup_worker_env <- function() {
  env <- new.env(parent = globalenv())
  for (file in c("helpers_streaming_io.R", "helpers_stream_load_control.R", "helpers_followup_questions.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", file), encoding = "UTF-8", local = env)
  }
  env$mb_api_key_get_effective_key_value <- function(...) "test-key"
  env$mergen_perf_now <- function() 0
  env$mergen_perf_log <- function(...) NULL
  env$mergen_send_message_release_slot <- function(...) NULL
  env
}

test_that("kullanıcı takipleri kapattığında anahtar veya işçi çözülmez", {
  env <- .followup_worker_env()
  env$mb_api_key_get_effective_key_value <- function(...) stop("Anahtar okunmamalı")
  session <- list(userData = new.env())
  expect_false(env$mergen_stream_dispatch_followups(session, "m", "s", "y",
    list(enable_followups = FALSE), list(), NULL, NULL,
    later_fn = function(...) stop("Planlanmamalı"), dispatch_fn = function(...) stop("Gönderilmemeli")))
})

test_that("takip jetonu sahip, istek, sohbet veya oturum kapanışında iptal edilir", {
  for (change in c("owner", "request", "chat", "closed")) {
    ud <- new.env()
    ud$user_id <- ud$kimlik_sahibi <- 7L
    ud$llm_request_owner <- "A"
    closed <- FALSE
    end_fn <- NULL
    session <- list(userData = ud, isClosed = function() closed,
      onSessionEnded = function(fn) { end_fn <<- fn; function() end_fn <<- NULL })
    values <- new.env()
    values$current_chat_id <- "chat-A"
    owner <- mergen_chat_owner_guard(session, values)
    current <- function() owner() && identical(ud$llm_request_owner, "A")
    callbacks <- list()
    fake_later <- function(fn, delay) callbacks[[length(callbacks) + 1L]] <<- fn
    token <- mergen_followup_cancellation(session, current, later_fn = fake_later)
    withr::defer(token$finish())
    expect_false(file.exists(token$path))
    if (change == "owner") mergen_session_owner_transition(ud, 7L, 8L)
    if (change == "request") ud$llm_request_owner <- "B"
    if (change == "chat") values$current_chat_id <- "chat-B"
    if (change == "closed") { closed <- TRUE; end_fn() }
    callbacks[[1]]()
    expect_true(file.exists(token$path))
    expect_length(ls(ud$kimlik_kancalari), 0L)
    expect_null(end_fn)
    expect_length(callbacks, 1L)
    token$finish()
    expect_false(file.exists(token$path))
  }
})

test_that("takip işçisi genel HTTP iptal kapısını taşır ve bayat sonucu bırakır", {
  env <- .followup_worker_env()
  callbacks <- list()
  task <- NULL
  resolve <- NULL
  updates <- 0L
  env$push_followup_update <- function(...) updates <<- updates + 1L
  session <- list(userData = new.env())
  session$userData$user_id <- session$userData$kimlik_sahibi <- 7L
  session$userData$llm_request_owner <- "A"
  env$mergen_stream_dispatch_followups(session, "m", "s", "y", list(enable_followups = TRUE),
    list(), NULL, NULL, later_fn = function(fn, delay) callbacks[[1]] <<- fn,
    build_fn = function(...) {
      gate <- getOption("mergen.llm.stop_check")
      expect_true(is.function(gate))
      expect_false(gate())
      mergen_session_owner_transition(session$userData, 7L, 8L)
      expect_true(gate())
      "bayat öneri"
    }, dispatch_fn = function(task_fn, ...) {
      task <<- task_fn
      promises::promise(function(ok, reject) resolve <<- ok)
    })
  callbacks[[1]]()
  expect_null(task())
  expect_null(getOption("mergen.llm.stop_check"))
  resolve("bayat öneri")
  for (i in 1:30) later::run_now(0)
  expect_identical(updates, 0L)
  expect_length(ls(session$userData$kimlik_kancalari), 0L)
})

test_that("tek işçide iptal edilen takip aktarımı kapasiteyi yeni göreve bırakır", {
  env <- .followup_worker_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_worker_monitor.R"),
         encoding = "UTF-8", local = env)
  cl <- parallel::makePSOCKcluster(1L)
  withr::defer(parallel::stopCluster(cl))
  old <- future::plan(future::cluster, workers = cl)
  withr::defer(future::plan(old))
  future::value(future::future(Sys.getpid()))
  marker <- withr::local_tempfile()
  builder <- function(...) {
    writeLines("started", marker)
    gate <- getOption("mergen.llm.stop_check")
    deadline <- Sys.time() + 20
    while (!gate() && Sys.time() < deadline) Sys.sleep(0.02)
    "bayat öneri"
  }
  environment(builder) <- list2env(list(marker = marker), parent = baseenv())
  session <- list(userData = new.env(), token = "followup-cancel")
  session$userData$user_id <- session$userData$kimlik_sahibi <- 7L
  session$userData$llm_request_owner <- "A"
  env$push_followup_update <- function(...) stop("Bayat sonuç uygulanmamalı")
  env$mergen_stream_dispatch_followups(session, "m", "s", "y", list(enable_followups = TRUE),
    list(), NULL, NULL, build_fn = builder)
  deadline <- Sys.time() + 15
  while (!file.exists(marker) && Sys.time() < deadline) later::run_now(0.05)
  expect_true(file.exists(marker))
  session$userData$llm_request_owner <- "B"
  done <- NULL
  failed <- NULL
  env$tracked_future_promise(function() "yeni görev", "cancel-capacity") |>
    promises::then(function(value) done <<- value, function(e) failed <<- e)
  deadline <- Sys.time() + 5
  while (is.null(done) && is.null(failed) && Sys.time() < deadline) later::run_now(0.05)
  expect_null(failed)
  expect_identical(done, "yeni görev")
})
