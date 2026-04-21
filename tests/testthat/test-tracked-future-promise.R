# ==============================================================================
# Dosya Yolu: tests/testthat/test-tracked-future-promise.R
# Açıklama: tracked_future_promise() sarmalayıcısının giriş doğrulaması, görev
# defteri büyüme/küçülme davranışı ve otomatik globals tespiti regresyonlarını
# koruyan birim testlerini içerir. MERGEN_DISABLE_FUTURES=true iken plan
# sequential olur; bu sayede testler dış süreç başlatmaz.
# ==============================================================================

# Fonksiyon dışında bir task_fn verildiğinde net bir hata üretir.
test_that("tracked_future_promise fonksiyon olmayan task_fn reddeder", {
  expect_error(tracked_future_promise(task_fn = "metin"), "task_fn")
  expect_error(tracked_future_promise(task_fn = NULL),     "task_fn")
  expect_error(tracked_future_promise(task_fn = 42L),      "task_fn")
})

# Başarılı promise tamamlandığında görev defterinden kayıt kaldırılır.
test_that("tracked_future_promise başarılı tamamlanmada görev defterini boşaltır", {
  onceki_aktif <- get_worker_monitor_info()$active_jobs

  p <- tracked_future_promise(
    task_fn = function() 7L + 5L,
    task_type = "unit_test_ok",
    session_token = "sess_test_ok"
  )

  # Sequential planda promise hemen çözülür; later kuyruğunu boşaltalım.
  later::run_now()

  sonraki_aktif <- get_worker_monitor_info()$active_jobs
  expect_equal(sonraki_aktif, onceki_aktif)
})

# onRejected yolunda da görev defteri temizlenmelidir.
test_that("tracked_future_promise hata durumunda görev defterini boşaltır", {
  onceki_aktif <- get_worker_monitor_info()$active_jobs

  # Promise hata verdiğinde onRejected sarmalayıcısı finish_worker_task çağırır.
  p <- tracked_future_promise(
    task_fn = function() stop("kasitli_hata"),
    task_type = "unit_test_err",
    session_token = "sess_test_err"
  )

  # Reddedilen promise'ı bastırarak yakala (uyarı üretmesin diye).
  promises::then(p, onRejected = function(err) NULL)
  later::run_now()

  sonraki_aktif <- get_worker_monitor_info()$active_jobs
  expect_equal(sonraki_aktif, onceki_aktif)
})
