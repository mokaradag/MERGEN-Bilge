# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-runtime-context.R
# Açıklama: ServerRuntimeContext erken server boot sözleşmesini doğrular.
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

.fake_runtime_session <- function() {
  list(
    userData = new.env(parent = emptyenv()),
    token = "test-token"
  )
}

.fake_session_cache <- function() {
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

.fake_user_session <- function(user_id = 42L,
                               sso_active = FALSE,
                               auth_ready = TRUE) {
  list(
    user_config_rv = function(...) NULL,
    resolve_current_user_id = function() user_id,
    current_user_id_provider = function() user_id,
    is_auth_ready = function() isTRUE(auth_ready),
    is_sso_active = function() isTRUE(sso_active),
    get_auth_source = function(default = NULL) {
      if (isTRUE(sso_active)) "keycloak" else "local"
    },
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

test_that("serverRuntimeContextInit cache ve identity sözleşmesini kurar", {
  session <- .fake_runtime_session()

  ctx <- serverRuntimeContextInit(
    session = session,
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session(77L)
  )

  expect_true(is_server_runtime_context(ctx))
  expect_identical(ctx$session, session)
  expect_true(is.function(ctx$cache$cache_mcp_file_locally))
  expect_true(is.function(ctx$cache$update_mcp_registry_snapshot))
  expect_true(is.function(ctx$identity$current_user_id_provider))
  expect_equal(ctx$identity$current_user_id_provider(), 77L)
})

test_that("serverRuntimeContextInit eksik provider alanını erken yakalar", {
  bad_user_session <- .fake_user_session()
  bad_user_session$current_user_id_provider <- NULL

  expect_error(
    serverRuntimeContextInit(
      session = .fake_runtime_session(),
      session_cache = .fake_session_cache(),
      sso_state = list(authenticated = FALSE),
      user_session = bad_user_session
    ),
    "user_session eksik zorunlu fonksiyon"
  )
})

test_that("serverRuntimeAttachForwardRefs ileri referans sözleşmesini doğrular", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session()
  )

  forward_refs <- list(
    welcome_fns = new.env(parent = emptyenv()),
    send_message_fns = new.env(parent = emptyenv()),
    render_welcome_screen = function(...) NULL,
    start_new_chat = function(...) NULL,
    send_message = function(...) NULL
  )

  out <- serverRuntimeAttachForwardRefs(ctx, forward_refs)

  expect_identical(out, ctx)
  expect_true(is.function(ctx$refs$send_message))
  expect_true(is.environment(ctx$refs$welcome_fns))
})

test_that("serverRuntimeAttachState reaktif durum sözleşmesini doğrular", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session()
  )

  state_bundle <- list(
    values = new.env(parent = emptyenv()),
    stop_generation = function(...) NULL,
    file_to_add = function(...) NULL,
    session_files = function(...) NULL,
    active_request_id = function(...) NULL,
    quick_action_skip_mcp = function(...) NULL,
    sync_feedback_from_db = function(...) NULL
  )

  serverRuntimeAttachState(ctx, state_bundle)

  expect_identical(ctx$state, state_bundle)
})

test_that("serverRuntimeAttachFilePrelude dosya ön hazırlık sözleşmesini doğrular", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session()
  )

  file_prelude <- list(
    filePreview = list(id = "file_preview"),
    fallback_followup_tool = list(generate = function(...) list()),
    followup_tools = list(generate = function(...) list())
  )

  out <- serverRuntimeAttachFilePrelude(ctx, file_prelude)

  expect_identical(out, ctx)

  file_runtime <- serverRuntimeRequireFileRuntime(
    ctx,
    require_prelude = TRUE,
    require_manager = FALSE
  )

  expect_identical(file_runtime$filePreview, file_prelude$filePreview)
  expect_true(is.function(file_runtime$fallback_followup_tool$generate))
  expect_true(is.function(file_runtime$followup_tools$generate))

  expect_error(
    serverRuntimeRequireFileRuntime(
      ctx,
      require_prelude = TRUE,
      require_manager = TRUE
    ),
    "file_manager_data"
  )
})

