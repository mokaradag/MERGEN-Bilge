# R/helpers_files.R

# UNC yolunu base R fonksiyonları (file(), readBin, pdftools vb.) için okunabilir formata çevirir.
# path_exists_relaxed() dosyanın varlığını doğrular ancak base R'ın açamayacağı bir yol döndürebilir.
# Bu fonksiyon file.exists() ile gerçekten açılabilecek varyantı bulur.
resolve_readable_path <- function(path) {
  if (is.null(path) || !nzchar(path)) return(path)
  p <- as.character(path[1])
  # Zaten base R ile çalışıyorsa dokunma
  if (tryCatch(isTRUE(file.exists(p)), error = function(e) FALSE)) return(p)
  # UNC forward slash -> backslash dene (\\server\share formatı)
  p_bs <- gsub("/", "\\\\", p, fixed = TRUE)
  if (tryCatch(isTRUE(file.exists(p_bs)), error = function(e) FALSE)) return(p_bs)
  # Tek slash başlangıcını çift slash ile dene
  p_fwd <- gsub("\\\\", "/", p, fixed = TRUE)
  if (grepl("^/[^/]", p_fwd)) {
    p_unc <- paste0("/", p_fwd)
    if (tryCatch(isTRUE(file.exists(p_unc)), error = function(e) FALSE)) return(p_unc)
    p_unc_bs <- gsub("/", "\\\\", p_unc, fixed = TRUE)
    if (tryCatch(isTRUE(file.exists(p_unc_bs)), error = function(e) FALSE)) return(p_unc_bs)
  }
  p
}

# Relaxed file.exists for UNC + long paths + Encoding variants
path_exists_relaxed <- function(path) {
  if (is.null(path) || length(path) == 0) return(FALSE)

  candidate <- as.character(path[1])
  if (!nzchar(candidate)) return(FALSE)

  # Generate variants: Slashes, Backslashes, UNC
  cand_slash <- gsub("\\\\", "/", candidate, fixed = TRUE)
  
  variants <- unique(trimws(Filter(nzchar, c(
    candidate,
    cand_slash,
    # UNC repairs
    sub("^//\\?/UNC", "//", cand_slash, perl = TRUE),
    sub("^//\\?/", "//", cand_slash, perl = TRUE),
    # Fix missing leading slash for UNC (common R issue on Windows)
    if (grepl("^/[^/]", cand_slash)) paste0("/", cand_slash) else NULL,
    gsub("/", "\\\\", cand_slash, fixed = TRUE)
  ))))

  for (chk in variants) {
    # 1. Check as is
    if (tryCatch(isTRUE(file.exists(chk)), error=function(e) FALSE)) return(TRUE)
    if (tryCatch(isTRUE(fs::file_exists(chk)), error=function(e) FALSE)) return(TRUE)
    
    # 2. Check UTF-8 encoded (for Turkish chars)
    chk_utf8 <- tryCatch(enc2utf8(chk), error=function(e) chk)
    if (tryCatch(isTRUE(file.exists(chk_utf8)), error=function(e) FALSE)) return(TRUE)
    if (tryCatch(isTRUE(fs::file_exists(chk_utf8)), error=function(e) FALSE)) return(TRUE)
  }

  FALSE
}

normalize_for_path_compare <- function(path) {
  if (is.null(path) || length(path) == 0) {
    return("")
  }

  candidate <- as.character(path[1])
  if (!nzchar(candidate)) {
    return("")
  }

  cleaned <- gsub("\\\\", "/", candidate, fixed = TRUE)
  cleaned <- sub("^//\\?/UNC", "//", cleaned, perl = TRUE)
  cleaned <- sub("^//\\?/", "//", cleaned, perl = TRUE)
  cleaned <- sub("^//(?=[A-Za-z]:)", "", cleaned, perl = TRUE)
  cleaned <- gsub("(?<!:)//+", "/", cleaned, perl = TRUE)
  cleaned <- trimws(cleaned)
  tolower(cleaned)
}

