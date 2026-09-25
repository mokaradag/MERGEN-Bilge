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
  sonuc <- worker_monitor_auto_globals("unit_dep_fail", gorev)
  expect_false(sonuc$ok)
  expect_null(worker_monitor_dep_cache_get("unit_dep_fail", gorev))
  worker_monitor_dep_cache_clear()
})

test_that("aynı gövdeli görevde bağlı yardımcı değişirse önbellek yeniden tarar", {
  worker_monitor_dep_cache_clear()
  withr::defer(worker_monitor_dep_cache_clear())
  assign(".wd_derin_a", function() 1L, envir = globalenv())
  assign(".wd_derin_b", function() 2L, envir = globalenv())
  assign(".wd_yardimci_a", function() .wd_derin_a(), envir = globalenv())
  assign(".wd_yardimci_b", function() .wd_derin_b(), envir = globalenv())
  withr::defer(rm(list = c(".wd_derin_a", ".wd_derin_b", ".wd_yardimci_a", ".wd_yardimci_b"),
                  envir = globalenv()))
  yap <- function(yardimci) {
    force(yardimci)
    function() yardimci()
  }

  ilk <- worker_monitor_auto_globals("unit_dep_ident", yap(.wd_yardimci_a))
  expect_true(".wd_derin_a" %in% names(ilk$globals))
  ikinci <- worker_monitor_auto_globals("unit_dep_ident", yap(.wd_yardimci_b))
  expect_true(".wd_derin_b" %in% names(ikinci$globals))
  # Aynı yardımcıyla tekrar çağrı önbellekten gelir.
  sayac <- .wd_say()
  worker_monitor_auto_globals("unit_dep_ident", yap(.wd_yardimci_b))
  expect_identical(c(sayac$detect, sayac$expand), c(0L, 0L))
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
  env$file_summary_pool_size <- function() 4L
  env$file_summary_free_workers <- function() NA_integer_

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
  skip_if_not_installed("later")
  withr::local_envvar(c(MERGEN_FILE_SUMMARY_MAX_CONCURRENT = "1"))
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)
  env$file_summary_pool_size <- function() 4L
  env$file_summary_free_workers <- function() NA_integer_

  baslayan <- character(0)
  coz <- NULL
  kapali <- FALSE
  env$file_summary_schedule(function() {
    baslayan <<- c(baslayan, "ilk")
    promises::promise(function(resolve, reject) coz <<- resolve)
  }, session = list(isClosed = function() FALSE))
  # İlk iş sürerken sıraya giren oturum, sırası gelmeden kapanır.
  env$file_summary_schedule(function() { baslayan <<- c(baslayan, "kapanan"); NULL },
                            session = list(isClosed = function() kapali))
  expect_length(env$.FILE_SUMMARY_QUEUE$pending, 1L)
  kapali <- TRUE
  coz(TRUE)
  expect_true(.wd_bekle(function() identical(env$.FILE_SUMMARY_QUEUE$active, 0L) &&
                          length(env$.FILE_SUMMARY_QUEUE$pending) == 0L))
  expect_identical(baslayan, "ilk")
  expect_length(env$.FILE_SUMMARY_QUEUE$pending, 0L)
})

test_that("özet sınırı işçi havuzundan türetilir ve bir işçi etkileşimli işe ayrılır", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)
  withr::local_envvar(c(MERGEN_FILE_SUMMARY_MAX_CONCURRENT = "2"))
  havuz <- 1L
  env$file_summary_pool_size <- function() havuz
  sinir <- function(n) { havuz <<- n; env$file_summary_effective_limit() }
  expect_identical(c(sinir(1L), sinir(2L), sinir(3L), sinir(8L)), c(1L, 1L, 2L, 2L))

  # İki işçili havuzda tek boş işçi etkileşimli işe kalır; özet başlamaz.
  havuz <- 2L
  bos <- 1L
  env$file_summary_free_workers <- function() bos
  expect_false(env$file_summary_has_capacity())
  bos <- 2L
  expect_true(env$file_summary_has_capacity())
  # Tek işçili havuz bölünemez: işçi boşsa tek özet başlar.
  havuz <- 1L
  bos <- 1L
  expect_true(env$file_summary_has_capacity())
  bos <- 0L
  expect_false(env$file_summary_has_capacity())
})

