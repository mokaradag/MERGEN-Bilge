# R/module_ai_expert.R
# Dosya Yolu: R/module_ai_expert.R
# Aciklama: AI Uzman (AI Expert) Shiny modulu.
#            Altyazi (subtitle) goruntuleyicisi UI bilesenini ve
#            sunucu tarafindaki durum yonetimini icerir.

#' AI Uzman Altyazi UI Bileseni
#'
#' Sayfa altinda sabit konumlu altyazi seridi olusturur.
#' Bu serit, AI konusmasi sirasinda metin goruntuler.
#'
#' @param id Modul ad alani kimligi
#' @return Altyazi seridi UI tanimi
aiExpertSubtitleUI <- function(id) {
  ns <- NS(id)

  # Sabit konumlu altyazi seridi (tum sayfalarda gorunur)
  tags$div(
    id = ns("subtitle_strip"),
    class = "ai-expert-subtitle-strip ai-expert-hidden",

    # Sol: Karakter avatari
    tags$div(
      class = "ai-expert-avatar-wrapper",
      tags$img(
        id = ns("subtitle_avatar"),
        class = "ai-expert-subtitle-avatar",
        src = ""
      )
    ),

    # Orta: Altyazi metin alani
    tags$div(
      class = "ai-expert-subtitle-text-wrapper",
      tags$span(
        id = ns("subtitle_text"),
        class = "ai-expert-subtitle-text",
        ""
      )
    ),

    # Sag: Durdurma butonu
    tags$div(
      class = "ai-expert-stop-wrapper",
      tags$button(
        id = ns("stop_ai_talk"),
        class = "ai-expert-stop-btn",
        title = "AI konusmasini durdur",
        tags$i(class = "fa-solid fa-xmark")
      )
    )
  )
}

