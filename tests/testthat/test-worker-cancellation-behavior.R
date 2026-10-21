.cancellation_env <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_worker_cancellation.R"),
         encoding = "UTF-8", local = env)
  env
}

test_that("kalıcı işin geri alımı karantinadaki süreç ölmeden başlamaz", {
  env <- .cancellation_env()
  alive <- TRUE
  rejected <- 0L
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  env$mergen_cancellable_worker_launch <- function(...) list(
    is_alive = function() alive, kill_tree = function(...) FALSE,
    kill = function(...) FALSE)
  current <- TRUE
  promises::catch(env$mergen_cancellable_worker_promise(raw(), function() current,
    lane = "durable"), function(e) rejected <<- rejected + 1L)
  env$mergen_cancellable_worker_tick()
  current <- FALSE
  for (i in 1:3) env$mergen_cancellable_worker_tick()
  for (i in 1:10) later::run_now(0)
  expect_true(env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$quarantined)
  expect_identical(rejected, 0L)
  alive <- FALSE
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$next_probe <- Sys.time() - 1
  env$mergen_cancellable_worker_tick()
  for (i in 1:10) later::run_now(0)
  expect_identical(rejected, 1L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
})

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
  expect_length(launched, 1L)
  current[c(1, 3)] <- FALSE
  env$mergen_cancellable_worker_tick()
  expect_false(launched[[1]]$alive)
  expect_length(launched, 2L)
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
  for (i in 1:4) env$mergen_cancellable_worker_promise(as.raw(i), function() TRUE, timeout = 1, queue_timeout = 300)
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[4]]$created <- Sys.time() - 100
  queued <- env$.MERGEN_CANCELLABLE_WORKERS$jobs[[4]]
  env$mergen_cancellable_worker_tick()
  expect_identical(launched, 2L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 4L)
  expect_null(env$.MERGEN_CANCELLABLE_WORKERS$jobs[[4]]$started)
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$process <- list(is_alive = function() FALSE, get_result = function() 1)
  env$mergen_cancellable_worker_tick()
  expect_identical(launched, 3L)
  expect_false(queued$cancelled)
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$process <- list(is_alive = function() FALSE, get_result = function() 1)
  env$mergen_cancellable_worker_tick()
  expect_true(!is.null(queued$started))
})

