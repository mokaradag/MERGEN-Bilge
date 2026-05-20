# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-chat-persistence-regression.R
# Açıklama: Kayıtlı söyleşi, geçmiş ve görsel galeri yenileme/yükleme/silme
#           yarış durumları için deterministik E2E benzeri regresyon testleri.
# ==============================================================================

.find_e2e_cp_repo_root <- function() {
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

  stop("Chat persistence E2E test repo kökünü bulamadı.", call. = FALSE)
}

repo_root_e2e_cp <- .find_e2e_cp_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_e2e_cp, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_e2e_cp <- resolve_repo_root_for_tests()

if (!exists("e2e_cp_new_state", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(
      repo_root_e2e_cp,
      "tests",
      "testthat",
      "helper_e2e_chat_persistence_harness.R"
    ),
    encoding = "UTF-8",
    local = globalenv()
  )
}

test_that("saved chat ordering follows last activity and final answer persists once", {
  chats <- list(
    eski = e2e_cp_make_chat(
      "Eski söyleşi",
      "2026-05-07 08:00:00",
      messages = list(e2e_cp_make_message("user", "Merhaba"))
    ),
    orta = e2e_cp_make_chat(
      "Orta söyleşi",
      "2026-05-07 09:00:00",
      messages = list(e2e_cp_make_message("user", "Ara soru"))
    )
  )

  state <- e2e_cp_new_state(chats = chats)

  expect_identical(e2e_cp_saved_chat_order(state$saved_chats), c("orta", "eski"))

  state <- e2e_cp_finalize_answer_once(
    state,
    request_id = "req_istanbul_001",
    chat_id = "yeni",
    title = "Türkçe karakter testi: İğdır ve Şırnak",
    user_text = "İğdır verilerini özetler misin?",
    ai_text = "İğdır için kısa özet hazırlandı.",
    timestamp = "2026-05-07 10:30:00"
  )

  state <- e2e_cp_finalize_answer_once(
    state,
    request_id = "req_istanbul_001",
    chat_id = "yeni",
    title = "Çift final",
    user_text = "Bu ikinci kez yazılmamalı.",
    ai_text = "Bu yanıt kaydedilmemeli.",
    timestamp = "2026-05-07 10:31:00"
  )

  expect_identical(state$saved_chat_updates, 1L)
  expect_identical(state$saved_chat_refreshes, 1L)
  expect_identical(state$last_skip_reason, "already_finalized")
  expect_identical(
    e2e_cp_saved_chat_order(state$saved_chats),
    c("yeni", "orta", "eski")
  )

  expect_true(grepl(
    "İğdır",
    state$saved_chats$yeni$title,
    fixed = TRUE
  ))
})

test_that("loading saved chats does not trigger TTS and stale deleted load is ignored", {
  chat_messages <- list(
    e2e_cp_make_message("user", "Eski soru", id = "u1"),
    e2e_cp_make_message("ai", "Eski yanıt", id = "a1")
  )

  chats <- list(
    aktif = e2e_cp_make_chat(
      "Aktif söyleşi",
      "2026-05-07 11:00:00",
      messages = chat_messages
    ),
    diger = e2e_cp_make_chat(
      "Diğer söyleşi",
      "2026-05-07 10:00:00",
      messages = chat_messages
    )
  )

  state <- e2e_cp_new_state(
    chats = chats,
    current_chat_id = "aktif",
    current_messages = chat_messages
  )

  state <- e2e_cp_load_chat(state, "diger")

  expect_identical(state$load_chat_count, 1L)
  expect_identical(state$current_chat_id, "diger")
  expect_false(state$show_welcome)
  expect_identical(state$tts_calls, 0L)
  expect_true(any(grepl("Söyleşi yüklendi:", state$toasts, fixed = TRUE)))

  loaded_toasts_before_delete <- sum(grepl(
    "Söyleşi yüklendi:",
    state$toasts,
    fixed = TRUE
  ))

  state <- e2e_cp_delete_chat(state, "diger")

  expect_true(state$show_welcome)
  expect_null(state$current_chat_id)
  expect_identical(state$welcome_render_count, 1L)
  expect_true(any(grepl("Söyleşi silindi.", state$toasts, fixed = TRUE)))

  state <- e2e_cp_load_chat(state, "diger")

  expect_identical(state$last_skip_reason, "deleted_chat")
  expect_identical(state$load_chat_count, 1L)
  expect_identical(
    sum(grepl("Söyleşi yüklendi:", state$toasts, fixed = TRUE)),
    loaded_toasts_before_delete
  )
  expect_identical(state$tts_calls, 0L)
})

