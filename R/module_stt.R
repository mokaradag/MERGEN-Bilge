# R/module_stt.R

sttUI <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("stt_modal_container"))
  )
}

sttServer <- function(id, parent_session, settings) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    rv <- reactiveValues(
      transcription_history = "",
      is_recording = FALSE,
      accept_chunks = FALSE # Kilit mekanizması
    )
    
    final_text <- reactiveVal("")
    
    start_session <- function() {
      rv$transcription_history <- ""
      rv$is_recording <- TRUE
      rv$accept_chunks <- TRUE
      
      # 1. Ayarlardan Karakter Bilgisini Al
      chars <- tryCatch(get_characters_data(), error = function(e) NULL)
      selected_id <- "mergen"
      if (!is.null(settings$selected_character)) {
        selected_id <- settings$selected_character
      }
      
      char_info <- NULL
      if (!is.null(chars) && !is.null(chars$styles)) {
        for (c in chars$styles) {
          if (c$id == selected_id) {
            char_info <- c
            break
          }
        }
        if (is.null(char_info)) char_info <- chars$styles[[1]]
      } else {
        # Fallback
        char_info <- list(
          display_name = "MERGEN", 
          image = "img/mergen_avatar.png", # Varsayılan yolunuz neyse
          accent = "#7C4DFF"
        )
      }
      
      # 2. Font Boyutu Sınıfını Belirle
      current_font <- settings$font_size %||% "medium"
      font_class <- switch(current_font,
                           "small" = "stt-font-small",
                           "medium" = "stt-font-medium",
                           "large" = "stt-font-large",
                           "xlarge" = "stt-font-xlarge",
                           "stt-font-medium")
      
      showModal(modalDialog(
        id = ns("stt_modal"),
        # Başlık revizyonu: Daha sade, font uyumlu
        title = tags$div(
          class = "stt-modal-header",
          tags$i(class = "fas fa-microphone-lines", style = "color: #7C4DFF;"),
          span("Sesli İletişim", style = "margin-left: 12px; font-family: 'Segoe UI', sans-serif; letter-spacing: 0.5px;")
        ),
        footer = NULL, 
        size = "l",
        easyClose = FALSE,
        fade = TRUE,
        class = "stt-modal-dialog",
        
        div(
          class = "stt-modal-body",
          
          # --- YENİ GÖRSELLEŞTİRİCİ ALANI ---
          div(
            class = "stt-visualizer-wrapper",
            
            # Sol: Modern Dalga Formu
            div(
              class = "stt-vis-canvas-container",
              tags$canvas(id = ns("visualizer_canvas"), width = "500", height = "120")
            ),
            
            # Sağ: Karakter Bilgi Paneli (Boşluğu doldurur)
            div(
              class = "stt-vis-info-panel",
              div(
                class = "stt-char-badge",
                tags$img(src = char_info$image, class = "stt-avatar"),
                div(
                  class = "stt-char-text",
                  div(class = "stt-char-name", char_info$display_name),
                  div(class = "stt-char-status", "Dinliyorum...")
                )
              ),
              # Teknik veriler
              div(
                class = "stt-tech-stats",
                div(id = ns("stt_timer"), class = "stt-stat-item", icon("clock"), "00:00"),
                div(id = ns("stt_db_indicator"), class = "stt-stat-item", icon("wave-square"), "-Inf dB")
              )
            )
          ),
          
          div(id = ns("stt_status"), class = "stt-status recording", "Mikrofon Açık"),
          
          # --- METİN ALANI ---
          div(
            class = "stt-editor-container",
            div(class = font_class, # Font sınıfı buraya uygulanır
                textAreaInput(
                  ns("transcribed_text"), 
                  label = NULL, 
                  value = "", 
                  placeholder = "Konuşmanız burada metne dönüşecek...", 
                  width = "100%", 
                  rows = 6,
                  resize = "vertical"
                )
            )
          ),
          
          # --- KONTROLLER ---
          div(
            class = "stt-controls",
            div(
              class = "stt-controls-left",
              # Temizle Butonu
              actionButton(ns("clear_btn"), "Temizle", icon = icon("trash-can"), class = "btn-stt-clear"),
              # Durdur/Devam Et
              actionButton(ns("toggle_record_btn"), "Durdur", icon = icon("stop"), class = "btn-stt-record recording")
            ),
            div(
              class = "stt-controls-right",
              # İptal (Kırmızı)
              actionButton(ns("dismiss_btn"), "İptal", icon = icon("xmark"), class = "btn-stt-cancel"),
              # Onayla (Yeşil)
              actionButton(ns("accept_btn"), "Onayla ve Gönder", icon = icon("paper-plane"), class = "btn-stt-confirm")
            )
          )
        )
      ))
      
      # JS Client'ı başlat
      shinyjs::delay(500, {
        session$sendCustomMessage("initSTT", list(
          canvasId = ns("visualizer_canvas"),
          timerId = ns("stt_timer"),
          dbId = ns("stt_db_indicator"),
          nsPrefix = id,
          accentColor = char_info$accent %||% "#7C4DFF"
        ))
      })
    }
    
    # Temizle Butonu
    observeEvent(input$clear_btn, {
      updateTextAreaInput(session, "transcribed_text", value = "")
    })
    
    observeEvent(input$toggle_record_btn, {
      if (rv$is_recording) {
        # --- DURDURMA İŞLEMİ ---
        rv$is_recording <- FALSE
        rv$accept_chunks <- FALSE # KİLİT: Artık gelen hiç bir paketi kabul etme
        
        updateActionButton(session, "toggle_record_btn", label = "Devam Et", icon = icon("microphone"))
        shinyjs::runjs(sprintf("$('#%s').removeClass('recording').addClass('paused');", ns("toggle_record_btn")))
        shinyjs::runjs(sprintf("window.STT_Client.stopRecording('%s');", id))
        shinyjs::runjs(sprintf("$('#%s').text('Duraklatıldı').removeClass('recording').addClass('paused');", ns("stt_status")))
        shinyjs::runjs(sprintf("$('.stt-char-status').text('Bekliyor');"))
        shinyjs::runjs(sprintf("$('.stt-visualizer-wrapper').addClass('paused-mode');"))
      } else {
        # --- BAŞLATMA İŞLEMİ ---
        rv$is_recording <- TRUE
        rv$accept_chunks <- TRUE # Kilidi aç
        
        updateActionButton(session, "toggle_record_btn", label = "Durdur", icon = icon("stop"))
        shinyjs::runjs(sprintf("$('#%s').removeClass('paused').addClass('recording');", ns("toggle_record_btn")))
        shinyjs::runjs(sprintf("window.STT_Client.startRecording('%s');", id))
        shinyjs::runjs(sprintf("$('#%s').text('Mikrofon Açık').removeClass('paused').addClass('recording');", ns("stt_status")))
        shinyjs::runjs(sprintf("$('.stt-char-status').text('Dinliyorum...');"))
        shinyjs::runjs(sprintf("$('.stt-visualizer-wrapper').removeClass('paused-mode');"))
      }
    })
    
    observeEvent(input$audio_chunk, {
      req(input$audio_chunk)
      
      # KİLİT KONTROLÜ: Eğer kullanıcı durdurduysa, asla işleme.
      # Bu, "Durdur"a basıldığı an kesilen yarım cümlelerin veya 
      # sessizlik anında modelin uydurduğu "Altyazı..." metinlerinin eklenmesini engeller.
      if (!isTRUE(rv$accept_chunks)) return(NULL)
      
      api_url <- Sys.getenv("LOCAL_STT_ENDPOINT", "http://localhost:8080/v1/audio/transcriptions")
      api_model <- Sys.getenv("LOCAL_STT_MODEL", "whisper-large-v3")
      api_key <- Sys.getenv("LOCAL_STT_API_KEY", "")
      
      if (!nzchar(api_key)) {
        api_key <- session$userData$ai_api_key
      }
      if (!nzchar(api_key)) return(NULL)
      api_key <- trimws(api_key)
      
      audio_binary <- tryCatch(
        base64enc::base64decode(input$audio_chunk),
        error = function(e) { return(NULL) }
      )
      req(audio_binary)
      
      input_file <- tempfile(fileext = ".webm")
      wav_file <- tempfile(fileext = ".wav")
      writeBin(audio_binary, input_file)
      
      tryCatch({
        av::av_audio_convert(input_file, wav_file, format = "wav", sample_rate = 16000, channels = 1)
        
        # Dosya boyutu kontrolü (Sessizlik filtresi 2. katman)
        if (file.size(wav_file) < 2500) return(NULL)

        body_params <- list(
          file = httr::upload_file(wav_file, type = "audio/wav"),
          model = api_model,
          language = "tr",
          task = "transcribe"
        )
        
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
            clean_text <- trimws(text_segment)
            
            # Basit filtreler: Modelin tipik halüsinasyonları
            # (Ancak kilit mekanizması zaten çoğunu çözecek)
            if (grepl("^(Altyazı|Alt yazı)", clean_text, ignore.case = TRUE)) return(NULL)
            if (grepl("^(Evet\\.|Hımmm|Sadece|Teşekkürler\\.)", clean_text) && nchar(clean_text) < 10) return(NULL)
            
            if (nzchar(clean_text)) {
              # Kilit son kez kontrol edilir (Asenkron gecikme için)
              if (isolate(rv$accept_chunks)) {
                current_ui_val <- input$transcribed_text
                sep <- if (nzchar(current_ui_val) && !grepl("\\s$", current_ui_val)) " " else ""
                new_val <- paste0(current_ui_val, sep, clean_text)
                updateTextAreaInput(session, "transcribed_text", value = new_val)
              }
            }
          }
        }
      }, error = function(e) {
        cat("[STT Error]", conditionMessage(e), "\n")
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