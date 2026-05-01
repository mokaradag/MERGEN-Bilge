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

.fake_user_session <- function(user_id = 42L) {
  list(
    user_config_rv = function(...) NULL,
    resolve_current_user_id = function() user_id,
    current_user_id_provider = function() user_id,
    is_auth_ready = function() TRUE,
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