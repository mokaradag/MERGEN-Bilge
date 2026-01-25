# R/server_music_handlers.R
# Dosya Yolu: R/server_music_handlers.R
# Açıklama: Arka plan müzik yönetimi için observer fonksiyonları.
# Bu dosya server.R'den ayrılarak modülerlik sağlanmıştır.

#' Müzik İşleyicilerini Başlat
#' @description Arka plan müzik yönetimi için observer'ları kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
musicHandlersInit <- function(input, session, settings_data) {

  session$onFlushed(function() {
    session$sendCustomMessage("initMusicManager", list(
      enabled = isTRUE(shiny::isolate(settings_data$enable_background_music)),
      volume = shiny::isolate(settings_data$music_volume) %||% 0.3
    ))
  }, once = TRUE)

  shiny::observeEvent(input$get_music_playlist, {
    shiny::req(input$get_music_playlist)
    msg <- input$get_music_playlist

    base_path <- file.path("www", "music")

    target_sub <- "Genel Tema"
    playlist_type <- "genel"

    if (identical(msg$type, "karakter") && !is.null(msg$character) && nzchar(msg$character)) {
      check_path <- file.path(base_path, "Karakter", msg$character)
      if (dir.exists(check_path)) {
        target_sub <- file.path("Karakter", msg$character)
        playlist_type <- "karakter"
      }
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

        session$sendCustomMessage("setMusicPlaylist", list(
          files = I(file_urls),
          type = playlist_type
        ))
      }
    }
  })

  invisible(NULL)
}
