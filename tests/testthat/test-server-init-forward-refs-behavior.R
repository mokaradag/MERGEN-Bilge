# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-init-forward-refs-behavior.R
# Açıklama: R/server_init_forward_refs.R serverInitForwardRefs() ileri-referans
#           sarmalayıcılarının DAVRANIŞSAL testleri. Bu dosya davranışsal olarak
#           daha önce test edilmiyordu.
#
#           serverInitForwardRefs(session) gecikmeli bağlama için kapanışlar
#           döndürür: render_welcome_screen / start_new_chat henüz bağlı değilse
#           güvenle NULL döner; send_message bileşeni hazır değilse uyarı toast'ı
#           gösterir. moduleServer/reaktif bağlam GEREKMEZ; kapanışlar doğrudan
#           çağrılır. Gerçek DB/ağ GEREKMEZ.
# ==============================================================================

.source_forward_refs_for_test <- function(toast_recorder = NULL) {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  env$showToast <- function(session, message, type = "info") {
    if (!is.null(toast_recorder)) {
      toast_recorder$msgs[[length(toast_recorder$msgs) + 1L]] <- list(message = message, type = type)
    }
    invisible(NULL)
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_init_forward_refs.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

.fake_session <- function() list(token = "tok-1")

# ------------------------------------------------------------------------------
# Dönen yapı
# ------------------------------------------------------------------------------
testthat::test_that("serverInitForwardRefs beklenen kapanış/ortam listesini döndürür", {
  env <- .source_forward_refs_for_test()
  refs <- env$serverInitForwardRefs(.fake_session())
  testthat::expect_true(is.list(refs))
  testthat::expect_true(all(c(
    "welcome_fns", "render_welcome_screen", "start_new_chat",
    "send_message_fns", "send_message"
  ) %in% names(refs)))
  testthat::expect_true(is.environment(refs$welcome_fns))
  testthat::expect_true(is.environment(refs$send_message_fns))
  testthat::expect_true(is.function(refs$render_welcome_screen))
  testthat::expect_true(is.function(refs$send_message))
})

# ------------------------------------------------------------------------------
# render_welcome_screen / start_new_chat gecikmeli bağlama
# ------------------------------------------------------------------------------
testthat::test_that("render_welcome_screen bağlanmadan önce güvenle NULL döner", {
  env <- .source_forward_refs_for_test()
  refs <- env$serverInitForwardRefs(.fake_session())
  testthat::expect_null(refs$render_welcome_screen("herhangi", 1))
  testthat::expect_null(refs$start_new_chat())
})

testthat::test_that("render_welcome_screen bağlandıktan sonra hedef fonksiyonu argümanlarla çağırır", {
  env <- .source_forward_refs_for_test()
  refs <- env$serverInitForwardRefs(.fake_session())
  rec <- new.env(); rec$args <- NULL
  refs$welcome_fns$render_welcome_screen <- function(...) { rec$args <- list(...); "render-ok" }

  sonuc <- refs$render_welcome_screen("saved", replace_existing = FALSE)
  testthat::expect_identical(sonuc, "render-ok")
  testthat::expect_identical(rec$args[[1]], "saved")
  testthat::expect_false(rec$args$replace_existing)
})

testthat::test_that("start_new_chat bağlandıktan sonra hedef fonksiyonu çağırır", {
  env <- .source_forward_refs_for_test()
  refs <- env$serverInitForwardRefs(.fake_session())
  rec <- new.env(); rec$called <- 0L
  refs$welcome_fns$start_new_chat <- function(...) { rec$called <- rec$called + 1L; invisible(NULL) }
  refs$start_new_chat()
  testthat::expect_identical(rec$called, 1L)
})

# ------------------------------------------------------------------------------
# send_message gecikmeli bağlama + hazır-değil uyarısı
# ------------------------------------------------------------------------------
testthat::test_that("send_message bileşen hazır değilken uyarı toast'ı gösterir ve NULL döner", {
  rec <- new.env(); rec$msgs <- list()
  env <- .source_forward_refs_for_test(toast_recorder = rec)
  refs <- env$serverInitForwardRefs(.fake_session())

  sonuc <- refs$send_message("merhaba")
  testthat::expect_null(sonuc)
  mesajlar <- vapply(rec$msgs, function(m) m$message, character(1))
  testthat::expect_true(any(grepl("henüz hazır değil", mesajlar, fixed = TRUE)))
})

testthat::test_that("send_message bağlandıktan sonra hedef fonksiyonu çağırır ve toast göstermez", {
  rec <- new.env(); rec$msgs <- list()
  env <- .source_forward_refs_for_test(toast_recorder = rec)
  refs <- env$serverInitForwardRefs(.fake_session())

  gonderim <- new.env(); gonderim$prompt <- NULL
  refs$send_message_fns$send_message <- function(p) { gonderim$prompt <- p; "gonderildi" }

  sonuc <- refs$send_message("Türkiye'nin başkenti?")
  testthat::expect_identical(sonuc, "gonderildi")
  testthat::expect_identical(gonderim$prompt, "Türkiye'nin başkenti?")
  # Hazır olduğunda uyarı toast'ı çıkmamalı.
  testthat::expect_length(rec$msgs, 0L)
})
