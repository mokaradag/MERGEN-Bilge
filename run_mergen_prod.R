# ==============================================================================
# Dosya Yolu: run_mergen_prod.R
# Açıklama: MERGEN Bilge üretim başlatma betiği.
#
# Kullanım:
#   Rscript run_mergen_prod.R
#
# Not:
# - Üretimde app.R doğrudan seçilip Ctrl+Enter ile çalıştırılmamalıdır.
# - Bu dosya repo kökünü bulur, .Renviron dosyasını yükler, app.R'ı güvenli
#   biçimde source eder ve uygulamayı run_mergen_app() üzerinden başlatır.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Script / repo kökünü güvenli tespit et
# ------------------------------------------------------------------------------

resolve_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)

  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0L) {
    script_path <- sub("^--file=", "", file_arg[[1]])
    return(dirname(normalizePath(script_path, winslash = "/", mustWork = TRUE)))
  }

  frames <- sys.frames()
  ofiles <- vapply(
    frames,
    function(frame) {
      if (!is.null(frame$ofile)) {
        return(as.character(frame$ofile)[1])
      }
      NA_character_
    },
    character(1)
  )

  ofiles <- ofiles[!is.na(ofiles) & nzchar(ofiles)]

  if (length(ofiles) > 0L) {
    return(dirname(normalizePath(ofiles[[length(ofiles)]], winslash = "/", mustWork = TRUE)))
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

repo_root <- resolve_script_dir()

required_paths <- c(
  "app.R",
  "global.R",
  "ui.R",
  "server.R",
  "R",
  "www"
)

missing_paths <- required_paths[!file.exists(file.path(repo_root, required_paths))]

if (length(missing_paths) > 0L) {
  stop(
    sprintf(
      "MERGEN Bilge üretim başlatması durduruldu. Eksik dosya/klasör: %s\nRepo kökü: %s",
      paste(missing_paths, collapse = ", "),
      repo_root
    ),
    call. = FALSE
  )
}

setwd(repo_root)

# ------------------------------------------------------------------------------
# 2. Üretim ortamını sabitle
# ------------------------------------------------------------------------------

options(
  encoding = "UTF-8",
  shiny.autoreload = FALSE,
  future.rng.onMisuse = "ignore"
)

Sys.setenv(
  # Repo kökü runtime boyunca sabit kalsın; getwd() değişse bile artifact/www yolları doğru çözülür.
  MERGEN_REPO_ROOT = repo_root,

  # app.R source edilirken otomatik runApp tetiklenmesin.
  MERGEN_RUN_APP = "false",

  # Üretimde future/worker altyapısı açık kalsın.
  MERGEN_DISABLE_FUTURES = "false",

  # Log ve zaman davranışı tutarlı olsun.
  TZ = Sys.getenv("TZ", "Europe/Istanbul")
)

# Windows VM üzerinde Türkçe karakter davranışını iyileştirmek için en iyi çaba.
try(suppressWarnings(Sys.setlocale("LC_CTYPE", "Turkish_Turkey.UTF-8")), silent = TRUE)
try(suppressWarnings(Sys.setlocale("LC_COLLATE", "Turkish_Turkey.UTF-8")), silent = TRUE)

# ------------------------------------------------------------------------------
# 3. Repo .Renviron dosyasını çalışma dizini ayarlandıktan sonra elle yükle
# ------------------------------------------------------------------------------

renviron_path <- file.path(repo_root, ".Renviron")

if (file.exists(renviron_path)) {
  readRenviron(renviron_path)
} else {
  warning(
    sprintf(
      ".Renviron bulunamadı. Ortam değişkenlerinin sistem/user seviyesinde tanımlı olduğu varsayılıyor. Beklenen konum: %s",
      renviron_path
    ),
    call. = FALSE
  )
}

mergen_mojibake_variant <- function(value, source_encoding) {
  tryCatch(
    iconv(
      list(charToRaw(enc2utf8(value))),
      from = source_encoding,
      to = "UTF-8",
      sub = NA_character_
    )[[1]],
    error = function(e) NA_character_
  )
}

mergen_turkish_mojibake_map <- function() {
  encodings <- c("WINDOWS-1252", "latin1")
  turkish_chars <- intToUtf8(
    c(0x00C7, 0x00E7, 0x011E, 0x011F, 0x0130, 0x0131,
      0x00D6, 0x00F6, 0x015E, 0x015F, 0x00DC, 0x00FC),
    multiple = TRUE
  )
  replacements <- character(0)

  for (correct in turkish_chars) {
    level_one <- unique(vapply(
      encodings,
      function(enc) mergen_mojibake_variant(correct, enc),
      character(1)
    ))
    level_one <- level_one[!is.na(level_one) & nzchar(level_one) & level_one != correct]
    level_two <- unique(unlist(lapply(level_one, function(value) {
      vapply(
        encodings,
        function(enc) mergen_mojibake_variant(value, enc),
        character(1)
      )
    }), use.names = FALSE))

    variants <- unique(c(level_two, level_one))
    variants <- variants[!is.na(variants) & nzchar(variants) & variants != correct]
    for (variant in variants) {
      replacements[[variant]] <- correct
    }
  }

  replacements[order(nchar(names(replacements), type = "chars"), decreasing = TRUE)]
}

repair_mergen_log_dir <- function(path, repo_root) {
  if (is.null(path) || !length(path)) {
    return("")
  }

  path <- enc2utf8(trimws(as.character(path[[1]])))
  if (is.na(path) || !nzchar(path)) {
    return(path)
  }

  encoding_env <- new.env(parent = baseenv())
  sys.source(
    file.path(repo_root, "R", "utils_text_encoding.R"),
    envir = encoding_env
  )

  repaired <- encoding_env$repair_text_mojibake(path, max_passes = 2L)
  replacements <- mergen_turkish_mojibake_map()

  for (pass in seq_len(2L)) {
    previous <- repaired
    for (marker in names(replacements)) {
      repaired <- gsub(marker, replacements[[marker]], repaired, fixed = TRUE)
    }
    if (identical(repaired, previous)) {
      break
    }
  }

  has_residual <- any(vapply(
    names(replacements),
    function(marker) grepl(marker, repaired, fixed = TRUE),
    logical(1)
  ))
  if (isTRUE(has_residual)) {
    stop("MERGEN_LOG_DIR iki geçişte onarılamadı.", call. = FALSE)
  }

  repaired
}

local({
  configured_log_dir <- Sys.getenv("MERGEN_LOG_DIR", "")
  repaired_log_dir <- repair_mergen_log_dir(configured_log_dir, repo_root)

  if (!identical(repaired_log_dir, trimws(configured_log_dir))) {
    Sys.setenv(MERGEN_LOG_DIR = repaired_log_dir)
  }
})

# ------------------------------------------------------------------------------
# 4. Port/host ayarlarını normalize et
# ------------------------------------------------------------------------------

normalize_prod_port <- function(value, default = 8009L) {
  port <- suppressWarnings(as.integer(trimws(as.character(value[1]))))

  if (is.na(port) || port < 1L || port > 65535L) {
    return(as.integer(default))
  }

  as.integer(port)
}

prod_host <- Sys.getenv("MERGEN_HOST", "0.0.0.0")
prod_port <- normalize_prod_port(Sys.getenv("MERGEN_PORT", "8009"), default = 8009L)

# ------------------------------------------------------------------------------
# 5. Kritik ortam değişkenleri için erken, anlaşılır kontrol
# ------------------------------------------------------------------------------

required_env <- c(
  "DB_DSN",
  "LOCAL_LLM_ENDPOINT"
)

missing_env <- required_env[!nzchar(Sys.getenv(required_env, unset = ""))]

if (length(missing_env) > 0L) {
  stop(
    sprintf(
      "MERGEN Bilge üretim başlatması durduruldu. Eksik zorunlu ortam değişkenleri: %s",
      paste(missing_env, collapse = ", ")
    ),
    call. = FALSE
  )
}

# ------------------------------------------------------------------------------
# 6. app.R güvenli biçimde yüklenir; app.R otomatik çalışmaz
# ------------------------------------------------------------------------------

message("MERGEN Bilge üretim başlatması hazırlanıyor...")
message(sprintf("Repo kökü : %s", repo_root))
message(sprintf("Host      : %s", prod_host))
message(sprintf("Port      : %s", prod_port))
message(sprintf("TZ        : %s", Sys.getenv("TZ")))
message("app.R source ediliyor...")

source("app.R", encoding = "UTF-8", local = globalenv())

if (!exists("run_mergen_app", envir = globalenv(), mode = "function")) {
  stop(
    "Boot tamamlanamadı: run_mergen_app() bulunamadı. app.R beklenen üretim API'sini yüklememiş görünüyor.",
    call. = FALSE
  )
}

if (exists("validate_boot_state", envir = globalenv(), mode = "function")) {
  validate_boot_state()
}

# ------------------------------------------------------------------------------
# 7. Uygulamayı başlat
# ------------------------------------------------------------------------------

message("MERGEN Bilge üretim modunda başlatılıyor...")

run_mergen_app(
  host = prod_host,
  port = prod_port,
  launch.browser = FALSE,
  quiet = FALSE
)