# ==============================================================================
# Dosya Yolu: tests/testthat/test-feedback-behavior.R
# Açıklama: R/module_feedback.R feedbackServer() ve feedbackUI() DAVRANIŞSAL
#           testleri. Bu dosya daha önce hiçbir test tarafından çağrılmıyordu.
#
#           feedbackServer() bir modal kontrol listesi (open) döndürür. open()
#           geri bildirim türüne (like/dislike) göre başlık ve etiket setini
#           belirler ve istemciye custom message gönderir. Modül session_proxy
#           kullandığından mesajlar kök MockShinySession üzerinden yakalanır.
#           save_feedback_to_db_extended / resolve_effective_user_id stub'lanır;
#           gerçek DB GEREKMEZ.
# ==============================================================================

.source_feedback_for_test <- function(user_id_impl = NULL, save_recorder = NULL) {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  env$resolve_effective_user_id <- if (is.function(user_id_impl)) user_id_impl else function(session, current_user_id) 5L
  env$save_feedback_to_db_extended <- if (is.function(save_recorder)) save_recorder else function(...) invisible(TRUE)
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_feedback.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Kök session üzerinden custom message yakalayan yardımcı (proxy değil).
.capture_root_messages <- function(session, rec) {
  root <- .subset2(session, "parent")
  root$sendCustomMessage <- function(type, message) {
    rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
    invisible(TRUE)
  }
}

.msg_of_type <- function(rec, type) {
  for (m in rec$msgs) if (identical(m$type, type)) return(m$message)
  NULL
}

# ------------------------------------------------------------------------------
# feedbackUI yapısı
# ------------------------------------------------------------------------------
testthat::test_that("feedbackUI ad alanlı modal yapısını ve Türkçe butonları üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_feedback_for_test()

  html <- paste(as.character(env$feedbackUI("fb")), collapse = "\n")
  testthat::expect_true(grepl("fb-feedback_modal_container", html, fixed = TRUE))
  testthat::expect_true(grepl("fb-tag_buttons", html, fixed = TRUE))
  testthat::expect_true(grepl("Gönder", html, fixed = TRUE))
  testthat::expect_true(grepl("İptal", html, fixed = TRUE))
  testthat::expect_true(grepl("Geri Bildirim", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# open_modal: like / dislike karar mantığı
# ------------------------------------------------------------------------------
testthat::test_that("feedbackServer open() beğeni türünde 'Beğendiniz' başlığı ve like etiketleri kurar", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- .source_feedback_for_test()
  rec <- new.env(); rec$msgs <- list()

  shiny::testServer(env$feedbackServer, args = list(current_user_id = 5L), {
    .capture_root_messages(session, rec)
    session$returned$open("msg-1", "like")
  })

  baslik <- .msg_of_type(rec, "updateFeedbackTitle")
  testthat::expect_false(is.null(baslik))
  testthat::expect_true(grepl("Bu Yanıtı Beğendiniz", baslik$html, fixed = TRUE))
  testthat::expect_true(grepl("fa-thumbs-up", baslik$html, fixed = TRUE))

  etiketler <- .msg_of_type(rec, "updateFeedbackTags")
  testthat::expect_false(is.null(etiketler))
  testthat::expect_true(grepl("tag-like", etiketler$html, fixed = TRUE))
  # Beğeni etiket seti Türkçe değerlerini içermeli.
  testthat::expect_true(grepl("Açık ve net", etiketler$html, fixed = TRUE))
  testthat::expect_true(grepl("Faydalı", etiketler$html, fixed = TRUE))
  testthat::expect_false(grepl("Yanıltıcı", etiketler$html, fixed = TRUE))  # dislike etiketi olmamalı
})

testthat::test_that("feedbackServer open() beğenmeme türünde 'Geri Bildirim' başlığı ve dislike etiketleri kurar", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- .source_feedback_for_test()
  rec <- new.env(); rec$msgs <- list()

  shiny::testServer(env$feedbackServer, args = list(current_user_id = 5L), {
    .capture_root_messages(session, rec)
    session$returned$open("msg-2", "dislike")
  })

  baslik <- .msg_of_type(rec, "updateFeedbackTitle")
  testthat::expect_true(grepl("Bu Yanıt Hakkında Geri Bildirim", baslik$html, fixed = TRUE))
  testthat::expect_true(grepl("fa-comment-dots", baslik$html, fixed = TRUE))

  etiketler <- .msg_of_type(rec, "updateFeedbackTags")
  testthat::expect_true(grepl("tag-dislike", etiketler$html, fixed = TRUE))
  testthat::expect_true(grepl("Yanıltıcı", etiketler$html, fixed = TRUE))
  testthat::expect_true(grepl("Eksik bilgi", etiketler$html, fixed = TRUE))
  testthat::expect_false(grepl("Faydalı", etiketler$html, fixed = TRUE))  # like etiketi olmamalı
})

testthat::test_that("feedbackServer open() iptal geri çağrısını oturum verisine kaydeder", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- .source_feedback_for_test()
  rec <- new.env(); rec$msgs <- list()
  cb <- function() invisible("iptal edildi")

  shiny::testServer(env$feedbackServer, args = list(current_user_id = 5L), {
    .capture_root_messages(session, rec)
    session$returned$open("msg-3", "like", on_cancel = cb)
    # open_modal on_cancel'i session$userData'ya yazar.
    testthat::expect_true(is.function(session$userData$feedback_cancel_callback))
    testthat::expect_identical(session$userData$feedback_cancel_callback(), "iptal edildi")
  })
})

# ------------------------------------------------------------------------------
# submit: kullanıcı kimliği hazır değilse DB'ye yazılmaz
# ------------------------------------------------------------------------------
testthat::test_that("submit kullanıcı kimliği hazır değilken (0) DB'ye geri bildirim yazmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })

  save_rec <- new.env(); save_rec$n <- 0L
  env <- .source_feedback_for_test(
    user_id_impl = function(session, current_user_id) 0L,  # hazır değil
    save_recorder = function(...) { save_rec$n <- save_rec$n + 1L; invisible(TRUE) }
  )

  shiny::testServer(env$feedbackServer, args = list(current_user_id = 0L), {
    session$returned$open("msg-x", "like")   # current_message_id/type kurulur
    session$setInputs(submit = 1)
    session$setInputs(submit = 2)            # observeEvent flush'ını zorla
    # Kullanıcı kimliği 0 -> kayıt fonksiyonu HİÇ çağrılmamalı.
    testthat::expect_identical(save_rec$n, 0L)
  })
})
