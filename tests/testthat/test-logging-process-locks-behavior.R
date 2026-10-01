# Canlı günlük üreticisi ve eski dizin kilidi yarışları.

.log_lock_env <- function() {
  env <- new.env(parent = globalenv())
  for (ad in c("config_logging_locks.R", "config_logging_daily_file.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", ad), encoding = "UTF-8", local = env)
  }
  env
}

.log_lock_ready <- function(path) {
  bitis <- Sys.time() + 10
  while (!file.exists(path) && Sys.time() < bitis) Sys.sleep(0.02)
  expect_true(file.exists(path))
}

test_that("canlı yedek yazıcının kilidi sahiplenmeyi ve veri kaybını önler", {
  skip_if_not_installed("callr")
  skip_if_not_installed("filelock")
  env <- .log_lock_env()
  dizin <- withr::local_tempdir()
  ana <- file.path(dizin, "mergen_20260101.log")
  yedek <- file.path(dizin, "mergen_20260101.pbaska-11.log")
  hazir <- file.path(dizin, "hazir")
  devam <- file.path(dizin, "devam")
  writeBin(charToRaw("ilk\n"), yedek)
  isci <- callr::r_bg(function(yedek, hazir, devam) {
    kilit <- filelock::lock(paste0(yedek, ".writer"))
    on.exit(filelock::unlock(kilit))
    writeLines("hazir", hazir)
    while (!file.exists(devam)) Sys.sleep(0.02)
    con <- file(yedek, "ab")
    writeBin(charToRaw("son\n"), con)
    close(con)
  }, args = list(yedek, hazir, devam))
  on.exit(if (isci$is_alive()) isci$kill(), add = TRUE)
  .log_lock_ready(hazir)
  Sys.setFileTime(yedek, Sys.time() - 600)
  expect_length(env$.mergen_log_orphan_fallbacks(ana, "bizim.log", TRUE), 0L)
  expect_true(file.exists(yedek))
  writeLines("devam", devam)
  isci$wait(10000)
  expect_false(isci$is_alive())
  sahiplenilen <- env$.mergen_log_orphan_fallbacks(ana, "bizim.log", TRUE)
  expect_length(sahiplenilen, 0L)
  Sys.setFileTime(yedek, Sys.time() - 600)
  sahiplenilen <- env$.mergen_log_orphan_fallbacks(ana, "bizim.log", TRUE)
  expect_length(sahiplenilen, 1L)
  expect_true(env$.mergen_log_merge_fallback(ana, sahiplenilen))
  expect_identical(readBin(ana, "raw", file.info(ana)$size), charToRaw("ilk\nson\n"))
})

test_that("canlı süreçte eski mtime işletim sistemi kilidini devraldırmaz", {
  skip_if_not_installed("callr")
  skip_if_not_installed("filelock")
  env <- .log_lock_env()
  dizin <- withr::local_tempdir()
  kilit <- file.path(dizin, "yazim.lock")
  hazir <- file.path(dizin, "hazir")
  devam <- file.path(dizin, "devam")
  kaynak <- file.path(resolve_repo_root_for_tests(), "R", "config_logging_locks.R")
  isci <- callr::r_bg(function(kaynak, kilit, hazir, devam) {
    source(kaynak, encoding = "UTF-8")
    jeton <- .mergen_log_lock_acquire(kilit, 0.25, 1)
    on.exit(.mergen_log_lock_release(kilit, jeton))
    writeLines(jeton, hazir)
    while (!file.exists(devam)) Sys.sleep(0.02)
  }, args = list(kaynak, kilit, hazir, devam))
  on.exit(if (isci$is_alive()) isci$kill(), add = TRUE)
  .log_lock_ready(hazir)
  sahibi <- readLines(hazir)
  Sys.setFileTime(c(kilit, file.path(kilit, "sahip")), Sys.time() - 600)
  expect_null(env$.mergen_log_lock_acquire(kilit, 0.05, 1))
  expect_identical(readLines(file.path(kilit, "sahip")), sahibi)
  writeLines("devam", devam)
  isci$wait(10000)
  expect_false(isci$is_alive())
  jeton <- env$.mergen_log_lock_acquire(kilit, 0.05, 1)
  expect_type(jeton, "character")
  env$.mergen_log_lock_release(kilit, jeton)
})

test_that("dizin sahiplenilmeden önce tazelenen eski kilit korunur", {
  env <- .log_lock_env()
  kilit <- file.path(withr::local_tempdir(), "yazim.lock")
  dir.create(kilit)
  writeLines("onceki-sahip", file.path(kilit, "sahip"))
  Sys.setFileTime(c(kilit, file.path(kilit, "sahip")), Sys.time() - 600)
  env$file.rename <- function(from, to) {
    if (identical(from, kilit)) Sys.setFileTime(file.path(from, "sahip"), Sys.time())
    base::file.rename(from, to)
  }
  expect_null(env$.mergen_log_lock_acquire(kilit, 0, 1))
  expect_identical(readLines(file.path(kilit, "sahip")), "onceki-sahip")
})
