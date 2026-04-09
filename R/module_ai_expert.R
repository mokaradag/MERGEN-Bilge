# R/module_ai_expert.R
# Dosya Yolu: R/module_ai_expert.R
# Açıklama: AI Uzman (AI Expert) Shiny modülü.
#            Altyazı (subtitle) görüntüleyicisi UI bileşenini ve
#            sunucu tarafındaki durum yönetimini içerir.
#            Altyazı gösterimi TTS sesi hazır olana kadar bekler (senkronizasyon).

#' AI Uzman Altyazı UI Bileşeni
#'
#' Sayfa altında sabit konumlu altyazı şeridi oluşturur.
#' Bu şerit, AI konuşması sırasında metin görüntüler.
#'
#' @param id Modül ad alanı kimliği
#' @return Altyazı şeridi UI tanımı
aiExpertSubtitleUI <- function(id) {
  ns <- NS(id)

  # Sabit konumlu altyazı şeridi (tüm sayfalarda görünür)
  tags$div(
    id = ns("subtitle_strip"),
    class = "ai-expert-subtitle-strip ai-expert-hidden",

    # Sol: Karakter avatarı
    tags$div(
      class = "ai-expert-avatar-wrapper",
      tags$img(
        id = ns("subtitle_avatar"),
        class = "ai-expert-subtitle-avatar",
        src = ""
      )
    ),

    # Orta: Altyazı metin alanı
    tags$div(
      class = "ai-expert-subtitle-text-wrapper",
      tags$span(
        id = ns("subtitle_text"),
        class = "ai-expert-subtitle-text",
        ""
      )
    ),

    # Sağ: Durdurma butonu
    tags$div(
      class = "ai-expert-stop-wrapper",
      tags$button(
        id = ns("stop_ai_talk"),
        class = "ai-expert-stop-btn action-button",
        title = "AI konuşmasını durdur",
        tags$i(class = "fa-solid fa-xmark")
      )
    )
  )
}

