# ==============================================================================
# R/config_file_store_index_mutation.R
# Dosya deposu indeks mutasyonları: güvenli indeks yazımı, yükleme kaydı,
# görünen ad onarımı ve indeks girdisi silme yardımcıları.
# R/config_file_store.R ve R/config_file_store_index_lock.R dosyalarından
# sonra source edilmelidir; .file_store_with_index_lock kilit yardımcısı
# ayrı kilit dosyasında yaşar (fonksiyon-yoğunluk bölme sözleşmesi).
# ==============================================================================

.file_store_mutate_index <- function(mutator) {
  if (!is.function(mutator)) {
    stop("mutator fonksiyon olmalıdır.", call. = FALSE)
  }

  # KİLİTSİZ MUTASYON YOK: sahiplik doğrulanamazsa eşzamanlı iki yazar aynı
  # anlık görüntüyü kaydedip birbirinin indeks güncellemesini siliyordu.
  .file_store_with_index_lock({
    idx <- .load_index()
    next_idx <- mutator(idx)

    if (is.null(next_idx)) {
      next_idx <- idx
    }

    .save_index(next_idx)
    next_idx
  }, require_lock = TRUE)
}

recover_display_name_from_storage_name <- function(file_path) {
  base_name <- basename(file_path %||% "")
  if (!nzchar(base_name)) {
    return(base_name)
  }

  # Kalıcı depolama adları kullanıcıya gösterilmemelidir.
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

normalize_file_display_name <- function(file_name, file_info = NULL) {
  candidates <- character(0)

  if (is.list(file_info)) {
    candidates <- c(
      candidates,
      file_info$display_name %||% "",
      file_info$display %||% "",
      file_info$original_name %||% "",
      file_info$name %||% ""
    )
  }

  candidates <- c(candidates, file_name %||% "")

  for (candidate in candidates) {
    candidate <- as.character(candidate %||% "")[1]
    if (is.na(candidate) || !nzchar(candidate)) {
      next
    }

    cleaned <- tryCatch(
      recover_display_name_from_storage_name(candidate),
      error = function(e) candidate
    )

    if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
      cleaned <- normalize_text_utf8(cleaned, repair_mojibake = TRUE)
    } else {
      cleaned <- enc2utf8(cleaned)
    }

    if (!is.na(cleaned) && nzchar(cleaned)) {
      return(cleaned)
    }
  }

  ""
}

