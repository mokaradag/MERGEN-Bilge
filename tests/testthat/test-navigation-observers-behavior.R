# ==============================================================================
# Dosya Yolu: tests/testthat/test-navigation-observers-behavior.R
# Açıklama: R/server_observers_navigation.R navigationObserversInit() sekme-geçiş
#           gözlemcisinin DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test
#           tarafından çağrılmıyordu.
#
#           navigationObserversInit moduleServer DEĞİLDİR; session doğrudan
#           iletilir. input$tabs değişimine göre ilgili modüle yenileme sinyali
#           gönderir (shinyjs::runjs custom message'ı olarak). Mesajlar kök
#           MockShinySession üzerinden yakalanır; gözlemci prime-then-set ile
#           tetiklenir. render_welcome_screen enjekte edilir. Ağ/DB GEREKMEZ.
# ==============================================================================

.source_navigation_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_observers_navigation.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Tüm custom message'ları (shinyjs::runjs dahil) serileştirip tek metinde birleştirir.
.capture_nav <- function(env, prime_tab, real_tab, show_welcome = FALSE) {
  rec <- new.env()
  rec$msgs <- list()
  rec$welcome_calls <- 0L

  record_runjs <- function(code) {
    rec$msgs[[length(rec$msgs) + 1L]] <- list(
      type = "shinyjs.runjs",
      message = code
    )
    invisible(NULL)
  }

  testthat::with_mocked_bindings(
    {
      shiny::testServer(
        function(input, output, session) {
          values <- shiny::reactiveValues(
            show_welcome = show_welcome,
            saved_chats = list()
          )

          env$navigationObserversInit(
            input = input,
            session = session,
            values = values,
            render_welcome_screen = function(...) {
              rec$welcome_calls <- rec$welcome_calls + 1L
              invisible(NULL)
            }
          )
        },
        {
          session$setInputs(tabs = prime_tab)
          session$setInputs(tabs = real_tab)
        }
      )
    },

    runjs = record_runjs,

    # Gecikmeli ifadeyi bilerek zorlamaz.
    # Böylece render_welcome_screen senkron çalışmaz.
    delay = function(ms, expr) invisible(NULL),

    .package = "shinyjs"
  )

  rec
}

# Yakalanan tüm mesajların düz metin temsili (alt-string araması için).
.nav_blob <- function(rec) {
  paste(vapply(rec$msgs, function(m) {
    tryCatch(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null"),
             error = function(e) paste(unlist(m), collapse = " "))
  }, character(1)), collapse = " ")
}

