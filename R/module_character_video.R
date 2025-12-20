# R/module_character_video.R

get_character_video_data <- function(char_id) {
  char_key <- tolower(trimws(char_id))
  if (char_key == "umay ana") char_key <- "umay"
  
  cat(sprintf("[VIDEO R] get_character_video_data çağrıldı: '%s' -> '%s'\n", char_id, char_key))
  
  image_map <- list(
    "mergen" = "Mergen_resim_original.png",
    "ulgen" = "Ulgen_resim_original.png",
    "kayra" = "Kayra_resim_original.png",
    "erlik" = "Erlik_resim_original.png",
    "umay" = "Umay_Ana_resim_original.png"
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
	  sys_dir <- file.path("www", "characters", "video", char_key, type)
	  
	  cat(sprintf("[VIDEO R] Taranıyor: %s (var mı: %s)\n", sys_dir, dir.exists(sys_dir)))
	  
	  if (!dir.exists(sys_dir)) {
		return(character(0))
	  }
	  
	  files <- list.files(sys_dir, pattern = "\\.(mp4|webm|MP4|WEBM)$", 
						 full.names = FALSE, ignore.case = TRUE)
	  
	  cat(sprintf("[VIDEO R] Bulunan dosyalar (%s): %s\n", type, 
				  if(length(files) > 0) paste(files, collapse = ", ") else "YOK"))
	  
	  if (length(files) == 0) {
		return(character(0))
	  }
	  
	  paths <- file.path("characters", "video", char_key, type, files)
	  return(paths)
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
  
  cat(sprintf("[VIDEO R] Sonuç: char=%s, resim=%s, intro=%d, loop=%d, select=%d\n",
              result$character,
              result$image,
              length(result$videos$intro),
              length(result$videos$loop),
              length(result$videos$select)))
  
  return(result)
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