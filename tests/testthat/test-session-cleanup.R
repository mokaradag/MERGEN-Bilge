# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-cleanup.R
# Açıklama: register_session_cleanup_on_end() ve safe_unlink_if_exists()
# fonksiyonlarının oturum kapanış davranışı, onSessionEnded olmayan bağlamda
# güvenli atlama, ekstra callback çalıştırma ve hatalı callback'e rağmen
# diğer callback'lerin koşmasını doğrulayan birim testleri.
# ==============================================================================

local({
  if (!exists("register_session_cleanup_on_end", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "utils_session_cleanup.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

# Sahte Shiny oturumu: onSessionEnded() çağrılarını listeye biriktirir.
.make_fake_session <- function(token = "sess_test_123") {
  env <- new.env(parent = emptyenv())
  env$callbacks <- list()
  env$token <- token
  env$onSessionEnded <- function(fn) {
    env$callbacks[[length(env$callbacks) + 1]] <- fn
  }
  env$trigger_end <- function() {
    for (fn in env$callbacks) {
      try(fn(), silent = TRUE)
    }
  }
  env
}

test_that("register_session_cleanup_on_end extra callback'leri çalıştırır", {
  if (!exists("cleanup_worker_tasks_for_session", envir = globalenv(), inherits = FALSE)) {
    # worker monitor bootstrap tarafından yüklenir; emin değilsek stub tanımla.
    assign("cleanup_worker_tasks_for_session", function(token) invisible(NULL),
           envir = globalenv())
  }

  sess <- .make_fake_session()
  sayac <- 0L

  basari <- register_session_cleanup_on_end(sess, extra_cleanup = list(
    function() sayac <<- sayac + 1L,
    function() sayac <<- sayac + 1L
  ))

  expect_true(basari)
  expect_equal(length(sess$callbacks), 1L)

  sess$trigger_end()
  expect_equal(sayac, 2L)
})

test_that("register_session_cleanup_on_end onSessionEnded yoksa sessizce atlar", {
  bos_env <- list(token = "x")  # onSessionEnded yok
  basari <- register_session_cleanup_on_end(bos_env)
  expect_false(basari)
})

test_that("register_session_cleanup_on_end NULL oturum verildiğinde güvenli davranır", {
  expect_false(register_session_cleanup_on_end(NULL))
  expect_false(register_session_cleanup_on_end(list()))
})

test_that("register_session_cleanup_on_end bir callback çökse diğerleri çalışır", {
  sess <- .make_fake_session()
  sayac <- 0L

  register_session_cleanup_on_end(sess, extra_cleanup = list(
    function() sayac <<- sayac + 1L,
    function() stop("kasitli"),
    function() sayac <<- sayac + 10L
  ))

  sess$trigger_end()
  expect_equal(sayac, 11L)
})

test_that("safe_unlink_if_exists mevcut dosyayı siler", {
  gecici <- tempfile("cleanup_")
  writeLines("deneme", gecici, useBytes = TRUE)
  expect_true(file.exists(gecici))

  sonuc <- safe_unlink_if_exists(gecici)
  expect_true(sonuc)
  expect_false(file.exists(gecici))
})

test_that("safe_unlink_if_exists NULL/boş/olmayan yolu sessizce atlar", {
  expect_false(safe_unlink_if_exists(NULL))
  expect_false(safe_unlink_if_exists(""))
  expect_false(safe_unlink_if_exists(character(0)))
  expect_false(safe_unlink_if_exists("/tmp/kesinlikle_yok_99999"))
  expect_false(safe_unlink_if_exists(NA_character_))
})
