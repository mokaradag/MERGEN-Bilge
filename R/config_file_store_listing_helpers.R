# ==============================================================================
# R/config_file_store_listing_helpers.R
# Dosya deposu kullanıcı listeleme yardımcıları.
# R/config_file_store_registry.R dosyasını function-heavy yapmamak için ayrıldı.
# ==============================================================================

.file_store_drop_stale_entries <- function(uid, records_to_remove) {
  if (is.null(records_to_remove) || nrow(records_to_remove) == 0) {
    return(invisible(FALSE))
  }

  .file_store_mutate_index(function(idx_local) {
    bucket_local <- idx_local[[uid]]
    if (is.null(bucket_local)) {
      return(idx_local)
    }

    for (i in seq_len(nrow(records_to_remove))) {
      key <- records_to_remove$key[i]
      stale_path <- records_to_remove$path[i]
      current <- bucket_local[[key]]

      current_path <- if (is.list(current) && !is.null(current$path)) {
        as.character(current$path)
      } else {
        as.character(current %||% "")
      }

      same_missing_path <- identical(
        normalize_for_path_compare(current_path),
        normalize_for_path_compare(stale_path)
      )

      if (isTRUE(same_missing_path)) {
        bucket_local[[key]] <- NULL
      }
    }

    if (is.list(bucket_local) && !length(bucket_local)) {
      idx_local[[uid]] <- NULL
    } else {
      idx_local[[uid]] <- bucket_local
    }

    idx_local
  })

  invisible(TRUE)
}

.file_store_index_record_row <- function(key, val) {
  rec_path <- normalize_utf8_path(
    if (is.list(val) && !is.null(val$path)) val$path else as.character(val),
    mustWork = FALSE
  )

  rec_display <- if (is.list(val) && !is.null(val$display)) {
    as.character(val$display)
  } else {
    as.character(key)
  }

  list(
    key = key,
    path = rec_path,
    name = normalize_file_display_name(
      rec_display,
      file_info = list(path = rec_path, display = rec_display, name = rec_display)
    )
  )
}

.file_store_apply_rehydrated_paths <- function(uid, rehydrated) {
  if (!length(rehydrated)) {
    return(invisible(FALSE))
  }

  .file_store_mutate_index(function(idx_local) {
    if (!is.null(idx_local[[uid]])) {
      for (k in names(rehydrated)) {
        rec <- rehydrated[[k]]
        current <- idx_local[[uid]][[k]]

        current_path <- if (is.list(current) && !is.null(current$path)) {
          as.character(current$path)
        } else {
          as.character(current %||% "")
        }

        same_old_path <- identical(
          normalize_for_path_compare(current_path),
          normalize_for_path_compare(rec$old_path)
        )

        if (isTRUE(same_old_path)) {
          if (is.list(idx_local[[uid]][[k]])) {
            idx_local[[uid]][[k]]$path <- rec$new_path
          } else if (!is.null(idx_local[[uid]][[k]])) {
            idx_local[[uid]][[k]] <- rec$new_path
          }
        }
      }
    }

    idx_local
  })

  invisible(TRUE)
}

.file_store_list_user_files_relaxed <- function(dir_path) {
  dir_chr <- as.character(dir_path %||% "")
  if (!nzchar(dir_chr)) {
    return(character(0))
  }

  variants <- unique(Filter(nzchar, c(
    dir_chr,
    gsub("/", "\\\\", dir_chr, fixed = TRUE),
    enc2utf8(dir_chr),
    enc2native(dir_chr),
    if (grepl("^/[^/]", dir_chr)) paste0("/", dir_chr) else NULL
  )))

  for (v in variants) {
    files_base <- tryCatch(
      list.files(v, full.names = TRUE, recursive = FALSE, include.dirs = FALSE),
      error = function(e) character(0)
    )
    if (length(files_base)) {
      return(files_base)
    }

    files_fs <- tryCatch(
      as.character(fs::dir_ls(v, recurse = FALSE, type = "file")),
      error = function(e) character(0)
    )
    if (length(files_fs)) {
      return(files_fs)
    }
  }

  character(0)
}

.file_store_user_dir_paths <- function(user_id) {
  user_dir <- tryCatch(mergen_user_upload_dir(user_id), error = function(e) "")
  if (!nzchar(user_dir)) {
    return(character(0))
  }

  if (!isTRUE(tryCatch(path_exists_relaxed(user_dir), error = function(e) FALSE))) {
    return(character(0))
  }

  .file_store_list_user_files_relaxed(user_dir)
}

.file_store_merge_same_user_filesystem <- function(df, user_id, idx) {
  filesystem_paths <- .file_store_user_dir_paths(user_id)
  if (!length(filesystem_paths)) {
    return(df)
  }

  existing_norm <- vapply(df$path, normalize_for_path_compare, character(1))
  filesystem_norm <- vapply(filesystem_paths, normalize_for_path_compare, character(1))
  extra_paths <- filesystem_paths[!(filesystem_norm %in% existing_norm)]

  if (!length(extra_paths)) {
    return(df)
  }

  extra_df <- data.frame(
    key = tolower(basename(extra_paths)),
    path = vapply(extra_paths, normalize_utf8_path, character(1), mustWork = FALSE),
    name = vapply(
      extra_paths,
      function(p) mergen_resolve_display_name(p, user_id = user_id, idx = idx),
      character(1)
    ),
    stringsAsFactors = FALSE
  )

  rbind(df, extra_df[, c("key", "path", "name"), drop = FALSE])
}