test_that("bozuk süreç tanıtıcısı ölüm doğrulanana kadar kapasiteyi korur", {
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
  # Karantinada söz bir kez sonuçlanır, süreç yuvası ölüm kanıtlanana dek tutulur.
  expect_identical(errors, 1L)
  expect_identical(kills, 2L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 1L)
  expect_true(env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$quarantined)
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$process$is_alive <- function() FALSE
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$next_probe <- Sys.time() - 1
  env$mergen_cancellable_worker_tick()
  for (i in 1:20) later::run_now(0)
  expect_identical(errors, 1L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
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

test_that("kuyruk yaşı yürütme son tarihinden bağımsız ve sınırlıdır", {
  withr::local_options(mergen.cancellable_workers = 1L)
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  launched <- 0L
  env$mergen_cancellable_worker_launch <- function(payload) {
    launched <<- launched + 1L
    list(is_alive = function() TRUE)
  }
  errors <- 0L
  promises::catch(env$mergen_cancellable_worker_promise(raw(), function() TRUE, timeout = 14400), function(e) NULL)
  promises::catch(env$mergen_cancellable_worker_promise(raw(), function() TRUE, timeout = 30, priority = 2L,
    queue_timeout = 10), function(e) errors <<- errors + 1L)
  env$mergen_cancellable_worker_tick()
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[2]]$created <- Sys.time() - 11
  env$mergen_cancellable_worker_tick()
  for (i in 1:20) later::run_now(0)
  expect_identical(launched, 1L)
  expect_identical(errors, 1L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 1L)
})

test_that("callr çocuğunun anlamsal hatası çağırana ulaşır", {
  env <- .cancellation_env()
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_worker_monitor.R"), local = env)
  error <- NULL
  p <- env$tracked_future_promise(function() stop("RATE_LIMIT: x"), dependency_mode = "explicit",
    globals = list(), cancel_check = function() TRUE)
  promises::catch(p, function(e) error <<- e)
  deadline <- Sys.time() + 15
  while (is.null(error) && Sys.time() < deadline) later::run_now(0.05)
  expect_s3_class(error, "condition")
  expect_match(conditionMessage(error), "RATE_LIMIT: x", fixed = TRUE)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
})

test_that("callr gönderimi kendi havuzunu ve yapılandırılmış son tarihi kullanır", {
  env <- .cancellation_env()
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_worker_monitor.R"), local = env)
  received <- NULL
  env$mergen_cancellable_worker_promise <- function(payload, current, timeout, priority, queue_timeout, lane) {
    received <<- list(timeout = timeout, queue = queue_timeout, lane = lane)
    promises::promise_resolve(TRUE)
  }
  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)
  future::plan(future::sequential)
  env$tracked_future_promise(function() TRUE, task_type = "claude_code_document_summary",
    globals = list(), dependency_mode = "explicit", cancel_check = function() TRUE, execution_timeout = 14400)
  # Kabul edilmiş doküman özeti kalıcı şeritte, yürütme bütçesi kadar bekleyebilir.
  expect_equal(received$timeout, 14400)
  expect_equal(received$queue, 14400)
  expect_identical(received$lane, "durable")
  env$tracked_future_promise(function() TRUE, task_type = "llm_true_streaming",
    globals = list(), dependency_mode = "explicit", cancel_check = function() TRUE)
  expect_equal(received$queue, 300)
  expect_identical(received$lane, "interactive")
  env$tracked_future_promise(function() TRUE, task_type = "claude_code_run_outputs",
    globals = list(), dependency_mode = "explicit", cancel_check = function() TRUE)
  expect_identical(received$lane, "durable")
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_claude_code_dir_listing_async.R"), local = env)
  expect_true(env$cc_dir_listing_async_available())
})


test_that("Yolaç temizlik kilidi canlıyken alınmaz, sert ölümden sonra kurtarılır", {
  env <- .cancellation_env()
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_claude_code_codex_runtime_lock.R"), local = env)
  env$.cc_codex_guard_check <- function(guard) invisible(TRUE)
  lock <- file.path(withr::local_tempdir(), "cleanup.lock")
  ready <- withr::local_tempfile()
  process <- callr::r_bg(function(root, lock, ready) {
    source(file.path(root, "R/utils_common.R"))
    source(file.path(root, "R/helpers_process_ownership.R"))
    source(file.path(root, "R/helpers_claude_code_codex_runtime_lock.R"))
    assign(".cc_codex_guard_check", function(guard) invisible(TRUE), envir = globalenv())
    token <- .cc_codex_acquire_dir_lock(lock)
    stopifnot(nzchar(token))
    file.create(ready)
    Sys.sleep(60)
  }, args = list(root = resolve_repo_root_for_tests(), lock = lock, ready = ready))
  withr::defer(try(process$kill(), silent = TRUE))
  deadline <- Sys.time() + 10
  while (!file.exists(ready) && process$is_alive() && Sys.time() < deadline) Sys.sleep(0.01)
  expect_true(file.exists(ready))
  # Yaşlanmış ama canlı sahip çalınmaz (eşik 1 sn, marker 1.5 sn yaşlı).
  Sys.sleep(1.5)
  expect_identical(env$.cc_codex_acquire_dir_lock(lock, attempts = 0L, stale_sec = 1), "")
  process$kill(); process$wait(timeout = 5000)
  expect_false(process$is_alive())
  token <- env$.cc_codex_acquire_dir_lock(lock, attempts = 1L)
  expect_true(nzchar(token))
  expect_true(env$.cc_codex_reap_dir_lock(lock, token))
})

test_that("kök ölü raporlansa da süreç ağacı temizlenir ve ölüm açık FALSE ile kanıtlanır", {
  env <- .cancellation_env()
  tree <- 0L
  root_dead <- list(is_alive = function() FALSE, kill_tree = function() tree <<- tree + 1L,
                    kill = function(...) stop("kök zaten ölü"))
  expect_true(env$mergen_process_stop(root_dead))
  expect_identical(tree, 1L)
  unknown <- list(is_alive = function() stop("tanıtıcı kapalı"), kill_tree = function() NULL,
                  kill = function(...) NULL)
  expect_false(env$mergen_process_stop(unknown))
})

test_that("sorgulanamayan tanıtıcı PID düzeyinde kanıtlanır; PID de bilinmiyorsa NA kalır", {
  env <- .cancellation_env()
  env$mergen_pid_status <- function(pid, host, since = NULL, slack = 300) if (identical(pid, 41L)) FALSE else NA
  gone <- list(is_alive = function() stop("kapalı"), get_pid = function() 41L, get_start_time = function() Sys.time())
  expect_false(env$mergen_process_status(gone))
  unknown <- list(is_alive = function() stop("kapalı"), get_pid = function() 42L)
  expect_true(is.na(env$mergen_process_status(unknown)))
})

test_that("ölümü doğrulanamayan süreç kaynağını tutar ama terminal bildirimi bir kez alır", {
  env <- .cancellation_env()
  callbacks <- list()
  env$mergen_cancellable_worker_schedule <- function(func, delay) {
    callbacks[[length(callbacks) + 1L]] <<- list(func = func, delay = delay)
    function() NULL
  }
  alive <- NA
  process <- list(is_alive = function() if (is.na(alive)) stop("bilinmiyor") else alive,
                  kill_tree = function() NULL, kill = function(...) NULL)
  released <- uncertain <- 0L
  env$mergen_retire_process(process, function() released <<- released + 1L,
                            on_uncertain = function() uncertain <<- uncertain + 1L)
  for (i in 1:4) callbacks[[length(callbacks)]]$func()
  expect_identical(released, 0L)
  expect_identical(uncertain, 1L)
  expect_lte(callbacks[[length(callbacks)]]$delay, 30)
  alive <- FALSE
  callbacks[[length(callbacks)]]$func()
  expect_identical(released, 1L)
  expect_identical(uncertain, 1L)
})

test_that("sonlandırılamayan süreç ölene dek fiziksel yuva tutar, sözü bir kez sonuçlanır", {
  withr::local_options(mergen.cancellable_workers = 1L)
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  launched <- 0L
  zombie <- new.env()
  zombie$alive <- TRUE
  zombie$is_alive <- function() zombie$alive
  zombie$kill_tree <- function() NULL
  zombie$kill <- function(...) stop("sonlandırma reddedildi")
  env$mergen_cancellable_worker_launch <- function(payload) {
    launched <<- launched + 1L
    if (launched == 1L) zombie else list(is_alive = function() TRUE)
  }
  settled <- list()
  current <- TRUE
  promises::then(env$mergen_cancellable_worker_promise(raw(), function() current),
                 function(v) settled[[length(settled) + 1L]] <<- "ok",
                 function(e) settled[[length(settled) + 1L]] <<- conditionMessage(e))
  env$mergen_cancellable_worker_promise(raw(), function() TRUE)
  env$mergen_cancellable_worker_tick()
  expect_identical(launched, 1L)
  current <- FALSE
  for (i in 1:6) env$mergen_cancellable_worker_tick()
  for (i in 1:20) later::run_now(0)
  # Karantinadaki canlı olabilecek süreç yerine ikinci süreç başlatılmaz.
  expect_true(isTRUE(env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$quarantined))
  expect_identical(launched, 1L)
  expect_length(settled, 1L)
  expect_match(settled[[1]], "karantinada")
  expect_length(env$.mergen_cancellable_live_jobs(), 1L)
  expect_false(env$mergen_cancellable_worker_admissible("interactive"))
  # Ölüm kanıtlanınca yuva bırakılır; söz yeniden sonuçlanmaz.
  zombie$alive <- FALSE
  env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]$next_probe <- Sys.time() - 1
  env$mergen_cancellable_worker_tick()
  for (i in 1:20) later::run_now(0)
  expect_identical(launched, 2L)
  expect_length(settled, 1L)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 1L)
})

