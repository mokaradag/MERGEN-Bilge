# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-module-wiring-runtime-bindings.R
# Açıklama: server_module_wiring içindeki runtime modül bağlama yardımcılarının
#           server.R dışına taşınan sözleşmeleri koruduğunu doğrular.
# ==============================================================================

repo_root <- resolve_repo_root_for_tests()

source(
  file.path(repo_root, "R", "server_runtime_context.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root, "R", "server_module_wiring.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.fake_wiring_session <- function() {
  list(
    userData = new.env(parent = emptyenv()),
    token = "test-token"
  )
}

.fake_wiring_session_cache <- function() {
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

.fake_wiring_user_session <- function(user_id = 42L,
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

.fake_wiring_runtime_context <- function(session = .fake_wiring_session(),
                                         sso_active = FALSE,
                                         auth_ready = TRUE) {
  serverRuntimeContextInit(
    session = session,
    session_cache = .fake_wiring_session_cache(),
    sso_state = list(authenticated = auth_ready),
    user_session = .fake_wiring_user_session(
      sso_active = sso_active,
      auth_ready = auth_ready
    )
  )
}

test_that("serverBindFileManagerRuntime dosya yöneticisini runtime context'e bağlar", {
  session <- .fake_wiring_session()
  runtime_ctx <- .fake_wiring_runtime_context(session = session)

  called <- FALSE

  fake_file_manager_server <- function(id,
                                       new_file_trigger,
                                       session_files_reactive,
                                       mcp_enabled_reactive,
                                       user_id,
                                       settings_data,
                                       auth_ready_provider) {
    called <<- TRUE

    expect_identical(id, "file_manager_module")
    expect_true(is.function(new_file_trigger))
    expect_true(is.function(session_files_reactive))
    expect_true(is.function(mcp_enabled_reactive))
    expect_true(is.function(user_id))
    expect_true(is.function(auth_ready_provider))
    expect_identical(user_id(), 42L)
    expect_true(isTRUE(auth_ready_provider()))

    list(
      refresh_persisted_files = function(reason = NULL) reason,
      file_contents = function(...) list()
    )
  }

  out <- serverBindFileManagerRuntime(
    runtime_ctx = runtime_ctx,
    new_file_trigger = function() NULL,
    session_files_reactive = function() list(),
    mcp_enabled_reactive = function() TRUE,
    settings_data = list(enable_mcp_tools = TRUE),
    user_id_provider = runtime_ctx$identity$current_user_id_provider,
    file_manager_server_fn = fake_file_manager_server,
    observe_event_fn = function(...) {
      stop("Yerel modda SSO observer kaydı beklenmez.", call. = FALSE)
    }
  )

  expect_true(called)
  expect_true(is_server_runtime_context(out$runtime_ctx))
  expect_identical(out$file_manager_data, runtime_ctx$modules$file_manager)
  expect_identical(session$userData$file_manager_data, out$file_manager_data)
  expect_true(is.function(out$file_manager_data$refresh_persisted_files))
  expect_true(is.function(out$file_manager_data$file_contents))
})

test_that("serverBindFileManagerRuntime eksik dosya yöneticisi sözleşmesini erken yakalar", {
  runtime_ctx <- .fake_wiring_runtime_context()

  broken_file_manager_server <- function(...) {
    list(
      file_contents = function(...) list()
    )
  }

  expect_error(
    serverBindFileManagerRuntime(
      runtime_ctx = runtime_ctx,
      new_file_trigger = function() NULL,
      session_files_reactive = function() list(),
      mcp_enabled_reactive = function() TRUE,
      settings_data = list(),
      user_id_provider = runtime_ctx$identity$current_user_id_provider,
      file_manager_server_fn = broken_file_manager_server
    ),
    "refresh_persisted_files"
  )
})

test_that("serverBindImageGalleryRuntime görsel galerisini runtime context'e bağlar", {
  runtime_ctx <- .fake_wiring_runtime_context()

  called <- FALSE

  fake_image_gallery_server <- function(id, current_user_id_provider) {
    called <<- TRUE

    expect_identical(id, "image_gallery_module")
    expect_true(is.function(current_user_id_provider))
    expect_identical(current_user_id_provider(), 42L)

    list(
      refresh = function(...) TRUE
    )
  }

  out <- serverBindImageGalleryRuntime(
    runtime_ctx = runtime_ctx,
    current_user_id_provider = runtime_ctx$identity$current_user_id_provider,
    image_gallery_server_fn = fake_image_gallery_server,
    observe_event_fn = function(...) {
      stop("Yerel modda SSO observer kaydı beklenmez.", call. = FALSE)
    }
  )

  expect_true(called)
  expect_true(is_server_runtime_context(out$runtime_ctx))
  expect_identical(out$gallery_data, runtime_ctx$modules$image_gallery)
  expect_true(is.function(out$gallery_data$refresh))
})

test_that("serverBindImageGalleryRuntime eksik galeri sözleşmesini erken yakalar", {
  runtime_ctx <- .fake_wiring_runtime_context()

  broken_image_gallery_server <- function(...) {
    list()
  }

  expect_error(
    serverBindImageGalleryRuntime(
      runtime_ctx = runtime_ctx,
      current_user_id_provider = runtime_ctx$identity$current_user_id_provider,
      image_gallery_server_fn = broken_image_gallery_server
    ),
    "refresh"
  )
})