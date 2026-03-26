# ==============================================================================
# Dosya Yolu: R/helpers_llm_response_postprocess.R
# Açıklama: LLM yanıtlarından metin ve kaynak bilgisi çıkarma ile
#           Kaynakça bölümünü tıklanabilir bağlantılarla sonradan ekleme
#           işlemlerini merkezi olarak yönetir.
# ==============================================================================

# ------------------------------------------------------------------------------
# METNİ GÜVENLİ TEKİL KARAKTER DİZİSİNE İNDİR
# ------------------------------------------------------------------------------

normalize_llm_scalar_content <- function(ai_content) {
  if (is.null(ai_content)) {
    return("")
  }

  if (is.character(ai_content)) {
    if (length(ai_content) == 0 || is.na(ai_content[1])) {
      return("")
    }
    return(as.character(ai_content)[1])
  }

  if (is.list(ai_content)) {
    text_parts <- unlist(ai_content, use.names = FALSE)
    text_parts <- text_parts[!is.na(text_parts)]
    if (length(text_parts) == 0) {
      return("")
    }
    return(paste(as.character(text_parts), collapse = ""))
  }

  as.character(ai_content %||% "")
}

# ------------------------------------------------------------------------------
# LLM YANITINDAN METİN VE KAYNAKLARI ÇIKAR
# ------------------------------------------------------------------------------

extract_llm_content_and_sources <- function(response_content) {
  ai_content <- ""
  sources_list <- NULL

  if (!is.list(response_content)) {
    return(list(
      content = normalize_llm_scalar_content(response_content),
      sources = NULL
    ))
  }

  if (!is.null(response_content$choices) && length(response_content$choices) > 0) {
    first_choice <- response_content$choices[[1]]

    if (is.list(first_choice)) {
      if (!is.null(first_choice$message) && !is.null(first_choice$message$content)) {
        ai_content <- normalize_llm_scalar_content(first_choice$message$content)
      } else if (!is.null(first_choice$delta) && !is.null(first_choice$delta$content)) {
        delta_content <- first_choice$delta$content

        if (is.character(delta_content)) {
          ai_content <- paste(delta_content, collapse = "")
        } else if (is.list(delta_content)) {
          delta_parts <- vapply(delta_content, function(part) {
            if (is.character(part)) {
              return(paste(part, collapse = ""))
            }
            if (is.list(part) && !is.null(part$text)) {
              return(as.character(part$text %||% ""))
            }
            ""
          }, character(1))
          ai_content <- paste(delta_parts, collapse = "")
        }
      } else if (!is.null(first_choice$text)) {
        ai_content <- normalize_llm_scalar_content(first_choice$text)
      }

      if (!is.null(first_choice$message) && !is.null(first_choice$message$sources)) {
        sources_list <- first_choice$message$sources
      } else if (!is.null(first_choice$delta) && !is.null(first_choice$delta$sources)) {
        sources_list <- first_choice$delta$sources
      } else if (!is.null(first_choice$sources)) {
        sources_list <- first_choice$sources
      }
    }
  }

  if (!nzchar(ai_content) && !is.null(response_content$content)) {
    ai_content <- normalize_llm_scalar_content(response_content$content)
  }

  if (!nzchar(ai_content) &&
      !is.null(response_content$message) &&
      !is.null(response_content$message$content)) {
    ai_content <- normalize_llm_scalar_content(response_content$message$content)
  }

  if (is.null(sources_list) && !is.null(response_content$sources)) {
    sources_list <- response_content$sources
  }

  if (is.null(sources_list) &&
      !is.null(response_content$message) &&
      !is.null(response_content$message$sources)) {
    sources_list <- response_content$message$sources
  }

  list(
    content = normalize_llm_scalar_content(ai_content),
    sources = sources_list
  )
}

# ------------------------------------------------------------------------------
# KAYNAKLARI TIKLANABİLİR KAYNAKÇA OLARAK EKLE
# ------------------------------------------------------------------------------

append_clickable_sources <- function(ai_content, sources_list) {
  ai_content <- normalize_llm_scalar_content(ai_content)

  if (is.null(sources_list) || length(sources_list) == 0) {
    return(ai_content)
  }

  mergen_debug_cat("\n========== SOURCES PROCESSING ==========\n")

  extracted_sources <- list()
  seen_filenames <- character(0)

  for (i in seq_along(sources_list)) {
    src <- sources_list[[i]]

    if (is.list(src) && !is.null(src[["metadata"]])) {
      metadata_array <- src[["metadata"]]

      for (j in seq_along(metadata_array)) {
        doc <- metadata_array[[j]]
        filename <- doc[["name"]] %||% doc[["source"]]

        if (!is.null(filename) && nzchar(filename) && !(filename %in% seen_filenames)) {
          seen_filenames <- c(seen_filenames, filename)

          process_num <- ""
          formatted_filename <- filename

          mergen_debug_cat("[DOCUMENT ", j, "] Final: ", process_num, ": ", formatted_filename, "\n\n", sep = "")

          extracted_sources[[length(extracted_sources) + 1]] <- list(
            process = process_num,
            filename = formatted_filename,
            original_filename = filename
          )
        }
      }
    }
  }

  mergen_debug_cat("[SUMMARY] Total unique sources:", length(extracted_sources), "\n")

  if (length(extracted_sources) == 0) {
    mergen_debug_cat("========================================\n\n")
    return(ai_content)
  }

  ai_content <- sub(
    "\\n*Kaynakça:\\s*\\n(\\s*\\[?\\d+[)\\].]\\s*[^\\n]+\\n?)*\\s*$",
    "",
    ai_content,
    perl = TRUE
  )
  ai_content <- trimws(ai_content)

  sources_text <- "\n\nKaynakça:\n"

  for (i in seq_along(extracted_sources)) {
    src_info <- extracted_sources[[i]]
    source_id <- paste0("source_", i, "_", gsub("[^a-z0-9]", "", tolower(src_info$filename)))

    original_filename <- src_info$original_filename
    file_ext <- tolower(tools::file_ext(original_filename))

    icon_html <- if (file_ext %in% c("doc", "docx")) {
      "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
    } else if (identical(file_ext, "pdf")) {
      "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
    } else {
      "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
    }

    parts_raw <- strsplit(original_filename, "&&", fixed = TRUE)[[1]]
    label_prefix <- if (nchar(src_info$process) > 0) paste0(src_info$process, ": ") else ""

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
      } else {
        ""
      }

      clickable_html <- paste0(
        "<span class='source-link' data-source-id='", source_id,
        "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
        "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
        htmltools::htmlEscape(trimws(right_part)),
        "</span>"
      )

      line <- paste0(
        "<span class='kaynakca-entry' data-entry='", i, "'>",
        i, ") ", label_prefix, icon_html,
        if (nzchar(left_html)) paste0(left_html, " - ") else "",
        clickable_html,
        "</span>\n"
      )
    } else {
      clickable_html <- paste0(
        "<span class='source-link' data-source-id='", source_id,
        "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
        "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
        htmltools::htmlEscape(src_info$filename),
        "</span>"
      )

      line <- paste0(
        "<span class='kaynakca-entry' data-entry='", i, "'>",
        i, ") ", label_prefix, icon_html, clickable_html,
        "</span>\n"
      )
    }

    sources_text <- paste0(sources_text, line)
  }

  mergen_debug_cat("[SUCCESS] Kaynakça appended with", length(extracted_sources), "unique sources\n")
  mergen_debug_cat("========================================\n\n")

  paste0(ai_content, sources_text)
}