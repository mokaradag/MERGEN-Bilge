# ==============================================================================
# Dosya Yolu: R/helpers_tts_audio_validation.R
# Açıklama:   WAV ses kabı (container) ayrıştırma ve doğrulama katmanı.
#             İki kullanıcısı vardır:
#               1) Referans-ses profili doğrulaması (helpers_tts_voice_manifest.R
#                  içindeki mergen_tts_read_wav_metadata bu dosyadaki çekirdek
#                  bayt ayrıştırıcıya delege eder).
#               2) ÜRETİLEN ses (TTS yanıtı) doğrulaması: sunucudan gelen WAV
#                  yapısal olarak eksik/kesik/bozuk ise tarayıcıya gönderilmeden
#                  ve önbelleğe yazılmadan reddedilir (abartılı kısa süre =
#                  yarıda kesilmiş konuşma belirtisidir).
#
#             Ayrıştırıcı uzantıya güvenmez; RIFF/WAVE imzasını, chunk sınırlarını
#             ve BİLDİRİLEN chunk uzunluklarını GERÇEKTEN alınan bayt sayısına
#             karşı denetler. Sabit 44 baytlık başlık VARSAYILMAZ; `data`
#             chunk'ından önce ek yasal chunk'lar (LIST/fact/vb.) desteklenir.
#
#             Bu dosya yalnızca saf (Shiny/DB/ağ yan etkisi olmayan) yardımcılar
#             barındırır; bu yüzden TTS future-worker'ına güvenle taşınabilir ve
#             izole test edilebilir. tts_ses_profilleri bölümünde manifest'ten
#             ÖNCE yüklenir (manifest çekirdek ayrıştırıcıyı çağırır).
# ==============================================================================

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
}

# Üretilen ses doğrulaması için makul biçim aralıkları (merkezi eşikler).
# Referans-ses doğrulaması (mono/16-bit/16 kHz) ayrı ve daha katıdır; burada
# amaç sunucunun ürettiği geçerli-ama-değişken WAV'ları kabul edip yalnızca
# yapısal olarak bozuk/kesik olanları reddetmektir.
MERGEN_TTS_WAV_MIN_CHANNELS      <- 1L
MERGEN_TTS_WAV_MAX_CHANNELS      <- 8L
MERGEN_TTS_WAV_MIN_SAMPLE_RATE   <- 8000
MERGEN_TTS_WAV_MAX_SAMPLE_RATE   <- 192000
MERGEN_TTS_WAV_ALLOWED_BITS      <- c(8L, 16L, 24L, 32L)
# Üretilen ses için minimum makul süre (çok kısa = boş/kesik yanıt belirtisi).
MERGEN_TTS_WAV_MIN_DURATION_SECS <- 0.04

# Süre/metin makullük denetimi eşikleri. Amaç: uzun bir metin parçasının
# saçma derecede kısa bir sese dönüşmesini (yarıda kesilme) yakalamak. Eşikler
# BİLİNÇLİ olarak gevşektir; gerçek hızlı Türkçe konuşma ~20-25 karakter/sn
# civarındadır, bu yüzden 45 karakter/sn üstü fiziksel olarak imkânsıza yakındır.
MERGEN_TTS_PLAUSIBILITY_MIN_CHARS       <- 48L
MERGEN_TTS_PLAUSIBILITY_MAX_CHARS_PER_S <- 45

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

