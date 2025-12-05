# R/module_stt.R

sttUI <- function(id) {
  ns <- NS(id)
  tagList(
    # Client-side dependency is loaded in ui.R via tags$script/link
    uiOutput(ns("stt_modal_container"))
  )
}

sttServer <- function(id, parent_session) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Reactive values
    rv <- reactiveValues(
      transcription_history = "",
      current_text = "",
      is_recording = FALSE
    )
    
    # Return value for the main app
    final_text <- reactiveVal("")
    
    # Trigger to open modal
    start_session <- function() {
      rv$transcription_history <- ""
      rv$current_text <- ""
      rv$is_recording <- TRUE
      
      showModal(modalDialog(
        id = ns("stt_modal"),
        title = tags$div(
          class = "stt-modal-header",
          tags$i(class = "fas fa-microphone-lines"),
          span("Sesli Giriş (Canlı Deşifre)", style = "margin-left: 10px;")
        ),
        footer = NULL, # Custom footer defined in body
        size = "l",
        easyClose = FALSE,
        fade = TRUE,
        class = "stt-modal-dialog", # Custom class for CSS targeting
        
        div(
          class = "stt-modal-body",
          
          # Visualizer Container
          div(
            class = "stt-visualizer-container",
            tags$canvas(id = ns("visualizer_canvas"), width = "600", height = "150")
          ),
          
          # Status Indicator
          div(id = ns("stt_status"), class = "stt-status recording", "Dinliyor..."),
          
          # Transcription Editor
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
          
          # Controls
          div(
            class = "stt-controls",
            # Left: Stop/Record Toggle
            div(
              class = "stt-controls-left",
              actionButton(ns("toggle_record_btn"), "Durdur", icon = icon("stop"), class = "btn-stt-record recording")
            ),
            # Right: Action Buttons
            div(
              class = "stt-controls-right",
              actionButton(ns("dismiss_btn"), "İptal", icon = icon("times"), class = "btn-stt-secondary"),
              actionButton(ns("accept_btn"), "Onayla ve Gönder", icon = icon("check"), class = "btn-stt-primary")
            )
          )
        )
      ))
      
      # Initialize JS logic after modal is shown
      shinyjs::delay(500, {
        session$sendCustomMessage("initSTT", list(
          canvasId = ns("visualizer_canvas"),
          nsPrefix = id
        ))
      })
    }
    
    # Stop Recording/Start Recording Toggle
    observeEvent(input$toggle_record_btn, {
      if (rv$is_recording) {
        # Stop
        rv$is_recording <- FALSE
        updateActionButton(session, "toggle_record_btn", label = "Devam Et", icon = icon("microphone"), class = "btn-stt-record paused")
        shinyjs::runjs(sprintf("window.STT_Client.stopRecording('%s');", id))
        shinyjs::runjs(sprintf("$('#%s').text('Duraklatıldı').removeClass('recording').addClass('paused');", ns("stt_status")))
      } else {
        # Resume
        rv$is_recording <- TRUE
        updateActionButton(session, "toggle_record_btn", label = "Durdur", icon = icon("stop"), class = "btn-stt-record recording")
        shinyjs::runjs(sprintf("window.STT_Client.startRecording('%s');", id))
        shinyjs::runjs(sprintf("$('#%s').text('Dinliyor...').removeClass('paused').addClass('recording');", ns("stt_status")))
      }
    })
    
    # Handle incoming Audio Chunks
    observeEvent(input$audio_chunk, {
      req(input$audio_chunk)
      
      # 1. Decode Base64 to WebM
      audio_binary <- tryCatch(
        base64enc::base64decode(input$audio_chunk),
        error = function(e) return(NULL)
      )
      req(audio_binary)
      
      input_file <- tempfile(fileext = ".webm")
      wav_file <- tempfile(fileext = ".wav")
      writeBin(audio_binary, input_file)
      
      tryCatch({
        # 2. Convert to WAV (16kHz mono) for Whisper compatibility
        av::av_audio_convert(input_file, wav_file, format = "wav", sample_rate = 16000, channels = 1)
        
        # 3. Call Local Whisper API
        # Using configuration from global.R
        res <- httr::POST(
          url = stt_config$endpoint,
          httr::add_headers(Authorization = paste("Bearer", stt_config$api_key)),
          body = list(
            file = httr::upload_file(wav_file, type = "audio/wav"),
            model = stt_config$model,
            language = "tr",       # Force Turkish context
            temperature = 0.0      # Deterministic
          ),
          encode = "multipart",
          httr::timeout(10)
        )
        
        if (httr::status_code(res) == 200) {
          content_json <- httr::content(res, as = "text", encoding = "UTF-8")
          parsed <- jsonlite::fromJSON(content_json)
          text_segment <- parsed$text
          
          if (!is.null(text_segment) && nzchar(text_segment)) {
            # Ensure correct encoding
            Encoding(text_segment) <- "UTF-8"
            
            # Append to history and update UI
            # We add a space if history isn't empty
            sep <- if (nzchar(rv$transcription_history)) " " else ""
            rv$transcription_history <- paste0(rv$transcription_history, sep, text_segment)
            
            # Update the text area without resetting user's manual edits if possible.
            # However, for live sync, we usually append. 
            # Ideally, we read current input value and append.
            current_ui_val <- input$transcribed_text
            new_val <- if (nzchar(current_ui_val)) paste(current_ui_val, text_segment) else text_segment
            
            updateTextAreaInput(session, "transcribed_text", value = new_val)
          }
        }
        
      }, error = function(e) {
        cat("[STT ERROR]", conditionMessage(e), "\n")
      }, finally = {
        if (file.exists(input_file)) unlink(input_file)
        if (file.exists(wav_file)) unlink(wav_file)
      })
    })
    
    # Accept
    observeEvent(input$accept_btn, {
      shinyjs::runjs(sprintf("window.STT_Client.stopAndCleanup('%s');", id))
      text_to_send <- trimws(input$transcribed_text)
      removeModal()
      if (nzchar(text_to_send)) {
        final_text(text_to_send)
      }
    })
    
    # Dismiss
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