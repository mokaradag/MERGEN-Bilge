#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/test_voxcpm2_tts.R
# Açıklama:
#   Mergen Bilge uygulamasını değiştirmeden VoxCPM2 TTS modelini sınar.
#   Mevcut LOCAL_TTS_* ortam değişkenlerini kullanır ve isteğe bağlı bir WAV
#   dosyasını base64 veri URL'sine dönüştürerek ref_audio alanında gönderir.
#   --output verilmezse oluşan ses kalıcı olarak Masaüstü/VoxCPM2_Test
#   klasörüne kaydedilir.
#
# Örnekler:
#   Rscript tests/scripts/test_voxcpm2_tts.R
#   Rscript tests/scripts/test_voxcpm2_tts.R --text="Merhaba, bu bir Türkçe ses testidir."
#   Rscript tests/scripts/test_voxcpm2_tts.R --ref-audio="C:/Temp/erkek_1.wav"
#   Rscript tests/scripts/test_voxcpm2_tts.R --ref-audio="C:/Temp/kadin_1.wav" --output="C:/Temp/voxcpm2_kadin_1.wav"
#   Rscript tests/scripts/test_voxcpm2_tts.R --dry-run
# ==============================================================================

options(warn = 1)

args <- commandArgs(trailingOnly = TRUE)

arg_value <- function(name, default = NULL) {
  prefix <- paste0(name, "=")
  direct <- args[startsWith(args, prefix)]
  if (length(direct) > 0L) {
    return(sub(prefix, "", direct[[1]], fixed = TRUE))
  }

  pos <- match(name, args)
  if (!is.na(pos) && pos < length(args)) {
    return(args[[pos + 1L]])
  }

  default
}

has_flag <- function(name) {
  name %in% args
}

show_help <- function() {
  cat(paste0(
    "VoxCPM2 bağımsız TTS testi\n\n",
    "Kullanım:\n",
    "  Rscript tests/scripts/test_voxcpm2_tts.R [seçenekler]\n\n",
    "Seçenekler:\n",
    "  --text <metin>               Seslendirilecek Türkçe metin.\n",
    "  --ref-audio <wav-yolu>       Klonlama için WAV referans sesi.\n",
    "  --output <dosya-yolu>        Yanıtın kaydedileceği dosya.\n",
    "                                Verilmezse Masaüstü/VoxCPM2_Test kullanılır.\n",
    "  --voice <ad>                 Varsayılan: default.\n",
    "  --model <model>              Varsayılan: VoxCPM2.\n",
    "  --response-format <biçim>    İsteğe bağlı; ör. wav veya mp3.\n",
    "  --dry-run                    Ağa çıkmadan yapılandırmayı doğrular.\n",
    "  --allow-no-api-key           API anahtarı olmadan isteğe izin verir.\n",
    "  --help                       Bu yardımı gösterir.\n\n",
    "Kullanılan ortam değişkenleri:\n",
    "  LOCAL_TTS_ENDPOINT, LOCAL_TTS_API_KEY, LOCAL_TTS_TIMEOUT,\n",
    "  LOCAL_TTS_VERIFY_SSL, MERGEN_ALLOW_DEFAULT_API_KEY,\n",
    "  MERGEN_REQUIRE_PERSONAL_API_KEY, MERGEN_DEFAULT_API_KEY,\n",
    "  LOCAL_LLM_API_KEY\n\n",
    "İsteğe bağlı çıktı klasörü override'ı:\n",
    "  VOXCPM2_TEST_OUTPUT_DIR\n"
  ))
}

if (has_flag("--help") || has_flag("-h")) {
  show_help()
  quit(status = 0L)
}

required_packages <- c("httr", "jsonlite", "base64enc")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0L) {
  stop(
    sprintf(
      "Eksik R paketleri: %s. Önce renv::restore() çalıştırın.",
      paste(missing_packages, collapse = ", ")
    ),
    call. = FALSE
  )
}

find_repo_root <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }
  normalizePath(".", winslash = "/", mustWork = TRUE)
}

repo_root <- find_repo_root()
renviron_path <- file.path(repo_root, ".Renviron")
if (file.exists(renviron_path)) {
  readRenviron(renviron_path)
}

scalar_env <- function(name, default = "") {
  value <- Sys.getenv(name, unset = default)
  if (length(value) == 0L || is.na(value[[1]])) return(default)
  trimws(as.character(value[[1]]))
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || is.na(x[[1]])) y else x
}

as_bool <- function(value, default = FALSE) {
  value <- tolower(trimws(as.character(value %||% "")))
  if (!nzchar(value)) return(default)
  if (value %in% c("true", "t", "1", "yes", "y")) return(TRUE)
  if (value %in% c("false", "f", "0", "no", "n")) return(FALSE)
  default
}

