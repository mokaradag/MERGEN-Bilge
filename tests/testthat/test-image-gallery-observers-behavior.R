# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-gallery-observers-behavior.R
# Açıklama: R/server_observers_image_gallery.R imageGalleryObserversInit()
#           söyleşiye yönlendirme guard'larının DAVRANIŞSAL testleri. Bu dosya
#           daha önce hiçbir test tarafından çağrılmıyordu.
#
#           navigate_to_chat gözlemcisi, görsele tıklanınca ilgili söyleşiye
#           gider. Önce kimlik doğrulama guard'ları çalışır: boş/geçersiz chat_id,
#           devam eden yükleme kilidi ve bulunamayan söyleşi. Gözlemci
#           gallery_data$navigate_to_chat reaktif değeri prime-then-set ile
#           tetiklenir. showToast / load_chat_messages_from_db stub'lanır.
#           Gerçek DB GEREKMEZ.
# ==============================================================================

.source_gallery_obs_for_test <- function(load_in_progress = FALSE, db_impl = NULL) {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  rec <- new.env(); rec$toasts <- list(); rec$db_calls <- 0L
  env$showToast <- function(session, message, type = "info") {
    rec$toasts[[length(rec$toasts) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }
  env$load_chat_messages_from_db <- if (is.function(db_impl)) db_impl else function(chat_id_int, ...) {
    rec$db_calls <- rec$db_calls + 1L
    NULL
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_image_gallery.R"),
    encoding = "UTF-8",
    local = env
  )
  list(env = env, rec = rec, load_in_progress = load_in_progress)
}

.toast_msgs <- function(rec) vapply(rec$toasts, function(t) t$message, character(1))

# navigate_to_chat reaktifini prime-then-set ile tetikler.
.drive_navigate <- function(fix, prime_info, real_info, saved_chats = list()) {
  env <- fix$env; rec <- fix$rec
  shiny::testServer(function(input, output, session) {
    nav <- shiny::reactiveVal(NULL)
    lock <- shiny::reactiveVal(fix$load_in_progress)
    values <- shiny::reactiveValues(saved_chats = saved_chats)
    rec$lock <- lock
    # Modülde üç gözlemci var (navigate/delete/clear); hepsinin reaktifi
    # sağlanmazsa init anında NULL() çağrısı "non-function" hatası üretir.
    env$imageGalleryObserversInit(
      input = input, session = session, values = values,
      settings_data = list(),
      gallery_data = list(
        navigate_to_chat = nav,
        delete_image = shiny::reactiveVal(NULL),
        clear_all_images = shiny::reactiveVal(NULL)
      ),
      saved_chats_data = list(),
      current_user_id = 5L,
      load_chat_in_progress = lock
    )
    nav(prime_info)
    nav(real_info)
  }, {
    session$flushReact()
  })
}

# ------------------------------------------------------------------------------
# Boş / eksik chat_id
# ------------------------------------------------------------------------------
testthat::test_that("navigate_to_chat boş chat_id'de 'söyleşi bulunamadı' uyarısı verir", {
  fix <- .source_gallery_obs_for_test()
  .drive_navigate(fix, list(chat_id = ""), list(chat_id = ""))
  testthat::expect_true(any(grepl("ait olduğu söyleşi bulunamadı",
                                  .toast_msgs(fix$rec), fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# Geçersiz (sayısal olmayan) chat_id
# ------------------------------------------------------------------------------
testthat::test_that("navigate_to_chat sayısal olmayan chat_id'de 'Geçersiz söyleşi kimliği' verir", {
  fix <- .source_gallery_obs_for_test()
  .drive_navigate(fix, list(chat_id = "xyz"), list(chat_id = "abc"))
  testthat::expect_true(any(grepl("Geçersiz söyleşi kimliği",
                                  .toast_msgs(fix$rec), fixed = TRUE)))
  # Geçersiz kimlik DB yüklemesine gitmemeli.
  testthat::expect_identical(fix$rec$db_calls, 0L)
})

# ------------------------------------------------------------------------------
# Devam eden yükleme kilidi
# ------------------------------------------------------------------------------
testthat::test_that("navigate_to_chat yükleme sürerken 'lütfen bekleyin' der ve DB'ye gitmez", {
  fix <- .source_gallery_obs_for_test(load_in_progress = TRUE)
  .drive_navigate(fix, list(chat_id = "6"), list(chat_id = "5"))
  testthat::expect_true(any(grepl("lütfen bekleyin", .toast_msgs(fix$rec), fixed = TRUE)))
  testthat::expect_identical(fix$rec$db_calls, 0L)
})

# ------------------------------------------------------------------------------
# Bulunamayan söyleşi
# ------------------------------------------------------------------------------
testthat::test_that("navigate_to_chat önbellekte/DB'de yoksa 'artık mevcut değil' der ve kilidi bırakır", {
  fix <- .source_gallery_obs_for_test(load_in_progress = FALSE)  # DB stub NULL döner
  .drive_navigate(fix, list(chat_id = "6"), list(chat_id = "5"), saved_chats = list())
  testthat::expect_true(any(grepl("artık mevcut değil veya silinmiş",
                                  .toast_msgs(fix$rec), fixed = TRUE)))
  # Yükleme kilidi tekrar serbest bırakılmalı.
  testthat::expect_false(shiny::isolate(fix$rec$lock()))
})

testthat::test_that("navigate_to_chat geçerli ama bulunamayan kimlikte DB'den yüklemeyi dener", {
  fix <- .source_gallery_obs_for_test(load_in_progress = FALSE)
  .drive_navigate(fix, list(chat_id = "10"), list(chat_id = "11"), saved_chats = list())
  # Geçerli sayısal kimlik -> en az bir DB yükleme denemesi yapılmalı.
  testthat::expect_true(fix$rec$db_calls >= 1L)
})
