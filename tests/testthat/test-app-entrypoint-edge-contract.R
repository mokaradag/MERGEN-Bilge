# ==============================================================================
# Dosya Yolu: tests/testthat/test-app-entrypoint-edge-contract.R
# Açıklama: app.R giriş noktasındaki küçük ama kritik sınır davranışlarını
# korur: env bayrağı çözümleme, port normalize etme ve boot_step hata sarmalama.
# ==============================================================================

if (!exists("restore_test_log_stubs", mode = "function", inherits = TRUE)) {
  restore_test_log_stubs <- function() {
    assign("log_info",  function(...) invisible(NULL), envir = globalenv())
    assign("log_warn",  function(...) invisible(NULL), envir = globalenv())
    assign("log_error", function(...) invisible(NULL), envir = globalenv())
    assign("log_debug", function(...) invisible(NULL), envir = globalenv())
  }
}

if (!exists("load_app_entrypoint_for_tests", mode = "function", inherits = TRUE)) {
  source_app_safely_for_tests_edge <- function() {
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

      source_app_safely_for_tests_edge()
      restore_test_log_stubs()

      loaded <<- TRUE
      invisible(TRUE)
    }
  })
}

test_that(".env_flag_is_true truthy ve falsy varyantlarini dogru cozer", {
  load_app_entrypoint_for_tests()

  truthy_values <- c("1", "true", "TRUE", " yes ", "On", "t", "Y")
  falsy_values  <- c("0", "false", "FALSE", " no ", "Off", "f", "N")

  for (value in truthy_values) {
    expect_true(.env_flag_is_true(value, default = FALSE), info = value)
  }

  for (value in falsy_values) {
    expect_false(.env_flag_is_true(value, default = TRUE), info = value)
  }

  expect_true(.env_flag_is_true(NA_character_, default = TRUE))
  expect_false(.env_flag_is_true(NULL, default = FALSE))
  expect_true(.env_flag_is_true("belirsiz", default = TRUE))
  expect_false(.env_flag_is_true("belirsiz", default = FALSE))
})

test_that(".normalize_mergen_port sinir ve fallback davranisini korur", {
  load_app_entrypoint_for_tests()

  expect_equal(.normalize_mergen_port("1"), 1L)
  expect_equal(.normalize_mergen_port("8009"), 8009L)
  expect_equal(.normalize_mergen_port("65535"), 65535L)

  expect_equal(.normalize_mergen_port("0"), 8009L)
  expect_equal(.normalize_mergen_port("65536"), 8009L)
  expect_equal(.normalize_mergen_port(NA_integer_), 8009L)
  expect_equal(.normalize_mergen_port("abc"), 8009L)
  expect_equal(.normalize_mergen_port(""), 8009L)
})

test_that("boot_step adli hata sarmalamasi yapar", {
  load_app_entrypoint_for_tests()

  expect_no_error(
    boot_step("sorunsuz", {
      invisible(TRUE)
    })
  )

  expect_error(
    boot_step("deneme", {
      stop("patladı", call. = FALSE)
    }),
    "Boot adımı başarısız \\[deneme\\]: patladı"
  )
})