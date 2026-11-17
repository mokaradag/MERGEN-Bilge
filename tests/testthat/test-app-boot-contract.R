# ==============================================================================
# Dosya Yolu: tests/testthat/test-app-boot-contract.R
# Açıklama: app.R giris noktasi icin boot sozlesmelerini, resource-path
# yardimcisini ve run_mergen_app() port fallback davranisini korur.
# Bu test dosyasi app boot sonrasinda test ortamindaki log stub'larini geri
# yukler ve Windows VM'deki "was built under R version" uyarilarini susturur.
# ==============================================================================

restore_test_log_stubs <- function() {
  assign("log_info",  function(...) invisible(NULL), envir = globalenv())
  assign("log_warn",  function(...) invisible(NULL), envir = globalenv())
  assign("log_error", function(...) invisible(NULL), envir = globalenv())
  assign("log_debug", function(...) invisible(NULL), envir = globalenv())
}

source_app_safely_for_tests <- function() {
  withCallingHandlers(
    source("app.R", encoding = "UTF-8", local = globalenv()),
    warning = function(w) {
      msg <- conditionMessage(w)

      if (grepl("was built under R version", msg, fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
}

load_app_entrypoint_for_tests <- local({
  loaded <- FALSE

  function(force_reload = FALSE) {
    if (loaded && !isTRUE(force_reload)) {
      return(invisible(TRUE))
    }

    withr::local_dir(repo_root_for_tests)
    withr::local_envvar(
      c(
        MERGEN_RUN_APP = "false",
        MERGEN_DISABLE_FUTURES = "true",
        MERGEN_SQL_LOADER_STRICT = "false",
        LOCAL_LLM_ENDPOINT = "http://test.local/v1",
        DB_DSN = "test-dsn",
        AI_KEYS_MASTER = "test-master-key-boot-placeholder"
      )
    )

    source_app_safely_for_tests()

    # App boot sonrasi gercek logger fonksiyonlari test suite'ine sizmasin.
    restore_test_log_stubs()

    loaded <<- TRUE
    invisible(TRUE)
  }
})

# Bu test dosyadaki İLK yüklemeyi ölçer: app.R kaynak olarak yüklenirken
# (test/araç süreci) JIT seviyesi değişmemelidir; JIT yalnızca üretim başlatma
# yolunda (run_mergen_app) kapatılır ve runApp bitince geri yüklenir.
test_that("app.R kaynak yüklemesi JIT seviyesini değiştirmez; üretim başlatması kapatıp geri yükler", {
  withr::local_envvar(R_ENABLE_JIT = NA)
  onceki <- compiler::enableJIT(3)
  withr::defer(compiler::enableJIT(onceki))
  load_app_entrypoint_for_tests()
  expect_equal(compiler::enableJIT(-1), 3)

  calisirken <- NULL
  testthat::local_mocked_bindings(
    runApp = function(...) { calisirken <<- compiler::enableJIT(-1); invisible("ok") },
    .package = "shiny"
  )
  run_mergen_app(host = "127.0.0.1", port = 8009L, launch.browser = FALSE, quiet = TRUE)
  expect_equal(calisirken, 0)
  expect_equal(compiler::enableJIT(-1), 3)

  # Operatör R_ENABLE_JIT verdiyse başlatma seviyeye dokunmaz.
  withr::local_envvar(R_ENABLE_JIT = "3")
  run_mergen_app(host = "127.0.0.1", port = 8009L, launch.browser = FALSE, quiet = TRUE)
  expect_equal(calisirken, 3)
})

test_that("app.R boot helperlari tanimlanir ve shiny.appobj uretilir", {
  load_app_entrypoint_for_tests()

  expect_true(exists("validate_boot_state", envir = globalenv(), mode = "function", inherits = FALSE))
  expect_true(exists("create_mergen_app", envir = globalenv(), mode = "function", inherits = FALSE))
  expect_true(exists("run_mergen_app", envir = globalenv(), mode = "function", inherits = FALSE))
  expect_true(exists("safe_add_resource_path", envir = globalenv(), mode = "function", inherits = FALSE))

  expect_no_error(validate_boot_state())
  expect_s3_class(create_mergen_app(), "shiny.appobj")
})

test_that("validate_boot_state eksik boot nesnelerinde net hata verir", {
  load_app_entrypoint_for_tests()

  eksik_env <- new.env(parent = emptyenv())
  expect_error(validate_boot_state(eksik_env), "safe_source")

  assign("safe_source", function(...) invisible(TRUE), envir = eksik_env)
  expect_error(validate_boot_state(eksik_env), "ui")

  assign("ui", shiny::div("ok"), envir = eksik_env)
  expect_error(validate_boot_state(eksik_env), "server")

  assign(
    "server",
    function(input, output, session) invisible(NULL),
    envir = eksik_env
  )

  expect_no_error(validate_boot_state(eksik_env))
})

test_that("safe_add_resource_path eksik klasorde FALSE dondurur", {
  load_app_entrypoint_for_tests()

  missing_dir <- file.path(tempdir(), "olmayan_klasor_123456")
  expect_false(dir.exists(missing_dir))

  expect_warning(
    expect_false(safe_add_resource_path("olmayan_prefix", missing_dir)),
    "Kaynak yolu atlandı"
  )
})

test_that("safe_add_resource_path duplicate warning durumunda sessiz kalir", {
  load_app_entrypoint_for_tests()

  mevcut_dir <- withr::local_tempdir(pattern = "mergen-resource-")

  testthat::local_mocked_bindings(
    addResourcePath = function(prefix, directory) {
      warning("resource path already exists")
      invisible(NULL)
    },
    .package = "shiny"
  )

  expect_silent(
    expect_true(safe_add_resource_path("mevcut_prefix", mevcut_dir))
  )
})

test_that("run_mergen_app gecersiz portta 8009 fallback kullanir", {
  load_app_entrypoint_for_tests()

  captured <- new.env(parent = emptyenv())
  captured$host <- NULL
  captured$port <- NULL
  captured$app_class <- NULL
  captured$launch_browser <- NULL
  captured$quiet <- NULL

  testthat::local_mocked_bindings(
    runApp = function(appObj, host, port, launch.browser, quiet) {
      captured$host <- host
      captured$port <- port
      captured$app_class <- class(appObj)
      captured$launch_browser <- launch.browser
      captured$quiet <- quiet
      invisible("ok")
    },
    .package = "shiny"
  )

  expect_no_error(
    run_mergen_app(
      host = "127.0.0.1",
      port = NA_integer_,
      launch.browser = FALSE,
      quiet = TRUE
    )
  )

  expect_equal(captured$host, "127.0.0.1")
  expect_equal(captured$port, 8009L)
  expect_true("shiny.appobj" %in% captured$app_class)
  expect_false(captured$launch_browser)
  expect_true(captured$quiet)
})
# Açılışta SSE bağımlılık ısıtması başarısız ya da eksik kalırsa sessiz geçilmez;
# tanı maskelenmiş olarak loglanır ve açılış durmaz.
test_that("SSE bağımlılık ısıtması başarısız ya da eksikse açılış uyarısı maskeli loglanır", {
  load_app_entrypoint_for_tests()
  adlar <- c("mb_presence_initialize", "init_db_pool_once", "close_db_pool_once",
             "file_summary_warm_dependencies", "mergen_true_streaming_warm_dependencies")
  onceki <- lapply(adlar, function(ad) get0(ad, envir = globalenv(), inherits = FALSE))
  names(onceki) <- adlar
  withr::defer(for (ad in adlar) {
    if (is.null(onceki[[ad]])) suppressWarnings(rm(list = ad, envir = globalenv())) else assign(ad, onceki[[ad]], envir = globalenv())
  })
  assign("mb_presence_initialize", function() invisible(NULL), envir = globalenv())
  assign("init_db_pool_once", function(...) invisible(NULL), envir = globalenv())
  assign("close_db_pool_once", NULL, envir = globalenv())
  assign("file_summary_warm_dependencies", function() invisible(TRUE), envir = globalenv())

  app <- create_mergen_app()
  assign("mergen_true_streaming_warm_dependencies", function() invisible(FALSE), envir = globalenv())
  eksik <- paste(capture.output(app$onStart()), collapse = "\n")
  expect_match(eksik, "SSE bağımlılık ısıtması tamamlanmadı", fixed = TRUE)

  gizli <- paste0("gi", "zli")
  assign("mergen_true_streaming_warm_dependencies", function() stop(paste0("tarama hatası PWD='", gizli, "'")),
         envir = globalenv())
  hata <- paste(capture.output(expect_no_error(app$onStart())), collapse = "\n")
  expect_match(hata, "SSE bağımlılık ısıtması hata verdi", fixed = TRUE)
  expect_false(grepl(gizli, hata, fixed = TRUE))

  assign("mergen_true_streaming_warm_dependencies", function() invisible(TRUE), envir = globalenv())
  tamam <- paste(capture.output(app$onStart()), collapse = "\n")
  expect_false(grepl("SSE bağımlılık", tamam, fixed = TRUE))
})
