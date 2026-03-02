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

      avatar_src <- if (!is.null(char_info)) char_info$avatar else "mergen_avatar.png"
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

        # TTS için metin hazırlama
        clean_text <- prepare_ai_expert_tts_text(text)

        cat(sprintf("[AI_EXPERT] TTS sentezleniyor (%d karakter)...\n", nchar(clean_text)))

        # ÖNEMLİ: Altyazıyı TTS hazır olana kadar BEKLETEREK senkronize ediyoruz
        tts_processor$synthesize_speech(clean_text, voice = voice_sel) %...>%
          (function(res) {
            # Hâlâ konuşma durumundaysa devam et (durdurulmuş olabilir)
            if (!isTRUE(is_speaking())) return()

            if (isTRUE(res$success) && nzchar(res$audio_src)) {
              cat(sprintf("[AI_EXPERT] TTS hazır (Süre: %.2fs). Altyazı ve ses birlikte başlatılıyor.\n", res$duration))

              # TTS görselleştiricisini tetikle (süre 0 = zamanlayıcı yok, ses bitince JS tarafında kapanır)
              tts_visualizer$trigger(duration = 0)

              # Altyazı + ses birlikte başlatılıyor (senkronize)
              session$sendCustomMessage("aiExpertStartWithAudio", list(
                text        = text,
                avatarSrc   = avatar_src,
                accentColor = accent_color,
                nsPrefix    = ns(""),
                audioSrc    = res$audio_src,
                audioDuration = res$duration,
                fontSize    = font_size
              ))
            } else {
              cat("[AI_EXPERT] TTS başarısız, sadece altyazı gösteriliyor.\n")
              # TTS başarısız - altyazıyı tek başına göster
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
            # Hata durumunda altyazıyı sessiz göster
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
        # Görselleştiriciyisesiz bile aktive et (animasyon göster)
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
      set_page          = function(page) current_page(page),
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