# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-chat-persistence-wiring-contract.R
# Açıklama: Kayıtlı sohbet, geçmiş, galeri, karşılama ve mesaj arama
#           bağlamasının server.R yerine server_module_wiring.R içinde
#           açık bağımlılıklarla kalmasını doğrular.
# ==============================================================================

.read_repo_text_chat_persistence_contract <- function(path) {
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

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("server.R sohbet kalıcılığı bağlamasını çekirdek etkileşim helper'ına devreder", {
  server_text <- .read_repo_text_chat_persistence_contract("server.R")
  core_text <- .read_repo_text_chat_persistence_contract(
    "R/server_core_interaction_runtime.R"
  )

  expect_true(
    grepl(
      "serverBindCoreInteractionRuntime(",
      server_text,
      fixed = TRUE,
      useBytes = TRUE
    )
  )

  expect_true(
    grepl(
      "chat_persistence_modules_fn = serverBindChatPersistenceModules",
      core_text,
      fixed = TRUE,
      useBytes = TRUE
    )
  )

  expect_true(
    grepl(
      "chat_persistence <- chat_persistence_modules_fn(",
      core_text,
      fixed = TRUE,
      useBytes = TRUE
    )
  )

  expect_true(
    grepl(
      "current_user_id_provider = identity$current_user_id_provider",
      core_text,
      fixed = TRUE,
      useBytes = TRUE
    )
  )

  forbidden_direct_calls <- c(
    "savedChatsServer(",
    "savedChatsObserversInit(",
    "chatSearchInit(",
    "serverBindImageGalleryRuntime(",
    "imageGalleryObserversInit(",
    "welcomeHandlersInit(",
    "downloadOutputsInit(",
    "historyServer(",
    "messageSearchInit("
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
      "Sohbet kalıcılığı bağlaması server.R içine geri taşınmış olabilir:",
      paste(matched, collapse = ", ")
    )
  )
})

test_that("server_module_wiring.R sohbet kalıcılığı için açık bağımlılık alır", {
  wiring_text <- .read_repo_text_chat_persistence_contract(
    "R/server_module_wiring.R"
  )

  required_patterns <- c(
    "serverBindChatPersistenceModules <- function(",
    "saved_chats_server_fn = savedChatsServer",
    "saved_chats_observers_init_fn = savedChatsObserversInit",
    "chat_search_init_fn = chatSearchInit",
    "image_gallery_runtime_fn = serverBindImageGalleryRuntime",
    "image_gallery_observers_init_fn = imageGalleryObserversInit",
    "welcome_handlers_init_fn = welcomeHandlersInit",
    "download_outputs_init_fn = downloadOutputsInit",
    "history_server_fn = historyServer",
    "message_search_init_fn = messageSearchInit",
    "user_config_provider",
    "user_first_name_fn",
    "welcome_fns$render_welcome_screen <-",
    "welcome_fns$start_new_chat <-"
  )

  missing <- required_patterns[!vapply(
    required_patterns,
    function(pattern) grepl(pattern, wiring_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing,
    character(0),
    info = paste(
      "serverBindChatPersistenceModules açık bağımlılık sözleşmesi eksik:",
      paste(missing, collapse = ", ")
    )
  )
})

test_that("savedChatsObserversInit kullanıcı bağlamını provider ile alabilir", {
  saved_text <- .read_repo_text_chat_persistence_contract(
    "R/server_observers_saved_chats.R"
  )

  required_patterns <- c(
    "user_config_provider = NULL",
    "user_first_name_fn = NULL",
    "resolve_user_config <- function",
    "resolve_user_first_name <- function",
    "user_config_provider(default = default)",
    "user_first_name_fn(default = default)"
  )

  missing <- required_patterns[!vapply(
    required_patterns,
    function(pattern) grepl(pattern, saved_text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing,
    character(0),
    info = paste(
      "Kayıtlı sohbet gözlemcilerinde provider tabanlı kullanıcı bağlamı eksik:",
      paste(missing, collapse = ", ")
    )
  )
})