# ==============================================================================
# Dosya Yolu: R/server_runtime_auth_ready.R
# Açıklama: ServerRuntimeContext'in SSO sonrası (post-auth) işleri + yenilenebilir
#           modül wiring katmanı. `serverRuntimeOnSsoAuthReady`,
#           `serverRuntimeRefreshModuleOnSsoAuthReady` ve
#           `serverRuntimeAttachRefreshableModule` bu odaklı dosyaya alındı;
#           davranış BİREBİR korunur (yalnızca konum değişti). Bu katman
#           `server_runtime_context.R` içindeki modül kayıt yardımcılarını
#           (`serverRuntimeAttachModule`, `serverRuntimeGetModule`,
#           `serverRuntimeExposeSessionData`) ve düşük seviyeli sözleşme
#           yardımcılarını (`helpers_server_runtime_contracts.R`) ÇAĞRI ANINDA
#           kullanır; bu nedenle manifestte `server_runtime_context.R`'den SONRA
#           yüklenir.
#
#           Davranış sözleşmesi: SSO modunda zaten kimlik-hazır olan oturumda
#           callback HEMEN çalışır; aksi halde gözlemci (ignoreInit/once) kurulur.
#           İki yol da `.server_runtime_invoke_auth_ready_callback()` üzerinden
#           geçer. Yerel modda bu yardımcı no-op'tur (mevcut başlangıç akışı
#           değişmez).
# ==============================================================================

# İzole test/hata ayıklama bağlamı için WD-bağımsız yedek yükleme: bu dosya
# tek başına source edildiğinde modül kayıt + sözleşme yardımcılarına ihtiyaç
# duyar. server_runtime_context.R kendi bootstrap'ıyla sözleşme yardımcılarını
# da yükler, bu yüzden yalnızca onun varlığını kontrol etmek yeterlidir.
if (!exists("serverRuntimeAttachModule", mode = "function", inherits = TRUE)) {
  .server_runtime_auth_roots <- unique(c(
    getwd(), dirname(getwd()), dirname(dirname(getwd())),
    Sys.getenv("MERGEN_REPO_ROOT", unset = NA_character_),
    if (exists("repo_root_for_tests", inherits = TRUE)) {
      as.character(repo_root_for_tests)[1]
    } else {
      NA_character_
    }
  ))
  .server_runtime_auth_roots <- .server_runtime_auth_roots[
    !is.na(.server_runtime_auth_roots) & nzchar(.server_runtime_auth_roots)
  ]
  .server_runtime_auth_ctx_paths <- file.path(
    .server_runtime_auth_roots, "R", "server_runtime_context.R"
  )
  .server_runtime_auth_ctx_paths <- .server_runtime_auth_ctx_paths[
    file.exists(.server_runtime_auth_ctx_paths)
  ]
  if (length(.server_runtime_auth_ctx_paths) > 0L) {
    source(.server_runtime_auth_ctx_paths[1], encoding = "UTF-8", local = globalenv())
  }
  rm(list = intersect(c(
    ".server_runtime_auth_roots", ".server_runtime_auth_ctx_paths"
  ), ls()))
}

serverRuntimeOnSsoAuthReady <- function(ctx,
                                        callback,
                                        label = "auth_ready",
                                        once = TRUE,
                                        ignore_init = TRUE,
                                        run_if_ready = TRUE,
                                        observe_event_fn = shiny::observeEvent,
                                        req_fn = shiny::req) {
  .server_runtime_require_context(ctx)

  if (is.null(label) || length(label) != 1L || !nzchar(as.character(label))) {
    label <- "auth_ready"
  }
  label <- as.character(label)

  if (!is.function(callback)) {
    .server_runtime_stop(sprintf(
      "serverRuntimeOnSsoAuthReady[%s]: callback fonksiyon olmalıdır.",
      label
    ))
  }

  .server_runtime_require_functions(
    ctx$identity,
    c("is_sso_active", "is_auth_ready"),
    "runtime identity"
  )

  # Yerel modda mevcut başlangıç akışını değiştirme; bu yardımcı yalnızca SSO sonrası işler içindir.
  if (!isTRUE(ctx$identity$is_sso_active())) {
    return(invisible(FALSE))
  }

  if (is.null(ctx$sso_state)) {
    .server_runtime_stop(sprintf(
      "serverRuntimeOnSsoAuthReady[%s]: SSO modunda sso_state gereklidir.",
      label
    ))
  }

  authenticated_now <- try(
    shiny::isolate(isTRUE(ctx$sso_state$authenticated)),
    silent = TRUE
  )

  if (inherits(authenticated_now, "try-error")) {
    authenticated_now <- FALSE
  }

  if (isTRUE(run_if_ready) &&
      isTRUE(authenticated_now) &&
      isTRUE(ctx$identity$is_auth_ready())) {
    .server_runtime_invoke_auth_ready_callback(ctx, callback, label)

    return(invisible(TRUE))
  }

  observer <- observe_event_fn(ctx$sso_state$authenticated, {
    req_fn(
      isTRUE(ctx$sso_state$authenticated),
      isTRUE(ctx$identity$is_auth_ready())
    )

    .server_runtime_invoke_auth_ready_callback(ctx, callback, label)
  }, ignoreInit = ignore_init, once = once)

  invisible(observer)
}

