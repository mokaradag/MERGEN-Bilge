# ==============================================================================
# Dosya Yolu: R/helpers_llm_response_postprocess.R
# Açıklama: LLM yanıtlarından metin ve kaynak bilgisi çıkarma ile
#           Kaynakça bölümünü tıklanabilir bağlantılarla sonradan ekleme
#           işlemlerini merkezi olarak yönetir.
# ==============================================================================

# ------------------------------------------------------------------------------
# METNİ GÜVENLİ TEKİL KARAKTER DİZİSİNE İNDİR
# ------------------------------------------------------------------------------

# İç içe LLM metin düğümlerini güvenli metne dönüştür
normalize_llm_text_node <- function(x) {
  if (is.null(x)) {
    return("")
  }

  if (is.character(x)) {
    x <- x[!is.na(x)]
    if (!length(x)) {
      return("")
    }
    return(paste(x, collapse = ""))
  }

  if (is.atomic(x)) {
    x <- as.character(x)
    x <- x[!is.na(x)]
    if (!length(x)) {
      return("")
    }
    return(paste(x, collapse = ""))
  }

  if (is.list(x)) {
    if (!is.null(x$text)) {
      return(normalize_llm_text_node(x$text))
    }

    if (!is.null(x$content)) {
      return(normalize_llm_text_node(x$content))
    }

    if (!is.null(x$reasoning_content)) {
      return(normalize_llm_text_node(x$reasoning_content))
    }

    if (!is.null(x$reasoning)) {
      return(normalize_llm_text_node(x$reasoning))
    }

    parts <- vapply(x, function(item) {
      normalize_llm_text_node(item)
    }, character(1))

    parts <- parts[nzchar(parts)]
    if (!length(parts)) {
      return("")
    }

    return(paste(parts, collapse = ""))
  }

  as.character(x %||% "")
}

extract_first_nonempty_llm_text <- function(...) {
  adaylar <- list(...)

  for (aday in adaylar) {
    txt <- enc2utf8(normalize_llm_text_node(aday))
    if (nzchar(txt)) {
      return(txt)
    }
  }

  ""
}

extract_llm_text_bundle <- function(response_content) {
  content_text <- ""
  reasoning_text <- ""

  if (!is.list(response_content)) {
    return(list(
      content = enc2utf8(normalize_llm_text_node(response_content)),
      reasoning = ""
    ))
  }

  if (!is.null(response_content$choices) && length(response_content$choices) > 0) {
    first_choice <- response_content$choices[[1]]

    if (is.list(first_choice)) {
      message_obj <- first_choice$message %||% list()
      delta_obj <- first_choice$delta %||% list()

      content_text <- extract_first_nonempty_llm_text(
        message_obj$content,
        delta_obj$content,
        delta_obj$text,
        first_choice$text,
        response_content$content,
        response_content$message$content
      )

      reasoning_text <- extract_first_nonempty_llm_text(
        message_obj$reasoning_content,
        message_obj$reasoning,
        delta_obj$reasoning_content,
        delta_obj$reasoning,
        response_content$reasoning_content,
        response_content$reasoning,
        response_content$message$reasoning_content,
        response_content$message$reasoning
      )
    }
  }

  if (!nzchar(content_text)) {
    content_text <- extract_first_nonempty_llm_text(
      response_content$content,
      response_content$message$content
    )
  }

  if (!nzchar(reasoning_text)) {
    reasoning_text <- extract_first_nonempty_llm_text(
      response_content$reasoning_content,
      response_content$reasoning,
      response_content$message$reasoning_content,
      response_content$message$reasoning
    )
  }

  list(
    content = enc2utf8(content_text),
    reasoning = enc2utf8(reasoning_text)
  )
}

normalize_llm_scalar_content <- function(ai_content) {
  txt <- enc2utf8(normalize_llm_text_node(ai_content))
  if (!nzchar(txt)) {
    return("")
  }
  txt
}

# ------------------------------------------------------------------------------
# LLM YANITINDAN METİN VE KAYNAKLARI ÇIKAR
# ------------------------------------------------------------------------------

extract_llm_content_and_sources <- function(response_content, model_id = NULL) {
  text_bundle <- extract_llm_text_bundle(response_content)
  ai_content <- normalize_llm_scalar_content(text_bundle$content %||% "")
  reasoning_text <- enc2utf8(text_bundle$reasoning %||% "")
  sources_list <- NULL

  set_ai_content_if_nonempty <- function(candidate) {
    txt <- normalize_llm_scalar_content(candidate)
    if (nzchar(txt)) {
      ai_content <<- txt
      return(TRUE)
    }
    FALSE
  }

  if (!is.list(response_content)) {
    return(list(
      content = normalize_llm_scalar_content(response_content),
      sources = NULL,
      reasoning = ""
    ))
  }

  if (!is.null(response_content$choices) && length(response_content$choices) > 0) {
    first_choice <- response_content$choices[[1]]

    if (is.list(first_choice)) {
      message_obj <- first_choice$message %||% list()
      delta_obj <- first_choice$delta %||% list()

      if (is.list(message_obj)) {
        set_ai_content_if_nonempty(message_obj$content)

        if (!is.null(message_obj$sources)) {
          sources_list <- message_obj$sources
        }
      }

      if (is.list(delta_obj)) {
        set_ai_content_if_nonempty(delta_obj$content)
        set_ai_content_if_nonempty(delta_obj$text)

        if (is.null(sources_list) && !is.null(delta_obj$sources)) {
          sources_list <- delta_obj$sources
        }
      }

      set_ai_content_if_nonempty(first_choice$text)

      if (is.null(sources_list) && !is.null(first_choice$sources)) {
        sources_list <- first_choice$sources
      }
    }
  }

  set_ai_content_if_nonempty(response_content$content)

  if (!is.null(response_content$message) && is.list(response_content$message)) {
    set_ai_content_if_nonempty(response_content$message$content)

    if (is.null(sources_list) && !is.null(response_content$message$sources)) {
      sources_list <- response_content$message$sources
    }
  }

  if (is.null(sources_list) && !is.null(response_content$sources)) {
    sources_list <- response_content$sources
  }

  if (!nzchar(ai_content) && should_allow_reasoning_fallback(model_id)) {
    ai_content <- normalize_llm_scalar_content(reasoning_text)
  }

  list(
    content = normalize_llm_scalar_content(ai_content),
    sources = sources_list,
    reasoning = enc2utf8(reasoning_text %||% "")
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