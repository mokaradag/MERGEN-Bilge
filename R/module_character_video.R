# R/module_character_video.R
# Dosya Yolu: R/module_character_video.R
# Açıklama: Karakterlerin sinematik video ve statik görsel yönetimini sağlayan modül.
#           Karakter değişimlerinde ilgili video dosyalarını tarar ve 
#           JavaScript tarafındaki CinematicVideoManager'a veri iletir.

#' Persona Video Verilerini Getir
#'
#' @param char_id Persona kimliği (emre, selin, deniz, can, ipek). Eski
#'        kimlikler de normalize_character_id() ile güvenle çözülür.
#' @return Personanın görsel yollarını ve video listelerini (intro, loop, select) içeren liste
get_character_video_data <- function(char_id) {
  # Persona kimliğini yeni biçime normalleştir (eski kimlikler de çözülür)
  char_key <- normalize_character_id(char_id)

  cat(sprintf("[VIDEO R] get_character_video_data çağrıldı: '%s' -> '%s'\n", char_id, char_key))

  # Statik görsel yolu config_characters.R'den gelir; modül kendi dosya adı
  # switch'ini yazmaz (tek kaynak: get_character_record).
  char_record <- get_character_record(char_key)
  image_path <- char_record$image %||% ""

  # Belirli bir tipteki (intro, loop, select) video dosyalarını dizinden tarayan iç fonksiyon
	scan_videos <- function(type) {
	  # Fiziksel dosya yolunu belirle
	  sys_dir <- file.path("www", "characters", "video", char_key, type)
	  
	  if (!dir.exists(sys_dir)) {
		return(list())  # Dizin yoksa boş liste döndür (JSON'da [])
	  }
	  
	  # Desteklenen video formatlarını tara
	  files <- list.files(sys_dir, pattern = "\\.(mp4|webm|MP4|WEBM)$", 
						  full.names = FALSE, ignore.case = TRUE)
	  
	  cat(sprintf("[VIDEO R] %s - %s: %d dosya bulundu\n", char_key, type, length(files)))
	  
	  if (length(files) == 0) {
		return(list())  # Dosya yoksa boş liste
	  }
	  
	  # İstemci (browser) tarafında kullanılacak yolları oluştur
	  paths <- file.path("characters", "video", char_key, type, files)
	  
	  as.list(paths)
	}
  
  # JS tarafına gönderilecek veri yapısını hazırla
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

#' Karakter Video Modülü UI
#'
#' @param id Modül ad alanı kimliği
#' @return Video oynatıcı ve statik resim elementlerini içeren UI tanımı
characterVideoUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(
      id = ns("video_container"),
      class = "cinematic-video-container",
      # Ana video oynatıcı elementi
      tags$video(
        id = ns("character_player"),
        class = "character-video-player",
        autoplay = FALSE,
        playsinline = TRUE,
        muted = TRUE,
        preload = "none"
      ),
      # Video yüklenene kadar veya hata durumunda gösterilecek statik resim
		tags$img(
		  id = ns("character_static_img"),
		  class = "character-static-image",
		  # Boş src tarayıcıda mevcut sayfa URL'sine istek atar ve gizli konsol hatası üretir.
		  src = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
		)
    ),
    # CinematicVideoManager bileşenini başlatan ve elemanları bağlayan betik
    # Başlatma betiği: Daha uzun süre dener, bulamazsa sekme geçişinde yedek mekanizma devreye girer.
    # Not: JavaScript içeriği HTML() ile işaretlenir; aksi halde && ve < gibi operatörler
    #       HTML entity olarak kaçırılır ve tarayıcıda söz dizimi hatası oluşur.
    tags$script(HTML(sprintf("
      (function() {
        var videoId = '%s';
        var imageId = '%s';
        var attempts = 0;
        var maxAttempts = 60;
        function tryInit() {
          attempts++;
          if (typeof CinematicVideoManager !== 'undefined' &&
              document.getElementById(videoId) &&
              document.getElementById(imageId)) {
            CinematicVideoManager.init({
              videoElementId: videoId,
              imageElementId: imageId
            });
          } else if (attempts < maxAttempts) {
            // İlk 20 denemede 250ms, sonrasında 500ms aralıkla dene
            var delay = attempts < 20 ? 250 : 500;
            setTimeout(tryInit, delay);
          } else {
            console.warn('[VIDEO] Başlatma: elemanlar henüz bulunamadı, sekme geçişinde tekrar denenecek');
          }
        }
        if (document.readyState === 'complete' || document.readyState === 'interactive') {
          setTimeout(tryInit, 100);
        } else {
          document.addEventListener('DOMContentLoaded', function() { setTimeout(tryInit, 100); });
        }
      })();
    ", ns("character_player"), ns("character_static_img"))))
  )
}

#' Karakter Video Modülü Sunucu
#'
#' @param id Modül ad alanı kimliği
#' @param selected_character_trigger Seçili karakteri takip eden reaktif tetikleyici
#' @return Sunucu mantığı
characterVideoServer <- function(id, selected_character_trigger) {
  moduleServer(id, function(input, output, session) {
    
    # Karakter değiştiğinde verileri güncelle ve giriş animasyonunu (intro) başlat
    observeEvent(selected_character_trigger(), {
      char_id <- selected_character_trigger()
      # Dosya sisteminden video ve görsel yollarını al
      video_data <- get_character_video_data(char_id)
      # JS tarafındaki yöneticimize güncel verileri gönder
      session$sendCustomMessage("updateCharacterVideo", video_data)
    })
    
    # Not: "Ayarları Kaydet" tetiklemesi ana ayarlar modülü (module_settings.R) üzerinden yönetilir.
  })
}