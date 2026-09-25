# ==============================================================================
# Dosya Yolu: tests/testthat/test-worker-dispatch-cost-behavior.R
# Açıklama: Arka plan iş gönderiminin ana süreci (tüm kullanıcıları) bloklamaması.
#           * tracked_future_promise() otomatik kipte bağımlılık taramasını görev
#             gövdesi başına BİR KEZ yapar; sonraki çağrılar önbellekten gelir ve
#             değerler (kapanış değişkenleri) her çağrıda tazedir. Tarama büyük
#             .GlobalEnv'de saniyeler sürüyor, her sohbet/dosya gönderiminde
#             olay döngüsünü donduruyordu.
#           * Toplu yüklemede dosya özetleri eşzamanlı sınırlanır; tüm işçiler
#             özetle dolup diğer kullanıcıların sohbet istekleri beklemez.
#           * Dosya özeti İZOLE ortamla (explicit) gönderilir; Shiny oturumunu
#             taşıyan çağıran çerçeve serileştirilmez.
# ==============================================================================

.wd_bekle <- function(kosul, sure = 5) {
  son <- Sys.time() + sure
  while (!isTRUE(kosul()) && Sys.time() < son) later::run_now(timeoutSecs = 0.05)
  isTRUE(kosul())
}

.wd_say <- function() {
  wm_env <- environment(tracked_future_promise)
  eski_detect <- get("worker_monitor_detect_task_deps", envir = wm_env)
  eski_expand <- get("worker_monitor_expand_function_globals", envir = wm_env)
  sayac <- new.env(parent = emptyenv())
  sayac$detect <- 0L
  sayac$expand <- 0L
  assign("worker_monitor_detect_task_deps", function(task_fn) {
    sayac$detect <- sayac$detect + 1L
    eski_detect(task_fn)
  }, envir = wm_env)
  assign("worker_monitor_expand_function_globals", function(promise_globals) {
    sayac$expand <- sayac$expand + 1L
    eski_expand(promise_globals)
  }, envir = wm_env)
  withr::defer({
    assign("worker_monitor_detect_task_deps", eski_detect, envir = wm_env)
    assign("worker_monitor_expand_function_globals", eski_expand, envir = wm_env)
  }, envir = parent.frame())
  sayac
}

test_that("otomatik kip taramayı gövde başına bir kez yapar ve değerleri taze okur", {
  skip_if_not_installed("promises")
  skip_if_not_installed("future")
  skip_if_not_installed("later")
  worker_monitor_dep_cache_clear()
  sayac <- .wd_say()

  calistir <- function(deger) {
    kapanis_degeri <- deger
    sonuc <- new.env(parent = emptyenv())
    p <- tracked_future_promise(task_fn = function() kapanis_degeri * 2L,
                                task_type = "unit_dep_cache")
    promises::then(p, onFulfilled = function(v) sonuc$v <- v,
                   onRejected = function(e) sonuc$e <- conditionMessage(e))
    expect_true(.wd_bekle(function() !is.null(sonuc$v) || !is.null(sonuc$e)))
    expect_null(sonuc$e)
    sonuc$v
  }

  expect_identical(calistir(5L), 10L)
  expect_identical(c(sayac$detect, sayac$expand), c(1L, 1L))
  expect_identical(calistir(7L), 14L)
  expect_identical(calistir(9L), 18L)
  expect_identical(c(sayac$detect, sayac$expand), c(1L, 1L))
  worker_monitor_dep_cache_clear()
})

test_that("başarısız bağımlılık taraması önbelleğe alınmaz", {
  worker_monitor_dep_cache_clear()
  wm_env <- environment(tracked_future_promise)
  eski_detect <- get("worker_monitor_detect_task_deps", envir = wm_env)
  assign("worker_monitor_detect_task_deps",
         function(task_fn) list(globals = list(), packages = character(0), ok = FALSE),
         envir = wm_env)
  withr::defer(assign("worker_monitor_detect_task_deps", eski_detect, envir = wm_env))

  gorev <- function() 1L
  worker_monitor_auto_globals("unit_dep_fail", gorev)
  expect_null(worker_monitor_dep_cache_get("unit_dep_fail", gorev))
  worker_monitor_dep_cache_clear()
})

