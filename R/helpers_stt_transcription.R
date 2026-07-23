# R/helpers_stt_transcription.R
# Dosya Yolu: R/helpers_stt_transcription.R
# Açıklama: Sesli Giriş (STT) ses parçası çevirisi için SAF, worker-güvenli
#           yardımcı. base64 ses parçasını çözer, 16kHz mono WAV'e çevirir ve
#           OpenAI uyumlu STT uç noktasına gönderip metni döndürür. Ağır işler
#           (av dönüştürme + HTTP POST) buraya alındı; böylece STT çevirisi
#           tracked_future_promise ile arka planda çalışır ve ana olay döngüsünü
#           (İptal/Onayla/Temizle/Durdur butonları) bloklamaz.

#' Tek bir STT ses parçasını metne çevirir (worker-güvenli, saf).
#'
#' Yalnızca ad alanlı paket çağrıları (av::, httr::, jsonlite::, base64enc::) ve
#' kendi argümanlarını kullanır; başka global yardımcıya bağımlı değildir. Bu
#' sayede explicit dependency_mode ile future worker'a güvenle taşınabilir.
#'
#' @param chunk_b64 base64 kodlu webm ses parçası
#' @param api_url STT uç nokta URL'si
#' @param api_model STT model kimliği
#' @param api_key Bearer API anahtarı
#' @param timeout_sec HTTP zaman aşımı (saniye)
#' @return Temizlenmiş metin ("" boş/başarısız durumlarda)
mergen_stt_transcribe_chunk <- function(chunk_b64, api_url, api_model, api_key,
                                        timeout_sec = 30) {
  if (is.null(chunk_b64) || !nzchar(chunk_b64) || !nzchar(api_url)) {
    return("")
  }

  audio_binary <- tryCatch(
    base64enc::base64decode(chunk_b64),
    error = function(e) NULL
  )
  if (is.null(audio_binary) || length(audio_binary) == 0) {
    return("")
  }

  input_file <- tempfile(fileext = ".webm")
  wav_file <- tempfile(fileext = ".wav")
  on.exit({
    if (file.exists(input_file)) unlink(input_file)
    if (file.exists(wav_file)) unlink(wav_file)
  }, add = TRUE)

  writeBin(audio_binary, input_file)

  converted <- tryCatch({
    av::av_audio_convert(input_file, wav_file, format = "wav",
                         sample_rate = 16000, channels = 1)
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(converted) || !file.exists(wav_file)) {
    return("")
  }

  # Dosya boyutu kontrolü (sessizlik filtresi 2. katman)
  if (file.size(wav_file) < 2500) {
    return("")
  }

  res <- tryCatch(
    httr::POST(
      url = api_url,
      httr::add_headers(Authorization = paste("Bearer", api_key)),
      body = list(
        file = httr::upload_file(wav_file, type = "audio/wav"),
        model = api_model,
        language = "tr",
        task = "transcribe"
      ),
      encode = "multipart",
      httr::timeout(timeout_sec)
    ),
    error = function(e) NULL
  )

  if (is.null(res) || httr::status_code(res) != 200) {
    return("")
  }

  content_json <- tryCatch(
    httr::content(res, as = "text", encoding = "UTF-8"),
    error = function(e) ""
  )
  parsed <- tryCatch(jsonlite::fromJSON(content_json), error = function(e) NULL)
  text_segment <- if (is.list(parsed)) parsed$text else NULL

  if (is.null(text_segment) || length(text_segment) == 0 || !nzchar(text_segment)) {
    return("")
  }

  Encoding(text_segment) <- "UTF-8"
  clean_text <- trimws(text_segment)

  # Model halüsinasyon filtreleri (sessizlik anında üretilen tipik metinler)
  if (grepl("^(Altyazı|Alt yazı)", clean_text, ignore.case = TRUE)) {
    return("")
  }
  if (grepl("^(Evet\\.|Hımmm|Sadece|Teşekkürler\\.)", clean_text) &&
      nchar(clean_text) < 10) {
    return("")
  }

  clean_text
}
