# ==============================================================================
# Dosya Yolu: R/helpers_tts_voice_manifest.R
# Açıklama:   VoxCPM2 referans-ses profili manifest ve WAV doğrulama katmanı.
#             manifest.json'u yükler/doğrular, WAV başlığını gerçekten ayrıştırıp
#             (uzantıya güvenmeden) biçimi denetler ve tek bir profili çözerek
#             referans ses base64 veri URL'sini ve birebir dökümü (ref_text)
#             hazırlar.
#
#             Gerçek referans kayıtları biyometrik/kişisel veridir: bu katman
#             yalnızca dağıtım-yerel bir dizinden (LOCAL_TTS_VOICE_DIR) okur;
#             içeriği loglamaz ve tarayıcıya döndürmez.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

# Bilinen profil kimlikleri (persona kimlikleriyle aynıdır).
mergen_tts_known_profile_ids <- function() {
  if (exists("CHARACTER_VALID_IDS", inherits = TRUE)) {
    return(get("CHARACTER_VALID_IDS", inherits = TRUE))
  }
  c("emre", "selin", "deniz", "can", "ipek")
}

# Küçük-endian işaretsiz tam sayıyı ham baytlardan çözer (double döner; 4 baytlık
# değerler R integer sınırını aşabildiği için).
.mergen_tts_le_uint <- function(bytes) {
  if (length(bytes) == 0L) return(NA_real_)
  sum(as.numeric(as.integer(bytes)) * 256^(seq_along(bytes) - 1L))
}

# Ham 4 baytı güvenli biçimde ASCII chunk kimliğine çevirir (NUL/geçersiz baytta "").
.mergen_tts_chunk_id <- function(bytes) {
  tryCatch({
    id <- rawToChar(bytes)
    if (is.na(id)) "" else id
  }, error = function(e) "")
}

#' WAV Başlığı Meta Verisini Oku
#'
#' @description Uzantıya güvenmeden RIFF/WAVE başlığını ve fmt/data chunk'larını
#'   ayrıştırır. Süre = data baytları / byte_rate.
#' @param path WAV dosya yolu
#' @return Liste: valid, error, format_code, channels, sample_rate,
#'   bits_per_sample, byte_rate, block_align, data_bytes, duration_secs, file_size
mergen_tts_read_wav_metadata <- function(path) {
  res <- list(
    valid = FALSE, error = NULL, format_code = NA_real_, channels = NA_real_,
    sample_rate = NA_real_, bits_per_sample = NA_real_, byte_rate = NA_real_,
    block_align = NA_real_, data_bytes = NA_real_, duration_secs = NA_real_,
    file_size = NA_real_
  )

  # file.info() eksik dosyada NA döndürür (hata fırlatmaz).
  size <- suppressWarnings(file.info(path)$size)
  if (is.na(size) || size < 44) {
    res$error <- "WAV dosyası çok küçük veya okunamıyor."
    return(res)
  }
  res$file_size <- as.numeric(size)

  raw_all <- tryCatch(readBin(path, what = "raw", n = as.integer(min(size, 20 * 1024^2))),
                      error = function(e) raw(0))
  n <- length(raw_all)
  if (n < 12L) {
    res$error <- "WAV başlığı okunamadı."
    return(res)
  }
  if (.mergen_tts_chunk_id(raw_all[1:4]) != "RIFF" ||
      .mergen_tts_chunk_id(raw_all[9:12]) != "WAVE") {
    res$error <- "Dosya RIFF/WAVE biçiminde değil."
    return(res)
  }

  pos <- 13L
  iter <- 0L
  while (pos + 7L <= n && iter < 512L) {
    iter <- iter + 1L
    chunk_id <- .mergen_tts_chunk_id(raw_all[pos:(pos + 3L)])
    chunk_size <- .mergen_tts_le_uint(raw_all[(pos + 4L):(pos + 7L)])
    if (is.na(chunk_size) || chunk_size < 0) break
    body_start <- pos + 8L

    if (identical(chunk_id, "fmt ") && body_start + 15L <= n) {
      fmt <- raw_all[body_start:(body_start + 15L)]
      res$format_code     <- .mergen_tts_le_uint(fmt[1:2])
      res$channels        <- .mergen_tts_le_uint(fmt[3:4])
      res$sample_rate     <- .mergen_tts_le_uint(fmt[5:8])
      res$byte_rate       <- .mergen_tts_le_uint(fmt[9:12])
      res$block_align     <- .mergen_tts_le_uint(fmt[13:14])
      res$bits_per_sample <- .mergen_tts_le_uint(fmt[15:16])
    } else if (identical(chunk_id, "data")) {
      res$data_bytes <- chunk_size
    }

    # Chunk'lar word hizalıdır (tek boyutta 1 dolgu baytı).
    advance <- 8L + chunk_size + (chunk_size %% 2)
    if (advance <= 0) break
    pos <- pos + advance
  }

  if (!is.na(res$byte_rate) && res$byte_rate > 0 && !is.na(res$data_bytes)) {
    res$duration_secs <- res$data_bytes / res$byte_rate
  } else if (!is.na(res$sample_rate) && !is.na(res$channels) &&
             !is.na(res$bits_per_sample) && res$sample_rate > 0 &&
             res$channels > 0 && res$bits_per_sample > 0 && !is.na(res$data_bytes)) {
    res$duration_secs <- res$data_bytes / (res$sample_rate * res$channels * res$bits_per_sample / 8)
  }

  res$valid <- !is.na(res$format_code) && !is.na(res$sample_rate)
  res
}

