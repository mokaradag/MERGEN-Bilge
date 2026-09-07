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

# YÜKLEME ARA ÜRÜNLERİ listelemeden AYIKLANIR. Aşamalı kopya `.mergen-part`
# adına yazılır ve terfiden sonra silinir; Windows/UNC kilidinde `unlink()`
# sessizce başarısız olabildiği için bu ad diskte kalabilir. İndekste kaydı
# olmadığından yalnızca dosya sistemi fallback'inde görünür ve orada GEÇERLİ bir
# yükleme gibi listeleniyordu (açılamayan/yarım dosya). Rezervasyon dizinleri
# `include.dirs = FALSE` ile zaten dışlanır; `fs::dir_ls(type = "file")` de
# dizinleri getirmez, ancak marker dosyası bir dizin İÇİNDE olduğu için
# `recurse = FALSE` ile görünmez.
# Yalnızca DOSYA tabanlı aşamalı kopya soneki ayıklanır. REZERVASYON sonekleri
# (`.mergen-rsv`, `.aw-rsv`, `.oo-rsv`) yalnızca `dir.create()` ile üretilen
# DİZİNLERE aittir ve iki listeleme API'si de dizinleri zaten dışlar
# (`include.dirs = FALSE`, `fs::dir_ls(type = "file")`). Bu sonekleri dosya
# filtresine almak, aynı sonekle adlandırılmış GEÇERLİ bir dosyayı kullanıcı
# listelemesinden düşürüyordu.
#
# Yapılandırılmış değer GEÇERSİZSE (`NULL`, `NA`, boş, `character(0)`)
# varsayılana düşülür: `[1]` sonucu `NA` olduğunda `endsWith()` de `NA` üretiyor
# ve normal dosya yolları `NA` girdilerine dönüşüyordu.
.file_store_artifact_suffixes <- function() {
  sonek_ya_da_varsayilan <- function(ad, varsayilan) {
    deger <- if (exists(ad, inherits = TRUE)) {
      suppressWarnings(as.character(get(ad, inherits = TRUE)))
    } else {
      NA_character_
    }
    deger <- deger[1]
    if (length(deger) != 1L || is.na(deger) || !nzchar(deger)) varsayilan else deger
  }

  sonek_ya_da_varsayilan("MERGEN_UPLOAD_STAGING_SUFFIX", ".mergen-part")
}

# Dizinler listelemeden ayıklanır (`list.files(recursive = FALSE)` dizinleri de
# döndürür; `include.dirs` yalnızca özyinelemeli çağrıda etkilidir).
.file_store_drop_directories <- function(paths) {
  if (!length(paths)) return(paths)
  dizin <- vapply(
    as.character(paths),
    function(p) isTRUE(tryCatch(dir.exists(p), error = function(e) FALSE)),
    logical(1),
    USE.NAMES = FALSE
  )
  paths[!dizin]
}

.file_store_drop_upload_artifacts <- function(paths) {
  if (!length(paths)) return(paths)
  sonekler <- .file_store_artifact_suffixes()
  sonekler <- unique(sonekler[!is.na(sonekler) & nzchar(sonekler)])
  if (!length(sonekler)) return(paths)
  adlar <- basename(as.character(paths))
  tut <- !Reduce(`|`, lapply(sonekler, function(s) endsWith(adlar, s)))
  paths[tut]
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
    # `include.dirs` YALNIZCA `recursive = TRUE` ile etkilidir; `recursive =
    # FALSE` çağrısı DİZİNLERİ de döndürür. Dizinler bu yüzden AÇIKÇA ayıklanır:
    # rezervasyon dizinleri (`.mergen-rsv`, `.aw-rsv`, `.oo-rsv`) böylece sonek
    # eşleşmesine bakılmadan düşer ve aynı soneki taşıyan GEÇERLİ bir DOSYA
    # kullanıcı listelemesinde kalır.
    files_base <- tryCatch(
      list.files(v, full.names = TRUE, recursive = FALSE, include.dirs = FALSE),
      error = function(e) character(0)
    )
    files_base <- .file_store_drop_directories(files_base)
    # AYIKLAMA listeleme BAŞARISI denetiminden ÖNCE yapılır: yalnızca ara ürün
    # içeren bir klasör "dosya var" sayılıp sonraki varyantı denemeyi engellerdi.
    files_base <- .file_store_drop_upload_artifacts(files_base)
    if (length(files_base)) {
      return(files_base)
    }

    files_fs <- tryCatch(
      as.character(fs::dir_ls(v, recurse = FALSE, type = "file")),
      error = function(e) character(0)
    )
    files_fs <- .file_store_drop_upload_artifacts(files_fs)
    if (length(files_fs)) {
      return(files_fs)
    }
  }

  character(0)
}

