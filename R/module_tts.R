# R/module_tts.R
# Text-to-Speech (TTS) processing module (OpenAI-compatible)

#' TTS Processing Server Module
#'
#' Provides an asynchronous helper for converting text into speech using
#' an OpenAI-compatible `/audio/speech` endpoint. Returns base64-encoded
#' audio URLs that can be injected into the chat UI without additional
#' static hosting.
ttsProcessingServer <- function(id) {
  moduleServer(id, function(input, output, session) {

    #' Whether TTS is available (endpoint configured)
    tts_available <- function() {
      endpoint <- tts_config$base_url %||% ""
      nzchar(endpoint)
    }

    #' Normalize text before sending to TTS
    prepare_tts_text <- function(text) {
      if (!is.character(text) || length(text) == 0) return("")

      cleaned <- as.character(text[1])
      cleaned <- gsub("```[\\s\\S]*?```", " ", cleaned)       # remove code blocks
      cleaned <- gsub("`([^`]*)`", "\\1", cleaned)              # inline code
      cleaned <- gsub("\u3010[^\u3011]+\u3011", " ", cleaned)   # wipe bracketed refs
      cleaned <- gsub("\n+", " ", cleaned)
      cleaned <- gsub("[[:space:]]+", " ", cleaned)
      cleaned <- gsub("[[]([^]]*)[]]\\(([^)]*)\\)", "\\1", cleaned, perl = TRUE)  # links
      cleaned <- gsub("[#>*_-]+", " ", cleaned)
      trimws(cleaned)
    }

    #' Build the final speech endpoint URL
    build_speech_url <- function() {
      base <- tts_config$base_url %||% ""
      if (!nzchar(base)) return("")
      base <- sub("/+$", "", base)
      if (grepl("/audio/speech$", base, ignore.case = TRUE)) {
        return(base)
      }
      paste0(base, "/audio/speech")
    }

    #' Resolve API key for the TTS endpoint
    resolve_tts_api_key <- function() {
      user_key <- tryCatch({
        sess_key <- session$userData$ai_api_key %||% NULL
        if (is.null(sess_key) || !nzchar(sess_key)) return(NULL)
        as.character(sess_key)[1]
      }, error = function(e) NULL)

      if (!is.null(user_key) && nzchar(user_key)) {
        return(user_key)
      }

      default_key <- tts_config$api_key %||% ""
      if (is.null(default_key) || is.na(default_key)) default_key <- ""
      default_key
    }

    #' Asynchronously synthesize speech
    #' @return promise resolving to list(success, audio_src, voice, duration, error)
    synthesize_speech <- function(text, voice = NULL) {
      if (!tts_available()) {
        return(promises::promise_resolve(list(
          success = FALSE, audio_src = NULL, voice = voice, duration = 0, error = "TTS endpoint is not configured."
        )))
      }

      speech_text <- prepare_tts_text(text)
      if (!nzchar(speech_text)) {
        return(promises::promise_resolve(list(
          success = FALSE, audio_src = NULL, voice = voice, duration = 0, error = "TTS text is empty."
        )))
      }

      # --- MAIN PROCESS VARIABLES (Capture before future) ---
      speech_url   <- build_speech_url()
      voice_to_use <- voice %||% tts_config$default_voice %||% "nova"
      api_key      <- resolve_tts_api_key()
      model_to_use <- tts_config$model %||% "tts-1"
      timeout_val  <- as.numeric(tts_config$timeout_seconds %||% 30)
      if (is.na(timeout_val) || timeout_val <= 0) timeout_val <- 30
      
      verify_ssl_val <- tts_config$verify_ssl
      should_verify  <- if (is.null(verify_ssl_val)) FALSE else isTRUE(verify_ssl_val)
      
      # Log file path (absolute to avoid working dir confusion in workers)
      debug_log_file <- normalizePath(file.path("logs", "tts_debug.txt"), mustWork = FALSE)
      if (!file.exists(dirname(debug_log_file))) dir.create(dirname(debug_log_file), recursive = TRUE)

      # --- ASYNC WORKER START ---
      future_promise({
        start_time <- Sys.time()
        
        # -- Worker Side Logging Helper --
        worker_log <- function(msg) {
          try({
            cat(sprintf("[%s] [Worker-%s] %s\n", 
                        format(Sys.time(), "%H:%M:%S"), 
                        Sys.getpid(), 
                        msg), 
                file = debug_log_file, append = TRUE)
          }, silent = TRUE)
        }

        worker_log(sprintf("INIT: URL=%s | Model=%s | Voice=%s", speech_url, model_to_use, voice_to_use))

        # Explicitly load libraries in the worker process
        library(httr)
        library(jsonlite)
        library(base64enc)

        # Header Setup
        headers <- c(
          `Content-Type` = "application/json",
          `Authorization` = paste("Bearer", api_key)
        )

        # Body Setup
        body_data <- list(
          model = model_to_use,
          voice = voice_to_use,
          input = speech_text,
          response_format = "mp3"
        )
        
        # Config Setup (SSL Bypass if needed)
        req_config <- if (isTRUE(should_verify)) {
           list() 
        } else {
           httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L)
        }
        
        worker_log("SENDING POST Request...")
        
        # Execute Request
        resp <- tryCatch({
          httr::POST(
            url = speech_url,
            httr::add_headers(.headers = headers),
            body = body_data,
            encode = "json",
            timeout(timeout_val),
            req_config 
          )
        }, error = function(e) {
           worker_log(sprintf("FATAL ERROR in POST: %s", conditionMessage(e)))
           return(list(error_obj = e))
        })
        
        # Handle Connection Errors
        if (is.list(resp) && !is.null(resp$error_obj)) {
           err_msg <- conditionMessage(resp$error_obj)
           return(list(success = FALSE, audio_src = NULL, voice = voice_to_use, duration = 0, error = err_msg))
        }

        status <- httr::status_code(resp)
        worker_log(sprintf("RESPONSE Status: %d", status))

        if (status >= 200 && status < 300) {
          content_type <- httr::headers(resp)[["content-type"]] %||% ""
          mime_type <- "audio/mpeg"
          if (nzchar(content_type)) {
            mime_type <- strsplit(content_type, ";", fixed = TRUE)[[1]][1]
          }

          audio_src <- NULL
          # Check for JSON wrapper (rare but possible)
          if (grepl("json", content_type, ignore.case = TRUE)) {
            parsed <- tryCatch(httr::content(resp, as = "parsed", encoding = "UTF-8"),
                               error = function(e) NULL)
            b64 <- NULL
            if (is.list(parsed)) {
              if (!is.null(parsed$audio)) b64 <- parsed$audio
              else if (!is.null(parsed$data)) b64 <- parsed$data
              else if (!is.null(parsed$content)) b64 <- parsed$content
            }
            if (!is.null(b64) && nzchar(as.character(b64)[1])) {
              b64_str <- as.character(b64)[1]
              if (startsWith(b64_str, "data:")) {
                audio_src <- b64_str
              } else {
                audio_src <- paste0("data:", mime_type, ";base64,", b64_str)
              }
            }
          }

          # Standard Binary Response
          if (is.null(audio_src)) {
            audio_raw <- httr::content(resp, as = "raw")
            worker_log(sprintf("BINARY CONTENT: %d bytes received", length(audio_raw)))
            
            if (length(audio_raw) > 0) {
                audio_b64 <- base64enc::base64encode(audio_raw)
                audio_src <- paste0("data:", mime_type, ";base64,", audio_b64)
            }
          }

          if (!nzchar(audio_src)) {
            worker_log("FAIL: Empty audio content.")
            return(list(success = FALSE, audio_src = NULL, voice = voice_to_use,
                        duration = 0, error = "Ses yanıtı boş döndü."))
          }
          
          duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
          worker_log("SUCCESS: Audio encoded and ready.")

          list(success = TRUE, audio_src = audio_src, voice = voice_to_use,
               duration = duration, error = NULL)
        } else {
          err_msg <- tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"),
                              error = function(e) "TTS request failed.")
          worker_log(sprintf("API FAIL: %s", substr(err_msg, 1, 100)))
          list(success = FALSE, audio_src = NULL, voice = voice_to_use,
               duration = 0, error = paste("TTS hata:", err_msg))
        }
      }) %...!% {
        function(e) {
          # Log unhandled exceptions in the future
          try({
             cat(sprintf("[%s] [Worker-ERR] %s\n", format(Sys.time(), "%H:%M:%S"), conditionMessage(e)), 
                 file = normalizePath(file.path("logs", "tts_debug.txt"), mustWork = FALSE), append = TRUE)
          }, silent = TRUE)
          
          list(success = FALSE, audio_src = NULL, voice = voice_to_use,
               duration = 0, error = conditionMessage(e))
        }
      }
    }

    list(
      synthesize_speech = synthesize_speech,
      tts_available = tts_available,
      prepare_tts_text = prepare_tts_text
    )
  })
}

#' Build a reusable audio player UI snippet for a chat message
build_tts_audio_ui <- function(message_id, audio_src, voice = NULL) {
  if (is.null(audio_src) || !nzchar(audio_src)) return(NULL)

  label <- if (!is.null(voice) && nzchar(voice)) {
    paste("Ses:", voice)
  } else {
    "Sesli Yanıt"
  }

  div(
    id = paste0("tts_audio_", message_id),
    class = "tts-audio-wrapper",
    div(
      class = "tts-audio-header",
      tags$i(class = "fas fa-volume-up"),
      span(label)
    ),
	tags$audio(
      controls = "controls",
      autoplay = "autoplay",
      preload = "auto",
      src = audio_src
    )
  )
}