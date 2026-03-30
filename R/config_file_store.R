# ==============================================================================
# R/config_file_store.R
# Dosya deposu altyapısı: kalıcı yükleme dizinleri, indeks yönetimi,
# dosya kayıt/çözümleme fonksiyonları, ortam değişkeni doğrulama,
# bellek yönetimi ve çöp toplama zamanlayıcısı.
# global.R tarafından utils_path_helpers.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- ORTAM DEĞİŞKENLERİ AES-GCM VE OPSİYONEL VİZ KÜTÜPHANELERİ ---
# Ortamda AES-GCM var mı? Eski openssl sürümlerinde bu fonksiyon yoktur.
HAVE_AES_GCM <- isTRUE("aes_gcm_encrypt" %in% getNamespaceExports("openssl"))

# Opsiyonel görselleştirme kütüphaneleri (yoksa hata verme)
have_highcharter <- requireNamespace("highcharter", quietly = TRUE)
have_plotly_gg   <- (requireNamespace("plotly", quietly = TRUE) &&
                     requireNamespace("ggplot2", quietly = TRUE))

# ==============================================================================
# PAYLAŞIMLI DOSYA DEPOSU (ana süreç + worker'lar için ortak)
# ==============================================================================
MERGEN_FILES_ROOT <- tools::R_user_dir("mergen", which = "data")
dir.create(MERGEN_FILES_ROOT, showWarnings = FALSE, recursive = TRUE)
MERGEN_FILES_ROOT <- normalize_utf8_path(MERGEN_FILES_ROOT,
                                         mustWork = dir.exists(MERGEN_FILES_ROOT))

# Kalıcı yüklemeler dizini: ./mergen_uploads (MCP_FILES_BASE ile geçersiz kılınabilir)
MERGEN_UPLOADS_DIR <- file.path(getwd(), "mergen_uploads")
dir.create(MERGEN_UPLOADS_DIR, showWarnings = FALSE, recursive = TRUE)
MERGEN_UPLOADS_DIR <- normalize_utf8_path(MERGEN_UPLOADS_DIR,
                                          mustWork = dir.exists(MERGEN_UPLOADS_DIR))

# MCP tabanlı kalıcı yüklemeler için temel dizin
MERGEN_MCP_BASE_DIR <- resolve_mcp_base_dir()

# Kayıt defteri (indeks) dosya yolu; kullanıcı bazlı kovalar destekler
MERGEN_INDEX_PATH <- file.path(MERGEN_FILES_ROOT, "index.json")

# --- İNDEKS YARDIMCILARI (ana süreç ve worker'lar tarafından kullanılır) ---

# JSON'dan okunan dizeleri UTF-8 olarak İŞARETLEYEN özyinelemeli yardımcı.
# ÖNEMLİ: enc2utf8() yerine Encoding()<-"UTF-8" kullanılır.
# JSON zaten UTF-8'dir; enc2utf8() baytları yeniden dönüştürerek çift kodlamaya neden olur,
# Encoding()<-"UTF-8" ise mevcut baytları olduğu gibi koruyup sadece işaretler.
.mark_utf8 <- function(x) {
  if (is.character(x)) { Encoding(x) <- "UTF-8"; return(x) }
  if (is.list(x)) return(lapply(x, .mark_utf8))
  x
}

# Kaydetmeden önce native encoding dizeleri UTF-8'e çeviren yardımcı
.convert_to_utf8 <- function(x) {
  if (is.character(x)) return(enc2utf8(x))
  if (is.list(x)) return(lapply(x, .convert_to_utf8))
  x
}

.save_index <- function(idx) {
  # Native encoding (ör. CP1254) baytlarını UTF-8'e çevir, yoksa JSON bozulur
  idx <- .convert_to_utf8(idx)
  jsonlite::write_json(idx, MERGEN_INDEX_PATH, auto_unbox = TRUE, pretty = TRUE)
}