#' AI Uzman Sunucu Modulu
#'
#' AI Uzman konusma durumunu, zamanlamasini ve yarris durumu
#' onleme mantikini yonetir.
#'
#' @param id Modul ad alani kimligi
#' @param settings_data Merkezi ayarlar reaktif degerleri
#' @param tts_processor TTS isleme modulu (sesli cikti icin)
#' @param tts_visualizer TTS gorsellestiricisi (animasyon tetiklemek icin)
#' @return AI Uzman kontrol fonksiyonlarini iceren liste
aiExpertServer <- function(id, settings_data, tts_processor, tts_visualizer) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # --- Reaktif durum degiskenleri ---
    is_speaking     <- reactiveVal(FALSE)    # AI simdi konusuyor mu
    is_cooldown     <- reactiveVal(FALSE)    # Bekleme suresi aktif mi
    last_speak_time <- reactiveVal(NULL)     # Son konusma zamani
    current_page    <- reactiveVal("chat")   # Aktif sayfa
    user_is_active  <- reactiveVal(FALSE)    # Kullanici mesaj gonderiyor mu

    # Bekleme suresi (saniye) - iki konusma arasi minimum sure
    COOLDOWN_SECONDS <- 120

    # Yasakli sayfalar (bu sayfalarda AI konusmaz)
    MUTED_PAGES <- c("settings_kisisel", "admin_analytics", "health")

    # --- Yardimci: AI Uzman konusmasi mumkun mu? ---
    can_speak <- function() {
      # 1. Ozellik acik mi?
      if (!isTRUE(settings_data$enable_ai_expert)) return(FALSE)

      # 2. Butunlesik mod mu?
      if (!identical(settings_data$experience_mode, "kesif")) return(FALSE)

      # 3. Yasakli sayfa mi?
      page <- isolate(current_page())
      if (page %in% MUTED_PAGES) return(FALSE)

      # 4. Zaten konusuyor mu?
      if (isTRUE(is_speaking())) return(FALSE)

      # 5. TTS seslendirmesi veya STT kaydi aktif mi? (yaris durumu onleme)
      if (isTRUE(settings_data$enable_tts_audio)) {
        # TTS aciksa ve kullanici bir prompt gonderdiyse, AI konusmamali
        # (TTS seslendirmesi ile cakisma onlenir)
      }

      # 6. Bekleme suresinde mi?
      if (isTRUE(is_cooldown())) return(FALSE)

      # 7. Son konusmadan yeterli sure gecti mi?
      lst <- isolate(last_speak_time())
      if (!is.null(lst)) {
        elapsed <- as.numeric(difftime(Sys.time(), lst, units = "secs"))
        if (elapsed < COOLDOWN_SECONDS) return(FALSE)
      }

      # 8. Kullanici aktif mi? (yaziyorsa veya istek gonderdiyse konusma)
      if (isTRUE(user_is_active())) return(FALSE)

      return(TRUE)
    }

    # --- Konusmayi baslat ---
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

      # Istemciye altyazi goster mesaji gonder
      session$sendCustomMessage("aiExpertStartSubtitle", list(
        text        = text,
        avatarSrc   = avatar_src,
        accentColor = accent_color,
        nsPrefix    = ns("")
      ))

      # TTS ile seslendirme (TTS islemcisi kullanilabilir durumda ise)
      tts_available <- FALSE
      tryCatch({
        tts_available <- isTRUE(tts_processor$tts_available())
      }, error = function(e) {})

      if (tts_available) {
        # TTS ses tonunu karakter ayarindan al
        voice_sel <- if (!is.null(char_info) && !is.null(char_info$tts_voice)) {
          char_info$tts_voice
        } else {
          "tr-male-1"
        }

        # TTS icin metin hazirlama
        clean_text <- prepare_ai_expert_tts_text(text)

        tts_processor$synthesize_speech(clean_text, voice = voice_sel) %...>%
          (function(res) {
            if (isTRUE(res$success) && nzchar(res$audio_src)) {
              cat(sprintf("[AI_EXPERT] TTS basarili (Sure: %.2fs)\n", res$duration))

              # TTS gorsellestiricisini tetikle
              tts_visualizer$trigger(duration = res$duration)

              # Istemciye sesi gonder
              session$sendCustomMessage("aiExpertPlayAudio", list(
                src      = res$audio_src,
                duration = res$duration,
                nsPrefix = ns("")
              ))
            } else {
              cat("[AI_EXPERT] TTS basarisiz, sadece altyazi gosteriliyor.\n")
              # TTS basarisiz olsa da altyazi zamanlayicisini baslat
              session$sendCustomMessage("aiExpertNoAudioFallback", list(
                textLength = nchar(text),
                nsPrefix   = ns("")
              ))
            }
          }) %...!%
          (function(e) {
            cat(sprintf("[AI_EXPERT] TTS hatasi: %s\n", conditionMessage(e)))
            session$sendCustomMessage("aiExpertNoAudioFallback", list(
              textLength = nchar(text),
              nsPrefix   = ns("")
            ))
          })
      } else {
        # TTS yoksa sadece altyazi goster, sure tahminle
        session$sendCustomMessage("aiExpertNoAudioFallback", list(
          textLength = nchar(text),
          nsPrefix   = ns("")
        ))
      }

      invisible(NULL)
    }

    # --- Konusmayi durdur ---
    stop_speaking <- function() {
      if (!isTRUE(is_speaking())) return(invisible(NULL))

      is_speaking(FALSE)
      session$sendCustomMessage("aiExpertStopSubtitle", list(
        nsPrefix = ns("")
      ))

      # Bekleme suresini baslat
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

    # --- Istemciden "konusma bitti" sinyali ---
    observeEvent(input$ai_expert_speech_ended, {
      is_speaking(FALSE)
      # Bekleme suresini baslat
      is_cooldown(TRUE)
      shinyjs::delay(COOLDOWN_SECONDS * 1000, {
        is_cooldown(FALSE)
      })
    })

    # --- TTS Gorsellestiricisi gorunurlugu ---
    # enable_ai_expert veya enable_tts_audio acikken gorsellestiricyi goster
    observe({
      ai_expert_on <- isTRUE(settings_data$enable_ai_expert) &&
                       identical(settings_data$experience_mode, "kesif")
      tts_on <- isTRUE(settings_data$enable_tts_audio)
      should_show <- ai_expert_on || tts_on

      # Istemciye gorsellestiricinin gorunurlugunu bildir
      session$sendCustomMessage("aiExpertVisualizerVisibility", list(
        visible = should_show
      ))
    })

    # --- Dis erisim icin fonksiyonlar ---
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