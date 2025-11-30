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
          success = FALSE, audio_src = NULL, voice = voice, duration = 0, error = "TTS endpoint is not configured."
        )))
      }

      speech_text <- prepare_tts_text(text)
      if (!nzchar(speech_text)) {
        return(promises::promise_resolve(list(
          success = FALSE, audio_src = NULL, voice = voice, duration = 0, error = "TTS text is empty."
        )))
      }

      speech_url <- build_speech_url()
      
      # Türkçe: Parametreleri 'future' içine girmeden önce burada yakalıyoruz (Scope fix)
      voice_to_use <- voice %||% tts_config$default_voice %||% "nova"
      api_key      <- resolve_tts_api_key()
      model_to_use <- tts_config$model %||% "tts-1-hd"
      timeout_val  <- as.numeric(tts_config$timeout_seconds %||% 30)
      if (is.na(timeout_val) || timeout_val <= 0) timeout_val <- 30
      
      # Türkçe: SSL ayarını kesinleştiriyoruz. Config yoksa varsayılan FALSE olsun (On-premise rahatlığı için)
      verify_ssl_val <- tts_config$verify_ssl
      should_verify  <- if (is.null(verify_ssl_val)) FALSE else isTRUE(verify_ssl_val)
      
      future_promise({
        start_time <- Sys.time()
        library(httr)

        # Türkçe: Header'ları oluştur
        headers <- c(
          `Content-Type` = "application/json",
          `Authorization` = paste("Bearer", api_key) # API key burada ekleniyor
        )

        # Türkçe: Body oluştur
        body_data <- list(
          model = model_to_use,
          voice = voice_to_use,
          input = speech_text,
          response_format = "mp3" # MP3 formatında iste
        )
        
        # Türkçe: SSL konfigürasyonunu worker içinde taze oluştur (Serialization sorununu önler)
        # Çalışan scriptinizdeki gibi explicit config kullanıyoruz.
        req_config <- if (isTRUE(should_verify)) {
           list() 
        } else {
           httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L)
        }
        
        cat(sprintf("[TTS WORKER] Requesting: %s (Model: %s, Voice: %s)\n", speech_url, model_to_use, voice_to_use))
        
        # Türkçe: İsteği gönder (Senin çalışan kodunla birebir aynı yapı)
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
           return(list(error_obj = e))
        })
        
        # Hata yakalama (bağlantı hatası vb.)
        if (is.list(resp) && !is.null(resp$error_obj)) {
           err_msg <- conditionMessage(resp$error_obj)
           cat(sprintf("[TTS WORKER] ❌ Connection Failed: %s\n", err_msg))
           return(list(success = FALSE, audio_src = NULL, voice = voice_to_use, duration = 0, error = err_msg))
        }

        status <- httr::status_code(resp)
        cat(sprintf("[TTS WORKER] Status Code: %d\n", status))

        if (status >= 200 && status < 300) {
          content_type <- httr::headers(resp)[["content-type"]] %||% ""
          mime_type <- "audio/mpeg"
          if (nzchar(content_type)) {
            # normalize mime without charset/params
            mime_type <- strsplit(content_type, ";", fixed = TRUE)[[1]][1]
          }

          audio_src <- NULL
          # ... (JSON check logic remains same) ...
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

          if (is.null(audio_src)) {
            # Türkçe: Binary (RAW) içeriği al ve base64'e çevir (Çalışan script mantığı)
            audio_raw <- httr::content(resp, as = "raw")
            
            if (length(audio_raw) > 0) {
                # Ensure base64enc is available (it is in global)
                audio_b64 <- base64enc::base64encode(audio_raw)
                audio_src <- paste0("data:", mime_type, ";base64,", audio_b64)
            }
          }

          if (!nzchar(audio_src)) {
            cat("[TTS WORKER] ❌ Empty audio content received.\n")
            return(list(success = FALSE, audio_src = NULL, voice = voice_to_use,
                        duration = 0, error = "Ses yanıtı boş döndü."))
          }
          
          duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
          cat(sprintf("[TTS WORKER] ✅ Success! Audio generated in %.2fs\n", duration))

          list(success = TRUE, audio_src = audio_src, voice = voice_to_use,
               duration = duration, error = NULL)
        } else {
          err_msg <- tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"),
                              error = function(e) "TTS request failed.")
          cat(sprintf("[TTS WORKER] ❌ API Error: %s\n", substr(err_msg, 1, 200)))
          list(success = FALSE, audio_src = NULL, voice = voice_to_use,
               duration = 0, error = paste("TTS hata:", err_msg))
        }
      }) %...!% {
        function(e) {
          cat(sprintf("[TTS WORKER] ❌ Exception: %s\n", conditionMessage(e)))
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
      autoplay = "autoplay", # Türkçe: Otomatik oynatmayı aktif et
      preload = "auto",      # Türkçe: Ön yüklemeyi aç
      src = audio_src
    )
  )
}