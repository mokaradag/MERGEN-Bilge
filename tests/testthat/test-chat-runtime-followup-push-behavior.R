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
  testthat::expect_null(env$update_messages_after_bulk_deletion(character(0)))
  testthat::expect_null(env$update_messages_after_bulk_deletion(integer(0)))
  testthat::expect_null(env$update_messages_after_bulk_deletion(c(1L, 2L)))

  testthat::expect_identical(rec$conn_calls, 0L)
})

testthat::test_that("update_messages_after_bulk_deletion geçerli girdide değişim durumunu ve kısmi güncellemeyi doğru bildirir", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_image_gallery.R"),
         encoding = "UTF-8", local = env)
  env$normalize_db_params <- function(x) x
  env$get_connection <- function() list(conn = structure(list(), class = "sahte_conn"))
  env$release_connection <- function(info) invisible(NULL)

  # 1) Değişen mesaj yok -> FALSE; güncelleme HİÇ denenmez.
  guncelleme_cagrisi <- 0L
  withr::with_tempdir({
    mevcut_dosya <- file.path(getwd(), "mevcut.png")
    writeBin(raw(1), mevcut_dosya)
    testthat::local_mocked_bindings(
      dbGetQuery = function(conn, query, params = NULL) {
        data.frame(MessageID = 10L, MessageContent = paste0("[GÖRSEL:", mevcut_dosya, "] açıklama"),
                   stringsAsFactors = FALSE)
      },
      dbExecute = function(...) {
        guncelleme_cagrisi <<- guncelleme_cagrisi + 1L
        stop("güncelleme çağrılmamalıydı")
      },
      .package = "DBI"
    )
    testthat::expect_false(env$update_messages_after_bulk_deletion(42L))
  })
  testthat::expect_identical(guncelleme_cagrisi, 0L)

  # 2) Silinen görsel -> TRUE
  exec_say <- 0L
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, query, params = NULL) {
      data.frame(MessageID = 11L, MessageContent = "[GÖRSEL:/yok/silindi.png] açıklama",
                 stringsAsFactors = FALSE)
    },
    dbExecute = function(conn, query, params = NULL) { exec_say <<- exec_say + 1L; 1L },
    .package = "DBI"
  )
  testthat::expect_true(env$update_messages_after_bulk_deletion("42"))
  testthat::expect_identical(exec_say, 1L)

  # 3) Kısmi güncelleme (ilk mesaj güncellenir, ikinci DB hatası verir) -> TRUE
  exec_say <- 0L
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, query, params = NULL) {
      data.frame(MessageID = c(11L, 12L),
                 MessageContent = c("[GÖRSEL:/yok/a.png] a", "[GÖRSEL:/yok/b.png] b"),
                 stringsAsFactors = FALSE)
    },
    dbExecute = function(conn, query, params = NULL) {
      exec_say <<- exec_say + 1L
      denenen <<- c(denenen, as.integer(params[[length(params)]]))
      if (exec_say == 2L) stop("ikinci satırda geçici DB hatası")
      1L
    },
    .package = "DBI"
  )
  denenen <- integer()
  testthat::expect_true(env$update_messages_after_bulk_deletion(42L))
  # İkinci satır da sırasıyla denendi (ilk başarıda durulmadı).
  testthat::expect_identical(denenen, c(11L, 12L))

  # 4) İlk sorgu DB hatası -> FALSE
  env$get_connection <- function() stop("DB erişilemez")
  testthat::expect_false(env$update_messages_after_bulk_deletion(42L))
})

testthat::test_that("delete_all_user_images yalnızca mesajı gerçekten değişen söyleşileri bildirir", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_image_gallery.R"),
         encoding = "UTF-8", local = env)
  withr::with_tempdir({
    f1 <- file.path(getwd(), "a.png"); writeBin(raw(1), f1)
    f2 <- file.path(getwd(), "b.png"); writeBin(raw(1), f2)
    f3 <- file.path(getwd(), "c.png"); writeBin(raw(1), f3)
    env$scan_user_images <- function(uid) {
      data.frame(file_path = c(f1, f2, f3), chat_id = c("10", "20", "gecersiz"),
                 stringsAsFactors = FALSE)
    }
    env$update_messages_after_bulk_deletion <- function(cid) {
      if (identical(cid, "10")) return(TRUE)
      if (identical(cid, "20")) return(FALSE)
      NULL
    }
    silinen <- env$delete_all_user_images(7L)
    testthat::expect_identical(as.integer(silinen), 3L)
    testthat::expect_identical(attr(silinen, "chat_ids"), "10")
  })
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