test_that("serverRuntimeAttachFileManager dosya yöneticisi sözleşmesini doğrular", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session()
  )

  file_manager_data <- list(
    refresh_persisted_files = function(reason = NULL) reason,
    file_contents = function(...) list()
  )

  out <- serverRuntimeAttachFileManager(
    ctx,
    file_manager_data = file_manager_data
  )

  expect_identical(out, ctx)

  file_runtime <- serverRuntimeRequireFileRuntime(
    ctx,
    require_prelude = FALSE,
    require_manager = TRUE
  )

  expect_identical(file_runtime$file_manager_data, file_manager_data)

  expect_error(
    serverRuntimeAttachFileManager(
      ctx,
      file_manager_data = list(file_contents = function(...) list())
    ),
    "refresh_persisted_files"
  )
})

test_that("serverRuntimeAttachChat sohbet runtime sözleşmesini doğrular", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session()
  )

  chat_runtime <- list(
    reset_chat_state = function(...) NULL,
    add_message = function(...) NULL,
    generate_title_from_prompt = function(...) NULL,
    simulate_streaming_stoppable = function(...) NULL
  )

  serverRuntimeAttachChat(ctx, chat_runtime)

  expect_identical(ctx$chat, chat_runtime)
})

test_that("serverRuntimeAttachModule modül fonksiyon sözleşmesini isteğe bağlı doğrular", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session()
  )

  module_value <- list(refresh = function(...) NULL)

  serverRuntimeAttachModule(
    ctx,
    name = "image_gallery",
    value = module_value,
    required_functions = "refresh"
  )

  expect_identical(ctx$modules$image_gallery, module_value)
  expect_identical(
    serverRuntimeGetModule(ctx, "image_gallery", required_functions = "refresh"),
    module_value
  )

  expect_error(
    serverRuntimeGetModule(ctx, "missing_module"),
    "kayıtlı değil"
  )

  expect_error(
    serverRuntimeAttachModule(
      ctx,
      name = "broken_module",
      value = list(),
      required_functions = "refresh"
    ),
    "runtime module 'broken_module' eksik zorunlu fonksiyon"
  )
})

test_that("serverRuntimeExposeSessionData oturum verisini açık sözleşmeyle yazar", {
  session <- .fake_runtime_session()

  ctx <- serverRuntimeContextInit(
    session = session,
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session()
  )

  file_manager_data <- list(
    file_contents = function(...) list()
  )

  out <- serverRuntimeExposeSessionData(
    ctx = ctx,
    key = "file_manager_data",
    value = file_manager_data
  )

  expect_identical(out, ctx)
  expect_identical(session$userData$file_manager_data, file_manager_data)

  expect_error(
    serverRuntimeExposeSessionData(
      ctx = ctx,
      key = "file_manager_data",
      value = list(),
      overwrite = FALSE
    ),
    "zaten mevcut"
  )
})

test_that("serverRuntimeCreateFunctionSlot geç bağlanan fonksiyonu güncel hedefe yönlendirir", {
  slot <- serverRuntimeCreateFunctionSlot("trigger_tts_for_message")

  expect_false(slot$is_bound())
  expect_null(slot$call("ai_1", "ilk içerik"))

  called <- NULL

  slot$set(function(message_id, content) {
    called <<- list(
      message_id = message_id,
      content = content
    )

    "tamam"
  })

  expect_true(slot$is_bound())
  expect_identical(slot$call("ai_2", "son içerik"), "tamam")
  expect_identical(called$message_id, "ai_2")
  expect_identical(called$content, "son içerik")

  expect_error(
    slot$set(NULL),
    "fonksiyon olmalıdır"
  )
})

test_that("serverRuntimeRefreshModuleOnSsoAuthReady modül yenilemeyi tek yardımcıyla kurar", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = TRUE),
    user_session = .fake_user_session(sso_active = TRUE, auth_ready = TRUE)
  )

  refreshed_reason <- NULL
  registered <- FALSE

  file_manager_data <- list(
    refresh_persisted_files = function(reason = NULL) {
      refreshed_reason <<- reason
    },
    file_contents = function(...) list()
  )

  serverRuntimeAttachModule(
    ctx,
    name = "file_manager",
    value = file_manager_data,
    required_functions = c("refresh_persisted_files", "file_contents")
  )

  fake_observe_event <- function(eventExpr,
                                 handlerExpr,
                                 ignoreInit = TRUE,
                                 once = TRUE) {
    registered <<- TRUE
    force(handlerExpr)

    list(
      ignoreInit = ignoreInit,
      once = once
    )
  }

  observer <- serverRuntimeRefreshModuleOnSsoAuthReady(
    ctx = ctx,
    module_name = "file_manager",
    refresh_function = "refresh_persisted_files",
    refresh_args = list("auth_ready"),
    label = "file_manager_refresh",
    observe_event_fn = fake_observe_event,
    req_fn = function(...) NULL
  )

  expect_true(registered)
  expect_true(isTRUE(observer$ignoreInit))
  expect_true(isTRUE(observer$once))
  expect_identical(refreshed_reason, "auth_ready")
})

