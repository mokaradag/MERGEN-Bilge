# R/config_speech_assets.R
# Önceden üretilmiş konuşma varlık ağacının (www/speech) TEK yetkili tanımı.
# Persona kimlikleri, rehberli/sessiz sayfalar, çeşit sayısı, yol kurucuları ve
# beklenen varlık sayıları buradan türetilir. Üretici (tools/speech), manifest,
# çalışma zamanı ve testler bu dosyayı tek kaynak olarak kullanır; sayı/harita
# kopyalanmaz.

#' Konuşma varlık ağacının kök dizini (test için MERGEN_SPEECH_ROOT ile
#' geçersiz kılınabilir).
mergen_speech_root <- function() {
  override <- Sys.getenv("MERGEN_SPEECH_ROOT", "")
  if (nzchar(override)) return(override)
  file.path("www", "speech")
}

#' Kanonik persona kimlikleri (sıralı). Karakter yapılandırması yüklüyse ondan
#' türetilir; izole test/worker bağlamında sabit listeyle aynı kalır.
mergen_speech_personas <- function() {
  fallback <- c("emre", "selin", "deniz", "can", "ipek")
  chars_fn <- get0("get_characters_data", mode = "function")
  if (is.null(chars_fn)) return(fallback)

  ids <- tryCatch({
    styles <- chars_fn()$styles
    vapply(styles, function(s) {
      if (is.null(s$id)) "" else as.character(s$id)[1]
    }, character(1))
  }, error = function(e) character(0))

  ids <- ids[nzchar(ids)]
  if (length(ids) == 0) return(fallback)
  ids
}

#' Rehberli sayfalar: sayfa kimliği -> Türkçe sayfa adı (14 sayfa).
mergen_speech_guided_pages <- function() {
  c(
    history               = "Söyleşi Geçmişi",
    saved_chats           = "Kayıtlı Söyleşiler",
    ortak_sohbetler       = "Ortak Söyleşiler",
    image_gallery         = "Görsel Galerisi",
    claude_code           = "Çalışma Alanı",
    claude_code_sessions  = "Oturumlar",
    ortak_bilge_yolac     = "Ortak Bilge Yolaç Oturumları",
    ortak_calismalar      = "Ortak Çalışmalarım",
    files                 = "Dosya Yönetimi",
    settings_yapilandirma = "Yapılandırma",
    destek_yardim         = "Yardım Merkezi",
    destek_geri_bildirim  = "Geri Bildirim & Hata",
    destek_surum          = "Yenilikler",
    destek_hakkinda       = "Hakkında"
  )
}

#' Sayfa rehberliği ÜRETİLMEYEN sessiz sayfalar. `chat` karşılama dizisiyle
#' kapsanır; `settings_kisisel` persona tanıtım videosu oynatır; yönetici
#' paneli sayfaları ve Sistem Durumu rehberliksizdir.
mergen_speech_silent_pages <- function() {
  c(
    "chat",
    "settings_kisisel",
    "admin_analytics",
    "admin_geri_bildirim",
    "admin_hata_analizi",
    "admin_yanit_analizi",
    "admin_dokumantasyon",
    "health"
  )
}

#' Boşta (idle) konuşmanın sessiz kaldığı sayfalar. Ortak (paylaşımlı) odalar
#' rehberlik klibi alır ama sürekli boşta konuşma almaz; kişiselleştirme,
#' yönetici ve sağlık sayfalarında hiçbir otomatik konuşma yapılmaz.
mergen_speech_idle_muted_pages <- function() {
  unique(c(
    setdiff(mergen_speech_silent_pages(), "chat"),
    "ortak_calismalar",
    "ortak_sohbetler",
    "ortak_bilge_yolac"
  ))
}

#' Her senaryo/sayfa için ortak metin çeşidi sayısı.
mergen_speech_variant_count <- function() 10L

#' Desteklenen senaryolar.
mergen_speech_scenarios <- function() c("welcome", "page_guidance")

#' Beklenen ortak metin sayısı: karşılama + rehberli sayfalar x çeşit.
mergen_speech_expected_script_count <- function() {
  mergen_speech_variant_count() * (1L + length(mergen_speech_guided_pages()))
}

#' Persona başına beklenen WAV sayısı (metin sayısıyla aynı).
mergen_speech_expected_audio_per_persona <- function() {
  mergen_speech_expected_script_count()
}

#' Tüm personalar için beklenen toplam WAV sayısı.
mergen_speech_expected_audio_total <- function() {
  mergen_speech_expected_audio_per_persona() * length(mergen_speech_personas())
}

#' Üretilen WAV'ların beklenen ses profili. VoxCPM2 referans girdisini
#' 16 kHz olarak işleyebilir, ancak üretilmiş ses çıktısı 48 kHz'dir.
#' VOXCPM2_EXPECTED_SAMPLE_RATE yalnızca üretilmiş WAV/PCM çıktısını tanımlar.
mergen_speech_expected_wav_profile <- function() {
  rate <- suppressWarnings(as.integer(
    Sys.getenv("VOXCPM2_EXPECTED_SAMPLE_RATE", "48000")
  ))
  if (is.na(rate) || rate <= 0L) rate <- 48000L

  list(
    sample_rate = rate,
    channels = 1L,
    bits_per_sample = 16L
  )
}

#' Tüm beklenen varlıkların tablosu: senaryo, sayfa, çeşit, kimlik ve yollar.
#' Üretici planı ve manifest doğrulaması bu tablo üzerinden yürür.
mergen_speech_expected_assets <- function(root = mergen_speech_root()) {
  variants <- seq_len(mergen_speech_variant_count())
  pages <- names(mergen_speech_guided_pages())

  rows <- list()
  for (v in variants) {
    rows[[length(rows) + 1L]] <- list(
      scenario = "welcome", page = NA_character_, variant = v,
      id = mergen_speech_asset_id("welcome", NULL, v),
      script_path = mergen_speech_script_path("welcome", NULL, v, root)
    )
  }
  for (pg in pages) {
    for (v in variants) {
      rows[[length(rows) + 1L]] <- list(
        scenario = "page_guidance", page = pg, variant = v,
        id = mergen_speech_asset_id("page_guidance", pg, v),
        script_path = mergen_speech_script_path("page_guidance", pg, v, root)
      )
    }
  }

  data.frame(
    scenario = vapply(rows, function(r) r$scenario, character(1)),
    page = vapply(rows, function(r) r$page, character(1)),
    variant = vapply(rows, function(r) as.integer(r$variant), integer(1)),
    id = vapply(rows, function(r) r$id, character(1)),
    script_path = vapply(rows, function(r) r$script_path, character(1)),
    stringsAsFactors = FALSE
  )
}
