# R/helpers_files.R

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

  base <- Sys.getenv("MCP_FILES_BASE")
  if (!nzchar(base)) {
    base <- getOption(
      "mergen.mcp_base_dir",
      default = normalizePath(file.path(getwd(), "mergen_uploads"), winslash = "/", mustWork = FALSE)
    )
  }
  
  # Use safe local normalization
  base <- safe_norm(base)
  fs::dir_create(base, recurse = TRUE)

  # Skip re-copy if already under base
  src_norm  <- safe_norm(upload$datapath)
  base_norm <- base # already normalized

  if (startsWith(normalize_for_path_compare(src_norm), paste0(normalize_for_path_compare(base_norm), "/"))) {
    cat("[copy_to_mcp_base] Skipped re-copy; already under MCP base:", src_norm, "\n")
    return(src_norm)
  }

  # per-user bucket
  user_dir <- fs::path(base, sprintf("user_%s", as.character(user_id)))
  fs::dir_create(user_dir, recurse = TRUE)

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

  fs::file_copy(upload$datapath, dest, overwrite = TRUE)
  if (!fs::file_exists(dest)) {
    stop(sprintf("Kopyalanamadı: %s -> %s (dosya oluşmadı)", upload$datapath, dest))
  }
  normalize_mcp_path(dest, must_exist = TRUE)
}

# Is path under MCP base?
is_under_mcp_base <- function(p) {
  base <- Sys.getenv("MCP_FILES_BASE")
  if (!nzchar(base)) base <- getOption("mergen.mcp_base_dir", "")
  if (!nzchar(base)) return(FALSE)
  
  safe_norm <- function(x) {
     x <- gsub("\\\\", "/", x)
     if (.Platform$OS.type == "windows" && grepl("^/[^/]", x)) x <- paste0("/", x)
     x
  }
  
  np <- safe_norm(p)
  nb <- safe_norm(base)
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