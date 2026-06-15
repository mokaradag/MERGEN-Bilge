# ==============================================================================
# Dosya Yolu: tests/testthat/test-character-video-debug-behavior.R
# Açıklama: .character_video_debug (R/module_character_video.R) küçük log
#           sarmalayıcısının davranışını sınar: log_debug mevcutsa mesaj+... ona
#           iletilir; mevcut değilse sessizce no-op olur (hata fırlatmaz) ve her
#           durumda invisible(NULL) döner. Modül dosyası yalnızca fonksiyon tanımı
#           içerdiğinden baseenv ebeveynli izole bir ortama source edilir; böylece
#           log_debug arama zinciri deterministiktir (batch globalenv kirliliğinden
#           etkilenmez). Gerçek logger/DB/ağ GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)

.cvd_repo_root <- resolve_repo_root_for_tests()
.cvd_file <- file.path(.cvd_repo_root, "R", "module_character_video.R")

test_that("log_debug yoksa .character_video_debug sessizce no-op olur (invisible NULL)", {
  # Ebeveyn baseenv: zincirde globalenv YOK -> log_debug kesinlikle bulunmaz.
  env <- new.env(parent = baseenv())
  source(.cvd_file, encoding = "UTF-8", local = env)

  fn <- env[[".character_video_debug"]]
  expect_true(is.function(fn))

  res <- NULL
  expect_no_error(res <- fn("herhangi bir mesaj", char_id = "emre"))
  expect_null(res)

  # Görünmez döndürdüğünü kanıtla (withVisible$visible FALSE olmalı).
  vis <- withVisible(fn("ikinci mesaj"))
  expect_false(vis$visible)
  expect_null(vis$value)
})

test_that("log_debug mevcutsa .character_video_debug mesajı ve ... argümanlarını iletir", {
  rec <- new.env()
  rec$calls <- list()

  env <- new.env(parent = baseenv())
  # log_debug kayıt edici stub: gerçek glue/logger çalıştırmaz, yalnızca argümanları toplar.
  env$log_debug <- function(msg, ...) {
    rec$calls[[length(rec$calls) + 1L]] <- list(msg = msg, dots = list(...))
    invisible(NULL)
  }
  source(.cvd_file, encoding = "UTF-8", local = env)

  fn <- env[[".character_video_debug"]]
  res <- fn("[VIDEO R] test mesajı: {char_key}", char_key = "selin", count = 3L)

  expect_null(res)
  expect_length(rec$calls, 1L)
  expect_identical(rec$calls[[1]]$msg, "[VIDEO R] test mesajı: {char_key}")
  expect_identical(rec$calls[[1]]$dots$char_key, "selin")
  expect_identical(rec$calls[[1]]$dots$count, 3L)
})
