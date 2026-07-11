# ==============================================================================
# Dosya Yolu: tests/testthat/test-worker-monitor.R
# Açıklama: Worker görev izleme yardımcılarının oturum bazlı temizleme ve
# worker sayısı çözümleme davranışını doğrulayan testleri içerir.
# ==============================================================================

# İzole çalıştırma (testthat::test_file) için bağımlılık güvencesi:
# helper_bootstrap.R helpers_worker_monitor.R'yi yükler ancak utils_rate_limiter.R'yi
# yüklemez. resolve_mergen_worker_count() o dosyada tanımlıdır; tam suite'te başka bir
# test global ortama yüklediği için tek başına koşumda eksik kalır. Çalışma dizininden
# bağımsız olarak gerçek sahibini koşulsuz değil, yalnızca yoksa yükleriz.
if (!exists("resolve_mergen_worker_count", mode = "function")) {
  .wm_repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function")) {
    resolve_repo_root_for_tests()
  } else {
    Sys.getenv("MERGEN_REPO_ROOT", unset = getwd())
  }
  source(file.path(.wm_repo_root, "R", "utils_rate_limiter.R"), encoding = "UTF-8")
}

# Oturum bazlı temizliğin yalnızca hedef oturumun görevlerini sildiğini doğrular.
test_that("session bazlı görev temizliği yalnızca ilgili oturumu temizler", {
  before_count <- get_worker_monitor_info()$active_jobs

  id1 <- create_worker_task_id("unit")
  id2 <- create_worker_task_id("unit")

  register_worker_task(id1, task_type = "unit", session_token = "s1")
  register_worker_task(id2, task_type = "unit", session_token = "s2")

  expect_equal(get_worker_monitor_info()$active_jobs, before_count + 2L)

  cleanup_worker_tasks_for_session("s1")
  expect_equal(get_worker_monitor_info()$active_jobs, before_count + 1L)

  cleanup_worker_tasks_for_session("s2")
  expect_equal(get_worker_monitor_info()$active_jobs, before_count)
})

# Worker sayısı çözümleyicisinin her durumda pozitif bir sayı döndürdüğünü doğrular.
test_that("resolve_mergen_worker_count pozitif sayı döndürür", {
  Sys.setenv(MERGEN_WORKERS = "2")
  expect_gte(resolve_mergen_worker_count(), 1L)
  Sys.unsetenv("MERGEN_WORKERS")
})
# Explicit bağımlılık modu: otomatik tarama/genişletme ÇAĞRILMAZ, yalnızca
# verilen globals worker'a taşınır ve görev ortamı izole edilir. Açılış kritik
# yolundaki senkron tarama duraklamasını (Windows VM ~9-14 sn) önleyen sözleşme.
test_that("tracked_future_promise explicit modda otomatik taramayı atlar ve verilen globals ile çalışır", {
  skip_if_not_installed("promises")
  skip_if_not_installed("future")
  skip_if_not_installed("later")

  wm_env <- environment(tracked_future_promise)
  old_detect <- get("worker_monitor_detect_task_deps", envir = wm_env)
  old_expand <- get("worker_monitor_expand_function_globals", envir = wm_env)

  calls <- new.env(parent = emptyenv())
  calls$detect <- 0L
  calls$expand <- 0L

  assign("worker_monitor_detect_task_deps", function(task_fn) {
    calls$detect <- calls$detect + 1L
    old_detect(task_fn)
  }, envir = wm_env)
  assign("worker_monitor_expand_function_globals", function(promise_globals) {
    calls$expand <- calls$expand + 1L
    old_expand(promise_globals)
  }, envir = wm_env)
  on.exit({
    assign("worker_monitor_detect_task_deps", old_detect, envir = wm_env)
    assign("worker_monitor_expand_function_globals", old_expand, envir = wm_env)
  }, add = TRUE)

  before_count <- get_worker_monitor_info()$active_jobs

  got <- new.env(parent = emptyenv())
  p <- tracked_future_promise(
    # startup_probe_value bu test çerçevesinde TANIMLI DEĞİLDİR; yalnızca
    # explicit globals + ortam yeniden bağlama üzerinden çözülebilir.
    task_fn = function() startup_probe_value + 1L,
    task_type = "unit_explicit",
    dependency_mode = "explicit",
    globals = list(startup_probe_value = 41L),
    packages = character(0)
  )

  expect_identical(calls$detect, 0L)
  expect_identical(calls$expand, 0L)

  promises::then(
    p,
    onFulfilled = function(v) got$value <- v,
    onRejected = function(e) got$error <- conditionMessage(e)
  )
  deadline <- Sys.time() + 5
  while (is.null(got$value) && is.null(got$error) && Sys.time() < deadline) {
    later::run_now(timeoutSecs = 0.1)
  }

  expect_null(got$error)
  expect_identical(got$value, 42L)

  # Görev defteri fulfillment sonrası temizlenir.
  expect_equal(get_worker_monitor_info()$active_jobs, before_count)
})