test_that("serverRuntimeAttachRefreshableModule attach, refresh ve oturum uyumluluk yazımını tek yerden yapar", {
  session <- .fake_runtime_session()

  ctx <- serverRuntimeContextInit(
    session = session,
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = TRUE),
    user_session = .fake_user_session(sso_active = TRUE, auth_ready = TRUE)
  )

  refreshed_reason <- NULL
  registered <- FALSE

  file_manager_data <- list(
    refresh_persisted_files = function(reason = NULL) {
      refreshed_reason <<- reason
    },
    file_contents = function(...) list()
  )

  fake_observe_event <- function(eventExpr,
                                 handlerExpr,
                                 ignoreInit = TRUE,
                                 once = TRUE) {
    registered <<- TRUE
    force(handlerExpr)

    list(
      ignoreInit = ignoreInit,
      once = once
    )
  }

  out <- serverRuntimeAttachRefreshableModule(
    ctx = ctx,
    name = "file_manager",
    value = file_manager_data,
    required_functions = c("refresh_persisted_files", "file_contents"),
    refresh_function = "refresh_persisted_files",
    refresh_args = list("auth_ready"),
    label = "file_manager_refresh",
    expose_session_key = "file_manager_data",
    observe_event_fn = fake_observe_event,
    req_fn = function(...) NULL
  )

  expect_identical(out, ctx)
  expect_identical(ctx$modules$file_manager, file_manager_data)
  expect_identical(session$userData$file_manager_data, file_manager_data)
  expect_true(registered)
  expect_identical(refreshed_reason, "auth_ready")
})

test_that("serverRuntimeRefreshModuleOnSsoAuthReady eksik modülü SSO modunda erken yakalar", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session(sso_active = TRUE, auth_ready = FALSE)
  )

  expect_error(
    serverRuntimeRefreshModuleOnSsoAuthReady(
      ctx = ctx,
      module_name = "file_manager",
      refresh_function = "refresh_persisted_files",
      observe_event_fn = function(...) NULL
    ),
    "kayıtlı değil"
  )
})

test_that("serverRuntimeOnSsoAuthReady yerel modda mevcut akışı değiştirmez", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session(sso_active = FALSE, auth_ready = TRUE)
  )

  called <- FALSE

  out <- serverRuntimeOnSsoAuthReady(
    ctx,
    label = "local_noop",
    callback = function(ctx) {
      called <<- TRUE
    }
  )

  expect_false(isTRUE(out))
  expect_false(called)
})

test_that("serverRuntimeOnSsoAuthReady SSO observer kaydını tek sözleşmeden yapar", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = list(authenticated = FALSE),
    user_session = .fake_user_session(sso_active = TRUE, auth_ready = FALSE)
  )

  registered <- FALSE

  fake_observe_event <- function(eventExpr,
                                 handlerExpr,
                                 ignoreInit = TRUE,
                                 once = TRUE) {
    registered <<- TRUE

    list(
      ignoreInit = ignoreInit,
      once = once
    )
  }

  observer <- serverRuntimeOnSsoAuthReady(
    ctx,
    label = "sso_registration",
    callback = function(ctx) NULL,
    observe_event_fn = fake_observe_event
  )

  expect_true(registered)
  expect_true(isTRUE(observer$ignoreInit))
  expect_true(isTRUE(observer$once))
})

test_that("serverRuntimeOnSsoAuthReady SSO durum sözleşmesini erken doğrular", {
  ctx <- serverRuntimeContextInit(
    session = .fake_runtime_session(),
    session_cache = .fake_session_cache(),
    sso_state = NULL,
    user_session = .fake_user_session(sso_active = TRUE, auth_ready = FALSE)
  )

	expect_error(
	  serverRuntimeOnSsoAuthReady(
		ctx,
		label = "missing_sso_state",
		callback = function(ctx) NULL
	  ),
	  "SSO modunda sso_state gereklidir"
	)
})