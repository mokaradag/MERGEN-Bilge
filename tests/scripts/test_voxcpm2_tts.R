#!/usr/bin/env Rscript

# Standalone VoxCPM2 TTS and voice-cloning test for MERGEN Bilge.
# The file is intentionally ASCII-only; Turkish default text is built with
# Unicode escapes so Windows Rscript cannot corrupt it while parsing the file.

options(warn = 1, encoding = "UTF-8")

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

has_flag <- function(name) name %in% args

show_help <- function() {
  cat(paste0(
    "VoxCPM2 standalone TTS test\n\n",
    "Usage:\n",
    "  Rscript tests/scripts/test_voxcpm2_tts.R [options]\n\n",
    "Options:\n",
    "  --text <text>              Target text.\n",
    "  --text-file <path>         Read target text from a UTF-8 file.\n",
    "  --ref-audio <wav>          Reference WAV for voice cloning.\n",
    "  --ref-text <text>          Exact transcript of reference audio.\n",
    "  --control <instruction>    Style instruction prepended in parentheses.\n",
    "  --slow                     Use a slow, calm, clearly articulated style.\n",
    "  --speed <0.25-4.0>         OpenAI speech speed value; default 1.0.\n",
    "  --voice <name>             Voice name; default 'default'.\n",
    "  --model <name>             Model name; default 'VoxCPM2'.\n",
    "  --response-format <fmt>    wav, mp3, flac, aac, opus, or pcm.\n",
    "  --output <path>            Output file. Defaults to Desktop/VoxCPM2_Test.\n",
    "  --dry-run                  Validate and print a masked request.\n",
    "  --allow-no-api-key         Allow a request without Authorization.\n",
    "  --help                     Show this help.\n\n",
    "Environment variables:\n",
    "  LOCAL_TTS_ENDPOINT, LOCAL_TTS_API_KEY, LOCAL_TTS_TIMEOUT,\n",
    "  LOCAL_TTS_VERIFY_SSL, MERGEN_ALLOW_DEFAULT_API_KEY,\n",
    "  MERGEN_REQUIRE_PERSONAL_API_KEY, MERGEN_DEFAULT_API_KEY,\n",
    "  LOCAL_LLM_API_KEY, VOXCPM2_TEST_OUTPUT_DIR\n"
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
    sprintf("Missing R packages: %s. Run renv::restore() first.", paste(missing_packages, collapse = ", ")),
    call. = FALSE
  )
}

find_repo_root <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) && dir.exists(file.path(candidate, "R"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }
  normalizePath(".", winslash = "/", mustWork = TRUE)
}

repo_root <- find_repo_root()
renviron_path <- file.path(repo_root, ".Renviron")
if (file.exists(renviron_path)) readRenviron(renviron_path)

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

build_speech_url <- function(base_url) {
  base_url <- sub("/+$", "", trimws(base_url))
  if (!nzchar(base_url)) return("")
  if (grepl("/audio/speech$", base_url, ignore.case = TRUE)) return(base_url)
  paste0(base_url, "/audio/speech")
}

resolve_api_key <- function() {
  service_key <- scalar_env("LOCAL_TTS_API_KEY")
  if (nzchar(service_key)) return(list(value = service_key, source = "LOCAL_TTS_API_KEY"))

  allow_default <- as_bool(scalar_env("MERGEN_ALLOW_DEFAULT_API_KEY", "FALSE"))
  require_personal <- as_bool(scalar_env("MERGEN_REQUIRE_PERSONAL_API_KEY", "FALSE"))
  default_key <- scalar_env("MERGEN_DEFAULT_API_KEY")
  if (allow_default && !require_personal && nzchar(default_key)) {
    return(list(value = default_key, source = "MERGEN_DEFAULT_API_KEY"))
  }

  legacy_key <- scalar_env("LOCAL_LLM_API_KEY")
  if (nzchar(legacy_key)) return(list(value = legacy_key, source = "LOCAL_LLM_API_KEY"))

  list(value = "", source = "none")
}

