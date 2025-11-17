# R/helpers_files.R

# Copy an upload to MCP base (per-user) and return normalized path
copy_to_mcp_base <- function(upload, user_id) {
  base <- Sys.getenv("MCP_FILES_BASE")
  if (!nzchar(base)) {
    base <- getOption(
      "mergen.mcp_base_dir",
      default = normalizePath(file.path(getwd(), "mergen_uploads"), winslash = "/", mustWork = FALSE)
    )
  }
  base <- safe_windows_short_path(base, must_exist = dir.exists(base))
  fs::dir_create(base, recurse = TRUE)

  # Work with a short/ASCII-safe source path whenever possible
  src_original <- upload$datapath
  src_short <- safe_windows_short_path(src_original, must_exist = file.exists(src_original))
  if (!isTRUE(file.exists(src_short)) && isTRUE(file.exists(src_original))) {
    src_short <- src_original
  }
  
  # Skip re-copy if already under base
  src_norm  <- tryCatch(normalizePath(src_short, winslash = "/", mustWork = FALSE), error = function(e) src_short)
  base_norm <- tryCatch(normalizePath(base,          winslash = "/", mustWork = FALSE), error = function(e) base)
  if (startsWith(tolower(src_norm), tolower(paste0(base_norm, "/")))) {
    cat("[copy_to_mcp_base] Skipped re-copy; already under MCP base:", src_norm, "\n")
    return(safe_windows_short_path(src_norm, must_exist = file.exists(src_norm)))
  }

  # per-user bucket
  user_dir <- fs::path(base, sprintf("user_%s", as.character(user_id)))
  fs::dir_create(user_dir, recurse = TRUE)

  ext <- tools::file_ext(upload$name)
  unique_tag <- if (file.exists(src_short)) {
    digest::digest(file = src_short, algo = "xxhash64")
  } else {
    # Rarely, the temporary upload might already be gone (e.g. aggressive AV or
    # short-lived network share).  Fall back to a time/random-based hash to
    # avoid crashing the upload flow.
    cat(
      "[copy_to_mcp_base] Kaynak dosya bulunamadı, rastgele etiket kullanılıyor:",
      src_short, "\n"
    )
    digest::digest(paste(upload$name, Sys.time(), runif(1)), algo = "xxhash64")
  }

  dest <- fs::path(
    user_dir,
    sprintf(
      "%s_%s%s",
      format(Sys.time(), "%Y%m%d-%H%M%S"),
      unique_tag,
      if (nzchar(ext)) paste0(".", ext) else ""
    )
  )

  fs::file_copy(upload$datapath, dest, overwrite = TRUE)
  if (!fs::file_exists(dest)) {
    stop(sprintf("Kopyalanamadı: %s -> %s (dosya oluşmadı)", upload$datapath, dest))
  }
  dest_norm <- normalizePath(dest, winslash = "/", mustWork = TRUE)
  safe_windows_short_path(dest_norm, must_exist = TRUE)
}

# Is path under MCP base?
is_under_mcp_base <- function(p) {
  base <- Sys.getenv("MCP_FILES_BASE")
  if (!nzchar(base)) base <- getOption("mergen.mcp_base_dir", "")
  if (!nzchar(base)) return(FALSE)
  np <- tryCatch(normalizePath(p, winslash = "/", mustWork = FALSE), error = function(e) p)
  nb <- tryCatch(normalizePath(base, winslash = "/", mustWork = FALSE), error = function(e) base)
  startsWith(tolower(np), tolower(paste0(nb, "/"))) || tolower(np) == tolower(nb)
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
    if (!file.exists(file_info$datapath)) return("Hata: Dosya bulunamadı.")

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