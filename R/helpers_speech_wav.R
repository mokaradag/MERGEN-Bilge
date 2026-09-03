# R/helpers_speech_wav.R
# Saf WAV (RIFF/WAVE) yardımcıları: PCM WAV üretimi (test/aday doğrulama),
# başlık ayrıştırma ve üretim profili doğrulaması. Uzantıya güvenilmez; gerçek
# başlık baytları okunur. Süre, istek süresinden değil WAV başlığından
# hesaplanır. Shiny/ağ/DB erişimi yoktur.

#' 32-bit little-endian tamsayıyı raw'a çevir.
.speech_wav_uint32le <- function(x) {
  x <- as.numeric(x)
  as.raw(c(x %% 256, (x %/% 256) %% 256, (x %/% 65536) %% 256, (x %/% 16777216) %% 256))
}

#' 16-bit little-endian tamsayıyı raw'a çevir.
.speech_wav_uint16le <- function(x) {
  x <- as.integer(x)
  as.raw(c(x %% 256L, (x %/% 256L) %% 256L))
}

#' Raw baytlardan little-endian işaretsiz tamsayı oku.
.speech_wav_read_uintle <- function(bytes) {
  if (length(bytes) == 0) return(NA_real_)
  sum(as.numeric(bytes) * 256^(seq_along(bytes) - 1))
}

#' Deterministik PCM WAV baytları üret. Testlerde ve üretici öz-denetiminde
#' küçük fixture'lar için kullanılır; `samples` verilmezse sessizlik üretir.
#'
#' @param n_samples Toplam örnek sayısı (kanal başına).
#' @param sample_rate Örnekleme hızı (Hz).
#' @param channels Kanal sayısı.
#' @param bits_per_sample Bit derinliği (8 veya 16).
#' @param samples İsteğe bağlı örnek değerleri (16-bit için -32768..32767).
#' @return WAV dosya içeriği (raw vektör).
mergen_wav_build_pcm <- function(n_samples = 1600L,
                                 sample_rate = 16000L,
                                 channels = 1L,
                                 bits_per_sample = 16L,
                                 samples = NULL) {
  n_samples <- as.integer(n_samples)
  channels <- as.integer(channels)
  bits_per_sample <- as.integer(bits_per_sample)
  bytes_per_sample <- bits_per_sample %/% 8L

  if (is.null(samples)) samples <- integer(n_samples * channels)
  total_samples <- length(samples)

  data_bytes <- if (bits_per_sample == 16L) {
    writeBin(as.integer(samples), raw(), size = 2L, endian = "little")
  } else {
    as.raw((as.integer(samples) + 128L) %% 256L)
  }

  byte_rate <- sample_rate * channels * bytes_per_sample
  block_align <- channels * bytes_per_sample
  data_size <- length(data_bytes)

  c(
    charToRaw("RIFF"),
    .speech_wav_uint32le(36 + data_size),
    charToRaw("WAVE"),
    charToRaw("fmt "),
    .speech_wav_uint32le(16),
    .speech_wav_uint16le(1L),               # PCM
    .speech_wav_uint16le(channels),
    .speech_wav_uint32le(sample_rate),
    .speech_wav_uint32le(byte_rate),
    .speech_wav_uint16le(block_align),
    .speech_wav_uint16le(bits_per_sample),
    charToRaw("data"),
    .speech_wav_uint32le(data_size),
    data_bytes
  )
}

