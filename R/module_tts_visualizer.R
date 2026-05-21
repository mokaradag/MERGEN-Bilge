# R/module_tts_visualizer.R
# Dosya Yolu: R/module_tts_visualizer.R
# Açıklama: TTS (Metinden Sese) işlemi sırasında aktif olan görselleştirici modülü.
#           Karakter avatarı, ismi ve konuşma animasyonunu (canvas) yönetir.

#' TTS Görselleştirici UI
#'
#' Modülün arayüz bileşenlerini tanımlar. Sol tarafta karakter bilgileri,
#' sağda ise dinamik dalga animasyonu için bir canvas alanı içerir.
#'
#' @param id Modül ad alanı kimliği
#' @return Görselleştirici için UI tanımı
ttsVisualizerUI <- function(id) {
  ns <- NS(id)
  
  tags$div(
    class = "tts-outer-wrapper",
    
    # 1. Ana Konteynır (Sol tarafta yer alır)
    tags$div(
      id = ns("container"), 
      class = "tts-visualizer-container shiny-visual-hidden", 
      
      # Karakter Avatarı ve İsmi
      tags$div(
        class = "tts-char-info",
        tags$img(id = ns("char_avatar"), class = "tts-avatar-img", src = ""),
        tags$span(id = ns("char_name"), class = "tts-name-text", "")
      ),
      
      # Animasyon Çizim Alanı (Canvas)
      tags$canvas(id = "tts_canvas", class = "tts-canvas"),
      
      # Durdurma İpucu (Varsayılan olarak gizlidir, konuşma modunda üzerine gelince gösterilir)
      tags$div(
        class = "tts-tooltip", 
        tags$i(class = "fa-solid fa-circle-stop"), 
        tags$span("Seslendirmeyi durdur")
      )
    )
  )
}

#' TTS Görselleştirici Sunucu Modülü
#'
#' Karakter seçimlerine göre temayı günceller ve TTS motorundan gelen
#' sinyallere göre animasyon durumlarını yönetir.
#'
#' @param id Modül ad alanı kimliği
#' @param settings_data Merkezi ayarlar reaktif değerleri
#' @return trigger ve stop fonksiyonlarını içeren bir liste
ttsVisualizerServer <- function(id, settings_data) {
  moduleServer(id, function(input, output, session) {
    
    ns <- session$ns

    #' Görselleştirici Durumunu Güncelle
    #' 
    #' @param state Durum ("idle", "talking", "stop")
    #' @param duration Konuşma süresi (saniye)
    send_state <- function(state = "idle", duration = NULL) {
      char_id <- normalize_character_id(settings_data$selected_character)
      char_info <- get_character_record(char_id)

      display_name <- if (!is.null(char_info)) char_info$display_name else "EMRE ONAT"
      accent_color <- if (!is.null(char_info)) char_info$accent else "#7C4DFF"
      avatar_src <- if (!is.null(char_info) && !is.null(char_info$avatar)) char_info$avatar else "characters/avatar/emre/avatar.png"

      # 1. İçeriği Güncelle (Resim, İsim, Renkler)
      shinyjs::runjs(sprintf("$('#%s').attr('src', '%s');", ns("char_avatar"), avatar_src))
      shinyjs::runjs(sprintf("$('#%s').text('%s');", ns("char_name"), display_name))
      shinyjs::runjs(sprintf("$('#%s').css('border-color', '%s');", ns("char_avatar"), accent_color))
      shinyjs::runjs(sprintf("$('#%s').css('color', '%s');", ns("char_name"), accent_color))

      # 2. CSS Sınıflarını Yönet (Konuşma modu aktifleştirme)
      if (state == "talking") {
        shinyjs::addClass(id = "container", class = "talking-mode")
      } else {
        shinyjs::removeClass(id = "container", class = "talking-mode")
      }

      # 3. JavaScript Tarafına Animasyon Mesajı Gönder
      session$sendCustomMessage(
        "updateTTSVisualizer",
        list(
          state = state,
          duration = duration,
          name = display_name,
          color = accent_color
        )
      )
    }

    # Yardımcı Fonksiyonlar
    trigger_animation <- function(duration = 5) {
      send_state(state = "talking", duration = duration)
    }

    stop_animation <- function() {
      send_state(state = "stop")
    }

    # Görünürlük Mantığı (TTS veya AI Uzman açıkken göster)
    observe({
      tts_on <- isTRUE(settings_data$enable_tts_audio)
      ai_expert_on <- isTRUE(settings_data$enable_ai_expert) &&
                       identical(settings_data$experience_mode, "kesif")
      is_enabled <- tts_on || ai_expert_on
      shinyjs::toggleClass(id = "container", class = "shiny-visual-hidden", condition = !is_enabled)

      if (is_enabled) {
        # Sekme geçişlerinde boyutlandırma sorunlarını önlemek için gecikmeli denemeler
        shinyjs::delay(200, {
          session$sendCustomMessage("resizeTTSVisualizer", list())
          send_state(state = "idle")
        })
        shinyjs::delay(800, {
          session$sendCustomMessage("resizeTTSVisualizer", list())
        })
      } else {
        stop_animation()
      }
    })

    # Karakter değiştiğinde temayı güncelle
    observeEvent(settings_data$selected_character, {
      send_state(state = "idle")
    }, ignoreNULL = FALSE)

    # Modül dışından erişilecek fonksiyonlar
    return(list(
      trigger = trigger_animation,
      stop = stop_animation
    ))
  })
}