.load_index <- function() {
  if (file.exists(MERGEN_INDEX_PATH)) {
    idx <- jsonlite::read_json(MERGEN_INDEX_PATH, simplifyVector = TRUE)
    # JSON dosyası UTF-8'dir; R bazen native encoding olarak işaretler, UTF-8 olarak düzelt
    .mark_utf8(idx)
  } else {
    list()
  }
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

  # Var olan geçerli yolu mümkün olduğunca olduğu gibi koru.
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

  # Karşılaştırma için yol normalizasyonu (küçük harf, ayırıcı düzeltmesi)
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

  # Kaynak zaten kullanıcı kovası altındaysa ikinci kez fiziksel kopya alma, sadece indeksle
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

    # Dosya oluştuysa yolu olduğu gibi koru; yeniden normalizasyon Türkçe karakteri bozabiliyor.
    dest_norm <- gsub("\\\\", "/", as.character(dest), fixed = TRUE)
    if (!path_exists_relaxed(dest_norm)) {
      dest_norm <- normalize_mcp_path(dest_norm, must_exist = TRUE)
    } else {
      dest_norm <- enc2utf8(dest_norm)
    }
  }

  # İndekse kaydet (geriye uyumlu: path + display)
  idx <- .load_index()
  key <- tolower(basename(as_name))
  entry <- list(path = enc2utf8(dest_norm), display = enc2utf8(basename(as_name)))

  if (!is.null(user_id)) {
    uid <- as.character(user_id)
    if (is.null(idx[[uid]])) idx[[uid]] <- list()
    idx[[uid]][[key]] <- entry
  } else {
    idx[[key]] <- entry
  }

  .save_index(idx)
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

