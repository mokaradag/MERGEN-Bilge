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
  smoke_html <- .browser_smoke_read_text("tests/smoke/ux-smoke.html")
  ui_text <- .browser_smoke_read_text("ui.R")
  welcome_text <- .browser_smoke_read_text("R/welcome_screen_modern.R")
  input_js <- .browser_smoke_read_text("www/js/input_handlers.js")
  handlers_js <- .browser_smoke_read_text("www/js/shiny_message_handlers.js")
  music_js <- .browser_smoke_read_text("www/js/music_manager.js")
  tts_js <- .browser_smoke_read_text("www/js/tts_manager.js")
  stt_js <- .browser_smoke_read_text("www/js/stt_client.js")
  streaming_js <- .browser_smoke_read_text("www/js/streaming_manager.js")
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
		'new URL("../", window.location.href)',
		"isSsoEnabled",
		"fullQuickActions tarayıcı modu VM smoke'ta atlandı",
		"getFrameAccess",
		"cross-origin SSO/Keycloak",
		"MERGEN_BROWSER_UX_PROFILE_DIR",
		"waitForFrameAccessible",
		"navigateFrameToApp",
		"doc.body || doc.documentElement",
		"iframe aynı-origin DOM erişimi zaman aşımı",
        "load_chat_from_storage",
        "kayıtlı sohbet load_chat_from_storage olayı tarayıcıdan üretildi",
        "kayıtlı sohbet yüklenince tarihsel TTS autoplay başlamaz",

        "testStreamingLifecycle",
        "MergenStreamingSmoke",
        "streaming delta görünür içeriğe işlendi",
        "stale requestId delta yoksayılır",
        "stream finalize dataset temizler",
        "stream finalize state finalized yapar",
        "stream action butonları geri açılır",
        "stream finalize follow-up pending state temizlenir",
        "stream finalize duplicate mesaj üretmez",
        "rawScriptPayload",
        "rawImgPayload",
        "javascript:alert(1)",
        "streaming markdown script elementi üretmez",
        "streaming markdown img elementi üretmez",
        "streaming markdown a elementi üretmez",
        "streaming markdown tehlikeli HTML çalıştırmaz",

        "failOnTimeout",
		"VM zamanlamasında görünmedi",
		"Console ignored",
		"bloklayıcı JS hatası yok",
		"data-ux-smoke",
		"reasoning-host",
		"Reasoning testi sentetiktir",
		"prepareFreshAppStorage",
		"restoreSmokeStorage",
		"skip_intro",
		"mergen_current_chat",
		"intro görünürlüğü SSO production smoke'ta atlandı",
		"ux_smoke_target=",
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
      "testOneQuickActionOnCurrentWelcome(app);",
      "fullQuickActions tarayıcı modu VM smoke'ta atlandı"
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
    streaming_js,
    c(
      "window.MergenStreamingSmoke",
      "handleInitStreamingMessage",
      "handleStreamingDelta",
      "handleFinalizeStreamingMessage",
      "isStaleStreamingPayload",
      "state.finalized = true",
      "messageDiv.dataset.streaming = \"false\"",
      "btn.disabled = false"
    ),
    "Streaming browser smoke hedefleri eksik:"
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


testthat::test_that("Shiny handler ve smoke durum sözleşmeleri gerçek JavaScript ile çalışır", {
  node <- Sys.which("node")
  testthat::skip_if(!nzchar(node), "Node kullanılamıyor")
  for (script in c("shiny_message_handlers_contract_regressions.js",
                   "ux_smoke_navigation_regressions.js", "ux_smoke_start_gate_regressions.js",
                   "ux_smoke_startup_timing_regressions.js")) {
    args <- shQuote(file.path(.find_browser_smoke_repo_root(), "tests/scripts", script))
    if (identical(script, "ux_smoke_startup_timing_regressions.js")) {
      browsers <- c(unname(Sys.which(c("google-chrome", "chromium", "msedge"))),
                    file.path(Sys.getenv("PROGRAMFILES"), "Microsoft/Edge/Application/msedge.exe"),
                    file.path(Sys.getenv("PROGRAMFILES(X86)"), "Microsoft/Edge/Application/msedge.exe"))
      browsers <- browsers[nzchar(browsers) & file.exists(browsers)]
      if (length(browsers)) {
        if (grepl("^msedge([.]exe)?$", basename(browsers[[1]]), ignore.case = TRUE)) {
          policy <- new.env(parent = globalenv())
          sys.source(file.path(.find_browser_smoke_repo_root(), "tests/scripts/helpers_browser_ux_profile.R"), envir = policy)
          policy$ux_smoke_check_edge_policy()
        }
        args <- c(args, "--browser", shQuote(browsers[[1]]))
      }
    }
    result <- system2(node, args, stdout = TRUE, stderr = TRUE)
    testthat::expect_null(attr(result, "status"), info = paste(result, collapse = "\n"))
    testthat::expect_match(paste(result, collapse = "\n"), "regressions passed", fixed = TRUE)
  }
})


testthat::test_that("native Edge fixture ilke reddinde tarayici baslatmaz", {
  root <- .find_browser_smoke_repo_root()
  calls <- as.list(parse(file.path(root, "tests/testthat/test-browser-smoke-harness-contract.R")))
  execution <- Filter(function(e) is.call(e) && length(e) >= 3L &&
    is.character(e[[2]]) && identical(e[[2]], "Shiny handler ve smoke durum sözleşmeleri gerçek JavaScript ile çalışır"), calls)[[1]][[3]]
  for (allowed in c(FALSE, TRUE)) {
    env <- new.env(parent = environment())
    checked <- 0L
    native <- 0L
    env$.find_browser_smoke_repo_root <- function() root
    env$Sys.which <- function(x) if (identical(x, "node")) "mock-node" else c("", "", "/mock/msedge.exe")
    env$file.exists <- function(x) x == "/mock/msedge.exe"
    env$sys.source <- function(file, envir) {
      testthat::expect_identical(file, file.path(root, "tests/scripts/helpers_browser_ux_profile.R"))
      envir$ux_smoke_check_edge_policy <- function() {
        checked <<- checked + 1L
        if (!allowed) stop("policy blocked")
      }
    }
    env$system2 <- function(command, args, ...) {
      if ("--browser" %in% args) {
        testthat::expect_identical(checked, 1L)
        native <<- native + 1L
      }
      "regressions passed"
    }
    if (allowed) eval(execution, env) else testthat::expect_error(eval(execution, env), "policy blocked", fixed = TRUE)
    testthat::expect_identical(checked, 1L)
    testthat::expect_identical(native, as.integer(allowed))
  }
})