#' WAV Baytlarını Ayrıştır (çekirdek, uzantısız)
#'
#' @description Ham WAV baytlarından RIFF/WAVE başlığını ve fmt/data chunk'larını
#'   ayrıştırır. `data` chunk'ından önce ek yasal chunk'lara izin verir. Bildirilen
#'   RIFF/chunk uzunluklarını gerçek bayt sayısına karşı denetleyip kesilme
#'   (truncation) bayrağı üretir. ASLA exception fırlatmaz.
#' @param raw_all Ham bayt vektörü (raw)
#' @return Liste: header_ok, error, format_code, channels, sample_rate, byte_rate,
#'   block_align, bits_per_sample, has_fmt, has_data, data_declared_bytes,
#'   data_offset, data_available_bytes, effective_data_bytes, total_bytes,
#'   riff_declared_size, truncated, truncated_reason, duration_secs (bildirilen
#'   data'dan), effective_duration_secs (gerçek/etkin data'dan)
mergen_tts_parse_wav_bytes <- function(raw_all) {
  res <- list(
    header_ok = FALSE, error = NULL,
    format_code = NA_real_, channels = NA_real_, sample_rate = NA_real_,
    byte_rate = NA_real_, block_align = NA_real_, bits_per_sample = NA_real_,
    has_fmt = FALSE, has_data = FALSE,
    data_declared_bytes = NA_real_, data_offset = NA_real_,
    data_available_bytes = NA_real_, effective_data_bytes = NA_real_,
    total_bytes = 0, riff_declared_size = NA_real_,
    truncated = FALSE, truncated_reason = NULL,
    duration_secs = NA_real_, effective_duration_secs = NA_real_
  )

  if (!is.raw(raw_all)) {
    raw_all <- tryCatch(as.raw(raw_all), error = function(e) raw(0))
  }
  n <- length(raw_all)
  res$total_bytes <- as.numeric(n)

  if (n < 12L) {
    res$error <- "WAV başlığı okunamadı."
    return(res)
  }
  if (.mergen_tts_chunk_id(raw_all[1:4]) != "RIFF" ||
      .mergen_tts_chunk_id(raw_all[9:12]) != "WAVE") {
    res$error <- "Dosya RIFF/WAVE biçiminde değil."
    return(res)
  }
  res$header_ok <- TRUE
  res$riff_declared_size <- .mergen_tts_le_uint(raw_all[5:8])

  # RIFF boyutu (dosya boyutu - 8) gerçek baytları aşıyorsa kesik demektir.
  # 0 ve 0xFFFFFFFF akış (streaming) sentinel değerleridir; kesik sayılmaz.
  riff_sz <- res$riff_declared_size
  if (!is.na(riff_sz) && riff_sz >= 4 && riff_sz < 4294967295 &&
      (riff_sz + 8) > n) {
    res$truncated <- TRUE
    res$truncated_reason <- "RIFF gövdesi bildirilenden kısa (kesik)."
  }

  pos <- 13L
  iter <- 0L
  while (pos + 7L <= n && iter < 512L) {
    iter <- iter + 1L
    chunk_id <- .mergen_tts_chunk_id(raw_all[pos:(pos + 3L)])
    chunk_size <- .mergen_tts_le_uint(raw_all[(pos + 4L):(pos + 7L)])
    if (is.na(chunk_size) || chunk_size < 0) break
    body_start <- pos + 8L

    if (identical(chunk_id, "fmt ")) {
      if (body_start + 15L <= n) {
        fmt <- raw_all[body_start:(body_start + 15L)]
        res$format_code     <- .mergen_tts_le_uint(fmt[1:2])
        res$channels        <- .mergen_tts_le_uint(fmt[3:4])
        res$sample_rate     <- .mergen_tts_le_uint(fmt[5:8])
        res$byte_rate       <- .mergen_tts_le_uint(fmt[9:12])
        res$block_align     <- .mergen_tts_le_uint(fmt[13:14])
        res$bits_per_sample <- .mergen_tts_le_uint(fmt[15:16])
        res$has_fmt <- TRUE
      } else {
        # fmt chunk'ı için gereken 16 bayt yok -> kesik başlık.
        res$truncated <- TRUE
        res$truncated_reason <- res$truncated_reason %||% "fmt chunk'ı eksik/kesik."
        break
      }
    } else if (identical(chunk_id, "data")) {
      res$has_data <- TRUE
      res$data_declared_bytes <- chunk_size
      res$data_offset <- body_start
      # data chunk'ından sonra fiziksel olarak mevcut bayt sayısı.
      res$data_available_bytes <- max(0, n - (body_start - 1L))
    }

    # Bildirilen chunk boyutu dosya sonunu aşıyorsa güvenle ilerleyemeyiz.
    if (!identical(chunk_id, "data") &&
        (body_start + chunk_size - 1L) > n) {
      res$truncated <- TRUE
      res$truncated_reason <- res$truncated_reason %||%
        sprintf("'%s' chunk boyutu alınan bayttan büyük (kesik).", chunk_id)
      break
    }

    # Chunk'lar word (2 bayt) hizalıdır; tek boyutta 1 dolgu baytı.
    advance <- 8L + chunk_size + (chunk_size %% 2)
    if (advance <= 0) break
    pos <- pos + advance
  }

  # Etkin data baytı: bildirilen değer gerçek baytları aşıyorsa KESİK'tir;
  # bildirilen 0/eksikse akış WAV'ı kabul edilir ve gerçek mevcut baytlar kullanılır.
  if (isTRUE(res$has_data)) {
    declared <- res$data_declared_bytes
    available <- res$data_available_bytes %||% 0
    if (!is.na(declared) && declared > 0 && declared > available) {
      res$truncated <- TRUE
      res$truncated_reason <- res$truncated_reason %||%
        "data chunk boyutu alınan bayttan büyük (kesik)."
      res$effective_data_bytes <- available
    } else if (!is.na(declared) && declared > 0) {
      res$effective_data_bytes <- declared
    } else {
      res$effective_data_bytes <- available
    }
  }

  # Süre: byte_rate varsa ondan; yoksa fmt alanlarından hesapla.
  compute_duration <- function(data_bytes) {
    if (is.na(data_bytes)) return(NA_real_)
    if (!is.na(res$byte_rate) && res$byte_rate > 0) {
      return(data_bytes / res$byte_rate)
    }
    if (!is.na(res$sample_rate) && !is.na(res$channels) &&
        !is.na(res$bits_per_sample) && res$sample_rate > 0 &&
        res$channels > 0 && res$bits_per_sample > 0) {
      return(data_bytes / (res$sample_rate * res$channels * res$bits_per_sample / 8))
    }
    NA_real_
  }

  # duration_secs: BİLDİRİLEN data'dan (mergen_tts_read_wav_metadata ile birebir
  # uyumlu). effective_duration_secs: gerçek/etkin data'dan (üretilen doğrulama).
  res$duration_secs <- compute_duration(res$data_declared_bytes)
  res$effective_duration_secs <- compute_duration(res$effective_data_bytes)

  res
}

