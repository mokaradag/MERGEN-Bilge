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

# Anahtar dosya sürümünü tam hassasiyetle taşır: aynı saniyede aynı boyutla
# yeniden yazılan dosya eski baytları getirmez. Üstveri okunamazsa sürüm
# kanıtlanamaz; anahtar tekildir ve önbellek kullanılmaz.
mergen_preview_cache_key <- function(path) {
  dp <- if (exists("resolve_readable_path", mode = "function")) {
    resolve_readable_path(path)
  } else {
    path
  }

  finfo <- tryCatch(file.info(dp), error = function(e) NULL)
  if (is.null(finfo) || is.na(finfo$size[1]) || is.na(finfo$mtime[1])) {
    return(paste(dp, "nometa", basename(tempfile("k")), sep = "||"))
  }

  paste(dp, as.character(finfo$size[1]), format(as.numeric(finfo$mtime[1]), digits = 17),
        sep = "||")
}
