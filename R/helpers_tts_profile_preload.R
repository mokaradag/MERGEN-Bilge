# ==============================================================================
# Dosya Yolu: R/helpers_tts_profile_preload.R
# Açıklama:   VoxCPM2 ses profili başlangıç/ön yükleme politikası.
#             "Profil yükleme" (yalnızca doğrula + base64) işini; uzak modeli
#             ısıtma ve gerçek konuşma üretiminden AYIRIR. Yalnızca bir konuşma
#             özelliği (Yanıtları Seslendir veya AI Uzman Konuşması) etkinken
#             ve yalnızca SEÇİLİ persona için tembel, düşük öncelikli yükleme
#             tetikler.
#
#             Hızlı Başlangıç sözleşmesi: bu politika açılış katmanının zorunlu
#             boot anahtarlarına eklenmez, 0-100 ilerleme çubuğunu etkilemez ve
#             yalnızca preload_profile (ağsız) çağırır. Profil yüklemesinin
#             kendisi module_tts içinde later ile ertelenir; bu yüzden uygulama
#             önce kullanılabilir hale gelir.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

#' Profil Ön Yükleme Kararı (saf)
#'
#' @description Seçili profilin ön yüklenip yüklenmeyeceğini belirler: yalnızca
#'   bir konuşma özelliği etkinse. Odak/Dinamik modda ikisi de kapalı olduğundan
#'   hiçbir profil yüklenmez; Bütünleşik modda veya kullanıcı sonradan bir
#'   özelliği açtığında yüklenir.
#' @param tts_enabled Yanıtları Seslendir açık mı
#' @param expert_enabled AI Uzman Konuşması açık mı
#' @return Mantıksal
mergen_tts_profile_preload_decision <- function(tts_enabled, expert_enabled) {
  isTRUE(tts_enabled) || isTRUE(expert_enabled)
}

#' Profil Ön Yükleme Gözlemcilerini Bağla
#'
#' @description enable_tts_audio / enable_ai_expert açıldığında ve seçili karakter
#'   değiştiğinde (bir konuşma özelliği açıksa) yalnızca seçili persona profilini
#'   tembel yükler. Yükleme idempotenttir ve bellek önbelleğiyle dedup edilir;
#'   hızlı karakter değişimlerine ve tekrarlayan ayar olaylarına karşı güvenlidir.
#' @param session Shiny session
#' @param settings_data Merkezi ayarlar reaktif değerleri
#' @param tts_processor preload_profile fonksiyonunu içeren liste
#' @return Görünmez mantıksal (bağlandı mı)
mergen_tts_bind_profile_preload <- function(session, settings_data, tts_processor) {
  if (!is.list(tts_processor) || !is.function(tts_processor$preload_profile)) {
    return(invisible(FALSE))
  }
  if (is.null(settings_data)) return(invisible(FALSE))

  do_preload <- function() {
    tts_on <- isTRUE(shiny::isolate(settings_data$enable_tts_audio))
    expert_on <- isTRUE(shiny::isolate(settings_data$enable_ai_expert))
    if (!mergen_tts_profile_preload_decision(tts_on, expert_on)) return(invisible(FALSE))
    char_id <- shiny::isolate(settings_data$selected_character)
    tryCatch(tts_processor$preload_profile(char_id), error = function(e) NULL)
    invisible(TRUE)
  }

  # TTS açıldığında seçili profili yükle (kayıtlı ayar TRUE gelirse de yakalanır).
  shiny::observeEvent(settings_data$enable_tts_audio, {
    if (isTRUE(settings_data$enable_tts_audio)) do_preload()
  }, ignoreInit = FALSE)

  # AI Uzman açıldığında seçili profili yükle.
  shiny::observeEvent(settings_data$enable_ai_expert, {
    if (isTRUE(settings_data$enable_ai_expert)) do_preload()
  }, ignoreInit = FALSE)

  # Karakter değişince (bir konuşma özelliği açıksa) yeni profili yükle.
  shiny::observeEvent(settings_data$selected_character, {
    do_preload()
  }, ignoreInit = TRUE)

  invisible(TRUE)
}
