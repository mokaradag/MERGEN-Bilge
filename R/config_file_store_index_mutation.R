# ==============================================================================
# R/config_file_store_index_mutation.R
# Dosya deposu indeks mutasyonları: güvenli indeks yazımı, yükleme kaydı,
# görünen ad onarımı ve indeks girdisi silme yardımcıları.
# R/config_file_store.R dosyasından sonra source edilmelidir.
# ==============================================================================

.file_store_with_index_lock <- function(expr, timeout_sec = 5, poll_sec = 0.05) {
  lock_dir <- paste0(MERGEN_INDEX_PATH, ".lock")
  start_time <- Sys.time()
  acquired <- FALSE

  repeat {
    acquired <- tryCatch(
      dir.create(lock_dir, showWarnings = FALSE, recursive = FALSE),
      warning = function(w) FALSE,
      error = function(e) FALSE
    )

    if (isTRUE(acquired)) {
      break
    }

    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    if (!is.finite(elapsed) || elapsed >= timeout_sec) {
      break
    }

    Sys.sleep(poll_sec)
  }

  if (!isTRUE(acquired)) {
    try(
      log_warn("[INDEX] İndeks kilidi alınamadı; mevcut davranışı korumak için kilitsiz devam ediliyor: {lock_dir}"),
      silent = TRUE
    )
    return(force(expr))
  }

  on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)

  force(expr)
}

.file_store_mutate_index <- function(mutator) {
  if (!is.function(mutator)) {
    stop("mutator fonksiyon olmalıdır.", call. = FALSE)
  }

  .file_store_with_index_lock({
    idx <- .load_index()
    next_idx <- mutator(idx)

    if (is.null(next_idx)) {
      next_idx <- idx
    }

    .save_index(next_idx)
    next_idx
  })
}

recover_display_name_from_storage_name <- function(file_path) {
  base_name <- basename(file_path %||% "")
  if (!nzchar(base_name)) {
    return(base_name)
  }

  # Kalıcı depolama adları kullanıcıya gösterilmemelidir.
  # Desteklenen iç storage prefix örnekleri:
  # - 20260505-120545_abcd1234_orijinal.pdf
  # - 20260505120545_1234_orijinal.pdf
  # - 20260505120545839_abcd1234_ef567890_orijinal.pdf
  # Son örnek, aynı dosya aynı anda/çok hızlı yüklendiğinde hedef çakışmasını
  # önlemek için eklenen ikinci benzersiz token'ı içerir.
  storage_prefix_patterns <- c(
    "^\\d{15,20}_[0-9A-Fa-f]{4,64}_[0-9A-Fa-f]{4,64}_",
    "^\\d{8}-?\\d{6}_[0-9A-Za-z]{4,64}_"
  )

  for (pattern in storage_prefix_patterns) {
    cleaned <- sub(pattern, "", base_name, perl = TRUE)

    if (nzchar(cleaned) && !identical(cleaned, base_name)) {
      if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
        return(normalize_text_utf8(cleaned, repair_mojibake = TRUE))
      }
      return(enc2utf8(cleaned))
    }
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(base_name, repair_mojibake = TRUE))
  }

  enc2utf8(base_name)
}

repair_index_display_names_from_path <- function() {
  fix_node <- function(node) {
    if (is.list(node) && !is.null(node$path)) {
      path_value <- as.character(node$path)[1]
      node$path <- path_value
      node$display <- recover_display_name_from_storage_name(path_value)
      return(node)
    }

    if (is.list(node)) {
      for (nm in names(node)) {
        node[[nm]] <- fix_node(node[[nm]])
      }
      return(node)
    }

    node
  }

  idx_fixed <- .file_store_mutate_index(function(idx) {
    fix_node(idx)
  })

  invisible(idx_fixed)
}

# ==============================================================================
# DOSYA KAYIT FONKSİYONU
# Kaynak dosyayı kalıcı depoya kopyalar ve kullanıcı kovasına indeksler.
# ==============================================================================

