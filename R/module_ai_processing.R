# R/module_ai_processing.R
# AI Processing Module - API calls only (Conservative approach)
# This module handles ONLY the LLM API calls, not UI updates

#' AI Processing Server Module
#' @param id Module namespace ID
#' @return List of functions for AI API operations
aiProcessingServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    
    #' Make a non-streaming LLM API call
    #' @param chat_history List of message history
    #' @param current_settings Current app settings
    #' @param model_selected Selected model name
    #' @return A promise that resolves to list(ai_text, duration, success)
    call_llm_non_streaming <- function(chat_history, current_settings, model_selected = NULL) {
      
      start_time_main <- Sys.time()
      
      # Capture immutable copies for worker
      history_copy <- chat_history
      settings_copy <- current_settings
      
      # Get API configuration
      if (is.null(model_selected) || !nzchar(model_selected)) {
        model_selected <- current_settings$model_selection %||% as.character(api_config$local_models[1]) %||% ""
      }
      model_selected <- as.character(model_selected)[1]
      creds <- resolve_local_llm_credentials(model_selected)
      api_endpoint <- creds$endpoint
      if (!nzchar(api_endpoint)) {
        api_endpoint <- "http://localhost:11434/api/generate"
      }
      
	requires_key <- !grepl("(?i)(localhost|127\\.0\\.0\\.1|ollama)", api_endpoint)
	allow_user_key <- isTRUE(creds$allow_user_key)
	api_key_val <- NULL

	if (allow_user_key) {
	  api_key_val <- try({
		sess <- settings_copy$shiny_session
		if (!is.null(sess)) {
		  mb_api_key_get_effective_key_value(
		    session = sess,
		    require_auth = TRUE,
		    allow_default = NULL,
		    clear_on_mismatch = TRUE
		  )
		} else {
		  NULL
		}
	  }, silent = TRUE)

	  if (inherits(api_key_val, "try-error")) {
		api_key_val <- NULL
	  }
	}

	if (is.null(api_key_val) || !nzchar(api_key_val)) {
	  default_key <- creds$default_api_key %||% ""
	  if (nzchar(default_key)) {
			api_key_val <- as.character(default_key)[1]
	  }
	}

	if ((is.null(api_key_val) || !nzchar(api_key_val)) && requires_key) {
	  # Fail fast with a friendly error (promise resolved)
	  return(promises::promise_resolve(list(
			content = NULL,
			duration = 0,
			success = FALSE,
			error = "API anahtarı bulunamadı. Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin."
	  )))
	}
      
	  if (is.null(model_selected) || !nzchar(model_selected)) {
        model_selected <- "mergen-local-model"
      }
	  
	  settings_copy$model_selection <- model_selected
      
      # Create future promise for async processing
		p <- tracked_future_promise(
		  task_fn = function() {
			start_time_worker <- Sys.time()

			library(httr)
			library(jsonlite)

			# Future işçisine gerekli nesneleri açıkça taşı
			ai_text <- call_llm_worker(history_copy, settings_copy, api_endpoint, api_key_val)
			duration <- as.numeric(difftime(Sys.time(), start_time_worker, units = "secs"))

			list(ai_text = ai_text, duration = duration)
		  },
		  task_type = "llm_non_streaming",
		  session_token = session$token,
		  meta = list(
			model = model_selected
		  ),
          globals = list(
            call_llm_worker = call_llm_worker,
            call_local_llm_sse_worker = call_local_llm_sse_worker,
            llm_worker_run_mcp_second_pass = llm_worker_run_mcp_second_pass,
            llm_worker_second_pass_messages = llm_worker_second_pass_messages,
            llm_worker_second_pass_body = llm_worker_second_pass_body,
            llm_worker_second_pass_headers = llm_worker_second_pass_headers,
            llm_worker_second_pass_fallback_response = llm_worker_second_pass_fallback_response,
            llm_worker_call_second_pass_non_streaming = llm_worker_call_second_pass_non_streaming,
            llm_worker_stream_content_looks_like_reasoning = llm_worker_stream_content_looks_like_reasoning,
            format_answer_from_tool_results = format_answer_from_tool_results,
            history_copy = history_copy,
            settings_copy = settings_copy,
            api_endpoint = api_endpoint,
            api_key_val = api_key_val,
            get_local_model_capabilities = get_local_model_capabilities,
            should_omit_temperature = should_omit_temperature,
            should_allow_reasoning_fallback = should_allow_reasoning_fallback,
            apply_model_request_overrides = apply_model_request_overrides,
            normalize_llm_text_node = normalize_llm_text_node,
            extract_first_nonempty_llm_text = extract_first_nonempty_llm_text,
            extract_llm_text_bundle = extract_llm_text_bundle,
            extract_llm_delta_bundle = extract_llm_delta_bundle,
            `%||%` = `%||%`,
            resolve_local_llm_endpoint = resolve_local_llm_endpoint,
            resolve_local_llm_credentials = resolve_local_llm_credentials,
            extract_llm_content_and_sources = extract_llm_content_and_sources,
            normalize_llm_scalar_content = normalize_llm_scalar_content,
            strip_planner_text = strip_planner_text,
            decode_utf8_raw_chunk = decode_utf8_raw_chunk,
            create_utf8_stream_decoder = create_utf8_stream_decoder,
            find_last_utf8_boundary = find_last_utf8_boundary,
            parse_llm_sse_event = parse_llm_sse_event,
            extract_llm_delta_text = extract_llm_delta_text,
            extract_llm_event_sources = extract_llm_event_sources,
            append_stream_delta_line = append_stream_delta_line,
            append_stream_reasoning_line = append_stream_reasoning_line,
            streaming_should_stop = streaming_should_stop,
            log_info = log_info,
            log_warn = log_warn,
            api_config = api_config
          )
		)
      
      # Transform promise to standardized format
      promises::then(p,
		onFulfilled = function(result) {
          # Extract content (list or character) and normalize to scalar string
          ai_content <- if (is.list(result$ai_text)) {
            result$ai_text$content
          } else {
            result$ai_text
          }

          # Normalize to safe scalar string
          if (!is.character(ai_content) || length(ai_content) == 0 || is.na(ai_content[1])) {
            ai_content <- ""
          } else {
            ai_content <- as.character(ai_content)[1]
          }

			# NEW: take chart_store from worker and stash into main session
			charts_from_worker <- if (is.list(result$ai_text)) result$ai_text$chart_store else NULL
			if (!is.null(charts_from_worker) && is.list(charts_from_worker) && length(charts_from_worker) > 0) {
			  store <- session$userData$chart_store %||% list()
			  for (nm in names(charts_from_worker)) {
				store[[nm]] <- charts_from_worker[[nm]]
			  }
			  session$userData$chart_store <- store
			}

			response_duration <- if (is.list(result$ai_text)) {
			  result$ai_text$duration
			} else {
			  result$duration
			}

			# Düşünen modellerin non-streaming yanıtlarında akıl yürütme metni
			# varsa, üst katmana aktarılarak MB_Messages.ReasoningContent
			# sütununa kaydedilmesi sağlanır.
			reasoning_from_worker <- if (is.list(result$ai_text)) result$ai_text$reasoning_content else NULL
			if (is.null(reasoning_from_worker) || !nzchar(as.character(reasoning_from_worker)[1] %||% "")) {
			  reasoning_from_worker <- NULL
			}

			return(list(
			  content = ai_content,
			  duration = response_duration,
			  success = TRUE,
			  error = NULL,
			  chart_store = charts_from_worker %||% list(),
			  reasoning_content = reasoning_from_worker
			))
        },
		onRejected = function(error) {
		  cat("[AI MODULE] Non-streaming request FAILED:", error$message, "\n")
		  duration <- as.numeric(difftime(Sys.time(), start_time_main, units = "secs"))

		  em <- as.character(error$message)
		  error_msg <- if (is.character(em) && length(em) > 0 && !is.na(em[1])) em[1] else ""

		  if (!nzchar(error_msg) || grepl("^AUTH_MISSING_KEY", error_msg)) {
			display_msg <- "API anahtarı eksik. Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin."
		  } else if (grepl("RATE_LIMIT", error_msg)) {
			display_msg <- "Çok fazla istek gönderildi. Lütfen birkaç dakika bekleyin."
		  } else if (grepl("AUTH_ERROR", error_msg)) {
			display_msg <- "API kimlik doğrulama hatası. Lütfen yöneticinize başvurun."
		  } else if (grepl("SERVICE_UNAVAILABLE", error_msg)) {
			display_msg <- "AI servisi geçici olarak kullanılamıyor. Lütfen daha sonra tekrar deneyin."
		  } else if (grepl("CONNECTION_ERROR", error_msg)) {
			display_msg <- "AI servisine bağlanılamadı. İnternet bağlantınızı kontrol edin."
		  } else if (grepl("TIMEOUT|408", error_msg)) {
			# 408 = sunucu timeout'u, client timeout değil
			display_msg <- "İstek zaman aşımına uğradı. Veri çok büyük olabilir. Lütfen daha spesifik bir soru sorun veya filtre ekleyin."
		  } else {
			display_msg <- "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin."
		  }

		  return(list(content = NULL, duration = duration, success = FALSE, error = display_msg))
		}
      ) %...!% (function(e) {
          # onFulfilled/onRejected içinde oluşan hataları yakala
          log_error_with_context(e, "AI_MODULE_NON_STREAM_THEN")
          try(showNotification(paste("AI hatası:", conditionMessage(e)), type = "error"), silent = TRUE)
          list(content = NULL, duration = as.numeric(difftime(Sys.time(), start_time_main, units = "secs")),
               success = FALSE, error = "İşleme sırasında bir hata oluştu.")
      })
    }
    
    #' Make a streaming LLM API call (returns full text, caller handles streaming UI)
    #' @param chat_history List of message history
    #' @param current_settings Current app settings  
    #' @param model_selected Selected model name
    #' @return A promise that resolves to list(ai_text, duration, success)
    call_llm_streaming <- function(chat_history, current_settings, model_selected = NULL) {
      
      start_time <- Sys.time()
      
      # Capture immutable copies
      history_copy <- chat_history
      settings_copy <- current_settings
      
      if (is.null(model_selected) || model_selected == "") {
        model_selected <- api_config$local_models[1]
      }
	  
	  creds <- resolve_local_llm_credentials(model_selected)
      api_endpoint <- creds$endpoint
      requires_key <- !grepl("(?i)(localhost|127\\.0\\.0\\.1|ollama)", api_endpoint)
	  allow_user_key <- isTRUE(creds$allow_user_key)
      
      # Set model in settings
      settings_for_llm <- settings_copy
      settings_for_llm$model_selection <- model_selected
	  
	# Fail fast if API key is missing (streaming path) ===
	api_key_val <- NULL
	if (allow_user_key) {
	  api_key_val <- try({
		sess <- settings_for_llm$shiny_session
		if (!is.null(sess)) {
		  mb_api_key_get_effective_key_value(
		    session = sess,
		    require_auth = TRUE,
		    allow_default = NULL,
		    clear_on_mismatch = TRUE
		  )
		} else {
		  NULL
		}
	  }, silent = TRUE)

	  if (inherits(api_key_val, "try-error")) {
		api_key_val <- NULL
	  }
	}

	if (is.null(api_key_val) || !nzchar(api_key_val)) {
	  default_key <- creds$default_api_key %||% ""
	  if (nzchar(default_key)) {
			api_key_val <- as.character(default_key)[1]
	  }
	}

	if (!is.null(api_key_val) && nzchar(api_key_val)) {
	  settings_for_llm$api_key_override <- as.character(api_key_val)[1]
	}

	if ((is.null(api_key_val) || !nzchar(api_key_val)) && requires_key) {
	  return(promises::promise_resolve(list(
			content = NULL,
			duration = 0,
			success = FALSE,
			error = "API anahtarı eksik. Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin."
	  )))
	}
      
      # Create future promise
		p <- tracked_future_promise(
		  task_fn = function() {
			tryCatch({
			  ai_text <- call_llm_with_retry(history_copy, settings_for_llm)
			  duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
			  list(ai_text = ai_text, duration = duration, error = FALSE)
			}, error = function(e) {
			  list(error = TRUE, message = e$message)
			})
		  },
		  task_type = "llm_streaming",
		  session_token = session$token,
		  meta = list(
			model = model_selected
		  )
		)
      
      # Transform to standardized format
      promises::then(
        p,
        onFulfilled = function(res) {
			if (isTRUE(res$error)) {
			  cat("[AI MODULE] Streaming request FAILED:", res$message, "\n")

			  # Robust extraction (avoid length-0 grepl/if crash)
			  err_raw  <- res$message
			  error_msg <- if (is.character(err_raw) && length(err_raw) > 0 && !is.na(err_raw[1])) err_raw[1] else ""

			  if (!nzchar(error_msg) || grepl("^AUTH_MISSING_KEY", error_msg)) {
				display_msg <- "API anahtarı eksik. Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin."
			  } else if (grepl(":", error_msg)) {
				display_msg <- sub("^[A-Z_]+:\\s*", "", error_msg)
			  } else {
				display_msg <- error_msg
				if (!nzchar(display_msg)) {
				  display_msg <- "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin."
				}
			  }

			  return(list(
				content = NULL,
				duration = NULL,
				success = FALSE,
				error = display_msg
			  ))
			} else {
            cat("[AI MODULE] Streaming request completed\n")

            # Extract + normalize to scalar string
            msg <- if (is.list(res$ai_text)) res$ai_text$content %||% "" else res$ai_text %||% ""
            if (!is.character(msg) || length(msg) == 0 || is.na(msg[1])) {
              msg <- ""
            } else {
              msg <- as.character(msg)[1]
            }
            cat("[AI MODULE] stream content_nchar=", nchar(msg), "\n", sep = "")

            # Choose duration from inner list if present
            duration_val <- if (is.list(res$ai_text) && !is.null(res$ai_text$duration)) {
              res$ai_text$duration
            } else {
              res$duration
            }

            return(list(
              content = msg,
              duration = duration_val,
              success = TRUE,
              error = NULL
            ))
          }
        },
		onRejected = function(err) {
		  cat("[AI MODULE] Streaming request REJECTED:", err$message, "\n")

		  em <- as.character(conditionMessage(err))
		  error_msg <- if (is.character(em) && length(em) > 0 && !is.na(em[1])) em[1] else ""

		  if (!nzchar(error_msg) || grepl("^AUTH_MISSING_KEY", error_msg)) {
			display_msg <- "API anahtarı eksik. Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin."
		  } else if (grepl(":", error_msg)) {
			display_msg <- sub("^[A-Z_]+:\\s*", "", error_msg)
		  } else {
			display_msg <- error_msg
			if (!nzchar(display_msg)) {
			  display_msg <- "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin."
			}
		  }

		  return(list(
			content = NULL,
			duration = NULL,
			success = FALSE,
			error = display_msg
		  ))
		}
      ) %...!% (function(e) {
          log_error_with_context(e, "AI_MODULE_STREAM_THEN")
          try(showNotification(paste("AI hatası:", conditionMessage(e)), type = "error"), silent = TRUE)
          list(content = NULL, duration = NULL, success = FALSE,
               error = "İşleme sırasında bir hata oluştu.")
      })
    }
    
    # Return public interface
    return(list(
      call_llm_non_streaming = call_llm_non_streaming,
      call_llm_streaming = call_llm_streaming
    ))
  })
}