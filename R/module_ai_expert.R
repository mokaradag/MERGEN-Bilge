# R/module_ai_expert.R
# Dosya Yolu: R/module_ai_expert.R
# Açıklama: AI Uzman (AI Expert) Shiny modülü.
#            Altyazı (subtitle) görüntüleyicisi UI bileşenini ve
#            sunucu tarafındaki durum yönetimini içerir.

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
        class = "ai-expert-stop-btn",
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

    # Bekleme süresi (saniye) - iki konuşma arası minimum süre
    COOLDOWN_SECONDS <- 120

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

      # 5. TTS seslendirmesi veya STT kaydı aktif mi? (yarış durumu önleme)
      if (isTRUE(settings_data$enable_tts_audio)) {
        # TTS açıksa ve kullanıcı bir prompt gönderdiyse, AI konuşmamalı
        # (TTS seslendirmesi ile çakışma önlenir)
      }

      # 6. Bekleme süresinde mi?
      if (isTRUE(is_cooldown())) return(FALSE)

      # 7. Son konuşmadan yeterli süre geçti mi?
      lst <- isolate(last_speak_time())
      if (!is.null(lst)) {
        elapsed <- as.numeric(difftime(Sys.time(), lst, units = "secs"))
        if (elapsed < COOLDOWN_SECONDS) return(FALSE)
      }

      # 8. Kullanıcı aktif mi? (yazıyorsa veya istek gönderdiyse konuşma)
      if (isTRUE(user_is_active())) return(FALSE)

      return(TRUE)
    }

    # --- Konuşmayı başlat ---
    start_speaking <- function(text) {
      if (is.null(text) || !nzchar(text)) return(invisible(NULL))
      if (isTRUE(is_speaking())) return(invisible(NULL))

      is_speaking(TRUE)
      last_speak_time(Sys.time())

      # Karakter bilgilerini al
      char_id <- isolate(settings_data$selected_character) %||% "mergen"
      chars_data <- get_characters_data()
      char_info <- Find(function(x) x$id == char_id, chars_data$styles)

      avatar_src <- if (!is.null(char_info)) char_info$avatar else "mergen_avatar.png"
      accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"

      # İstemciye altyazı göster mesajı gönder
      session$sendCustomMessage("aiExpertStartSubtitle", list(
        text        = text,
        avatarSrc   = avatar_src,
        accentColor = accent_color,
        nsPrefix    = ns("")
      ))

      # TTS ile seslendirme (TTS işlemcisi kullanılabilir durumda ise)
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

        # TTS için metin hazırlama
        clean_text <- prepare_ai_expert_tts_text(text)

        tts_processor$synthesize_speech(clean_text, voice = voice_sel) %...>%
          (function(res) {
            if (isTRUE(res$success) && nzchar(res$audio_src)) {
              cat(sprintf("[AI_EXPERT] TTS başarılı (Süre: %.2fs)\n", res$duration))

              # TTS görselleştiricisini tetikle
              tts_visualizer$trigger(duration = res$duration)

              # İstemciye sesi gönder
              session$sendCustomMessage("aiExpertPlayAudio", list(
                src      = res$audio_src,
                duration = res$duration,
                nsPrefix = ns("")
              ))
            } else {
              cat("[AI_EXPERT] TTS başarısız, sadece altyazı gösteriliyor.\n")
              # TTS başarısız olsa da altyazı zamanlayıcısını başlat
              session$sendCustomMessage("aiExpertNoAudioFallback", list(
                textLength = nchar(text),
                nsPrefix   = ns("")
              ))
            }
          }) %...!%
          (function(e) {
            cat(sprintf("[AI_EXPERT] TTS hatası: %s\n", conditionMessage(e)))
            session$sendCustomMessage("aiExpertNoAudioFallback", list(
              textLength = nchar(text),
              nsPrefix   = ns("")
            ))
          })
      } else {
        # TTS yoksa sadece altyazı göster, süre tahminle
        session$sendCustomMessage("aiExpertNoAudioFallback", list(
          textLength = nchar(text),
          nsPrefix   = ns("")
        ))
      }

      invisible(NULL)
    }

    # --- Konuşmayı durdur ---
    stop_speaking <- function() {
      if (!isTRUE(is_speaking())) return(invisible(NULL))

      is_speaking(FALSE)
      session$sendCustomMessage("aiExpertStopSubtitle", list(
        nsPrefix = ns("")
      ))

      # Bekleme süresini başlat
      is_cooldown(TRUE)
      shinyjs::delay(COOLDOWN_SECONDS * 1000, {
        is_cooldown(FALSE)
      })

      invisible(NULL)
    }

    # --- Durdurma butonu observer ---
    observeEvent(input$stop_ai_talk, {
      stop_speaking()
    })

    # --- İstemciden "konuşma bitti" sinyali ---
    observeEvent(input$ai_expert_speech_ended, {
      is_speaking(FALSE)
      # Bekleme süresini başlat
      is_cooldown(TRUE)
      shinyjs::delay(COOLDOWN_SECONDS * 1000, {
        is_cooldown(FALSE)
      })
    })

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
      start_speaking  = start_speaking,
      stop_speaking   = stop_speaking,
      is_speaking     = is_speaking,
      can_speak       = can_speak,
      set_page        = function(page) current_page(page),
      set_user_active = function(active) user_is_active(active)
    ))
  })
}