test_that("şeritler yapılandırılan toplam süreç sınırını çoğaltmaz", {
  withr::local_options(mergen.cancellable_workers = 2L)
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  launched <- character()
  env$mergen_cancellable_worker_launch <- function(payload) {
    launched <<- c(launched, rawToChar(payload))
    list(is_alive = function() TRUE)
  }
  for (i in 1:3) env$mergen_cancellable_worker_promise(charToRaw(paste0("alim", i)), function() TRUE, lane = "durable")
  for (i in 1:3) env$mergen_cancellable_worker_promise(charToRaw(paste0("sohbet", i)), function() TRUE)
  for (i in 1:3) env$mergen_cancellable_worker_tick()
  expect_identical(env$mergen_cancellable_worker_capacity(), 2L)
  expect_setequal(launched, c("alim1", "sohbet1"))
  expect_identical(env$.mergen_cancellable_running(env$.MERGEN_CANCELLABLE_WORKERS$jobs), 2L)
})

test_that("bir şeridin kuyruğu dolu olsa da diğer şerit iş kabul eder", {
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  sohbet <- lapply(1:34, function(i) { job <- new.env(); job$lane <- "interactive"; job })
  env$.MERGEN_CANCELLABLE_WORKERS$jobs <- sohbet
  failure <- NULL
  p <- env$mergen_cancellable_worker_promise(raw(), function() TRUE, lane = "durable")
  promises::catch(p, function(e) failure <<- e)
  for (i in 1:20) later::run_now(0)
  expect_null(failure)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 35L)
})