.file_store_user_dir_paths <- function(user_id) {
  uid <- as.character(user_id)

  candidate_dirs <- unique(Filter(nzchar, c(
    tryCatch(mergen_user_upload_dir(uid), error = function(e) ""),
    file.path(getOption("mergen.mcp_base_dir", ""), paste0("user_", uid)),
    file.path(getOption("mergen.files_root", ""), paste0("user_", uid)),
    if (exists("MERGEN_MCP_BASE_DIR", inherits = TRUE)) {
      file.path(MERGEN_MCP_BASE_DIR, paste0("user_", uid))
    } else {
      ""
    },
    if (exists("MERGEN_UPLOADS_DIR", inherits = TRUE)) {
      file.path(MERGEN_UPLOADS_DIR, paste0("user_", uid))
    } else {
      ""
    }
  )))

  if (!length(candidate_dirs)) {
    return(character(0))
  }

  paths <- unique(unlist(lapply(candidate_dirs, function(user_dir) {
    if (!isTRUE(tryCatch(path_exists_relaxed(user_dir), error = function(e) FALSE))) {
      return(character(0))
    }

    .file_store_list_user_files_relaxed(user_dir)
  }), use.names = FALSE))

  paths[nzchar(paths)]
}

.file_store_file_size_safe <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size)) {
    return(NA_real_)
  }
  as.numeric(size)
}

.file_store_lifecycle_key <- function(path, name = NULL) {
  display <- normalize_file_display_name(name %||% recover_display_name_from_storage_name(path))

  if (!nzchar(display)) {
    display <- recover_display_name_from_storage_name(path)
  }

  tolower(display)
}

.file_store_deduplicate_rows <- function(df) {
  if (is.null(df) || !is.data.frame(df) || nrow(df) == 0L) {
    return(df)
  }

  keys <- vapply(
    seq_len(nrow(df)),
    function(i) .file_store_lifecycle_key(df$path[i], df$name[i]),
    character(1)
  )

  df[!duplicated(keys), , drop = FALSE]
}

.file_store_merge_same_user_filesystem <- function(df, user_id, idx) {
  df <- .file_store_deduplicate_rows(df)

  filesystem_paths <- .file_store_user_dir_paths(user_id)
  if (!length(filesystem_paths)) {
    return(df)
  }

  filesystem_df <- data.frame(
    key = tolower(basename(filesystem_paths)),
    path = vapply(filesystem_paths, normalize_utf8_path, character(1), mustWork = FALSE),
    name = vapply(
      filesystem_paths,
      function(p) mergen_resolve_display_name(p, user_id = user_id, idx = idx),
      character(1)
    ),
    stringsAsFactors = FALSE
  )

  filesystem_df <- .file_store_deduplicate_rows(filesystem_df)

	existing_keys <- vapply(
	  seq_len(nrow(df)),
	  function(i) .file_store_lifecycle_key(df$path[i], df$name[i]),
	  character(1)
	)

	filesystem_keys <- vapply(
	  seq_len(nrow(filesystem_df)),
	  function(i) .file_store_lifecycle_key(filesystem_df$path[i], filesystem_df$name[i]),
	  character(1)
	)

	keep_extra <- !(filesystem_keys %in% existing_keys)
	extra_df <- filesystem_df[keep_extra, , drop = FALSE]

  if (!nrow(extra_df)) {
    return(df)
  }

  .file_store_deduplicate_rows(
    rbind(df, extra_df[, c("key", "path", "name"), drop = FALSE])
  )
}