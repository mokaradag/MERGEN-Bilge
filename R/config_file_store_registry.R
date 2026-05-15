# ==============================================================================
# R/config_file_store_registry.R
# Dosya deposu kayıt çözümleme ve kullanıcı dosya listeleme yardımcıları.
# R/config_file_store_index_mutation.R dosyasından sonra source edilmelidir.
# ==============================================================================

# ==============================================================================
# DOSYA ÇÖZÜMLEME FONKSİYONU
# Dosya adını (veya yolunu) mevcut bir mutlak yola çözümler.
# Kullanıcı kovasını önceliklendirir.
# ==============================================================================

resolve_uploaded_file <- function(requested,
                                  user_id = NULL,
                                  allow_direct_path = FALSE,
                                  allow_cross_bucket = FALSE,
                                  trusted_roots = character(0)) {
	log_debug("resolve_uploaded_file(): requested='{requested}', user_id='{user_id}'")
	if (is.null(requested) || !(is.character(requested) && length(requested) > 0 && nzchar(requested[1]))) return(NULL)

	requested_chr <- as.character(requested[1])

	if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
	  requested_chr <- normalize_text_utf8(requested_chr, repair_mojibake = TRUE)
	} else {
	  requested_chr <- enc2utf8(requested_chr)
	}

	requested <- requested_chr

	uid <- if (!is.null(user_id) && nzchar(as.character(user_id)[1])) {
	  as.character(user_id)[1]
	} else {
	  NULL
	}

	is_valid_uid <- function(x) {
	  !is.null(x) &&
		nzchar(x) &&
		!(tolower(x) %in% c("0", "unknown", "null", "na"))
	}

	safe_norm <- function(p) {
	  normalize_for_path_compare(normalize_utf8_path(p, mustWork = FALSE))
	}

	path_is_under_root <- function(path, root) {
	  path_norm <- safe_norm(path)
	  root_norm <- safe_norm(root)

	  identical(path_norm, root_norm) ||
		startsWith(path_norm, paste0(root_norm, "/")) ||
		startsWith(path_norm, paste0(root_norm, "\\"))
	}

	user_allowed_roots <- function(uid) {
	  if (!is_valid_uid(uid)) {
		return(character(0))
	  }

	  unique(Filter(nzchar, c(
		tryCatch(mergen_user_upload_dir(uid), error = function(e) ""),
		file.path(MERGEN_UPLOADS_DIR, sprintf("user_%s", uid)),
		file.path(MERGEN_MCP_BASE_DIR, sprintf("user_%s", uid))
	  )))
	}

	path_is_allowed_for_user <- function(path, uid) {
	  roots <- user_allowed_roots(uid)
	  any(vapply(roots, function(root) path_is_under_root(path, root), logical(1)))
	}

	path_is_under_trusted_root <- function(path, trusted_roots) {
	  trusted_roots <- as.character(trusted_roots %||% character(0))
	  trusted_roots <- trusted_roots[nzchar(trusted_roots)]

	  if (!length(trusted_roots)) {
		return(FALSE)
	  }

	  any(vapply(trusted_roots, function(root) path_is_under_root(path, root), logical(1)))
	}

	safe_return_path <- function(path, reason) {
	  if (is.null(path) || !nzchar(as.character(path)[1]) || !path_exists_relaxed(path)) {
		return(NULL)
	  }

	  p <- normalize_mcp_path(path, must_exist = FALSE)
	  log_info("resolve_uploaded_file(): {reason} -> {p}")
	  p
	}

  full_key <- tolower(requested_chr)
  key      <- tolower(basename(requested_chr))
  idx <- .load_index()
  log_debug("resolve_uploaded_file(): full='{full_key}', anahtar='{key}', index kovası sayısı={length(idx)}")

  if (!is.null(user_id)) {
    uid <- as.character(user_id)
    if (!is.null(idx[[uid]])) {
      bucket <- idx[[uid]]

      if (is.list(bucket) && length(bucket)) {
        for (nm in names(bucket)) {
          ent <- bucket[[nm]]
          ent_path <- if (is.list(ent) && !is.null(ent$path)) ent$path else as.character(ent)
          ent_disp <- if (is.list(ent) && !is.null(ent$display)) tolower(as.character(ent$display)) else tolower(nm)
			if (!is.null(ent_path) &&
				path_exists_relaxed(ent_path) &&
				identical(ent_disp, full_key) &&
				path_is_allowed_for_user(ent_path, uid)) {
			  return(safe_return_path(ent_path, "kullanıcı kovasında TAM adla bulundu"))
			}
        }
      }

      hit <- bucket[[key]]
      if (is.list(hit) && !is.null(hit$path)) hit <- hit$path
		if (!is.null(hit) &&
			path_exists_relaxed(hit) &&
			path_is_allowed_for_user(hit, uid)) {
		  return(safe_return_path(hit, "kullanıcı kovasında basename ile bulundu"))
		} else {
		  log_debug("resolve_uploaded_file(): kullanıcı kovasında eşleşme yok (display/basename)")
		}
    } else {
      log_debug("resolve_uploaded_file(): kullanıcı kovası yok: user_id='{uid}'")
    }
  }

  # İndeks eksik/bozuk/boş olsa bile yalnızca kullanıcının kendi fiziksel
  # klasöründe güvenli fallback ara. Bu cross-bucket değildir.
  if (is_valid_uid(uid)) {
    own_roots <- user_allowed_roots(uid)

    for (root in own_roots) {
      root_ok <- tryCatch(path_exists_relaxed(root), error = function(e) FALSE)
      if (!isTRUE(root_ok)) next

      user_files <- tryCatch(
        list.files(root, full.names = TRUE, recursive = FALSE, include.dirs = FALSE),
        error = function(e) character(0)
      )

      if (!length(user_files)) {
        next
      }

      file_bases <- tolower(basename(user_files))

      matched_files <- user_files[
        file_bases == key |
          endsWith(file_bases, paste0("_", key))
      ]

      if (length(matched_files) > 0) {
        matched_files <- matched_files[
          vapply(
            matched_files,
            function(p) path_exists_relaxed(p) && path_is_allowed_for_user(p, uid),
            logical(1)
          )
        ]
      }

      if (length(matched_files) > 0) {
        return(safe_return_path(
          matched_files[1],
          "kullanıcının kendi klasöründe filesystem fallback ile bulundu"
        ))
      }
    }
  }

  if (isTRUE(allow_direct_path) && path_exists_relaxed(requested_chr)) {
    direct_allowed <- FALSE

    if (is_valid_uid(uid) && path_is_allowed_for_user(requested_chr, uid)) {
      direct_allowed <- TRUE
    }

    if (path_is_under_trusted_root(requested_chr, trusted_roots)) {
      direct_allowed <- TRUE
    }

    if (isTRUE(direct_allowed)) {
      return(safe_return_path(requested_chr, "izinli doğrudan yol bulundu"))
    }

    log_warn("resolve_uploaded_file(): doğrudan yol reddedildi; kullanıcı kovası veya trusted_roots altında değil")
    return(NULL)
  }

  if (isTRUE(allow_cross_bucket)) {
    if (length(idx)) {
      for (bucket_name in names(idx)) {
        bucket <- idx[[bucket_name]]
        if (is.list(bucket)) {
          for (nm in names(bucket)) {
            ent <- bucket[[nm]]
            ent_path <- if (is.list(ent) && !is.null(ent$path)) ent$path else as.character(ent)
            ent_disp <- if (is.list(ent) && !is.null(ent$display)) tolower(as.character(ent$display)) else tolower(nm)
            if (!is.null(ent_path) && path_exists_relaxed(ent_path) && identical(ent_disp, full_key)) {
              p <- normalize_mcp_path(ent_path, must_exist = FALSE)
              log_info("resolve_uploaded_file(): display ile kovalar arasında bulundu (bucket='{bucket_name}') -> {p}")
              return(p)
            }
          }
        }
      }
    }

    hit <- idx[[key]]
    if (is.list(hit) && !is.null(hit$path)) hit <- hit$path
    if (!is.null(hit) && path_exists_relaxed(hit)) {
      p <- normalize_mcp_path(hit, must_exist = FALSE)
      log_info("resolve_uploaded_file(): legacy haritada (basename) bulundu -> {p}")
      return(p)
    }

    if (length(idx)) {
      for (bucket_name in names(idx)) {
        bucket <- idx[[bucket_name]]
        if (is.list(bucket)) {
          hit <- bucket[[key]]
          if (is.list(hit) && !is.null(hit$path)) hit <- hit$path
          if (!is.null(hit) && path_exists_relaxed(hit)) {
            p <- normalize_mcp_path(hit, must_exist = FALSE)
            log_info("resolve_uploaded_file(): çapraz kovada (basename) bulundu (bucket='{bucket_name}') -> {p}")
            return(p)
          }
        }
      }
    }
  }

  log_warn("resolve_uploaded_file(): '{requested}' için eşleşme bulunamadı")
  NULL
}

