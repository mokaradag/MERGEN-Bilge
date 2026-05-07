# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-boot-welcome-regression.R
# Açıklama: Non-SSO test boot, karşılama ekranı ve browser restore sözleşmeleri
#           için deterministik E2E benzeri regresyon dilimi.
# ==============================================================================

.find_e2e_boot_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("E2E boot test repo kökünü bulamadı. Testi repo kökünden çalıştırın.", call. = FALSE)
}

repo_root_e2e_boot <- .find_e2e_boot_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_e2e_boot, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_e2e_boot <- resolve_repo_root_for_tests()

if (!exists("e2e_regression_config", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_e2e_boot, "tests", "testthat", "helper_e2e_race_harness.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

e2e_boot_read_text <- function(path) {
  full_path <- if (grepl("^/", path) || grepl("^[A-Za-z]:", path)) {
    path
  } else {
    file.path(repo_root_e2e_boot, path)
  }

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

e2e_boot_has_text <- function(text, needle) {
  isTRUE(suppressWarnings(grepl(
    needle,
    text,
    fixed = TRUE,
    useBytes = TRUE
  )))
}

e2e_boot_expect_all_text <- function(text, expected, label) {
  found <- vapply(
    expected,
    function(item) e2e_boot_has_text(text, item),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(label, paste(expected[!found], collapse = ", "))
  )
}

e2e_boot_register_shiny_tags <- function() {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    testthat::skip("shiny paketi gerekli.")
  }

  if (!exists("tags", envir = globalenv(), inherits = FALSE)) {
    assign("tags", shiny::tags, envir = globalenv())
  }

  if (!exists("div", envir = globalenv(), inherits = FALSE)) {
    assign("div", shiny::div, envir = globalenv())
  }

  if (!exists("span", envir = globalenv(), inherits = FALSE)) {
    assign("span", shiny::span, envir = globalenv())
  }

  invisible(TRUE)
}

e2e_boot_source_app <- function() {
  withCallingHandlers(
    source("app.R", encoding = "UTF-8", local = globalenv()),
    warning = function(w) {
      msg <- conditionMessage(w)

      if (grepl("was built under R version", msg, fixed = TRUE) ||
          grepl("already", msg, ignore.case = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )

  invisible(TRUE)
}

e2e_boot_source_welcome_helpers <- function() {
  e2e_boot_register_shiny_tags()

  source(
    file.path(repo_root_e2e_boot, "R", "utils_common.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  source(
    file.path(repo_root_e2e_boot, "R", "helpers_api_model_config.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  source(
    file.path(repo_root_e2e_boot, "R", "welcome_screen_modern.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

test_that("app.R non-SSO test boot is valid and does not launch unwanted futures", {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    testthat::skip("shiny paketi gerekli.")
  }

  withr::local_dir(repo_root_e2e_boot)
  withr::local_envvar(c(
    MERGEN_RUN_APP = "false",
    MERGEN_DISABLE_FUTURES = "true",
    MERGEN_SQL_LOADER_STRICT = "false",
    SSO_ENABLED = "FALSE",
    LOCAL_LLM_ENDPOINT = "http://test.local/v1",
    DB_DSN = "test-dsn",
    AI_KEYS_MASTER = "test-master-key-boot-placeholder"
  ))

  expect_no_error(e2e_boot_source_app())

  expect_false(.env_flag_is_true(Sys.getenv("MERGEN_RUN_APP"), default = TRUE))
  expect_true(.env_flag_is_true(Sys.getenv("MERGEN_DISABLE_FUTURES"), default = FALSE))

  expect_no_error(validate_boot_state())

  app_obj <- create_mergen_app()

  expect_s3_class(app_obj, "shiny.appobj")
  expect_true(exists("ui", envir = globalenv(), inherits = FALSE))
  expect_true(is.function(get("server", envir = globalenv(), inherits = FALSE)))

  if (requireNamespace("future", quietly = TRUE)) {
    expect_equal(future::nbrOfWorkers(), 1L)
  }
})

test_that("modern welcome screen renders quick actions, recent chats and Turkish text", {
  if (!requireNamespace("htmltools", quietly = TRUE)) {
    testthat::skip("htmltools paketi gerekli.")
  }

  e2e_boot_source_welcome_helpers()

  config <- e2e_regression_config()
  actions <- build_main_actions_data_from_config(config)

  saved_chats <- list(
    eski = list(
      title = "Eski Söyleşi",
      timestamp = "2026-05-06 08:00:00",
      last_message_timestamp = "2026-05-06 08:00:00",
      messages = list(list(content = "Eski içerik")),
      message_count = 1L
    ),
    yeni = list(
      title = "Yeni İhale",
      timestamp = "2026-05-07 10:00:00",
      last_message_timestamp = "2026-05-07 10:00:00",
      messages = list(list(content = "İğdır kaynak planı incelendi.")),
      message_count = 1L
    ),
    orta = list(
      title = "Orta Söyleşi",
      timestamp = "2026-05-07 09:00:00",
      last_message_timestamp = "2026-05-07 09:00:00",
      messages = list(list(content = "Özetleme bağlamı hazır.")),
      message_count = 1L
    )
  )

  screen <- createModernWelcomeScreen(saved_chats, actions)
  html <- paste(as.character(htmltools::renderTags(screen)$html), collapse = "\n")

  e2e_boot_expect_all_text(
    html,
    c(
      "modern-welcome-root",
      "MERGEN",
      "Bilge",
      "Hızlı Başlangıç",
      "Son Konuşmalar",
      "dynamic-greeting-text",
      "modern-welcome-actions-grid",
      "İğdır"
    ),
    "Karşılama HTML sözleşmesi eksik:"
  )

  action_tokens <- regmatches(
    html,
    gregexpr("data-action-id=\"[^\"]+\"", html, perl = TRUE)
  )[[1]]

  action_ids <- sub(
    "data-action-id=\"([^\"]+)\"",
    "\\1",
    action_tokens,
    perl = TRUE
  )

  expect_setequal(
    action_ids,
    c(
      "project-process",
      "app-expert",
      "resource-analysis",
      "excel-analysis",
      "image-creation",
      "coding-support",
      "summarization"
    )
  )

  expect_equal(length(action_ids), 7L)
  expect_equal(length(unique(action_ids)), 7L)

  model_tokens <- regmatches(
    html,
    gregexpr("data-action-model=\"[^\"]+\"", html, perl = TRUE)
  )[[1]]

  expect_equal(length(model_tokens), 7L)

  onclick_tokens <- regmatches(
    html,
    gregexpr(
      "onclick=\"window\\._handleQuickAction\\(this\\); return false;\"",
      html,
      perl = TRUE
    )
  )[[1]]

  expect_true(
    length(onclick_tokens) >= 7L,
    info = "Her modern welcome action butonu _handleQuickAction onclick sözleşmesini taşımalıdır."
  )

  pos_new <- regexpr("Yeni İhale", html, fixed = TRUE, useBytes = TRUE)[[1]]
  pos_mid <- regexpr("Orta Söyleşi", html, fixed = TRUE, useBytes = TRUE)[[1]]
  pos_old <- regexpr("Eski Söyleşi", html, fixed = TRUE, useBytes = TRUE)[[1]]

  expect_true(pos_new > 0L && pos_mid > 0L && pos_old > 0L)
  expect_true(pos_new < pos_mid)
  expect_true(pos_mid < pos_old)
})

test_that("client boot wiring keeps quick action, prompt send and restore paths separate", {
  ui_text <- e2e_boot_read_text("ui.R")
  shiny_handlers <- e2e_boot_read_text(file.path("www", "js", "shiny_message_handlers.js"))
  input_handlers <- e2e_boot_read_text(file.path("www", "js", "input_handlers.js"))

  e2e_boot_expect_all_text(
    ui_text,
    c(
      "id = \"welcome_fullscreen_container\"",
      "id = \"chat_content_container\"",
      "id = \"user_input\"",
      "id = \"send_stop_btn\"",
      "src = \"js/shiny_message_handlers.js\"",
      "src = \"js/streaming_manager.js\"",
      "src = \"js/premium_reasoning.js\"",
      "src = \"js/file_handlers.js\"",
      "src = \"js/tts_manager.js\"",
      "src = \"js/stt_client.js\"",
      "src = \"js/music_manager.js\""
    ),
    "Ana UI boot/welcome/client wiring sözleşmesi eksik:"
  )

  e2e_boot_expect_all_text(
    shiny_handlers,
    c(
      "window._handleQuickAction = function(btn)",
      "btn.getAttribute('data-action-model')",
      "btn.getAttribute('data-action-id')",
      "Shiny.setInputValue('quick_template'",
      "text: ''",
      "action_id: actionId",
      "$('#welcome_fullscreen_container').fadeOut(300)",
      "localStorage.getItem('mergen_current_chat')",
      "Shiny.setInputValue('load_chat_from_storage'",
      "{ priority: 'event' }"
    ),
    "shiny_message_handlers.js hızlı işlem/restore sözleşmesi eksik:"
  )

  restore_start <- regexpr(
    "Shiny.setInputValue('load_chat_from_storage'",
    shiny_handlers,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  expect_true(restore_start > 0L)

  restore_segment <- substr(
    shiny_handlers,
    max(1L, restore_start - 300L),
    min(nchar(shiny_handlers, type = "chars", allowNA = FALSE), restore_start + 600L)
  )

  expect_false(
    grepl(
      "playAudioMessage|playTts|tts_processor|toggleMusic|initMusicManager",
      restore_segment,
      perl = TRUE,
      ignore.case = TRUE
    ),
    info = "localStorage restore yolu eski sohbet yüklerken TTS/müzik tetiklememelidir."
  )

  e2e_boot_expect_all_text(
    input_handlers,
    c(
      "$(document).on('click', '#send_stop_btn'",
      "hasClass('stop-mode')",
      "Shiny.setInputValue(\"send_prompt_from_js\"",
      "nonce: Math.random()",
      "Lütfen bir mesaj yazın."
    ),
    "input_handlers.js normal prompt gönderim sözleşmesi eksik:"
  )
})