#' Base64/veri-URL ses yükünü ham baytlara çöz (hata toleranslı)
#'
#' @description JSON sarmalayıcı yanıtlarda ses base64 veya `data:...;base64,...`
#'   biçiminde gelebilir. Bu yardımcı öneki soyar ve güvenle çözer; başarısızlıkta
#'   NULL döndürür (asla exception fırlatmaz).
#' @param x Base64 dizgesi veya data URL
#' @return Ham bayt vektörü veya NULL
mergen_tts_decode_audio_payload <- function(x) {
  s <- as.character(x %||% "")[1]
  if (is.na(s) || !nzchar(s)) return(NULL)
  pure <- sub("^data:[^,]*,", "", s)
  pure <- gsub("[[:space:]]", "", pure)
  if (!nzchar(pure)) return(NULL)
  tryCatch({
    raw_bytes <- base64enc::base64decode(pure)
    if (length(raw_bytes) == 0L) return(NULL)
    raw_bytes
  }, error = function(e) NULL)
}

#' Süre/Metin Makullük Denetimi
#'
#' @description Uzun bir metin parçasının fiziksel olarak imkânsız derecede kısa
#'   bir sese dönüşüp dönüşmediğini (yarıda kesilme belirtisi) BİLİNÇLİ gevşek bir
#'   kuralla denetler. Kısa metinlerde denetim uygulanmaz (yanlış-pozitif kaçınma).
#' @param duration_secs Ölçülen (WAV) süre
#' @param text_chars Metnin karakter uzunluğu
#' @param min_chars_for_check Bu uzunluğun altında denetim yapılmaz
#' @param max_chars_per_second Fiziksel üst konuşma hızı sınırı (karakter/sn)
#' @return Mantıksal: makul ise TRUE
mergen_tts_audio_duration_plausible <- function(duration_secs, text_chars,
                                                min_chars_for_check = MERGEN_TTS_PLAUSIBILITY_MIN_CHARS,
                                                max_chars_per_second = MERGEN_TTS_PLAUSIBILITY_MAX_CHARS_PER_S) {
  text_chars <- suppressWarnings(as.numeric(text_chars %||% 0))
  duration_secs <- suppressWarnings(as.numeric(duration_secs %||% NA_real_))
  if (is.na(text_chars) || text_chars < min_chars_for_check) return(TRUE)
  if (is.na(duration_secs) || duration_secs <= 0) return(FALSE)
  if (is.na(max_chars_per_second) || max_chars_per_second <= 0) return(TRUE)
  min_expected <- text_chars / max_chars_per_second
  duration_secs >= min_expected
}

