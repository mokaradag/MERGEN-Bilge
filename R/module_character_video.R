# R/module_character_video.R

get_character_video_data <- function(char_id) {
  # Karakter klasör adlari ve resim dosya eslesmeleri
  # Klasör isimleri kucuk harf varsayilmistir: mergen, ulgen, kayra, erlik, umay
  
  char_key <- tolower(char_id)
  if (char_key == "umay ana") char_key <- "umay"
  
  # Resim dosya isimleri haritalamasi
  image_map <- list(
    "mergen" = "Mergen_resim.original.png",
    "ulgen" = "Ulgen_resim.original.png",
    "kayra" = "Kayra_resim.original.png",
    "erlik" = "Erlik_resim.original.png",
    "umay" = "Umay_Ana_resim.original.png"
  )
  
  # Resim yolu
  img_filename <- image_map[[char_key]]
  if (is.null(img_filename)) {
    # Varsayilan veya hata durumu
    image_path <- ""
  } else {
    image_path <- file.path("characters", "resim", img_filename)
  }
  
  # Video dosyalari tarama fonksiyonu
  scan_videos <- function(type) {
    # www klasoru kok dizindir, list.files icin tam yol gerekir
    # Ancak URL icin www kismi atilir
    sys_dir <- file.path("www", "characters", "video", char_key, type)
    
    if (dir.exists(sys_dir)) {
      files <- list.files(sys_dir, pattern = "\\.(mp4|webm)$", full.names = FALSE)
      if (length(files) > 0) {
        return(file.path("characters", "video", char_key, type, files))
      }
    }
    return(character(0))
  }
  
  list(
    character = char_key,
    image = image_path,
    videos = list(
      intro = scan_videos("intro"),
      loop = scan_videos("loop"),
      select = scan_videos("select")
    )
  )
}

characterVideoUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(
      id = ns("video_container"),
      class = "cinematic-video-container",
      style = "position: relative; width: 100%; height: 100%; overflow: hidden; border-radius: 10px;",
      tags$video(
        id = ns("character_player"),
        class = "character-video-player",
        style = "width: 100%; height: 100%; object-fit: cover; display: none;",
        autoplay = TRUE,
        playsinline = TRUE
      ),
      tags$img(
        id = ns("character_static_img"),
        class = "character-static-image",
        style = "width: 100%; height: 100%; object-fit: cover; display: block;",
        src = "" 
      )
    ),
    tags$script(sprintf("
      $(document).ready(function() {
        CinematicVideoManager.init({
          videoElementId: '%s',
          imageElementId: '%s'
        });
      });
    ", ns("character_player"), ns("character_static_img")))
  )
}

characterVideoServer <- function(id, selected_character_trigger) {
  moduleServer(id, function(input, output, session) {
    
    # Karakter degistiginde verileri guncelle ve introyu baslat
    observeEvent(selected_character_trigger(), {
      char_id <- selected_character_trigger()
      video_data <- get_character_video_data(char_id)
      session$sendCustomMessage("updateCharacterVideo", video_data)
    })
    
    # Ayarlari Kaydet butonuna basildiginda
    # Not: module_settings.R icindeki triggerVideoSelection mesaji JS tarafindan dinlenir
  })
}