# Aynı süreçte oturumlar sayaçları paylaşır; işçiler ayrı dosyalara yazar.

.performance_storage_env <- function() {
  env <- new.env(parent = globalenv())
  env$mb_presence_publish <- function(...) invisible(TRUE)
  source(file.path(resolve_repo_root_for_tests(), "R", "module_performance.R"),
         encoding = "UTF-8", local = env)
  env
}

test_that("oturumlar aynı süreç toplamını kaybetmeden biriktirir", {
  env <- .performance_storage_env()
  ikinci <- .performance_storage_env()
  dizin <- withr::local_tempdir()
  withr::local_envvar(c(MERGEN_APP_WORKER_INDEX = "1", MERGEN_APP_WORKER_COUNT = "2", MERGEN_PORT = "4300"))
  withr::with_dir(dizin, {
    shiny::testServer(env$performanceStatsServer, args = list(current_user_id_provider = function() 7L), {
      session$returned$track_request(1)
    })
    shiny::testServer(env$performanceStatsServer, args = list(current_user_id_provider = function() 8L), {
      for (i in 1:9) session$returned$track_request(1)
    })
    dosya <- list.files("logs", pattern = "performance_stats-.*4300\\.txt$", full.names = TRUE)
    expect_length(dosya, 1L)
    expect_identical(read.delim(dosya)$total_requests, 10L)
    expect_false(file.exists("logs/performance_stats.txt"))
    ilk <- readBin(dosya, "raw", file.info(dosya)$size)
    Sys.setenv(MERGEN_APP_WORKER_INDEX = "2", MERGEN_PORT = "4301")
    shiny::testServer(ikinci$performanceStatsServer, args = list(current_user_id_provider = function() 9L), {
      for (i in 1:10) session$returned$track_request(1)
    })
    expect_identical(readBin(dosya, "raw", file.info(dosya)$size), ilk)
    expect_length(list.files("logs", pattern = "performance_stats-.*4301\\.txt$"), 1L)
  })
})

test_that("aynı PID ile yeni önyükleme ayrı varlık kimliği alır", {
  kaynak <- file.path(resolve_repo_root_for_tests(), "R", "helpers_user_presence_shared.R")
  ilk <- new.env(parent = globalenv())
  ikinci <- new.env(parent = globalenv())
  source(kaynak, encoding = "UTF-8", local = ilk)
  source(kaynak, encoding = "UTF-8", local = ikinci)
  expect_false(identical(ilk$mb_presence_process_id(), ikinci$mb_presence_process_id()))
  expect_identical(ilk$mb_presence_process_id(), ilk$mb_presence_process_id())
})
