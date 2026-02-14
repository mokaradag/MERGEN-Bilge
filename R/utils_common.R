# ==============================================================================
# R/utils_common.R
# Dosya Yolu: R/utils_common.R
# Açıklama: Uygulama genelinde kullanılan temel yardımcı fonksiyonlar.
# NULL birleştirme operatörü, güvenli kontroller ve metin temizleyicileri içerir.
# global.R tarafından config_packages.R'den hemen sonra source() ile çağrılır.
# ==============================================================================

# --- NULL BİRLEŞTİRME OPERATÖRÜ ---
# Eğer sol taraf NULL ise sağ tarafı döndürür
`%||%` <- function(a, b) {
  if (is.null(a)) b else a
}

# --- GÜVENLİ NZCHAR KONTROLÜ ---
# Tek satırda NULL, NA ve boş karakter kontrolü yapar
safe_nzchar <- function(x) {
  is.character(x) && length(x) > 0 && !is.na(x[1]) && nzchar(x[1])
}

# --- ZAMAN DAMGASI BİÇİMLENDİRİCİ ---
# Türkiye formatında (GG.AA.YYYY - SS:DD) zaman damgası üretir
format_timestamp <- function() {
  format(Sys.time(), "%d.%m.%Y - %H:%M")
}

# --- YAPISAL KAYNAKLARDAN KAYNAKÇA HTML OLUŞTURUCU ---
# API yanıtındaki yapısal sources listesini tıklanabilir Kaynakça metnine dönüştürür.
# Hem call_llm_worker hem call_local_llm tarafından kullanılır.
build_kaynakca_from_sources <- function(sources_list) {
  if (is.null(sources_list) || length(sources_list) == 0) return("")

  cat("\n========== SOURCES PROCESSING ==========\n")

  extracted_sources <- list()
  seen_filenames <- character(0)

  for (i in seq_along(sources_list)) {
    src <- sources_list[[i]]

    if (is.list(src) && !is.null(src[["metadata"]])) {
      metadata_array <- src[["metadata"]]
      for (j in seq_along(metadata_array)) {
        doc <- metadata_array[[j]]
        filename <- doc[["name"]] %||% doc[["source"]]

        if (!is.null(filename) && is.character(filename)) {
          filename <- as.character(filename)[1]
          if (filename %in% seen_filenames) {
            cat("[DOCUMENT ", j, "] DUPLICATE - skipping: <", filename, ">\n", sep = "")
            next
          }

          cat("[DOCUMENT ", j, "] Extracted: <", filename, ">\n", sep = "")
          seen_filenames <- c(seen_filenames, filename)

          # Süreç numarasını ve dosya adını ayır
          process_match <- regexpr("^[a-z]+_[0-9]+_[0-9]+_", filename, ignore.case = TRUE)
          process_num <- ""
          actual_filename <- filename

          if (process_match > 0) {
            match_length <- attr(process_match, "match.length")
            process_part <- substr(filename, 1, match_length - 1)
            actual_filename <- substr(filename, match_length + 1, nchar(filename))
            process_num <- toupper(process_part)
            process_num <- gsub("_", " ", process_num)
            process_num <- gsub("-", " ", process_num)
          }

          # Dosya adını biçimlendir
          file_ext <- tools::file_ext(actual_filename)
          file_base <- tools::file_path_sans_ext(actual_filename)
          file_base <- gsub("_", " ", file_base)
          file_base <- gsub("-", " ", file_base)
          file_base <- tools::toTitleCase(file_base)
          formatted_filename <- paste0(file_base, ".", file_ext)

          extracted_sources[[length(extracted_sources) + 1]] <- list(
            process = process_num,
            filename = formatted_filename,
            original_filename = filename
          )
        }
      }
    }
  }

  cat("[SUMMARY] Total unique sources:", length(extracted_sources), "\n")
  if (length(extracted_sources) == 0) {
    cat("========================================\n\n")
    return("")
  }

  # Tıklanabilir Kaynakça HTML'i oluştur
  sources_text <- "\n\nKaynakça:\n"

  for (i in seq_along(extracted_sources)) {
    src_info <- extracted_sources[[i]]
    source_id <- paste0("source_", i, "_", gsub("[^a-z0-9]", "", tolower(src_info$filename)))
    original_filename <- src_info$original_filename
    file_ext <- tolower(tools::file_ext(original_filename))

    # Dosya türüne göre ikon seç
    icon_html <- if (file_ext %in% c("doc", "docx")) {
      "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
    } else if (identical(file_ext, "pdf")) {
      "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
    } else if (file_ext %in% c("xls", "xlsx")) {
      "<i class='fa-regular fa-file-excel' style='margin-right:6px;color:#1d6f42'></i>"
    } else {
      "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
    }

    label_prefix <- if (nchar(src_info$process) > 0) paste0(src_info$process, ": ") else ""
    parts_raw <- strsplit(original_filename, "&&", fixed = TRUE)[[1]]

    if (length(parts_raw) > 1) {
      parts <- trimws(parts_raw)
      left_parts <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
      right_part <- parts[length(parts)]

      left_html <- if (length(left_parts)) {
        paste(
          vapply(left_parts, function(p) {
            paste0("<span class='source-chunk'>", htmltools::htmlEscape(p), "</span>")
          }, character(1)),
          collapse = " - "
        )
      } else ""

      clickable_html <- paste0(
        "<span class='source-link' data-source-id='", source_id,
        "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
        "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
        htmltools::htmlEscape(trimws(right_part)),
        "</span>"
      )

      line <- paste0(
        i, ") ", label_prefix, icon_html,
        if (nzchar(left_html)) paste0(left_html, " - ") else "",
        clickable_html, "\n"
      )
    } else {
      clickable_html <- paste0(
        "<span class='source-link' data-source-id='", source_id,
        "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
        "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
        htmltools::htmlEscape(src_info$filename),
        "</span>"
      )
      line <- paste0(i, ") ", label_prefix, icon_html, clickable_html, "\n")
    }

    sources_text <- paste0(sources_text, line)
  }

  cat("[SUCCESS] Kaynakça built with", length(extracted_sources), "unique sources\n")
  cat("========================================\n\n")
  sources_text
}

