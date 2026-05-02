# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-runtime-context-accessors.R
# Açıklama: ServerRuntimeContext bölüm erişim yardımcılarının eksik identity,
#           state ve cache sözleşmelerini erken yakaladığını doğrular.
# ==============================================================================

repo_root <- resolve_repo_root_for_tests()

source(
  file.path(repo_root, "R", "server_runtime_context.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.make_runtime_context_accessor_test_ctx <- function() {
  ctx <- new.env(parent = emptyenv())
  class(ctx) <- c("mergen_server_runtime_context", "environment")

  ctx$identity <- list(
    user_config_rv = function(value) value,
    current_user_id_provider = function() 42L,
    resolve_current_user_id = function() 42L,
    is_auth_ready = function() TRUE
  )

  ctx$state <- list(
    values = list(messages = list()),
    stop_generation = function(value = NULL) value,
    session_files = function() list()
  )

  ctx$cache <- list(
    mcp_saved_path = "mcp_saved",
    cache_mcp_file_locally = function(...) TRUE,
    update_mcp_registry_snapshot = function(...) TRUE
  )

  ctx
}

test_that("runtime section accessors geçerli bölümleri döndürür", {
  ctx <- .make_runtime_context_accessor_test_ctx()

  identity <- serverRuntimeRequireIdentity(
    ctx,
    required_values = c("user_config_rv"),
    required_functions = c("current_user_id_provider", "is_auth_ready")
  )

  state <- serverRuntimeRequireState(
    ctx,
    required_values = c("values"),
    required_functions = c("stop_generation", "session_files")
  )

  cache <- serverRuntimeRequireCache(
    ctx,
    required_values = c("mcp_saved_path"),
    required_functions = c("cache_mcp_file_locally", "update_mcp_registry_snapshot")
  )

  expect_identical(identity, ctx$identity)
  expect_identical(state, ctx$state)
  expect_identical(cache, ctx$cache)
})

test_that("runtime section accessors eksik fonksiyonları erken yakalar", {
  ctx <- .make_runtime_context_accessor_test_ctx()
  ctx$identity$current_user_id_provider <- NULL

  expect_error(
    serverRuntimeRequireIdentity(
      ctx,
      required_functions = c("current_user_id_provider")
    ),
    "eksik zorunlu fonksiyon"
  )
})

test_that("runtime section accessors eksik değerleri erken yakalar", {
  ctx <- .make_runtime_context_accessor_test_ctx()
  ctx$state$values <- NULL

  expect_error(
    serverRuntimeRequireState(
      ctx,
      required_values = c("values")
    ),
    "eksik zorunlu alan"
  )
})

test_that("runtime section accessors geçersiz context ile ilerlemez", {
  expect_error(
    serverRuntimeRequireState(list()),
    "Geçerli bir mergen_server_runtime_context"
  )
})