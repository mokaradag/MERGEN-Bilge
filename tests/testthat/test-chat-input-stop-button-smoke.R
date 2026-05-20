# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-input-stop-button-smoke.R
# Açıklama: Ana sohbet stop/durdur butonunun gerçek observer yolu üzerinden
#           gönderim UI durumunu temizlediğini doğrular. Uygulamayı, DB'yi,
#           LLM'i, tarayıcıyı, TTS/STT endpoint'lerini başlatmaz.
# ==============================================================================

.find_chat_input_stop_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Chat input stop smoke repo kökünü bulamadı.", call. = FALSE)
}

repo_root_chat_input_stop <- .find_chat_input_stop_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_chat_input_stop, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_chat_input_stop <- resolve_repo_root_for_tests()

.chat_input_stop_source_once <- function(path, required_function = NULL) {
  if (!is.null(required_function) &&
      exists(required_function, envir = globalenv(), inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(repo_root_chat_input_stop, path),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

.chat_input_stop_source_once("R/utils_common.R", "%||%")
.chat_input_stop_source_once("R/helpers_user_session_identity.R", "resolve_effective_user_id")
.chat_input_stop_source_once("R/server_observers_chat_input.R", "chatInputObserversInit")

testthat::test_that("stop button observer clears sending/typing UI state without full app", {
  testthat::skip_if_not_installed("shiny")

  restore_names <- c("showToast")
  old_values <- lapply(restore_names, function(nm) {
    if (exists(nm, envir = globalenv(), inherits = FALSE)) {
      get(nm, envir = globalenv())
    } else {
      NULL
    }
  })
  names(old_values) <- restore_names

  old_exists <- vapply(
    restore_names,
    exists,
    logical(1),
    envir = globalenv(),
    inherits = FALSE
  )

  toast_messages <- character()

  assign(
    "showToast",
    function(session, message, type = "info", ...) {
      toast_messages <<- c(toast_messages, paste(type, message, sep = ":"))
      invisible(TRUE)
    },
    envir = globalenv()
  )

  on.exit({
    for (nm in restore_names) {
      if (isTRUE(old_exists[[nm]])) {
        assign(nm, old_values[[nm]], envir = globalenv())
      } else if (exists(nm, envir = globalenv(), inherits = FALSE)) {
        rm(list = nm, envir = globalenv())
      }
    }
  }, add = TRUE)

  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(
      is_sending = TRUE,
      typing = TRUE
    )

    settings_data <- shiny::reactiveValues()
    stop_generation <- shiny::reactiveVal(FALSE)
    active_request_id <- shiny::reactiveVal("req_stop_smoke")
    reset_called <- 0L

    reset_chat_state <- function() {
      reset_called <<- reset_called + 1L
      values$is_sending <- FALSE
      values$typing <- FALSE
      invisible(TRUE)
    }

    stt_data <- list(
      start_session = function() invisible(TRUE),
      final_text = shiny::reactiveVal("")
    )

    chatInputObserversInit(
      input = input,
      session = session,
      values = values,
      settings_data = settings_data,
      stop_generation = stop_generation,
      active_request_id = active_request_id,
      reset_chat_state = reset_chat_state,
      send_message = function(...) stop("send_message bu smoke testte çağrılmamalı."),
      current_user_id = function() 4242L,
      file_manager_data = list(),
      session_files = shiny::reactiveVal(list()),
      file_to_add = shiny::reactiveVal(NULL),
      stt_data = stt_data
    )

    session$userData$.values <- values
    session$userData$.stop_generation <- stop_generation
    session$userData$.active_request_id <- active_request_id
    session$userData$.reset_called <- function() reset_called
  }, {
    session$flushReact()

    testthat::expect_true(isTRUE(session$userData$.values$is_sending))
    testthat::expect_true(isTRUE(session$userData$.values$typing))
    testthat::expect_false(isTRUE(session$userData$.stop_generation()))

    session$setInputs(send_stop_btn = 1)
    session$flushReact()

    testthat::expect_true(isTRUE(session$userData$.stop_generation()))
    testthat::expect_match(
      session$userData$.active_request_id(),
      "^cancelled_"
    )
    testthat::expect_false(isTRUE(session$userData$.values$is_sending))
    testthat::expect_false(isTRUE(session$userData$.values$typing))
    testthat::expect_gte(session$userData$.reset_called(), 1L)
    testthat::expect_true(any(grepl("Yanıt oluşturma durduruldu", toast_messages, fixed = TRUE)))
  })
})