# Kopya sahipliği yol adından bağımsız, kilit altında doğrulanır.
file_ingestion_owner_path <- function(path) {
  file.path(dirname(path), paste0(".", basename(path), ".ingest-owner"))
}

file_ingestion_artifact_owned <- function(result) {
  id <- result$artifact_id
  if (is.null(id) || !nzchar(id)) return(FALSE)
  marker <- file_ingestion_owner_path(result$dest)
  owner <- suppressWarnings(tryCatch(readRDS(marker), error = function(e) NULL))
  isTRUE(file.exists(result$dest)) && identical(owner$id, id) &&
    identical(file.info(result$dest)[c("size", "mtime", "ctime")], owner$identity)
}

file_ingestion_claim_artifact <- function(path, expected = file.info(path)[c("size", "mtime", "ctime")]) {
  id <- paste0(Sys.getpid(), "-", basename(tempfile("ingest_")))
  .file_store_with_index_lock({
    if (!isTRUE(file.exists(path)) ||
        !identical(file.info(path)[c("size", "mtime", "ctime")], expected) ||
        file.exists(file_ingestion_owner_path(path))) {
      stop("Kopyalanan dosyanın sahipliği doğrulanamadı.")
    }
    saveRDS(list(id = id, identity = expected), file_ingestion_owner_path(path))
  }, require_lock = TRUE)
  id
}
