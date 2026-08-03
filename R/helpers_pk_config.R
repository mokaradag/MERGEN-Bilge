# ==============================================================================
# Dosya Yolu: R/helpers_pk_config.R
# Açıklama: Proje ve Kaynak Analizi yapılandırma çözümleyicisi.
# Öncelik: sorgu metadata -> ortam değişkeni -> options() -> varsayılan.
# ==============================================================================

pk_config_spec <- list(
  MERGEN_PK_ENGINE = list(
    type = "character",
    default = "v1",
    allowed = c("v1", "v2")
  ),
  MERGEN_PK_TELEMETRY = list(
    type = "logical",
    default = TRUE
  ),
  MERGEN_PK_LOG_QUESTION_TEXT = list(
    type = "logical",
    default = FALSE
  ),
  MERGEN_PK_TELEMETRY_HMAC_KEY = list(
    type = "character",
    default = "",
    secret = TRUE
  ),
  MERGEN_PK_TELEMETRY_HMAC_KEY_ID = list(
    type = "character",
    default = "k1"
  ),
  MERGEN_PK_ROW_CAP = list(
    type = "integer",
    default = 50000L,
    min = 1L
  )
)

pk_config_meta_key <- function(key) {
  tolower(sub("^MERGEN_PK_", "", as.character(key)[1]))
}

pk_config_option_key <- function(key) {
  paste0("mergen.pk.", pk_config_meta_key(key))
}

.pk_config_as_logical <- function(value) {
  if (is.logical(value) && length(value) == 1L && !is.na(value)) return(value)
  if (length(value) != 1L) return(NULL)

  txt <- tolower(trimws(as.character(value)[1]))
  if (is.na(txt) || !nzchar(txt)) return(NULL)

  if (txt %in% c("true", "t", "1", "yes", "y", "on", "evet", "acik", "açık")) return(TRUE)
  if (txt %in% c("false", "f", "0", "no", "n", "off", "hayir", "hayır", "kapali", "kapalı")) return(FALSE)

  NULL
}

# Tam sayılar yuvarlanmaz. Kesirli, taşan veya birden çok değer geçersizdir.
.pk_config_as_integer <- function(value, spec) {
  if (length(value) != 1L) return(NULL)

  num <- suppressWarnings(as.numeric(as.character(value)[1]))
  if (length(num) != 1L || is.na(num) || !is.finite(num)) return(NULL)
  if (!identical(num, trunc(num))) return(NULL)
  if (num < -.Machine$integer.max || num > .Machine$integer.max) return(NULL)

  out <- as.integer(num)
  if (is.na(out)) return(NULL)
  if (!is.null(spec$min) && out < spec$min) return(NULL)
  if (!is.null(spec$max) && out > spec$max) return(NULL)

  out
}

.pk_config_as_character <- function(value, spec) {
  if (length(value) != 1L) return(NULL)

  txt <- as.character(value)[1]
  if (is.na(txt)) return(NULL)

  txt <- trimws(txt)
  if (!nzchar(txt) && nzchar(spec$default %||% "")) return(NULL)
  if (!is.null(spec$allowed) && !(txt %in% spec$allowed)) return(NULL)

  txt
}

.pk_config_coerce <- function(value, spec) {
  if (is.null(value) || length(value) == 0L) return(NULL)

  switch(
    spec$type %||% "character",
    logical   = .pk_config_as_logical(value),
    integer   = .pk_config_as_integer(value, spec),
    character = .pk_config_as_character(value, spec),
    NULL
  )
}

pk_config_resolve <- function(key, query_meta = NULL) {
  key <- as.character(key)[1]
  spec <- pk_config_spec[[key]]

  if (is.null(spec)) {
    stop(sprintf("pk_config_resolve: tanimsiz yapilandirma anahtari '%s'.", key), call. = FALSE)
  }

  if (is.list(query_meta)) {
    candidate <- .pk_config_coerce(query_meta[[pk_config_meta_key(key)]], spec)
    if (!is.null(candidate)) return(candidate)
  }

  env_raw <- Sys.getenv(key, unset = NA_character_)
  if (!is.na(env_raw)) {
    candidate <- .pk_config_coerce(env_raw, spec)
    if (!is.null(candidate)) return(candidate)
  }

  candidate <- .pk_config_coerce(getOption(pk_config_option_key(key), default = NULL), spec)
  if (!is.null(candidate)) return(candidate)

  spec$default
}

pk_config_safe_snapshot <- function() {
  out <- list()

  for (key in names(pk_config_spec)) {
    spec <- pk_config_spec[[key]]
    value <- tryCatch(pk_config_resolve(key), error = function(e) NULL)

    if (isTRUE(spec$secret)) {
      out[[key]] <- list(
        present = !is.null(value) && nzchar(as.character(value)[1]),
        nchar = if (is.null(value)) 0L else nchar(as.character(value)[1]),
        value = "<hidden>"
      )
    } else {
      out[[key]] <- value
    }
  }

  out
}
