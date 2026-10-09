# Kopya kimliği yolun gösteriminden bağımsızdır.
file_ingestion_owner_path <- function(path) {
  file.path(dirname(path), paste0(".", basename(path), ".ingest-owner"))
}

file_ingestion_file_identity <- function(path) {
  if (is.null(path)) return(NULL)
  info <- if (is.data.frame(path)) path else file.info(path)[c("size", "mtime", "ctime")]
  rownames(info) <- NULL
  info
}

file_ingestion_artifact_owned <- function(result) {
  id <- result$artifact_id
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(FALSE)
  owner <- suppressWarnings(tryCatch(file_ingestion_read_owner(result$dest), error = function(e) NULL))
  if (!is.list(owner) || !identical(owner$id, id)) return(FALSE)
  if (identical(owner$state, "copying")) return(isTRUE(result$transaction_pending) &&
    identical(owner$staging, result$staging))
  isTRUE(file.exists(result$dest)) &&
    identical(file_ingestion_file_identity(result$dest), file_ingestion_file_identity(owner$identity))
}

file_ingestion_read_owner <- function(path) {
  marker <- file_ingestion_owner_path(path)
  owner <- if (file.exists(marker)) readRDS(marker) else NULL
  if (!is.list(owner) || !identical(owner$state, "copying")) return(owner)
  verified <- suppressWarnings(tryCatch(readRDS(paste0(marker, ".identity")), error = function(e) NULL))
  if (is.list(verified) && identical(verified$id, owner$id)) {
    owner$identity <- verified$identity
    owner$state <- "claimed"
  }
  owner
}

file_ingestion_begin_copy <- function(path, staging, source, transaction) {
  result <- list(ok = FALSE, dest = path, source_path = source,
    artifact_id = transaction$id, staging = staging, transaction_pending = TRUE)
  saveRDS(result, transaction$journal)
  .file_store_with_index_lock({
    if (file.exists(path) || file.exists(staging)) stop("Kopya hedefi zaten var.")
    unlink(paste0(file_ingestion_owner_path(path), ".identity"), force = TRUE)
    saveRDS(list(id = transaction$id, state = "copying", staging = staging),
            file_ingestion_owner_path(path))
  }, require_lock = TRUE)
  invisible(NULL)
}

file_ingestion_claim_artifact <- function(path, expected = file_ingestion_file_identity(path), id = NULL) {
  supplied_id <- id
  id <- id %||% paste0(Sys.getpid(), "-", basename(tempfile("ingest_")))
  .file_store_with_index_lock({
    actual <- file_ingestion_file_identity(path)
    marker <- file_ingestion_owner_path(path)
    owner <- file_ingestion_read_owner(path)
    if ((!is.null(supplied_id) && (!is.list(owner) || !identical(owner$id, supplied_id))) ||
        !isTRUE(file.exists(path)) || !identical(actual, file_ingestion_file_identity(expected)) ||
        (is.list(owner) && !identical(owner$id, supplied_id) &&
          (identical(owner$state, "copying") || identical(actual, file_ingestion_file_identity(owner$identity))))) {
      stop("Kopyalanan dosyanın sahipliği doğrulanamadı.")
    }
    if (is.null(supplied_id)) saveRDS(list(id = id, identity = actual), marker) else
      saveRDS(list(id = id, identity = actual), paste0(marker, ".identity"))
  }, require_lock = TRUE)
  id
}

file_ingestion_discard_unclaimed <- function(path, source, expected) {
  .file_store_with_index_lock({
    marker <- file_ingestion_owner_path(path)
    owner <- file_ingestion_read_owner(path)
    if (!identical(owner$state, "copying") &&
        identical(file_ingestion_file_identity(path), file_ingestion_file_identity(expected)) &&
        (is.null(owner) || !identical(file_ingestion_file_identity(owner$identity), file_ingestion_file_identity(expected)))) {
      file_ingestion_discard_dest(path, source)
      if (!file.exists(path)) unlink(marker, force = TRUE)
    }
  }, require_lock = TRUE)
  invisible(NULL)
}
