# ==============================================================================
# Dosya Yolu: R/helpers_server_runtime_named_contracts.R
# Açıklama: Server runtime için adlandırılmış fonksiyon ve ortam sözleşmesi
#           yardımcıları. Ana runtime sözleşme dosyasının fonksiyon bütçesini
#           aşmaması için ayrı tutulur.
# ==============================================================================

.server_runtime_require_named_functions <- function(named_functions, owner) {
  if (!is.list(named_functions)) {
    .server_runtime_stop(sprintf(
      "%s fonksiyon sözleşmesi liste olmalıdır.",
      owner
    ))
  }

  function_names <- names(named_functions)

  if (is.null(function_names) || any(!nzchar(function_names))) {
    .server_runtime_stop(sprintf(
      "%s fonksiyon sözleşmesindeki tüm alanlar adlandırılmalıdır.",
      owner
    ))
  }

  missing <- function_names[!vapply(
    named_functions,
    is.function,
    logical(1)
  )]

  if (length(missing) > 0L) {
    .server_runtime_stop(sprintf(
      "%s eksik/geçersiz fonksiyon(lar): %s",
      owner,
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

.server_runtime_require_environment <- function(x, owner) {
  if (!is.environment(x)) {
    .server_runtime_stop(sprintf(
      "%s ortam olmalıdır.",
      owner
    ))
  }

  invisible(TRUE)
}