test_that("işçiler doluyken bekleyen özet kapasite açılınca kendiliğinden başlar", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  withr::local_envvar(c(MERGEN_FILE_SUMMARY_MAX_CONCURRENT = "2"))
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)
  env$file_summary_pool_size <- function() 3L
  bos <- 1L
  env$file_summary_free_workers <- function() bos

  baslayan <- 0L
  env$file_summary_schedule(function() { baslayan <<- baslayan + 1L; NULL })
  expect_identical(baslayan, 0L)
  expect_true(env$.FILE_SUMMARY_QUEUE$pump_scheduled)
  bos <- 3L
  expect_true(.wd_bekle(function() identical(baslayan, 1L), sure = 5))
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

test_that("açılış ısıtmasından sonra ilk dosya özeti bağımlılık taraması yapmaz", {
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
    yakalanan$dosya <- globals$file_name_safe
    invisible(NULL)
  }
  worker_monitor_dep_cache_clear()
  withr::defer(worker_monitor_dep_cache_clear())

  expect_true(env$file_summary_warm_dependencies())
  sayac <- .wd_say()
  oturum <- list(userData = list(user_id = 7L), token = "tok-7", isClosed = function() FALSE)
  env$processAndSummarizeFile(
    list(name = "rapor.txt", datapath = "/kalici/user_7/rapor.txt", size = 10),
    current_user_id = 7L, session = oturum, settings = list(),
    file_manager_data = list(), session_files_reactive = function(...) list(),
    already_persisted = TRUE
  )

  expect_identical(c(sayac$detect, sayac$expand), c(0L, 0L))
  expect_identical(yakalanan$mode, "explicit")
  expect_identical(yakalanan$dosya, "rapor.txt")
})

test_that("dosya özeti bekleyen kuyruğu sınırlıdır ve kapanan oturum kaydı bırakılır", {
  skip_if_not_installed("promises")
  withr::local_envvar(c(MERGEN_FILE_SUMMARY_MAX_CONCURRENT = "1", MERGEN_FILE_SUMMARY_MAX_QUEUE = "2"))
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)

  bekleyen_is <- function() promises::promise(function(resolve, reject) NULL)
  kapali <- FALSE
  kapanan_oturum <- list(isClosed = function() kapali)
  expect_true(env$file_summary_schedule(bekleyen_is))
  expect_true(env$file_summary_schedule(bekleyen_is, session = kapanan_oturum))
  expect_true(env$file_summary_schedule(bekleyen_is))
  expect_false(env$file_summary_schedule(bekleyen_is))
  expect_identical(env$.FILE_SUMMARY_QUEUE$rejected_total, 1L)
  expect_length(env$.FILE_SUMMARY_QUEUE$pending, 2L)

  kapali <- TRUE
  expect_true(env$file_summary_schedule(bekleyen_is))
  expect_length(env$.FILE_SUMMARY_QUEUE$pending, 2L)
  expect_false(any(vapply(env$.FILE_SUMMARY_QUEUE$pending,
                          function(k) identical(k$session, kapanan_oturum), logical(1))))
})

