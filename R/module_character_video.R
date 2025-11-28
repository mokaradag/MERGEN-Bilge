# R/module_character_video.R
# Karakter Video Modülü - Ayarlar sayfasında video oynatma işlevselliği

#' Karakter video verilerini döndürür
#' @return Karakter video bilgilerini içeren liste
get_character_videos <- function() {
  list(
    mergen = list(
      id = "mergen",
      video = "characters/video/Mergen_video.mp4",
      accent = "#7C4DFF"
    ),
    ulgen = list(
      id = "ulgen",
      video = "characters/video/Ulgen_video.mp4",
      accent = "#2F6DF6"
    ),
    kayra = list(
      id = "kayra",
      video = "characters/video/Kayra_video.mp4",
      accent = "#12A97B"
    ),
    erlik = list(
      id = "erlik",
      video = "characters/video/Erlik_video.mp4",
      accent = "#B66A2C"
    ),
    umay = list(
      id = "umay",
      video = "characters/video/Umay_Ana_video.mp4",
      accent = "#E98686"
    )
  )
}

#' Karakter video UI bileşeni
#' @param id Namespace ID
#' @return Video container UI
characterVideoUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    # Video container - ateş efekti ile birlikte
    div(
      id = ns("video_overlay"),
      class = "character-video-overlay",
      style = "display: none;",
      
      # Ateş parçacıkları JS tarafından eklenecek
      
      # Video elementi - varsayılan ses AÇIK
      tags$video(
        id = ns("character_video"),
        class = "character-video",
        playsinline = TRUE,
        preload = "auto"
      ),
      
      # Ses kontrol butonu
      tags$button(
        id = ns("mute_toggle"),
        class = "video-mute-btn",
        title = "Sesi Aç/Kapat",
        onclick = sprintf("toggleVideoMute('%s')", ns("character_video")),
        tags$i(class = "fa-solid fa-volume-xmark")
      )
    )
  )
}

#' Karakter video sunucu modülü
#' @param id Namespace ID
#' @param character_selected Seçili karakter reactive değeri
characterVideoServer <- function(id, character_selected) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Video verilerini yükle
    video_data <- get_character_videos()
    
    # Karakter değiştiğinde video tetikle
    observeEvent(character_selected(), {
      char_id <- character_selected()
      req(char_id)
      
      # Karakter ID'sini normalize et (umay -> umay)
      char_key <- gsub("_ana$", "", char_id, ignore.case = TRUE)
      if (char_key == "umay ana") char_key <- "umay"
      char_key <- tolower(gsub(" ", "", char_key))
      
      char_video <- video_data[[char_key]]
      
      if (!is.null(char_video)) {
        session$sendCustomMessage("playCharacterVideo", list(
          videoElementId = ns("character_video"),
          overlayId = ns("video_overlay"),
          muteButtonId = ns("mute_toggle"),
          videoSrc = char_video$video,
          accentColor = char_video$accent,
          delay = 1000,
          containerId = paste0(gsub("-character_video$", "", id), "-character_image_area")
        ))
      }
    }, ignoreInit = TRUE)
  })
}