# Varsayılan (auto) mod geri uyumludur: tarama + iç içe genişletme çalışır
# ve kapanış değişkenleri worker tarafına taşınmaya devam eder.
test_that("tracked_future_promise auto modda tarama davranışını korur", {
  skip_if_not_installed("promises")
  skip_if_not_installed("future")
  skip_if_not_installed("later")

  wm_env <- environment(tracked_future_promise)
  old_detect <- get("worker_monitor_detect_task_deps", envir = wm_env)
  old_expand <- get("worker_monitor_expand_function_globals", envir = wm_env)

  calls <- new.env(parent = emptyenv())
  calls$detect <- 0L
  calls$expand <- 0L

  assign("worker_monitor_detect_task_deps", function(task_fn) {
    calls$detect <- calls$detect + 1L
    old_detect(task_fn)
  }, envir = wm_env)
  assign("worker_monitor_expand_function_globals", function(promise_globals) {
    calls$expand <- calls$expand + 1L
    old_expand(promise_globals)
  }, envir = wm_env)
  on.exit({
    assign("worker_monitor_detect_task_deps", old_detect, envir = wm_env)
    assign("worker_monitor_expand_function_globals", old_expand, envir = wm_env)
  }, add = TRUE)

  closure_value <- 5L
  got <- new.env(parent = emptyenv())
  p <- tracked_future_promise(
    task_fn = function() closure_value * 2L,
    task_type = "unit_auto"
  )

  expect_identical(calls$detect, 1L)
  expect_identical(calls$expand, 1L)

  promises::then(
    p,
    onFulfilled = function(v) got$value <- v,
    onRejected = function(e) got$error <- conditionMessage(e)
  )
  deadline <- Sys.time() + 5
  while (is.null(got$value) && is.null(got$error) && Sys.time() < deadline) {
    later::run_now(timeoutSecs = 0.1)
  }

  expect_null(got$error)
  expect_identical(got$value, 10L)
})

# Explicit modda reddedilen görev de defterden temizlenir (kayıt sızıntısı yok).
test_that("tracked_future_promise explicit modda reddedilme sonrası görev defterini temizler", {
  skip_if_not_installed("promises")
  skip_if_not_installed("future")
  skip_if_not_installed("later")

  before_count <- get_worker_monitor_info()$active_jobs

  got <- new.env(parent = emptyenv())
  p <- tracked_future_promise(
    task_fn = function() stop("kasıtlı test hatası"),
    task_type = "unit_explicit_err",
    dependency_mode = "explicit",
    globals = list()
  )
  promises::catch(p, function(e) got$error <- conditionMessage(e))

  deadline <- Sys.time() + 5
  while (is.null(got$error) && Sys.time() < deadline) {
    later::run_now(timeoutSecs = 0.1)
  }

  expect_true(grepl("kasıtlı test hatası", got$error %||% ""))
  expect_equal(get_worker_monitor_info()$active_jobs, before_count)
})