existing_directory <- function(paths) {
  paths <- unique(paths[nzchar(paths)])
  matches <- paths[dir.exists(paths)]
  if (length(matches) == 0L) return("")
  normalizePath(matches[[1]], winslash = "/", mustWork = TRUE)
}

resolve_desktop_dir <- function() {
  override <- scalar_env("VOXCPM2_TEST_OUTPUT_DIR")
  if (nzchar(override)) {
    override <- path.expand(override)
    dir.create(override, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(override)) {
      stop(
        sprintf("VOXCPM2_TEST_OUTPUT_DIR oluşturulamadı: %s", override),
        call. = FALSE
      )
    }
    return(normalizePath(override, winslash = "/", mustWork = TRUE))
  }

  powershell_desktop <- ""
  if (identical(.Platform$OS.type, "windows")) {
    powershell_desktop <- tryCatch({
      command <- "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)"
      result <- suppressWarnings(system2(
        "powershell.exe",
        args = c("-NoProfile", "-NonInteractive", "-Command", shQuote(command)),
        stdout = TRUE,
        stderr = FALSE
      ))
      result <- trimws(result)
      result <- result[nzchar(result)]
      if (length(result) > 0L) result[[1]] else ""
    }, error = function(e) "")
  }

  desktop_under <- function(base) {
    if (!nzchar(base)) return("")
    file.path(base, "Desktop")
  }

  candidates <- c(
    powershell_desktop,
    desktop_under(scalar_env("OneDriveCommercial")),
    desktop_under(scalar_env("OneDrive")),
    desktop_under(scalar_env("USERPROFILE")),
    desktop_under(scalar_env("HOME")),
    desktop_under(path.expand("~"))
  )

  desktop <- existing_directory(candidates)
  if (nzchar(desktop)) return(desktop)

  fallback_base <- scalar_env("USERPROFILE")
  if (!nzchar(fallback_base)) fallback_base <- scalar_env("HOME")
  if (!nzchar(fallback_base)) {
    stop(
      "Windows Masaüstü klasörü belirlenemedi. --output ile açık bir dosya yolu verin.",
      call. = FALSE
    )
  }

  desktop <- file.path(fallback_base, "Desktop")
  dir.create(desktop, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(desktop)) {
    stop(
      sprintf("Masaüstü klasörü oluşturulamadı veya erişilemiyor: %s", desktop),
      call. = FALSE
    )
  }

  normalizePath(desktop, winslash = "/", mustWork = TRUE)
}

build_speech_url <- function(base_url) {
  base_url <- sub("/+$", "", trimws(base_url))
  if (!nzchar(base_url)) return("")
  if (grepl("/audio/speech$", base_url, ignore.case = TRUE)) return(base_url)
  paste0(base_url, "/audio/speech")
}

resolve_api_key <- function() {
  service_key <- scalar_env("LOCAL_TTS_API_KEY")
  if (nzchar(service_key)) {
    return(list(value = service_key, source = "LOCAL_TTS_API_KEY"))
  }

  allow_default <- as_bool(scalar_env("MERGEN_ALLOW_DEFAULT_API_KEY", "FALSE"))
  require_personal <- as_bool(scalar_env("MERGEN_REQUIRE_PERSONAL_API_KEY", "FALSE"))
  default_key <- scalar_env("MERGEN_DEFAULT_API_KEY")

  if (allow_default && !require_personal && nzchar(default_key)) {
    return(list(value = default_key, source = "MERGEN_DEFAULT_API_KEY"))
  }

  legacy_key <- scalar_env("LOCAL_LLM_API_KEY")
  if (nzchar(legacy_key)) {
    return(list(value = legacy_key, source = "LOCAL_LLM_API_KEY"))
  }

  list(value = "", source = "yok")
}

validate_wav <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Referans ses dosyası bulunamadı: %s", path), call. = FALSE)
  }
  if (dir.exists(path)) {
    stop(sprintf("Referans ses yolu bir klasör: %s", path), call. = FALSE)
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  header <- readBin(con, what = "raw", n = 12L)
  if (length(header) < 12L) {
    stop("Referans ses dosyası geçerli bir WAV dosyası değil: başlık çok kısa.", call. = FALSE)
  }

  riff <- rawToChar(header[1:4])
  wave <- rawToChar(header[9:12])
  if (!identical(riff, "RIFF") || !identical(wave, "WAVE")) {
    stop("ref_audio için RIFF/WAVE biçiminde bir WAV dosyası gereklidir.", call. = FALSE)
  }

  normalizePath(path, winslash = "/", mustWork = TRUE)
}

