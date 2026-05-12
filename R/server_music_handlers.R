# R/server_music_handlers.R
# Dosya Yolu: R/server_music_handlers.R
# Açıklama: Arka plan müzik yönetimi için observer fonksiyonları.
# Basit akış: Ana Tema (bir kez) -> Karakter Müziği (rastgele döngü)
# Giriş ekranı için ayrı müzik yöneticisi: SpaceIntroMusic (www/music/intro/)
# Klasör yapısı:
#   www/music/intro/          -> Giriş ekranı uzay müzikleri
#   www/music/Ana Tema/       -> Ana tema müzikleri (bir kez çalınır)
#   www/music/Karakter/mergen/ -> MERGEN karakter müzikleri
#   www/music/Karakter/ulgen/  -> ÜLGEN karakter müzikleri
#   www/music/Karakter/kayra/  -> KAYRA karakter müzikleri
#   www/music/Karakter/erlik/  -> ERLİK karakter müzikleri
#   www/music/Karakter/umay/   -> UMAY ANA karakter müzikleri

#' Native/Windows encoding değerlerini güvenli UTF-8'e çevir
#' @description Özellikle Windows VM + Türkçe locale ortamında Ü gibi karakterlerin
#'              URLencode tarafından %DC şeklinde native byte olarak kodlanmasını
#'              engeller. Beklenen URL formu UTF-8 percent-encoding'dir:
#'              Ü -> %C3%9C.
music_force_utf8 <- function(x) {
  x <- as.character(x)

  y <- iconv(x, from = "", to = "UTF-8", sub = "byte")

  ifelse(is.na(y), enc2utf8(x), y)
}

#' UTF-8 path segment URL encoder
#' @description Her path segmentini ayrı encode eder; "/" ayraç olarak kalır.
#'              Örn: Ülgen, Endless Skyforge (1).mp3 ->
#'              %C3%9Clgen%2C%20Endless%20Skyforge%20%281%29.mp3
music_url_encode_segment_utf8 <- function(x) {
  x <- music_force_utf8(x)

  vapply(
    x,
    function(one) utils::URLencode(one, reserved = TRUE),
    character(1),
    USE.NAMES = FALSE
  )
}

#' UTF-8 güvenli müzik URL yolu oluştur
music_url_path_utf8 <- function(...) {
  parts <- unlist(list(...), use.names = FALSE)
  parts <- parts[!is.na(parts) & nzchar(parts)]

  paste(music_url_encode_segment_utf8(parts), collapse = "/")
}

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

    # Ana müzik yöneticisini hazırla (henüz çalmaya başlama)
    # Müzik, mod seçiminden sonra toggleMusic ile başlatılır.
    # Giriş ekranı atlandıysa (skip_intro) o zaman doğrudan başlat.
    intro_atlanmis <- isTRUE(session$userData$deep_space_dismissed)
    session$sendCustomMessage("initMusicManager", list(
      enabled = if (intro_atlanmis) isTRUE(shiny::isolate(settings_data$enable_background_music)) else FALSE,
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
	character_name <- tolower(trimws(enc2utf8(character_name)))

	if (identical(character_name, "umay ana")) {
	  character_name <- "umay"
	}

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
		clean_sub <- music_force_utf8(gsub("\\\\", "/", target_sub))
		sub_parts <- strsplit(clean_sub, "/", fixed = TRUE)[[1]]
		sub_parts <- music_force_utf8(sub_parts)

		files <- music_force_utf8(files)

		file_urls <- vapply(files, function(f) {
		  music_url_path_utf8(c("music", sub_parts, f))
		}, character(1), USE.NAMES = FALSE)

		cat(sprintf(
		  "[MUSIC] Playlist detay: type=%s | character=%s | folder=%s | files=%s\n",
		  playlist_type,
		  character_name,
		  full_dir,
		  paste(files, collapse = " | ")
		))

		cat(sprintf(
		  "[MUSIC] Playlist URL detay: %s\n",
		  paste(file_urls, collapse = " | ")
		))

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