# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-cleanup-idempotency.R
# Açıklama: register_session_cleanup_on_end() fonksiyonunun aynı oturum için
#           tekrar tekrar callback kaydetmemesini doğrular.
# ==============================================================================

.find_repo_root <- function() {
  adaylar <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (aday in adaylar) {
    if (file.exists(file.path(aday, "app.R")) &&
        dir.exists(file.path(aday, "R"))) {
      return(aday)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.repo_root <- .find_repo_root()

if (!exists("%||%", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(.repo_root, "R", "utils_common.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

if (!exists("register_session_cleanup_on_end", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(.repo_root, "R", "utils_session_cleanup.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

.make_fake_session <- function(token = "sess_idempotent_123") {
  env <- new.env(parent = emptyenv())
  env$callbacks <- list()
  env$token <- token
  env$userData <- new.env(parent = emptyenv())

  env$onSessionEnded <- function(fn) {
    env$callbacks[[length(env$callbacks) + 1L]] <- fn
    invisible(NULL)
  }

  env$trigger_end <- function() {
    for (fn in env$callbacks) {
      try(fn(), silent = TRUE)
    }
    invisible(NULL)
  }

  env
}

test_that("register_session_cleanup_on_end aynı oturumda yalnızca bir callback kaydeder", {
  sess <- .make_fake_session()
  sayac <- 0L

  sonuc1 <- register_session_cleanup_on_end(
    sess,
    extra_cleanup = list(function() sayac <<- sayac + 1L)
  )

  sonuc2 <- register_session_cleanup_on_end(
    sess,
    extra_cleanup = list(function() sayac <<- sayac + 100L)
  )

  expect_true(sonuc1)
  expect_true(sonuc2)

  # İkinci çağrı yeni callback eklememeli.
  expect_equal(length(sess$callbacks), 1L)

  sess$trigger_end()

  # Yalnızca ilk callback çalışmalı.
  expect_equal(sayac, 1L)
})

test_that("register_session_cleanup_on_end userData yoksa güvenli userData ortamı oluşturur", {
  sess <- .make_fake_session()
  sess$userData <- NULL

  sonuc <- register_session_cleanup_on_end(
    sess,
    extra_cleanup = list(function() invisible(TRUE))
  )

  expect_true(sonuc)
  expect_true(is.environment(sess$userData))
  expect_true(isTRUE(sess$userData$mergen_session_cleanup_registered))
  expect_equal(length(sess$callbacks), 1L)
})

test_that("register_session_cleanup_on_end onSessionEnded yoksa FALSE döndürür", {
  eksik_session <- list(token = "eksik")
  sonuc <- register_session_cleanup_on_end(eksik_session)

  expect_false(sonuc)
})