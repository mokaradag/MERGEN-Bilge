# ==============================================================================
# Dosya Yolu: R/helpers_llm_sse.R
# Açıklama: Gerçek SSE akışı için işçi tarafı yardımcılarını içerir.
#           LLM uç noktasına stream=TRUE ile bağlanır, veri parçalarını
#           JSON satırları olarak geçici dosyaya yazar ve nihai sonucu döndürür.
# ==============================================================================

# Akış dosyası satır protokolü ve SSE olay/delta ayrıştırma yardımcıları ayrı
# dosyalardadır. İzole test/debug source kullanımında bu dosyaların önce
# yüklenmiş olduğundan emin olmak için küçük fallback köprüsü:
.helpers_llm_sse_stream_io_path <- file.path("R", "helpers_llm_stream_io.R")
if (!exists("append_stream_delta_line", mode = "function", inherits = TRUE) &&
    file.exists(.helpers_llm_sse_stream_io_path)) {
  source(.helpers_llm_sse_stream_io_path, encoding = "UTF-8", local = globalenv())
}
rm(.helpers_llm_sse_stream_io_path)

.helpers_llm_sse_events_path <- file.path("R", "helpers_llm_sse_events.R")
if (!exists("extract_llm_delta_bundle", mode = "function", inherits = TRUE) &&
    file.exists(.helpers_llm_sse_events_path)) {
  source(.helpers_llm_sse_events_path, encoding = "UTF-8", local = globalenv())
}
rm(.helpers_llm_sse_events_path)

# ------------------------------------------------------------------------------
# SSE OLAY/DELTA AYRIŞTIRMA YARDIMCILARI
# ------------------------------------------------------------------------------
# decode_utf8_raw_chunk(), parse_llm_sse_event(), extract_llm_delta_bundle(),
# extract_llm_delta_text() ve extract_llm_event_sources() yardımcıları
# R/helpers_llm_sse_events.R içinde tutulur.