test_that("zaman aşımı, kuyruk zaman aşımı ve kullanıcı iptali ayrı bildirilir", {
  withr::local_options(mergen.cancellable_workers = 1L)
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  env$mergen_cancellable_worker_launch <- function(payload) {
    process <- new.env()
    process$alive <- TRUE
    process$is_alive <- function() process$alive
    process$kill_tree <- function() process$alive <- FALSE
    process
  }
  messages <- character()
  record <- function(e) messages <<- c(messages, conditionMessage(e))
  current <- TRUE
  promises::catch(env$mergen_cancellable_worker_promise(raw(), function() current, timeout = 1), record)
  promises::catch(env$mergen_cancellable_worker_promise(raw(), function() TRUE, queue_timeout = 1), record)
  env$mergen_cancellable_worker_tick()
  jobs <- env$.MERGEN_CANCELLABLE_WORKERS$jobs
  jobs[[1]]$started <- Sys.time() - 5
  jobs[[2]]$created <- Sys.time() - 5
  env$mergen_cancellable_worker_tick()
  promises::catch(env$mergen_cancellable_worker_promise(raw(), function() current), record)
  env$mergen_cancellable_worker_tick()
  current <- FALSE
  env$mergen_cancellable_worker_tick()
  for (i in 1:20) later::run_now(0)
  expect_length(messages, 3L)
  expect_match(messages[[1]], "^TIMEOUT:")
  expect_match(messages[[2]], "kuyru", fixed = TRUE)
  expect_false(grepl("TIMEOUT", messages[[2]]))
  expect_match(messages[[3]], "iptal edildi", fixed = TRUE)
})

test_that("kalıcı işler etkileşimli şeridin kapasitesini tüketmez", {
  withr::local_options(mergen.cancellable_workers = 2L)
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  launched <- character()
  env$mergen_cancellable_worker_launch <- function(payload) {
    launched <<- c(launched, rawToChar(payload))
    list(is_alive = function() TRUE)
  }
  env$mergen_cancellable_worker_promise(charToRaw("alim"), function() TRUE, lane = "durable")
  env$mergen_cancellable_worker_promise(charToRaw("alim2"), function() TRUE, lane = "durable")
  env$mergen_cancellable_worker_promise(charToRaw("sohbet"), function() TRUE)
  env$mergen_cancellable_worker_tick()
  expect_setequal(launched, c("alim", "sohbet"))
  expect_false(env$mergen_cancellable_worker_admissible("durable"))
  expect_false(env$mergen_cancellable_worker_admissible("interactive"))
})


test_that("tek fiziksel işçi iki şeridi öncelikle ve sırayla çalıştırır", {
  withr::local_options(mergen.cancellable_workers = 1L)
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  processes <- list()
  launched <- character()
  env$mergen_cancellable_worker_launch <- function(payload) {
    launched <<- c(launched, rawToChar(payload))
    p <- new.env(); p$alive <- TRUE
    p$is_alive <- function() p$alive
    p$get_result <- function() TRUE
    processes[[length(processes) + 1L]] <<- p
    p
  }
  failure <- NULL
  promises::catch(env$mergen_cancellable_worker_promise(charToRaw("kalici"), function() TRUE,
    lane = "durable", priority = 2L), function(e) failure <<- e)
  env$mergen_cancellable_worker_promise(charToRaw("sohbet"), function() TRUE)
  env$mergen_cancellable_worker_tick()
  expect_identical(launched, "sohbet")
  expect_identical(env$.mergen_cancellable_running(env$.MERGEN_CANCELLABLE_WORKERS$jobs), 1L)
  processes[[1]]$alive <- FALSE
  env$mergen_cancellable_worker_tick()
  expect_identical(launched, c("sohbet", "kalici"))
  expect_identical(env$.mergen_cancellable_running(env$.MERGEN_CANCELLABLE_WORKERS$jobs), 1L)
  processes[[2]]$alive <- FALSE
  env$mergen_cancellable_worker_tick()
  for (i in 1:20) later::run_now(0)
  expect_null(failure)
  expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
  expect_true(env$mergen_cancellable_worker_admissible("durable"))
})

test_that("sohbet doluluğu kalıcı işin ayrılmış fiziksel yuvasını tüketmez", {
  withr::local_options(mergen.cancellable_workers = 2L)
  env <- .cancellation_env()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  launched <- character()
  env$mergen_cancellable_worker_launch <- function(payload) {
    launched <<- c(launched, rawToChar(payload))
    list(is_alive = function() TRUE)
  }
  for (name in c("sohbet1", "sohbet2"))
    env$mergen_cancellable_worker_promise(charToRaw(name), function() TRUE)
  env$mergen_cancellable_worker_tick()
  env$mergen_cancellable_worker_promise(charToRaw("alim"), function() TRUE, lane = "durable")
  env$mergen_cancellable_worker_tick()
  expect_setequal(launched, c("sohbet1", "alim"))
  expect_identical(env$.mergen_cancellable_running(env$.MERGEN_CANCELLABLE_WORKERS$jobs), 2L)
})
