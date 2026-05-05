# ==============================================================================
# Dosya Yolu: R/helpers_files.R
# Açıklama: Dosya içeriklerini okuma, yüklenen dosyaları MCP kalıcı alanına
#            kopyalama ve kısa önizleme metinleri üretme yardımcıları.
#            Yol/UNC/karşılaştırma yardımcıları R/helpers_files_path.R içinde tutulur.
# ==============================================================================

# Yüklenen dosyayı kullanıcıya özel MCP temel dizinine kopyalar ve normalize edilmiş yolu döndürür.
copy_to_mcp_base <- function(upload, user_id) {
  # Genel yol normalizasyonunda oluşabilecek çiftleme sorunlarını önlemek için yerel güvenli normalleştirici.
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
      # normalizePath ile encoding'i düzelt.
      base <- tryCatch(
        normalizePath(raw_env, winslash = "/", mustWork = FALSE),
        error = function(e) raw_env
      )
    }
  }
  if (!nzchar(base)) {
    base <- normalizePath(file.path(getwd(), "mergen_uploads"), winslash = "/", mustWork = FALSE)
  }

  # Yerel güvenli normalizasyonu uygula.
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

  # Dosya zaten MCP temel dizini altındaysa yeniden kopyalama.
  src_norm  <- safe_norm(upload$datapath)
  base_norm <- base # Zaten normalize edilmiş temel dizin.

  if (startsWith(normalize_for_path_compare(src_norm), paste0(normalize_for_path_compare(base_norm), "/"))) {
    cat("[copy_to_mcp_base] Skipped re-copy; already under MCP base:", src_norm, "\n")
    return(src_norm)
  }

  # Kullanıcıya özel dosya kovası/dizini.
  user_dir <- fs::path(base, sprintf("user_%s", as.character(user_id)))
  tryCatch(
    fs::dir_create(user_dir, recurse = TRUE),
    error = function(e) {
      # fs başarısız olursa base R ile dene.
      cat(sprintf("[copy_to_mcp_base] fs::dir_create başarısız: %s - base::dir.create deneniyor\n", conditionMessage(e)))
      dir.create(as.character(user_dir), showWarnings = TRUE, recursive = TRUE)
    }
  )

  # Dizin gerçekten var mı kontrol et.
  if (!dir.exists(as.character(user_dir)) && !path_exists_relaxed(user_dir)) {
    cat(sprintf("[copy_to_mcp_base] HATA: Kullanıcı dizini oluşturulamadı: %s\n", user_dir))
    cat(sprintf("[copy_to_mcp_base]   base encoding: %s, Encoding()=%s\n",
                base, Encoding(base)))
    stop(sprintf("Kullanıcı dizini oluşturulamadı: %s", user_dir))
  }

  ext <- tools::file_ext(upload$name)
  unique_tag <- digest::digest(file = upload$datapath, algo = "xxhash64")

  safe_display_name <- basename(upload$name %||% "")
  safe_display_name <- gsub("[/\\\\]+", "_", safe_display_name)
  safe_display_name <- gsub("[[:cntrl:]]+", "_", safe_display_name)
  safe_display_name <- trimws(safe_display_name)

  if (!nzchar(safe_display_name)) {
    safe_display_name <- if (nzchar(ext)) paste0("dosya.", ext) else "dosya"
  }

  timestamp_tag <- gsub("[^0-9]", "", format(Sys.time(), "%Y%m%d%H%M%OS3"))

  dest <- NULL
  for (attempt in seq_len(20L)) {
    unique_stub <- basename(tempfile(
      pattern = paste0(timestamp_tag, "_", unique_tag, "_"),
      tmpdir = as.character(user_dir)
    ))

    candidate_dest <- fs::path(
      user_dir,
      paste0(unique_stub, "_", safe_display_name)
    )

    if (!path_exists_relaxed(candidate_dest)) {
      dest <- candidate_dest
      break
    }
  }

  if (is.null(dest) || !nzchar(as.character(dest))) {
    stop("Benzersiz hedef dosya adı üretilemedi.", call. = FALSE)
  }

  # Önce fs::file_copy dene, başarısız olursa base::file.copy ile yedek deneme yap.
  copy_success <- tryCatch({
    fs::file_copy(upload$datapath, dest, overwrite = TRUE)
    TRUE
  }, error = function(e) {
    cat(sprintf("[copy_to_mcp_base] fs::file_copy başarısız: %s\n", conditionMessage(e)))
    FALSE
  })

  if (!copy_success || !tryCatch(fs::file_exists(dest), error = function(e) FALSE)) {
    # base::file.copy ile yedek deneme yap; farklı encoding davranışı bazı ortamlarda işe yarayabilir.
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
    # Son çare: locale farklarından kaynaklı sorunlar için enc2native ile dene.
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

  if (.Platform$OS.type == "windows" && grepl("^/[^/]", dest_chr)) {
    dest_unc <- paste0("/", dest_chr)
    if (path_exists_relaxed(dest_unc)) {
      dest_chr <- dest_unc
    }
  }

  dest_readable <- tryCatch(
    resolve_readable_path(dest_chr),
    error = function(e) dest_chr
  )

  if (path_exists_relaxed(dest_readable)) {
    return(gsub("\\\\", "/", as.character(dest_readable), fixed = TRUE))
  }

  safe_windows_short_path(dest_readable, must_exist = TRUE)
}

# is_under_mcp_base() R/helpers_files_path.R içinde tanımlıdır.

# Bir data.frame nesnesini hızlı önizleme amacıyla basit CSV markdown metnine dönüştürür.
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

# Bir dosyanın içeriğini metin olarak okur; Excel dosyaları için kompakt profil özeti üretir.
readFileContentToString <- function(file_info) {
  tryCatch({
    if (!path_exists_relaxed(file_info$datapath)) return("Hata: Dosya bulunamadı.")

    # UNC yollarını base R fonksiyonlarının açabileceği formata çevir.
    file_info$datapath <- resolve_readable_path(file_info$datapath)

    file_ext  <- tolower(tools::file_ext(file_info$name))
    file_size <- file.info(file_info$datapath)$size

    content <- switch(file_ext,
      "txt" = , "csv" = , "json" = , "r" = , "py" = , "md" = , "log" = {
        if (file_size > 1024 * 1024) {  # 1 MB üzerindeki dosyalar kısaltılarak okunur.
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