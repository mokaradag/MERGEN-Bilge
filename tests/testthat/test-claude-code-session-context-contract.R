# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-session-context-contract.R
# Açıklama: Bilge Yolaç oturum bağlamı helper sözleşmesini ve akış finalizasyon
#           idempotency davranışını doğrular.
# ==============================================================================

.source_cc_session_context_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$reactive <- shiny::reactive
  test_env$is.reactive <- shiny::is.reactive

  test_env$get_characters_data <- function() {
    list(
      styles = list(
        list(
          id = "mergen",
          display_name = "Mergen",
          accent = "#7c3aed",
          accent_hover = "#6d28d9"
        ),
        list(
          id = "kayra",
          display_name = "Kayra",
          accent = "#10b981",
          accent_hover = "#059669"
        )
      )
    )
  }

  source(
    file.path(repo_root, "R", "helpers_claude_code_session_context.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Bilge Yolaç aktif karakter bağlamı helper üzerinden çözülür", {
  test_env <- .source_cc_session_context_for_test()

  settings_data <- list(selected_character = "kayra")
  active_character <- test_env$cc_create_active_character_reactive(settings_data)

  karakter <- shiny::isolate(active_character())

  expect_equal(karakter$id, "kayra")
  expect_equal(karakter$display_name, "Kayra")
})

test_that("Bilge Yolaç aktif karakter bağlamı varsayılan karaktere düşer", {
  test_env <- .source_cc_session_context_for_test()

  settings_data <- list(selected_character = "bilinmeyen")
  active_character <- test_env$cc_create_active_character_reactive(settings_data)

  karakter <- shiny::isolate(active_character())

  expect_equal(karakter$id, "mergen")
  expect_equal(karakter$display_name, "Mergen")
})

test_that("Bilge Yolaç kullanıcı adı öncelik sırası korunur", {
  test_env <- .source_cc_session_context_for_test()

  session <- list(
    userData = list(
      user_first_name = "Oturum",
      user_config = list(
        first_name = "Ayar",
        name = "Tam Ad"
      )
    )
  )

  from_param <- test_env$cc_create_user_first_name_reactive(
    session = session,
    user_first_name = function() "Parametre"
  )

  expect_equal(shiny::isolate(from_param()), "Parametre")

  from_session <- test_env$cc_create_user_first_name_reactive(
    session = session,
    user_first_name = NULL
  )

  expect_equal(shiny::isolate(from_session()), "Oturum")

  session$userData$user_first_name <- NULL
  from_config <- test_env$cc_create_user_first_name_reactive(
    session = session,
    user_first_name = NULL
  )

  expect_equal(shiny::isolate(from_config()), "Ayar")

  session$userData$user_config$first_name <- NULL
  from_name <- test_env$cc_create_user_first_name_reactive(
    session = session,
    user_first_name = NULL
  )

  expect_equal(shiny::isolate(from_name()), "Tam Ad")

  session$userData$user_config$name <- NULL
  fallback <- test_env$cc_create_user_first_name_reactive(
    session = session,
    user_first_name = NULL
  )

  expect_equal(shiny::isolate(fallback()), "Siz")
})

test_that("Bilge Yolaç streaming finalizasyonu tekrar çağrıldığında no-op kalır", {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$format_streaming_chunk_html <- function(parca) {
    NULL
  }

  source(
    file.path(repo_root, "R", "module_claude_code_akis.R"),
    encoding = "UTF-8",
    local = test_env
  )

  sent_messages <- list()
  session <- list(
    sendCustomMessage = function(type, message) {
      sent_messages[[length(sent_messages) + 1L]] <<- list(
        type = type,
        message = message
      )
    }
  )

  ns <- function(id) {
    paste0("cc_", id)
  }

  rv <- new.env(parent = emptyenv())
  rv$is_running <- FALSE
  rv$active_process <- NULL
  rv$stream_env <- NULL

  akis <- test_env$create_akis_yardimcilari(session, ns, rv)

  expect_false(isTRUE(akis$finalize_streaming("Tamamlandı", "check", "#10b981")))
  expect_length(sent_messages, 0L)

  rv$is_running <- TRUE
  rv$active_process <- list(pid = 123L)
  rv$stream_env <- new.env(parent = emptyenv())

  expect_true(isTRUE(akis$finalize_streaming("Tamamlandı", "check", "#10b981")))
  expect_false(isTRUE(rv$is_running))
  expect_null(rv$active_process)
  expect_null(rv$stream_env)
  expect_length(sent_messages, 3L)

  expect_false(isTRUE(akis$finalize_streaming("Tamamlandı", "check", "#10b981")))
  expect_length(sent_messages, 3L)
})