#' WAV Dosyasını Sözleşmeye Göre Doğrula
#'
#' @description PCM (format 1), mono, 16-bit, 16 kHz ve süre aralığı denetimi.
#'   Kabul edilen süre üst sınırı VoxCPM2/sunucu limitini (30 sn) aşamaz.
#' @param path WAV yolu
#' @param min_secs Alt süre sınırı
#' @param max_secs Üst süre sınırı (<= 30)
#' @return Liste: ok, error, metadata
mergen_tts_validate_wav <- function(path, min_secs = 0.5, max_secs = 30) {
  meta <- mergen_tts_read_wav_metadata(path)
  if (!isTRUE(meta$valid)) {
    return(list(ok = FALSE, error = meta$error %||% "WAV başlığı ayrıştırılamadı.", metadata = meta))
  }
  if (!isTRUE(meta$format_code == 1)) {
    return(list(ok = FALSE, error = "WAV PCM (16-bit) biçiminde olmalıdır.", metadata = meta))
  }
  if (!isTRUE(meta$channels == 1)) {
    return(list(ok = FALSE, error = "WAV tek kanallı (mono) olmalıdır.", metadata = meta))
  }
  if (!isTRUE(meta$bits_per_sample == 16)) {
    return(list(ok = FALSE, error = "WAV 16-bit örnekleme derinliğinde olmalıdır.", metadata = meta))
  }
  if (!isTRUE(meta$sample_rate == 16000)) {
    return(list(ok = FALSE, error = "WAV 16 kHz örnekleme hızında olmalıdır.", metadata = meta))
  }
  if (is.na(meta$duration_secs) || meta$duration_secs < min_secs || meta$duration_secs > max_secs) {
    return(list(
      ok = FALSE,
      error = sprintf("WAV süresi %.1f-%.0f sn aralığında olmalıdır.", min_secs, max_secs),
      metadata = meta
    ))
  }
  list(ok = TRUE, error = NULL, metadata = meta)
}

# Dosyanın SHA-256 özetini hesaplar (openssl; abartılı log kaçınmak için kısaltılır).
mergen_tts_file_sha256 <- function(path) {
  tryCatch({
    con <- file(path, open = "rb")
    on.exit(close(con), add = TRUE)
    as.character(openssl::sha256(con))
  }, error = function(e) "")
}

# UTF-8 metnin SHA-256 özetini hesaplar.
mergen_tts_text_sha256 <- function(text) {
  tryCatch(
    as.character(openssl::sha256(charToRaw(enc2utf8(as.character(text %||% ""))))),
    error = function(e) ""
  )
}