# ------------------------------------------------------------------------------
# AKIŞ DOSYASI SATIR PROTOKOLÜ
# ------------------------------------------------------------------------------
# append_stream_delta_line(), append_stream_reasoning_line(),
# decode_stream_delta_payload() ve streaming_should_stop() yardımcıları
# R/helpers_llm_stream_io.R içinde tutulur.

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

	# Düşünmeli modeller bazı uçlarda temperature alanını reddedebiliyor.
	if (!should_omit_temperature(selected_model)) {
	  body$temperature <- temp_value
	}

	# Model bazlı ek istek alanlarını uygula.
	# Örn. gemma-4-31B-it için chat_template_kwargs$enable_thinking = TRUE.
	if (exists("apply_model_request_overrides", mode = "function", inherits = TRUE)) {
	  body <- apply_model_request_overrides(body, selected_model)
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

	# Üretimde reasoning debug çıktıları kapalıdır.
	# Geçici teşhis gerektiğinde:
	# Sys.setenv(MERGEN_REASONING_DEBUG = "TRUE")
	reasoning_debug_enabled <- isTRUE(as.logical(Sys.getenv("MERGEN_REASONING_DEBUG", "FALSE")))

	append_stream_debug_line_local <- function(message) {
	  if (!isTRUE(reasoning_debug_enabled)) {
		return(invisible(NULL))
	  }

	  debug_text <- enc2utf8(as.character(message %||% "")[1])
	  if (!nzchar(debug_text)) {
		return(invisible(NULL))
	  }

	  debug_b64 <- base64enc::base64encode(charToRaw(debug_text))

	  payload <- jsonlite::toJSON(
		list(type = "stream_debug", text_b64 = debug_b64),
		auto_unbox = TRUE,
		null = "null"
	  )

	  writeBin(charToRaw(paste0(payload, "\n")), stream_con)
	  flush(stream_con)
	  invisible(NULL)
	}

	summarize_sse_event_shape <- function(event_obj) {
	  safe_names <- function(x) {
		if (is.list(x) && !is.null(names(x))) {
		  paste(names(x), collapse = ",")
		} else {
		  paste0("<", paste(class(x), collapse = "/"), ">")
		}
	  }

	  first_choice <- NULL
	  if (is.list(event_obj) &&
		  !is.null(event_obj$choices) &&
		  is.list(event_obj$choices) &&
		  length(event_obj$choices) > 0) {
		first_choice <- event_obj$choices[[1]]
	  }

	  delta_obj <- if (is.list(first_choice) && !is.null(first_choice$delta)) {
		first_choice$delta
	  } else {
		NULL
	  }

	  message_obj <- if (is.list(first_choice) && !is.null(first_choice$message)) {
		first_choice$message
	  } else {
		NULL
	  }

	  paste0(
		"top=[", safe_names(event_obj), "] ",
		"choice=[", safe_names(first_choice), "] ",
		"delta=[", safe_names(delta_obj), "] ",
		"message=[", safe_names(message_obj), "]"
	  )
	}

	event_buffer <- ""
	accumulated_text <- ""
	accumulated_reasoning <- ""
	accumulated_sources <- NULL

	reasoning_debug_event_count <- 0L
	reasoning_debug_seen <- FALSE

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
		  # fixed=TRUE ile ignore.case birlikte kullanılamaz; Windows VM konsolunda
		  # her SSE parçasında uyarı üretmemesi için iki tarafı da küçük harfe indir.
		  x_lower <- tolower(enc2utf8(x %||% ""))
		  tag_lower <- tolower(enc2utf8(tag %||% ""))

		  pos <- regexpr(tag_lower, x_lower, fixed = TRUE, useBytes = TRUE)[1]
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

    log_info(sprintf(
      "[LLM REQUEST FINAL] path=sse_worker stream=%s payload_model=%s endpoint=%s",
      as.character(body$stream %||% NA),
      as.character(body$model %||% ""),
      api_url
    ))

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
		
		reasoning_debug_event_count <<- reasoning_debug_event_count + 1L

		if (isTRUE(reasoning_debug_enabled) && reasoning_debug_event_count <= 20L) {
		  has_reasoning_now <- nzchar(reasoning_text)
		  has_content_now <- nzchar(delta_text)
		  has_raw_now <- nzchar(raw_delta_text)
		  has_think_tag_now <- grepl("<think>|</think>", raw_delta_text, ignore.case = TRUE, perl = TRUE)

		  event_shape <- tryCatch(
			summarize_sse_event_shape(event_obj),
			error = function(e) paste("shape_error=", conditionMessage(e))
		  )

		  append_stream_debug_line_local(sprintf(
			"[REASONING DEBUG] event=%d content=%s reasoning=%s raw=%s think_tag=%s raw_chars=%d reasoning_chars=%d model=%s | %s",
			reasoning_debug_event_count,
			if (has_content_now) "TRUE" else "FALSE",
			if (has_reasoning_now) "TRUE" else "FALSE",
			if (has_raw_now) "TRUE" else "FALSE",
			if (has_think_tag_now) "TRUE" else "FALSE",
			nchar(raw_delta_text %||% ""),
			nchar(reasoning_text %||% ""),
			selected_model,
			event_shape
		  ))

		  if (isTRUE(has_reasoning_now) && !isTRUE(reasoning_debug_seen)) {
			reasoning_debug_seen <<- TRUE
			append_stream_debug_line_local(sprintf(
			  "[REASONING DEBUG] İlk reasoning parçası yakalandı - chars=%d, model=%s",
			  nchar(reasoning_text),
			  selected_model
			))
		  }
		}

      # Akıl yürütme akışı ayrı kanalla yayınlanır; yanıt metnine karışmaz.
		if (nzchar(reasoning_text)) {
		  accumulated_reasoning <<- paste0(accumulated_reasoning, reasoning_text)

		  # Reasoning metni gerçekten çıkarıldıysa artık capability bayrağına takılmadan
		  # UI kanalına yaz. Capability bayrağı panelin nasıl başlayacağını belirler;
		  # fakat model gerçekten reasoning alanı yayıyorsa bunu bastırmak hatalıdır.
		  append_stream_reasoning_line(
			stream_file = NULL,
			text_value = reasoning_text,
			stream_con = stream_con
		  )
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
		if (isTRUE(reasoning_debug_enabled) &&
			is.null(parsed_event) &&
			reasoning_debug_event_count < 20L) {
		  append_stream_debug_line_local(sprintf(
			"[REASONING DEBUG] parse_null event_text_chars=%d preview=%s",
			nchar(event_text %||% ""),
			substr(gsub("[\r\n\t]+", " ", event_text %||% ""), 1, 220)
		  ))
		}
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

    # Durumlu UTF-8 çözücü: SSE parçaları çoklu baytlı karakterlerin ortasında
    # bölünebilir. Yarım baytlar bir sonraki parçanın başına aktarılır; böylece
    # "input string 1 is invalid UTF-8" hatası akış sırasında üretilmez.
    chunk_decoder <- if (exists("create_utf8_stream_decoder", mode = "function", inherits = TRUE)) {
      create_utf8_stream_decoder()
    } else {
      list(
        decode = function(raw_chunk) decode_utf8_raw_chunk(raw_chunk),
        flush = function() ""
      )
    }

    response_meta <- curl::curl_fetch_stream(
      api_url,
      fun = function(raw_chunk) {
        if (streaming_should_stop(stop_file)) {
          stop("STREAM_ABORTED_BY_USER")
        }

        chunk_text <- tryCatch(
          chunk_decoder$decode(raw_chunk),
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

    # Akış bittikten sonra buffer'da kalan tam baytları işle
    tail_text <- tryCatch(chunk_decoder$flush(), error = function(e) "")
    if (nzchar(tail_text)) {
      event_buffer <- paste0(event_buffer, tail_text)
    }

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