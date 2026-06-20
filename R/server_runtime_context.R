# ==============================================================================
# Dosya Yolu: R/server_runtime_context.R
# Açıklama: server.R erken başlatma nesneleri için küçük, açık sözleşmeli
#           çalışma zamanı bağlamı. Amaç server.R içindeki gevşek değişken
#           yayılımını azaltmak ve eksik/yanlış init sırasını erken yakalamaktır.
#
#           SSO sonrası (post-auth) işleri + yenilenebilir modül wiring katmanı
#           (serverRuntimeOnSsoAuthReady, serverRuntimeRefreshModuleOnSsoAuthReady,
#           serverRuntimeAttachRefreshableModule) odaklı bir dosyaya ayrılmıştır:
#           R/server_runtime_auth_ready.R (manifestte bu dosyadan SONRA yüklenir).
#           Bu dosya runtime context init/attach/require yardımcılarını ve modül
#           kayıt yardımcılarını (AttachModule/GetModule/ExposeSessionData) tutar.
# ==============================================================================

.server_runtime_contract_files <- c("helpers_server_runtime_contracts.R", "helpers_server_runtime_named_contracts.R")
.server_runtime_contract_helpers <- c(
  "is_server_runtime_context", ".server_runtime_stop",
  ".server_runtime_require_context", ".server_runtime_require_values",
  ".server_runtime_require_functions", ".server_runtime_require_named_functions",
  ".server_runtime_require_environment", ".server_runtime_invoke_auth_ready_callback"
)
.server_runtime_missing_contract_helpers <- .server_runtime_contract_helpers[!vapply(.server_runtime_contract_helpers, exists, logical(1), mode = "function", inherits = TRUE)]

if (length(.server_runtime_missing_contract_helpers) > 0L) {
  # Yedek yükleme yalnızca izole test/hata ayıklama bağlamında devreye girer.
  # testthat tests/testthat'a setwd ettiğinden göreli "R/<dosya>" yolu güvenilmez;
  # WD-bağımsız aday köklerden (getwd, üst dizinler, MERGEN_REPO_ROOT) çözeriz.
  .server_runtime_roots <- unique(c(getwd(), dirname(getwd()), dirname(dirname(getwd())),
    Sys.getenv("MERGEN_REPO_ROOT", unset = NA_character_),
    if (exists("repo_root_for_tests", inherits = TRUE)) as.character(repo_root_for_tests)[1] else NA_character_))
  .server_runtime_roots <- .server_runtime_roots[!is.na(.server_runtime_roots) & nzchar(.server_runtime_roots)]
  for (.server_runtime_cfile in .server_runtime_contract_files) {
    .server_runtime_paths <- file.path(.server_runtime_roots, "R", .server_runtime_cfile)
    .server_runtime_paths <- .server_runtime_paths[file.exists(.server_runtime_paths)]
    if (length(.server_runtime_paths) > 0L) source(.server_runtime_paths[1], encoding = "UTF-8", local = globalenv())
  }
  .server_runtime_missing_contract_helpers <- .server_runtime_contract_helpers[!vapply(.server_runtime_contract_helpers, exists, logical(1), mode = "function", inherits = TRUE)]
}

if (length(.server_runtime_missing_contract_helpers) > 0L) {
  stop(sprintf(
    "server_runtime_context: Eksik sözleşme yardımcıları: %s",
    paste(.server_runtime_missing_contract_helpers, collapse = ", ")
  ), call. = FALSE)
}

rm(list = intersect(c(
  ".server_runtime_contract_files", ".server_runtime_contract_helpers",
  ".server_runtime_missing_contract_helpers", ".server_runtime_roots", ".server_runtime_cfile", ".server_runtime_paths"
), ls()))

serverRuntimeRequireIdentity <- function(ctx,
                                         required_values = character(0),
                                         required_functions = character(0),
                                         owner = "runtime identity") {
  .server_runtime_require_context(ctx)

  .server_runtime_require_values(
    ctx,
    c("identity"),
    "server_runtime_context"
  )

  if (!is.list(ctx$identity)) {
    .server_runtime_stop(
      "serverRuntimeRequireIdentity: runtime_ctx$identity liste olmalıdır."
    )
  }

  if (length(required_values) > 0L) {
    .server_runtime_require_values(
      ctx$identity,
      required_values,
      owner
    )
  }

  if (length(required_functions) > 0L) {
    .server_runtime_require_functions(
      ctx$identity,
      required_functions,
      owner
    )
  }

  ctx$identity
}

serverRuntimeRequireState <- function(ctx,
                                      required_values = character(0),
                                      required_functions = character(0),
                                      owner = "runtime state") {
  .server_runtime_require_context(ctx)

  .server_runtime_require_values(
    ctx,
    c("state"),
    "server_runtime_context"
  )

  if (!is.list(ctx$state)) {
    .server_runtime_stop(
      "serverRuntimeRequireState: runtime_ctx$state liste olmalıdır."
    )
  }

  if (length(required_values) > 0L) {
    .server_runtime_require_values(
      ctx$state,
      required_values,
      owner
    )
  }

  if (length(required_functions) > 0L) {
    .server_runtime_require_functions(
      ctx$state,
      required_functions,
      owner
    )
  }

  ctx$state
}