# --- PLANLAYICI / AJAN META-METİN TEMİZLEYİCİ ---
# LLM yanıtlarından araç çağrısı kalıntılarını ve planlama cümlelerini temizler
strip_planner_text <- function(x) {
  # NULL veya character(0) güvenli kontrolü
  if (is.null(x)) return(x)
  if (!is.character(x) || length(x) == 0) return("")
  s <- x[1]
  if (!nzchar(s)) return(s)

  # JSON araç çağrısı kalıntılarını kaldır
  s <- gsub("\\{\\s*\"(tool|name)\"\\s*:\\s*\"[^\"]+\"[^{}]*\"arguments\"\\s*:\\s*\\{[^{}]*\\}\\s*\\}", "", s, perl = TRUE)
  s <- gsub("\\{\\s*\"action\"\\s*:\\s*\"[^\"]+\"[^{}]*\"parameters\"\\s*:\\s*\\{[^{}]*\\}\\s*\\}", "", s, perl = TRUE)
  s <- gsub("\\s*<tool_call>.*?</tool_call>\\s*", "", s, perl = TRUE)

  # Qwen/RAG modellerin metin olarak yazdığı <function=...> biçimli araç çağrılarını kaldır
  s <- gsub("<function=\\w+>.*?</function>", "", s, perl = TRUE)
  # Tamamlanmamış (kapanış etiketi eksik) <function=...> bloklarını da kaldır
  s <- gsub("<function=\\w+>(?:(?!</function>).)*$", "", s, perl = TRUE)
  # Kalan kapanmamış </too, </tool vb. parçaları kaldır
  s <- gsub("</?(too|tool|function|parameter)\\w*>?\\s*$", "", s, perl = TRUE)

  # Planlayıcı meta-cümlelerini kaldır (İngilizce kalıplar)
  s <- gsub("(?im)^(we need to .*|let'?s try.*|probably .*|i'?ll try.*|we will call.*|we will invoke.*|now produce the tool call\\.?|we need to produce a tool call\\.?)\\s*$", "", s, perl = TRUE)

  # Çoklu boş satırları tek satıra düşür
  s <- gsub("\n{3,}", "\n\n", s, perl = TRUE)
  trimws(s)
}