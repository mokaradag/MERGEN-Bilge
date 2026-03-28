# R/config_version_history.R
# Dosya Yolu: R/config_version_history.R
# Açıklama: Sürüm geçmişi verilerini version_history.md dosyasından okur ve ayrıştırır.
# Yeni sürüm eklemek için sadece version_history.md dosyasını güncellemek yeterlidir.

#' Markdown Dosyasından Sürüm Geçmişini Ayrıştır
#'
#' @description version_history.md dosyasını okur ve yapılandırılmış listeye dönüştürür.
#' @return Sürüm listesi: current_version ve versions içerir.
get_version_history <- function() {
  md_path <- file.path(getwd(), "version_history.md")

  if (!file.exists(md_path)) {
    warning("[VERSİYON] version_history.md dosyası bulunamadı: ", md_path)
    return(list(current_version = "0.0", versions = list()))
  }

  # Dosyayı bayt düzeyinde okuyup UTF-8'e zorla çevir.
  # Bu yaklaşım Windows + SSO oturumlarında Türkçe karakter kaybını engeller.
  read_version_lines <- function(path) {
    raw_size <- suppressWarnings(file.info(path)$size[1])
    if (is.na(raw_size) || raw_size <= 0) return(character(0))

    raw_content <- readBin(path, what = "raw", n = raw_size)

    decode_lines <- function(from) {
      txt <- tryCatch(
        iconv(list(raw_content), from = from, to = "UTF-8", sub = NA_character_)[[1]],
        error = function(e) NA_character_
      )

      if (is.na(txt) || !nzchar(txt)) return(NULL)

      txt <- sub("^\ufeff", "", txt, perl = TRUE)
      txt <- enc2utf8(txt)
      lines <- strsplit(txt, "\r\n|\n|\r", perl = TRUE)[[1]]
      enc2utf8(lines)
    }

    for (enc in c("UTF-8", "WINDOWS-1254", "CP1254", "latin1")) {
      lines <- decode_lines(enc)
      if (!is.null(lines) && length(lines) > 0) {
        return(lines)
      }
    }

    character(0)
  }

  lines <- read_version_lines(md_path)

  versions <- list()
  current_version <- NULL
  current_ver <- NULL
  current_section <- NULL
  section_icon <- NULL
  in_comment <- FALSE

  # Mevcut sürümü listeye ekle
  flush_version <- function() {
    if (!is.null(current_ver)) {
      versions[[length(versions) + 1]] <<- current_ver
    }
  }

  for (line in lines) {
    trimmed <- enc2utf8(trimws(line))

    # HTML yorum bloğu takibi
    if (grepl("<!--", trimmed)) {
      in_comment <- TRUE
      if (grepl("-->", trimmed)) {
        in_comment <- FALSE
      }
      next
    }

    if (in_comment) {
      if (grepl("-->", trimmed)) {
        in_comment <- FALSE
      }
      next
    }

    # Boş satırı atla
    if (nchar(trimmed) == 0) next

    # Sürüm ayracı
    if (trimmed == "---") {
      current_section <- NULL
      next
    }

    # Sürüm başlığı: ## v1.0 | 2026-03-07 | Başlık
    if (grepl("^## v", trimmed)) {
      flush_version()
      parts <- strsplit(sub("^## ", "", trimmed), "\\s*\\|\\s*")[[1]]
      ver_num <- sub("^v", "", trimws(parts[1]))
      ver_date <- if (length(parts) >= 2) trimws(parts[2]) else ""
      ver_title <- if (length(parts) >= 3) trimws(parts[3]) else ""

      if (is.null(current_version)) current_version <- ver_num

      current_ver <- list(
        id = paste0("v", gsub("\\.", "_", ver_num)),
        version = ver_num,
        date = ver_date,
        title = ver_title,
        badge = NULL,
        highlights = list(),
        details = list()
      )
      current_section <- NULL
      next
    }

    # Rozet satırı
    if (grepl("^badge:", trimmed) && !is.null(current_ver)) {
      badge_val <- trimws(sub("^badge:\\s*", "", trimmed))
      if (nzchar(badge_val) && badge_val != "NULL") {
        current_ver$badge <- badge_val
      }
      next
    }

    # Bölüm başlığı
    if (grepl("^### ", trimmed) && !is.null(current_ver)) {
      section_text <- sub("^### ", "", trimmed)
      section_parts <- strsplit(section_text, "\\s*\\|\\s*")[[1]]
      section_name <- trimws(section_parts[1])

      if (grepl("^Öne Çıkanlar", section_name, ignore.case = TRUE)) {
        current_section <- "highlights"
      } else {
        current_section <- "detail"
        section_icon <- if (length(section_parts) >= 2) trimws(section_parts[2]) else "circle"
        current_ver$details[[length(current_ver$details) + 1]] <- list(
          category = section_name,
          icon = section_icon,
          items = list()
        )
      }
      next
    }

    # Madde satırı
    if (grepl("^- ", trimmed) && !is.null(current_ver) && !is.null(current_section)) {
      item_text <- sub("^- ", "", trimmed)

      if (current_section == "highlights") {
        current_ver$highlights[[length(current_ver$highlights) + 1]] <- item_text
      } else if (current_section == "detail" && length(current_ver$details) > 0) {
        detail_idx <- length(current_ver$details)
        current_ver$details[[detail_idx]]$items[[
          length(current_ver$details[[detail_idx]]$items) + 1
        ]] <- item_text
      }
    }
  }

  # Son sürümü ekle
  flush_version()

  list(
    current_version = current_version %||% "0.0",
    versions = versions
  )
}

#' Mevcut Sürüm Numarasını Getir
#' @return Karakter türünde sürüm numarası
get_current_version <- function() {
  get_version_history()$current_version
}