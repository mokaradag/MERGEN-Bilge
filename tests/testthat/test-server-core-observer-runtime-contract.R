# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-core-observer-runtime-contract.R
# Açıklama: Çekirdek observer/File Manager runtime ayrımının geri alınmamasını
#           ve kaynak manifestindeki güvenli yükleme sırasını korur.
# ==============================================================================

.read_repo_text_core_observer_contract <- function(path) {
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

  txt <- gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.load_manifest_paths_core_observer_contract <- function() {
  repo_root <- resolve_repo_root_for_tests()
  manifest_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "config_source_manifest.R"),
    encoding = "UTF-8",
    local = manifest_env
  )

  get("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)
}

test_that("core observer runtime çekirdek observer ve File Manager bağlamasını sahiplenir", {
  observer_text <- .read_repo_text_core_observer_contract(
    file.path("R", "server_core_observer_runtime.R")
  )

  core_text <- .read_repo_text_core_observer_contract(
    file.path("R", "server_core_interaction_runtime.R")
  )

  expected_observer_tokens <- c(
    "serverBindCoreObserverRuntime <- function",
    "boot_readiness_init_fn(session)",
    "chat_export_init_fn(",
    "quick_actions_init_fn(",
    "settings_observers_init_fn(",
    "session_timeout_server_fn(",
    "file_manager_runtime_fn(",
    "chat_ui_observers_init_fn(",
    "navigation_observers_init_fn(",
    "startup_observers_init_fn",
    "startup_screen_observers_init_fn",
    "ai_expert_handlers_init_fn(",
    "storage_observers_init_fn(",
    "file_observers_init_fn(",
    "file_click_observers_init_fn("
  )

  missing_tokens <- expected_observer_tokens[!vapply(
    expected_observer_tokens,
    function(token) grepl(token, observer_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_tokens,
    character(0),
    info = paste(
      "server_core_observer_runtime.R beklenen runtime bağlama tokenlarını taşımalıdır:",
      paste(missing_tokens, collapse = ", ")
    )
  )

  expect_true(
    grepl("core_observer_runtime_fn(", core_text, fixed = TRUE, useBytes = TRUE),
    info = "server_core_interaction_runtime.R çekirdek observer bağlamasını yeni helper'a devretmelidir."
  )

  direct_call_patterns <- c(
    "\\n  chat_export_init_fn\\(",
    "\\n  quick_actions_init_fn\\(",
    "\\n  settings_observers_init_fn\\(",
    "\\n  session_timeout_server_fn\\(",
    "\\n  file_manager_runtime_fn\\(",
    "\\n  chat_ui_observers_init_fn\\(",
    "\\n  navigation_observers_init_fn\\(",
    "\\n  ai_expert_handlers_init_fn\\(",
    "\\n  storage_observers_init_fn\\(",
    "\\n  file_observers_init_fn\\(",
    "\\n  file_click_observers_init_fn\\("
  )

  leaked_direct_calls <- direct_call_patterns[vapply(
    direct_call_patterns,
    function(pattern) grepl(pattern, core_text, perl = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    leaked_direct_calls,
    character(0),
    info = paste(
      "server_core_interaction_runtime.R observer/File Manager çağrılarını doğrudan geri almamalıdır:",
      paste(leaked_direct_calls, collapse = ", ")
    )
  )
})

test_that("core observer runtime manifestte core interaction runtime öncesinde yüklenir", {
  paths <- .load_manifest_paths_core_observer_contract()

  pos <- function(path) match(path, paths)

  expect_false(is.na(pos("R/server_core_observer_runtime.R")))
  expect_false(is.na(pos("R/server_core_interaction_runtime.R")))

  expect_lt(
    pos("R/server_init_chat_runtime.R"),
    pos("R/server_core_observer_runtime.R")
  )

  expect_lt(
    pos("R/server_core_observer_runtime.R"),
    pos("R/server_core_interaction_runtime.R")
  )
})