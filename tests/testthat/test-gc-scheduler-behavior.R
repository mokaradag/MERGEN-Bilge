# ==============================================================================
# Dosya Yolu: tests/testthat/test-gc-scheduler-behavior.R
# Açıklama: config_file_store.R içindeki gc_scheduler ve start_gc_scheduler_once
#           davranışını doğrular. gc_scheduler periyodik çöp toplama döngüsünü
#           later::later ile yeniden zamanlar; hata durumunda daha uzun gecikmeyle
#           tekrar dener. start_gc_scheduler_once tek-seferlik global bayrak ile
#           döngünün yalnızca bir kez başlamasını sağlar.
#
#           later::later mock'lanır (gerçek arka plan callback'i ZAMANLANMAZ),
#           gc() env'e stub edilir ve .mergen_gc_scheduler_started global bayrağı
#           test başında temizlenip sonunda eski haline döndürülür. Çevrimdışı,
#           deterministik; gerçek GC/arka plan döngüsü yok.
# ==============================================================================

# Türkçe yorum: config_file_store.R'yi yalıtılmış ortama yükler; gc() önceden
# stub edilir (kaynak-zamanı GC çağrısı yok). Kaynak-zamanı döngü başlatma zaten
# MERGEN_DISABLE_FUTURES=true ile atlanır (test/bootstrap modu).
.gcSchedulerEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$gc <- function(...) invisible(NULL)
  suppressMessages(source(file.path(kok, "R", "config_file_store.R"), encoding = "UTF-8", local = env))
  env
}

test_that("gc_scheduler gc çalıştırır ve 300 sn gecikmeyle yeniden zamanlar", {
  env <- .gcSchedulerEnv()
  gc_cagrildi <- new.env(parent = emptyenv()); gc_cagrildi$n <- 0L
  env$gc <- function(verbose = FALSE) { gc_cagrildi$n <- gc_cagrildi$n + 1L; invisible(NULL) }
  rec <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    later = function(func, delay = 0, ...) { rec$delay <- delay; invisible(NULL) },
    .package = "later"
  )
  env$gc_scheduler()
  expect_identical(gc_cagrildi$n, 1L)
  expect_identical(rec$delay, 300)
})

test_that("gc_scheduler gc hata verirse 600 sn gecikmeyle yeniden dener", {
  env <- .gcSchedulerEnv()
  env$gc <- function(verbose = FALSE) stop("gc başarısız")
  rec <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    later = function(func, delay = 0, ...) { rec$delay <- delay; invisible(NULL) },
    .package = "later"
  )
  env$gc_scheduler()
  expect_identical(rec$delay, 600)
})

test_that("start_gc_scheduler_once ilk çağrıda başlatır, ikincide atlar", {
  env <- .gcSchedulerEnv()
  env$gc <- function(...) invisible(NULL)
  testthat::local_mocked_bindings(
    later = function(func, delay = 0, ...) invisible(NULL),
    .package = "later"
  )

  # Türkçe yorum: global bayrağı temizle ve test sonunda eski haline döndür
  flag <- ".mergen_gc_scheduler_started"
  vardi <- exists(flag, envir = .GlobalEnv, inherits = FALSE)
  eski <- if (vardi) get(flag, envir = .GlobalEnv, inherits = FALSE) else NULL
  withr::defer({
    if (vardi) assign(flag, eski, envir = .GlobalEnv)
    else if (exists(flag, envir = .GlobalEnv, inherits = FALSE)) rm(list = flag, envir = .GlobalEnv)
  })
  if (exists(flag, envir = .GlobalEnv, inherits = FALSE)) rm(list = flag, envir = .GlobalEnv)

  ilk <- env$start_gc_scheduler_once()
  expect_true(ilk)
  # Türkçe yorum: bayrak global ortama yazılmış olmalı
  expect_true(isTRUE(get(flag, envir = .GlobalEnv, inherits = FALSE)))

  ikinci <- env$start_gc_scheduler_once()
  expect_false(ikinci)
})
