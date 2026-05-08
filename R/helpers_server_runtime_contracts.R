# ==============================================================================
# Dosya Yolu: R/helpers_server_runtime_contracts.R
# Açıklama: Server runtime context için düşük seviyeli sözleşme ve hata
#           yardımcıları. Bu dosya server_runtime_context.R dosyasının yalnızca
#           runtime bağlam orkestrasyonuna odaklanabilmesi için önce source edilir.
# ==============================================================================

is_server_runtime_context <- function(ctx) {
  is.environment(ctx) && inherits(ctx, "mergen_server_runtime_context")
}

.server_runtime_stop <- function(message) {
  stop(message, call. = FALSE)
}

.server_runtime_require_context <- function(ctx) {
  if (!is_server_runtime_context(ctx)) {
    .server_runtime_stop(
      "server_runtime_context: Geçerli bir mergen_server_runtime_context bekleniyor."
    )
  }

  invisible(TRUE)
}

.server_runtime_require_values <- function(x, names, owner) {
  missing <- names[vapply(
    names,
    function(nm) is.null(x[[nm]]),
    logical(1)
  )]

  if (length(missing) > 0L) {
    .server_runtime_stop(sprintf(
      "%s eksik zorunlu alan(lar): %s",
      owner,
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

.server_runtime_require_functions <- function(x, names, owner) {
  missing <- names[!vapply(
    names,
    function(nm) is.function(x[[nm]]),
    logical(1)
  )]

  if (length(missing) > 0L) {
    .server_runtime_stop(sprintf(
      "%s eksik zorunlu fonksiyon(lar): %s",
      owner,
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

.server_runtime_invoke_auth_ready_callback <- function(ctx, callback, label) {
  tryCatch(
    callback(ctx),
    error = function(e) {
      .server_runtime_stop(sprintf(
        "serverRuntimeOnSsoAuthReady[%s]: callback başarısız: %s",
        label,
        conditionMessage(e)
      ))
    }
  )
}