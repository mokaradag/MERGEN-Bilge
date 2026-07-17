# R/config_speech_asset_paths.R
# Konuşma varlık ağacının YOL kurucuları: varlık kimliği, ortak metin/persona
# WAV yolları, tarayıcı URL'leri, referans/kilit/manifest/durum dosyası
# konumları. Yapı tanımı (persona/sayfa/çeşit kümeleri ve sayılar)
# R/config_speech_assets.R içindedir; bu dosya ondan hemen sonra yüklenir.

#' Varlık kimliği: karşılama için "welcome_03", sayfa için "files_03".
mergen_speech_asset_id <- function(scenario, page = NULL, variant = 1L) {
  stem <- if (identical(scenario, "welcome")) "welcome" else as.character(page)
  sprintf("%s_%02d", stem, as.integer(variant))
}

#' Ortak metin dosyası yolu (persona bağımsız).
mergen_speech_script_path <- function(scenario, page = NULL, variant = 1L,
                                      root = mergen_speech_root()) {
  id <- mergen_speech_asset_id(scenario, page, variant)
  if (identical(scenario, "welcome")) {
    file.path(root, "scripts", "welcome", paste0(id, ".txt"))
  } else {
    file.path(root, "scripts", "pages", page, paste0(id, ".txt"))
  }
}

#' Persona'ya özel WAV dosyası yolu.
mergen_speech_audio_path <- function(persona, scenario, page = NULL, variant = 1L,
                                     root = mergen_speech_root()) {
  id <- mergen_speech_asset_id(scenario, page, variant)
  if (identical(scenario, "welcome")) {
    file.path(root, "audio", persona, "welcome", paste0(id, ".wav"))
  } else {
    file.path(root, "audio", persona, "pages", page, paste0(id, ".wav"))
  }
}

#' Tarayıcı tarafında kullanılacak göreli ses URL'si. www/ altındaki her alt
#' klasör app.R tarafından kendi adıyla resource path olarak kaydedilir; bu
#' nedenle URL "speech/..." önekiyle başlar.
mergen_speech_audio_url <- function(persona, scenario, page = NULL, variant = 1L) {
  id <- mergen_speech_asset_id(scenario, page, variant)
  if (identical(scenario, "welcome")) {
    sprintf("speech/audio/%s/welcome/%s.wav", persona, id)
  } else {
    sprintf("speech/audio/%s/pages/%s/%s.wav", persona, page, id)
  }
}

#' Persona ses referans dizini ve dosya yolları.
mergen_speech_voice_dir <- function(persona, root = mergen_speech_root()) {
  file.path(root, "voices", persona)
}

mergen_speech_reference_text_path <- function(persona, root = mergen_speech_root()) {
  file.path(mergen_speech_voice_dir(persona, root), "reference.txt")
}

mergen_speech_reference_wav_path <- function(persona, root = mergen_speech_root()) {
  file.path(mergen_speech_voice_dir(persona, root), "reference.wav")
}

mergen_speech_voice_lock_path <- function(persona, root = mergen_speech_root()) {
  file.path(mergen_speech_voice_dir(persona, root), "voice-lock.json")
}

#' Otomatik üretilen üst veri dizini ve dosyaları.
mergen_speech_generated_dir <- function(root = mergen_speech_root()) {
  file.path(root, "generated")
}

mergen_speech_manifest_path <- function(root = mergen_speech_root()) {
  file.path(mergen_speech_generated_dir(root), "speech_manifest.json")
}

mergen_speech_candidate_reference_path <- function(persona, root = mergen_speech_root()) {
  file.path(mergen_speech_generated_dir(root), "candidates",
            sprintf("%s_reference_candidate.wav", persona))
}

mergen_speech_generation_state_path <- function(persona, root = mergen_speech_root()) {
  file.path(mergen_speech_generated_dir(root),
            sprintf("generation_state_%s.json", persona))
}

mergen_speech_generator_lock_path <- function(root = mergen_speech_root()) {
  file.path(mergen_speech_generated_dir(root), "generator.lock")
}