repair_index_display_names_from_path <- function() {
  fix_node <- function(node) {
	if (is.list(node) && !is.null(node$path)) {
	  path_value <- as.character(node$path)[1]
	  existing_display <- as.character(node$display %||% "")[1]

	  node$path <- path_value
	  node$display <- normalize_file_display_name(
		existing_display,
		file_info = list(
		  path = path_value,
		  display = existing_display,
		  name = path_value
		)
	  )

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

# İndeks girdisinin anahtar/görünen ad/yol normalizasyonu tek kaynaktan gelir;
# tekil kayıt ve toplu kayıt yolları aynı kuralları kullanır.
.file_store_index_entry <- function(path, display_name) {
  display_name <- basename(as.character(display_name %||% "")[1])
  path <- as.character(path %||% "")[1]

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    display_name <- normalize_text_utf8(display_name, repair_mojibake = TRUE)
    path <- normalize_text_utf8(path, repair_mojibake = FALSE)
  } else {
    display_name <- enc2utf8(display_name)
    path <- enc2utf8(path)
  }

  list(key = tolower(display_name), path = path, display = display_name)
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
    kopyalandi <- FALSE
  } else {
    kopyalandi <- TRUE
    # Aynı saniyede aynı rastgele son ek üretilirse mevcut dosya EZİLMEZ:
    # hedef varsa yeni ad üretilir ve kopya overwrite = FALSE ile yapılır.
    # `file_exists` + `file_copy` atomik DEĞİLDİR: eşzamanlı bir yükleme aynı
    # adı aradaki pencerede yaratırsa overwrite = FALSE hata verir. Kopyalama
    # bu yüzden deneme döngüsünün İÇİNDE yapılır ve hedef-zaten-var hatasında
    # kalan adaylarla devam edilir.
    dest <- ""
    son_hata <- ""
    for (deneme in seq_len(5L)) {
      unique_name <- paste0(
        format(Sys.time(), "%Y%m%d%H%M%S"), "_",
        sprintf("%04d", sample(0:9999, 1)), "_",
        basename(as_name)
      )
      aday <- file.path(user_folder, unique_name)
      if (fs::file_exists(aday)) next

      kopya <- tryCatch({
        fs::file_copy(src_path, aday, overwrite = FALSE)
        TRUE
      }, error = function(e) {
        son_hata <<- conditionMessage(e)
        FALSE
      })

      if (!isTRUE(kopya)) next

      # Windows/UNC hedefinde kopya kısa süre görünmeyebilir. Yeni adla
      # yeniden kopyalamak diskte indekslenmemiş yetim dosyalar bırakıyordu;
      # görünürlük için SINIRLI beklenir, süre aşılırsa aday TEMİZLENİR.
      gorunur <- FALSE
      for (bekleme in seq_len(10L)) {
        if (isTRUE(fs::file_exists(aday)) || isTRUE(path_exists_relaxed(aday))) {
          gorunur <- TRUE
          break
        }
        Sys.sleep(0.05)
      }

      if (isTRUE(gorunur)) {
        dest <- aday
        break
      }

      son_hata <- sprintf("kopya görünür olmadı: %s", aday)
      try(fs::file_delete(aday), silent = TRUE)
    }

    if (!nzchar(dest)) {
      if (nzchar(son_hata)) {
        message(sprintf("[UPLOAD] Kopyalama başarısız: %s", son_hata))
      }
      stop(sprintf("Dosya kopyalanamadı: %s -> %s", src_path, user_folder))
    }

    dest_norm <- gsub("\\\\", "/", as.character(dest), fixed = TRUE)
    if (!path_exists_relaxed(dest_norm)) {
      dest_norm <- normalize_mcp_path(dest_norm, must_exist = TRUE)
    } else {
      dest_norm <- enc2utf8(dest_norm)
    }
  }

  kayit <- .file_store_index_entry(dest_norm, as_name)
  dest_norm <- kayit$path
  key <- kayit$key
  entry <- list(path = kayit$path, display = kayit$display)

  # Kopyalama kilit DIŞINDA yapılır: eşzamanlı bir kova temizliği kopyayı bu
  # aralıkta silmiş olabilir. Varlık denetimi indeks kilidinin İÇİNDE yapılır ki
  # indekse var olmayan bir dosya yazılmasın.
  # Kopya indeks kilidinin DIŞINDA tamamlanır: kilit edinimi ya da indeks yazımı
  # düşerse kopya `user_folder` içinde indekslenmemiş kalıyordu. Her denemede
  # yeni bir yetim dosya birikiyor ve dosya sistemi fallback'i bunu yükleme
  # başarısız bildirildikten sonra da sunabiliyordu.
  kayitli <- FALSE
  # Mutator, `.save_index()` ÇAĞRILMADAN ÖNCE çalışır. `kayitli` mutator
  # içinde TRUE yapıldığında `atomic_write_json()` hatasında `temizle_kopya()`
  # kopyayı silmiyor ve indekssiz yetim dosya kalıyordu.
  dosya_vardi <- FALSE
  temizle_kopya <- function() {
    if (isTRUE(kopyalandi) && !isTRUE(kayitli)) {
      try(fs::file_delete(dest_norm), silent = TRUE)
    }
  }

  tryCatch(.file_store_mutate_index(function(idx) {
    # Varlık denetimi YENİDEN KULLANILAN yollar için de yapılır: kaynak zaten
    # kalıcı kovadaysa `kopyalandi` FALSE olur ve eşzamanlı bir
    # `mergen_clear_user_bucket()` dosyayı bu aralıkta silmiş olabilirdi;
    # indekse var olmayan bir yol yazılıyordu.
    if (!isTRUE(path_exists_relaxed(dest_norm))) return(idx)

    if (!is.null(user_id)) {
      uid <- as.character(user_id)
      if (is.null(idx[[uid]])) idx[[uid]] <- list()
      idx[[uid]][[key]] <- entry
    } else {
      idx[[key]] <- entry
    }

    dosya_vardi <<- TRUE
    idx
  }), error = function(e) {
    temizle_kopya()
    stop(e)
  })

  # Kayıt YALNIZCA indeks yazımı (`.save_index()`) tamamlandıktan sonra
  # başarılı sayılır.
  kayitli <- isTRUE(dosya_vardi)

  if (!isTRUE(kayitli)) {
    temizle_kopya()
    stop(sprintf("Kayıt sırasında dosya bulunamadı (eşzamanlı temizlik?): %s", dest_norm))
  }

  dest_norm
}

# Kalıcı klasöre ZATEN kopyalanmış dosyaları TEK indeks mutasyonunda kaydeder.
# Dosya alım hattı (R/helpers_file_ingestion_runtime.R) kopyalamayı worker'da
# yaptığı için burada yeniden kopyalama yapılmaz; parti başına tek kilit/tek
# JSON yazımı ile ana süreçteki indeks maliyeti dosya sayısından bağımsız kalır.
mergen_index_persisted_files <- function(entries, user_id = NULL) {
  entries <- entries %||% list()
  if (!length(entries)) return(character())

  hazirlanan <- lapply(entries, function(e) {
    .file_store_index_entry(e$path, e$display %||% basename(e$path %||% ""))
  })
  hazirlanan <- Filter(function(e) nzchar(e$key) && nzchar(e$path), hazirlanan)

  if (!length(hazirlanan)) return(character())

  .file_store_mutate_index(function(idx) {
    for (kayit in hazirlanan) {
      girdi <- list(path = kayit$path, display = kayit$display)

      if (!is.null(user_id)) {
        uid <- as.character(user_id)
        if (is.null(idx[[uid]])) idx[[uid]] <- list()
        idx[[uid]][[kayit$key]] <- girdi
      } else {
        idx[[kayit$key]] <- girdi
      }
    }

    idx
  })

  vapply(hazirlanan, function(e) e$display, character(1))
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
  key_name <- basename(filename)

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    key_name <- normalize_text_utf8(key_name, repair_mojibake = TRUE)
  } else {
    key_name <- enc2utf8(key_name)
  }

  key <- tolower(key_name)

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