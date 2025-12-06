# R/module_stt.R

sttUI <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("stt_modal_container"))
  )
}

sttServer <- function(id, parent_session) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    rv <- reactiveValues(
      transcription_history = "",
      is_recording = FALSE
    )
    
    final_text <- reactiveVal("")
    
    start_session <- function() {
      rv$transcription_history <- ""
      rv$is_recording <- TRUE
      
      showModal(modalDialog(
        id = ns("stt_modal"),
        title = tags$div(
          class = "stt-modal-header",
          tags$i(class = "fas fa-microphone-lines"),
          span("Sesli Giriş (Canlı Deşifre)", style = "margin-left: 10px;")
        ),
        footer = NULL, 
        size = "l",
        easyClose = FALSE,
        fade = TRUE,
        class = "stt-modal-dialog",
        
        div(
          class = "stt-modal-body",
          
          div(
            class = "stt-visualizer-container",
            tags$canvas(id = ns("visualizer_canvas"), width = "600", height = "150")
          ),
          
          div(id = ns("stt_status"), class = "stt-status recording", "Dinliyor..."),
          
          div(
            class = "stt-editor-container",
            textAreaInput(
              ns("transcribed_text"), 
              label = NULL, 
              value = "", 
              placeholder = "Konuşmanız burada metne dökülecek...", 
              width = "100%", 
              rows = 6,
              resize = "vertical"
            )
          ),
          
          div(
            class = "stt-controls",
            div(
              class = "stt-controls-left",
              actionButton(ns("toggle_record_btn"), "Durdur", icon = icon("stop"), class = "btn-stt-record recording")
            ),
            div(
              class = "stt-controls-right",
              actionButton(ns("dismiss_btn"), "İptal", icon = icon("times"), class = "btn-stt-secondary"),
              actionButton(ns("accept_btn"), "Onayla ve Gönder", icon = icon("check"), class = "btn-stt-primary")
            )
          )
        )
      ))
      
      shinyjs::delay(500, {
        session$sendCustomMessage("initSTT", list(
          canvasId = ns("visualizer_canvas"),
          nsPrefix = id
        ))
      })
    }
    
    observeEvent(input$toggle_record_btn, {
      if (rv$is_recording) {
        rv$is_recording <- FALSE
        updateActionButton(session, "toggle_record_btn", label = "Devam Et", icon = icon("microphone"))
        shinyjs::runjs(sprintf("$('#%s').removeClass('recording').addClass('paused');", ns("toggle_record_btn")))
        shinyjs::runjs(sprintf("window.STT_Client.stopRecording('%s');", id))
        shinyjs::runjs(sprintf("$('#%s').text('Duraklatıldı').removeClass('recording').addClass('paused');", ns("stt_status")))
      } else {
        rv$is_recording <- TRUE
        updateActionButton(session, "toggle_record_btn", label = "Durdur", icon = icon("stop"))
        shinyjs::runjs(sprintf("$('#%s').removeClass('paused').addClass('recording');", ns("toggle_record_btn")))
        shinyjs::runjs(sprintf("window.STT_Client.startRecording('%s');", id))
        shinyjs::runjs(sprintf("$('#%s').text('Dinliyor...').removeClass('paused').addClass('recording');", ns("stt_status")))
      }
    })
    
	observeEvent(input$audio_chunk, {
	  req(input$audio_chunk)
	  
	  api_url <- Sys.getenv("LOCAL_STT_ENDPOINT", "http://localhost:8080/v1/audio/transcriptions")
	  api_model <- Sys.getenv("LOCAL_STT_MODEL", "whisper-large-v3")
	  api_key <- Sys.getenv("LOCAL_STT_API_KEY", "")
	  
	  if (!nzchar(api_key)) {
		api_key <- session$userData$ai_api_key
	  }
	  if (!nzchar(api_key)) {
		cat("[STT] HATA: API anahtarı bulunamadı!\n")
		return(NULL)
	  }
	  api_key <- trimws(api_key)
      
      # 1. Decode
      audio_binary <- tryCatch(
        base64enc::base64decode(input$audio_chunk),
        error = function(e) { return(NULL) }
      )
      req(audio_binary)
      
      input_file <- tempfile(fileext = ".webm")
      wav_file <- tempfile(fileext = ".wav")
      writeBin(audio_binary, input_file)
      
      tryCatch({
        # 2. Convert
        av::av_audio_convert(input_file, wav_file, format = "wav", sample_rate = 16000, channels = 1)
        
        # Check size (silence filtering)
        if (file.size(wav_file) < 1000) return(NULL)

        # 3. Call API
        # MATCHING WORKING TEST CODE EXACTLY
        body_params <- list(
          file = httr::upload_file(wav_file, type = "audio/wav"),
          model = api_model,
          language = "tr",
          task = "transcribe"
        )
        
        # --- CRITICAL DEBUG PRINT ---
        cat("------------------------------------------------\n")
        cat("[STT Request]\n")
        cat("URL:", api_url, "\n")
        cat("API Key Length:", nchar(api_key), "\n") # If this is 0, the request will fail
        cat("Model:", api_model, "\n")
        cat("File Size:", file.size(wav_file), "bytes\n")
        cat("------------------------------------------------\n")
        
        res <- httr::POST(
          url = api_url,
          add_headers(Authorization = paste("Bearer", api_key)),
          body = body_params,
          encode = "multipart",
          timeout(10)
        )
        
        if (httr::status_code(res) == 200) {
          content_json <- httr::content(res, as = "text", encoding = "UTF-8")
          parsed <- jsonlite::fromJSON(content_json)
          text_segment <- parsed$text
          
          if (!is.null(text_segment) && nzchar(text_segment)) {
            Encoding(text_segment) <- "UTF-8"
            cat("[STT] Success:", text_segment, "\n")
            
            current_ui_val <- input$transcribed_text
            sep <- if (nzchar(current_ui_val) && !grepl("\\s$", current_ui_val)) " " else ""
            new_val <- paste0(current_ui_val, sep, text_segment)
            
            updateTextAreaInput(session, "transcribed_text", value = new_val)
          }
        } else {
          cat("[STT API Error] Status:", httr::status_code(res), "\n")
          cat("Response Body:", httr::content(res, "text", encoding="UTF-8"), "\n")
        }
        
      }, error = function(e) {
        cat("[STT Processing Error]", conditionMessage(e), "\n")
      }, finally = {
        if (file.exists(input_file)) unlink(input_file)
        if (file.exists(wav_file)) unlink(wav_file)
      })
    })
    
    observeEvent(input$accept_btn, {
      shinyjs::runjs(sprintf("window.STT_Client.stopAndCleanup('%s');", id))
      text_to_send <- trimws(input$transcribed_text)
      removeModal()
      if (nzchar(text_to_send)) {
        final_text(text_to_send)
      }
    })
    
    observeEvent(input$dismiss_btn, {
      shinyjs::runjs(sprintf("window.STT_Client.stopAndCleanup('%s');", id))
      removeModal()
    })
    
    return(list(
      start_session = start_session,
      final_text = final_text
    ))
  })
}