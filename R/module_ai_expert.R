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
		  # Boş src tarayıcıda mevcut sayfa URL'sine istek atar ve gizli konsol hatası üretir.
		  src = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
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
    prewarmed_tts   <- reactiveVal(NULL)     # Ön ısıtılmış ilk TTS parçası
    prewarming_tts  <- reactiveVal(NULL)     # Hazırlanmakta olan ilk TTS parçası

    PREWARM_TTL_SECS <- 90                   # Ön ısıtma önbelleği ömrü (sn)

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
    # split_text_for_ai_expert_tts() saf bir metin yardımcısıdır ve
    # R/helpers_ai_expert_chunking.R içinde tutulur. Burada yeniden tanım
    # yapılmaz; modül yalnızca paylaşılan helper'ı çağırır.
	
    get_prewarmed_tts <- function(text, char_id, voice_sel) {
      cache <- isolate(prewarmed_tts())
      if (is.null(cache)) return(NULL)

      age_secs <- tryCatch(
        as.numeric(difftime(Sys.time(), cache$created_at, units = "secs")),
        error = function(e) Inf
      )

      if (!is.finite(age_secs) || age_secs > PREWARM_TTL_SECS) {
        prewarmed_tts(NULL)
        return(NULL)
      }

      if (!identical(cache$text, text)) return(NULL)
      if (!identical(cache$char_id, char_id)) return(NULL)
      if (!identical(cache$voice_sel, voice_sel)) return(NULL)

      cache
    }

    get_inflight_prewarm_tts <- function(text, char_id, voice_sel) {
      inflight <- isolate(prewarming_tts())
      if (is.null(inflight)) return(NULL)

      if (!identical(inflight$text, text)) return(NULL)
      if (!identical(inflight$char_id, char_id)) return(NULL)
      if (!identical(inflight$voice_sel, voice_sel)) return(NULL)

      inflight
    }

    prewarm_speaking <- function(text, selected_char_id = NULL) {
      text <- trimws(as.character(text %||% ""))
      if (!nzchar(text)) return(invisible(FALSE))

      # Telaffuz/yazım düzeltmesi: start_speaking ile aynı metnin önbelleğe
      # alındığından emin olmak için burada da uygulanır. Aksi halde cache
      # anahtarı farklı olur ve prewarm'in TTS önbelleği bulunmaz.
      if (exists("sanitize_ai_expert_pronunciation", mode = "function", inherits = TRUE)) {
        text <- tryCatch(sanitize_ai_expert_pronunciation(text), error = function(e) text)
      }

      tts_available <- FALSE
      tryCatch({
        tts_available <- isTRUE(tts_processor$tts_available())
      }, error = function(e) {})

      if (!tts_available) return(invisible(FALSE))

      char_id <- normalize_character_id(selected_char_id %||% isolate(settings_data$selected_character))
      char_info <- get_character_record(char_id)

      voice_sel <- if (!is.null(char_info) && !is.null(char_info$tts_voice)) {
        char_info$tts_voice
      } else {
        "default"
      }
      # VoxCPM2 referans-ses profili kimliği (tek çözümleme noktası).
      profile_sel <- if (exists("mergen_tts_profile_for_character", mode = "function", inherits = TRUE)) {
        mergen_tts_profile_for_character(char_id)
      } else {
        NULL
      }

      cached <- get_prewarmed_tts(text, char_id, voice_sel)
      if (!is.null(cached)) return(invisible(TRUE))

      inflight <- get_inflight_prewarm_tts(text, char_id, voice_sel)
      if (!is.null(inflight)) return(invisible(TRUE))

      chunks <- split_text_for_ai_expert_tts(text, max_chunk_chars = 220, min_chunk_chars = 70)
      if (length(chunks) == 0) chunks <- list(text)

      cat(sprintf(
        "[AI_EXPERT] İlk TTS parçası ön ısıtılıyor... (karakter: %s)\n",
        char_id
      ))

      # Ön ısıtma konuşma başlamadan yapılır; iptal edilmez (should_cancel yok).
      tts_promise <- tts_processor$synthesize_speech(chunks[[1]], voice = voice_sel, profile_id = profile_sel)

      prewarming_tts(list(
        text = text,
        char_id = char_id,
        voice_sel = voice_sel,
        first_chunk_text = chunks[[1]],
        chunks = chunks,
        promise = tts_promise,
        created_at = Sys.time()
      ))

      tts_promise %...>%
        (function(res) {
          prewarming_tts(NULL)

          if (isTRUE(res$success) && nzchar(res$audio_src)) {
            prewarmed_tts(list(
              text = text,
              char_id = char_id,
              voice_sel = voice_sel,
              first_chunk_text = chunks[[1]],
              chunks = chunks,
              audio_src = res$audio_src,
              duration = res$duration,
              created_at = Sys.time()
            ))

            cat(sprintf(
              "[AI_EXPERT] Ön ısıtılmış ilk TTS parçası hazır (Süre: %.2fs).\n",
              res$duration
            ))
          }
        }) %...!%
        (function(e) {
          prewarming_tts(NULL)
          cat(sprintf("[AI_EXPERT] Ön ısıtma TTS hatası: %s\n", conditionMessage(e)))
        })

      invisible(TRUE)
    }
	
    # --- Konuşmayı başlat ---
    # ÖNEMLİ: Altyazı ve ses senkronizasyonu
    # TTS hazır olana kadar altyazı başlatılmaz, böylece senkronize olurlar
	start_speaking <- function(text, cooldown_secs = COOLDOWN_AFTER_PAGE) {
	  if (is.null(text) || !nzchar(text)) return(invisible(NULL))
	  if (isTRUE(is_speaking())) return(invisible(NULL))

	  # Telaffuz/yazım düzeltmesini güvenlik ağı olarak burada da uygula.
	  # call_ai_expert_llm zaten bu düzeltmeyi yapar; ancak doğrudan
	  # start_speaking çağıran yollar olursa "Bilge Yola" -> "Bilge Yolaç"
	  # düzeltmesi yine de yapılır.
	  if (exists("sanitize_ai_expert_pronunciation", mode = "function", inherits = TRUE)) {
	    text <- tryCatch(sanitize_ai_expert_pronunciation(text), error = function(e) text)
	  }

	  is_speaking(TRUE)
	  last_speak_time(Sys.time())

	  # Persona bilgilerini al (eski kimlikler normalleştirilir)
	  char_id <- normalize_character_id(isolate(settings_data$selected_character))
	  char_info <- get_character_record(char_id)

	  avatar_src <- if (!is.null(char_info)) char_info$avatar else "characters/avatar/emre/avatar.png"
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
          "default"
        }
        # VoxCPM2 referans-ses profili kimliği (tek çözümleme noktası).
        profile_sel <- if (exists("mergen_tts_profile_for_character", mode = "function", inherits = TRUE)) {
          mergen_tts_profile_for_character(char_id)
        } else {
          NULL
        }
        # Not: Eskimiş parça oynatımı zaten her devam çağrısındaki is_speaking()
        # denetimiyle engellenir; eşzamanlılık da synthesize_speech içindeki
        # sınırlı kuyrukla sınırlanır (ek should_cancel gerekmez).

        # İlk sesi daha hızlı başlatmak için metni kısa parçalara böl
        chunks <- split_text_for_ai_expert_tts(text, max_chunk_chars = 220, min_chunk_chars = 70)
        if (length(chunks) == 0) chunks <- list(text)

        cat(sprintf(
          "[AI_EXPERT] TTS %d parçaya bölündü (toplam: %d karakter)...\n",
          length(chunks), nchar(text)
        ))

        queue_remaining_chunks <- function(all_chunks, start_index = 2L) {
          total_chunks <- length(all_chunks)
          if (start_index > total_chunks) return(invisible(NULL))

          # Kalan parçaları seri değil, eşzamanlı başlat.
          # Böylece son parça önceki parçaların sentezini bekleyip gecikmez.
          for (idx in seq.int(start_index, total_chunks)) {
            local({
              current_idx <- idx
              current_text <- all_chunks[[current_idx]]

              cat(sprintf(
                "[AI_EXPERT] TTS parça %d/%d sentezleniyor (%d karakter)...\n",
                current_idx, total_chunks, nchar(current_text)
              ))

              tts_processor$synthesize_speech(
                current_text, voice = voice_sel, profile_id = profile_sel
              ) %...>%
                (function(res) {
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
                }) %...!%
                (function(e) {
                  cat(sprintf(
                    "[AI_EXPERT] TTS parça %d/%d hatası: %s\n",
                    current_idx, total_chunks, conditionMessage(e)
                  ))
                })
            })
          }

          invisible(NULL)
        }

        # YARIŞ DURUMU KORUMASI: İlk parça istemciye gönderildi mi?
        first_chunk_dispatched <- FALSE

        dispatch_audio_start <- function(first_chunk_text, all_chunks, audio_src, audio_duration) {
          if (!isTRUE(is_speaking())) return(invisible(NULL))
          if (isTRUE(first_chunk_dispatched)) return(invisible(NULL))

          tts_visualizer$trigger(duration = 0)

          session$sendCustomMessage("aiExpertStartWithAudio", list(
            text          = first_chunk_text,
            totalChunks   = length(all_chunks),
            avatarSrc     = avatar_src,
            accentColor   = accent_color,
            nsPrefix      = ns(""),
            audioSrc      = audio_src,
            audioDuration = audio_duration,
            fontSize      = font_size
          ))

          first_chunk_dispatched <<- TRUE

          if (length(all_chunks) > 1) {
            queue_remaining_chunks(all_chunks, 2L)
          }

          invisible(NULL)
        }

        dispatch_subtitle_fallback <- function() {
          if (!isTRUE(is_speaking())) return(invisible(NULL))
          if (isTRUE(first_chunk_dispatched)) return(invisible(NULL))

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

          invisible(NULL)
        }

        synthesize_first_chunk_now <- function() {
          tts_processor$synthesize_speech(
            chunks[[1]], voice = voice_sel, profile_id = profile_sel
          ) %...>%
            (function(first_res) {
              if (!isTRUE(is_speaking())) return()

              if (isTRUE(first_res$success) && nzchar(first_res$audio_src)) {
                cat(sprintf(
                  "[AI_EXPERT] İlk TTS parçası hazır (Süre: %.2fs). Konuşma hemen başlatılıyor.\n",
                  first_res$duration
                ))

                dispatch_audio_start(
                  first_chunk_text = chunks[[1]],
                  all_chunks = chunks,
                  audio_src = first_res$audio_src,
                  audio_duration = first_res$duration
                )
              } else {
                dispatch_subtitle_fallback()
              }
            }) %...!%
            (function(e) {
              cat(sprintf("[AI_EXPERT] TTS hatası: %s\n", conditionMessage(e)))
              if (!isTRUE(is_speaking())) return()

              if (isTRUE(first_chunk_dispatched)) {
                cat("[AI_EXPERT] İlk parça zaten gönderilmiş; tam metin geri dönüşü atlandı.\n")
                return()
              }

              dispatch_subtitle_fallback()
            })
        }

        # Önceden hazırlanmış ilk TTS parçası varsa onu kullan
        prewarmed <- get_prewarmed_tts(text, char_id, voice_sel)
        inflight_prewarm <- get_inflight_prewarm_tts(text, char_id, voice_sel)

        if (!is.null(prewarmed) && nzchar(prewarmed$audio_src %||% "")) {
          resolved_chunks <- prewarmed$chunks %||% chunks

          cat(sprintf(
            "[AI_EXPERT] Ön ısıtılmış ilk TTS parçası kullanılıyor (Süre: %.2fs).\n",
            prewarmed$duration
          ))

          dispatch_audio_start(
            first_chunk_text = prewarmed$first_chunk_text %||% resolved_chunks[[1]],
            all_chunks = resolved_chunks,
            audio_src = prewarmed$audio_src,
            audio_duration = prewarmed$duration
          )

          prewarmed_tts(NULL)

        } else if (!is.null(inflight_prewarm) && !is.null(inflight_prewarm$promise)) {
          cat("[AI_EXPERT] Ön ısıtılan ilk TTS parçası hâlâ hazırlanıyor, hazır olur olmaz kullanılacak.\n")

          inflight_prewarm$promise %...>%
            (function(res) {
              if (!isTRUE(is_speaking()) || isTRUE(first_chunk_dispatched)) return()

              ready <- get_prewarmed_tts(text, char_id, voice_sel)

              if (is.null(ready) && isTRUE(res$success) && nzchar(res$audio_src)) {
                ready <- list(
                  first_chunk_text = inflight_prewarm$first_chunk_text %||% chunks[[1]],
                  chunks = inflight_prewarm$chunks %||% chunks,
                  audio_src = res$audio_src,
                  duration = res$duration
                )
              }

              if (!is.null(ready) && nzchar(ready$audio_src %||% "")) {
                resolved_chunks <- ready$chunks %||% chunks

                cat(sprintf(
                  "[AI_EXPERT] Ön ısıtılan ilk TTS parçası yetişti (Süre: %.2fs).\n",
                  ready$duration
                ))

                dispatch_audio_start(
                  first_chunk_text = ready$first_chunk_text %||% resolved_chunks[[1]],
                  all_chunks = resolved_chunks,
                  audio_src = ready$audio_src,
                  audio_duration = ready$duration
                )

                prewarmed_tts(NULL)
              } else {
                synthesize_first_chunk_now()
              }
            }) %...!%
            (function(e) {
              cat(sprintf(
                "[AI_EXPERT] Ön ısıtılan ilk TTS parçası beklenirken hata oluştu: %s\n",
                conditionMessage(e)
              ))

              if (!isTRUE(is_speaking()) || isTRUE(first_chunk_dispatched)) return()
              synthesize_first_chunk_now()
            })

        } else {
          synthesize_first_chunk_now()
        }
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
      start_speaking     = start_speaking,
      prewarm_speaking   = prewarm_speaking,
      stop_speaking      = stop_speaking,
      is_speaking        = is_speaking,
      can_speak          = can_speak,
      set_page           = function(page) {
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