# ==============================================================================
# DOSYA ÇÖZÜMLEME FONKSİYONU
# Dosya adını (veya yolunu) mevcut bir mutlak yola çözümler.
# Kullanıcı kovasını önceliklendirir.
# ==============================================================================
resolve_uploaded_file <- function(requested, user_id = NULL) {
  # Günlük: gelen parametreleri yaz
  log_debug("resolve_uploaded_file(): requested='{requested}', user_id='{user_id}'")
  if (is.null(requested) || !(is.character(requested) && length(requested) > 0 && nzchar(requested[1]))) return(NULL)

  if (path_exists_relaxed(requested[1])) {
    p <- tryCatch(normalize_mcp_path(requested[1], must_exist = TRUE),
                 error = function(e) normalizePath(requested[1], winslash = "/", mustWork = TRUE))
    log_info("resolve_uploaded_file(): doğrudan mevcut dosya bulundu -> {p}")
    return(p)
  }

  # Not: önce TAM adla (display) ara, sonra basename'e düş
  full_key <- tolower(as.character(requested))
  key      <- tolower(basename(requested))
  idx <- .load_index()
  log_debug("resolve_uploaded_file(): full='{full_key}', anahtar='{key}', index kovası sayısı={length(idx)}")

  # 1) Kullanıcı kovası
  if (!is.null(user_id)) {
    uid <- as.character(user_id)
    if (!is.null(idx[[uid]])) {
      bucket <- idx[[uid]]

      # Önce display eşleşmesi (tam ad)
      if (is.list(bucket) && length(bucket)) {
        for (nm in names(bucket)) {
          ent <- bucket[[nm]]
          ent_path <- if (is.list(ent) && !is.null(ent$path)) ent$path else as.character(ent)
          ent_disp <- if (is.list(ent) && !is.null(ent$display)) tolower(as.character(ent$display)) else tolower(nm)
          if (!is.null(ent_path) && path_exists_relaxed(ent_path) && identical(ent_disp, full_key)) {
            p <- normalize_mcp_path(ent_path, must_exist = FALSE)
            log_info("resolve_uploaded_file(): kullanıcı kovasında TAM adla bulundu -> {p}")
            return(p)
          }
        }
      }

      # Sonra basename anahtarı
      hit <- bucket[[key]]
      if (is.list(hit) && !is.null(hit$path)) hit <- hit$path  # yeni yapı
      if (!is.null(hit) && path_exists_relaxed(hit)) {
        p <- normalize_mcp_path(hit, must_exist = FALSE)
        log_info("resolve_uploaded_file(): kullanıcı kovasında basename ile bulundu -> {p}")
        return(p)
      } else {
        log_debug("resolve_uploaded_file(): kullanıcı kovasında eşleşme yok (display/basename)")
      }
    } else {
      log_debug("resolve_uploaded_file(): kullanıcı kovası yok: user_id='{uid}'")
    }
  }

  # 2) Legacy düz harita: önce display'e göre tara, sonra basename
  # (Not: düz haritada display tuttuğumuz yeni kayıtlar olabilir)
  if (length(idx)) {
    # Display'e göre tam ad araması
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

  # 3) Basename ile klasik aramalar (düz + çapraz)
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

  log_warn("resolve_uploaded_file(): '{requested}' için eşleşme bulunamadı")
  NULL
}

# ==============================================================================
# KULLANICI YÜKLEME DİZİNİ YARDIMCILARI
# ==============================================================================

# Kullanıcıya özel yükleme dizinini döndürür (yoksa oluşturur)
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

# Kullanıcının yüklediği dosyaların listesini döndürür
mergen_list_user_files <- function(user_id, prune_missing = TRUE) {
  idx <- .load_index()
  uid <- as.character(user_id)
  bucket <- idx[[uid]]
  
  drop_stale_entries <- function(keys_to_remove) {
    if (!length(keys_to_remove)) return(invisible(FALSE))
    idx_local <- .load_index()
    if (is.null(idx_local[[uid]])) return(invisible(FALSE))
    for (key in unique(keys_to_remove)) {
      idx_local[[uid]][[key]] <- NULL
    }
    if (is.list(idx_local[[uid]]) && !length(idx_local[[uid]])) {
      idx_local[[uid]] <- NULL
    }
    .save_index(idx_local)
    TRUE
  }

  if (!is.null(bucket) && length(bucket) > 0) {
    entries <- lapply(names(bucket), function(key) {
      val <- bucket[[key]]
      list(
        key = key,
        path = normalize_utf8_path(if (is.list(val) && !is.null(val$path)) val$path else as.character(val), mustWork = FALSE),
        name = {
          disp <- if (is.list(val) && !is.null(val$display)) val$display else NA_character_
          disp <- disp %||% NA_character_
          # .load_index() zaten .mark_utf8() ile işaretliyor; yine de güvenlik için enc2utf8
          if (!is.na(disp) && nzchar(disp)) enc2utf8(disp) else enc2utf8(key)
        }
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
          rehydrated[[df$key[i]]] <<- alt
          exists_now <- TRUE
          log_info("[INDEX] {df$name[i]} yolu yeniden oluşturuldu -> {alt}")
        }
      }

      exists_now
    }, logical(1))

    if (length(rehydrated)) {
      idx_local <- .load_index()
      if (!is.null(idx_local[[uid]])) {
        for (k in names(rehydrated)) {
          if (is.list(idx_local[[uid]][[k]])) {
            idx_local[[uid]][[k]]$path <- rehydrated[[k]]
          } else if (!is.null(idx_local[[uid]][[k]])) {
            idx_local[[uid]][[k]] <- rehydrated[[k]]
          }
        }
        .save_index(idx_local)
      }
    }

    if (prune_missing && any(!exists_vec)) {
      missing_keys <- unique(df$key[!exists_vec])
      missing_names <- unique(df$name[!exists_vec])
      log_warn("[INDEX] {length(missing_keys)} kayıt bulunamadı (user={uid}): {paste(missing_names, collapse = ', ')} \U2014 indeks temizleniyor")
      drop_stale_entries(missing_keys)
    }

    df <- df[exists_vec, , drop = FALSE]
    if (nrow(df) > 0) {
      out <- data.frame(
        path = df$path,
        name = df$name,
        stringsAsFactors = FALSE
      )
      attr(out, "source") <- "index"
      attr(out, "count") <- nrow(out)
      log_info("[INDEX] user={uid} için {nrow(out)} dosya bulundu (kaynak: index)")
      return(out)
    }
  }

  # Fallback: plain folder listing (pre-index or very old data)
  dir <- mergen_user_upload_dir(user_id)

  # UNC/encoding farkları nedeniyle dizin tespiti esnek yapılır
  dir_ok <- tryCatch(path_exists_relaxed(dir), error = function(e) dir.exists(dir))
  if (!isTRUE(dir_ok) && grepl("^/[^/]", dir)) {
    # Tek slash ile gelen UNC benzeri yolu çift slash varyantı ile de dene
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
  
  # Ağ paylaşımı/UNC varyasyonlarında dizin okunurluğunu farklı yollarla dene
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

  resolve_display_name_from_index <- function(file_path) {
    idx_all <- .load_index()
    target_path <- normalize_for_path_compare(file_path)
    target_base <- tolower(basename(file_path))

    for (bucket_name in names(idx_all)) {
      bucket <- idx_all[[bucket_name]]

      candidate_entries <- if (is.list(bucket) && (!is.null(bucket$path) || !is.null(bucket$display))) {
        list(bucket)
      } else if (is.list(bucket) && length(bucket) > 0) {
        unname(bucket)
      } else {
        list()
      }

      for (entry in candidate_entries) {
        entry_path <- if (is.list(entry) && !is.null(entry$path)) as.character(entry$path) else as.character(entry %||% "")
        entry_display <- if (is.list(entry) && !is.null(entry$display)) as.character(entry$display) else ""

        if (!nzchar(entry_path) || !nzchar(entry_display)) next

        same_path <- identical(normalize_for_path_compare(entry_path), target_path)
        same_file <- identical(tolower(basename(entry_path)), target_base)

        if (same_path || same_file) {
          return(enc2utf8(entry_display))
        }
      }
    }

    basename(file_path)
  }

  out <- data.frame(
    path = vapply(paths, normalize_utf8_path, character(1), mustWork = FALSE),
    name = vapply(paths, resolve_display_name_from_index, character(1)),
    stringsAsFactors = FALSE
  )
  
  attr(out, "source") <- "filesystem"
  attr(out, "count") <- nrow(out)
  log_info("[INDEX] user={uid} için {nrow(out)} dosya bulundu (kaynak: filesystem)")
  out
}

# İndeksten belirli bir dosyayı kaldırır
mergen_remove_from_index <- function(user_id, filename) {
  idx <- .load_index()
  uid <- as.character(user_id)
  key <- tolower(basename(filename))
  if (!is.null(idx[[uid]])) {
    idx[[uid]][[key]] <- NULL
    if (is.list(idx[[uid]]) && !length(idx[[uid]])) {
      idx[[uid]] <- NULL
    }
    .save_index(idx)
  }
  invisible(TRUE)
}

# Kullanıcının tüm dosyalarını ve indeks kovasını temizler
mergen_clear_user_bucket <- function(user_id) {
  uid <- as.character(user_id)
  user_folder_name <- sprintf("user_%s", uid)

  # Olası tüm dizin adaylarını topla (UNC, yerel, MCP)
  candidate_dirs <- unique(c(
    tryCatch(mergen_user_upload_dir(user_id), error = function(e) NULL),
    file.path(MERGEN_UPLOADS_DIR, user_folder_name),
    file.path(MERGEN_MCP_BASE_DIR, user_folder_name)
  ))
  candidate_dirs <- candidate_dirs[!vapply(candidate_dirs, is.null, logical(1))]

  # Her aday dizinde fiziksel dosyaları sil
  for (dir in candidate_dirs) {
    dir_ok <- tryCatch(dir.exists(dir), error = function(e) FALSE)
    if (!dir_ok) {
      # path_exists_relaxed ile de dene (UNC yolları için)
      dir_ok <- tryCatch(path_exists_relaxed(dir), error = function(e) FALSE)
    }
    if (isTRUE(dir_ok)) {
      files <- tryCatch(
        list.files(dir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE),
        error = function(e) character(0)
      )
      for (f in files) try(unlink(f, force = TRUE), silent = TRUE)
    }
  }

  # İndeks kovasını temizle
  idx <- .load_index()
  if (!is.null(idx[[uid]])) {
    idx[[uid]] <- NULL
    .save_index(idx)
  }
  invisible(TRUE)
}

# ==============================================================================
# GLOBAL SEÇENEKLERİN AYARLANMASI
# ==============================================================================
# Bu değişkenleri yardımcı modüllere de erişilebilir kıl
options(mergen.files_root   = MERGEN_FILES_ROOT,
        mergen.index_path   = MERGEN_INDEX_PATH,
        mergen.mcp_base_dir = MERGEN_MCP_BASE_DIR)

# Bellek yönetimi ayarları
options(
  shiny.maxRequestSize   = 30 * 1024^2,   # 30MB maks yükleme
  future.globals.maxSize = 200 * 1024^2    # 200MB future işlemleri için
)

# --- ÇÖP TOPLAMA ZAMANLAYICISI (hata korumalı) ---
gc_scheduler <- function() {
  tryCatch({
    gc(verbose = FALSE)
    later::later(gc_scheduler, delay = 300)  # Her 5 dakikada bir çalıştır
  }, error = function(e) {
    # Hata durumunda bile tekrar planla
    later::later(gc_scheduler, delay = 600)  # Hata sonrası 10 dakika bekle
  })
}
gc_scheduler()

# Veritabanı bağlantı havuzu (server.R'de başlatılır)
pool <- NULL

# ==============================================================================
# ZORUNLU ORTAM DEĞİŞKENLERİ DOĞRULAMASI
# ==============================================================================
required_env_vars <- c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")
missing_vars <- required_env_vars[sapply(required_env_vars, function(v) !nzchar(Sys.getenv(v)))]

if (length(missing_vars) > 0) {
  stop(sprintf(
    "Eksik zorunlu ortam değişkenleri: %s\n\n.Renviron dosyasında yapılandırın:\n%s",
    paste(missing_vars, collapse = ", "),
    paste(sprintf("%s=deger_buraya", missing_vars), collapse = "\n")
  ))
}

message("\u2713 Tüm zorunlu ortam değişkenleri yapılandırılmış")