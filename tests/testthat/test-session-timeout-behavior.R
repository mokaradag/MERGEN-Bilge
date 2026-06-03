# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-timeout-behavior.R
# Açıklama: R/module_session_timeout.R sessionTimeoutServer() oturum zaman aşımı
#           modülünün DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test
#           tarafından çağrılmıyordu.
#
#           Periyodik kontrol invalidateLater'a dayandığından (testServer'da
#           ilerletilmez) burada gözlemlenebilir davranışlar test edilir:
#           - aktivite input listesiyle hatasız başlatma,
#           - 'Çıkış Yap' (logout_session) oturumu kapatır,
#           - 'Tamam' (continue_session) hatasız çalışır.
#           Gerçek zamanlayıcı/DB/tarayıcı GEREKMEZ.
# ==============================================================================

.source_session_timeout_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_session_timeout.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

testthat::test_that("sessionTimeoutServer aktivite input listesiyle hatasız başlatılır", {
  env <- .source_session_timeout_for_test()
  testthat::expect_no_error(
    shiny::testServer(
      env$sessionTimeoutServer,
      args = list(idle_minutes = 30, activity_inputs = c("user_input", "send_stop_btn")),
      { session$flushReact() }
    )
  )
})

testthat::test_that("logout_session oturumu kapatır", {
  env <- .source_session_timeout_for_test()
  kapandi <- NULL
  shiny::testServer(
    env$sessionTimeoutServer,
    args = list(idle_minutes = 30, activity_inputs = character()),
    {
      session$setInputs(logout_session = 1)
      session$setInputs(logout_session = 2)  # observeEvent flush'ını zorla
      kapandi <<- session$isClosed()
    }
  )
  testthat::expect_true(isTRUE(kapandi))
})

testthat::test_that("continue_session hatasız çalışır ve oturumu kapatmaz", {
  env <- .source_session_timeout_for_test()
  kapandi <- NULL
  testthat::expect_no_error(
    shiny::testServer(
      env$sessionTimeoutServer,
      args = list(idle_minutes = 30, activity_inputs = character()),
      {
        session$setInputs(continue_session = 1)
        session$setInputs(continue_session = 2)
        kapandi <<- session$isClosed()
      }
    )
  )
  # 'Tamam' oturumu kapatmamalı.
  testthat::expect_false(isTRUE(kapandi))
})

testthat::test_that("sessionTimeoutServer varsayılan idle_minutes ile de başlatılır", {
  env <- .source_session_timeout_for_test()
  testthat::expect_no_error(
    shiny::testServer(env$sessionTimeoutServer, args = list(), { session$flushReact() })
  )
})
