mergen_preview_cache_put <- function(cache, id, value, max_entries = 3L, max_bytes = 16 * 1024^2) {
  cache[[id]] <- NULL
  bytes <- function(item) nchar(if (is.list(item)) item$base64 %||% "" else item %||% "", type = "bytes")
  value_bytes <- bytes(value)
  if (length(value_bytes) == 1L && !is.na(value_bytes) && value_bytes <= max_bytes) cache[[id]] <- value
  while (length(cache) > max_entries ||
         sum(vapply(cache, bytes, numeric(1))) > max_bytes) {
    cache <- cache[-1L]
  }
  cache
}

mergen_preview_cache_key <- function(path) {
  dp <- if (exists("resolve_readable_path", mode = "function")) {
    resolve_readable_path(path)
  } else {
    path
  }

  finfo <- tryCatch(file.info(dp), error = function(e) NULL)

  size_txt <- if (!is.null(finfo) && !is.na(finfo$size[1])) {
    as.character(finfo$size[1])
  } else {
    "nosize"
  }

  mtime_txt <- if (!is.null(finfo) && !is.na(finfo$mtime[1])) {
    format(finfo$mtime[1], "%Y%m%d%H%M%S")
  } else {
    "nomtime"
  }

  paste(dp, size_txt, mtime_txt, sep = "||")
}