test_that("history refresh skips invalid user id without wiping valid cache", {
  messages <- list(
    e2e_cp_make_message(
      "user",
      "Kayıtlı geçmişte Türkçe soru",
      timestamp = "07.05.2026 - 12:00"
    ),
    e2e_cp_make_message(
      "ai",
      "Kayıtlı geçmişte Türkçe yanıt",
      timestamp = "07.05.2026 - 12:01"
    )
  )

  chats <- list(
    gecmis = e2e_cp_make_chat(
      "Geçmiş söyleşi",
      "2026-05-07 12:01:00",
      messages = messages
    )
  )

  state <- e2e_cp_new_state(chats = chats)
  state <- e2e_cp_refresh_history(state, user_id = 42L)

  expect_identical(state$history_refreshes, 1L)
  expect_identical(nrow(state$history_cache), 1L)
  expect_identical(state$history_cache$Chat_ID[[1]], "Geçmiş söyleşi")

  state <- e2e_cp_refresh_history(state, user_id = 0L)

  expect_identical(state$history_skips, 1L)
  expect_identical(state$last_skip_reason, "invalid_history_user")
  expect_identical(nrow(state$history_cache), 1L)
  expect_identical(state$history_cache$Soru[[1]], "Kayıtlı geçmişte Türkçe soru")
})

test_that("gallery refresh is user-scoped and invalid user id does not wipe cache", {
  images_by_user <- list(
    "11" = data.frame(
      file_path = "user_11/chat_a/gorsel_istanbul.png",
      filename = "görsel_istanbul.png",
      user_id = 11L,
      stringsAsFactors = FALSE
    ),
    "22" = data.frame(
      file_path = "user_22/chat_b/gorsel_ankara.png",
      filename = "görsel_ankara.png",
      user_id = 22L,
      stringsAsFactors = FALSE
    )
  )

  state <- e2e_cp_new_state()
  state <- e2e_cp_refresh_gallery(state, user_id = 11L, images_by_user)

  expect_identical(state$gallery_refreshes, 1L)
  expect_identical(state$gallery_cache$filename[[1]], "görsel_istanbul.png")
  expect_identical(state$gallery_cache$user_id[[1]], 11L)

  state <- e2e_cp_refresh_gallery(state, user_id = 0L, images_by_user)

  expect_identical(state$gallery_skips, 1L)
  expect_identical(state$last_skip_reason, "invalid_gallery_user")
  expect_identical(state$gallery_cache$filename[[1]], "görsel_istanbul.png")
  expect_identical(state$gallery_cache$user_id[[1]], 11L)

  state <- e2e_cp_refresh_gallery(state, user_id = 22L, images_by_user)

  expect_identical(state$gallery_refreshes, 2L)
  expect_identical(state$gallery_cache$filename[[1]], "görsel_ankara.png")
  expect_identical(state$gallery_cache$user_id[[1]], 22L)
})

