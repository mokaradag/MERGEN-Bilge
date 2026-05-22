# ==============================================================================
# Dosya Yolu: tests/testthat/test-e2e-sso-identity-readiness-regression.R
# Açıklama: SSO kimlik hazır olma, geçici kullanıcı kimliği ve refreshable modül
#           yarış durumları için deterministik E2E benzeri regresyon testleri.
# ==============================================================================

.find_e2e_sso_repo_root <- function() {
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

  stop("SSO E2E test repo kökünü bulamadı.", call. = FALSE)
}

repo_root_e2e_sso <- .find_e2e_sso_repo_root()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_e2e_sso, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_e2e_sso <- resolve_repo_root_for_tests()

if (!exists("e2e_sso_new_runtime_context", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(
      repo_root_e2e_sso,
      "tests",
      "testthat",
      "helper_e2e_sso_identity_harness.R"
    ),
    encoding = "UTF-8",
    local = globalenv()
  )
}

source(
  file.path(repo_root_e2e_sso, "R", "helpers_server_runtime_contracts.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_e2e_sso, "R", "helpers_server_runtime_named_contracts.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_e2e_sso, "R", "server_runtime_context.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_e2e_sso, "R", "server_runtime_context.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_e2e_sso, "R", "server_module_wiring.R"),
  encoding = "UTF-8",
  local = globalenv()
)

test_that("SSO refreshable modules wait for real user id before first refresh", {
  runtime <- e2e_sso_new_runtime_context(
    user_id = 0L,
    auth_ready = FALSE,
    authenticated = FALSE,
    sso_active = TRUE
  )

  observer_probe <- e2e_sso_new_observer_probe()
  refresh_log <- e2e_sso_new_refresh_log()

  fm_runtime <- serverBindFileManagerRuntime(
    runtime_ctx = runtime$ctx,
    new_file_trigger = function() NULL,
    session_files_reactive = function() list(),
    mcp_enabled_reactive = function() FALSE,
    settings_data = list(),
    user_id_provider = runtime$ctx$identity$current_user_id_provider,
    file_manager_server_fn = e2e_sso_file_manager_server_stub(refresh_log),
    observe_event_fn = observer_probe$observe_event,
    req_fn = e2e_sso_req
  )

  runtime$ctx <- fm_runtime$runtime_ctx

  gallery_runtime <- serverBindImageGalleryRuntime(
    runtime_ctx = runtime$ctx,
    current_user_id_provider = runtime$ctx$identity$current_user_id_provider,
    image_gallery_server_fn = e2e_sso_image_gallery_server_stub(refresh_log),
    observe_event_fn = observer_probe$observe_event,
    req_fn = e2e_sso_req
  )

  runtime$ctx <- gallery_runtime$runtime_ctx

  expect_identical(observer_probe$count(), 2L)
  expect_identical(refresh_log$count(), 0L)

  runtime <- e2e_sso_mark_ready(runtime, user_id = 4242L)
  observer_probe$trigger_all()

  expect_identical(refresh_log$count(), 2L)
  expect_identical(
    refresh_log$modules(),
    c("file_manager", "image_gallery")
  )
  expect_identical(refresh_log$user_ids(), c(4242L, 4242L))
  expect_identical(refresh_log$reasons(), c("auth_ready", "refresh"))
})

test_that("SSO authenticated olsa bile auth_ready olmadan refresh çalışmaz", {
  runtime <- e2e_sso_new_runtime_context(
    user_id = 0L,
    auth_ready = FALSE,
    authenticated = TRUE,
    sso_active = TRUE
  )

  observer_probe <- e2e_sso_new_observer_probe()
  refresh_log <- e2e_sso_new_refresh_log()

  fm_runtime <- serverBindFileManagerRuntime(
    runtime_ctx = runtime$ctx,
    new_file_trigger = function() NULL,
    session_files_reactive = function() list(),
    mcp_enabled_reactive = function() FALSE,
    settings_data = list(),
    user_id_provider = runtime$ctx$identity$current_user_id_provider,
    file_manager_server_fn = e2e_sso_file_manager_server_stub(refresh_log),
    observe_event_fn = observer_probe$observe_event,
    req_fn = e2e_sso_req
  )

  runtime$ctx <- fm_runtime$runtime_ctx

  expect_identical(observer_probe$count(), 1L)
  expect_identical(refresh_log$count(), 0L)

  expect_error(
    observer_probe$trigger_all(),
    "e2e_sso_req_failed",
    fixed = TRUE
  )

  expect_identical(refresh_log$count(), 0L)
  expect_identical(runtime$ctx$identity$current_user_id_provider(), 0L)
})