#' AI Uzman Sunucu Modülü
#'
#' AI Uzman konuşma durumunu, zamanlamasını ve yarış durumu
#' önleme mantığını yönetir.
#'
#' @param id Modül ad alanı kimliği
#' @param settings_data Merkezi ayarlar reaktif değerleri
#' @param tts_processor TTS işleme modülü (sesli çıktı için)
#' @param tts_visualizer TTS görselleştiricisi (animasyon tetiklemek için)
#' @return AI Uzman kontrol fonksiyonlarını içeren liste
aiExpertServer <- function(id, settings_data, tts_processor, tts_visualizer) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # --- Reaktif durum değişkenleri ---
    is_speaking     <- reactiveVal(FALSE)    # AI şimdi konuşuyor mu
    is_cooldown     <- reactiveVal(FALSE)    # Bekleme süresi aktif mi
    last_speak_time <- reactiveVal(NULL)     # Son konuşma zamanı
    current_page    <- reactiveVal("chat")   # Aktif sayfa
    user_is_active  <- reactiveVal(FALSE)    # Kullanıcı mesaj gönderiyor mu
    tts_vocalizing  <- reactiveVal(FALSE)    # TTS yanıt seslendirmesi aktif mi

    # Bekleme süreleri (saniye) - daha hızlı ve akıcı deneyim için kısa tutuldu
    COOLDOWN_AFTER_GREETING  <- 10  # Karşılama sonrası bekleme
    COOLDOWN_AFTER_PAGE      <- 8   # Sayfa rehberliği sonrası bekleme
    COOLDOWN_AFTER_IDLE      <- 12  # Boşta konuşma sonrası bekleme
    COOLDOWN_AFTER_STOP      <- 5   # Manuel durdurma sonrası bekleme

    # Aktif bekleme süresi (dinamik olarak değişir)
    active_cooldown_seconds <- reactiveVal(15)

    # Yasaklı sayfalar (bu sayfalarda AI konuşmaz)
    MUTED_PAGES <- c("settings_kisisel", "admin_analytics", "health")

    # --- Yardımcı: AI Uzman konuşması mümkün mü? ---
    can_speak <- function() {
      # 1. Özellik açık mı?
      if (!isTRUE(settings_data$enable_ai_expert)) return(FALSE)

      # 2. Bütünleşik mod mu?
      if (!identical(settings_data$experience_mode, "kesif")) return(FALSE)

      # 3. Yasaklı sayfa mı?
      page <- isolate(current_page())
      if (page %in% MUTED_PAGES) return(FALSE)

      # 4. Zaten konuşuyor mu?
      if (isTRUE(is_speaking())) return(FALSE)

      # 5. TTS yanıt seslendirmesi aktif mi? (yarış durumu önleme)
      if (isTRUE(tts_vocalizing())) return(FALSE)

      # 6. Bekleme süresinde mi?
      if (isTRUE(is_cooldown())) return(FALSE)

      # 7. Son konuşmadan yeterli süre geçti mi?
      lst <- isolate(last_speak_time())
      cooldown_secs <- isolate(active_cooldown_seconds())
      if (!is.null(lst)) {
        elapsed <- as.numeric(difftime(Sys.time(), lst, units = "secs"))
        if (elapsed < cooldown_secs) return(FALSE)
      }

      # 8. Kullanıcı aktif mi? (yazıyorsa veya istek gönderdiyse konuşma)
      if (isTRUE(user_is_active())) return(FALSE)

      return(TRUE)
    }

    # --- Bekleme süresini başlat (senaryo bazlı) ---
    start_cooldown <- function(cooldown_secs) {
      active_cooldown_seconds(cooldown_secs)
      is_cooldown(TRUE)
      shinyjs::delay(cooldown_secs * 1000, {
        is_cooldown(FALSE)
      })
    }

    # --- AI Uzman TTS metnini kısa parçalara böl ---
    # Amaç: İlk ses parçasını daha hızlı üretmek ve konuşmayı bekletmeden başlatmak.
    split_text_for_ai_expert_tts <- function(text, max_chunk_chars = 220, min_chunk_chars = 70) {
      text <- trimws(as.character(text %||% ""))
      if (!nzchar(text)) return(list())

      sentence_candidates <- unlist(strsplit(text, "(?<=[.!?…])\\s+", perl = TRUE))
      sentence_candidates <- trimws(sentence_candidates)
      sentence_candidates <- sentence_candidates[nzchar(sentence_candidates)]

      if (length(sentence_candidates) == 0) {
        sentence_candidates <- text
      }

      split_long_piece <- function(piece) {
        piece <- trimws(piece)
        if (!nzchar(piece)) return(character(0))
        if (nchar(piece) <= max_chunk_chars) return(piece)

        comma_parts <- unlist(strsplit(piece, "(?<=[,;:])\\s+", perl = TRUE))
        comma_parts <- trimws(comma_parts)
        comma_parts <- comma_parts[nzchar(comma_parts)]

        if (length(comma_parts) <= 1) {
          words <- unlist(strsplit(piece, "\\s+"))
          out <- character(0)
          current <- ""

          for (w in words) {
            candidate <- trimws(paste(current, w))
            if (!nzchar(current) || nchar(candidate) <= max_chunk_chars) {
              current <- candidate
            } else {
              out <- c(out, current)
              current <- w
            }
          }

          if (nzchar(current)) out <- c(out, current)
          return(out)
        }

        out <- character(0)
        current <- ""

        for (part in comma_parts) {
          candidate <- trimws(paste(current, part))
          if (!nzchar(current) || nchar(candidate) <= max_chunk_chars) {
            current <- candidate
          } else {
            out <- c(out, split_long_piece(current))
            current <- part
          }
        }

        if (nzchar(current)) out <- c(out, split_long_piece(current))
        out
      }

      chunks <- character(0)
      current <- ""

      for (sentence in sentence_candidates) {
        sentence_parts <- split_long_piece(sentence)

        for (part in sentence_parts) {
          candidate <- trimws(paste(current, part))
          if (!nzchar(current)) {
            current <- part
          } else if (nchar(candidate) <= max_chunk_chars) {
            current <- candidate
          } else if (nchar(current) < min_chunk_chars) {
            current <- candidate
          } else {
            chunks <- c(chunks, current)
            current <- part
          }
        }
      }

      if (nzchar(current)) chunks <- c(chunks, current)

      chunks <- trimws(chunks)
      chunks <- chunks[nzchar(chunks)]

      as.list(chunks)
    }
	
    # --- Konuşmayı başlat ---
    # ÖNEMLİ: Altyazı ve ses senkronizasyonu
    # TTS hazır olana kadar altyazı başlatılmaz, böylece senkronize olurlar
	start_speaking <- function(text, cooldown_secs = COOLDOWN_AFTER_PAGE) {
	  if (is.null(text) || !nzchar(text)) return(invisible(NULL))
	  if (isTRUE(is_speaking())) return(invisible(NULL))

	  is_speaking(TRUE)
	  last_speak_time(Sys.time())

	  # Karakter bilgilerini al
	  char_id <- isolate(settings_data$selected_character) %||% "mergen"
	  chars_data <- get_characters_data()
	  char_info <- Find(function(x) x$id == char_id, chars_data$styles)

	  avatar_src <- if (!is.null(char_info)) char_info$avatar else "img/mergen_avatar.png"
	  accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"

	  # Yazı tipi boyutunu ayarlardan al
	  font_size <- isolate(settings_data$font_size) %||% "medium"

	  # TTS ile seslendirme kontrolü
	  tts_available <- FALSE
	  tryCatch({
		tts_available <- isTRUE(tts_processor$tts_available())
	  }, error = function(e) {})

	  if (tts_available) {
		# TTS ses tonunu karakter ayarından al
		voice_sel <- if (!is.null(char_info) && !is.null(char_info$tts_voice)) {
		  char_info$tts_voice
		} else {
		  "tr-male-1"
		}

		# İlk sesi daha hızlı başlatmak için metni kısa parçalara böl
		chunks <- split_text_for_ai_expert_tts(text, max_chunk_chars = 220, min_chunk_chars = 70)
		if (length(chunks) == 0) chunks <- list(text)

		cat(sprintf(
		  "[AI_EXPERT] TTS %d parçaya bölündü (toplam: %d karakter)...\n",
		  length(chunks), nchar(text)
		))

		# YARIŞ DURUMU KORUMASI: İlk parça istemciye gönderildi mi?
		# Gönderildiyse geri dönüş (fallback) yolu tam metni tekrar tetiklememeli.
		first_chunk_dispatched <- FALSE

		# İlk parçayı üret ve konuşmayı hemen başlat
		tts_processor$synthesize_speech(chunks[[1]], voice = voice_sel) %...>%
		  (function(first_res) {
			if (!isTRUE(is_speaking())) return()

			if (isTRUE(first_res$success) && nzchar(first_res$audio_src)) {
			  cat(sprintf(
				"[AI_EXPERT] İlk TTS parçası hazır (Süre: %.2fs). Konuşma hemen başlatılıyor.\n",
				first_res$duration
			  ))

			  # Görselleştiriciyi aktive et
			  tts_visualizer$trigger(duration = 0)

			  # İlk parça için altyazı ve ses aynı anda başlasın
			  session$sendCustomMessage("aiExpertStartWithAudio", list(
				text          = chunks[[1]],
				totalChunks   = length(chunks),
				avatarSrc     = avatar_src,
				accentColor   = accent_color,
				nsPrefix      = ns(""),
				audioSrc      = first_res$audio_src,
				audioDuration = first_res$duration,
				fontSize      = font_size
			  ))

			  # İlk parça başarıyla istemciye iletildi: geri dönüş yolu artık devre dışı
			  first_chunk_dispatched <<- TRUE

              # Kalan parçaları SIRALI biçimde hazırla ve kuyruğa gönder
              # ÖNEMLİ: Bazı TTS uç noktaları paralel isteklerde kararsız çalışır.
              # Bu nedenle ilk parçadan sonraki parçalar tek tek sentezlenir.
              if (length(chunks) > 1) {
                total_chunks <- length(chunks)

                queue_next_chunk <- NULL
                queue_next_chunk <- function(idx) {
                  if (!isTRUE(is_speaking())) return(invisible(NULL))
                  if (idx > total_chunks) return(invisible(NULL))

                  chunk_text <- chunks[[idx]]

                  cat(sprintf(
                    "[AI_EXPERT] TTS parça %d/%d sentezleniyor (%d karakter)...\n",
                    idx, total_chunks, nchar(chunk_text)
                  ))

                  tts_processor$synthesize_speech(chunk_text, voice = voice_sel) %...>%
                    local({
                      current_idx <- idx
                      current_text <- chunk_text

                      function(res) {
                        if (!isTRUE(is_speaking())) return()

                        if (isTRUE(res$success) && nzchar(res$audio_src)) {
                          cat(sprintf(
                            "[AI_EXPERT] TTS parça %d/%d hazır (Süre: %.2fs)\n",
                            current_idx, total_chunks, res$duration
                          ))

                          session$sendCustomMessage("aiExpertQueueAudioChunk", list(
                            index         = current_idx - 1L,
                            text          = current_text,
                            audioSrc      = res$audio_src,
                            audioDuration = res$duration,
                            nsPrefix      = ns("")
                          ))
                        } else {
                          cat(sprintf(
                            "[AI_EXPERT] TTS parça %d/%d başarısız.\n",
                            current_idx, total_chunks
                          ))
                        }

                        if (current_idx < total_chunks) {
                          queue_next_chunk(current_idx + 1L)
                        }
                      }
                    }) %...!%
                    local({
                      current_idx <- idx

                      function(e) {
                        cat(sprintf(
                          "[AI_EXPERT] TTS parça %d/%d hatası: %s\n",
                          current_idx, total_chunks, conditionMessage(e)
                        ))

                        if (isTRUE(is_speaking()) && current_idx < total_chunks) {
                          queue_next_chunk(current_idx + 1L)
                        }
                      }
                    })
                }

                queue_next_chunk(2L)
              }
			} else {
			  cat("[AI_EXPERT] İlk TTS parçası başarısız, sadece altyazı gösteriliyor.\n")

			  session$sendCustomMessage("aiExpertStartSubtitle", list(
				text        = text,
				avatarSrc   = avatar_src,
				accentColor = accent_color,
				nsPrefix    = ns(""),
				fontSize    = font_size
			  ))

			  session$sendCustomMessage("aiExpertNoAudioFallback", list(
				textLength = nchar(text),
				nsPrefix   = ns("")
			  ))
			}
		  }) %...!%
		  (function(e) {
			cat(sprintf("[AI_EXPERT] TTS hatası: %s\n", conditionMessage(e)))
			if (!isTRUE(is_speaking())) return()

			# YARIŞ DURUMU KORUMASI: İlk parça zaten istemciye iletildiyse
			# (ses oynatılıyor veya az önce bitti), tam metinle altyazıyı
			# YENİDEN BAŞLATMAK yanlış olur; mevcut parça akışı çalışmaya
			# devam etmeli. Bu geri dönüş yalnızca henüz hiçbir parça
			# gönderilmemişse tetiklenmelidir.
			if (isTRUE(first_chunk_dispatched)) {
			  cat("[AI_EXPERT] İlk parça zaten gönderilmiş; tam metin geri dönüşü atlandı.\n")
			  return()
			}

			session$sendCustomMessage("aiExpertStartSubtitle", list(
			  text        = text,
			  avatarSrc   = avatar_src,
			  accentColor = accent_color,
			  nsPrefix    = ns(""),
			  fontSize    = font_size
			))

			session$sendCustomMessage("aiExpertNoAudioFallback", list(
			  textLength = nchar(text),
			  nsPrefix   = ns("")
			))
		  })
	  } else {
		# TTS yoksa sadece altyazı göster, süre tahminle
		# Görselleştiriciyi sessiz bile aktive et (animasyon göster)
		tts_visualizer$trigger(duration = 0)

		session$sendCustomMessage("aiExpertStartSubtitle", list(
		  text        = text,
		  avatarSrc   = avatar_src,
		  accentColor = accent_color,
		  nsPrefix    = ns(""),
		  fontSize    = font_size
		))

		session$sendCustomMessage("aiExpertNoAudioFallback", list(
		  textLength = nchar(text),
		  nsPrefix   = ns("")
		))
	  }

	  # Senaryo bazlı bekleme süresini kaydet (konuşma bittikten sonra uygulanacak)
	  active_cooldown_seconds(cooldown_secs)

	  invisible(NULL)
	}

    # --- Konuşmayı durdur ---
    stop_speaking <- function(cooldown_secs = NULL) {
      is_speaking(FALSE)
      session$sendCustomMessage("aiExpertStopSubtitle", list(
        nsPrefix = ns("")
      ))

      # TTS görselleştiricisini durdur
      tryCatch({
        tts_visualizer$stop()
      }, error = function(e) {})

      # Bekleme süresini başlat (0 geçilirse bekleme olmaz)
      cd <- cooldown_secs %||% COOLDOWN_AFTER_STOP
      if (cd > 0) {
        start_cooldown(cd)
      }

      invisible(NULL)
    }

    # --- Durdurma butonu observer ---
    observeEvent(input$stop_ai_talk, {
      cat("[AI_EXPERT] Durdurma butonu tıklandı.\n")
      stop_speaking(COOLDOWN_AFTER_STOP)
    }, ignoreInit = TRUE)

    # --- İstemciden "konuşma bitti" sinyali ---
    observeEvent(input$ai_expert_speech_ended, {
      if (isTRUE(is_speaking())) {
        is_speaking(FALSE)
        # Bekleme süresini başlat (aktif senaryo bekleme süresiyle)
        cd <- isolate(active_cooldown_seconds()) %||% COOLDOWN_AFTER_PAGE
        start_cooldown(cd)
      }
    }, ignoreInit = TRUE)

    # --- TTS Görselleştiricisi görünürlüğü ---
    # enable_ai_expert veya enable_tts_audio açıkken görselleştiriciyi göster
    observe({
      ai_expert_on <- isTRUE(settings_data$enable_ai_expert) &&
                       identical(settings_data$experience_mode, "kesif")
      tts_on <- isTRUE(settings_data$enable_tts_audio)
      should_show <- ai_expert_on || tts_on

      # İstemciye görselleştiricinin görünürlüğünü bildir
      session$sendCustomMessage("aiExpertVisualizerVisibility", list(
        visible = should_show
      ))
    })

    # --- Dış erişim için fonksiyonlar ---
    return(list(
      start_speaking    = start_speaking,
      stop_speaking     = stop_speaking,
      is_speaking       = is_speaking,
      can_speak         = can_speak,
      set_page          = function(page) {
        current_page(page)
        # JS tarafına sayfa bilgisini gönder (altyazı konumu ayarı için)
        session$sendCustomMessage("aiExpertSetPage", list(page = page))
      },
      set_user_active   = function(active) user_is_active(active),
      set_tts_vocalizing = function(active) tts_vocalizing(active),
      # Bekleme süreleri dış erişim için
      COOLDOWN_GREETING = COOLDOWN_AFTER_GREETING,
      COOLDOWN_PAGE     = COOLDOWN_AFTER_PAGE,
      COOLDOWN_IDLE     = COOLDOWN_AFTER_IDLE,
      COOLDOWN_STOP     = COOLDOWN_AFTER_STOP
    ))
  })
}