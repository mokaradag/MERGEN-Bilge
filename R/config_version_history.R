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
  lines <- if (exists("read_text_lines_utf8", mode = "function", inherits = TRUE)) {
    read_text_lines_utf8(
      md_path,
      encodings = c("UTF-8", "WINDOWS-1254", "CP1254", "latin1"),
      repair_mojibake = TRUE
    )
  } else {
    readLines(md_path, warn = FALSE, encoding = "UTF-8")
  }

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
    trimmed <- trimws(line)

    if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
      trimmed <- normalize_text_utf8(trimmed, repair_mojibake = TRUE)
    } else {
      trimmed <- enc2utf8(trimmed)
    }

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
#'
#' @description MERGEN Bilge uygulamasının görünür sürüm numarasının
#'   TEK doğru kaynağıdır. Tüm sidebar, Hakkında sayfası, karşılama
#'   ekranı, sürüm rozet ve modalı bu değeri kullanır.
#'   version_history.md dosyasında en üstteki en yeni "## v..." satırı
#'   uygulamanın güncel sürümünü belirler.
#'
#' @return Karakter türünde sürüm numarası (örn. "1.1")
get_current_version <- function() {
  get_version_history()$current_version
}

#' Görünür sürüm etiketini getir (örn. "v1.1")
#'
#' @description Sidebar, hakkında, karşılama gibi görünür alanlarda
#'   kullanılan "v<sayı>" biçimindeki etikettir. Versiyon değişikliği
#'   tek bir noktadan (version_history.md) yapıldığında bu helper
#'   tüm yerleri otomatik günceller.
#'
#' @return Karakter etiket (örn. "v1.1"); sürüm boşsa "v?"
get_app_version_label <- function() {
  v <- tryCatch(get_current_version(), error = function(e) NULL)
  if (is.null(v) || !nzchar(as.character(v)[1])) {
    return("v?")
  }
  paste0("v", as.character(v)[1])
}

#' Görünür sürüm ürün etiketini getir (örn. "MERGEN Bilge v1.1")
#'
#' @description Ürün adıyla birlikte tam sürüm etiketini döndürür.
#'   Görünür yerlerde tutarlılığı korumak için sürüm referansları
#'   doğrudan dize gömmek yerine bu helper'dan alınmalıdır.
#'
#' @return Karakter etiket (örn. "MERGEN Bilge v1.1")
get_app_version_full_label <- function() {
  paste("MERGEN Bilge", get_app_version_label())
}