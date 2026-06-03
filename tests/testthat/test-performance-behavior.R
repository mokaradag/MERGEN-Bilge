# ==============================================================================
# Dosya Yolu: tests/testthat/test-performance-behavior.R
# Açıklama: R/module_performance.R performanceStatsServer() tarafından döndürülen
#           istek/hata takip mantığının DAVRANIŞSAL testleri. Bu dosya daha önce
#           hiçbir test tarafından çağrılmıyordu.
#
#           track_request(): toplam ve başarılı istek sayacını artırır, ortalama
#           yanıt süresini koşan ortalama (running average) ile günceller.
#           track_error(): toplam istek + hata sayacını artırır (başarılıyı değil).
#           Modül init'te logs/performance_stats.txt okur/yazar; testler bunu
#           geçici dizinde (withr::with_dir) izole ederek deterministik tutar.
#           cat() çıktısı yutulur. Gerçek DB/ağ GEREKMEZ.
# ==============================================================================

.source_performance_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_performance.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# performanceStatsServer'ı temiz (dosyasız) geçici dizinde çalıştırır, body(session)
# fonksiyonunu testServer reaktif bağlamında çağırır ve cat() çıktısını yutar.
# Böylece istatistikler 0'dan başlar.
.run_performance <- function(env, body) {
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  invisible(utils::capture.output(
    withr::with_dir(tmp, {
      shiny::testServer(
        env$performanceStatsServer,
        args = list(current_user_id_provider = function() 5L),
        {
          body(session)
        }
      )
    })
  ))
}

# ------------------------------------------------------------------------------
# track_request
# ------------------------------------------------------------------------------
testthat::test_that("track_request toplam ve başarılı istek sayacını artırır", {
  env <- .source_performance_for_test()
  res <- new.env()
  .run_performance(env, function(session) {
    r <- session$returned
    r$track_request(1.5)
    res$total <- shiny::isolate(r$stats$total_requests)
    res$success <- shiny::isolate(r$stats$successful_requests)
    res$avg <- shiny::isolate(r$stats$avg_response_time)
  })
  testthat::expect_identical(res$total, 1)
  testthat::expect_identical(res$success, 1)
  # İlk istek -> ortalama doğrudan ilk süreye eşit.
  testthat::expect_identical(res$avg, 1.5)
})

testthat::test_that("track_request ortalama yanıt süresini koşan ortalama ile günceller", {
  env <- .source_performance_for_test()
  res <- new.env()
  .run_performance(env, function(session) {
    r <- session$returned
    r$track_request(2.0)
    r$track_request(4.0)
    res$avg <- shiny::isolate(r$stats$avg_response_time)
    res$total <- shiny::isolate(r$stats$total_requests)
  })
  # ((2*1)+4)/2 = 3.0
  testthat::expect_identical(res$avg, 3.0)
  testthat::expect_identical(res$total, 2)
})

testthat::test_that("track_request süre verilmezse sayacı artırır, ortalamayı bozmaz", {
  env <- .source_performance_for_test()
  res <- new.env()
  .run_performance(env, function(session) {
    r <- session$returned
    r$track_request(2.0)        # avg = 2.0
    r$track_request(NULL)       # süre yok -> avg değişmemeli
    res$avg <- shiny::isolate(r$stats$avg_response_time)
    res$total <- shiny::isolate(r$stats$total_requests)
  })
  testthat::expect_identical(res$avg, 2.0)
  testthat::expect_identical(res$total, 2)
})

# ------------------------------------------------------------------------------
# track_error
# ------------------------------------------------------------------------------
testthat::test_that("track_error toplam ve hata sayacını artırır, başarılıyı artırmaz", {
  env <- .source_performance_for_test()
  res <- new.env()
  .run_performance(env, function(session) {
    r <- session$returned
    r$track_error()
    res$total <- shiny::isolate(r$stats$total_requests)
    res$errors <- shiny::isolate(r$stats$error_count)
    res$success <- shiny::isolate(r$stats$successful_requests)
  })
  testthat::expect_identical(res$total, 1)
  testthat::expect_identical(res$errors, 1)
  testthat::expect_identical(res$success, 0)
})

testthat::test_that("track_request ve track_error sayaçları bağımsız ilerletir", {
  env <- .source_performance_for_test()
  res <- new.env()
  .run_performance(env, function(session) {
    r <- session$returned
    r$track_request(1.0)
    r$track_request(1.0)
    r$track_error()
    res$total <- shiny::isolate(r$stats$total_requests)
    res$success <- shiny::isolate(r$stats$successful_requests)
    res$errors <- shiny::isolate(r$stats$error_count)
  })
  testthat::expect_identical(res$total, 3)
  testthat::expect_identical(res$success, 2)
  testthat::expect_identical(res$errors, 1)
})

# ------------------------------------------------------------------------------
# Dönen yapı + oturum sayacı
# ------------------------------------------------------------------------------
testthat::test_that("performanceStatsServer beklenen kontrol listesini döndürür", {
  env <- .source_performance_for_test()
  res <- new.env()
  .run_performance(env, function(session) {
    res$names <- names(session$returned)
    res$count <- session$returned$get_active_session_count()
  })
  testthat::expect_true(all(c(
    "track_request", "track_error", "touch_session", "get_active_session_count", "stats"
  ) %in% res$names))
  # Init sırasında bu oturum kaydedildiğinden en az bir aktif oturum olmalı.
  testthat::expect_true(res$count >= 1L)
})
