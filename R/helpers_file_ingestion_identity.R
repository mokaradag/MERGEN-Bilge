# Kopya kimliği yolun gösteriminden bağımsızdır.
file_ingestion_owner_path <- function(path) {
  file.path(dirname(path), paste0(".", basename(path), ".ingest-owner"))
}

file_ingestion_file_identity <- function(path) {
  if (is.null(path) || (!is.data.frame(path) &&
      (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)))) return(NULL)
  info <- if (is.data.frame(path)) path else {
    resolved <- if (exists("resolve_readable_path", mode = "function")) resolve_readable_path(path) else path
    file.info(resolved)[c("size", "mtime", "ctime")]
  }
  rownames(info) <- NULL
  if (!is.data.frame(path)) attr(info, "file_key") <- file_ingestion_physical_identity(resolved)
  info
}

file_ingestion_identity_matches <- function(actual, expected) {
  if (!is.data.frame(actual) || !is.data.frame(expected) || anyNA(actual) || anyNA(expected)) return(FALSE)
  key <- attr(expected, "file_key")
  actual_key <- attr(actual, "file_key")
  attr(actual, "file_key") <- attr(expected, "file_key") <- NULL
  identical(actual, expected) && (is.null(key) || identical(actual_key, key))
}

file_ingestion_artifact_owned <- function(result, allow_deleting = TRUE) {
  id <- result$artifact_id
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(FALSE)
  owner <- suppressWarnings(tryCatch(file_ingestion_read_owner(result$dest), error = function(e) NULL))
  if (!is.list(owner) || !identical(owner$id, id)) return(FALSE)
  if (identical(owner$state, "copying") ||
      (identical(owner$state, "deleting") && !allow_deleting)) return(FALSE)
  isTRUE(path_exists_relaxed(result$dest)) &&
    file_ingestion_identity_matches(file_ingestion_file_identity(result$dest), file_ingestion_file_identity(owner$identity))
}

file_ingestion_read_owner <- function(path) {
  marker <- file_ingestion_owner_path(path)
  owner <- if (path_exists_relaxed(marker)) readRDS(marker) else NULL
  if (!is.list(owner) || !identical(owner$state, "copying")) return(owner)
  verified <- suppressWarnings(tryCatch(readRDS(paste0(marker, ".identity")), error = function(e) NULL))
  if (is.list(verified) && identical(verified$id, owner$id)) {
    if (identical(verified$state, "promoting")) {
      key <- file_ingestion_physical_identity(path)
      if (is.null(key) || !identical(key, verified$file_key)) return(owner)
      owner$identity <- file_ingestion_file_identity(path)
    } else owner$identity <- verified$identity
    owner$state <- "claimed"
  }
  owner
}

file_ingestion_begin_copy <- function(path, staging, source, transaction) {
  .file_store_with_index_lock({
    owner <- file_ingestion_read_owner(path)
    if (path_exists_relaxed(file_ingestion_owner_path(path)) && !is.list(owner))
      stop("Kopya rezervasyonunun sahipliği okunamadı.")
    if (path_exists_relaxed(path) || path_exists_relaxed(staging)) stop("Kopya hedefi zaten var.")
    if (is.list(owner) && !identical(owner$id, transaction$id) &&
        !identical(mergen_pid_status(owner$pid, owner$host), FALSE))
      stop("Kopya hedefi başka bir işlem tarafından ayrılmış.")
    previous <- suppressWarnings(tryCatch(readRDS(transaction$journal), error = function(e) NULL))
    result <- list(ok = FALSE, dest = path, source_path = source,
      artifact_id = transaction$id, staging = staging, transaction_pending = TRUE)
    saveRDS(result, transaction$journal)
    unlink(paste0(file_ingestion_owner_path(path), ".identity"), force = TRUE)
    saveRDS(list(id = transaction$id, state = "copying", staging = staging,
      pid = Sys.getpid(), host = unname(Sys.info()[["nodename"]])), file_ingestion_owner_path(path))
    if (is.list(previous) && !identical(previous$dest, path)) {
      old_owner <- file_ingestion_read_owner(previous$dest)
      if (identical(old_owner$id, transaction$id) && identical(old_owner$state, "copying") &&
          !path_exists_relaxed(previous$staging)) unlink(file_ingestion_owner_path(previous$dest), force = TRUE)
    }
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
    if (is.null(attr(actual, "file_key")) ||
        (!is.null(supplied_id) && (!is.list(owner) || !identical(owner$id, supplied_id) ||
          !identical(owner$state, "claimed") ||
          !file_ingestion_identity_matches(actual, file_ingestion_file_identity(owner$identity)))) ||
        !isTRUE(path_exists_relaxed(path)) || !file_ingestion_identity_matches(actual, file_ingestion_file_identity(expected)) ||
        (is.list(owner) && !identical(owner$id, supplied_id) &&
          (identical(owner$state, "copying") || file_ingestion_identity_matches(actual, file_ingestion_file_identity(owner$identity))))) {
      stop("Kopyalanan dosyanın sahipliği doğrulanamadı.")
    }
    if (is.null(supplied_id)) saveRDS(list(id = id, identity = actual, pid = Sys.getpid(), host = unname(Sys.info()[["nodename"]])), marker) else
      saveRDS(list(id = id, identity = actual), paste0(marker, ".identity"))
  }, require_lock = TRUE)
  id
}

file_ingestion_discard_unclaimed <- function(path, source, expected) {
  id <- paste0(Sys.getpid(), "-", basename(tempfile("discard_")))
  marker <- file_ingestion_owner_path(path)
  reserved <- .file_store_with_index_lock({
    owner <- file_ingestion_read_owner(path)
    if (!identical(owner$state, "copying") &&
        file_ingestion_identity_matches(file_ingestion_file_identity(path), file_ingestion_file_identity(expected)) &&
        (is.null(owner) || !file_ingestion_identity_matches(file_ingestion_file_identity(owner$identity), file_ingestion_file_identity(expected)))) {
      saveRDS(list(id = id, identity = expected, state = "deleting",
        pid = Sys.getpid(), host = unname(Sys.info()[["nodename"]])), marker)
      TRUE
    } else FALSE
  }, require_lock = TRUE)
  result <- list(dest = path, artifact_id = id)
  if (reserved && file_ingestion_artifact_owned(result)) {
    file_ingestion_discard_dest(path, source)
    if (!path_exists_relaxed(path) && identical(file_ingestion_read_owner(path)$id, id))
      unlink(marker, force = TRUE)
  }
  invisible(NULL)
}

file_ingestion_physical_identity <- function(path) {
  info <- tryCatch(fs::file_info(path), error = function(e) NULL)
  if (is.null(info) || NROW(info) != 1L || !is.finite(info$inode) || info$inode <= 0) return(NULL)
  lapply(info[c("device_id", "inode", "size", "modification_time")], as.character)
}

file_ingestion_prepare_promotion <- function(staging, path, transaction) {
  key <- file_ingestion_physical_identity(staging)
  if (is.null(key)) stop("Staging dosya kimliği doğrulanamadı.")
  saveRDS(list(id = transaction$id, state = "promoting", file_key = key),
    paste0(file_ingestion_owner_path(path), ".identity"))
}