#' WAV başlığını ayrıştır. Bozuk/eksik dosyalarda ok = FALSE ve neden döner.
#'
#' @param path WAV dosya yolu.
#' @return list(ok, reason, format_code, channels, sample_rate,
#'   bits_per_sample, data_bytes, duration_ms)
mergen_wav_parse <- function(path) {
  fail <- function(reason) {
    list(ok = FALSE, reason = reason, format_code = NA_integer_,
         channels = NA_integer_, sample_rate = NA_integer_,
         bits_per_sample = NA_integer_, data_bytes = NA_real_,
         duration_ms = NA_real_)
  }

  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    return(fail("gecersiz_yol"))
  }
  if (!file.exists(path)) return(fail("dosya_yok"))

  file_size <- suppressWarnings(file.info(path)$size)
  if (is.na(file_size) || file_size <= 0) return(fail("bos_dosya"))
  if (file_size < 44) return(fail("kesik_dosya"))

  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)

  header <- readBin(con, "raw", n = 12L)
  if (length(header) < 12L) return(fail("kesik_dosya"))
  if (!identical(rawToChar(header[1:4]), "RIFF")) return(fail("riff_imzasi_gecersiz"))
  if (!identical(rawToChar(header[9:12]), "WAVE")) return(fail("wave_imzasi_gecersiz"))

  fmt <- NULL
  data_size <- NA_real_
  data_offset <- NA_real_
  offset <- 12

  while (offset + 8 <= file_size) {
    chunk_header <- readBin(con, "raw", n = 8L)
    if (length(chunk_header) < 8L) break

    chunk_id <- rawToChar(chunk_header[1:4])
    chunk_size <- .speech_wav_read_uintle(chunk_header[5:8])
    body_start <- offset + 8

    if (is.na(chunk_size) || chunk_size < 0 || body_start + chunk_size > file_size + 1) {
      if (identical(chunk_id, "data")) return(fail("data_kesik"))
      return(fail("kesik_dosya"))
    }

    if (identical(chunk_id, "fmt ")) {
      if (chunk_size < 16) return(fail("fmt_kesik"))
      fmt_bytes <- readBin(con, "raw", n = 16L)
      if (length(fmt_bytes) < 16L) return(fail("fmt_kesik"))
      fmt <- list(
        format_code = as.integer(.speech_wav_read_uintle(fmt_bytes[1:2])),
        channels = as.integer(.speech_wav_read_uintle(fmt_bytes[3:4])),
        sample_rate = as.integer(.speech_wav_read_uintle(fmt_bytes[5:8])),
        byte_rate = .speech_wav_read_uintle(fmt_bytes[9:12]),
        block_align = as.integer(.speech_wav_read_uintle(fmt_bytes[13:14])),
        bits_per_sample = as.integer(.speech_wav_read_uintle(fmt_bytes[15:16]))
      )
      remaining <- chunk_size - 16
      if (remaining > 0) readBin(con, "raw", n = as.integer(remaining))
    } else if (identical(chunk_id, "data")) {
      data_size <- chunk_size
      data_offset <- body_start
      break
    } else {
      readBin(con, "raw", n = as.integer(chunk_size))
    }

    # Tek baytlık hizalama (chunk boyutları çift bayta hizalanır)
    offset <- body_start + chunk_size + (chunk_size %% 2)
    if (chunk_size %% 2 == 1 && offset <= file_size) readBin(con, "raw", n = 1L)
  }

  if (is.null(fmt)) return(fail("fmt_chunk_yok"))
  if (is.na(data_size)) return(fail("data_chunk_yok"))
  if (!identical(fmt$format_code, 1L)) return(fail("desteklenmeyen_kodlama"))
  if (data_offset + data_size > file_size) return(fail("data_kesik"))
  if (is.na(fmt$byte_rate) || fmt$byte_rate <= 0) return(fail("gecersiz_bayt_hizi"))

  duration_ms <- (data_size / fmt$byte_rate) * 1000

  list(
    ok = TRUE, reason = NULL,
    format_code = fmt$format_code,
    channels = fmt$channels,
    sample_rate = fmt$sample_rate,
    bits_per_sample = fmt$bits_per_sample,
    data_bytes = data_size,
    duration_ms = duration_ms
  )
}

#' WAV dosyasını üretim profiline göre doğrula.
#'
#' @param path WAV yolu.
#' @param expected list(sample_rate, channels, bits_per_sample) veya NULL.
#' @param min_ms / max_ms Makul süre sınırları (ms).
#' @return list(ok, reason, info = mergen_wav_parse çıktısı)
mergen_wav_validate <- function(path, expected = NULL,
                                min_ms = 200, max_ms = 180000) {
  info <- mergen_wav_parse(path)
  if (!isTRUE(info$ok)) {
    return(list(ok = FALSE, reason = info$reason, info = info))
  }

  if (!is.null(expected)) {
    if (!is.null(expected$sample_rate) &&
        !identical(as.integer(info$sample_rate), as.integer(expected$sample_rate))) {
      return(list(ok = FALSE, reason = "ornekleme_hizi_uyusmuyor", info = info))
    }
    if (!is.null(expected$channels) &&
        !identical(as.integer(info$channels), as.integer(expected$channels))) {
      return(list(ok = FALSE, reason = "kanal_sayisi_uyusmuyor", info = info))
    }
    if (!is.null(expected$bits_per_sample) &&
        !identical(as.integer(info$bits_per_sample), as.integer(expected$bits_per_sample))) {
      return(list(ok = FALSE, reason = "bit_derinligi_uyusmuyor", info = info))
    }
  }

  if (is.finite(min_ms) && info$duration_ms < min_ms) {
    return(list(ok = FALSE, reason = "sure_cok_kisa", info = info))
  }
  if (is.finite(max_ms) && info$duration_ms > max_ms) {
    return(list(ok = FALSE, reason = "sure_cok_uzun", info = info))
  }

  list(ok = TRUE, reason = NULL, info = info)
}
