.cancellation_env <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_worker_cancellation.R"),
         encoding = "UTF-8", local = env)
  env
}

test_that("iptal kuyruğu iki süreci aşmaz ve bayat bekleyen işi başlatmaz", {
  withr::local_options(mergen.cancellable_workers = 2L)
  env <- .cancellation_env()
  current <- rep(TRUE, 4)
  launched <- list()
  env$mergen_cancellable_worker_launch <- function(payload) {
    process <- new.env()
    process$alive <- TRUE
    process$is_alive <- function() process$alive
    process$kill <- function(...) { process$alive <- FALSE; TRUE }
    process$get_result <- function() as.integer(payload)
    launched[[length(launched) + 1L]] <<- process
    process
  }
  env$mergen_cancellable_worker_schedule <- function(...) function() NULL
  errors <- 0L
  for (i in 1:4) local({
    id <- i
    promises::catch(env$mergen_cancellable_worker_promise(as.raw(id), function() current[id]),
                    function(e) errors <<- errors + 1L)
  })
  env$mergen_cancellable_worker_tick()
  expect_length(launched, 2L)
  current[c(1, 3)] <- FALSE
  env$mergen_cancellable_worker_tick()
  expect_false(launched[[1]]$alive)
  expect_length(launched, 3L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 2L)
  for (i in 1:20) later::run_now(0)
  expect_identical(errors, 2L)
})

test_that("sonlanmayan eski süreç kapasitesini ve kirasını korur", {
  env <- .cancellation_env()
  callbacks <- list()
  env$mergen_cancellable_worker_schedule <- function(func, ...) {
    callbacks[[length(callbacks) + 1L]] <<- func
    function() NULL
  }
  process <- new.env()
  process$alive <- TRUE
  process$is_alive <- function() process$alive
  process$kill <- function(...) stop("sonlandırma başarısız")
  released <- 0L
  env$mergen_retire_process(process, function() released <<- released + 1L)
  expect_identical(released, 0L)
  expect_length(callbacks, 1L)
  process$alive <- FALSE
  callbacks[[1]]()
  expect_identical(released, 1L)
})

test_that("iptal kuyruğu doluyken sınırsız görev kabul etmez", {
  env <- .cancellation_env()
  env$.MERGEN_CANCELLABLE_WORKERS$jobs <- rep(list(new.env()), 34L)
  failure <- NULL
  p <- env$mergen_cancellable_worker_promise(raw(), function() TRUE)
  expect_true(promises::is.promise(p))
  promises::catch(p, function(e) failure <<- e)
  for (i in 1:20) later::run_now(0)
  expect_match(conditionMessage(failure), "kuyruğu dolu")
})

test_that("yardımcı işler sohbet için ayrılan bekleme kapasitesini tüketmez", {
  env <- .cancellation_env()
  env$.MERGEN_CANCELLABLE_WORKERS$jobs <- rep(list(new.env()), 32L)
  failure <- NULL
  p <- env$mergen_cancellable_worker_promise(raw(), function() TRUE, priority = 2L)
  expect_true(promises::is.promise(p))
  promises::catch(p, function(e) failure <<- e)
  for (i in 1:20) later::run_now(0)
  expect_match(conditionMessage(failure), "kuyruğu dolu")
})

test_that("izlenen iptal işi canlı oturum kapanışını işçiye serileştirmez", {
  env <- .cancellation_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_worker_monitor.R"),
         encoding = "UTF-8", local = env)
  captured <- NULL
  env$mergen_cancellable_worker_promise <- function(payload, ...) {
    captured <<- unserialize(payload)
    promises::promise_resolve(captured())
  }
  task <- local({
    unused_session <- new.env()
    value <- "düz veri"
    function() value
  })
  env$tracked_future_promise(task, cancel_check = function() TRUE)
  expect_identical(captured(), "düz veri")
  expect_false(exists("unused_session", environment(captured), inherits = FALSE))
  expect_false(exists("task_fn", environment(captured), inherits = FALSE))
  for (i in 1:20) later::run_now(0)
})

test_that("çalışan iptal işi ağ veya yerli çağrının dönmesini beklemeden sonlanır", {
  if (!requireNamespace("callr", quietly = TRUE)) skip("Bağımsız süreç desteği kullanılamıyor")
  env <- .cancellation_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_worker_monitor.R"),
         encoding = "UTF-8", local = env)
  marker <- withr::local_tempfile()
  current <- TRUE
  error <- NULL
  p <- env$tracked_future_promise(function() {
    writeLines(as.character(Sys.getpid()), marker)
    Sys.sleep(30)
    TRUE
  }, dependency_mode = "explicit", globals = list(marker = marker),
  cancel_check = function() current)
  promises::catch(p, function(e) error <<- e)
  deadline <- Sys.time() + 15
  while (!file.exists(marker) && is.null(error) && Sys.time() < deadline) later::run_now(0.05)
  expect_true(file.exists(marker))
  process <- env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$process
  current <- FALSE
  started <- Sys.time()
  deadline <- started + 5
  while (is.null(error) && Sys.time() < deadline) later::run_now(0.05)
  expect_s3_class(error, "error")
  expect_false(process$is_alive())
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 5)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
})

