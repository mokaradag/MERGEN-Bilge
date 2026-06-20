# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-core-interaction-runtime.R
# Açıklama: server_core_interaction_runtime bağlayıcısının server.R dışına alınan
#           gözlemci/dosya/kalıcılık sırasını koruduğunu doğrular.
# ==============================================================================

repo_root <- resolve_repo_root_for_tests()

source(
  file.path(repo_root, "R", "server_runtime_context.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root, "R", "server_runtime_auth_ready.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root, "R", "server_core_interaction_runtime.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# serverBindCoreInteractionRuntime varsayılan core_observer_runtime_fn olarak
# serverBindCoreObserverRuntime'ı çağırır; izole koşumda sahibini yükleriz.
source(
  file.path(repo_root, "R", "server_core_observer_runtime.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# bootReadinessInit() server_core_interaction_runtime tarafından çağrılır;
# izole koşumda gerçek sahibini (module_boot_readiness.R) açıkça yükleriz.
source(
  file.path(repo_root, "R", "module_boot_readiness.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.fake_core_session <- function() {
  list(
    userData = new.env(parent = emptyenv()),
    token = "test-token"
  )
}

.fake_core_session_cache <- function() {
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

.fake_core_user_session <- function(user_id = 42L) {
  list(
    user_config_rv = function(...) NULL,
    resolve_current_user_id = function() user_id,
    current_user_id_provider = function() user_id,
    is_auth_ready = function() TRUE,
    is_sso_active = function() FALSE,
    get_auth_source = function(default = NULL) "local",
    get_user_config = function(default = NULL) {
      list(
        name = "Test User",
        first_name = "Test",
        userId = as.character(user_id)
      )
    },
    get_first_name = function(default = "") "Test",
    get_display_name = function(default = "Kullanıcı") "Test User",
    get_current_user_id_snapshot = function() user_id,
    get_cache_dir = function() tempdir()
  )
}

.fake_core_runtime_context <- function(with_state = TRUE) {
  session <- .fake_core_session()

  ctx <- serverRuntimeContextInit(
    session = session,
    session_cache = .fake_core_session_cache(),
    sso_state = list(authenticated = TRUE),
    user_session = .fake_core_user_session()
  )

  if (isTRUE(with_state)) {
    values <- list(
      saved_chats = list(),
      messages = list()
    )

    ctx <- serverRuntimeAttachState(
      ctx,
      list(
        values = values,
        stop_generation = function(...) FALSE,
        file_to_add = function(...) NULL,
        session_files = function(...) list(),
        active_request_id = function(...) NULL,
        quick_action_skip_mcp = function(...) FALSE,
        sync_feedback_from_db = function(...) TRUE
      )
    )

    ctx <- serverRuntimeAttachFilePrelude(
      ctx,
      list(
        filePreview = list(id = "file_preview"),
        fallback_followup_tool = list(generate = function(...) list()),
        followup_tools = list(generate = function(...) list())
      )
    )
  }

  ctx
}

.fake_core_reactive <- function(x) {
  force(x)
  function() x
}

test_that("serverBindCoreInteractionRuntime çekirdek bağlama sırasını korur", {
  calls <- character(0)

  record <- function(name) {
    calls <<- c(calls, name)
    invisible(TRUE)
  }

  runtime_ctx <- .fake_core_runtime_context()

  fake_file_manager_runtime <- function(runtime_ctx,
                                        new_file_trigger,
                                        session_files_reactive,
                                        mcp_enabled_reactive,
                                        settings_data,
                                        user_id_provider) {
    record("file_manager_runtime")

    expect_true(is.function(new_file_trigger))
    expect_true(is.function(session_files_reactive))
    expect_true(is.function(mcp_enabled_reactive))
    expect_true(is.function(user_id_provider))
    expect_identical(user_id_provider(), 42L)

    file_manager_data <- list(
      refresh_persisted_files = function(...) TRUE,
      file_contents = function(...) list()
    )

    runtime_ctx <- serverRuntimeAttachFileManager(
      ctx = runtime_ctx,
      file_manager_data = file_manager_data
    )

    list(
      runtime_ctx = runtime_ctx,
      file_manager_data = file_manager_data
    )
  }

  fake_chat_persistence <- function(input,
                                    output,
                                    session,
                                    runtime_ctx,
                                    values,
                                    settings_data,
                                    load_chat_in_progress,
                                    session_files,
                                    filePreview,
                                    file_manager_data,
                                    current_user_id_provider,
                                    user_config_provider,
                                    user_first_name_fn,
                                    welcome_fns) {
    record("chat_persistence")

    expect_true(is_server_runtime_context(runtime_ctx))
    expect_true(is.function(session_files))
    expect_true(is.function(file_manager_data$refresh_persisted_files))
    expect_identical(current_user_id_provider(), 42L)
    expect_identical(user_first_name_fn(default = ""), "Test")
    expect_identical(user_config_provider(default = NULL)$name, "Test User")
    expect_true(is.environment(welcome_fns))

    list(
      runtime_ctx = runtime_ctx,
      saved_chats_data = list(refresh = function(...) TRUE)
    )
  }

  out <- serverBindCoreInteractionRuntime(
    input = list(),
    output = list(),
    session = .fake_core_session(),
    runtime_ctx = runtime_ctx,
    core_bundle = serverBuildCoreInteractionBundle(
      settings_data = list(enable_mcp_tools = TRUE),
      api_config = list(),
      media_modules = list(
        ai_expert = list(),
        tts_processor = list()
      ),
      render_welcome_screen = function(...) TRUE,
      start_new_chat = function(...) TRUE,
      send_message = function(...) TRUE,
      load_chat_in_progress = function(...) FALSE,
      welcome_fns = new.env(parent = emptyenv()),
      user_config_provider = function(default = NULL) {
        runtime_ctx$identity$get_user_config(default = default)
      },
      user_first_name_fn = function(default = "") {
        runtime_ctx$identity$get_first_name(default = default)
      }
    ),
    chat_rebind_all_charts_fn = function(...) TRUE,
    chat_export_init_fn = function(..., user_display_name) {
      record("chat_export")
      expect_identical(user_display_name(), "Test User")
    },
    quick_actions_init_fn = function(..., current_user_id, send_message_fn) {
      record("quick_actions")
      expect_identical(current_user_id(), 42L)
      expect_true(is.function(send_message_fn))
    },
    settings_observers_init_fn = function(...) {
      record("settings_observers")
    },
    session_timeout_server_fn = function(id, idle_minutes, activity_inputs) {
      record("session_timeout")
      expect_identical(id, "session_timeout")
      expect_identical(idle_minutes, 30)
      expect_true("user_input" %in% activity_inputs)
    },
    file_manager_runtime_fn = fake_file_manager_runtime,
    chat_ui_observers_init_fn = function(...) {
      record("chat_ui_observers")
    },
    navigation_observers_init_fn = function(...) {
      record("navigation_observers")
    },
    startup_observers_init_fn = function(...) {
      record("startup_observers")
    },
    startup_screen_observers_init_fn = function(...) {
      record("startup_screen_observers")
    },
    ai_expert_handlers_init_fn = function(..., chat_history_rv) {
      record("ai_expert_handlers")
      expect_true(is.function(chat_history_rv))
    },
    storage_observers_init_fn = function(...) {
      record("storage_observers")
    },
    file_observers_init_fn = function(...) {
      record("file_observers")
    },
    file_click_observers_init_fn = function(...) {
      record("file_click_observers")
    },
    chat_persistence_modules_fn = fake_chat_persistence,
    reactive_fn = .fake_core_reactive
  )

  expect_identical(
    calls,
    c(
      "chat_export",
      "quick_actions",
      "settings_observers",
      "session_timeout",
      "file_manager_runtime",
      "chat_ui_observers",
      "navigation_observers",
      "startup_observers",
      "startup_screen_observers",
      "ai_expert_handlers",
      "storage_observers",
      "file_observers",
      "file_click_observers",
      "chat_persistence"
    )
  )

  expect_true(is_server_runtime_context(out$runtime_ctx))
  expect_true(is.function(out$file_manager_data$refresh_persisted_files))
  expect_true(is.function(out$saved_chats_data$refresh))
  expect_identical(out$filePreview$id, "file_preview")
})

test_that("serverBindCoreInteractionRuntime eksik state sözleşmesini erken yakalar", {
  runtime_ctx <- .fake_core_runtime_context(with_state = FALSE)

  expect_error(
    serverBindCoreInteractionRuntime(
      input = list(),
      output = list(),
      session = .fake_core_session(),
      runtime_ctx = runtime_ctx,
      settings_data = list(),
      api_config = list(),
      media_modules = list(ai_expert = list(), tts_processor = list()),
      render_welcome_screen = function(...) TRUE,
      start_new_chat = function(...) TRUE,
      send_message = function(...) TRUE,
      load_chat_in_progress = function(...) FALSE,
      welcome_fns = new.env(parent = emptyenv()),
      user_config_provider = function(default = NULL) default,
      user_first_name_fn = function(default = "") default,
      reactive_fn = .fake_core_reactive
    ),
    "eksik zorunlu alan.*state"
  )
})