wav_to_data_url <- function(path) {
  file_size <- file.info(path)$size
  if (is.na(file_size) || file_size <= 0) {
    stop("Referans WAV dosyası boş.", call. = FALSE)
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_audio <- readBin(con, what = "raw", n = file_size)
  encoded <- base64enc::base64encode(raw_audio)
  paste0("data:audio/wav;base64,", encoded)
}

mime_extension <- function(content_type) {
  mime <- tolower(trimws(strsplit(content_type %||% "", ";", fixed = TRUE)[[1]][1]))
  switch(
    mime,
    "audio/wav" = "wav",
    "audio/x-wav" = "wav",
    "audio/wave" = "wav",
    "audio/mpeg" = "mp3",
    "audio/mp3" = "mp3",
    "audio/ogg" = "ogg",
    "audio/flac" = "flac",
    "audio/aac" = "aac",
    "application/octet-stream" = "bin",
    "bin"
  )
}

strip_data_url <- function(value) {
  value <- as.character(value %||% "")[[1]]
  if (!startsWith(value, "data:")) {
    return(list(mime = "", base64 = value))
  }

  comma <- regexpr(",", value, fixed = TRUE)[[1]]
  if (comma < 1L) return(list(mime = "", base64 = value))

  meta <- substr(value, 6L, comma - 1L)
  mime <- strsplit(meta, ";", fixed = TRUE)[[1]][1]
  list(mime = mime, base64 = substr(value, comma + 1L, nchar(value)))
}

write_audio_response <- function(response, output_path = NULL) {
  content_type <- httr::headers(response)[["content-type"]] %||% ""
  response_raw <- httr::content(response, as = "raw")
  audio_raw <- response_raw
  detected_mime <- content_type

  if (grepl("json", content_type, ignore.case = TRUE)) {
    parsed <- tryCatch(
      jsonlite::fromJSON(rawToChar(response_raw), simplifyVector = FALSE),
      error = function(e) NULL
    )
    candidate <- NULL
    if (is.list(parsed)) {
      for (field in c("audio", "data", "content")) {
        if (!is.null(parsed[[field]]) && length(parsed[[field]]) > 0L) {
          candidate <- parsed[[field]][[1]] %||% parsed[[field]]
          break
        }
      }
    }
    if (is.null(candidate) || !nzchar(as.character(candidate)[1])) {
      stop("Başarılı HTTP yanıtında çözülebilir ses alanı bulunamadı.", call. = FALSE)
    }

    decoded <- strip_data_url(as.character(candidate)[1])
    audio_raw <- base64enc::base64decode(decoded$base64)
    if (nzchar(decoded$mime)) detected_mime <- decoded$mime
  }

  if (length(audio_raw) == 0L) {
    stop("TTS yanıtı boş ses içeriği döndürdü.", call. = FALSE)
  }

  if (is.null(output_path) || !nzchar(output_path)) {
    ext <- mime_extension(detected_mime)
    stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    output_dir <- file.path(resolve_desktop_dir(), "VoxCPM2_Test")
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(output_dir)) {
      stop(
        sprintf("Çıktı klasörü oluşturulamadı: %s", output_dir),
        call. = FALSE
      )
    }
    output_path <- file.path(output_dir, sprintf("voxcpm2_test_%s.%s", stamp, ext))
  } else {
    output_path <- path.expand(output_path)
    dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  }

  con <- file(output_path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(audio_raw, con)

  list(
    path = normalizePath(output_path, winslash = "/", mustWork = TRUE),
    bytes = length(audio_raw),
    mime = detected_mime
  )
}

text <- arg_value(
  "--text",
  paste0(
    "Merhaba. Bu, Mergen Bilge için Vox CPM iki Türkçe ses sentezi testidir. ",
    "Ç, ğ, ı, İ, ö, ş ve ü karakterlerini doğru söylüyor muyum?"
  )
)
voice <- arg_value("--voice", "default")
model <- arg_value("--model", "VoxCPM2")
ref_audio_path <- arg_value("--ref-audio", "")
output_path <- arg_value("--output", "")
response_format <- arg_value("--response-format", "")
dry_run <- has_flag("--dry-run")
allow_no_api_key <- has_flag("--allow-no-api-key")

endpoint_base <- scalar_env("LOCAL_TTS_ENDPOINT")
speech_url <- build_speech_url(endpoint_base)
if (!nzchar(speech_url)) {
  stop("LOCAL_TTS_ENDPOINT tanımlı değil. .Renviron dosyasını kontrol edin.", call. = FALSE)
}

api_key <- resolve_api_key()
if (!nzchar(api_key$value) && !allow_no_api_key) {
  stop(
    paste0(
      "TTS API anahtarı bulunamadı. LOCAL_TTS_API_KEY, izinli MERGEN_DEFAULT_API_KEY ",
      "veya LOCAL_LLM_API_KEY değişkenlerinden birini tanımlayın. Anahtarsız servis ",
      "için --allow-no-api-key kullanın."
    ),
    call. = FALSE
  )
}

timeout_seconds <- suppressWarnings(as.numeric(scalar_env("LOCAL_TTS_TIMEOUT", "90")))
if (is.na(timeout_seconds) || timeout_seconds <= 0) timeout_seconds <- 90
verify_ssl <- as_bool(scalar_env("LOCAL_TTS_VERIFY_SSL", "TRUE"), default = TRUE)

body <- list(
  model = model,
  input = text,
  voice = voice
)

ref_audio_bytes <- 0
if (nzchar(ref_audio_path)) {
  ref_audio_path <- validate_wav(path.expand(ref_audio_path))
  ref_audio_bytes <- file.info(ref_audio_path)$size
  body$ref_audio <- wav_to_data_url(ref_audio_path)
}
if (nzchar(response_format)) {
  body$response_format <- response_format
}

default_output_dir <- if (nzchar(output_path)) {
  dirname(path.expand(output_path))
} else {
  file.path(resolve_desktop_dir(), "VoxCPM2_Test")
}

cat("== VoxCPM2 bağımsız TTS testi ==\n")
cat(sprintf("Repo kökü       : %s\n", repo_root))
cat(sprintf("Uç nokta        : %s\n", speech_url))
cat(sprintf("Model           : %s\n", model))
cat(sprintf("Ses             : %s\n", voice))
cat(sprintf("Metin uzunluğu  : %d karakter\n", nchar(text, type = "chars")))
cat(sprintf("API anahtarı    : %s (%d karakter; değer yazdırılmadı)\n", api_key$source, nchar(api_key$value)))
cat(sprintf("SSL doğrulama   : %s\n", if (verify_ssl) "açık" else "kapalı"))
cat(sprintf("Zaman aşımı     : %s saniye\n", timeout_seconds))
cat(sprintf("Referans ses    : %s\n", if (nzchar(ref_audio_path)) ref_audio_path else "yok (default ses testi)"))
cat(sprintf("Çıktı klasörü   : %s\n", default_output_dir))
if (ref_audio_bytes > 0) {
  cat(sprintf("Referans boyutu : %d bayt\n", ref_audio_bytes))
}
if (nzchar(response_format)) {
  cat(sprintf("Yanıt biçimi    : %s\n", response_format))
}

if (dry_run) {
  sanitized <- body
  if (!is.null(sanitized$ref_audio)) {
    sanitized$ref_audio <- sprintf("<data:audio/wav;base64,...> (%d karakter)", nchar(body$ref_audio))
  }
  cat("\nDry-run başarılı. Gönderilecek gövde (hassas içerik maskeli):\n")
  cat(jsonlite::toJSON(sanitized, auto_unbox = TRUE, pretty = TRUE), "\n")
  quit(status = 0L)
}

headers <- c(`Content-Type` = "application/json")
if (nzchar(api_key$value)) {
  headers[["Authorization"]] <- paste("Bearer", api_key$value)
}

request_config <- if (verify_ssl) {
  list()
} else {
  list(httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L))
}

