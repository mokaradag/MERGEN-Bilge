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

# Desteklenen görsel uzantıları. Görseller yüklenip Dosya Yönetimi tablosunda
# listelenebilir; ancak bu sürümde içerikleri yapay zekâ tarafından analiz
# edilmez (görsel/vision pipeline'ı henüz yoktur). Tek kaynak burada tutulur.
fm_image_extensions <- function() {
  c("jpg", "jpeg", "png", "gif", "webp", "bmp", "svg")
}

fm_normal_allowed_extensions <- function() {
  c(
    "txt", "pdf", "docx", "xlsx", "xls", "csv", "json",
    "r", "py", "md", "log", "xml", "html",
    fm_image_extensions()
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

fm_normalize_user_id <- function(user_id, invalid = "unknown") {
  invalid_chr <- if (is.null(invalid) || length(invalid) == 0L || is.na(invalid[1])) {
    "unknown"
  } else {
    trimws(as.character(invalid[1]))
  }

  if (!nzchar(invalid_chr)) {
    invalid_chr <- "unknown"
  }

  if (is.null(user_id) || length(user_id) == 0L || is.na(user_id[1])) {
    return(invalid_chr)
  }

  uid <- trimws(as.character(user_id[1]))
  if (!nzchar(uid)) {
    return(invalid_chr)
  }

  uid_lower <- tolower(uid)
  if (uid_lower %in% c("0", "unknown", "null", "na", "nan")) {
    return(invalid_chr)
  }

  uid
}

fm_valid_user_id <- function(user_id) {
  !identical(fm_normalize_user_id(user_id), "unknown")
}

fm_file_ext_icon_html <- function(ext) {
  e <- if (is.null(ext) || length(ext) == 0L || is.na(ext[1])) {
    ""
  } else {
    tolower(as.character(ext[1]))
  }

  ico <- switch(
    e,
    "pdf"  = "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>",
    "doc"  = "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>",
    "docx" = "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>",
    "xls"  = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
    "xlsx" = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
    "csv"  = "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#217346'></i>",
    "json" = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
    "xml"  = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
    "html" = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
    "r"    = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
    "py"   = "<i class='fa-regular fa-file-code' style='margin-right:6px;'></i>",
    "md"   = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
    "log"  = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
    "txt"  = "<i class='fa-regular fa-file-lines' style='margin-right:6px;'></i>",
    "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
  )

  paste0(ico, toupper(e))
}

fm_format_file_timestamp <- function(path = NULL, fallback_time = Sys.time()) {
  ts <- fallback_time

  path_chr <- if (is.null(path) || length(path) == 0L || is.na(path[1])) {
    ""
  } else {
    as.character(path[1])
  }

  if (nzchar(path_chr) && file.exists(path_chr)) {
    info <- tryCatch(file.info(path_chr), error = function(e) NULL)
    if (!is.null(info) && !is.na(info$mtime[1])) {
      ts <- info$mtime[1]
    }
  }

  format(ts, "%Y-%m-%d %H:%M")
}