serverRuntimeRefreshModuleOnSsoAuthReady <- function(ctx,
                                                     module_name,
                                                     refresh_function,
                                                     refresh_args = list(),
                                                     label = NULL,
                                                     once = TRUE,
                                                     ignore_init = TRUE,
                                                     observe_event_fn = shiny::observeEvent,
                                                     req_fn = shiny::req) {
  .server_runtime_require_context(ctx)

  if (is.null(module_name) ||
      length(module_name) != 1L ||
      !nzchar(as.character(module_name))) {
    .server_runtime_stop(
      "serverRuntimeRefreshModuleOnSsoAuthReady: Geçerli bir modül adı bekleniyor."
    )
  }

  if (is.null(refresh_function) ||
      length(refresh_function) != 1L ||
      !nzchar(as.character(refresh_function))) {
    .server_runtime_stop(
      "serverRuntimeRefreshModuleOnSsoAuthReady: Geçerli bir yenileme fonksiyonu adı bekleniyor."
    )
  }

  if (!is.list(refresh_args)) {
    .server_runtime_stop(
      "serverRuntimeRefreshModuleOnSsoAuthReady: refresh_args liste olmalıdır."
    )
  }

  module_name <- as.character(module_name)
  refresh_function <- as.character(refresh_function)

  if (is.null(label) || length(label) != 1L || !nzchar(as.character(label))) {
    label <- paste0(module_name, "_", refresh_function, "_auth_ready")
  }

  # SSO modunda eksik modül/fonksiyon sözleşmesini observer çalışmadan önce yakala.
  if (isTRUE(ctx$identity$is_sso_active())) {
    serverRuntimeGetModule(
      ctx,
      module_name,
      required_functions = refresh_function
    )
  }

  serverRuntimeOnSsoAuthReady(
    ctx = ctx,
    label = label,
    once = once,
    ignore_init = ignore_init,
    observe_event_fn = observe_event_fn,
    req_fn = req_fn,
    callback = function(ctx) {
      module_value <- serverRuntimeGetModule(
        ctx,
        module_name,
        required_functions = refresh_function
      )

      do.call(module_value[[refresh_function]], refresh_args)
    }
  )
}

serverRuntimeAttachRefreshableModule <- function(ctx,
                                                 name,
                                                 value,
                                                 required_functions = character(0),
                                                 refresh_function = NULL,
                                                 refresh_args = list(),
                                                 label = NULL,
                                                 expose_session_key = NULL,
                                                 overwrite_session_key = TRUE,
                                                 once = TRUE,
                                                 ignore_init = TRUE,
                                                 observe_event_fn = shiny::observeEvent,
                                                 req_fn = shiny::req) {
  .server_runtime_require_context(ctx)

  if (!is.list(refresh_args)) {
    .server_runtime_stop(
      "serverRuntimeAttachRefreshableModule: refresh_args liste olmalıdır."
    )
  }

  ctx <- serverRuntimeAttachModule(
    ctx = ctx,
    name = name,
    value = value,
    required_functions = required_functions
  )

  if (!is.null(expose_session_key)) {
    ctx <- serverRuntimeExposeSessionData(
      ctx = ctx,
      key = expose_session_key,
      value = value,
      overwrite = overwrite_session_key
    )
  }

  if (!is.null(refresh_function)) {
    serverRuntimeRefreshModuleOnSsoAuthReady(
      ctx = ctx,
      module_name = name,
      refresh_function = refresh_function,
      refresh_args = refresh_args,
      label = label,
      once = once,
      ignore_init = ignore_init,
      observe_event_fn = observe_event_fn,
      req_fn = req_fn
    )
  }

  invisible(ctx)
}
