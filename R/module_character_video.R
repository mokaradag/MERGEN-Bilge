# R/module_character_video.R
# Karakter Video Modülü - Ayarlar sayfasında video oynatma işlevselliği

#' Karakter video verilerini döndürür (Gelişmiş Kategorili Yapı)
#' @return Karakter video bilgilerini ve dosya listelerini içeren liste
get_character_videos <- function() {
  # Karakterlerin listesi ve renkleri
  chars <- list(
    mergen = "#7C4DFF",
    ulgen = "#2F6DF6",
    kayra = "#12A97B",
    erlik = "#B66A2C",
    umay = "#E98686"
  )
  
  video_db <- list()
  
  for (char_id in names(chars)) {
    # Klasör yolları (www/ olmadan relative path)
    base_path_www <- file.path("www", "characters", "video", char_id)
    
    # Yardımcı fonksiyon: Klasördeki mp4'leri listele
    get_files <- function(category) {
      path <- file.path(base_path_www, category)
      if (dir.exists(path)) {
        files <- list.files(path, pattern = "\\.mp4$", full.names = FALSE)
        if (length(files) > 0) {
          # Browser için 'www' prefixini kaldırıp path oluştur
          return(file.path("characters", "video", char_id, category, files))
        }
      }
      return(character(0))
    }
    
    # 3 Kategoriyi tara
    intro_videos <- get_files("intro")
    loop_videos <- get_files("loop")
    select_videos <- get_files("select")
    
    # Eğer alt klasörler boşsa eski usül tek dosya fallback (Geriye uyumluluk)
    legacy_video <- file.path("characters", "video", paste0(tools::toTitleCase(char_id), "_video.mp4"))
    
    # Veri yapısını oluştur
    video_db[[char_id]] <- list(
      id = char_id,
      accent = chars[[char_id]],
      # JS tarafına gönderilecek playlist
      playlist = list(
        intro = if(length(intro_videos) > 0) intro_videos else legacy_video,
        loop = if(length(loop_videos) > 0) loop_videos else legacy_video,
        select = if(length(select_videos) > 0) select_videos else legacy_video
      )
    )
  }
  
  return(video_db)
}

#' Karakter video UI bileşeni
#' @param id Namespace ID
#' @return Video container UI
characterVideoUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    # Video container - gelişmiş efektler ile
    div(
      id = ns("video_overlay"),
      class = "character-video-overlay",
      style = "display: none;",
      
      # Enerji dalgası efekti
      div(class = "energy-wave"),
      
      # Işık hüzmeleri
      div(class = "light-beam beam-1"),
      div(class = "light-beam beam-2"),
      div(class = "light-beam beam-3"),
      div(class = "light-beam beam-4"),
      
      # Ateş parçacıkları JS tarafından eklenecek
      
      # Video wrapper - kırpma için
      div(
        class = "character-video-wrapper",
        # Video elementi - varsayılan ses AÇIK
        tags$video(
          id = ns("character_video"),
          class = "character-video",
          playsinline = TRUE,
          preload = "auto"
        )
      ),
      
      # Ses kontrol butonu - SES AÇIK ikonu ile başla
      tags$button(
        id = ns("mute_toggle"),
        class = "video-mute-btn is-unmuted",
        title = "Sesi Kapat",
        onclick = sprintf("toggleVideoMute('%s')", ns("character_video")),
        tags$i(class = "fa-solid fa-volume-high")
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
    
    # Video verilerini dinamik olarak yükle
    video_data <- reactive({ get_character_videos() })
    
    # 1. Karakter değiştiğinde (Intro -> Loop başlar)
    observeEvent(character_selected(), {
      char_id <- character_selected()
      req(char_id)
      
      # ID Normalizasyonu
      char_key <- gsub("_ana$", "", char_id, ignore.case = TRUE)
      if (char_key == "umay ana") char_key <- "umay"
      char_key <- tolower(gsub(" ", "", char_key))
      
      char_info <- video_data()[[char_key]]
      
      if (!is.null(char_info)) {
        session$sendCustomMessage("initCharacterVideoSystem", list(
          videoElementId = ns("character_video"),
          overlayId = ns("video_overlay"),
          muteButtonId = ns("mute_toggle"),
          playlist = char_info$playlist,     # Tüm listeleri gönder
          accentColor = char_info$accent,
          containerId = paste0(gsub("-character_video$", "", id), "-character_image_area"),
          mode = "intro" # Başlangıç modu
        ))
      }
    }, ignoreInit = TRUE)
    
    # 2. Ayarlar Kaydedildiğinde (Selection videosu tetikle)
    # Bu event dışarıdan (settings module) tetiklenecek bir input/reactive bekleyebilir
    # Ancak modüler yapı gereği custom message listener ekleyebiliriz.
    
    observeEvent(input$trigger_selection_video, {
       session$sendCustomMessage("triggerVideoSelection", list(
         videoElementId = ns("character_video")
       ))
    })
  })
}