test_that("önbellek ilk taramada tanımsız doğrudan serbest değişkeni sonradan taşır", {
  worker_monitor_dep_cache_clear()
  yap <- function(tanimla) {
    if (tanimla) gec_tanimli <- 3L
    function() if (exists("gec_tanimli")) gec_tanimli else 0L
  }
  worker_monitor_auto_globals("unit_dep_late", yap(FALSE))
  sonraki <- worker_monitor_auto_globals("unit_dep_late", yap(TRUE))
  expect_identical(sonraki$globals$gec_tanimli, 3L)
  worker_monitor_dep_cache_clear()
})

test_that("dosya özeti kuyruğu eşzamanlı iş sayısını sınırlar ve sırayla başlatır", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  withr::local_envvar(c(MERGEN_FILE_SUMMARY_MAX_CONCURRENT = "2"))
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)

  cozuculer <- list()
  baslayan <- character(0)
  is_uret <- function(ad) {
    force(ad)
    function() {
      baslayan <<- c(baslayan, ad)
      promises::promise(function(resolve, reject) cozuculer[[ad]] <<- resolve)
    }
  }
  for (ad in c("a", "b", "c", "d")) env$file_summary_schedule(is_uret(ad))
  expect_identical(baslayan, c("a", "b"))
  expect_identical(env$.FILE_SUMMARY_QUEUE$active, 2L)

  cozuculer$a(TRUE)
  expect_true(.wd_bekle(function() length(baslayan) == 3L))
  expect_identical(baslayan, c("a", "b", "c"))

  cozuculer$b(TRUE); cozuculer$c(TRUE)
  expect_true(.wd_bekle(function() length(baslayan) == 4L))
  cozuculer$d(TRUE)
  expect_true(.wd_bekle(function() identical(env$.FILE_SUMMARY_QUEUE$active, 0L)))
})

test_that("kapanan oturumun kuyruktaki özeti başlatılmaz", {
  skip_if_not_installed("promises")
  withr::local_envvar(c(MERGEN_FILE_SUMMARY_MAX_CONCURRENT = "1"))
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)

  baslayan <- character(0)
  env$file_summary_schedule(function() { baslayan <<- c(baslayan, "canli"); NULL },
                            session = list(isClosed = function() FALSE))
  env$file_summary_schedule(function() { baslayan <<- c(baslayan, "kapali"); NULL },
                            session = list(isClosed = function() TRUE))
  expect_identical(baslayan, "canli")
  expect_identical(env$.FILE_SUMMARY_QUEUE$active, 0L)
  expect_length(env$.FILE_SUMMARY_QUEUE$pending, 0L)
})

test_that("dosya özeti oturum çerçevesini taşımadan explicit kipte gönderilir", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_pipeline.R"), encoding = "UTF-8", local = env)
  yakalanan <- new.env(parent = emptyenv())
  env$showNotification <- function(...) "not-1"
  env$removeNotification <- function(...) invisible(NULL)
  env$showToast <- function(...) invisible(NULL)
  env$session_user_data_put_list_item <- function(...) invisible(NULL)
  env$is_under_mcp_base <- function(p) TRUE
  env$`%...>%` <- function(lhs, rhs) lhs
  env$`%...!%` <- function(lhs, rhs) lhs
  env$tracked_future_promise <- function(task_fn, task_type, session_token, dependency_mode = "auto",
                                         globals = NULL, packages = NULL, ...) {
    yakalanan$mode <- dependency_mode
    yakalanan$globals <- names(globals)
    invisible(NULL)
  }
  worker_monitor_dep_cache_clear()

  oturum <- list(userData = list(user_id = 7L), token = "tok-7", isClosed = function() FALSE)
  sonuc <- env$processAndSummarizeFile(
    list(name = "rapor.txt", datapath = "/kalici/user_7/rapor.txt", size = 10),
    current_user_id = 7L, session = oturum, settings = list(),
    file_manager_data = list(), session_files_reactive = function(...) list(),
    already_persisted = TRUE
  )

  expect_true(env$mergen_file_pipeline_accepted(sonuc))
  expect_identical(yakalanan$mode, "explicit")
  expect_true(all(c("summarize_file_with_llm", "file_name_safe", "dest_safe") %in% yakalanan$globals))
  expect_false(any(c("session", "file_manager_data", "session_files_reactive") %in% yakalanan$globals))
  worker_monitor_dep_cache_clear()
})
