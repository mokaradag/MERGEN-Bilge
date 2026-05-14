# ==============================================================================
# Dosya Yolu: tests/testthat/test-browser-smoke-harness-contract.R
# Açıklama: Repo-local browser UX smoke harness dosyasının gerçek UI anchor'ları,
#           hızlı işlem sözleşmeleri ve medya/reasoning probe'larıyla hizalı
#           kalmasını doğrular.
# ==============================================================================

.find_browser_smoke_repo_root <- function() {
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

  stop("Browser smoke test repo kökünü bulamadı.", call. = FALSE)
}

.browser_smoke_read_text <- function(path) {
  full_path <- file.path(.find_browser_smoke_repo_root(), path)

  if (!file.exists(full_path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", full_path), call. = FALSE)
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

  if (is.na(txt)) txt <- ""
  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.browser_smoke_expect_all <- function(text, expected, label) {
  found <- vapply(
    expected,
    function(item) grepl(item, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  testthat::expect_true(
    all(found),
    info = paste(label, paste(expected[!found], collapse = ", "))
  )
}

testthat::test_that("browser UX smoke harness gerçek UI anchor'larıyla hizalıdır", {
  smoke_html <- .browser_smoke_read_text("www/smoke/ux-smoke.html")
  ui_text <- .browser_smoke_read_text("ui.R")
  welcome_text <- .browser_smoke_read_text("R/welcome_screen_modern.R")
  input_js <- .browser_smoke_read_text("www/js/input_handlers.js")
  handlers_js <- .browser_smoke_read_text("www/js/shiny_message_handlers.js")
  music_js <- .browser_smoke_read_text("www/js/music_manager.js")
  tts_js <- .browser_smoke_read_text("www/js/tts_manager.js")
  stt_js <- .browser_smoke_read_text("www/js/stt_client.js")
  reasoning_js <- .browser_smoke_read_text("www/js/premium_reasoning.js")

  .browser_smoke_expect_all(
    ui_text,
    c(
      'id = "welcome_fullscreen_container"',
      'id = "chat_content_container"',
      'id = "user_input"',
      'inputId = "send_stop_btn"'
    ),
    "ui.R browser smoke anchor sözleşmesi eksik:"
  )

	.browser_smoke_expect_all(
	  smoke_html,
	  c(
		"#welcome_fullscreen_container",
		"#chat_content_container",
		"#user_input",
		"#send_stop_btn",
		".modern-welcome-video-container",
		".modern-welcome-neural-canvas",
		"#dynamic-greeting-text",
		".modern-welcome-action-btn",
		"/smoke/ux-smoke.html",
		"isSsoEnabled",
		"getFrameAccess",
		"cross-origin SSO/Keycloak",
		"MERGEN_SMOKE_BASE_URL",
		"prepareFreshAppStorage",
		"restoreSmokeStorage",
		"skip_intro",
		"mergen_current_chat",
		"intro görünürlüğü SSO production smoke'ta atlandı",
		"#ux_smoke_target=",
		"UX_SMOKE_DONE:PASS",
		"UX_SMOKE_DONE:FAIL"
	  ),
	  "ux-smoke.html ana DOM sözleşmesi eksik:"
	)

  .browser_smoke_expect_all(
    welcome_text,
    c(
      "modern-welcome-video-container",
      "modern-welcome-neural-canvas",
      "dynamic-greeting-text",
      "modern-welcome-action-btn",
      "data-action-model",
      "data-action-id"
    ),
    "Modern welcome smoke hedefleri eksik:"
  )

  .browser_smoke_expect_all(
    handlers_js,
    c(
      "window._handleQuickAction = function(btn)",
      "QUICK_ACTION_DEBOUNCE_MS",
      "Shiny.setInputValue('quick_template'"
    ),
    "Quick action browser smoke hedefleri eksik:"
  )

  .browser_smoke_expect_all(
    smoke_html,
    c(
      '"project-process"',
      '"app-expert"',
      '"resource-analysis"',
      '"excel-analysis"',
      '"image-creation"',
      '"coding-support"',
      '"summarization"',
      "quick_template",
      "send_prompt_from_js",
      "fullQuickActions",
      "hasSmokeFlag",
      "testQuickActions();",
      "testOneQuickActionOnly();",
      "isSsoEnabled(app.doc)"
    ),
    "Browser smoke quick action/input kapsamı eksik:"
  )

  .browser_smoke_expect_all(
    input_js,
    c(
      "CHAT_INPUT_SELECTOR",
      "send_prompt_from_js",
      "hasClass('stop-mode')"
    ),
    "Input handler smoke hedefleri eksik:"
  )

  .browser_smoke_expect_all(
    smoke_html,
    c(
      "MusicManager",
      "mergenTTS",
      "STT_Client",
      "duckForSTT",
      "unduckAfterSTT",
      "PremiumReasoning",
      "onReasoningDelta",
      "onResetChatState"
    ),
    "Browser smoke medya/reasoning kapsamı eksik:"
  )

  .browser_smoke_expect_all(
    music_js,
    c(
      "window.MusicManager",
      "_audio: null",
      "duckForSTT",
      "unduckAfterSTT"
    ),
    "MusicManager browser smoke hedefleri eksik:"
  )

  .browser_smoke_expect_all(
    tts_js,
    c(
      "window.mergenTTS",
      "stopTTSPlayback",
      "MusicManager.duck()",
      "MusicManager.unduck()"
    ),
    "TTS browser smoke hedefleri eksik:"
  )

  .browser_smoke_expect_all(
    stt_js,
    c(
      "window.STT_Client",
      "MusicManager.duckForSTT()",
      "MusicManager.unduckAfterSTT()"
    ),
    "STT browser smoke hedefleri eksik:"
  )

  .browser_smoke_expect_all(
    reasoning_js,
    c(
      "window.PremiumReasoning",
      "premiumReasoningStart",
      "streamingReasoningDelta",
      "premiumReasoningStreamStart",
      "onResetChatState"
    ),
    "Reasoning browser smoke hedefleri eksik:"
  )
})