cat("\nPOST isteği gönderiliyor...\n")
started_at <- Sys.time()
response <- tryCatch(
  do.call(
    httr::POST,
    c(
      list(
        url = speech_url,
        httr::add_headers(.headers = headers),
        body = body,
        encode = "json",
        httr::timeout(timeout_seconds)
      ),
      request_config
    )
  ),
  error = function(e) {
    stop(sprintf("TTS isteği gönderilemedi: %s", conditionMessage(e)), call. = FALSE)
  }
)
elapsed <- as.numeric(difftime(Sys.time(), started_at, units = "secs"))
status <- httr::status_code(response)
content_type <- httr::headers(response)[["content-type"]] %||% ""

cat(sprintf("HTTP durumu     : %d\n", status))
cat(sprintf("İçerik türü     : %s\n", if (nzchar(content_type)) content_type else "belirtilmedi"))
cat(sprintf("Geçen süre      : %.2f saniye\n", elapsed))

if (status < 200L || status >= 300L) {
  error_body <- tryCatch(
    httr::content(response, as = "text", encoding = "UTF-8"),
    error = function(e) "<yanıt gövdesi okunamadı>"
  )
  if (nchar(error_body) > 4000L) {
    error_body <- paste0(substr(error_body, 1L, 4000L), "...")
  }
  stop(sprintf("VoxCPM2 testi başarısız. Sunucu yanıtı:\n%s", error_body), call. = FALSE)
}

saved <- write_audio_response(response, output_path)
cat("\nTEST BAŞARILI\n")
cat(sprintf("Kaydedilen dosya: %s\n", saved$path))
cat(sprintf("Ses boyutu      : %d bayt\n", saved$bytes))
cat(sprintf("Algılanan tür   : %s\n", if (nzchar(saved$mime)) saved$mime else "belirtilmedi"))
cat("Dosyayı dinleyerek Türkçe telaffuzu ve varsa referans sese benzerliği doğrulayın.\n")
