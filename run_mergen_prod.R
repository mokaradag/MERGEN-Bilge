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

resolve_prod_log_dir <- function(default = "logs") {
  log_dir <- trimws(Sys.getenv("MERGEN_LOG_DIR", default))
  if (!nzchar(log_dir)) {
    log_dir <- default
  }

  if (!grepl("^(?:[A-Za-z]:|/|//|\\\\\\\\)", log_dir)) {
    log_dir <- file.path(repo_root, log_dir)
  }

  normalizePath(log_dir, winslash = "/", mustWork = FALSE)
}

prod_log_file_path <- function() {
  file.path(
    resolve_prod_log_dir(),
    sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d"))
  )
}

write_prod_boot_log <- function(level = "INFO", message) {
  log_file <- prod_log_file_path()
  log_dir <- dirname(log_file)

  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  }

  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("%s [%s] [PROD_BOOT] %s", timestamp, level, enc2utf8(message))

  tryCatch(
    cat(line, "\n", file = log_file, append = TRUE, sep = "", useBytes = TRUE),
    error = function(e) {
      message(sprintf("[MERGEN PROD BOOT LOG ERROR] %s", conditionMessage(e)))
    }
  )

  invisible(log_file)
}

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
  write_prod_boot_log("INFO", sprintf(".Renviron yüklendi: %s", renviron_path))
} else {
  write_prod_boot_log("WARN", sprintf(".Renviron bulunamadı: %s", renviron_path))
  warning(
    sprintf(
      ".Renviron bulunamadı. Ortam değişkenlerinin sistem/user seviyesinde tanımlı olduğu varsayılıyor. Beklenen konum: %s",
      renviron_path
    ),
    call. = FALSE
  )
}

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

write_prod_boot_log("INFO", sprintf(
  "Üretim başlatma hazırlanıyor. repo_root=%s host=%s port=%s log_file=%s",
  repo_root,
  prod_host,
  prod_port,
  prod_log_file_path()
))

# ------------------------------------------------------------------------------
# 5. Kritik ortam değişkenleri için erken, anlaşılır kontrol
# ------------------------------------------------------------------------------

required_env <- c(
  "DB_DSN",
  "LOCAL_LLM_ENDPOINT"
)

missing_env <- required_env[!nzchar(Sys.getenv(required_env, unset = ""))]

if (length(missing_env) > 0L) {
  write_prod_boot_log(
    "ERROR",
    sprintf(
      "Üretim başlatması durduruldu. Eksik zorunlu ortam değişkenleri: %s",
      paste(missing_env, collapse = ", ")
    )
  )
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

tryCatch({
  write_prod_boot_log("INFO", "app.R source ediliyor...")
  source("app.R", encoding = "UTF-8", local = globalenv())
  write_prod_boot_log("INFO", "app.R source başarıyla tamamlandı.")

  if (!exists("run_mergen_app", envir = globalenv(), mode = "function")) {
    stop(
      "Boot tamamlanamadı: run_mergen_app() bulunamadı. app.R beklenen üretim API'sini yüklememiş görünüyor.",
      call. = FALSE
    )
  }

  if (exists("validate_boot_state", envir = globalenv(), mode = "function")) {
    write_prod_boot_log("INFO", "validate_boot_state() çalıştırılıyor...")
    validate_boot_state()
    write_prod_boot_log("INFO", "validate_boot_state() başarıyla tamamlandı.")
  }

# ------------------------------------------------------------------------------
# 7. Uygulamayı başlat
# ------------------------------------------------------------------------------

  message("MERGEN Bilge üretim modunda başlatılıyor...")
  write_prod_boot_log("INFO", "run_mergen_app() çağrılıyor...")

  run_mergen_app(
    host = prod_host,
    port = prod_port,
    launch.browser = FALSE,
    quiet = FALSE
  )
}, error = function(e) {
  write_prod_boot_log(
    "ERROR",
    sprintf("Üretim başlatması hata ile durdu: %s", conditionMessage(e))
  )
  stop(e)
})
