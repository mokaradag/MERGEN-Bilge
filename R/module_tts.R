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
    #'
    #' Removes heavy markdown/code fences and collapses whitespace so the
    #' synthesized speech stays natural and concise.
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
          success = FALSE,
          audio_src = NULL,
          voice = voice %||% NULL,
          duration = 0,
          error = "TTS endpoint is not configured."
        )))
      }

      speech_text <- prepare_tts_text(text)
      if (!nzchar(speech_text)) {
        return(promises::promise_resolve(list(
          success = FALSE,
          audio_src = NULL,
          voice = voice %||% NULL,
          duration = 0,
          error = "TTS text is empty."
        )))
      }

      speech_url <- build_speech_url()
      if (!nzchar(speech_url)) {
        return(promises::promise_resolve(list(
          success = FALSE,
          audio_src = NULL,
          voice = voice %||% NULL,
          duration = 0,
          error = "Invalid TTS endpoint URL."
        )))
      }

      voice_to_use <- voice %||% tts_config$default_voice %||% "tr-female-1"
      api_key <- resolve_tts_api_key()
      timeout_val <- as.numeric(tts_config$timeout_seconds %||% 30)
      if (is.na(timeout_val) || timeout_val <= 0) {
        timeout_val <- 30
      }

      future_promise({
        start_time <- Sys.time()
        library(httr)

        headers <- list(
          `Content-Type` = "application/json",
          Accept = "audio/mpeg"
        )
        if (nzchar(api_key)) {
          headers$Authorization <- paste("Bearer", api_key)
        }

        body <- list(
          model = tts_config$model %||% "tts-1-hd",
          voice = voice_to_use,
          input = speech_text,
          response_format = "mp3"
        )

        resp <- httr::POST(
          url = speech_url,
          httr::add_headers(.headers = headers),
          body = body,
          encode = "json",
          timeout(timeout_val)
        )

        status <- httr::status_code(resp)
        if (status >= 200 && status < 300) {
          content_type <- httr::headers(resp)[["content-type"]] %||% ""

          audio_src <- NULL
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
                audio_src <- paste0("data:audio/mpeg;base64,", b64_str)
              }
            }
          }

          if (is.null(audio_src)) {
            audio_raw <- httr::content(resp, as = "raw")
            audio_b64 <- base64enc::base64encode(audio_raw)
            audio_src <- paste0("data:audio/mpeg;base64,", audio_b64)
          }
          duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

          list(success = TRUE, audio_src = audio_src, voice = voice_to_use,
               duration = duration, error = NULL)
        } else {
          err_msg <- tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"),
                              error = function(e) "TTS request failed.")
          list(success = FALSE, audio_src = NULL, voice = voice_to_use,
               duration = 0, error = paste("TTS hata:", err_msg))
        }
      }) %...!% {
        function(e) {
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
      preload = "none",
      src = audio_src
    )
  )
}