# ==============================================================================
# KULLANICI YÜKLEME DİZİNİ YARDIMCILARI
# ==============================================================================

mergen_user_upload_dir <- function(user_id) {
  base <- resolve_mcp_base_dir()
  p <- file.path(base, sprintf("user_%s", as.character(user_id)))
  created <- tryCatch({
    fs::dir_create(p, recurse = TRUE)
    TRUE
  }, error = function(e) {
    log_warn("[INDEX] Kullanıcı klasörü oluşturulamadı ({conditionMessage(e)}); varsayılan dizine düşülüyor")
    FALSE
  })

  p_exists <- tryCatch(path_exists_relaxed(p), error = function(e) dir.exists(p))
  if (!isTRUE(created) || !isTRUE(p_exists)) {
    fallback <- file.path(MERGEN_UPLOADS_DIR, sprintf("user_%s", as.character(user_id)))
    fs::dir_create(fallback, recurse = TRUE)
    fallback_exists <- tryCatch(path_exists_relaxed(fallback), error = function(e) dir.exists(fallback))
    return(normalize_mcp_path(fallback, must_exist = isTRUE(fallback_exists)))
  }

  normalize_mcp_path(p, must_exist = isTRUE(p_exists))
}

mergen_resolve_display_name <- function(file_path, user_id = NULL, idx = NULL) {
  idx_all <- idx %||% .load_index()

  hedef_yol <- normalize_for_path_compare(file_path)
  hedef_basename <- tolower(basename(file_path %||% ""))

  oncelikli_kovalar <- character(0)
  if (!is.null(user_id) && nzchar(as.character(user_id))) {
    uid <- as.character(user_id)
    if (!is.null(idx_all[[uid]])) {
      oncelikli_kovalar <- uid
    }
  }

	kovalar <- if (length(oncelikli_kovalar) > 0L) {
	  oncelikli_kovalar
	} else {
	  character(0)
	}

  for (kova_adi in kovalar) {
    kova <- idx_all[[kova_adi]]

    aday_kayitlar <- if (is.list(kova) && (!is.null(kova$path) || !is.null(kova$display))) {
      list(kova)
    } else if (is.list(kova) && length(kova) > 0) {
      unname(kova)
    } else {
      list()
    }

    for (kayit in aday_kayitlar) {
      kayit_yolu <- if (is.list(kayit) && !is.null(kayit$path)) {
        as.character(kayit$path)
      } else {
        as.character(kayit %||% "")
      }

      kayit_gorunen_ad <- if (is.list(kayit) && !is.null(kayit$display)) {
        as.character(kayit$display)
      } else {
        ""
      }

      if (!nzchar(kayit_yolu) || !nzchar(kayit_gorunen_ad)) next

      ayni_yol <- identical(
        normalize_for_path_compare(kayit_yolu),
        hedef_yol
      )

      ayni_dosya <- identical(
        tolower(basename(kayit_yolu)),
        hedef_basename
      )

      if (ayni_yol || ayni_dosya) {
        if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
          return(normalize_text_utf8(kayit_gorunen_ad, repair_mojibake = TRUE))
        }
        return(enc2utf8(kayit_gorunen_ad))
      }
    }
  }

  recover_display_name_from_storage_name(file_path)
}

