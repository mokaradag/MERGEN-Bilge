# R/server_music_handlers.R
# Dosya Yolu: R/server_music_handlers.R
# Açıklama: Arka plan müzik yönetimi için observer fonksiyonları.
# Basit akış: Ana Tema (bir kez) → Karakter Müziği (rastgele döngü)
# Giriş ekranı için ayrı müzik yöneticisi: SpaceIntroMusic (www/music/intro/)
# Klasör yapısı:
#   www/music/intro/          → Giriş ekranı uzay müzikleri
#   www/music/Ana Tema/       → Ana tema müzikleri (bir kez çalınır)
#   www/music/Karakter/mergen/ → MERGEN karakter müzikleri
#   www/music/Karakter/ulgen/  → ÜLGEN karakter müzikleri
#   www/music/Karakter/kayra/  → KAYRA karakter müzikleri
#   www/music/Karakter/erlik/  → ERLİK karakter müzikleri
#   www/music/Karakter/umay/   → UMAY ANA karakter müzikleri

#' Müzik İşleyicilerini Başlat
#' @description Arka plan müzik yönetimi için observer'ları kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
musicHandlersInit <- function(input, session, settings_data) {

  # Giriş müziğini öncelikli olarak gönder (gecikmeyi azalt)
  session$onFlushed(function() {
    # Önce giriş ekranı intro müziğini gönder (en hızlı deneyim için)
    intro_dir <- file.path("www", "music", "intro")
    if (dir.exists(intro_dir)) {
      intro_files <- list.files(intro_dir, pattern = "\\.mp3$", full.names = FALSE, ignore.case = TRUE)
      if (length(intro_files) > 0) {
        intro_urls <- vapply(intro_files, function(f) {
          utils::URLencode(paste0("music/intro/", f))
        }, character(1), USE.NAMES = FALSE)

        cat(sprintf("[MUSIC] Giriş müzik playlist'i gönderiliyor: %d parça\n", length(intro_urls)))
        session$sendCustomMessage("initSpaceIntroMusic", list(
          files = I(intro_urls),
          volume = shiny::isolate(settings_data$music_volume) %||% 0.25
        ))
      }
    }

    # Ana müzik yöneticisini başlat
    session$sendCustomMessage("initMusicManager", list(
      enabled = isTRUE(shiny::isolate(settings_data$enable_background_music)),
      volume = shiny::isolate(settings_data$music_volume) %||% 0.3,
      character = shiny::isolate(settings_data$selected_character) %||% "mergen"
    ))
  }, once = TRUE)

  # İstemciden playlist isteği geldiğinde
  shiny::observeEvent(input$get_music_playlist, {
    shiny::req(input$get_music_playlist)
    msg <- input$get_music_playlist

    base_path <- file.path("www", "music")
    request_type <- msg$type %||% "tema"
    request_id <- msg$requestId %||% 0
    character_name <- msg$character %||% shiny::isolate(settings_data$selected_character) %||% "mergen"

    target_sub <- NULL
    playlist_type <- request_type

    if (identical(request_type, "tema")) {
      # Ana tema klasörü
      target_sub <- "Ana Tema"
    } else if (identical(request_type, "karakter")) {
      # Karakter müzik klasörü
      check_path <- file.path(base_path, "Karakter", character_name)
      if (dir.exists(check_path)) {
        target_sub <- file.path("Karakter", character_name)
      } else {
        cat(sprintf("[MUSIC] Karakter klasörü bulunamadı: %s\n", check_path))
        # Karakter klasörü yoksa boş liste gönder
        session$sendCustomMessage("setMusicPlaylist", list(
          files = I(character(0)),
          type = "karakter",
          requestId = request_id
        ))
        return()
      }
    } else {
      # Bilinmeyen tip, ana temaya düş
      target_sub <- "Ana Tema"
      playlist_type <- "tema"
    }

    full_dir <- file.path(base_path, target_sub)

    if (dir.exists(full_dir)) {
      files <- list.files(full_dir, pattern = "\\.mp3$", full.names = FALSE, ignore.case = TRUE)

      if (length(files) > 0) {
        clean_sub <- gsub("\\\\", "/", target_sub)

        file_urls <- vapply(files, function(f) {
          full_rel_path <- paste0("music/", clean_sub, "/", f)
          utils::URLencode(full_rel_path)
        }, character(1), USE.NAMES = FALSE)

        cat(sprintf("[MUSIC] Playlist gönderiliyor: %s | Karakter: %s | %d parça\n", playlist_type, character_name, length(file_urls)))

        session$sendCustomMessage("setMusicPlaylist", list(
          files = I(file_urls),
          type = playlist_type,
          requestId = request_id
        ))
      } else {
        cat(sprintf("[MUSIC] Klasörde dosya bulunamadı: %s\n", full_dir))
        session$sendCustomMessage("setMusicPlaylist", list(
          files = I(character(0)),
          type = playlist_type,
          requestId = request_id
        ))
      }
    } else {
      cat(sprintf("[MUSIC] Klasör bulunamadı: %s\n", full_dir))
      session$sendCustomMessage("setMusicPlaylist", list(
        files = I(character(0)),
        type = playlist_type,
        requestId = request_id
      ))
    }
  })

  invisible(NULL)
}