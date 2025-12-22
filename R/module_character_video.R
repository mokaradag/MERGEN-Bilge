# R/module_character_video.R

get_character_video_data <- function(char_id) {
  char_key <- tolower(trimws(char_id))
  if (char_key == "umay ana") char_key <- "umay"
  
  cat(sprintf("[VIDEO R] get_character_video_data çağrıldı: '%s' -> '%s'\n", char_id, char_key))
  
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
    # Fallback to existing logic or empty
    image_path <- ""
  } else {
    image_path <- file.path("characters", "resim", img_filename)
  }
  
  # Video dosyalari tarama fonksiyonu
	scan_videos <- function(type) {
	  sys_dir <- file.path("www", "characters", "video", char_key, type)
	  
	  if (!dir.exists(sys_dir)) {
		return(list())  # Boş liste döndür (JSON'da [])
	  }
	  
	  files <- list.files(sys_dir, pattern = "\\.(mp4|webm|MP4|WEBM)$", 
						  full.names = FALSE, ignore.case = TRUE)
	  
	  cat(sprintf("[VIDEO R] %s - %s: %d dosya bulundu\n", char_key, type, length(files)))
	  
	  if (length(files) == 0) {
		return(list())  # Boş liste
	  }
	  
	  paths <- file.path("characters", "video", char_key, type, files)
	  
	  as.list(paths)
	}
  
  result <- list(
    character = char_key,
    image = image_path,
    videos = list(
      intro = scan_videos("intro"),
      loop = scan_videos("loop"),
      select = scan_videos("select")
    )
  )
  
  return(result)
}

characterVideoUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(
      id = ns("video_container"),
      class = "cinematic-video-container",
      tags$canvas(
        id = "character-border-canvas",
        class = "character-border-canvas"
      ),
      tags$video(
        id = ns("character_player"),
        class = "character-video-player",
        autoplay = FALSE,
        playsinline = TRUE,
        muted = FALSE,
        preload = "none"
      ),
      tags$img(
        id = ns("character_static_img"),
        class = "character-static-image",
        src = "" 
      )
    ),
	tags$script(sprintf("
      $(document).ready(function() {
        // Initialize Video Manager
        CinematicVideoManager.init({
          videoElementId: '%s',
          imageElementId: '%s'
        });
        
        // Initialize Border Effects
        if (typeof CharacterBorderEffects !== 'undefined') {
          CharacterBorderEffects.init({
            canvasId: 'character-border-canvas'
          });
        }
      });
    ", ns("character_player"), ns("character_static_img")))
  )
}

characterVideoServer <- function(id, selected_character_trigger) {
  moduleServer(id, function(input, output, session) {
    
    observeEvent(selected_character_trigger(), {
      char_id <- selected_character_trigger()
      video_data <- get_character_video_data(char_id)
      
      chars_data <- get_characters_data()
      character_data <- Find(function(x) x$id == char_id, chars_data$styles)
      
      if (!is.null(character_data)) {
        color_data <- list(
          accent = character_data$accent,
          accent_hover = character_data$accent_hover,
          accent_active = character_data$accent_active
        )
        session$sendCustomMessage("updateCharacterBorderColors", color_data)
      }
      
      session$sendCustomMessage("updateCharacterVideo", video_data)
    })
    
  })
}