test_that("başarısız bağımlılık taramasında dosya özeti explicit değil auto kipte gönderilir", {
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
  env$worker_monitor_auto_globals <- function(task_type, task_fn, ...) {
    list(globals = list(), packages = character(0), ok = FALSE)
  }
  env$tracked_future_promise <- function(task_fn, task_type, session_token, dependency_mode = "auto",
                                         globals = NULL, packages = NULL, ...) {
    yakalanan$mode <- dependency_mode
    yakalanan$globals <- globals
    invisible(NULL)
  }
  oturum <- list(userData = list(user_id = 7L), token = "tok-7", isClosed = function() FALSE)
  env$processAndSummarizeFile(
    list(name = "rapor.txt", datapath = "/kalici/user_7/rapor.txt", size = 10),
    current_user_id = 7L, session = oturum, settings = list(),
    file_manager_data = list(), session_files_reactive = function(...) list(),
    already_persisted = TRUE
  )
  expect_identical(yakalanan$mode, "auto")
  expect_null(yakalanan$globals)
})

test_that("oturum kimliği değişirse kuyruktaki özet başlamaz ve sonuç yeni kullanıcıya yazılmaz", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_pipeline.R"), encoding = "UTF-8", local = env)
  olay <- new.env(parent = emptyenv())
  olay$yazilan <- character(0)
  olay$gonderim <- 0L
  olay$kapanan <- 0L
  olay$toast <- 0L
  env$showNotification <- function(...) "not-1"
  env$removeNotification <- function(...) olay$kapanan <- olay$kapanan + 1L
  env$showToast <- function(...) olay$toast <- olay$toast + 1L
  env$session_user_data_put_list_item <- function(session, alan, ...) {
    olay$yazilan <- c(olay$yazilan, alan)
    invisible(NULL)
  }
  env$is_under_mcp_base <- function(p) TRUE
  env$`%...>%` <- promises::`%...>%`
  env$`%...!%` <- promises::`%...!%`
  env$tracked_future_promise <- function(...) {
    olay$gonderim <- olay$gonderim + 1L
    promises::promise_resolve(list(summary = "ozet", dest = "/kalici/user_7/rapor.txt", ext = "txt"))
  }
  bekleyen <- NULL
  env$file_summary_schedule <- function(start_fn, session = NULL) {
    bekleyen <<- start_fn
    TRUE
  }
  dosya <- list(name = "rapor.txt", datapath = "/kalici/user_7/rapor.txt", size = 10)
  oturum <- list(userData = new.env(), token = "tok-7", isClosed = function() FALSE)
  oturum$userData$user_id <- 7L

  # 1) Özet sıradayken oturum B'ye geçer: iş hiç başlamaz.
  env$processAndSummarizeFile(dosya, current_user_id = 7L, session = oturum, settings = list(),
                              file_manager_data = list(), session_files_reactive = function(...) list(),
                              already_persisted = TRUE)
  oturum$userData$user_id <- 8L
  cikti <- utils::capture.output(bekleyen())
  expect_identical(olay$gonderim, 0L)
  expect_identical(olay$kapanan, 1L)
  expect_false("file_summaries" %in% olay$yazilan)

  # 2) Özet işçideyken oturum B'ye geçer: sonuç B'nin oturumuna yazılmaz.
  oturum$userData$user_id <- 7L
  env$processAndSummarizeFile(dosya, current_user_id = 7L, session = oturum, settings = list(),
                              file_manager_data = list(), session_files_reactive = function(...) list(),
                              already_persisted = TRUE)
  bekleyen()
  oturum$userData$user_id <- 8L
  cikti <- utils::capture.output(tamam <- .wd_bekle(function() olay$kapanan >= 2L))
  expect_true(tamam)
  expect_identical(olay$gonderim, 1L)
  expect_false("file_summaries" %in% olay$yazilan)
  expect_identical(olay$toast, 0L)

  # 3) Kimlik aynı kalırsa sonuç yazılır.
  oturum$userData$user_id <- 7L
  env$processAndSummarizeFile(dosya, current_user_id = 7L, session = oturum, settings = list(),
                              file_manager_data = list(), session_files_reactive = function(...) list(),
                              already_persisted = TRUE)
  bekleyen()
  expect_true(.wd_bekle(function() "file_summaries" %in% olay$yazilan))
})