serverRuntimeRequireCache <- function(ctx,
                                      required_values = character(0),
                                      required_functions = character(0),
                                      owner = "runtime cache") {
  .server_runtime_require_context(ctx)

  .server_runtime_require_values(
    ctx,
    c("cache"),
    "server_runtime_context"
  )

  if (!is.list(ctx$cache)) {
    .server_runtime_stop(
      "serverRuntimeRequireCache: runtime_ctx$cache liste olmalıdır."
    )
  }

  if (length(required_values) > 0L) {
    .server_runtime_require_values(
      ctx$cache,
      required_values,
      owner
    )
  }

  if (length(required_functions) > 0L) {
    .server_runtime_require_functions(
      ctx$cache,
      required_functions,
      owner
    )
  }

  ctx$cache
}

serverRuntimeContextInit <- function(session,
                                     session_cache,
                                     sso_state,
                                     user_session) {
  if (is.null(session) || is.null(session$userData)) {
    .server_runtime_stop(
      "serverRuntimeContextInit: session$userData bulunamadı."
    )
  }

  .server_runtime_require_values(
    session_cache,
    c("mcp_saved_path"),
    "session_cache"
  )

  .server_runtime_require_functions(
    session_cache,
    c(
      "setup_user_session",
      "cache_mcp_file_locally",
      "update_mcp_registry_snapshot",
      "get_cache_dir"
    ),
    "session_cache"
  )

  .server_runtime_require_values(
    user_session,
    c("user_config_rv"),
    "user_session"
  )

  .server_runtime_require_functions(
    user_session,
    c(
      "resolve_current_user_id",
      "current_user_id_provider",
      "is_auth_ready",
      "is_sso_active",
      "get_auth_source",
      "get_user_config",
      "get_first_name",
      "get_display_name",
      "get_current_user_id_snapshot",
      "get_cache_dir"
    ),
    "user_session"
  )

  ctx <- new.env(parent = emptyenv())
  class(ctx) <- c("mergen_server_runtime_context", "environment")

  ctx$session <- session
  ctx$sso_state <- sso_state

  ctx$cache <- list(
    mcp_saved_path = session_cache$mcp_saved_path,
    cache_root = session_cache$cache_root,
    setup_user_session = session_cache$setup_user_session,
    cache_mcp_file_locally = session_cache$cache_mcp_file_locally,
    update_mcp_registry_snapshot = session_cache$update_mcp_registry_snapshot,
    get_cache_dir = session_cache$get_cache_dir
  )

  ctx$identity <- list(
    user_config_rv = user_session$user_config_rv,
    resolve_current_user_id = user_session$resolve_current_user_id,
    current_user_id_provider = user_session$current_user_id_provider,
    is_auth_ready = user_session$is_auth_ready,
    is_sso_active = user_session$is_sso_active,
    get_auth_source = user_session$get_auth_source,
    get_user_config = user_session$get_user_config,
    get_first_name = user_session$get_first_name,
    get_display_name = user_session$get_display_name,
    get_current_user_id_snapshot = user_session$get_current_user_id_snapshot,
    get_cache_dir = user_session$get_cache_dir
  )

  ctx$refs <- NULL
  ctx$state <- NULL
  ctx$file <- NULL
  ctx$chat <- NULL
  ctx$modules <- list()

  ctx
}

serverRuntimeAttachForwardRefs <- function(ctx, forward_refs) {
  .server_runtime_require_context(ctx)

  .server_runtime_require_values(
    forward_refs,
    c("welcome_fns", "send_message_fns"),
    "forward_refs"
  )

  .server_runtime_require_functions(
    forward_refs,
    c("render_welcome_screen", "start_new_chat", "send_message"),
    "forward_refs"
  )

  ctx$refs <- forward_refs

  invisible(ctx)
}

serverRuntimeAttachState <- function(ctx, state_bundle) {
  .server_runtime_require_context(ctx)

  .server_runtime_require_values(
    state_bundle,
    c("values"),
    "state_bundle"
  )

  .server_runtime_require_functions(
    state_bundle,
    c(
      "stop_generation",
      "file_to_add",
      "session_files",
      "active_request_id",
      "quick_action_skip_mcp",
      "sync_feedback_from_db"
    ),
    "state_bundle"
  )

  ctx$state <- state_bundle

  invisible(ctx)
}

