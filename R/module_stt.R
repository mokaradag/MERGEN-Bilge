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

    set_stt_modal_active_js <- function(active) {
      active_js <- if (isTRUE(active)) "true" else "false"

      shinyjs::runjs(sprintf(
        "
        (function() {
          if (window.Shiny && typeof window.Shiny.setInputValue === 'function') {
            window.Shiny.setInputValue('stt_modal_active', %s, {priority: 'event'});
          } else {
            console.warn('[STT] Shiny.setInputValue hazır değil; stt_modal_active atlandı');
          }
        })();
        ",
        active_js
      ))
    }

    rv <- reactiveValues(
      transcription_history = "", # Sunucu otoriter biriktirilmiş metin (issue #3)
      transcribe_gen = 0L,        # Çeviri jetonu: bayat asenkron sonuçları eler
      is_recording = FALSE,
      accept_chunks = FALSE, # Kilit mekanizması
      next_chunk_seq = 1L,
      next_append_seq = 1L,
      pending_stt_chunks = 0L,
      completed_stt_chunks = list(),
      accept_after_pending = FALSE
    )

    final_text <- reactiveVal("")

    # Biriktirilmiş metni metin alanına yazar (tek nokta).
    push_transcription <- function(value) {
      rv$transcription_history <- value
      updateTextAreaInput(session, "transcribed_text", value = value)
    }

    reset_stt_queue <- function() {
      rv$next_chunk_seq <- 1L
      rv$next_append_seq <- 1L
      rv$pending_stt_chunks <- 0L
      rv$completed_stt_chunks <- list()
      rv$accept_after_pending <- FALSE
    }

    flush_completed_stt_chunks <- function() {
      repeat {
        key <- as.character(isolate(rv$next_append_seq))
        completed <- isolate(rv$completed_stt_chunks)
        if (!key %in% names(completed)) break

        clean_text <- completed[[key]]
        completed[[key]] <- NULL
        rv$completed_stt_chunks <- completed
        rv$next_append_seq <- isolate(rv$next_append_seq) + 1L

        if (is.null(clean_text) || length(clean_text) == 0L) next
        clean_text <- as.character(clean_text)[1]
        if (is.na(clean_text) || !nzchar(clean_text)) next

        # BİRİKTİRME: taban her zaman sunucu otoriter geçmiştir; metin alanının
        # gecikmeli round-trip değeri değildir. Bu, konuşup durup tekrar
        # konuşulduğunda ilk parçanın silinmesini ve paralel STT dönüşlerinde
        # parça sırasının bozulmasını önler.
        base <- as.character(isolate(rv$transcription_history) %||% "")[1]
        if (is.na(base)) base <- ""
        sep <- if (nzchar(base) && !grepl("\\s$", base)) " " else ""
        push_transcription(paste0(base, sep, clean_text))
      }
    }

    finish_accept <- function() {
      # Onay akışında otoriter metin sunucu geçmişidir. Accept anında elle
      # düzenlenmiş metin bu geçmişe yazılır; beklenen STT callback'leri de aynı
      # geçmişe append eder. Böylece textarea round-trip'i gecikse bile beklenen
      # son parçalar gönderilen metinden düşmez.
      text_to_send <- trimws(as.character(isolate(rv$transcription_history) %||% "")[1])
      if (is.na(text_to_send)) text_to_send <- ""
      rv$accept_after_pending <- FALSE
      removeModal()
      if (nzchar(text_to_send)) {
        final_text(text_to_send)
      }
    }

    start_session <- function() {
      rv$transcription_history <- ""
      rv$transcribe_gen <- isolate(rv$transcribe_gen) + 1L
      rv$is_recording <- TRUE
      rv$accept_chunks <- TRUE
      reset_stt_queue()

      # 1. Ayarlardan persona bilgisini al (eski kimlikler normalleştirilir)
      chars <- tryCatch(get_characters_data(), error = function(e) NULL)
      selected_id <- normalize_character_id(settings$selected_character)

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
        # Yedek: varsayılan persona (Emre) bilgisi
        char_info <- list(
          display_name = "EMRE ONAT",
          image = "characters/avatar/emre/avatar.png",
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
              tags$canvas(id = ns("visualizer_canvas"))
            ),

            # Sağ: Karakter Bilgi Paneli (Boşluğu doldurur)
            div(
              class = "stt-vis-info-panel",
              div(
                class = "stt-char-badge",
                tags$img(src = char_info$image, class = "stt-avatar"),
                div(
                  class = "stt-char-text",
                  div(class = "stt-char-name", style = paste0("color: ", char_info$accent, ";"), char_info$display_name),
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
              actionButton(ns("clear_btn"), "Temizle", icon = icon("trash-can"), class = "btn-stt-clear"),
              actionButton(ns("toggle_record_btn"), "Durdur", icon = icon("stop"), class = "btn-stt-record recording")
            ),
            div(
              class = "stt-controls-right",
              actionButton(ns("dismiss_btn"), "İptal", icon = icon("xmark"), class = "btn-stt-cancel"),
              actionButton(ns("accept_btn"), "Onayla ve Gönder", icon = icon("paper-plane"), class = "btn-stt-confirm")
            )
          )
        )
      ))

      # STT modalının açık olduğunu uygulama geneline bildir
      set_stt_modal_active_js(TRUE)

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

    # Temizle Butonu: hem metin alanını hem de sunucu otoriter geçmişi sıfırla.
    # Jeton artırılır ki uçuşta olan (henüz dönmemiş) çeviriler temizlenen metne
    # geri eklenmesin.
    observeEvent(input$clear_btn, {
      rv$transcribe_gen <- isolate(rv$transcribe_gen) + 1L
      reset_stt_queue()
      push_transcription("")
    })

    observeEvent(input$toggle_record_btn, {
      if (rv$is_recording) {
        # --- DURDURMA İŞLEMİ ---
        rv$is_recording <- FALSE
        rv$accept_chunks <- FALSE # KİLİT: Artık YENİ ses paketi kabul etme/gönderme
        # ÖNEMLİ: transcribe_gen VE kuyruk (next_chunk_seq/next_append_seq/
        # pending_stt_chunks/completed_stt_chunks) BİLEREK sıfırlanmaz.
        # Duraklatmadan önce dispatch edilmiş STT parçaları hâlâ AYNI kayıt
        # üretimine aittir; mergen_stt_transcribe_chunk() bir HTTP zaman
        # aşımıyla (MERGEN_STT_TIMEOUT_SEC) her zaman sonuçlanır, bu yüzden
        # kuyruk kilitlenme riski yoktur. Üretimi burada artırmak/kuyruğu
        # sıfırlamak, duraklatmadan hemen önce söylenen son parçanın veya tüm
        # cümlenin sessizce düşmesine yol açıyordu. Sıfırlama yalnızca
        # Temizle/İptal/Yeni Oturum akışlarında yapılır (kullanıcı bilerek
        # vazgeçtiği için).

        updateActionButton(session, "toggle_record_btn", label = "Devam Et", icon = icon("microphone"))
        shinyjs::runjs(sprintf("$('#%s').removeClass('recording').addClass('paused');", ns("toggle_record_btn")))
        shinyjs::runjs(sprintf("window.STT_Client.stopRecording('%s');", id))
        shinyjs::runjs(sprintf("$('#%s').text('Duraklatıldı').removeClass('recording').addClass('paused');", ns("stt_status")))
        shinyjs::runjs(sprintf("$('.stt-char-status').text('Bekliyor');"))
        shinyjs::runjs(sprintf("$('.stt-visualizer-wrapper').addClass('paused-mode');"))
      } else {
        # --- BAŞLATMA İŞLEMİ (Devam Et) ---
        # Duraklatma sırasında kullanıcı metin alanını elle düzenlemiş olabilir;
        # devam etmeden önce sunucu geçmişini görünen metinle eşitle. Duraklama
        # sırasında asenkron parça eklenmediği için metin alanı güvenilirdir.
        edited_text <- as.character(isolate(input$transcribed_text) %||% "")[1]
        if (is.na(edited_text)) edited_text <- ""
        rv$transcription_history <- edited_text

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

      api_url <- Sys.getenv("LOCAL_STT_ENDPOINT")
      api_model <- Sys.getenv("LOCAL_STT_MODEL")
      api_key <- Sys.getenv("LOCAL_STT_API_KEY", "")

      if (!nzchar(api_key)) {
        api_key <- session$userData$ai_api_key
      }
      if (!nzchar(api_key)) return(NULL)
      api_key <- trimws(api_key)

      # Çeviri, gönderim anındaki üretim jetonu ile ilişkilendirilir; böylece
      # yeni oturum/temizle sonrası dönen bayat sonuçlar geçmişe eklenmez.
      chunk_b64 <- input$audio_chunk
      dispatch_gen <- isolate(rv$transcribe_gen)
      chunk_seq <- isolate(rv$next_chunk_seq)
      rv$next_chunk_seq <- chunk_seq + 1L
      rv$pending_stt_chunks <- isolate(rv$pending_stt_chunks) + 1L
      stt_timeout <- suppressWarnings(as.numeric(Sys.getenv("MERGEN_STT_TIMEOUT_SEC", "30")))
      if (is.na(stt_timeout) || stt_timeout <= 0) stt_timeout <- 30

      # AĞIR İŞ ARKA PLANDA: av dönüştürme + HTTP POST worker'a taşındı. Böylece
      # ana olay döngüsü bloklanmaz ve İptal/Onayla/Temizle/Durdur butonları
      # her zaman anında yanıt verir (issue #1).
      promise <- tracked_future_promise(
        task_fn = function() {
          mergen_stt_transcribe_chunk(chunk_b64, api_url, api_model, api_key, stt_timeout)
        },
        task_type = "stt_transcribe",
        session_token = session$token,
        dependency_mode = "explicit",
        globals = list(
          mergen_stt_transcribe_chunk = mergen_stt_transcribe_chunk,
          chunk_b64 = chunk_b64,
          api_url = api_url,
          api_model = api_model,
          api_key = api_key,
          stt_timeout = stt_timeout
        )
      )

      promise %...>% (function(clean_text) {
        # Yalnızca üretim (transcribe_gen) hâlâ aynıysa tamamlanma/sayaç
        # güncelle. Stale callback'ler (Temizle/İptal/Yeni Oturum ile
        # üretim artırılmış) yeni oturumun bekleyen sayacını azaltamaz.
        # NOT: Durdur (duraklatma) artık üretimi artırmaz/kuyruğu sıfırlamaz;
        # bu yüzden duraklatmadan önce dispatch edilmiş bir parça, sonuç
        # duraklatma sırasında/sonrasında gelse bile burada üretim eşleştiği
        # için METİN HER ZAMAN eklenir (canlı `accept_chunks` durumuna göre
        # boşaltılmaz). Bu, "Durdur"a basar basmaz uçuştaki son parçanın
        # sessizce kaybolmasını önler.
        if (identical(dispatch_gen, isolate(rv$transcribe_gen))) {
          clean_text <- as.character(clean_text %||% "")[1]
          if (is.na(clean_text)) clean_text <- ""
          completed <- isolate(rv$completed_stt_chunks)
          completed[[as.character(chunk_seq)]] <- clean_text
          rv$completed_stt_chunks <- completed
          flush_completed_stt_chunks()

          rv$pending_stt_chunks <- max(0L, isolate(rv$pending_stt_chunks) - 1L)
          if (isTRUE(isolate(rv$accept_after_pending)) && isolate(rv$pending_stt_chunks) == 0L) {
            finish_accept()
          }
        }
        invisible(NULL)
      }) %...!% (function(e) {
        cat("[STT Error]", conditionMessage(e), "\n")
        if (identical(dispatch_gen, isolate(rv$transcribe_gen))) {
          completed <- isolate(rv$completed_stt_chunks)
          completed[[as.character(chunk_seq)]] <- ""
          rv$completed_stt_chunks <- completed
          flush_completed_stt_chunks()

          rv$pending_stt_chunks <- max(0L, isolate(rv$pending_stt_chunks) - 1L)
          if (isTRUE(isolate(rv$accept_after_pending)) && isolate(rv$pending_stt_chunks) == 0L) {
            finish_accept()
          }
        }
        invisible(NULL)
      })

      invisible(NULL)
    })

    observeEvent(input$accept_btn, {
      # STT modalı kapanıyor bilgisini uygulama geneline bildir
      set_stt_modal_active_js(FALSE)

      accepted_text <- as.character(isolate(input$transcribed_text) %||% "")[1]
      if (is.na(accepted_text)) accepted_text <- ""
      rv$transcription_history <- accepted_text
      rv$accept_chunks <- FALSE
      rv$accept_after_pending <- TRUE
      shinyjs::runjs(sprintf("window.STT_Client.stopAndCleanup('%s');", id))
      updateActionButton(session, "accept_btn", label = "Metin hazırlanıyor...", icon = icon("spinner"))
      shinyjs::disable("accept_btn")

      flush_completed_stt_chunks()
      if (isolate(rv$pending_stt_chunks) == 0L) {
        finish_accept()
      }
    })

    observeEvent(input$dismiss_btn, {
      # STT modalı kapanıyor bilgisini uygulama geneline bildir
      set_stt_modal_active_js(FALSE)

      rv$transcribe_gen <- isolate(rv$transcribe_gen) + 1L
      reset_stt_queue()
      shinyjs::runjs(sprintf("window.STT_Client.stopAndCleanup('%s');", id))
      removeModal()
    })

    return(list(
      start_session = start_session,
      final_text = final_text
    ))
  })
}
