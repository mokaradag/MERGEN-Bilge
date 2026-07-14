# ==============================================================================
# Dosya Yolu: R/helpers_tts_audio_cache.R
# Açıklama:   Üretilen ses (generated-audio) önbelleği ve biçim/mime yardımcıları.
#             Aynı metin + profil + sürüm + hız + biçim için üretilen sesi
#             dağıtım-yerel, sınırlı (boyut + TTL) bir diske hashli dosya adıyla
#             saklar. Böylece tekrarlayan sabit ifadeler birebir aynı ses olarak
#             ve ağ turu olmadan geri döner.
#
#             Gizlilik: yalnızca LOCAL_TTS_CACHE_DIR altına yazar; dosya adları
#             hash'tir (kullanıcı metni dosya adında/metaveride düz metin olarak
#             tutulmaz); dizin listeleme dışa açılmaz.
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

# Yanıt biçimi -> dosya uzantısı.
mergen_tts_format_ext <- function(fmt) {
  fmt <- tolower(trimws(as.character(fmt %||% "")[1]))
  switch(fmt,
    "wav" = "wav", "mp3" = "mp3", "flac" = "flac", "aac" = "aac",
    "opus" = "opus", "ogg" = "ogg", "pcm" = "pcm",
    "wav"
  )
}

# Yanıt biçimi -> MIME türü.
mergen_tts_mime_for_format <- function(fmt) {
  fmt <- tolower(trimws(as.character(fmt %||% "")[1]))
  switch(fmt,
    "wav" = "audio/wav", "mp3" = "audio/mpeg", "flac" = "audio/flac",
    "aac" = "audio/aac", "opus" = "audio/opus", "ogg" = "audio/ogg",
    "pcm" = "audio/pcm",
    "audio/wav"
  )
}

# Ham ses baytlarını base64 veri URL'sine çevirir.
mergen_tts_raw_to_data_url <- function(raw_bytes, fmt) {
  if (length(raw_bytes) == 0L) return("")
  paste0("data:", mergen_tts_mime_for_format(fmt), ";base64,", base64enc::base64encode(raw_bytes))
}

#' Üretilen Ses Önbellek Anahtarı
#'
#' @description Çıktıyı belirleyen tüm bileşenleri içeren deterministik SHA-256
#'   anahtarı üretir: şema, model, profil kimliği, profil sürümü, WAV sağlaması,
#'   transcript sağlaması, hız, yanıt biçimi ve gönderilen nihai metin. Herhangi
#'   biri değişince anahtar değişir.
#' @return Hex SHA-256 dizesi (hata durumunda "")
mergen_tts_audio_cache_key <- function(model, profile_id, profile_version,
                                       wav_sha256, transcript_sha256,
                                       text, speed, response_format) {
  parts <- c(
    "voxcpm-audio-v1",
    as.character(model %||% ""),
    as.character(profile_id %||% ""),
    as.character(profile_version %||% ""),
    as.character(wav_sha256 %||% ""),
    as.character(transcript_sha256 %||% ""),
    sprintf("%.4f", as.numeric(speed %||% 1.0)),
    as.character(response_format %||% ""),
    as.character(text %||% "")
  )
  canonical <- paste(parts, collapse = "")
  tryCatch(
    as.character(openssl::sha256(charToRaw(enc2utf8(canonical)))),
    error = function(e) ""
  )
}

# Önbellek anahtarından tam dosya yolu (hashli ad).
mergen_tts_audio_cache_path <- function(cache_dir, key, response_format) {
  if (!nzchar(cache_dir %||% "") || !nzchar(key %||% "")) return("")
  file.path(cache_dir, paste0(key, ".", mergen_tts_format_ext(response_format)))
}

# Önbellekten ham baytları okur (yoksa/boşsa NULL).
mergen_tts_audio_cache_read <- function(cache_path) {
  if (!nzchar(cache_path %||% "") || !file.exists(cache_path)) return(NULL)
  size <- tryCatch(file.info(cache_path)$size, error = function(e) NA_real_)
  if (is.na(size) || size <= 0) return(NULL)
  raw_bytes <- tryCatch(readBin(cache_path, "raw", n = as.integer(size)), error = function(e) NULL)
  if (is.null(raw_bytes) || length(raw_bytes) == 0L) return(NULL)
  raw_bytes
}

#' Üretilen Sesi Önbelleğe Yaz (atomik: geçici dosya + yeniden adlandırma)
#' @return Mantıksal (başarı). Asla exception fırlatmaz.
mergen_tts_audio_cache_write <- function(cache_path, raw_bytes) {
  if (!nzchar(cache_path %||% "") || length(raw_bytes) == 0L) return(FALSE)
  tryCatch({
    dir <- dirname(cache_path)
    if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    tmp <- paste0(cache_path, ".tmp-", Sys.getpid(), "-", as.integer(stats::runif(1, 1, 1e9)))
    con <- file(tmp, open = "wb")
    writeBin(raw_bytes, con)
    close(con)
    ok <- suppressWarnings(file.rename(tmp, cache_path))
    if (!isTRUE(ok)) {
      copied <- suppressWarnings(file.copy(tmp, cache_path, overwrite = TRUE))
      unlink(tmp, force = TRUE)
      return(isTRUE(copied))
    }
    TRUE
  }, error = function(e) FALSE)
}

#' Önbellek Temizliği (TTL + boyut sınırı, LRU)
#'
#' @description Süresi dolan dosyaları (mtime > ttl_days) siler; toplam boyut
#'   max_mb'yi aşıyorsa en eski dosyalardan başlayarak sınırın altına iner.
#'   Açılışı bloklamaz; tembel/düşük öncelikle çağrılır. Asla exception fırlatmaz.
#' @return Görünmez NULL
mergen_tts_audio_cache_cleanup <- function(cache_dir, max_mb = 512, ttl_days = 30,
                                           now = Sys.time()) {
  tryCatch({
    if (!nzchar(cache_dir %||% "") || !dir.exists(cache_dir)) return(invisible(NULL))
    files <- list.files(cache_dir, pattern = "\\.(wav|mp3|flac|aac|opus|ogg|pcm)$",
                        full.names = TRUE, ignore.case = TRUE)
    if (length(files) == 0L) return(invisible(NULL))

    info <- file.info(files)
    info$path <- rownames(info)

    # 1) TTL süresi dolanları sil
    if (!is.null(ttl_days) && ttl_days > 0) {
      age_days <- as.numeric(difftime(now, info$mtime, units = "days"))
      expired <- info$path[!is.na(age_days) & age_days > ttl_days]
      if (length(expired) > 0L) {
        unlink(expired, force = TRUE)
        info <- info[!(info$path %in% expired), , drop = FALSE]
      }
    }

    # 2) Boyut sınırını uygula (en eskiden başlayarak)
    if (nrow(info) > 0L && !is.null(max_mb) && max_mb > 0) {
      budget <- max_mb * 1024^2
      total <- sum(info$size, na.rm = TRUE)
      if (total > budget) {
        ord <- order(info$mtime, decreasing = FALSE)
        info <- info[ord, , drop = FALSE]
        for (i in seq_len(nrow(info))) {
          if (total <= budget) break
          unlink(info$path[i], force = TRUE)
          total <- total - (info$size[i] %||% 0)
        }
      }
    }
    invisible(NULL)
  }, error = function(e) invisible(NULL))
}