test_that("runtime files keep saved chat, history and gallery race contracts wired", {
  saved_observers <- e2e_cp_read_repo_text("R/server_observers_saved_chats.R")
  saved_module <- e2e_cp_read_repo_text("R/module_saved_chats.R")
  history_module <- e2e_cp_read_repo_text("R/module_chat_history.R")
  gallery_module <- e2e_cp_read_repo_text("R/module_image_gallery.R")
  wiring_module <- e2e_cp_read_repo_text("R/server_module_wiring.R")

  required_saved_patterns <- c(
    "last_deleted_chat_id <- reactiveVal(NULL)",
    "do_load_chat <- function(chat_id)",
    "identical(chat_id, last_deleted_chat_id())",
    "load_chat_in_progress()",
    "values$show_welcome <- TRUE",
    "createWelcomeScreen(values$saved_chats)",
    "saved_chats_data$refresh()"
  )

  missing_saved <- required_saved_patterns[!vapply(
    required_saved_patterns,
    function(pattern) grepl(pattern, saved_observers, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_saved,
    character(0),
    info = paste("Kayıtlı söyleşi race sözleşmesi eksik:", paste(missing_saved, collapse = ", "))
  )

  forbidden_saved_chat_tts_patterns <- c(
    "trigger_tts",
    "trigger_tts_for_message",
    "playAudioMessage",
    "sendCustomMessage(\"playAudioMessage\"",
    "sendCustomMessage('playAudioMessage'",
    "attach_tts_audio(",
    "autoplay = TRUE"
  )

  forbidden_hits <- forbidden_saved_chat_tts_patterns[vapply(
    forbidden_saved_chat_tts_patterns,
    function(pattern) grepl(pattern, saved_observers, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    forbidden_hits,
    character(0),
    info = paste(
      "Kayıtlı söyleşi yükleme akışı eski AI mesajlarını TTS/autoplay ile başlatmamalı:",
      paste(forbidden_hits, collapse = ", ")
    )
  )

  expect_true(
    grepl("render_message_bubble_ui(", saved_observers, fixed = TRUE, useBytes = TRUE),
    info = "Kayıtlı söyleşi yükleme eski mesajları sadece UI render yoluyla eklemeli."
  )

  required_module_patterns <- c(
    "meta <- meta[order(meta$timestamp, decreasing = TRUE), , drop = FALSE]",
    "load_chat_trigger(input$load_chat_id)",
    "delete_chat_trigger(chat_id)",
    "refresh <- function()"
  )

  missing_module <- required_module_patterns[!vapply(
    required_module_patterns,
    function(pattern) grepl(pattern, saved_module, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_module,
    character(0),
    info = paste("Kayıtlı söyleşi modül sözleşmesi eksik:", paste(missing_module, collapse = ", "))
  )

  required_history_patterns <- c(
    "observeEvent(input$external_refresh_trigger",
    "refresh_history_cache(force = TRUE)",
    "load_history_rows_batch(",
    "user_id = resolve_current_user_id()"
  )

  missing_history <- required_history_patterns[!vapply(
    required_history_patterns,
    function(pattern) grepl(pattern, history_module, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_history,
    character(0),
    info = paste("Geçmiş refresh sözleşmesi eksik:", paste(missing_history, collapse = ", "))
  )

  required_gallery_patterns <- c(
    "resolve_effective_user_id(",
    "scan_user_images(uid)",
    "delete_single_image(",
    "delete_all_user_images(",
    "refresh = function() refresh_trigger(refresh_trigger() + 1)"
  )

  missing_gallery <- required_gallery_patterns[!vapply(
    required_gallery_patterns,
    function(pattern) grepl(pattern, gallery_module, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_gallery,
    character(0),
    info = paste("Galeri kullanıcı kapsamı sözleşmesi eksik:", paste(missing_gallery, collapse = ", "))
  )

  required_wiring_patterns <- c(
    "serverBindChatPersistenceModules <- function(",
    "saved_chats_server_fn = savedChatsServer",
    "saved_chats_observers_init_fn = savedChatsObserversInit",
    "image_gallery_runtime_fn = serverBindImageGalleryRuntime",
    "history_server_fn = historyServer",
    "message_search_init_fn = messageSearchInit"
  )

  missing_wiring <- required_wiring_patterns[!vapply(
    required_wiring_patterns,
    function(pattern) grepl(pattern, wiring_module, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_wiring,
    character(0),
    info = paste("Sohbet kalıcılığı wiring sözleşmesi eksik:", paste(missing_wiring, collapse = ", "))
  )
})