# Copy an upload to MCP base (per-user) and return normalized path
copy_to_mcp_base <- function(upload, user_id) {
  # Local safe normalizer to avoid global path doubling issues
  safe_norm <- function(p) {
     if (is.null(p) || !nzchar(p)) return("")
     p <- gsub("\\\\", "/", p)
     if (.Platform$OS.type == "windows" && grepl("^/[^/]", p)) p <- paste0("/", p)
     p
  }

  # KRİTİK: Önce config_file_store.R'de normalizePath() ile çözümlenen
  # seçeneği kullan (Türkçe karakter encoding'i doğru). Sys.getenv() ham
  # baytlar döndürerek Windows'ta dosya yolunu bozabiliyor
  # (Geliştirme -> GeliAYtirme gibi).
  base <- getOption("mergen.mcp_base_dir", "")
  if (!nzchar(base)) {
    raw_env <- Sys.getenv("MCP_FILES_BASE", "")
    if (nzchar(raw_env)) {
      # normalizePath ile encoding'i düzelt
      base <- tryCatch(
        normalizePath(raw_env, winslash = "/", mustWork = FALSE),
        error = function(e) raw_env
      )
    }
  }
  if (!nzchar(base)) {
    # normalizePath() Windows UNC yollarında Türkçe karakterleri bozar;
    # config_file_store.R'de güvenli şekilde başlatılan MERGEN_UPLOADS_DIR kullanılır.
    base <- MERGEN_UPLOADS_DIR
  }

  # Use safe local normalization
  base <- safe_norm(base)

  cat(sprintf("[copy_to_mcp_base] user_id=%s, kaynak=%s, hedef_base=%s\n",
              as.character(user_id), upload$datapath, base))

  tryCatch(
    fs::dir_create(base, recurse = TRUE),
    error = function(e) {
      cat(sprintf("[copy_to_mcp_base] fs::dir_create(base) başarısız: %s - base R deneniyor\n", conditionMessage(e)))
      dir.create(base, showWarnings = TRUE, recursive = TRUE)
    }
  )

  # Skip re-copy if already under base
  src_norm  <- safe_norm(upload$datapath)
  base_norm <- base # already normalized

  if (startsWith(normalize_for_path_compare(src_norm), paste0(normalize_for_path_compare(base_norm), "/"))) {
    cat("[copy_to_mcp_base] Skipped re-copy; already under MCP base:", src_norm, "\n")
    return(src_norm)
  }

  # per-user bucket
  user_dir <- fs::path(base, sprintf("user_%s", as.character(user_id)))
  tryCatch(
    fs::dir_create(user_dir, recurse = TRUE),
    error = function(e) {
      # fs başarısız olursa base R ile dene
      cat(sprintf("[copy_to_mcp_base] fs::dir_create başarısız: %s - base::dir.create deneniyor\n", conditionMessage(e)))
      dir.create(as.character(user_dir), showWarnings = TRUE, recursive = TRUE)
    }
  )

  # Dizin gerçekten var mı kontrol et
  if (!dir.exists(as.character(user_dir)) && !path_exists_relaxed(user_dir)) {
    cat(sprintf("[copy_to_mcp_base] HATA: Kullanıcı dizini oluşturulamadı: %s\n", user_dir))
    cat(sprintf("[copy_to_mcp_base]   base encoding: %s, Encoding()=%s\n",
                base, Encoding(base)))
    stop(sprintf("Kullanıcı dizini oluşturulamadı: %s", user_dir))
  }

  ext <- tools::file_ext(upload$name)
  unique_tag <- digest::digest(file = upload$datapath, algo = "xxhash64")

  dest <- fs::path(
    user_dir,
    sprintf(
      "%s_%s%s",
      format(Sys.time(), "%Y%m%d-%H%M%S"),
      unique_tag,
      if (nzchar(ext)) paste0(".", ext) else ""
    )
  )

  # Önce fs::file_copy dene, başarısız olursa base::file.copy ile yedek
  copy_success <- tryCatch({
    fs::file_copy(upload$datapath, dest, overwrite = TRUE)
    TRUE
  }, error = function(e) {
    cat(sprintf("[copy_to_mcp_base] fs::file_copy başarısız: %s\n", conditionMessage(e)))
    FALSE
  })

  if (!copy_success || !tryCatch(fs::file_exists(dest), error = function(e) FALSE)) {
    # base::file.copy ile yedek deneme (farklı encoding davranışı olabilir)
    cat(sprintf("[copy_to_mcp_base] Yedek yol: base::file.copy deneniyor: %s -> %s\n",
                upload$datapath, dest))
    copy_success <- tryCatch({
      file.copy(upload$datapath, as.character(dest), overwrite = TRUE)
    }, error = function(e) {
      cat(sprintf("[copy_to_mcp_base] base::file.copy de başarısız: %s\n", conditionMessage(e)))
      FALSE
    })
  }

  # Boyut doğrulaması: dosya gerçekten yazıldı mı?
  dest_exists <- path_exists_relaxed(dest)
  if (!dest_exists) {
    # Son çare: enc2native ile dene (locale farklıysa)
    dest_native <- tryCatch(enc2native(as.character(dest)), error = function(e) as.character(dest))
    if (!identical(dest_native, as.character(dest))) {
      cat(sprintf("[copy_to_mcp_base] Native encoding ile yeniden deneniyor: %s\n", dest_native))
      tryCatch(file.copy(upload$datapath, dest_native, overwrite = TRUE), error = function(e) NULL)
      dest_exists <- path_exists_relaxed(dest_native) || path_exists_relaxed(dest)
    }
  }

  if (!dest_exists) {
    stop(sprintf("Kopyalanamadı: %s -> %s (dosya oluşmadı, fs=%s, base=%s)",
                 upload$datapath, dest, as.character(copy_success), as.character(dest_exists)))
  }

  src_size <- suppressWarnings(file.info(upload$datapath)$size)
  dest_size <- suppressWarnings(file.info(as.character(dest))$size)
  if (!is.na(src_size) && !is.na(dest_size) && dest_size != src_size) {
    cat(sprintf("[copy_to_mcp_base] UYARI: Boyut uyuşmazlığı! kaynak=%d, hedef=%d\n", src_size, dest_size))
  }

  # Dosya gerçekten oluştuysa yolu olduğu gibi koru.
  # Burada enc2utf8 uygulamak UNC + Türkçe karakterli yollarda
  # Geliştirme -> GeliÅŸtirme gibi bozulmaya yol açabiliyor.
  dest_chr <- gsub("\\\\", "/", as.character(dest), fixed = TRUE)
  if (path_exists_relaxed(dest_chr)) {
    return(dest_chr)
  }

  safe_windows_short_path(dest_chr, must_exist = TRUE)
}