resolve_desktop_dir <- function() {
  override <- scalar_env("VOXCPM2_TEST_OUTPUT_DIR")
  if (nzchar(override)) {
    dir.create(path.expand(override), recursive = TRUE, showWarnings = FALSE)
    return(normalizePath(path.expand(override), winslash = "/", mustWork = TRUE))
  }

  known_desktop <- ""
  if (identical(.Platform$OS.type, "windows")) {
    known_desktop <- tryCatch({
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

  candidates <- c(
    known_desktop,
    file.path(scalar_env("OneDriveCommercial"), "Desktop"),
    file.path(scalar_env("OneDrive"), "Desktop"),
    file.path(scalar_env("USERPROFILE"), "Desktop"),
    file.path(path.expand("~"), "Desktop")
  )
  candidates <- unique(candidates[nzchar(candidates)])
  existing <- candidates[dir.exists(candidates)]
  if (length(existing) == 0L) {
    stop("Desktop directory could not be resolved. Use --output with an explicit path.", call. = FALSE)
  }
  normalizePath(existing[[1]], winslash = "/", mustWork = TRUE)
}

read_utf8_file <- function(path) {
  path <- path.expand(path)
  if (!file.exists(path) || dir.exists(path)) {
    stop(sprintf("UTF-8 text file not found: %s", path), call. = FALSE)
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  text <- paste(lines, collapse = " ")
  sub("^\\ufeff", "", text, perl = TRUE)
}

looks_like_mojibake <- function(text) {
  grepl("[\\u00c3\\u00c4\\u00c5\\u00e2]", text, perl = TRUE)
}

validate_wav <- function(path) {
  path <- path.expand(path)
  if (!file.exists(path) || dir.exists(path)) {
    stop(sprintf("Reference WAV not found: %s", path), call. = FALSE)
  }
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  header <- readBin(con, what = "raw", n = 12L)
  if (length(header) < 12L || rawToChar(header[1:4]) != "RIFF" || rawToChar(header[9:12]) != "WAVE") {
    stop("ref_audio must be a RIFF/WAVE file.", call. = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

wav_to_data_url <- function(path) {
  size <- file.info(path)$size
  if (is.na(size) || size <= 0) stop("Reference WAV is empty.", call. = FALSE)
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_audio <- readBin(con, what = "raw", n = size)
  paste0("data:audio/wav;base64,", base64enc::base64encode(raw_audio))
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
    "audio/opus" = "opus",
    "application/octet-stream" = "bin",
    "bin"
  )
}

strip_data_url <- function(value) {
  value <- as.character(value %||% "")[[1]]
  if (!startsWith(value, "data:")) return(list(mime = "", base64 = value))
  comma <- regexpr(",", value, fixed = TRUE)[[1]]
  if (comma < 1L) return(list(mime = "", base64 = value))
  meta <- substr(value, 6L, comma - 1L)
  list(
    mime = strsplit(meta, ";", fixed = TRUE)[[1]][1],
    base64 = substr(value, comma + 1L, nchar(value))
  )
}

save_audio_response <- function(response, output_path = "") {
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
          candidate <- as.character(parsed[[field]])[[1]]
          break
        }
      }
    }
    if (is.null(candidate) || !nzchar(candidate)) {
      stop("Successful JSON response did not contain audio/data/content.", call. = FALSE)
    }
    decoded <- strip_data_url(candidate)
    audio_raw <- base64enc::base64decode(decoded$base64)
    if (nzchar(decoded$mime)) detected_mime <- decoded$mime
  }

  if (length(audio_raw) == 0L) stop("TTS response contained no audio bytes.", call. = FALSE)

  if (!nzchar(output_path)) {
    output_dir <- file.path(resolve_desktop_dir(), "VoxCPM2_Test")
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    ext <- mime_extension(detected_mime)
    output_path <- file.path(
      output_dir,
      sprintf("voxcpm2_test_%s.%s", format(Sys.time(), "%Y%m%d_%H%M%S"), ext)
    )
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

default_text <- paste0(
  "Merhaba. Bu, Mergen Bilge i\u00e7in Vox CPM iki T\u00fcrk\u00e7e ses sentezi testidir. ",
  "\u00c7, \u011f, \u0131, \u0130, \u00f6, \u015f ve \u00fc karakterlerini do\u011fru s\u00f6yl\u00fcyor muyum?"
)

text_file <- arg_value("--text-file", "")
text <- if (nzchar(text_file)) read_utf8_file(text_file) else arg_value("--text", default_text)
control <- arg_value("--control", "")
if (has_flag("--slow") && !nzchar(control)) {
  control <- "slow, calm, natural pace, clear articulation, short pauses between sentences"
}
if (nzchar(control)) text <- paste0("(", control, ")", text)
if (!nzchar(trimws(text))) stop("Target text is empty.", call. = FALSE)
if (looks_like_mojibake(text)) {
  stop(
    paste0(
      "Target text appears to contain mojibake (corrupted UTF-8 text). ",
      "Use --text-file with a UTF-8 file, or run Rscript with --encoding=UTF-8."
    ),
    call. = FALSE
  )
}

voice <- arg_value("--voice", "default")
model <- arg_value("--model", "VoxCPM2")
ref_audio_path <- arg_value("--ref-audio", "")
ref_text <- arg_value("--ref-text", "")
output_path <- arg_value("--output", "")
response_format <- arg_value("--response-format", "wav")
dry_run <- has_flag("--dry-run")
allow_no_api_key <- has_flag("--allow-no-api-key")

speed <- suppressWarnings(as.numeric(arg_value("--speed", "1.0")))
if (is.na(speed) || speed < 0.25 || speed > 4.0) {
  stop("--speed must be a number from 0.25 to 4.0.", call. = FALSE)
}

endpoint <- build_speech_url(scalar_env("LOCAL_TTS_ENDPOINT"))
if (!nzchar(endpoint)) stop("LOCAL_TTS_ENDPOINT is not configured.", call. = FALSE)

api_key <- resolve_api_key()
if (!nzchar(api_key$value) && !allow_no_api_key) {
  stop(
    "No TTS API key was found. Configure LOCAL_TTS_API_KEY or an allowed fallback key.",
    call. = FALSE
  )
}

timeout_seconds <- suppressWarnings(as.numeric(scalar_env("LOCAL_TTS_TIMEOUT", "90")))
if (is.na(timeout_seconds) || timeout_seconds <= 0) timeout_seconds <- 90
verify_ssl <- as_bool(scalar_env("LOCAL_TTS_VERIFY_SSL", "TRUE"), default = TRUE)

body <- list(
  model = model,
  input = text,
  voice = voice,
  response_format = response_format,
  speed = speed
)

ref_audio_bytes <- 0
if (nzchar(ref_audio_path)) {
  ref_audio_path <- validate_wav(ref_audio_path)
  ref_audio_bytes <- file.info(ref_audio_path)$size
  body$ref_audio <- wav_to_data_url(ref_audio_path)
}
if (nzchar(ref_text)) {
  if (!nzchar(ref_audio_path)) stop("--ref-text requires --ref-audio.", call. = FALSE)
  if (looks_like_mojibake(ref_text)) stop("Reference transcript contains mojibake.", call. = FALSE)
  body$ref_text <- ref_text
}

output_dir_display <- if (nzchar(output_path)) dirname(path.expand(output_path)) else file.path(resolve_desktop_dir(), "VoxCPM2_Test")

cat("== VoxCPM2 standalone TTS test ==\n")
cat(sprintf("Repository       : %s\n", repo_root))
cat(sprintf("Endpoint         : %s\n", endpoint))
cat(sprintf("Model            : %s\n", model))
cat(sprintf("Voice            : %s\n", voice))
cat(sprintf("Text characters  : %d\n", nchar(text, type = "chars")))
cat(sprintf("Speed            : %.2f\n", speed))
cat(sprintf("API key source   : %s (%d characters; value hidden)\n", api_key$source, nchar(api_key$value)))
cat(sprintf("SSL verification : %s\n", if (verify_ssl) "on" else "off"))
cat(sprintf("Timeout          : %s seconds\n", timeout_seconds))
cat(sprintf("Reference audio  : %s\n", if (nzchar(ref_audio_path)) ref_audio_path else "none"))
cat(sprintf("Reference text   : %s\n", if (nzchar(ref_text)) "provided" else "none"))
cat(sprintf("Output directory : %s\n", output_dir_display))
if (ref_audio_bytes > 0) cat(sprintf("Reference bytes  : %d\n", ref_audio_bytes))

if (dry_run) {
  masked <- body
  if (!is.null(masked$ref_audio)) {
    masked$ref_audio <- sprintf("<data:audio/wav;base64,...> (%d characters)", nchar(body$ref_audio))
  }
  cat("\nDry run succeeded. Masked request body:\n")
  cat(jsonlite::toJSON(masked, auto_unbox = TRUE, pretty = TRUE), "\n")
  quit(status = 0L)
}

headers <- c(`Content-Type` = "application/json")
if (nzchar(api_key$value)) headers[["Authorization"]] <- paste("Bearer", api_key$value)
request_config <- if (verify_ssl) list() else list(httr::config(ssl_verifypeer = 0L, ssl_verifyhost = 0L))

cat("\nSending POST request...\n")
started_at <- Sys.time()
response <- tryCatch(
  do.call(
    httr::POST,
    c(
      list(
        url = endpoint,
        httr::add_headers(.headers = headers),
        body = body,
        encode = "json",
        httr::timeout(timeout_seconds)
      ),
      request_config
    )
  ),
  error = function(e) stop(sprintf("TTS request failed: %s", conditionMessage(e)), call. = FALSE)
)

elapsed <- as.numeric(difftime(Sys.time(), started_at, units = "secs"))
status <- httr::status_code(response)
content_type <- httr::headers(response)[["content-type"]] %||% ""
cat(sprintf("HTTP status      : %d\n", status))
cat(sprintf("Content-Type     : %s\n", if (nzchar(content_type)) content_type else "not provided"))
cat(sprintf("Elapsed          : %.2f seconds\n", elapsed))

if (status < 200L || status >= 300L) {
  error_body <- tryCatch(
    httr::content(response, as = "text", encoding = "UTF-8"),
    error = function(e) "<response body could not be read>"
  )
  if (nchar(error_body) > 4000L) error_body <- paste0(substr(error_body, 1L, 4000L), "...")
  stop(sprintf("VoxCPM2 test failed. Server response:\n%s", error_body), call. = FALSE)
}

saved <- save_audio_response(response, output_path)
cat("\nTEST SUCCEEDED\n")
cat(sprintf("Saved file       : %s\n", saved$path))
cat(sprintf("Audio bytes      : %d\n", saved$bytes))
cat(sprintf("Detected type    : %s\n", if (nzchar(saved$mime)) saved$mime else "not provided"))
cat("Listen to the file and compare pace, Turkish pronunciation, and speaker similarity.\n")
