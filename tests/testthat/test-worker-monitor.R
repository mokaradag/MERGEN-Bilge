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

test_that("resolve_mergen_worker_count pozitif sayı döndürür", {
  Sys.setenv(MERGEN_WORKERS = "2")
  expect_gte(resolve_mergen_worker_count(), 1L)
  Sys.unsetenv("MERGEN_WORKERS")
})