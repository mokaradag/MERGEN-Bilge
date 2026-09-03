# ==============================================================================
# Dosya Yolu: R/helpers_file_manager_delete_runtime.R
# Açıklama: Dosya Yönetimi silme akışında fiziksel dosya ve indeks temizliği.
# ==============================================================================

fm_delete_persisted_file_artifacts <- function(
  info,
  uid,
  get_user_upload_dir,
  fm_debug = function(...) invisible(NULL),
  path_exists_fn = path_exists_relaxed,
  unlink_fn = unlink,
  resolve_fn = resolve_uploaded_file,
  remove_index_fn = mergen_remove_from_index
) {
  file_name <- as.character(if (is.null(info$name)) "" else info$name)
  deleted_physical <- FALSE
  deleted_path <- NA_character_

  try_delete_path <- function(candidate, source_label) {
    if (is.null(candidate) || !nzchar(candidate) || !isTRUE(path_exists_fn(candidate))) {
      return(FALSE)
    }

    try(unlink_fn(candidate, force = TRUE), silent = TRUE)
    deleted_physical <<- TRUE
    deleted_path <<- candidate
    fm_debug("delete_physical", sprintf("%s ile silindi: %s", source_label, candidate))
    TRUE
  }

  direct_candidates <- c(info$persisted_path, info$datapath, info$path)
  for (candidate in direct_candidates) {
    if (try_delete_path(candidate, "doğrudan")) break
  }

  if (!deleted_physical && nzchar(file_name)) {
    persisted <- tryCatch(
      resolve_fn(file_name, user_id = uid),
      error = function(e) NULL
    )

    try_delete_path(persisted, "resolve")
  }

  if (!deleted_physical && !is.null(uid) && nzchar(file_name)) {
    fallback_path <- file.path(get_user_upload_dir(), basename(file_name))
    try_delete_path(fallback_path, "fallback")
  }

  if (!is.null(uid) && nzchar(file_name)) {
    try(remove_index_fn(uid, file_name), silent = TRUE)
  }

  invisible(list(
    deleted_physical = deleted_physical,
    deleted_path = deleted_path,
    file_name = file_name,
    uid = uid
  ))
}