#' Üretilen WAV'ı Yapısal Olarak Doğrula
#'
#' @description Sunucudan gelen ham WAV baytlarını (veya base64/data-URL yükünü)
#'   önbelleğe yazmadan ve tarayıcıya göndermeden önce doğrular. Referans-ses
#'   doğrulamasından daha gevşektir (mono/16-bit/16 kHz ZORUNLU DEĞİL); yalnızca
#'   yapısal bütünlüğü ve makul biçimi denetler. ASLA exception fırlatmaz.
#'
#'   Denetimler: RIFF imzası, WAVE imzası, fmt chunk varlığı+geçerliliği, data
#'   chunk varlığı, bildirilen uzunlukların alınan bayta karşı tutarlılığı (kesik
#'   reddi), sıfırdan farklı/makul kanal sayısı, örnekleme hızı, bit derinliği ve
#'   pozitif (hesaplanabilir) süre. `text` verilirse ek makullük denetimi uygulanır.
#'
#' @param audio Ham bayt vektörü (raw) VEYA base64/data-URL dizgesi
#' @param text (opsiyonel) Sentezlenen metin; süre/metin makullük denetimi için
#' @param min_duration_secs Kabul edilen alt süre sınırı
#' @param check_plausibility Süre/metin makullük denetimi uygulansın mı
#' @return Liste: ok, error, retryable, duration, channels, sample_rate,
#'   bits_per_sample, metadata
mergen_tts_validate_generated_wav <- function(audio, text = NULL,
                                              min_duration_secs = MERGEN_TTS_WAV_MIN_DURATION_SECS,
                                              check_plausibility = TRUE) {
  fail <- function(msg, retryable = TRUE, meta = NULL) {
    list(ok = FALSE, error = msg, retryable = retryable, duration = NA_real_,
         channels = NA_real_, sample_rate = NA_real_, bits_per_sample = NA_real_,
         metadata = meta)
  }

  raw_bytes <- if (is.raw(audio)) audio else mergen_tts_decode_audio_payload(audio)
  if (is.null(raw_bytes) || length(raw_bytes) == 0L) {
    return(fail("Üretilen ses boş.", retryable = TRUE))
  }

  meta <- mergen_tts_parse_wav_bytes(raw_bytes)

  if (!isTRUE(meta$header_ok)) {
    return(fail(meta$error %||% "Geçersiz WAV başlığı (RIFF/WAVE yok).", meta = meta))
  }
  if (isTRUE(meta$truncated)) {
    return(fail(meta$truncated_reason %||% "WAV kesik/eksik.", meta = meta))
  }
  if (!isTRUE(meta$has_fmt) || is.na(meta$format_code) || is.na(meta$sample_rate)) {
    return(fail("WAV fmt chunk'ı eksik veya geçersiz.", meta = meta))
  }
  if (!isTRUE(meta$has_data)) {
    return(fail("WAV data chunk'ı bulunamadı.", meta = meta))
  }
  # format_code 0 geçersizdir; PCM(1)/IEEE float(3)/EXTENSIBLE(65534) yaygındır.
  if (isTRUE(meta$format_code == 0)) {
    return(fail("WAV biçim kodu geçersiz (0).", meta = meta))
  }
  ch <- meta$channels
  if (is.na(ch) || ch < MERGEN_TTS_WAV_MIN_CHANNELS || ch > MERGEN_TTS_WAV_MAX_CHANNELS) {
    return(fail("WAV kanal sayısı geçersiz.", meta = meta))
  }
  sr <- meta$sample_rate
  if (is.na(sr) || sr < MERGEN_TTS_WAV_MIN_SAMPLE_RATE || sr > MERGEN_TTS_WAV_MAX_SAMPLE_RATE) {
    return(fail("WAV örnekleme hızı geçersiz.", meta = meta))
  }
  bits <- meta$bits_per_sample
  if (is.na(bits) || !(as.integer(bits) %in% MERGEN_TTS_WAV_ALLOWED_BITS)) {
    return(fail("WAV bit derinliği desteklenmiyor.", meta = meta))
  }

  duration <- meta$effective_duration_secs
  if (is.na(duration) || !is.finite(duration) || duration <= 0 ||
      duration < min_duration_secs) {
    return(fail("WAV süresi hesaplanamıyor veya sıfır/çok kısa.", meta = meta))
  }

  if (isTRUE(check_plausibility) && !is.null(text)) {
    text_chars <- nchar(as.character(text %||% "")[1], type = "chars", allowNA = FALSE, keepNA = FALSE)
    if (!isTRUE(mergen_tts_audio_duration_plausible(duration, text_chars))) {
      return(fail("Üretilen ses metne göre şüpheli derecede kısa (yarıda kesilmiş olabilir).",
                  retryable = TRUE, meta = meta))
    }
  }

  list(
    ok = TRUE, error = NULL, retryable = FALSE,
    duration = duration,
    channels = ch, sample_rate = sr, bits_per_sample = bits,
    metadata = meta
  )
}