# ------------------------------------------------------------------------------
# Geçmiş sekmesi
# ------------------------------------------------------------------------------
testthat::test_that("history sekmesine geçiş geçmiş modülüne yenileme sinyali gönderir", {
  env <- .source_navigation_for_test()
  rec <- .capture_nav(env, "image_gallery", "history")
  testthat::expect_true(grepl("history_module-external_refresh_trigger", .nav_blob(rec), fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Görsel galerisi sekmesi
# ------------------------------------------------------------------------------
testthat::test_that("image_gallery sekmesine geçiş galeri yenileme sinyali gönderir", {
  env <- .source_navigation_for_test()
  rec <- .capture_nav(env, "history", "image_gallery")
  testthat::expect_true(grepl("image_gallery_module-refresh_gallery", .nav_blob(rec), fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Ana söyleşi + karşılama ekranı
# ------------------------------------------------------------------------------
testthat::test_that("chat sekmesinde karşılama ekranı render'ı gecikmeye bırakılır (senkron çağrılmaz)", {
  env <- .source_navigation_for_test()
  # Nötr prime ('files' eylemi shinyjs::delay içinde, senkron sinyal yok).
  rec <- .capture_nav(env, "files", "chat", show_welcome = TRUE)
  # Aşağı-kaydır butonunu gizleyen runjs senkron çalışır.
  testthat::expect_true(grepl("scroll_to_bottom_container", .nav_blob(rec), fixed = TRUE))
  # render_welcome_screen shinyjs::delay içinde olduğundan testServer'da senkron
  # çağrılmaz; gecikmeli davranış sözleşmesi korunur.
  testthat::expect_identical(rec$welcome_calls, 0L)
})

testthat::test_that("chat sekmesi ama karşılama kapalıyken galeri/geçmiş sinyali gönderilmez", {
  env <- .source_navigation_for_test()
  # Nötr prime: 'files' senkron history/gallery sinyali üretmez.
  rec <- .capture_nav(env, "files", "chat", show_welcome = FALSE)
  blob <- .nav_blob(rec)
  testthat::expect_false(grepl("image_gallery_module-refresh_gallery", blob, fixed = TRUE))
  testthat::expect_false(grepl("history_module-external_refresh_trigger", blob, fixed = TRUE))
})

testthat::test_that("smoke sohbetinden Yeni Söyleşi sonrası welcome sekme dönüşü tam render yapmaz", {
  env <- .source_navigation_for_test()
  for (file in c("helpers_chat_runtime.R", "server_welcome_handlers.R", "server_observers_chat_ui.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", file), local = env, encoding = "UTF-8")
  }
  rlang::local_bindings(file_store = list(), .env = globalenv())
  env$resolve_effective_user_id <- function(...) NA_integer_
  env$session_user_data_reset_lists <- function(...) invisible(NULL)
  env$showToast <- function(...) invisible(NULL)
  for (name in c("pk_entity_context_clear", "mergen_pk_bump_chat_epoch", "mergen_pk_abandon_active_requests")) {
    assign(name, function(...) invisible(NULL), env)
  }
  renders <- 0L
  refreshes <- 0L
  env$createWelcomeScreen <- function(...) {
    renders <<- renders + 1L
    shiny::div(class = "modern-welcome-root", "welcome")
  }
  env$createModernRecentChatsSection <- function(...) {
    refreshes <<- refreshes + 1L
    shiny::div(class = "modern-welcome-footer-section", "recent")
  }
  testthat::with_mocked_bindings({
    shiny::testServer(function(input, output, session) {
      values <- shiny::reactiveValues(show_welcome = FALSE, saved_chats = list(),
                                      messages = list(list(type = "ai", content = "smoke")))
      welcome <- env$welcomeHandlersInit(session, values, NULL, shiny::reactiveVal(list()), NULL, NA_integer_, NULL)
      env$chatUIObserversInit(input, session, values, welcome$start_new_chat, function(...) NULL,
                              welcome$render_welcome_screen)
      env$navigationObserversInit(input, session, values, welcome$render_welcome_screen)
      session$userData$.smoke_values <- values
    }, {
      session$setInputs(tabs = "chat")
      session$setInputs(tabs = "claude_code")
      session$setInputs(tabs = "chat")
      testthat::expect_false(session$userData$.smoke_values$show_welcome)
      testthat::expect_identical(renders, 0L)
      session$setInputs(new_chat_btn = 1L)
      testthat::expect_true(session$userData$.smoke_values$show_welcome)
      testthat::expect_length(session$userData$.smoke_values$messages, 0L)
      testthat::expect_identical(renders, 1L)
      session$setInputs(tabs = "claude_code")
      session$setInputs(tabs = "chat")
      testthat::expect_true(session$userData$.smoke_values$show_welcome)
      testthat::expect_identical(renders, 1L)
      testthat::expect_identical(refreshes, 1L)
      testthat::expect_true(session$userData$welcome_screen_attached)
    })
  }, runjs = function(...) invisible(NULL), delay = function(ms, expr) force(expr), .package = "shinyjs")
})


testthat::test_that("taze smoke oturumunun welcome navigasyonu diger oturumun dosya eslemelerini korur", {
  env <- .source_navigation_for_test()
  source(file.path(resolve_repo_root_for_tests(), "R/server_welcome_handlers.R"), local = env, encoding = "UTF-8")
  other <- shiny::MockShinySession$new()
  withr::defer(other$close())
  other$userData$file_id <- "other-session-file"
  mappings <- setNames(list(list(path = "other-session-report")), other$userData$file_id)
  rlang::local_bindings(file_store = mappings, .env = globalenv())
  env$resolve_effective_user_id <- function(...) NA_integer_
  renders <- 0L
  env$createWelcomeScreen <- function(...) {
    renders <<- renders + 1L
    shiny::div(class = "modern-welcome-root", "welcome")
  }
  env$createModernRecentChatsSection <- function(...) shiny::div(class = "modern-welcome-footer-section")
  testthat::with_mocked_bindings({
    shiny::testServer(function(input, output, session) {
      values <- shiny::reactiveValues(show_welcome = TRUE, saved_chats = list(), messages = list())
      welcome <- env$welcomeHandlersInit(session, values, NULL, shiny::reactiveVal(list()), NULL, NA_integer_, NULL)
      welcome$render_welcome_screen(list())
      env$navigationObserversInit(input, session, values, welcome$render_welcome_screen)
      session$userData$.smoke_values <- values
    }, {
      session$setInputs(tabs = "chat")
      session$setInputs(tabs = "claude_code")
      session$setInputs(tabs = "chat")
      testthat::expect_true(session$userData$.smoke_values$show_welcome)
      testthat::expect_identical(renders, 1L)
      testthat::expect_identical(file_store, mappings)
      testthat::expect_identical(file_store[[other$userData$file_id]]$path, "other-session-report")
    })
  }, runjs = function(...) invisible(NULL), delay = function(ms, expr) force(expr), .package = "shinyjs")
})
