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