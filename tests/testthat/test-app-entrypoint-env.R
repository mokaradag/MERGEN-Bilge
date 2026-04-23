# ==============================================================================
# Dosya Yolu: tests/testthat/test-app-entrypoint-env.R
# Aciklama: app.R icindeki env/port normalizasyon yardimcilarini dogrular.
# ==============================================================================

restore_test_log_stubs_env <- function() {
  assign("log_info",  function(...) invisible(NULL), envir = globalenv())
  assign("log_warn",  function(...) invisible(NULL), envir = globalenv())
  assign("log_error", function(...) invisible(NULL), envir = globalenv())
  assign("log_debug", function(...) invisible(NULL), envir = globalenv())
}

source_app_safely_env_tests <- function() {
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

load_app_entrypoint_env_helpers <- local({
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

    source_app_safely_env_tests()
    restore_test_log_stubs_env()

    loaded <<- TRUE
    invisible(TRUE)
  }
})

test_that(".env_flag_is_true truthy/falsy degerleri dogru cozer", {
  load_app_entrypoint_env_helpers()

  expect_true(.env_flag_is_true("true"))
  expect_true(.env_flag_is_true(" TRUE "))
  expect_true(.env_flag_is_true("1"))
  expect_true(.env_flag_is_true("yes"))
  expect_true(.env_flag_is_true("on"))

  expect_false(.env_flag_is_true("false"))
  expect_false(.env_flag_is_true(" FALSE "))
  expect_false(.env_flag_is_true("0"))
  expect_false(.env_flag_is_true("no"))
  expect_false(.env_flag_is_true("off"))

  expect_true(.env_flag_is_true("garbled", default = TRUE))
  expect_false(.env_flag_is_true("garbled", default = FALSE))
})

test_that(".normalize_mergen_port yalnizca gecerli aralikta port kabul eder", {
  load_app_entrypoint_env_helpers()

  expect_equal(.normalize_mergen_port("8009"), 8009L)
  expect_equal(.normalize_mergen_port(" 9001 "), 9001L)

  expect_equal(.normalize_mergen_port(NA_character_), 8009L)
  expect_equal(.normalize_mergen_port(""), 8009L)
  expect_equal(.normalize_mergen_port("abc"), 8009L)
  expect_equal(.normalize_mergen_port("0"), 8009L)
  expect_equal(.normalize_mergen_port("-1"), 8009L)
  expect_equal(.normalize_mergen_port("65536"), 8009L)
})