serverRuntimeAttachFilePrelude <- function(ctx, file_prelude) {
  .server_runtime_require_context(ctx)

  .server_runtime_require_values(
    file_prelude,
    c("filePreview", "fallback_followup_tool", "followup_tools"),
    "file_prelude"
  )

  .server_runtime_require_functions(
    file_prelude$fallback_followup_tool,
    c("generate"),
    "file_prelude$fallback_followup_tool"
  )

  .server_runtime_require_functions(
    file_prelude$followup_tools,
    c("generate"),
    "file_prelude$followup_tools"
  )

  if (is.null(ctx$file)) {
    ctx$file <- list()
  }

  ctx$file$filePreview <- file_prelude$filePreview
  ctx$file$fallback_followup_tool <- file_prelude$fallback_followup_tool
  ctx$file$followup_tools <- file_prelude$followup_tools

  invisible(ctx)
}

serverRuntimeAttachFileManager <- function(ctx, file_manager_data) {
  .server_runtime_require_context(ctx)

  .server_runtime_require_functions(
    file_manager_data,
    c("refresh_persisted_files", "file_contents"),
    "file_manager_data"
  )

  if (is.null(ctx$file)) {
    ctx$file <- list()
  }

  ctx$file$file_manager_data <- file_manager_data

  invisible(ctx)
}

serverRuntimeRequireFileRuntime <- function(ctx,
                                            require_prelude = TRUE,
                                            require_manager = FALSE) {
  .server_runtime_require_context(ctx)

  if (is.null(ctx$file)) {
    .server_runtime_stop(
      "serverRuntimeRequireFileRuntime: Dosya runtime bağlamı henüz kurulmadı."
    )
  }

  if (isTRUE(require_prelude)) {
    .server_runtime_require_values(
      ctx$file,
      c("filePreview", "fallback_followup_tool", "followup_tools"),
      "file_runtime"
    )

    .server_runtime_require_functions(
      ctx$file$fallback_followup_tool,
      c("generate"),
      "file_runtime$fallback_followup_tool"
    )

    .server_runtime_require_functions(
      ctx$file$followup_tools,
      c("generate"),
      "file_runtime$followup_tools"
    )
  }

  if (isTRUE(require_manager)) {
    .server_runtime_require_values(
      ctx$file,
      c("file_manager_data"),
      "file_runtime"
    )

    .server_runtime_require_functions(
      ctx$file$file_manager_data,
      c("refresh_persisted_files", "file_contents"),
      "file_runtime$file_manager_data"
    )
  }

  ctx$file
}

serverRuntimeAttachChat <- function(ctx, chat_runtime) {
  .server_runtime_require_context(ctx)

  .server_runtime_require_functions(
    chat_runtime,
    c(
      "reset_chat_state",
      "add_message",
      "generate_title_from_prompt",
      "simulate_streaming_stoppable"
    ),
    "chat_runtime"
  )

  ctx$chat <- chat_runtime

  invisible(ctx)
}

serverRuntimeAttachModule <- function(ctx,
                                      name,
                                      value,
                                      required_functions = character(0)) {
  .server_runtime_require_context(ctx)

  if (is.null(name) || length(name) != 1L || !nzchar(name)) {
    .server_runtime_stop(
      "serverRuntimeAttachModule: Geçerli bir modül adı bekleniyor."
    )
  }

  if (length(required_functions) > 0L) {
    .server_runtime_require_functions(
      value,
      required_functions,
      sprintf("runtime module '%s'", name)
    )
  }

  ctx$modules[[name]] <- value

  invisible(ctx)
}

serverRuntimeGetModule <- function(ctx,
                                   name,
                                   required_functions = character(0)) {
  .server_runtime_require_context(ctx)

  if (is.null(name) || length(name) != 1L || !nzchar(as.character(name))) {
    .server_runtime_stop(
      "serverRuntimeGetModule: Geçerli bir modül adı bekleniyor."
    )
  }

  name <- as.character(name)
  module_value <- ctx$modules[[name]]

  if (is.null(module_value)) {
    .server_runtime_stop(sprintf(
      "serverRuntimeGetModule: '%s' modülü runtime context içinde kayıtlı değil.",
      name
    ))
  }

  if (length(required_functions) > 0L) {
    .server_runtime_require_functions(
      module_value,
      required_functions,
      sprintf("runtime module '%s'", name)
    )
  }

  module_value
}

serverRuntimeExposeSessionData <- function(ctx,
                                           key,
                                           value,
                                           overwrite = TRUE) {
  .server_runtime_require_context(ctx)

  if (is.null(key) || length(key) != 1L || !nzchar(as.character(key))) {
    .server_runtime_stop(
      "serverRuntimeExposeSessionData: Geçerli bir oturum anahtarı bekleniyor."
    )
  }

  if (is.null(ctx$session) || is.null(ctx$session$userData)) {
    .server_runtime_stop(
      "serverRuntimeExposeSessionData: session$userData bulunamadı."
    )
  }

  key <- as.character(key)
  already_exists <- exists(key, envir = ctx$session$userData, inherits = FALSE)

  if (isTRUE(already_exists) && !isTRUE(overwrite)) {
    .server_runtime_stop(sprintf(
      "serverRuntimeExposeSessionData: '%s' oturum verisi zaten mevcut.",
      key
    ))
  }

  ctx$session$userData[[key]] <- value

  invisible(ctx)
}
