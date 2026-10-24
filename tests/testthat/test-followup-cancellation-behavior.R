testthat::local_edition(3)

.followup_worker_env <- function() {
  env <- new.env(parent = globalenv())
  for (file in c("helpers_user_session_identity.R", "helpers_async_result_guard.R",
                 "helpers_followup_cancellation.R", "helpers_streaming_io.R",
                 "helpers_stream_load_control.R", "helpers_followup_questions.R")) {
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
  env <- .followup_worker_env()
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
    owner <- env$mergen_chat_owner_guard(session, values)
    current <- function() owner() && identical(ud$llm_request_owner, "A")
    callbacks <- list()
    fake_later <- function(fn, delay) callbacks[[length(callbacks) + 1L]] <<- fn
    token <- env$mergen_followup_cancellation(session, current, later_fn = fake_later)
    withr::defer(token$finish())
    expect_false(file.exists(token$path))
    if (change == "owner") env$mergen_session_owner_transition(ud, 7L, 8L)
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
      env$mergen_session_owner_transition(session$userData, 7L, 8L)
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

test_that("takip üretimi iptal edilebilir bağımsız işçiye istek kapsamlı denetimle gider", {
  for (key_fails in c(FALSE, TRUE)) {
    env <- .followup_worker_env()
    if (key_fails) env$mb_api_key_get_effective_key_value <- function(...) stop("anahtar okunamadı")
    callbacks <- list()
    captured <- NULL
    allow <- NULL
    session <- list(userData = new.env())
    session$userData$user_id <- session$userData$kimlik_sahibi <- 7L
    session$userData$llm_request_owner <- "A"
    env$mergen_stream_dispatch_followups(session, "m", "s", "y", list(enable_followups = TRUE),
      list(), NULL, NULL, later_fn = function(fn, delay) callbacks[[1]] <<- fn,
      build_fn = function(..., allow_ai = TRUE) { allow <<- allow_ai; "öneri" },
      dispatch_fn = function(task_fn, cancel_check = NULL, ...) {
        captured <<- cancel_check
        task_fn()
        promises::promise(function(ok, reject) NULL)
      })
    callbacks[[1]]()
    expect_true(is.function(captured))
    expect_true(captured())
    session$userData$llm_request_owner <- "B"
    expect_false(captured())
    # Anahtar hatası yalnız isteğe bağlı AI zenginleştirmesini kapatır.
    expect_identical(allow, !key_fails)
  }
})

test_that("takiplerin dört hata yolu aynı sayacı tam bir kez artırır", {
  for (stage in c("schedule", "admission", "dispatch", "promise")) {
    env <- .followup_worker_env()
    source(file.path(resolve_repo_root_for_tests(), "R/helpers_runtime_metrics.R"),
      encoding = "UTF-8", local = env)
    callback <- NULL
    released <- 0L
    env$mergen_send_message_release_slot <- function(...) released <<- released + 1L
    if (stage == "admission") env$mergen_followup_try_admit <- function(...) stop("admission")
    result <- env$mergen_stream_dispatch_followups(list(userData = new.env()), "m", "s", "y",
      list(enable_followups = TRUE), list(), NULL, NULL,
      plan = list(enabled = TRUE, delay_seconds = 0),
      later_fn = function(fn, ...) {
        if (stage == "schedule") stop("schedule")
        callback <<- fn
      }, dispatch_fn = function(...) {
        if (stage == "dispatch") stop("dispatch")
        promises::promise_reject(simpleError("promise"))
      })
    expect_identical(result, stage != "schedule")
    if (is.function(callback)) callback()
    for (i in 1:30) later::run_now(0)
    expect_equal(env$mergen_runtime_metric_get("followups_failed"), 1, info = stage)
    expect_identical(released, if (stage %in% c("dispatch", "promise")) 1L else 0L)
  }
})

test_that("isteğe bağlı takip sayacı hatası yeni bir hata veya tekrar üretmez", {
  for (stage in c("dispatch", "promise")) {
    env <- .followup_worker_env()
    probes <- 0L
    env$mergen_runtime_metric_inc <- function(...) { probes <<- probes + 1L; stop("sayaç") }
    callback <- NULL
    env$mergen_stream_dispatch_followups(list(userData = new.env()), "m", "s", "y",
      list(enable_followups = TRUE), list(), NULL, NULL,
      plan = list(enabled = TRUE, delay_seconds = 0),
      later_fn = function(fn, ...) callback <<- fn,
      dispatch_fn = function(...) {
        if (stage == "dispatch") stop("dispatch")
        promises::promise_reject(simpleError("promise"))
      })
    callback()
    for (i in 1:30) later::run_now(0)
    # Kabul metriği aynı wrapper'ı kullanır; hata metriği de yalnız bir kez denenir.
    expect_identical(probes, 2L)
  }
})
