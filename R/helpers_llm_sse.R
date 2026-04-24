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

extract_llm_delta_bundle <- function(event_obj) {
  if (!is.list(event_obj)) {
    return(list(content = "", reasoning = ""))
  }

  content_text <- ""
  reasoning_text <- ""

  if (!is.null(event_obj$choices) && length(event_obj$choices) > 0) {
    first_choice <- event_obj$choices[[1]]

    if (is.list(first_choice)) {
      delta_obj <- first_choice$delta %||% list()
      message_obj <- first_choice$message %||% list()

      content_text <- extract_first_nonempty_llm_text(
        delta_obj$content,
        delta_obj$text,
        message_obj$content,
        first_choice$text
      )

		reasoning_text <- extract_first_nonempty_llm_text(
		  delta_obj$reasoning_content,
		  delta_obj$reasoning,
		  delta_obj$reasoning_text,
		  delta_obj$thinking,
		  delta_obj$thought,
		  delta_obj$reasoning$content,
		  delta_obj$reasoning$text,
		  delta_obj$reasoning$summary,
		  message_obj$reasoning_content,
		  message_obj$reasoning,
		  message_obj$reasoning_text,
		  message_obj$thinking,
		  message_obj$thought,
		  message_obj$reasoning$content,
		  message_obj$reasoning$text,
		  message_obj$reasoning$summary
		)
    }
  }

  if (!nzchar(content_text)) {
    content_text <- extract_first_nonempty_llm_text(
      event_obj$delta$content,
      event_obj$delta$text,
      event_obj$content
    )
  }

  if (!nzchar(reasoning_text)) {
	reasoning_text <- extract_first_nonempty_llm_text(
	  event_obj$delta$reasoning_content,
	  event_obj$delta$reasoning,
	  event_obj$delta$reasoning_text,
	  event_obj$delta$thinking,
	  event_obj$delta$thought,
	  event_obj$delta$reasoning$content,
	  event_obj$delta$reasoning$text,
	  event_obj$delta$reasoning$summary,
	  event_obj$reasoning_content,
	  event_obj$reasoning,
	  event_obj$reasoning_text,
	  event_obj$thinking,
	  event_obj$thought,
	  event_obj$reasoning$content,
	  event_obj$reasoning$text,
	  event_obj$reasoning$summary
	)
  }

  list(
    content = enc2utf8(content_text),
    reasoning = enc2utf8(reasoning_text)
  )
}