# Is path under MCP base?
is_under_mcp_base <- function(p) {
  # Önce doğru encoding'li seçeneği kullan (config_file_store.R'den)
  base <- getOption("mergen.mcp_base_dir", "")
  if (!nzchar(base)) base <- Sys.getenv("MCP_FILES_BASE")
  if (!nzchar(base)) return(FALSE)

  safe_norm <- function(x) {
    x <- gsub("\\\\", "/", x)
    if (.Platform$OS.type == "windows" && grepl("^/[^/]", x)) x <- paste0("/", x)
    enc2utf8(x)
  }

  np <- safe_norm(p)
  nb <- safe_norm(base)

  if (!nzchar(np) || !nzchar(nb)) return(FALSE)

  # Türkçe karakter bozulsa bile son klasör segmentleri ASCII kaldığı için
  # önce bunlar üzerinden hızlı ve güvenli tespit yap.
  np_parent <- tryCatch(basename(dirname(np)), error = function(e) "")
  np_grand  <- tryCatch(basename(dirname(dirname(np))), error = function(e) "")
  nb_base   <- tryCatch(basename(nb), error = function(e) "")

  if (
    grepl("^user_[0-9]+$", tolower(np_parent)) &&
    nzchar(np_grand) &&
    nzchar(nb_base) &&
    identical(tolower(np_grand), tolower(nb_base))
  ) {
    return(TRUE)
  }

  startsWith(normalize_for_path_compare(np), paste0(normalize_for_path_compare(nb), "/")) ||
    normalize_for_path_compare(np) == normalize_for_path_compare(nb)
}

# Turn a data.frame into simple CSV markdown (used for quick previews)
dataframeToMarkdown <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return("Excel dosyası boş veya okunamadı.")
  }

  tryCatch({
    temp_file <- tempfile(fileext = ".csv")
    data.table::fwrite(df, temp_file, bom = TRUE)
    paste(readLines(temp_file, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  }, error = function(e) {
    "Excel dosyası metne dönüştürülürken bir hata oluştu."
  })
}

# Read a file to string (including compact Excel digest)
readFileContentToString <- function(file_info) {
  tryCatch({
    if (!path_exists_relaxed(file_info$datapath)) return("Hata: Dosya bulunamadı.")

    # UNC yollarını base R fonksiyonlarının açabileceği formata çevir
    file_info$datapath <- resolve_readable_path(file_info$datapath)

    file_ext  <- tolower(tools::file_ext(file_info$name))
    file_size <- file.info(file_info$datapath)$size

    content <- switch(file_ext,
      "txt" = , "csv" = , "json" = , "r" = , "py" = , "md" = , "log" = {
        if (file_size > 1024 * 1024) {  # >1MB
          con <- file(file_info$datapath, "r", encoding = "UTF-8")
          on.exit(close(con))
          content <- readChar(con, min(50000, file_size))
          if (file_size > 50000) {
            content <- paste0(content, "\n... [Dosya kısaltıldı, ilk 50KB gösteriliyor]")
          }
          content
        } else {
          paste(readLines(file_info$datapath, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        }
      },
      "pdf" = {
        paste(pdftools::pdf_text(file_info$datapath), collapse = "\n\n--- Sayfa Sonu ---\n\n")
      },
      "docx" = {
        doc_xml  <- xml2::read_xml(unz(file_info$datapath, "word/document.xml"))
        xml_text <- xml2::xml_text(xml2::xml_find_all(doc_xml, ".//w:t"))
        paste(xml_text, collapse = " ")
      },
      "xlsx" = , "xls" = {
        digest_json   <- build_excel_digest_json(file_info$datapath, top_levels = 12)
        digest_trimmed <- substr(digest_json, 1, 50000)
        paste0(
          "Excel Dosyası: ", file_info$name, "\n",
          "ÖZET (profil JSON):\n",
          digest_trimmed
        )
      },
      paste("Hata: '", file_ext, "' dosya türünün içeriği okunamadı.", sep = "")
    )

    content
  }, error = function(e) {
    paste("Dosya okunurken bir hata oluştu:", e$message)
  })
}