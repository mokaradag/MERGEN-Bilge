# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-actions-behavior.R
# Açıklama: R/module_chat_actions.R chatActionsInit() beğeni/beğenmeme/yeniden
#           oluştur gözlemcilerinin DAVRANIŞSAL testleri. Bu dosya daha önce
#           hiçbir test tarafından çağrılmıyordu.
#
#           chatActionsInit moduleServer DEĞİLDİR; session doğrudan iletilir.
#           Gözlemciler prime-then-set ile tetiklenir; yan etkiler enjekte edilen
#           stub'larla (send_message_fn, feedback_modal$open) ve kaydedici
#           global'lerle (showToast, remove_feedback_from_db) ölçülür.
#           resolve_effective_user_id stub'lanır. Gerçek DB/LLM GEREKMEZ.
# ==============================================================================

.source_chat_actions_for_test <- function(user_id = 5L) {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  rec <- new.env()
  rec$toasts <- list()
  rec$removed <- list()
  rec$sent <- list()
  rec$modal_opens <- list()

  env$resolve_effective_user_id <- function(session, current_user_id) user_id
  env$remove_feedback_from_db <- function(uid, db_id) {
    rec$removed[[length(rec$removed) + 1L]] <- list(uid = uid, db_id = db_id)
    invisible(NULL)
  }
  env$showToast <- function(session, message, type = "info") {
    rec$toasts[[length(rec$toasts) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_chat_actions.R"),
    encoding = "UTF-8",
    local = env
  )
  list(env = env, rec = rec)
}

# Gözlemcileri kurar, belirtilen input'u prime-then-set ile tetikler.
.drive_chat_action <- function(fix, input_id, prime_value, real_value, messages,
                               liked = character(0), disliked = character(0),
                               is_sending = FALSE) {
  env <- fix$env; rec <- fix$rec
  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(
      messages = messages, liked_messages = liked, disliked_messages = disliked,
      is_sending = is_sending
    )
    feedback_modal <- list(open = function(db_id, kind, on_cancel = NULL) {
      rec$modal_opens[[length(rec$modal_opens) + 1L]] <- list(db_id = db_id, kind = kind)
      invisible(NULL)
    })
    env$chatActionsInit(
      input = input, session = session, values = values,
      current_user_id = 5L,
      send_message_fn = function(prompt) {
        rec$sent[[length(rec$sent) + 1L]] <- prompt; invisible(NULL)
      },
      stop_generation = function(...) invisible(NULL),
      reset_chat_state = function(...) invisible(NULL),
      feedback_modal = feedback_modal
    )
    output$probe <- renderText(paste(values$messages |> length(), collapse = ""))
    # values'ı dışarıya köprüle (isolate ile okunacak).
    rec$values <- values
  }, {
    do.call(session$setInputs, stats::setNames(list(prime_value), input_id))
    do.call(session$setInputs, stats::setNames(list(real_value), input_id))
    force(output$probe)
  })
}

.toast_messages <- function(rec) vapply(rec$toasts, function(t) t$message, character(1))

# ------------------------------------------------------------------------------
# like
# ------------------------------------------------------------------------------
testthat::test_that("like_message db_id'li yeni beğenide geri bildirim modalını açar", {
  fix <- .source_chat_actions_for_test()
  msgs <- list(
    list(id = "a1", type = "ai", db_id = 10L, content = "cevap")
  )
  .drive_chat_action(fix, "like_message", "a1", "a1", msgs)

  # feedback_modal$open en az bir kez (10, "like") ile çağrılmalı.
  testthat::expect_true(length(fix$rec$modal_opens) >= 1L)
  son <- fix$rec$modal_opens[[length(fix$rec$modal_opens)]]
  testthat::expect_identical(as.integer(son$db_id), 10L)
  testthat::expect_identical(son$kind, "like")
  # liked_messages "10" içermeli.
  testthat::expect_true("10" %in% shiny::isolate(fix$rec$values$liked_messages))
})

testthat::test_that("like_message db_id yoksa 'yanıt tamamlandıktan sonra' uyarısı verir", {
  fix <- .source_chat_actions_for_test()
  msgs <- list(list(id = "a1", type = "ai", content = "henüz tamamlanmadı"))  # db_id yok
  .drive_chat_action(fix, "like_message", "a1", "a1", msgs)

  testthat::expect_true(any(grepl("yanıt tamamlandıktan sonra beğenin",
                                  .toast_messages(fix$rec), fixed = TRUE)))
  # Modal açılmamalı.
  testthat::expect_length(fix$rec$modal_opens, 0L)
})

# ------------------------------------------------------------------------------
# dislike
# ------------------------------------------------------------------------------
testthat::test_that("dislike_message db_id'li yeni beğenmemede modalı 'dislike' ile açar", {
  fix <- .source_chat_actions_for_test()
  msgs <- list(list(id = "a2", type = "ai", db_id = 22L, content = "cevap"))
  .drive_chat_action(fix, "dislike_message", "a2", "a2", msgs)

  testthat::expect_true(length(fix$rec$modal_opens) >= 1L)
  son <- fix$rec$modal_opens[[length(fix$rec$modal_opens)]]
  testthat::expect_identical(son$kind, "dislike")
  testthat::expect_true("22" %in% shiny::isolate(fix$rec$values$disliked_messages))
})

# ------------------------------------------------------------------------------
# regenerate
# ------------------------------------------------------------------------------
testthat::test_that("regenerate_message önceki kullanıcı sorusunu yeniden gönderir ve AI mesajını siler", {
  fix <- .source_chat_actions_for_test()
  msgs <- list(
    list(id = "u1", type = "user", content = "Türkiye'nin başkenti?"),
    list(id = "a1", type = "ai", content = "Ankara")
  )
  .drive_chat_action(fix, "regenerate_message", "a1", "a1", msgs)

  # send_message_fn önceki kullanıcı sorusuyla çağrılmalı.
  testthat::expect_true(length(fix$rec$sent) >= 1L)
  testthat::expect_identical(fix$rec$sent[[length(fix$rec$sent)]], "Türkiye'nin başkenti?")
  # AI mesajı listeden çıkarılmış olmalı (yalnızca kullanıcı mesajı kalır).
  kalan <- shiny::isolate(fix$rec$values$messages)
  testthat::expect_length(kalan, 1L)
  testthat::expect_identical(kalan[[1]]$id, "u1")
})

testthat::test_that("regenerate_message ilk mesaj (idx<=1) için işlem yapmaz", {
  fix <- .source_chat_actions_for_test()
  msgs <- list(list(id = "u1", type = "user", content = "ilk mesaj"))
  .drive_chat_action(fix, "regenerate_message", "u1", "u1", msgs)
  # idx == 1 -> erken dönüş; gönderim olmamalı.
  testthat::expect_length(fix$rec$sent, 0L)
})

testthat::test_that("regenerate_message bilinmeyen mesaj kimliğinde sessizce çıkar", {
  fix <- .source_chat_actions_for_test()
  msgs <- list(
    list(id = "u1", type = "user", content = "soru"),
    list(id = "a1", type = "ai", content = "cevap")
  )
  .drive_chat_action(fix, "regenerate_message", "yok", "yok", msgs)
  testthat::expect_length(fix$rec$sent, 0L)
})
