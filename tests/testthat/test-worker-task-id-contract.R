# ==============================================================================
# Dosya Yolu: tests/testthat/test-worker-task-id-contract.R
# Açıklama: Worker görev kimliği üretimi ve kayıt defteri çakışma koruması için
# regresyon testleri. Üretim VM'inde aynı anda oluşan future işleri sessizce
# birbirinin kaydını ezmemelidir.
# ==============================================================================

test_that("create_worker_task_id benzersiz ve güvenli görev kimlikleri üretir", {
  ids <- replicate(
    3000,
    create_worker_task_id("unit test"),
    simplify = TRUE
  )

  expect_length(ids, 3000)
  expect_equal(length(unique(ids)), length(ids))

  # Görev kimlikleri log/HTML/diagnostic kullanımında güvenli karakterlerden oluşmalı.
  expect_true(all(grepl("^unit_test_", ids)))
  expect_false(any(grepl("[^A-Za-z0-9_.-]", ids, perl = TRUE)))
})

test_that("register_worker_task aynı task_id için sessiz overwrite yapmaz", {
  task_id <- create_worker_task_id("duplicate_guard")

  register_worker_task(
    task_id = task_id,
    task_type = "duplicate_guard",
    session_token = "unit-session"
  )

  on.exit(finish_worker_task(task_id), add = TRUE)

  expect_error(
    register_worker_task(
      task_id = task_id,
      task_type = "duplicate_guard",
      session_token = "unit-session"
    ),
    regexp = "zaten|already|duplicate"
  )
})