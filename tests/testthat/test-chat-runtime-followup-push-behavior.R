# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-runtime-followup-push-behavior.R
# Açıklama: push_followup_update (helpers_chat_render_updates.R) takip sorusu yayınlama
#           davranışı ve update_messages_after_bulk_deletion (helpers_image_gallery.R)
#           girdi doğrulama korumaları test edilir. Sahte oturum/DB ile çalışır;
#           gerçek DB/LLM/ağ/tarayıcı GEREKMEZ.
# ==============================================================================

.chat_runtime_env <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_chat_runtime.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_chat_render_updates.R"),
         encoding = "UTF-8", local = env)
  env
}

# cat() gürültüsünü bastırarak push_followup_update çalıştırır.
.run_push <- function(env, ...) {
  invisible(utils::capture.output(env$push_followup_update(...)))
}

testthat::test_that("push_followup_update geçerli takip sorularını temizleyip yayınlar", {
  env <- .chat_runtime_env()
  rec <- new.env()
  rec$count <- 0L
  rec$payload <- NULL
  session <- list(sendCustomMessage = function(type, msg) {
    rec$count <- rec$count + 1L
    rec$payload <- list(type = type, msg = msg)
    invisible(NULL)
  })

  .run_push(env, session, "msg-1", c("  Soru bir  ", "", "Soru iki"), pending = TRUE)

  testthat::expect_identical(rec$count, 1L)
  testthat::expect_identical(rec$payload$type, "updateFollowupSuggestions")
  testthat::expect_identical(rec$payload$msg$id, "msg-1")
  # Boşluklar kırpılır, boş öğe atılır.
  testthat::expect_identical(rec$payload$msg$followups, c("Soru bir", "Soru iki"))
  testthat::expect_true(isTRUE(rec$payload$msg$pending))
})

testthat::test_that("push_followup_update NULL oturum/mesaj veya boş listede yayın yapmaz", {
  env <- .chat_runtime_env()
  rec <- new.env(); rec$count <- 0L
  session <- list(sendCustomMessage = function(type, msg) {
    rec$count <- rec$count + 1L; invisible(NULL)
  })

  .run_push(env, NULL, "m", "x")            # NULL oturum
  .run_push(env, session, NULL, "x")        # NULL mesaj kimliği
  .run_push(env, session, "m", character(0))# boş liste
  .run_push(env, session, "m", c("", "   "))# yalnızca boşluk -> atılır

  testthat::expect_identical(rec$count, 0L)
})

# --- update_messages_after_bulk_deletion girdi doğrulama korumaları ------------

testthat::test_that("update_messages_after_bulk_deletion geçersiz chat_id'de DB bağlantısı AÇMAZ", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_image_gallery.R"),
         encoding = "UTF-8", local = env)

  # get_connection sayaç taklidi: geçersiz girdide HİÇ çağrılmamalı.
  rec <- new.env(); rec$conn_calls <- 0L
  env$get_connection <- function(...) {
    rec$conn_calls <- rec$conn_calls + 1L
    stop("DB'ye erişilmemeliydi")
  }

  testthat::expect_null(env$update_messages_after_bulk_deletion(NA))
  testthat::expect_null(env$update_messages_after_bulk_deletion(NULL))
  testthat::expect_null(env$update_messages_after_bulk_deletion("abc"))   # sayıya çevrilemez
  testthat::expect_null(env$update_messages_after_bulk_deletion(NA_integer_))

  testthat::expect_identical(rec$conn_calls, 0L)
})

test_that("yeni mesaj balonu önceki sahibin ayar kimliğini kullanmaz", {
  env <- .chat_runtime_env()
  env$format_timestamp <- function() "2026-09-30"
  env$normalize_character_id <- identity
  env$get_character_record <- function(...) list()
  env$insertUI <- function(...) invisible(NULL)
  kayit <- NULL
  env$render_message_bubble_ui <- function(message, settings, ...) {
    kayit <<- settings$user_config
    shiny::div("mesaj")
  }
  shiny::testServer(function(input, output, session) NULL, {
    values <- shiny::reactiveValues(show_welcome = FALSE, messages = list(), liked_messages = character(0),
                                    disliked_messages = character(0), current_chat_id = NULL)
    settings <- shiny::reactiveValues(selected_character = "bilge", user_config = list(full_name = "A"))
    session$userData$user_config <- list(full_name = "B")
    env$chat_add_message(session, values, settings, output, "metin", html = "<p>metin</p>",
                         current_user_id = 8L, persist_to_db = FALSE)
    expect_identical(kayit, list(full_name = "B"))
    session$userData$user_config <- NULL
    env$chat_add_message(session, values, settings, output, "metin", html = "<p>metin</p>",
                         current_user_id = 0L, persist_to_db = FALSE)
    expect_null(kayit)
  })
})