mergen_list_user_files <- function(user_id, prune_missing = TRUE) {
  idx <- .load_index()
  uid <- as.character(user_id)
  bucket <- idx[[uid]]

  drop_stale_entries <- function(records_to_remove) {
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

    TRUE
  }

  if (!is.null(bucket) && length(bucket) > 0) {
	entries <- lapply(names(bucket), function(key) {
	  val <- bucket[[key]]
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
	})

    df <- do.call(rbind, lapply(entries, function(rec) {
      data.frame(key = rec$key, path = rec$path, name = rec$name, stringsAsFactors = FALSE)
    }))

    rehydrated <- list()
    exists_vec <- vapply(seq_len(nrow(df)), function(i) {
      p <- df$path[i]
      exists_now <- path_exists_relaxed(p)

      if (!exists_now) {
        alt <- tryCatch({
          candidate <- file.path(mergen_user_upload_dir(user_id), basename(p %||% df$name[i]))
          normalize_mcp_path(candidate, must_exist = dir.exists(dirname(candidate)))
        }, error = function(e) NULL)

        if (!is.null(alt) && path_exists_relaxed(alt)) {
          df$path[i] <<- alt
          rehydrated[[df$key[i]]] <<- list(old_path = p, new_path = alt)
          exists_now <- TRUE
          log_info("[INDEX] {df$name[i]} yolu yeniden oluşturuldu -> {alt}")
        }
      }

      exists_now
    }, logical(1))

    if (length(rehydrated)) {
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
    }

    if (prune_missing && any(!exists_vec)) {
      missing_df <- df[!exists_vec, c("key", "path", "name"), drop = FALSE]
      missing_names <- unique(missing_df$name)
      log_warn("[INDEX] {nrow(missing_df)} kayıt bulunamadı (user={uid}): {paste(missing_names, collapse = ', ')} — indeks temizleniyor")
      drop_stale_entries(missing_df)
    }

	df <- df[exists_vec, , drop = FALSE]

	if (nrow(df) > 0) {
	  filesystem_paths <- character(0)
	  user_dir_for_merge <- tryCatch(mergen_user_upload_dir(user_id), error = function(e) "")

	  if (nzchar(user_dir_for_merge) &&
		  isTRUE(tryCatch(path_exists_relaxed(user_dir_for_merge), error = function(e) FALSE))) {
		filesystem_paths <- tryCatch(
		  list.files(
			user_dir_for_merge,
			full.names = TRUE,
			recursive = FALSE,
			include.dirs = FALSE
		  ),
		  error = function(e) character(0)
		)
	  }

	  if (length(filesystem_paths) > 0L) {
		existing_norm <- vapply(df$path, normalize_for_path_compare, character(1))
		filesystem_norm <- vapply(filesystem_paths, normalize_for_path_compare, character(1))
		extra_paths <- filesystem_paths[!(filesystem_norm %in% existing_norm)]

		if (length(extra_paths) > 0L) {
		  extra_df <- data.frame(
			key = tolower(basename(extra_paths)),
			path = vapply(extra_paths, normalize_utf8_path, character(1), mustWork = FALSE),
			name = vapply(
			  extra_paths,
			  function(p) mergen_resolve_display_name(
				p,
				user_id = user_id,
				idx = idx
			  ),
			  character(1)
			),
			stringsAsFactors = FALSE
		  )

		  df <- rbind(df, extra_df[, c("key", "path", "name"), drop = FALSE])
		}
	  }

	  out <- data.frame(
		path = df$path,
		name = vapply(df$name, normalize_file_display_name, character(1)),
		stringsAsFactors = FALSE
	  )

	  attr(out, "source") <- "index+filesystem"
	  attr(out, "count") <- nrow(out)
	  log_info("[INDEX] user={uid} için {nrow(out)} dosya bulundu (kaynak: index+filesystem)")
	  return(out)
	}
  }

  dir <- mergen_user_upload_dir(user_id)

  dir_ok <- tryCatch(path_exists_relaxed(dir), error = function(e) dir.exists(dir))
  if (!isTRUE(dir_ok) && grepl("^/[^/]", dir)) {
    dir_unc <- paste0("/", dir)
    if (isTRUE(tryCatch(path_exists_relaxed(dir_unc), error = function(e) FALSE))) {
      dir <- dir_unc
      dir_ok <- TRUE
    }
  }

  if (!isTRUE(dir_ok)) {
    log_info("[INDEX] user={uid} için klasör bulunamadı: {dir}")
    return(data.frame(path = character(), name = character(), stringsAsFactors = FALSE))
  }

  list_user_files_relaxed <- function(dir_path) {
    dir_chr <- as.character(dir_path %||% "")
    if (!nzchar(dir_chr)) return(character(0))

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
      if (length(files_base)) return(files_base)

      files_fs <- tryCatch(
        as.character(fs::dir_ls(v, recurse = FALSE, type = "file")),
        error = function(e) character(0)
      )
      if (length(files_fs)) return(files_fs)
    }

    character(0)
  }

  paths <- list_user_files_relaxed(dir)
  if (!length(paths)) {
    log_info("[INDEX] user={uid} klasörü boş: {dir}")
    return(data.frame(path = character(), name = character(), stringsAsFactors = FALSE))
  }

  idx_cache <- .load_index()

  out <- data.frame(
    path = vapply(paths, normalize_utf8_path, character(1), mustWork = FALSE),
    name = vapply(
      paths,
      function(p) mergen_resolve_display_name(
        p,
        user_id = user_id,
        idx = idx_cache
      ),
      character(1)
    ),
    stringsAsFactors = FALSE
  )

  attr(out, "source") <- "filesystem"
  attr(out, "count") <- nrow(out)
  log_info("[INDEX] user={uid} için {nrow(out)} dosya bulundu (kaynak: filesystem)")
  out
}