test_that("özet kuyruğu doluysa dosya kabul edilir, bildirim kapanır ve kullanıcı uyarılır", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_pipeline.R"), encoding = "UTF-8", local = env)
  olay <- new.env(parent = emptyenv())
  olay$kapanan <- character(0)
  olay$uyari <- character(0)
  olay$gonderim <- 0L
  env$showNotification <- function(...) "not-1"
  env$removeNotification <- function(id, ...) olay$kapanan <- c(olay$kapanan, id)
  env$showToast <- function(session, message, type = "info", ...) olay$uyari <- c(olay$uyari, type)
  env$session_user_data_put_list_item <- function(...) invisible(NULL)
  env$is_under_mcp_base <- function(p) TRUE
  env$file_summary_schedule <- function(start_fn, session = NULL) FALSE
  env$tracked_future_promise <- function(...) {
    olay$gonderim <- olay$gonderim + 1L
    invisible(NULL)
  }

  oturum <- list(userData = list(user_id = 7L), token = "tok-7", isClosed = function() FALSE)
  cikti <- utils::capture.output(
    sonuc <- env$processAndSummarizeFile(
      list(name = "rapor.txt", datapath = "/kalici/user_7/rapor.txt", size = 10),
      current_user_id = 7L, session = oturum, settings = list(),
      file_manager_data = list(), session_files_reactive = function(...) list(),
      already_persisted = TRUE
    )
  )

  expect_true(env$mergen_file_pipeline_accepted(sonuc))
  expect_identical(olay$gonderim, 0L)
  expect_identical(olay$kapanan, "not-1")
  expect_identical(olay$uyari, "warning")
  expect_true(any(grepl("[FILE PIPELINE]", cikti, fixed = TRUE)))
})

test_that("eşzamanlı özet gönderim hatası bildirimi kapatır, uyarır ve kuyruk yerini bırakır", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  withr::local_envvar(c(MERGEN_FILE_SUMMARY_MAX_CONCURRENT = "1"))
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_file_summary_queue.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_file_pipeline.R"), encoding = "UTF-8", local = env)
  olay <- new.env(parent = emptyenv())
  olay$kapanan <- character(0)
  olay$uyari <- character(0)
  env$showNotification <- function(...) "not-1"
  env$removeNotification <- function(id, ...) olay$kapanan <- c(olay$kapanan, id)
  env$showToast <- function(session, message, type = "info", ...) olay$uyari <- c(olay$uyari, type)
  env$session_user_data_put_list_item <- function(...) invisible(NULL)
  env$is_under_mcp_base <- function(p) TRUE
  env$`%...>%` <- promises::`%...>%`
  env$`%...!%` <- promises::`%...!%`
  env$tracked_future_promise <- function(...) stop("havuz hazır değil")
  worker_monitor_dep_cache_clear()
  withr::defer(worker_monitor_dep_cache_clear())

  oturum <- list(userData = list(user_id = 7L), token = "tok-7", isClosed = function() FALSE)
  cikti <- utils::capture.output({
    sonuc <- env$processAndSummarizeFile(
      list(name = "rapor.txt", datapath = "/kalici/user_7/rapor.txt", size = 10),
      current_user_id = 7L, session = oturum, settings = list(),
      file_manager_data = list(), session_files_reactive = function(...) list(),
      already_persisted = TRUE
    )
    tamam <- .wd_bekle(function() identical(env$.FILE_SUMMARY_QUEUE$active, 0L) &&
                         length(olay$uyari) > 0L)
  })

  expect_true(tamam)
  expect_true(env$mergen_file_pipeline_accepted(sonuc))
  expect_identical(olay$kapanan, "not-1")
  expect_identical(olay$uyari, "warning")
  expect_true(any(grepl("[FILE PIPELINE]", cikti, fixed = TRUE)))
})
