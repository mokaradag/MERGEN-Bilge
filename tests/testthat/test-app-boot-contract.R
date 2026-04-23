# ==============================================================================
# Dosya Yolu: tests/testthat/test-app-boot-contract.R
# Açıklama: app.R giris noktasi icin boot sozlesmelerini, resource-path
# yardimcisini ve run_mergen_app() port fallback davranisini korur.
# Bu test dosyasi app boot islemini yukledikten sonra test ortamindaki log
# stub'larini geri yukleyerek suite'in kalanini kirletmemeye dikkat eder.
# ==============================================================================

restore_test_log_stubs <- function() {
  assign("log_info",  function(...) invisible(NULL), envir = globalenv())
  assign("log_warn",  function(...) invisible(NULL), envir = globalenv())
  assign("log_error", function(...) invisible(NULL), envir = globalenv())
  assign("log_debug", function(...) invisible(NULL), envir = globalenv())
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

    source("app.R", encoding = "UTF-8", local = globalenv())

    # App boot sonrasi gercek logger fonksiyonlari test suite'ine sizmasin.
    restore_test_log_stubs()

    loaded <<- TRUE
    invisible(TRUE)
  }
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