extract_llm_delta_text <- function(event_obj) {
  extract_llm_delta_bundle(event_obj)$content
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

append_stream_delta_line <- function(stream_file, text_value, stream_con = NULL) {
  if ((!nzchar(stream_file %||% "")) && is.null(stream_con)) {
    return(invisible(NULL))
  }

  if (!nzchar(text_value %||% "")) {
    return(invisible(NULL))
  }

  text_utf8 <- enc2utf8(text_value)
  text_b64 <- base64enc::base64encode(charToRaw(text_utf8))

  payload <- jsonlite::toJSON(
    list(type = "delta", text_b64 = text_b64),
    auto_unbox = TRUE,
    null = "null"
  )

  payload_line <- paste0(payload, "\n")

  if (!is.null(stream_con)) {
    writeBin(charToRaw(payload_line), stream_con)
    flush(stream_con)
    return(invisible(NULL))
  }

  con <- file(stream_file, open = "ab")
  on.exit(close(con), add = TRUE)

  writeBin(charToRaw(payload_line), con)
  flush(con)
  invisible(NULL)
}

# Düşünen modellerde akıl yürütme akışı ana yanıt akışından ayrı kanalla
# aktarılır. Aynı dosyaya "type":"reasoning_delta" satırları yazılır.
append_stream_reasoning_line <- function(stream_file, text_value, stream_con = NULL) {
  if ((!nzchar(stream_file %||% "")) && is.null(stream_con)) {
    return(invisible(NULL))
  }

  if (!nzchar(text_value %||% "")) {
    return(invisible(NULL))
  }

  text_utf8 <- enc2utf8(text_value)
  text_b64 <- base64enc::base64encode(charToRaw(text_utf8))

  payload <- jsonlite::toJSON(
    list(type = "reasoning_delta", text_b64 = text_b64),
    auto_unbox = TRUE,
    null = "null"
  )

  payload_line <- paste0(payload, "\n")

  if (!is.null(stream_con)) {
    writeBin(charToRaw(payload_line), stream_con)
    flush(stream_con)
    return(invisible(NULL))
  }

  con <- file(stream_file, open = "ab")
  on.exit(close(con), add = TRUE)

  writeBin(charToRaw(payload_line), con)
  flush(con)
  invisible(NULL)
}

decode_stream_delta_payload <- function(payload) {
  if (is.null(payload)) {
    return("")
  }

  if (!is.null(payload$text_b64) && nzchar(as.character(payload$text_b64 %||% ""))) {
    decoded_raw <- tryCatch(
      base64enc::base64decode(as.character(payload$text_b64)[1]),
      error = function(e) NULL
    )

    if (!is.null(decoded_raw) && length(decoded_raw) > 0) {
      decoded_text <- tryCatch(rawToChar(decoded_raw), error = function(e) "")
      Encoding(decoded_text) <- "UTF-8"
      return(enc2utf8(decoded_text))
    }
  }

  if (!is.null(payload$text)) {
    return(enc2utf8(as.character(payload$text %||% "")))
  }

  ""
}

# ------------------------------------------------------------------------------
# KULLANICI DURDURMA SİNYALİ KONTROLÜ
# ------------------------------------------------------------------------------
# Akış sırasında kullanıcı "Durdur" butonuna bastığında ilgili stop_file dosyası
# oluşturulur. Worker bu bayrağı periyodik olarak kontrol eder. Bu yardımcı,
# kontrol mantığını tek noktada toplar ve birim test edilebilir kılar.
streaming_should_stop <- function(stop_file) {
  if (is.null(stop_file)) return(FALSE)
  candidate <- tryCatch(as.character(stop_file)[1], error = function(e) "")
  if (!nzchar(candidate) || is.na(candidate)) return(FALSE)
  isTRUE(file.exists(candidate))
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
    model_caps <- get_local_model_capabilities(selected_model)
    stream_reasoning <- isTRUE(model_caps$stream_reasoning)
    allow_reasoning_fallback <- isTRUE(model_caps$allow_reasoning_fallback)

    request_start_unix <- suppressWarnings(as.numeric(current_settings$request_start_unix %||% NA_real_))
    future_submit_unix <- suppressWarnings(as.numeric(current_settings$future_submit_unix %||% NA_real_))

    if (!is.na(request_start_unix)) {
      log_info(sprintf(
        "[CHAT PERF] SSE worker giriş yaptı - istekten beri %.3f sn",
        as.numeric(difftime(llm_start_time, as.POSIXct(request_start_unix, origin = "1970-01-01", tz = "UTC"), units = "secs"))
      ))
    }

    if (!is.na(future_submit_unix)) {
      log_info(sprintf(
        "[CHAT PERF] SSE worker giriş yaptı - future gönderiminden beri %.3f sn",
        as.numeric(difftime(llm_start_time, as.POSIXct(future_submit_unix, origin = "1970-01-01", tz = "UTC"), units = "secs"))
      ))
    }

    creds <- resolve_local_llm_credentials(selected_model)
    api_url <- creds$endpoint
    if (!nzchar(api_url)) {
      stop("API endpoint not found in configuration")
    }

	default_api_key <- creds$default_api_key %||% ""
	allow_user_key <- isTRUE(creds$allow_user_key)

	# Sunucu tarafindan yonetilen endpoint'lerde kullanici anahtari veya
	# api_key_override kesinlikle kullanilmaz. Bu endpoint'lerde sadece
	# .Renviron icinden cozulenen varsayilan endpoint anahtari kullanilir.
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
	  api_key <- as.character(default_api_key)[1] %||% ""
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
    if (!should_omit_temperature(selected_model)) {
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

    stream_con <- file(stream_file, open = "ab")
    on.exit(try(close(stream_con), silent = TRUE), add = TRUE)

	event_buffer <- ""
	accumulated_text <- ""
	accumulated_reasoning <- ""
	accumulated_sources <- NULL

	# Bazı OpenAI-uyumlu yerel uçlar reasoning_content yerine Qwen tarzı
	# <think>...</think> bloklarını normal delta$content içinde yayınlar.
	# Bu yardımcı, görünür yanıt ile modelin açıkça yayınladığı düşünce akışını ayırır.
	inside_think_block <- FALSE

	split_think_tag_delta <- function(delta_text) {
	  text <- enc2utf8(as.character(delta_text %||% "")[1])
	  if (!nzchar(text)) {
		return(list(content = "", reasoning = ""))
	  }

	  content_parts <- character(0)
	  reasoning_parts <- character(0)
	  remaining <- text

	  find_tag <- function(x, tag) {
		pos <- regexpr(tag, x, fixed = TRUE, ignore.case = TRUE, useBytes = TRUE)[1]
		if (is.na(pos) || pos < 0) -1L else as.integer(pos)
	  }

	  repeat {
		if (!nzchar(remaining)) {
		  break
		}

		if (isTRUE(inside_think_block)) {
		  close_pos <- find_tag(remaining, "</think>")

		  if (close_pos < 0L) {
			reasoning_parts <- c(reasoning_parts, remaining)
			remaining <- ""
			break
		  }

		  if (close_pos > 1L) {
			reasoning_parts <- c(reasoning_parts, substr(remaining, 1L, close_pos - 1L))
		  }

		  remaining <- substr(remaining, close_pos + nchar("</think>"), nchar(remaining))
		  inside_think_block <<- FALSE
		  next
		}

		open_pos <- find_tag(remaining, "<think>")

		if (open_pos < 0L) {
		  content_parts <- c(content_parts, remaining)
		  remaining <- ""
		  break
		}

		if (open_pos > 1L) {
		  content_parts <- c(content_parts, substr(remaining, 1L, open_pos - 1L))
		}

		remaining <- substr(remaining, open_pos + nchar("<think>"), nchar(remaining))
		inside_think_block <<- TRUE
	  }

	  list(
		content = enc2utf8(paste0(content_parts, collapse = "")),
		reasoning = enc2utf8(paste0(reasoning_parts, collapse = ""))
	  )
	}

    log_info(sprintf("[CHAT PERF] SSE işçi HTTP isteği başladı - model=%s", selected_model))

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

		delta_bundle <- extract_llm_delta_bundle(event_obj)

		raw_delta_text <- enc2utf8(delta_bundle$content)
		reasoning_text <- enc2utf8(delta_bundle$reasoning)

		think_split <- split_think_tag_delta(raw_delta_text)
		delta_text <- enc2utf8(think_split$content)

		if (nzchar(think_split$reasoning)) {
		  reasoning_text <- paste0(reasoning_text, think_split$reasoning)
		}

      # Akıl yürütme akışı ayrı kanalla yayınlanır; yanıt metnine karışmaz.
      if (nzchar(reasoning_text)) {
        accumulated_reasoning <<- paste0(accumulated_reasoning, reasoning_text)

        if (isTRUE(stream_reasoning)) {
          append_stream_reasoning_line(
            stream_file = NULL,
            text_value = reasoning_text,
            stream_con = stream_con
          )
        }
      }

      if (nzchar(delta_text)) {
        if (!nzchar(accumulated_text)) {
          log_info(sprintf(
            "[CHAT PERF] SSE işçide ilk delta alındı - %.3f sn",
            as.numeric(difftime(Sys.time(), llm_start_time, units = "secs"))
          ))
        }

        accumulated_text <<- paste0(accumulated_text, delta_text)
        append_stream_delta_line(
          stream_file = NULL,
          text_value = delta_text,
          stream_con = stream_con
        )
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
        if (streaming_should_stop(stop_file)) {
          stop("STREAM_ABORTED_BY_USER")
        }

        chunk_text <- tryCatch(
          decode_utf8_raw_chunk(raw_chunk),
          error = function(e) ""
        )

        if (!nzchar(chunk_text)) {
          return(invisible(NULL))
        }

        if (!nzchar(accumulated_text)) {
          log_info(sprintf(
            "[CHAT PERF] SSE işçide ilk ham HTTP parçası alındı - %.3f sn",
            as.numeric(difftime(Sys.time(), llm_start_time, units = "secs"))
          ))
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

    if (!nzchar(final_content) && isTRUE(allow_reasoning_fallback)) {
      final_content <- enc2utf8(normalize_llm_scalar_content(accumulated_reasoning))
    }

	list(
	  success = TRUE,
	  aborted = FALSE,
	  content = final_content,
	  reasoning = enc2utf8(normalize_llm_scalar_content(accumulated_reasoning)),
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
	  reasoning = enc2utf8(normalize_llm_scalar_content(accumulated_reasoning)),
	  sources = NULL,
	  duration = as.numeric(difftime(Sys.time(), llm_start_time, units = "secs")),
	  error = hata_mesaji
	)
  })
}