test_that("bağımsız işçi iç içe yardımcıların bildirdiği paketleri yükler", {
  if (!requireNamespace("callr", quietly = TRUE)) skip("Bağımsız süreç desteği kullanılamıyor")
  env <- .cancellation_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_worker_monitor.R"),
         encoding = "UTF-8", local = env)
  helper <- function(value) digest(value, algo = "xxhash64")
  environment(helper) <- globalenv()
  result <- error <- NULL
  p <- env$tracked_future_promise(function() helper("veri"),
    dependency_mode = "explicit", globals = list(helper = helper),
    packages = "digest", cancel_check = function() TRUE)
  promises::then(p, function(value) result <<- value, function(e) error <<- e)
  deadline <- Sys.time() + 15
  while (is.null(result) && is.null(error) && Sys.time() < deadline) later::run_now(0.05)
  expect_null(error)
  expect_identical(result, digest::digest("veri", algo = "xxhash64"))
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
})

test_that("istek işçisi sohbet değişimi, durdurma ve oturum kapanışında geçersizleşir", {
  for (change in c("chat", "stop", "owner", "end")) {
    shiny::testServer(function(input, output, session) NULL, {
      session$userData$user_id <- 7L
      session$userData$kimlik_sahibi <- 7L
      active <- shiny::reactiveVal("A")
      stopped <- shiny::reactiveVal(FALSE)
      values <- shiny::reactiveValues(current_chat_id = "chat_A")
      remove <- mergen_bind_request_owner_cleanup(session, active, "A", function() NULL,
                                                  values, stopped)
      current <- session$userData$llm_worker_guard
      expect_true(current())
      if (change == "chat") values$current_chat_id <- "chat_B"
      if (change == "stop") stopped(TRUE)
      if (change == "owner") session$userData$kimlik_nesli <- 1L
      if (change == "end") session$close()
      expect_false(current())
      remove()
    })
  }
})

test_that("bekleme süresi yürütme süresini tüketmez ve kapasite yapılandırılır", {
  withr::local_options(mergen.cancellable_workers = 3L)
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  launched <- 0L
  env$mergen_cancellable_worker_launch <- function(payload) {
    launched <<- launched + 1L
    list(is_alive = function() TRUE)
  }
  for (i in 1:4) env$mergen_cancellable_worker_promise(as.raw(i), function() TRUE, timeout = 1)
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[4]]$created <- Sys.time() - 100
  env$mergen_cancellable_worker_tick()
  expect_identical(launched, 3L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 4L)
  expect_null(env$.MERGEN_CANCELLABLE_WORKERS$jobs[[4]]$started)
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$process <- list(is_alive = function() FALSE, get_result = function() 1)
  env$mergen_cancellable_worker_tick()
  expect_identical(launched, 4L)
  expect_false(env$.MERGEN_CANCELLABLE_WORKERS$jobs[[3]]$cancelled)
  expect_true(!is.null(env$.MERGEN_CANCELLABLE_WORKERS$jobs[[3]]$started))
})

test_that("bozuk süreç tanıtıcısı sınırlı denemeden sonra kapasiteyi bırakır", {
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  kills <- 0L
  env$mergen_cancellable_worker_launch <- function(payload) list(
    is_alive = function() stop("tanıtıcı kapalı"),
    kill_tree = function() kills <<- kills + 1L,
    kill = function(...) kills <<- kills + 1L)
  errors <- 0L
  promises::catch(env$mergen_cancellable_worker_promise(raw(), function() TRUE),
    function(e) errors <<- errors + 1L)
  env$mergen_cancellable_worker_tick()
  for (i in 1:3) env$mergen_cancellable_worker_tick()
  for (i in 1:20) later::run_now(0)
  expect_identical(errors, 1L)
  expect_identical(kills, 2L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
  env$mergen_cancellable_worker_tick()
  expect_identical(errors, 1L)
})

test_that("yüksek stdout ve stderr çıktısı bağımsız işçiyi kilitlemez", {
  env <- .cancellation_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_worker_monitor.R"),
         encoding = "UTF-8", local = env)
  result <- error <- NULL
  p <- env$tracked_future_promise(function() {
    for (i in 1:300) {
      cat(strrep("x", 8192), "\n")
      cat(strrep("y", 8192), "\n", file = stderr())
    }
    42L
  }, dependency_mode = "explicit", globals = list(), cancel_check = function() TRUE)
  promises::then(p, function(value) result <<- value, function(e) error <<- e)
  deadline <- Sys.time() + 20
  while (is.null(result) && is.null(error) && Sys.time() < deadline) later::run_now(0.05)
  expect_null(error)
  expect_identical(result, 42L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
})
