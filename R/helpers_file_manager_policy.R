# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_policy.R
# Açıklama: Dosya Yönetimi modülü için saf seçim ve yükleme politika yardımcıları.
# ==============================================================================

fm_upload_limit_mb <- function(default = 25L) {
  default <- suppressWarnings(as.integer(default[1]))
  if (is.na(default) || default <= 0L) {
    default <- 25L
  }

  limit <- suppressWarnings(as.integer(getOption("mergen.upload_max_mb", default)))
  if (is.na(limit) || limit <= 0L) {
    return(default)
  }

  limit
}

fm_upload_limit_bytes <- function(upload_limit_mb = fm_upload_limit_mb()) {
  upload_limit_mb <- suppressWarnings(as.integer(upload_limit_mb[1]))
  if (is.na(upload_limit_mb) || upload_limit_mb <= 0L) {
    upload_limit_mb <- fm_upload_limit_mb()
  }

  as.numeric(upload_limit_mb) * 1024^2
}

fm_summarization_allowed_extensions <- function() {
  c("doc", "docx", "pdf", "txt")
}

fm_normal_allowed_extensions <- function() {
  c(
    "txt", "pdf", "docx", "xlsx", "xls", "csv", "json",
    "r", "py", "md", "log", "xml", "html"
  )
}

fm_resolve_allowed_extensions <- function(generate_message,
                                          summarization_mode) {
  if (!isTRUE(generate_message)) {
    return(fm_normal_allowed_extensions())
  }

  if (isTRUE(summarization_mode)) {
    return(fm_summarization_allowed_extensions())
  }

  fm_normal_allowed_extensions()
}

fm_attach_rule_hint_text <- function(mcp_enabled = FALSE,
                                     summarization_mode = FALSE,
                                     allow_summarization_text = FALSE) {
  if (isTRUE(mcp_enabled)) {
    return("Seçim kuralı: MCP açıkken yalnızca 1 dosya eklenebilir.")
  }

  if (isTRUE(allow_summarization_text) && isTRUE(summarization_mode)) {
    return("Seçim kuralı: Dosya Özetleme modunda birden fazla dosya seçebilirsiniz.")
  }

  "Seçim kuralı: MCP kapalıyken birden fazla dosya seçebilirsiniz."
}