test_that("already-ready SSO refreshes immediately without stale observer registration", {
  runtime <- e2e_sso_new_runtime_context(
    user_id = 5151L,
    auth_ready = TRUE,
    authenticated = TRUE,
    sso_active = TRUE
  )

  observer_probe <- e2e_sso_new_observer_probe()
  refresh_log <- e2e_sso_new_refresh_log()

  fm_runtime <- serverBindFileManagerRuntime(
    runtime_ctx = runtime$ctx,
    new_file_trigger = function() NULL,
    session_files_reactive = function() list(),
    mcp_enabled_reactive = function() FALSE,
    settings_data = list(),
    user_id_provider = runtime$ctx$identity$current_user_id_provider,
    file_manager_server_fn = e2e_sso_file_manager_server_stub(refresh_log),
    observe_event_fn = observer_probe$observe_event,
    req_fn = e2e_sso_req
  )

  runtime$ctx <- fm_runtime$runtime_ctx

  gallery_runtime <- serverBindImageGalleryRuntime(
    runtime_ctx = runtime$ctx,
    current_user_id_provider = runtime$ctx$identity$current_user_id_provider,
    image_gallery_server_fn = e2e_sso_image_gallery_server_stub(refresh_log),
    observe_event_fn = observer_probe$observe_event,
    req_fn = e2e_sso_req
  )

  runtime$ctx <- gallery_runtime$runtime_ctx

  expect_identical(observer_probe$count(), 0L)
  expect_identical(refresh_log$count(), 2L)
  expect_identical(
    refresh_log$modules(),
    c("file_manager", "image_gallery")
  )
  expect_identical(refresh_log$user_ids(), c(5151L, 5151L))
})

test_that("local non-SSO mode is not changed by SSO auth-ready refresh hook", {
  runtime <- e2e_sso_new_runtime_context(
    user_id = 6161L,
    auth_ready = TRUE,
    authenticated = FALSE,
    sso_active = FALSE
  )

  observer_probe <- e2e_sso_new_observer_probe()
  refresh_log <- e2e_sso_new_refresh_log()

  fm_runtime <- serverBindFileManagerRuntime(
    runtime_ctx = runtime$ctx,
    new_file_trigger = function() NULL,
    session_files_reactive = function() list(),
    mcp_enabled_reactive = function() FALSE,
    settings_data = list(),
    user_id_provider = runtime$ctx$identity$current_user_id_provider,
    file_manager_server_fn = e2e_sso_file_manager_server_stub(refresh_log),
    observe_event_fn = observer_probe$observe_event,
    req_fn = e2e_sso_req
  )

  runtime$ctx <- fm_runtime$runtime_ctx

  gallery_runtime <- serverBindImageGalleryRuntime(
    runtime_ctx = runtime$ctx,
    current_user_id_provider = runtime$ctx$identity$current_user_id_provider,
    image_gallery_server_fn = e2e_sso_image_gallery_server_stub(refresh_log),
    observe_event_fn = observer_probe$observe_event,
    req_fn = e2e_sso_req
  )

  runtime$ctx <- gallery_runtime$runtime_ctx

  expect_identical(observer_probe$count(), 0L)
  expect_identical(refresh_log$count(), 0L)
  expect_identical(runtime$ctx$identity$current_user_id_provider(), 6161L)
})

test_that("runtime wiring keeps SSO identity readiness contracts visible", {
  wiring <- e2e_sso_read_repo_ascii(
    repo_root_e2e_sso,
    "R",
    "server_module_wiring.R"
  )

  required_patterns <- c(
    "serverBindFileManagerRuntime <- function(",
    "auth_ready_provider = identity$is_auth_ready",
    "serverRuntimeAttachRefreshableModule(",
    "label = \"file_manager_refresh\"",
    "refresh_function = \"refresh_persisted_files\"",
    "serverBindImageGalleryRuntime <- function(",
    "label = \"image_gallery_refresh\"",
    "refresh_function = \"refresh\""
  )

  missing_patterns <- required_patterns[!vapply(
    required_patterns,
    function(pattern) grepl(pattern, wiring, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing_patterns,
    character(0),
    info = paste(
      "SSO refreshable module wiring sözleşmesi eksik:",
      paste(missing_patterns, collapse = ", ")
    )
  )

  file_manager_pos <- regexpr(
    "auth_ready_provider = identity$is_auth_ready",
    wiring,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  refreshable_pos <- regexpr(
    "serverRuntimeAttachRefreshableModule(",
    wiring,
    fixed = TRUE,
    useBytes = TRUE
  )[[1]]

  expect_true(file_manager_pos > 0L)
  expect_true(refreshable_pos > 0L)
  expect_true(
    file_manager_pos < refreshable_pos,
    info = paste(
      "File Manager auth_ready_provider modüle aktarılmadan",
      "refreshable module bağlanmamalıdır."
    )
  )
})