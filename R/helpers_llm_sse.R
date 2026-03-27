# ==============================================================================
# Dosya Yolu: R/helpers_llm_sse.R
# Açıklama: Gerçek SSE akışı için işçi tarafı yardımcılarını içerir.
#           LLM uç noktasına stream=TRUE ile bağlanır, veri parçalarını
#           JSON satırları olarak geçici dosyaya yazar ve nihai sonucu döndürür.
# ==============================================================================

# ------------------------------------------------------------------------------
# RAW PARÇAYI UTF-8 OLARAK ÇÖZ
# ------------------------------------------------------------------------------

decode_utf8_raw_chunk <- function(raw_chunk) {
  txt <- rawToChar(raw_chunk)
  Encoding(txt) <- "UTF-8"
  enc2utf8(txt)
}

# ------------------------------------------------------------------------------
# SSE OLAY METNİNİ AYRIŞTIR
# ------------------------------------------------------------------------------

parse_llm_sse_event <- function(event_text) {
  temiz_metin <- gsub("\r", "", event_text, fixed = TRUE)
  satirlar <- strsplit(temiz_metin, "\n", fixed = TRUE)[[1]]

  data_satirlari <- character(0)

  for (satir in satirlar) {
    if (grepl("^data\\s*:", satir)) {
      data_satirlari <- c(data_satirlari, sub("^data\\s*:\\s*", "", satir))
    }
  }

  if (length(data_satirlari) == 0) {
    aday <- trimws(temiz_metin)
    if (!nzchar(aday)) {
      return(NULL)
    }
    data_payload <- aday
  } else {
    data_payload <- paste(data_satirlari, collapse = "\n")
  }

  if (!nzchar(trimws(data_payload))) {
    return(NULL)
  }

  if (identical(trimws(data_payload), "[DONE]")) {
    return(list(done = TRUE, data = NULL))
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(data_payload, simplifyVector = FALSE),
    error = function(e) NULL
  )

  if (is.null(parsed)) {
    return(NULL)
  }

  list(done = FALSE, data = parsed)
}

# ------------------------------------------------------------------------------
# SSE OLAYINDAN METİN PARÇASI ÇIKAR
# ------------------------------------------------------------------------------

extract_llm_delta_text <- function(event_obj) {
  if (!is.list(event_obj)) {
    return("")
  }

  if (!is.null(event_obj$choices) && length(event_obj$choices) > 0) {
    first_choice <- event_obj$choices[[1]]

    if (!is.null(first_choice$delta)) {
      delta_obj <- first_choice$delta

      if (!is.null(delta_obj$content)) {
        content_obj <- delta_obj$content

        if (is.character(content_obj)) {
          return(paste(content_obj, collapse = ""))
        }

        if (is.list(content_obj)) {
          content_parts <- vapply(content_obj, function(part) {
            if (is.character(part)) {
              return(paste(part, collapse = ""))
            }

            if (is.list(part) && !is.null(part$text)) {
              return(as.character(part$text %||% ""))
            }

            ""
          }, character(1))

          return(paste(content_parts, collapse = ""))
        }
      }

      if (!is.null(delta_obj$text)) {
        return(as.character(delta_obj$text %||% ""))
      }
    }
  }

  if (!is.null(event_obj$delta) && !is.null(event_obj$delta$content)) {
    return(as.character(event_obj$delta$content %||% ""))
  }

  ""
}

# ------------------------------------------------------------------------------
# SSE OLAYINDAN KAYNAK BİLGİSİ ÇIKAR
# ------------------------------------------------------------------------------

extract_llm_event_sources <- function(event_obj) {
  ayristirilmis <- extract_llm_content_and_sources(event_obj)
  ayristirilmis$sources
}

# ------------------------------------------------------------------------------
# AKIŞ DOSYASINA DELTA SATIRI EKLE
# ------------------------------------------------------------------------------

