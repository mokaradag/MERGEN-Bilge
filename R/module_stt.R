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

    # Elle düzenleme senkronizasyonu, yalnızca son sunucu push'undan bu kadar
    # zaman geçtiyse uygulanır (bkz. flush_completed_stt_chunks). Bu, istemcinin
    # henüz yansıtmadığı KENDİ push'umuzu yanlışlıkla "elle düzenleme" sanıp
    # üzerine yazma riskini (ardışık hızlı parça birleştirme yarışını) önler;
    # gerçek elle düzenlemeler tipik olarak bundan çok daha uzun sürer.
    STT_EDIT_SYNC_GRACE_SEC <- 0.4
    # Onayla/Durdur sonrası kayıtçının stop() olayı TEK bir final ses parçası
    # daha gönderebilir (henüz dispatch edilmemiş bir segment); bu parçanın
    # kapıda (accept_chunks kapalıyken) sessizce düşmemesi için kısa, sınırlı
    # bir bekleme uygulanır.
    STT_FINAL_CHUNK_GRACE_MS <- 500

    rv <- reactiveValues(
      transcription_history = "", # Sunucu otoriter biriktirilmiş metin (issue #3)
      transcribe_gen = 0L,        # Çeviri jetonu: bayat asenkron sonuçları eler
      is_recording = FALSE,
      accept_chunks = FALSE, # Kilit mekanizması
      next_chunk_seq = 1L,
      next_append_seq = 1L,
      pending_stt_chunks = 0L,
      completed_stt_chunks = list(),
      accept_after_pending = FALSE,
      expect_final_chunk = FALSE, # Kayıtçının stop() sonrası TEK final parçası için bütçe
      last_pushed_value = "",     # Sunucunun textarea'ya en son yazdığı değer
      last_push_time = NULL       # O son yazımın zamanı (elle düzenleme tespiti için)
    )

    final_text <- reactiveVal("")

    # Biriktirilmiş metni metin alanına yazar (tek nokta).
    push_transcription <- function(value) {
      rv$transcription_history <- value
      rv$last_pushed_value <- value
      rv$last_push_time <- Sys.time()
      updateTextAreaInput(session, "transcribed_text", value = value)
    }

    reset_stt_queue <- function() {
      rv$next_chunk_seq <- 1L
      rv$next_append_seq <- 1L
      rv$pending_stt_chunks <- 0L
      rv$completed_stt_chunks <- list()
      rv$accept_after_pending <- FALSE
      rv$expect_final_chunk <- FALSE
      rv$last_pushed_value <- ""
      rv$last_push_time <- NULL
    }

    # Kullanıcı, sunucunun son gönderdiği metinden FARKLI bir değeri metin
    # alanına elle yazmış olabilir (ör. Durdur sırasında bir düzeltme
    # yaptıysa). Bir STT parçası biriktirilmiş metne eklenmeden ÖNCE bu elle
    # yapılan düzenleme sunucu geçmişine senkronize edilir; aksi halde geç
    # gelen bir parça bu düzeltmenin üzerine yazardı.
    sync_manual_edit_if_settled <- function() {
      live_text <- as.character(isolate(input$transcribed_text) %||% "")[1]
      last_pushed <- as.character(isolate(rv$last_pushed_value) %||% "")[1]
      if (is.na(live_text) || is.na(last_pushed) || identical(live_text, last_pushed)) {
        return(invisible(NULL))
      }

      last_push_time <- isolate(rv$last_push_time)
      grace_elapsed <- is.null(last_push_time) ||
        as.numeric(difftime(Sys.time(), last_push_time, units = "secs")) >= STT_EDIT_SYNC_GRACE_SEC
      if (!grace_elapsed) {
        return(invisible(NULL))
      }

      rv$transcription_history <- live_text
      rv$last_pushed_value <- live_text
      invisible(NULL)
    }

    flush_completed_stt_chunks <- function() {
      sync_manual_edit_if_settled()

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
        # Kayıtçının stop() sonrası tetiklenen 'stop' olayı, henüz dispatch
        # edilmemiş TEK bir final ses parçası daha gönderebilir (bkz.
        # observeEvent(input$audio_chunk) kapısı). Bu parçanın kapıda
        # sessizce düşmemesi için tek kullanımlık bir bütçe açılır.
        rv$expect_final_chunk <- TRUE
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
        rv$last_pushed_value <- edited_text
        rv$last_push_time <- Sys.time()

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

      # KİLİT KONTROLÜ: Kayıt kapalıyken YENİ paketleri işleme. Tek istisna:
      # Durdur/Onayla sonrası kayıtçının stop() olayının gönderdiği TEK final
      # parça (expect_final_chunk bütçesi) kapıdan geçebilir; aksi halde bu
      # parça henüz dispatch bile edilmeden sessizce kaybolurdu. Bütçe tek
      # kullanımlıktır ve burada hemen tüketilir.
	  if (!isTRUE(rv$accept_chunks) && !isTRUE(rv$expect_final_chunk)) return(NULL)
      rv$expect_final_chunk <- FALSE

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

      # SKALER ZORUNLU: istemci Shiny girdisi üzerinden DİZİ gönderebilir.
      # Boyut denetimi yalnızca ilk öğeyi ölçüyor, worker'a ise TÜM vektör
      # gidiyordu; sınır altındaki çok sayıda öğe MERGEN_STT_MAX_CHUNK_MB
      # sınırını aşabiliyordu.
      if (!is.character(chunk_b64) || length(chunk_b64) != 1L ||
          is.na(chunk_b64) || !nzchar(chunk_b64)) {
        showNotification("Geçersiz ses parçası.", type = "warning", duration = 6)
        return(NULL)
      }

      # KABUL SINIRLARI: parça boyutu ve uçuştaki iş sayısı, worker'a
      # GÖNDERMEDEN ÖNCE denetlenir. Önceden her olay yeni bir future
      # başlatıyor ve boyut yalnızca worker base64'ü çözüp av_audio_convert
      # çalıştırdıktan SONRA denetleniyordu; büyük/sık parçalar gönderen bir
      # istemci future kuyruğunu, belleği ve ffmpeg süreçlerini tüketerek
      # Shiny worker havuzunu kilitleyebiliyordu.
      max_chunk_mb <- suppressWarnings(as.numeric(Sys.getenv("MERGEN_STT_MAX_CHUNK_MB", "8")))
      # `Inf` değeri `is.na()` denetimini geçiyor ve sonlu hiçbir parça sınırı
      # aşamıyordu: yapılandırılmış sınır tamamen devre dışı kalıyordu.
      if (!is.finite(max_chunk_mb) || max_chunk_mb <= 0) max_chunk_mb <- 8
      chunk_bytes <- nchar(chunk_b64, type = "bytes")
      if (is.na(chunk_bytes) || chunk_bytes > max_chunk_mb * 1024 * 1024) {
        cat("[STT] Parça boyut sınırını aştı; atlandı.\n")
        showNotification(
          "Ses parçası çok büyük olduğu için işlenmedi; konuşmanın bir bölümü eksik olabilir.",
          type = "warning",
          duration = 6
        )
        return(NULL)
      }

      max_pending <- suppressWarnings(as.integer(Sys.getenv("MERGEN_STT_MAX_PENDING_CHUNKS", "6")))
      if (is.na(max_pending) || max_pending <= 0L) max_pending <- 6L
      if (isolate(rv$pending_stt_chunks) >= max_pending) {
        cat("[STT] Uçuştaki parça sınırına ulaşıldı; parça atlandı.\n")
        showNotification(
          "Ses işleme kuyruğu dolu; bir parça atlandı ve metne eklenmedi.",
          type = "warning",
          duration = 6
        )
        return(NULL)
      }

      dispatch_gen <- isolate(rv$transcribe_gen)
      chunk_seq <- isolate(rv$next_chunk_seq)
      rv$next_chunk_seq <- chunk_seq + 1L
      rv$pending_stt_chunks <- isolate(rv$pending_stt_chunks) + 1L
      stt_timeout <- suppressWarnings(as.numeric(Sys.getenv("MERGEN_STT_TIMEOUT_SEC", "30")))
      if (is.na(stt_timeout) || stt_timeout <= 0) stt_timeout <- 30

      # AĞIR İŞ ARKA PLANDA: av dönüştürme + HTTP POST worker'a taşındı. Böylece
      # ana olay döngüsü bloklanmaz ve İptal/Onayla/Temizle/Durdur butonları
      # her zaman anında yanıt verir (issue #1).
      # tracked_future_promise() gönderim anında SENKRON hata verebilir (worker
      # havuzu yok). Yakalanmazsa artırılmış `pending_stt_chunks` sayacı hiç
      # azalmıyor ve tekrarlanan hatalar tüm slotları kalıcı olarak tüketiyordu.
      promise <- tryCatch(
      tracked_future_promise(
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
      ),
      error = function(e) {
        cat("[STT] Parça gönderimi başarısız:", conditionMessage(e), "\n")
        # Sessiz kayıp yerine görünür uyarı: kullanıcı aksi hâlde eksik metni
        # fark etmeden "Onayla ve Gönder" diyebiliyordu.
        showNotification(
          "Ses işleme başlatılamadı; bir parça metne eklenmedi.",
          type = "warning",
          duration = 6
        )
        NULL
      })

      if (is.null(promise)) {
        # Sıra boşluğu bırakılmaz: bu seq için BOŞ tamamlama kaydedilir.
        # Aksi hâlde flush_completed_stt_chunks() beklediği anahtarı hiç
        # göremiyor, next_append_seq o numarada kilitleniyor ve sonraki tüm
        # parçalar metin alanına hiç yazılmıyordu (kullanıcı konuşmaya devam
        # ediyor, hiçbir metin görmüyor, "Onayla ve Gönder" boş metin üretiyor).
        if (identical(dispatch_gen, isolate(rv$transcribe_gen))) {
          completed <- isolate(rv$completed_stt_chunks)
          completed[[as.character(chunk_seq)]] <- ""
          rv$completed_stt_chunks <- completed
          flush_completed_stt_chunks()
        }

        rv$pending_stt_chunks <- max(0L, isolate(rv$pending_stt_chunks) - 1L)
        # Promise dalları gibi: son bekleyen parça düştüğünde onaylama akışı
        # tamamlanmalı; aksi hâlde "Onayla ve Gönder" kalıcı kilitli kalıyordu.
        if (isTRUE(isolate(rv$accept_after_pending)) &&
            isolate(rv$pending_stt_chunks) == 0L) {
          finish_accept()
        }
        return(NULL)
      }

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
      rv$last_pushed_value <- accepted_text
      rv$last_push_time <- Sys.time()
      rv$accept_chunks <- FALSE
      rv$accept_after_pending <- TRUE
      # Kayıtçının stop() sonrası göndermiş olabileceği TEK final parça için
      # kapı bütçesi açılır (bkz. observeEvent(input$audio_chunk)).
      rv$expect_final_chunk <- TRUE
      shinyjs::runjs(sprintf("window.STT_Client.stopAndCleanup('%s');", id))
      updateActionButton(session, "accept_btn", label = "Metin hazırlanıyor...", icon = icon("spinner"))
      shinyjs::disable("accept_btn")

      flush_completed_stt_chunks()

      # Bu final parçanın sunucuya ulaşıp dispatch edilmesi (pending sayacına
      # yansıması) için kısa, sınırlı bir bekleme uygulanır; aksi halde bu
      # segment hiç dispatch edilmeden Onayla anında kaybolur. Parça bu süre
      # içinde dispatch edilirse normal "pending == 0 olunca tamamla" akışı
      # zaten devreye girer (bkz. promise %...>%); hiç gelmezse (sessizlik),
      # süre sonunda pencere kapatılır ve normal şekilde tamamlanır.
      # accept_after_pending kontrolü, promise çözümünün bu bekleme bitmeden
      # zaten tamamlamış olabileceği durumda tekrar finish_accept() çağrılmasını
      # engeller (idempotentlik).
      shinyjs::delay(STT_FINAL_CHUNK_GRACE_MS, {
        rv$expect_final_chunk <- FALSE
        if (isTRUE(isolate(rv$accept_after_pending)) && isolate(rv$pending_stt_chunks) == 0L) {
          finish_accept()
        }
      })
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