# Manifest içindeki göreli yolun güvenli olduğunu doğrular (traversal/mutlak yok).
mergen_tts_safe_relative_path <- function(voice_dir, rel_path) {
  rel_path <- as.character(rel_path %||% "")[1]
  if (is.na(rel_path) || !nzchar(trimws(rel_path))) {
    return(list(ok = FALSE, error = "Boş dosya yolu.", path = ""))
  }
  normalized <- gsub("\\\\", "/", rel_path)
  if (grepl("\\.\\.", normalized, fixed = FALSE) ||
      startsWith(normalized, "/") ||
      grepl("^[A-Za-z]:", normalized)) {
    return(list(ok = FALSE, error = "Güvensiz göreli yol reddedildi.", path = ""))
  }
  list(ok = TRUE, error = NULL, path = file.path(voice_dir, normalized))
}

#' Ses Profili Manifestini Yükle
#'
#' @param voice_dir Dağıtım-yerel ses profili dizini
#' @return Liste: ok, error, manifest, transcripts, profiles, manifest_path
mergen_tts_load_voice_manifest <- function(voice_dir) {
  voice_dir <- as.character(voice_dir %||% "")[1]
  manifest_path <- file.path(voice_dir, "manifest.json")
  if (!nzchar(voice_dir) || !file.exists(manifest_path)) {
    return(list(ok = FALSE, error = "Ses profili manifesti bulunamadı.", manifest_path = manifest_path))
  }

  manifest <- tryCatch(
    jsonlite::fromJSON(manifest_path, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.list(manifest)) {
    return(list(ok = FALSE, error = "Manifest ayrıştırılamadı (geçersiz JSON).", manifest_path = manifest_path))
  }

  schema <- suppressWarnings(as.integer(manifest$schema_version %||% NA))
  if (is.na(schema) || schema != 1L) {
    return(list(ok = FALSE, error = "Desteklenmeyen manifest schema_version.", manifest_path = manifest_path))
  }
  if (!is.list(manifest$transcripts) || length(manifest$transcripts) == 0L) {
    return(list(ok = FALSE, error = "Manifest transcripts alanı eksik.", manifest_path = manifest_path))
  }
  if (!is.list(manifest$profiles) || length(manifest$profiles) == 0L) {
    return(list(ok = FALSE, error = "Manifest profiles alanı eksik.", manifest_path = manifest_path))
  }

  list(
    ok = TRUE, error = NULL, manifest = manifest,
    transcripts = manifest$transcripts, profiles = manifest$profiles,
    manifest_path = manifest_path
  )
}

# Transcript dosyasını UTF-8 olarak okur, BOM temizler, geçerlilik denetler.
.mergen_tts_read_transcript <- function(path) {
  size <- suppressWarnings(file.info(path)$size)
  if (is.na(size) || size <= 0) return(list(ok = FALSE, error = "Transcript dosyası boş.", text = ""))
  raw_all <- tryCatch(readBin(path, "raw", n = as.integer(min(size, 1024^2))), error = function(e) raw(0))
  if (length(raw_all) >= 3 && raw_all[1] == as.raw(0xEF) &&
      raw_all[2] == as.raw(0xBB) && raw_all[3] == as.raw(0xBF)) {
    raw_all <- raw_all[-(1:3)]
  }
  text <- tryCatch(rawToChar(raw_all), error = function(e) NA_character_)
  if (is.na(text)) return(list(ok = FALSE, error = "Transcript okunamadı.", text = ""))
  Encoding(text) <- "UTF-8"
  if (!isTRUE(all(validUTF8(text)))) {
    return(list(ok = FALSE, error = "Transcript geçerli UTF-8 değil.", text = ""))
  }
  text <- trimws(text)
  if (!nzchar(text)) return(list(ok = FALSE, error = "Transcript metni boş.", text = ""))
  list(ok = TRUE, error = NULL, text = text)
}

#' Tek Bir Ses Profilini Çöz (manifest -> doğrulama -> base64 referans ses)
#'
#' @description Manifesti yükler, profili ve transcript'i doğrular, WAV biçimini
#'   denetler, sağlama toplamlarını hesaplar ve referans WAV'ı base64 veri URL'sine
#'   çevirir. Bir profildeki hata diğer profilleri etkilemez; her zaman yapılandırılmış
#'   liste döndürür (ok = FALSE + Türkçe hata) ve asla exception fırlatmaz.
#' @return Liste: ok, error, profile_id, version, speed, ref_text, audio_data_url,
#'   audio_path, wav_sha256, transcript_sha256, duration, sample_rate, channels,
#'   bits, file_size, audio_mtime, audio_size, manifest_path, manifest_mtime
mergen_tts_resolve_profile <- function(profile_id, config = NULL,
                                       min_secs = 0.5, max_secs = 30) {
  if (is.null(config)) config <- if (exists("tts_config", inherits = TRUE)) get("tts_config", inherits = TRUE) else list()
  fail <- function(msg) list(ok = FALSE, error = msg, profile_id = profile_id)

  profile_id <- tolower(trimws(as.character(profile_id %||% "")[1]))
  if (!profile_id %in% mergen_tts_known_profile_ids()) return(fail("Bilinmeyen ses profili kimliği."))

  voice_dir <- as.character(config$voice_dir %||% "")[1]
  if (!nzchar(voice_dir)) return(fail("Ses profili dizini yapılandırılmamış."))

  loaded <- mergen_tts_load_voice_manifest(voice_dir)
  if (!isTRUE(loaded$ok)) return(fail(loaded$error))

  prof <- loaded$profiles[[profile_id]]
  if (!is.list(prof)) return(fail("Profil manifestte tanımlı değil."))
  if (identical(prof$enabled, FALSE)) return(fail("Profil devre dışı."))

  version <- suppressWarnings(as.integer(prof$version %||% 1L))
  if (is.na(version) || version < 1L) return(fail("Geçersiz profil sürümü."))

  speed <- suppressWarnings(as.numeric(prof$speed %||% config$speed %||% 1.0))
  if (is.na(speed) || speed < 0.25 || speed > 4.0) speed <- 1.0

  audio_rel <- mergen_tts_safe_relative_path(voice_dir, prof$audio %||% "")
  if (!isTRUE(audio_rel$ok)) return(fail(audio_rel$error))
  if (!file.exists(audio_rel$path)) return(fail("Referans WAV dosyası bulunamadı."))

  transcript_id <- as.character(prof$transcript_id %||% "")[1]
  tdef <- loaded$transcripts[[transcript_id]]
  if (!is.list(tdef)) return(fail("Profil transcript referansı geçersiz."))
  transcript_rel <- mergen_tts_safe_relative_path(voice_dir, tdef$file %||% "")
  if (!isTRUE(transcript_rel$ok)) return(fail(transcript_rel$error))
  if (!file.exists(transcript_rel$path)) return(fail("Transcript dosyası bulunamadı."))

  transcript <- .mergen_tts_read_transcript(transcript_rel$path)
  if (!isTRUE(transcript$ok)) return(fail(transcript$error))

  wav_check <- mergen_tts_validate_wav(audio_rel$path, min_secs = min_secs, max_secs = max_secs)
  if (!isTRUE(wav_check$ok)) return(fail(wav_check$error))

  raw_audio <- tryCatch(
    readBin(audio_rel$path, "raw", n = as.integer(wav_check$metadata$file_size)),
    error = function(e) raw(0)
  )
  if (length(raw_audio) == 0L) return(fail("Referans WAV okunamadı."))

  # Dosyalar yukarıda file.exists ile doğrulandı; file.info hata fırlatmaz.
  audio_info <- suppressWarnings(file.info(audio_rel$path))

  list(
    ok = TRUE, error = NULL,
    profile_id = profile_id,
    version = version,
    speed = speed,
    ref_text = transcript$text,
    audio_data_url = paste0("data:audio/wav;base64,", base64enc::base64encode(raw_audio)),
    audio_path = audio_rel$path,
    transcript_path = transcript_rel$path,
    wav_sha256 = mergen_tts_file_sha256(audio_rel$path),
    transcript_sha256 = mergen_tts_text_sha256(transcript$text),
    duration = wav_check$metadata$duration_secs,
    sample_rate = wav_check$metadata$sample_rate,
    channels = wav_check$metadata$channels,
    bits = wav_check$metadata$bits_per_sample,
    file_size = wav_check$metadata$file_size,
    audio_mtime = if (!is.null(audio_info)) as.numeric(audio_info$mtime) else NA_real_,
    audio_size = if (!is.null(audio_info)) as.numeric(audio_info$size) else NA_real_,
    manifest_path = loaded$manifest_path,
    manifest_mtime = as.numeric(suppressWarnings(file.info(loaded$manifest_path)$mtime))
  )
}
