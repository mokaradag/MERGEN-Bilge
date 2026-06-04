# ==============================================================================
# Dosya Yolu: tests/testthat/test-worker-monitor-summary-behavior.R
# Açıklama: R/helpers_worker_monitor.R işçi izleme defteri davranış testleri.
#           init_worker_monitor singleton sözleşmesi ve summarize_worker_tasks_by_type
#           tip-bazlı sayım davranışı doğrulanır. Defter .GlobalEnv'de tekildir;
#           her test kaydettiği görevleri sonradan temizler.
# ==============================================================================

testthat::local_edition(3)

.wm_ready <- exists("init_worker_monitor", mode = "function") &&
  exists("summarize_worker_tasks_by_type", mode = "function") &&
  exists("register_worker_task", mode = "function") &&
  exists("finish_worker_task", mode = "function")

test_that("init_worker_monitor tasks ortamı ve started_at içeren tekil defter döner", {
  skip_if_not(.wm_ready, "worker monitor yardımcıları yüklü değil")
  m1 <- init_worker_monitor()
  m2 <- init_worker_monitor()
  # Singleton: iki çağrı aynı ortamı döndürür.
  expect_identical(m1, m2)
  expect_true(is.environment(m1$tasks))
  expect_true(inherits(m1$started_at, "POSIXct"))
})

test_that("summarize_worker_tasks_by_type görevleri tipe göre sayar ve temizlikte boşalır", {
  skip_if_not(.wm_ready, "worker monitor yardımcıları yüklü değil")

  # Çakışmayı önlemek için ayırt edici tipler ve kimlikler kullan.
  ids <- c("wmtest_a1", "wmtest_a2", "wmtest_b1")
  withr::defer(for (id in ids) finish_worker_task(id))

  register_worker_task("wmtest_a1", task_type = "wmtest_alpha")
  register_worker_task("wmtest_a2", task_type = "wmtest_alpha")
  register_worker_task("wmtest_b1", task_type = "wmtest_beta")

  ozet <- summarize_worker_tasks_by_type()
  # Kaydettiğimiz tipler beklenen sayılarla görünmeli.
  expect_equal(ozet[["wmtest_alpha"]], 2L)
  expect_equal(ozet[["wmtest_beta"]], 1L)

  # Görevleri bitirince kendi tiplerimiz özetten kaybolmalı.
  for (id in ids) finish_worker_task(id)
  ozet2 <- summarize_worker_tasks_by_type()
  expect_null(ozet2[["wmtest_alpha"]])
  expect_null(ozet2[["wmtest_beta"]])
})

test_that("register_worker_task aynı kimliği ikinci kez kaydetmeyi reddeder", {
  skip_if_not(.wm_ready, "worker monitor yardımcıları yüklü değil")
  withr::defer(finish_worker_task("wmtest_dup"))
  register_worker_task("wmtest_dup", task_type = "wmtest_dup_type")
  expect_error(register_worker_task("wmtest_dup", task_type = "wmtest_dup_type"))
})

test_that("finish_worker_task görevi defterden kaldırır ve var olmayan kimlikte sessizdir", {
  skip_if_not(.wm_ready, "worker monitor yardımcıları yüklü değil")
  register_worker_task("wmtest_fin", task_type = "wmtest_fin_type")
  monitor <- init_worker_monitor()
  expect_true(exists("wmtest_fin", envir = monitor$tasks, inherits = FALSE))

  finish_worker_task("wmtest_fin")
  expect_false(exists("wmtest_fin", envir = monitor$tasks, inherits = FALSE))
  # Olmayan kimlik için hata vermemeli.
  expect_silent(finish_worker_task("wmtest_olmayan_xyz"))
})
