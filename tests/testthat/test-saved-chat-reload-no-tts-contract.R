# ==============================================================================
# Dosya Yolu: tests/testthat/test-saved-chat-reload-no-tts-contract.R
# Açıklama: Kayıtlı sohbet reload yolunun tarihsel AI mesajları için TTS
#           autoplay başlatmadığını yapısal olarak doğrular.
# ==============================================================================

.read_saved_chat_contract_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) return("")

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

.extract_load_chat_from_storage_block <- function(text) {
  marker <- "observeEvent(input$load_chat_from_storage"
  start <- regexpr(marker, text, fixed = TRUE, useBytes = TRUE)[[1]]
  testthat::expect_true(start > 0L, info = "load_chat_from_storage observer bulunamadı")

  tail <- substr(text, start, nchar(text))
  end_marker <- "}, ignoreInit = TRUE)"
  end <- regexpr(end_marker, tail, fixed = TRUE, useBytes = TRUE)[[1]]
  testthat::expect_true(end > 0L, info = "load_chat_from_storage observer sonu bulunamadı")

  substr(tail, 1L, end + nchar(end_marker) - 1L)
}

testthat::test_that("saved chat reload renders history without starting TTS playback", {
  storage_text <- .read_saved_chat_contract_text("R/server_observers_storage.R")
  reload_block <- .extract_load_chat_from_storage_block(storage_text)

  testthat::expect_true(
    grepl("render_message_bubble_ui", reload_block, fixed = TRUE),
    info = "Reload yolu tarihsel mesajları render etmelidir."
  )

  forbidden <- c(
    "playAudioMessage",
    "synthesize_speech",
    "synthesize_speech(",
    "sendCustomMessage(\"playAudioMessage\"",
    "sendCustomMessage('playAudioMessage'"
  )

  missing_guard <- forbidden[vapply(
    forbidden,
    function(token) grepl(token, reload_block, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing_guard,
    character(0),
    info = paste("Reload observer TTS autoplay tetikleyebilir:", paste(missing_guard, collapse = ", "))
  )
})

testthat::test_that("saved chat reload runtime smoke renders historical AI messages without TTS side effects", {
  testthat::skip_if_not_installed("shiny")

  if (!exists("storageObserversInit", envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "server_observers_storage.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }

  restore_names <- c(
    "showToast",
    "get_characters_data",
    "render_message_bubble_ui",
    "synthesize_speech"
  )

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

  tts_called <- FALSE

  assign("showToast", function(...) invisible(TRUE), envir = globalenv())

  assign(
    "get_characters_data",
    function() {
      list(styles = list(list(id = "mergen", display_name = "MERGEN")))
    },
    envir = globalenv()
  )

  assign(
    "render_message_bubble_ui",
    function(msg, settings_data, ...) {
      shiny::div(
        id = paste0("message_wrapper_", msg$id %||% "unknown"),
        class = paste("message-bubble", msg$type %||% ""),
        msg$content %||% ""
      )
    },
    envir = globalenv()
  )

  assign(
    "synthesize_speech",
    function(...) {
      tts_called <<- TRUE
      stop("saved chat reload must not synthesize speech", call. = FALSE)
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
      messages = list(),
      liked_messages = character(0),
      disliked_messages = character(0),
      show_welcome = TRUE
    )

    settings_data <- shiny::reactiveValues(
      selected_character = "mergen"
    )

    chart_rebind_count <- 0L

    storageObserversInit(
      input = input,
      session = session,
      output = output,
      values = values,
      settings_data = settings_data,
      chat_rebind_all_charts = function(...) {
        chart_rebind_count <<- chart_rebind_count + 1L
        invisible(TRUE)
      }
    )

    session$userData$.values <- values
    session$userData$.chart_rebind_count <- function() chart_rebind_count
  }, {
    historical_messages <- list(
      list(
        id = "old_ai_1",
        type = "ai",
        content = enc2utf8("Eski kayıtlı yanıt"),
        has_code = FALSE
      )
    )

    session$setInputs(load_chat_from_storage = historical_messages)
    session$flushReact()

    values <- session$userData$.values

    testthat::expect_equal(length(values$messages), 1L)
    testthat::expect_identical(values$messages[[1]]$id, "old_ai_1")
    testthat::expect_false(isTRUE(tts_called))
    testthat::expect_equal(session$userData$.chart_rebind_count(), 1L)
  })
})