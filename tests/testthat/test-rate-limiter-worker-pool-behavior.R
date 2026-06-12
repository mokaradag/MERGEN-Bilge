# ==============================================================================
# Dosya Yolu: tests/testthat/test-rate-limiter-worker-pool-behavior.R
# Açıklama: utils_rate_limiter.R işçi havuzu yardımcıları için davranış
#           testleri: monitor_workers ve stop_future_cluster. Gerçek PSOCK
#           cluster başlatılmaz; parallel::stopCluster mock'lanır ve global
#           future planı test sonunda geri yüklenir. Çevrimdışı/deterministik.
# ==============================================================================

.rateLimiterEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  # monitor_workers, get_worker_monitor_info'ya bağımlıdır
  source(file.path(kok, "R", "helpers_worker_monitor.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "utils_rate_limiter.R"), encoding = "UTF-8", local = env)
  env
}

testthat::test_that("monitor_workers uygulama düzeyi işçi metriği sözleşmesini döndürür", {
  env <- .rateLimiterEnv()

  bilgi <- env$monitor_workers()

  testthat::expect_true(is.list(bilgi))
  beklenen_alanlar <- c("total_workers", "active_jobs", "active_workers",
                        "free_workers", "queued_jobs", "usage_pct",
                        "task_type_breakdown", "note")
  testthat::expect_true(all(beklenen_alanlar %in% names(bilgi)))

  # Tutarlılık: işçi sayıları negatif olamaz ve aktif <= toplam
  testthat::expect_true(bilgi$total_workers >= 1L)
  testthat::expect_true(bilgi$active_workers <= bilgi$total_workers)
  testthat::expect_true(bilgi$free_workers >= 0L)
  testthat::expect_true(bilgi$queued_jobs >= 0L)
  testthat::expect_true(bilgi$usage_pct >= 0 && bilgi$usage_pct <= 100)

  # Not metni bu metriğin uygulama-düzeyi olduğunu açıkça söyler
  testthat::expect_true(grepl("uygulama düzeyi", bilgi$note, fixed = TRUE))
})

testthat::test_that("stop_future_cluster cluster yokken sessizce NULL döner", {
  env <- .rateLimiterEnv()

  # Önkoşul: globalenv'de cluster nesnesi olmadığından emin ol
  if (exists(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE)) {
    rm(".mergen_future_cluster", envir = .GlobalEnv)
  }

  stop_cagri <- 0L
  testthat::local_mocked_bindings(
    stopCluster = function(cl) { stop_cagri <<- stop_cagri + 1L; invisible(NULL) },
    .package = "parallel"
  )

  testthat::expect_null(env$stop_future_cluster())
  testthat::expect_identical(stop_cagri, 0L)
})

testthat::test_that("stop_future_cluster mevcut cluster'ı durdurur, kaldırır ve sequential'a döner", {
  env <- .rateLimiterEnv()

  # Mevcut future planını test sonunda geri yükle
  eski_plan <- future::plan()
  withr::defer(future::plan(eski_plan))

  # Sahte cluster nesnesi: gerçek PSOCK başlatmadan globalenv'e koy
  sahte_cluster <- structure(list(), class = c("fake_cluster", "cluster"))
  assign(".mergen_future_cluster", sahte_cluster, envir = .GlobalEnv)
  withr::defer({
    if (exists(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".mergen_future_cluster", envir = .GlobalEnv)
    }
  })

  durdurulan <- list()
  testthat::local_mocked_bindings(
    stopCluster = function(cl) {
      durdurulan[[length(durdurulan) + 1L]] <<- class(cl)[1]
      invisible(NULL)
    },
    .package = "parallel"
  )

  testthat::expect_null(env$stop_future_cluster())

  # Cluster durduruldu ve globalenv'den kaldırıldı
  testthat::expect_length(durdurulan, 1L)
  testthat::expect_identical(durdurulan[[1L]], "fake_cluster")
  testthat::expect_false(
    exists(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE)
  )

  # Plan sequential'a dönmüş olmalı
  testthat::expect_true(inherits(future::plan(), "sequential"))
})
