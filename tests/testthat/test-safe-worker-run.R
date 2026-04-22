# ==============================================================================
# Dosya Yolu: tests/testthat/test-safe-worker-run.R
# Açıklama: safe_worker_run() yardımcısının başarı/hata/giriş doğrulaması
# yollarını ve süre (duration_sec) ölçümünü kontrol eden birim testleri.
# ==============================================================================

local({
  if (!exists("safe_worker_run", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "utils_safe_worker_run.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

test_that("safe_worker_run başarılı görevde ok=TRUE ve doğru değeri döndürür", {
  sonuc <- safe_worker_run(task_fn = function() 2L + 3L)

  expect_true(sonuc$ok)
  expect_equal(sonuc$value, 5L)
  expect_null(sonuc$error_code)
  expect_null(sonuc$error_message)
  expect_true(is.numeric(sonuc$duration_sec))
  expect_true(sonuc$duration_sec >= 0)
})

test_that("safe_worker_run hata durumunda ok=FALSE ve hata mesajını döndürür", {
  sonuc <- safe_worker_run(task_fn = function() stop("özel_hata"))

  expect_false(sonuc$ok)
  expect_null(sonuc$value)
  expect_equal(sonuc$error_code, "worker_error")
  expect_true(grepl("özel_hata", sonuc$error_message, fixed = TRUE))
  expect_true(is.numeric(sonuc$duration_sec))
})

test_that("safe_worker_run custom error_code_fn kullanılabilir", {
  siniflandirici <- function(e) {
    if (grepl("network", conditionMessage(e))) "network_error" else "other"
  }

  sonuc_net <- safe_worker_run(
    task_fn = function() stop("network is down"),
    error_code_fn = siniflandirici
  )
  expect_equal(sonuc_net$error_code, "network_error")

  sonuc_other <- safe_worker_run(
    task_fn = function() stop("başka bir şey"),
    error_code_fn = siniflandirici
  )
  expect_equal(sonuc_other$error_code, "other")
})

test_that("safe_worker_run fonksiyon olmayan task_fn reddeder", {
  sonuc <- safe_worker_run(task_fn = "metin")
  expect_false(sonuc$ok)
  expect_equal(sonuc$error_code, "invalid_task_fn")

  sonuc2 <- safe_worker_run(task_fn = NULL)
  expect_false(sonuc2$ok)
  expect_equal(sonuc2$error_code, "invalid_task_fn")
})

test_that("safe_worker_run NULL değer döndüren başarılı görevleri bozmaz", {
  # İş fonksiyonu NULL dönebilir; ok hâlâ TRUE olmalı ve value NULL kalmalı.
  sonuc <- safe_worker_run(task_fn = function() NULL)

  expect_true(sonuc$ok)
  expect_null(sonuc$value)
  expect_null(sonuc$error_code)
})

test_that("safe_worker_run error_code_fn kendisi çökerse default kodu korur", {
  patlayan_siniflandirici <- function(e) stop("siniflandirici çöktü")

  sonuc <- safe_worker_run(
    task_fn = function() stop("asıl hata"),
    error_code_fn = patlayan_siniflandirici
  )

  # Sınıflandırıcı çökerse "worker_error" varsayılanına geri dönmeli.
  expect_false(sonuc$ok)
  expect_equal(sonuc$error_code, "worker_error")
})
