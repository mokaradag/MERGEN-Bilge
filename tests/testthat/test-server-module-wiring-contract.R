# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-module-wiring-contract.R
# Açıklama: Orta seviye server modül bağlama işlerinin server.R yerine
#           R/server_module_wiring.R içinde kalmasını doğrular.
# ==============================================================================

.read_repo_text_server_module_wiring_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

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

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.extract_safe_source_paths_server_module_wiring_contract <- function(text) {
  m <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, m)[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) {
    return(character(0))
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

test_that("server modül bağlama yardımcısı doğru manifest sırasındadır", {
  expect_source_manifest_order_for_tests(
    c(
      "R/server_runtime_context.R",
      "R/server_module_wiring.R",
      "R/server_init_session_state.R"
    ),
    label = "Server module wiring source sırası bozulmuş:"
  )
})

test_that("server.R orta seviye modül bağlamayı helper dosyasına devreder", {
  server_text <- .read_repo_text_server_module_wiring_contract("server.R")

  required_delegates <- c(
    "serverBindServiceModules(",
    "serverBindSettingsAndRefs(",
    "serverBindMediaModules(",
    "serverBindFilePreludeModules("
  )

  missing_delegates <- required_delegates[!vapply(
    required_delegates,
    function(pattern) grepl(pattern, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_delegates,
    character(0),
    info = paste(
      "server.R içinde beklenen modül bağlama yardımcıları yok:",
      paste(missing_delegates, collapse = ", ")
    )
  )

  forbidden_direct_calls <- c(
    "performanceStatsServer(",
    "healthServer(",
    "destekServer(",
    "settingsInit(",
    "serverInitForwardRefs(",
    "claudeCodeServer(",
    "visualSettingsSyncInit(",
    "chatOutputsInit(",
    "feedbackServer(",
    "aiProcessingServer(",
    "ttsProcessingServer(",
    "ttsVisualizerServer(",
    "musicHandlersInit(",
    "aiExpertServer(",
    "sttServer(",
    "filePreviewServer(",
    "create_followup_suggestions_tool(",
    "followupSuggestionsServer(",
    "init_docx_preview_js("
  )

  matched <- forbidden_direct_calls[vapply(
    forbidden_direct_calls,
    function(pattern) grepl(pattern, server_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "server.R içinde helper'a taşınması gereken doğrudan modül bağlama çağrıları var:",
      paste(matched, collapse = ", ")
    )
  )
})

test_that("server_module_wiring.R açık bağımlılık enjeksiyonu kullanır", {
  wiring_text <- .read_repo_text_server_module_wiring_contract(
    "R/server_module_wiring.R"
  )

  required_patterns <- c(
    "performance_stats_server_fn = performanceStatsServer",
    "settings_init_fn = settingsInit",
    "forward_refs_init_fn = serverInitForwardRefs",
    "claude_code_server_fn = claudeCodeServer",
    "feedback_server_fn = feedbackServer",
    "file_preview_server_fn = filePreviewServer"
  )

  missing_patterns <- required_patterns[!vapply(
    required_patterns,
    function(pattern) grepl(pattern, wiring_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_patterns,
    character(0),
    info = paste(
      "server_module_wiring.R içinde açık bağımlılık parametreleri eksik:",
      paste(missing_patterns, collapse = ", ")
    )
  )
})