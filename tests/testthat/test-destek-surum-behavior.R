# ==============================================================================
# Dosya Yolu: tests/testthat/test-destek-surum-behavior.R
# Açıklama: R/module_destek_surum.R sürüm bilgilendirme modülünün DAVRANIŞSAL
#           testleri. Bu dosya daha önce hiçbir test tarafından çağrılmıyordu.
#
#           destekSurumUI(): hero + sürüm sekme/içerik konteynerleri (yapı).
#           destekSurumServer(): init anında get_version_history() verisini
#           "initSurumPage" custom message'ı ile istemciye gönderir; veri NULL
#           ise mesaj göndermez. Mesaj, modül session_proxy'si yerine kök
#           MockShinySession üzerinden yakalanır. Gerçek DB GEREKMEZ.
# ==============================================================================

.source_destek_surum_for_test <- function(version_impl = NULL) {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  env$get_version_history <- if (is.function(version_impl)) version_impl else function() {
    list(
      versions = list(list(version = "v1.0", title = "Resmî sürüm")),
      current_version = "v1.0"
    )
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_destek_surum.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# ------------------------------------------------------------------------------
# destekSurumUI yapısı
# ------------------------------------------------------------------------------
testthat::test_that("destekSurumUI hero başlığını ve ad alanlı sekme/içerik konteynerlerini üretir", {
  env <- .source_destek_surum_for_test()
  html <- paste(as.character(env$destekSurumUI("srm")), collapse = "\n")

  testthat::expect_true(grepl("Sürüm Bilgilendirme", html, fixed = TRUE))
  testthat::expect_true(grepl("srm-version_tabs", html, fixed = TRUE))
  testthat::expect_true(grepl("srm-version_content", html, fixed = TRUE))
  testthat::expect_true(grepl("destek-surum-container", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# destekSurumServer: initSurumPage mesajı
# ------------------------------------------------------------------------------
testthat::test_that("destekSurumServer init anında sürüm verisini initSurumPage ile gönderir", {
  env <- .source_destek_surum_for_test()
  rec <- new.env(); rec$msgs <- list()

  shiny::testServer(env$destekSurumServer, args = list(), {
    root <- .subset2(session, "parent")
    root$sendCustomMessage <- function(type, message) {
      rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
      invisible(TRUE)
    }
    session$flushReact()
  })

  tipler <- vapply(rec$msgs, function(m) m$type, character(1))
  testthat::expect_true("initSurumPage" %in% tipler)

  msg <- rec$msgs[[which(tipler == "initSurumPage")[1]]]$message
  testthat::expect_identical(msg$current_version, "v1.0")
  testthat::expect_length(msg$versions, 1L)
  # tabsId/contentId ad alanıyla üretilmeli.
  testthat::expect_true(grepl("version_tabs", msg$tabsId, fixed = TRUE))
  testthat::expect_true(grepl("version_content", msg$contentId, fixed = TRUE))
})

testthat::test_that("destekSurumServer sürüm verisi NULL ise mesaj göndermez", {
  env <- .source_destek_surum_for_test(version_impl = function() NULL)
  rec <- new.env(); rec$msgs <- list()

  shiny::testServer(env$destekSurumServer, args = list(), {
    root <- .subset2(session, "parent")
    root$sendCustomMessage <- function(type, message) {
      rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
      invisible(TRUE)
    }
    session$flushReact()
  })

  tipler <- vapply(rec$msgs, function(m) m$type, character(1))
  testthat::expect_false("initSurumPage" %in% tipler)
})