mergen_register_uploaded_file <- function(src_path,
                                          as_name = basename(src_path),
                                          user_id = NULL,
                                          persist_under_mcp_base = TRUE) {
  base_dir <- if (isTRUE(persist_under_mcp_base)) resolve_mcp_base_dir() else MERGEN_FILES_ROOT
  user_folder <- if (!is.null(user_id)) {
    file.path(base_dir, paste0("user_", as.character(user_id)))
  } else {
    base_dir
  }
  fs::dir_create(user_folder, recurse = TRUE)

  preserve_existing_path <- function(p, must_exist = FALSE) {
    if (is.null(p) || length(p) == 0) return("")
    candidate <- gsub("\\\\", "/", as.character(p[1]), fixed = TRUE)
    if (!nzchar(candidate)) return("")
    if (!must_exist || path_exists_relaxed(candidate)) {
      return(enc2utf8(candidate))
    }
    tryCatch(
      normalize_mcp_path(candidate, must_exist = must_exist),
      error = function(e) enc2utf8(candidate)
    )
  }

  src_norm  <- preserve_existing_path(src_path, must_exist = FALSE)
  base_norm <- preserve_existing_path(base_dir, must_exist = FALSE)

  normalize_for_compare <- function(p) {
    if (is.null(p)) return("")
    val <- tolower(as.character(p))
    val <- gsub("\\\\", "/", val, fixed = TRUE)
    val <- sub("^//\\?/", "", val, perl = TRUE)
    val <- sub("^//(?=[A-Za-z]:)", "", val, perl = TRUE)
    val <- gsub("(?<!:)//+", "/", val, perl = TRUE)
    trimws(val)
  }

  src_cmp  <- normalize_for_compare(src_norm)
  base_cmp <- normalize_for_compare(base_norm)

  src_parent <- tryCatch(basename(dirname(src_norm)), error = function(e) "")
  src_grand  <- tryCatch(basename(dirname(dirname(src_norm))), error = function(e) "")
  user_leaf  <- tryCatch(basename(user_folder), error = function(e) "")
  base_leaf  <- tryCatch(basename(base_dir), error = function(e) "")

  already_in_user_bucket <- isTRUE(path_exists_relaxed(src_norm)) &&
    nzchar(src_parent) && nzchar(src_grand) &&
    nzchar(user_leaf) && nzchar(base_leaf) &&
    identical(tolower(src_parent), tolower(user_leaf)) &&
    identical(tolower(src_grand), tolower(base_leaf))

  if (
    already_in_user_bucket ||
    (nzchar(base_cmp) &&
      (identical(src_cmp, base_cmp) || startsWith(src_cmp, paste0(base_cmp, "/"))))
  ) {
    dest_norm <- src_norm
  } else {
    unique_name <- paste0(
      format(Sys.time(), "%Y%m%d%H%M%S"), "_",
      sprintf("%04d", sample(0:9999, 1)), "_",
      basename(as_name)
    )
    dest <- file.path(user_folder, unique_name)
    copy_ok <- tryCatch({
      fs::file_copy(src_path, dest, overwrite = TRUE)
      TRUE
    }, error = function(e) {
      message(sprintf("[UPLOAD] Kopyalama başarısız: %s", e$message))
      FALSE
    })

    if (!isTRUE(copy_ok) || !fs::file_exists(dest)) {
      stop(sprintf("Dosya kopyalanamadı: %s -> %s", src_path, dest))
    }

    dest_norm <- gsub("\\\\", "/", as.character(dest), fixed = TRUE)
    if (!path_exists_relaxed(dest_norm)) {
      dest_norm <- normalize_mcp_path(dest_norm, must_exist = TRUE)
    } else {
      dest_norm <- enc2utf8(dest_norm)
    }
  }

  display_name <- basename(as_name)

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    display_name <- normalize_text_utf8(display_name, repair_mojibake = TRUE)
    dest_norm <- normalize_text_utf8(dest_norm, repair_mojibake = FALSE)
  } else {
    display_name <- enc2utf8(display_name)
    dest_norm <- enc2utf8(dest_norm)
  }

  key <- tolower(display_name)
  entry <- list(path = dest_norm, display = display_name)

  .file_store_mutate_index(function(idx) {
    if (!is.null(user_id)) {
      uid <- as.character(user_id)
      if (is.null(idx[[uid]])) idx[[uid]] <- list()
      idx[[uid]][[key]] <- entry
    } else {
      idx[[key]] <- entry
    }

    idx
  })

  dest_norm
}

# Esnek seçenekli takma ad; server tarafından MCP dosyalarını kaydetmek için kullanılır
global_register_file <- function(src_path,
                                 filename,
                                 user_id = NULL,
                                 persist_under_mcp_base = TRUE) {
  mergen_register_uploaded_file(
    src_path,
    as_name = filename,
    user_id = user_id,
    persist_under_mcp_base = persist_under_mcp_base
  )
}

# İndeksten belirli bir dosyayı kaldırır
mergen_remove_from_index <- function(user_id, filename) {
  uid <- as.character(user_id)
  key <- tolower(basename(filename))

  .file_store_mutate_index(function(idx) {
    if (!is.null(idx[[uid]])) {
      idx[[uid]][[key]] <- NULL
      if (is.list(idx[[uid]]) && !length(idx[[uid]])) {
        idx[[uid]] <- NULL
      }
    }

    idx
  })

  invisible(TRUE)
}