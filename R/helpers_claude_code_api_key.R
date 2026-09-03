# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_api_key.R
# Açıklama:   Bilge Yolaç / Claude Code süreçlerine doğru API anahtarını
#             güvenli şekilde aktarır. Anahtar dosyaya yazılmaz; yalnızca
#             processx ortam değişkeni olarak verilir.
# ==============================================================================

cc_resolve_runtime_api_key <- function(session) {
  plan <- tryCatch(
    mb_api_key_get_effective_key(
      session = session,
      require_auth = TRUE,
      allow_default = NULL,
      clear_on_mismatch = TRUE
    ),
    error = function(e) list(key = "", source = "missing", owner = NULL)
  )

  key_value <- as.character(plan$key %||% "")[1]
  if (is.na(key_value) || !nzchar(key_value)) {
    return(list(
      ok = FALSE,
      key = "",
      source = "missing",
      message = "Bilge Yolaç için API anahtarı bulunamadı. Lütfen kişisel API anahtarınızı girin veya varsayılan kurum anahtarının yapılandırıldığını kontrol edin."
    ))
  }

  list(
    ok = TRUE,
    key = key_value,
    source = plan$source %||% "unknown",
    owner = plan$owner %||% NULL,
    message = ""
  )
}

cc_apply_runtime_api_key_env <- function(env = NULL, api_key) {
  api_key <- as.character(api_key %||% "")[1]
  if (is.na(api_key) || !nzchar(api_key)) {
    return(env)
  }

  if (is.null(env)) {
    env <- Sys.getenv()
  }

  env[["ANTHROPIC_AUTH_TOKEN"]] <- api_key
  env
}