append_stream_delta_line <- function(stream_file, text_value) {
  if (is.null(stream_file) || !nzchar(stream_file) || !nzchar(text_value)) {
    return(invisible(NULL))
  }

  payload <- jsonlite::toJSON(
    list(type = "delta", text = enc2utf8(text_value)),
    auto_unbox = TRUE,
    null = "null"
  )

  payload_line <- paste0(enc2utf8(payload), "\n")

  con <- file(stream_file, open = "ab")
  on.exit(close(con), add = TRUE)

  writeBin(charToRaw(payload_line), con)
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# İŞÇİ TARAFINDA GERÇEK SSE ÇAĞRISI ÇALIŞTIR
# ------------------------------------------------------------------------------

call_local_llm_sse_worker <- function(chat_history,
                                      current_settings,
                                      stream_file,
                                      stop_file = NULL) {
  llm_start_time <- Sys.time()

  tryCatch({
    selected_model <- current_settings$model_selection

    creds <- resolve_local_llm_credentials(selected_model)
    api_url <- creds$endpoint
    if (!nzchar(api_url)) {
      stop("API endpoint not found in configuration")
    }

    default_api_key <- creds$default_api_key %||% ""
    allow_user_key <- isTRUE(creds$allow_user_key)

    api_key <- ""
    if (allow_user_key) {
      api_key <- as.character(current_settings$api_key %||% current_settings$api_key_override %||% "")
      if (!nzchar(api_key)) {
        sess <- current_settings$shiny_session %||% NULL
        if (!is.null(sess) && !is.null(sess$userData$ai_api_key)) {
          api_key <- as.character(sess$userData$ai_api_key)[1]
        }
      }
    } else {
      api_key <- as.character(current_settings$api_key_override %||% "")
    }

    if (!nzchar(api_key) && nzchar(default_api_key)) {
      api_key <- as.character(default_api_key)[1]
    }

    is_local_noauth <- grepl("(?i)(localhost|127\\.0\\.0\\.1|ollama)", api_url)
    if (!nzchar(api_key) && !is_local_noauth) {
      stop("AUTH_MISSING_KEY: Kullanıcı API anahtarı bulunamadı. Lütfen Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin.")
    }

    messages_payload <- lapply(chat_history, function(msg) {
      role_val <- NULL
      if (!is.null(msg$type)) {
        role_val <- if (identical(msg$type, "user")) {
          "user"
        } else if (identical(msg$type, "system")) {
          "system"
        } else {
          "assistant"
        }
      } else if (!is.null(msg$role)) {
        role_val <- tolower(as.character(msg$role))
        if (!(role_val %in% c("user", "assistant", "system"))) {
          role_val <- "user"
        }
      } else {
        role_val <- "user"
      }

      content_val <- NULL
      if (!is.null(msg$content)) {
        content_val <- msg$content
      } else if (!is.null(msg$message)) {
        content_val <- msg$message
      } else {
        content_val <- as.character(msg)
      }

      list(role = role_val, content = content_val)
    })

    temp_value <- if (!is.null(current_settings$temperature)) current_settings$temperature else 0.4
    max_tokens_val <- current_settings$max_output_tokens %||% 4096

    body <- list(
      model = selected_model,
      messages = messages_payload,
      stream = TRUE,
      max_tokens = max_tokens_val
    )

    # Düşünmeli modeller bazı uçlarda temperature alanını reddedebiliyor
    if (!grepl("(?i)(think|reason|qwen3\\.5)", selected_model, perl = TRUE)) {
      body$temperature <- temp_value
    }

    headers <- c("Content-Type" = "application/json")
    if (nzchar(api_key)) {
      headers <- c(headers, "Authorization" = paste("Bearer", api_key))
    }

    if (file.exists(stream_file)) {
      unlink(stream_file, force = TRUE)
    }
    file.create(stream_file)

    event_buffer <- ""
    accumulated_text <- ""
    accumulated_sources <- NULL

    process_single_event <- function(parsed_event) {
      if (is.null(parsed_event)) {
        return(invisible(NULL))
      }

      if (isTRUE(parsed_event$done)) {
        return(invisible(NULL))
      }

      event_obj <- parsed_event$data
      if (is.null(event_obj)) {
        return(invisible(NULL))
      }

      delta_text <- enc2utf8(extract_llm_delta_text(event_obj))
      if (nzchar(delta_text)) {
        if (!nzchar(accumulated_text)) {
          log_info(sprintf(
            "[SSE] İlk delta alındı - %.3f sn",
            as.numeric(difftime(Sys.time(), llm_start_time, units = "secs"))
          ))
        }

        accumulated_text <<- paste0(accumulated_text, delta_text)
        append_stream_delta_line(stream_file, delta_text)
      }

      event_sources <- extract_llm_event_sources(event_obj)
      if (!is.null(event_sources) && length(event_sources) > 0) {
        accumulated_sources <<- event_sources
      }

      invisible(NULL)
    }

    process_event_buffer <- function(force = FALSE) {
      normalized <- gsub("\r\n", "\n", event_buffer, fixed = TRUE)
      normalized <- gsub("\r", "\n", normalized, fixed = TRUE)

      repeat {
        delimiter_pos <- regexpr("\n\n", normalized, fixed = TRUE)[1]
        if (delimiter_pos < 0) {
          break
        }

        event_text <- substr(normalized, 1, delimiter_pos - 1)
        remainder <- substr(normalized, delimiter_pos + 2, nchar(normalized))
        parsed_event <- parse_llm_sse_event(event_text)
        process_single_event(parsed_event)

        normalized <- remainder
      }

      if (isTRUE(force) && nzchar(trimws(normalized))) {
        parsed_event <- parse_llm_sse_event(normalized)
        process_single_event(parsed_event)
        normalized <- ""
      }

      event_buffer <<- normalized
      invisible(NULL)
    }

    h <- curl::new_handle()
    curl::handle_setheaders(h, .list = as.list(headers))
    curl::handle_setopt(
      h,
      post = TRUE,
      postfields = jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"),
      timeout_ms = 300000
    )

    response_meta <- curl::curl_fetch_stream(
      api_url,
      fun = function(raw_chunk) {
        if (!is.null(stop_file) && file.exists(stop_file)) {
          stop("STREAM_ABORTED_BY_USER")
        }

        chunk_text <- tryCatch(
          decode_utf8_raw_chunk(raw_chunk),
          error = function(e) ""
        )

        if (!nzchar(chunk_text)) {
          return(invisible(NULL))
        }

        event_buffer <<- paste0(event_buffer, chunk_text)
        process_event_buffer(force = FALSE)
        invisible(NULL)
      },
      handle = h
    )

    process_event_buffer(force = TRUE)

    if (!is.null(response_meta$status_code) && response_meta$status_code >= 400) {
      stop(sprintf("API_HTTP_ERROR_%d", response_meta$status_code))
    }

    final_content <- strip_planner_text(accumulated_text)
    final_content <- enc2utf8(normalize_llm_scalar_content(final_content))

    list(
      success = TRUE,
      aborted = FALSE,
      content = final_content,
      sources = accumulated_sources,
      duration = as.numeric(difftime(Sys.time(), llm_start_time, units = "secs")),
      error = NULL
    )
  }, error = function(e) {
    hata_mesaji <- conditionMessage(e)

    list(
      success = FALSE,
      aborted = identical(hata_mesaji, "STREAM_ABORTED_BY_USER"),
      content = "",
      sources = NULL,
      duration = as.numeric(difftime(Sys.time(), llm_start_time, units = "secs")),
      error = hata_mesaji
    )
  })
}