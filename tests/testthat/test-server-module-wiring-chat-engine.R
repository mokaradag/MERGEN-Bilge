# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-module-wiring-chat-engine.R
# Açıklama: Sohbet motoru wiring sözleşmesini doğrular. Amaç server.R içindeki
#           LLM/TTS/send-message sıralama bağımlılığının tekrar büyümesini
#           engellemektir.
# ==============================================================================

repo_root <- resolve_repo_root_for_tests()

source(
  file.path(repo_root, "R", "server_runtime_context.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root, "R", "server_runtime_function_slot.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root, "R", "server_module_wiring.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.fake_chat_engine_session <- function() {
  list(
    userData = new.env(parent = emptyenv()),
    token = "chat-engine-test-token"
  )
}

.fake_chat_engine_cache <- function() {
  list(
    mcp_saved_path = function(...) NULL,
    cache_root = tempdir(),
    setup_user_session = function(user_id) {
      file.path(tempdir(), paste0("user_", user_id))
    },
    cache_mcp_file_locally = function(path) path,
    update_mcp_registry_snapshot = function(files_snapshot = NULL) {
      files_snapshot
    },
    get_cache_dir = function() tempdir()
  )
}

.fake_chat_engine_user_session <- function(user_id = 42L) {
  list(
    user_config_rv = function(...) NULL,
    resolve_current_user_id = function() user_id,
    current_user_id_provider = function() user_id,
    is_auth_ready = function() TRUE,
    is_sso_active = function() FALSE,
    get_auth_source = function(default = NULL) "local",
    get_user_config = function(default = NULL) list(
      name = "Test User",
      first_name = "Test",
      userId = as.character(user_id)
    ),
    get_first_name = function(default = "") "Test",
    get_display_name = function(default = "Kullanıcı") "Test User",
    get_current_user_id_snapshot = function() user_id,
    get_cache_dir = function() tempdir()
  )
}

.fake_chat_engine_context <- function(session) {
  ctx <- serverRuntimeContextInit(
    session = session,
    session_cache = .fake_chat_engine_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_chat_engine_user_session()
  )

  state_bundle <- list(
    values = new.env(parent = emptyenv()),
    stop_generation = function(...) FALSE,
    file_to_add = function(...) NULL,
    session_files = function(...) list(),
    active_request_id = function(...) NULL,
    quick_action_skip_mcp = function(...) FALSE,
    sync_feedback_from_db = function(...) NULL
  )

  ctx <- serverRuntimeAttachState(ctx, state_bundle)

  ctx <- serverRuntimeAttachFilePrelude(
    ctx,
    list(
      filePreview = list(id = "file_preview"),
      fallback_followup_tool = list(generate = function(...) list()),
      followup_tools = list(generate = function(...) list())
    )
  )

  ctx <- serverRuntimeAttachFileManager(
    ctx,
    list(
      refresh_persisted_files = function(reason = NULL) reason,
      file_contents = function(...) list()
    )
  )

  ctx
}

test_that("serverBindChatEngineRuntime sohbet motorunu tek sözleşmeden bağlar", {
  session <- .fake_chat_engine_session()
  runtime_ctx <- .fake_chat_engine_context(session)

  observed <- new.env(parent = emptyenv())
  observed$chat_input <- FALSE
  observed$misc <- FALSE
  observed$chat_actions <- FALSE
  observed$send_message_init <- FALSE
  observed$tts_called <- NULL

  send_message_fns <- new.env(parent = emptyenv())

  chat_runtime_init_fn <- function(...) {
    list(
      reset_chat_state = function(...) "reset",
      add_message = function(...) list(id = "ai_1"),
      generate_title_from_prompt = function(...) "başlık",
      simulate_streaming_stoppable = function(...) "stream"
    )
  }

  llm_response_handlers_init_fn <- function(...) {
    args <- list(...)
    trigger_tts_fn <- args$trigger_tts_fn

    list(
      generate_non_streaming_stoppable = function(...) {
        trigger_tts_fn("ai_1", "Yanıt içeriği")
        "llm-tamam"
      }
    )
  }

  chat_input_observers_init_fn <- function(...) {
    observed$chat_input <- TRUE
    invisible(NULL)
  }

  misc_observers_init_fn <- function(...) {
    observed$misc <- TRUE
    invisible(NULL)
  }

  chat_actions_init_fn <- function(...) {
    observed$chat_actions <- TRUE
    invisible(NULL)
  }

  tts_handlers_init_fn <- function(...) {
    list(
      trigger_tts_for_message = function(message_id, content) {
        observed$tts_called <- list(
          message_id = message_id,
          content = content
        )

        invisible(NULL)
      },
      attach_tts_audio = function(...) invisible(NULL)
    )
  }

  send_message_init_fn <- function(...) {
    observed$send_message_init <- TRUE

    list(
      send_message = function(...) "gönderildi"
    )
  }

  result <- serverBindChatEngineRuntime(
    input = list(),
    output = list(),
    session = session,
    runtime_ctx = runtime_ctx,
    settings_data = list(),
    api_key = function(...) NULL,
    user_config_rv = function(...) list(),
    perf_tracker = list(
      track_error = function(...) NULL,
      track_request = function(...) NULL
    ),
    ai_processor = list(
      call_llm_non_streaming = function(...) NULL
    ),
    tts_processor = list(),
    tts_visualizer = list(),
    stt_data = list(),
    saved_chats_data = list(),
    send_message_fns = send_message_fns,
    send_message_proxy = function(...) "proxy",
    api_config = list(),
    admin_pool = NULL,
    chat_runtime_init_fn = chat_runtime_init_fn,
    llm_response_handlers_init_fn = llm_response_handlers_init_fn,
    chat_input_observers_init_fn = chat_input_observers_init_fn,
    misc_observers_init_fn = misc_observers_init_fn,
    chat_actions_init_fn = chat_actions_init_fn,
    tts_handlers_init_fn = tts_handlers_init_fn,
    send_message_init_fn = send_message_init_fn
  )

  expect_true(is_server_runtime_context(result$runtime_ctx))
  expect_true(observed$chat_input)
  expect_true(observed$misc)
  expect_true(observed$chat_actions)
  expect_true(observed$send_message_init)

  expect_true(is.function(result$send_message))
  expect_identical(send_message_fns$send_message, result$send_message)
  expect_identical(result$send_message(), "gönderildi")

  expect_true(result$chat_engine$tts_trigger_slot$is_bound())
  expect_identical(
    result$chat_engine$llm_handlers$generate_non_streaming_stoppable(),
    "llm-tamam"
  )

  expect_identical(observed$tts_called$message_id, "ai_1")
  expect_identical(observed$tts_called$content, "Yanıt içeriği")

  registered_engine <- serverRuntimeGetModule(
    result$runtime_ctx,
    "chat_engine",
    required_functions = c("send_message", "trigger_tts_for_message")
  )

  expect_identical(registered_engine$send_message, result$send_message)
})