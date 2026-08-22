# ==============================================================================
# R/config_logging.R
# Loglama altyapısı: logger ayarları, hata yakalayıcı, debug çıktıları
# ve AI çağrılarını izleme fonksiyonları.
# global.R tarafından config_packages.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- LOG DİZİNİ OLUŞTURMA ---
resolve_mergen_log_dir <- function(default = "logs") {
  log_dir <- trimws(Sys.getenv("MERGEN_LOG_DIR", default))
  if (!nzchar(log_dir)) {
    log_dir <- default
  }
  normalizePath(log_dir, winslash = "/", mustWork = FALSE)
}

resolve_mergen_log_threshold <- function(default = logger::INFO) {
  level <- tolower(trimws(Sys.getenv("MERGEN_LOG_THRESHOLD", "info")))

  switch(
    level,
    trace   = logger::TRACE,
    debug   = logger::DEBUG,
    info    = logger::INFO,
    warn    = logger::WARN,
    warning = logger::WARN,
    error   = logger::ERROR,
    fatal   = logger::FATAL,
    default
  )
}

# Log dizininin gerçekten YAZILABİLİR olduğunu doğrular. Birincil dizin
# (ör. UNC paylaşımı) yoksa oluşturmayı dener, sonra geçici bir sonda dosyasıyla
# yazma iznini test eder. Bu, "dizin var ama yazılamıyor" durumunu da yakalar.
mergen_log_dir_is_writable <- function(dir_path) {
  if (is.null(dir_path) || !nzchar(dir_path)) {
    return(FALSE)
  }
  if (!dir.exists(dir_path)) {
    tryCatch(
      dir.create(dir_path, recursive = TRUE, showWarnings = FALSE),
      error = function(e) FALSE
    )
  }
  if (!dir.exists(dir_path)) {
    return(FALSE)
  }
  probe <- file.path(dir_path, sprintf(".mergen_log_write_test_%s", Sys.getpid()))
  ok <- tryCatch({
    cat("", file = probe, append = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (file.exists(probe)) {
    unlink(probe)
  }
  isTRUE(ok)
}

# İŞÇİ KİPİ LOG DİZİNİ DOĞRULAMASINDAN ÖNCE BELİRLENİR.
#
# Faz 6 (§5.10) PK future işçisi bu dosyayı KENDİ sürecinde source eder ve
# aşağıda görüldüğü gibi işçide DOSYA appender'ı hiç kurulmaz. Buna rağmen
# yazılabilirlik kapısı işçide de çalışıyordu: UNC günlük dizini işçiden
# erişilemediğinde `stop()` tetikleniyor ve PK analizi hiç başlamadan
# önyükleme başarısız oluyordu. İşçi yalnızca konsol appender'ı kullandığı için
# günlük dizinini OLUŞTURMAZ ve DOĞRULAMAZ.
mergen_logging_worker_mode <- isTRUE(tolower(trimws(
  Sys.getenv("MERGEN_PK_WORKER_BOOTSTRAP", unset = "")
)) %in% c("1", "true", "t", "yes", "on"))

mergen_log_dir <- resolve_mergen_log_dir()

# Birincil log dizinine yazılamıyorsa (ör. UNC paylaşımı erişilemez/izinsiz),
# uygulama loglarını SESSİZCE kaybetmek yerine repo kökündeki yerel "logs"
# dizinine düşülür ve durum konsola yüksek sesle bildirilir. Bu, Haziran
# regresyonundaki "konsol çalışıyor ama mergen_YYYYMMDD.log oluşmuyor"
# durumunun sessizce sürmesini engeller.
if (!isTRUE(mergen_logging_worker_mode) &&
    !mergen_log_dir_is_writable(mergen_log_dir)) {
  fallback_log_dir <- normalizePath(
    file.path(getwd(), "logs"),
    winslash = "/", mustWork = FALSE
  )
  message(sprintf(
    "[MERGEN LOGGING] Yapilandirilmis log dizinine yazilamiyor (%s). Yerel dizine dusuluyor: %s",
    mergen_log_dir, fallback_log_dir
  ))
  mergen_log_dir <- fallback_log_dir
}

if (!isTRUE(mergen_logging_worker_mode) &&
    !mergen_log_dir_is_writable(mergen_log_dir)) {
  stop(sprintf("Log dizini oluşturulamadı/yazılamıyor: %s", mergen_log_dir))
}

# --- LOGGER YAPILANDIRMASI ---
library(logger)
log_threshold(resolve_mergen_log_threshold())

# --- GÜNLÜK LOG DOSYASI YARDIMCILARI (ODAKLI DOSYA) ---
# Tarih/yol çözümleme, dosya appender'ı ve açılış-garanti yardımcıları
# R/config_logging_daily_file.R içindedir (maintainability fonksiyon-yoğunluk
# bölmesi). Üretimde kaynak manifesti o dosyayı config_logging.R'den ÖNCE
# yükler, bu yüzden aşağıdaki guard atlanır. İzole test/debug akışlarında
# (config_logging.R doğrudan bir ortama source() edilir) yardımcılar henüz
# tanımlı olmayabilir; bu durumda working-directory bağımsız adaylarla AYNI
# ortama (envir = environment()) yüklenir, böylece `mergen_log_dir` ile aynı
# çerçevede çözülürler.
if (!exists("mergen_daily_file_appender", mode = "function",
            envir = environment(), inherits = FALSE)) {
  # Bu dosyanın bulunduğu dizini working-directory BAĞIMSIZ tespit et: source()
  # çağrı yığınında bir frame'e 'ofile' (kaynak dosya yolu) bırakır. Böylece
  # kardeş config_logging_daily_file.R, getwd()/MERGEN_REPO_ROOT'a güvenmeden
  # bulunur. İzole test/debug akışlarında config_logging.R repo dışı bir çalışma
  # dizininden source() edilebildiği için bu en güvenilir adaydır.
  .mergen_log_self_dir <- NULL
  for (.mergen_log_fi in rev(seq_len(sys.nframe()))) {
    .mergen_log_frame <- sys.frame(.mergen_log_fi)
    if (!exists("ofile", envir = .mergen_log_frame, inherits = FALSE)) {
      next
    }
    .mergen_log_ofile <- get("ofile", envir = .mergen_log_frame, inherits = FALSE)
    if (is.character(.mergen_log_ofile) &&
        length(.mergen_log_ofile) == 1L && nzchar(.mergen_log_ofile)) {
      .mergen_log_self_dir <- dirname(
        normalizePath(.mergen_log_ofile, winslash = "/", mustWork = FALSE)
      )
      break
    }
  }

  .mergen_log_daily_candidates <- c(
    if (!is.null(.mergen_log_self_dir)) {
      file.path(.mergen_log_self_dir, "config_logging_daily_file.R")
    },
    file.path(getwd(), "R", "config_logging_daily_file.R"),
    file.path(getwd(), "config_logging_daily_file.R"),
    file.path(getwd(), "..", "..", "R", "config_logging_daily_file.R"),
    file.path(Sys.getenv("MERGEN_REPO_ROOT", "."), "R", "config_logging_daily_file.R"),
    file.path("R", "config_logging_daily_file.R")
  )
  for (.mergen_log_daily_path in .mergen_log_daily_candidates) {
    if (file.exists(.mergen_log_daily_path)) {
      source(.mergen_log_daily_path, encoding = "UTF-8", local = environment())
      break
    }
  }
  rm(list = intersect(
    c(".mergen_log_daily_candidates", ".mergen_log_daily_path",
      ".mergen_log_self_dir", ".mergen_log_fi", ".mergen_log_frame",
      ".mergen_log_ofile"),
    ls(all.names = TRUE)
  ))
}

# Geriye dönük uyumluluk: bazı testler/çağıranlar log_file_path değişkenini okur.
log_file_path <- current_mergen_log_file_path()

# Faz 6 (§5.10): PK future işçisi bu dosyayı KENDİ sürecinde source eder.
# Orada günlük dosya appender'ını kurmak ve açılış başlığını yazmak, her temiz
# PSOCK işçisinin PAYLAŞILAN günlük log dosyasına sahte bir "uygulama başladı"
# kaydı düşürmesi ve ana süreçle eşzamanlı append yapması demektir. Faz 6
# arızaları tam da güvenilir başlangıç/hata kronolojisi gerektirdiğinden bu
# kaynak-zamanı kurulum ANA SÜREÇLE SINIRLIDIR; konsol appender'ı işçide de
# çalışır, dolayısıyla `log_*()` çağrıları sessizleşmez.
# (`mergen_logging_worker_mode` dosyanın BAŞINDA, log dizini doğrulamasından
# ÖNCE çözülür.)

# Çoklu appender yapılandırması
# Dosya logu düz metin olmalı
#
# İŞÇİ KİPİ SADECE "KURMA" DEĞİL, "TEMİZLE" DEMEKTİR: sıcak (yeniden
# kullanılan) bir PSOCK işçisi ÖNCEKİ kod sürümüyle önyüklenmiş olabilir ve
# index 1'de HÂLÂ `mergen_daily_file_appender` taşıyabilir. Kurulumu yalnızca
# ATLAMAK o işçiyi düzeltmez; paylaşılan günlük dosyaya eşzamanlı append
# sürerdi. Bu yüzden işçide index 1 AÇIKÇA sessiz bir appender'a çekilir.
if (!isTRUE(mergen_logging_worker_mode)) {
  log_appender(mergen_daily_file_appender, index = 1)
  log_layout(layout_glue, index = 1)
} else {
  # Sessiz appender: satırları yutar. `logger` index 1'i kaldırmaya izin
  # vermediğinden (kaldırma indeksleri kaydırıp konsol appender'ını bozardı)
  # yerine no-op yazılır. Konsol appender'ı index 2'de kalır; `log_*()`
  # çağrıları işçide de görünür olmayı sürdürür.
  log_appender(function(lines) invisible(NULL), index = 1)
  log_layout(layout_glue, index = 1)
}

# --- AÇILIŞTA GÜNLÜK DOSYAYI GARANTİLE (THRESHOLD-BAĞIMSIZ) ---
# Açılış dosyasını HEMEN oluştur: mergen_ensure_daily_log_file() günün
# mergen_YYYYMMDD.log dosyasını DOĞRUDAN cat() ile (logger/threshold'dan
# bağımsız) oluşturup açılış başlığını yazar; böylece dosya her gün, her
# yeniden başlatmada var olur. Tanım R/config_logging_daily_file.R içindedir.
# İŞÇİ KİPİNDE atlanır: temiz her PSOCK işçisi aksi hâlde paylaşılan günlük
# dosyaya sahte bir açılış kaydı yazardı.
if (!isTRUE(mergen_logging_worker_mode)) mergen_ensure_daily_log_file()

# Konsol renkleri üretimde varsayılan kapalıdır.
# Windows servis/VM koşullarında ANSI escape dizilerinin loglara karışmasını önler.
use_console_colors <- tolower(trimws(Sys.getenv("MERGEN_LOG_CONSOLE_COLORS", "false"))) %in%
  c("1", "true", "t", "yes", "y", "on")

# Windows PowerShell/R console bazen UTF-8 Türkçe karakterleri native geniş string'e
# çeviremeyip "unable to translate ... to a wide string" uyarısı üretir.
# Dosya logu UTF-8 kalır; yalnızca konsol çıktısı native-safe hale getirilir.
mergen_console_appender <- function(lines) {
  lines <- as.character(lines %||% "")
  if (exists("normalize_text_for_log", mode = "function", inherits = TRUE)) {
    lines <- normalize_text_for_log(lines)
  } else {
    lines <- enc2utf8(lines)
  }

  native_lines <- iconv(lines, from = "UTF-8", to = "", sub = "byte")
  native_lines[is.na(native_lines)] <- "<log encoding conversion failed>"

  cat(paste0(native_lines, collapse = "\n"), "\n", sep = "")
}

log_appender(mergen_console_appender, index = 2)

if (isTRUE(use_console_colors)) {
  log_layout(layout_glue_colors, index = 2)
} else {
  log_layout(layout_glue, index = 2)
}

# --- GÜVENLİ LOG SARICILARI ---
# Tüm uygulama logları bu sarmalayıcılardan geçer.
# ÖNEMLİ:
# - logger içindeki { ... } glue ifadeleri ÇAĞIRAN ortamda çözülmelidir.
# - Bu nedenle do.call(..., envir = caller_env) ile orijinal çağıran çerçeve korunur.
# - Önce msg ve ... içindeki doğrudan karakter veriler redakte edilir; sonra logger'a verilir.
.sanitize_log_value <- function(x) {
  if (is.null(x)) return(x)

  if (is.character(x) &&
      exists("normalize_text_for_log", mode = "function", inherits = TRUE)) {
    x <- normalize_text_for_log(x)
  }

  if (!exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    return(x)
  }

  if (is.character(x)) {
    return(redact_sensitive_text(x))
  }

  x
}

.forward_log_call <- function(log_fun, msg, ..., .caller_env = parent.frame()) {
  clean_msg <- .sanitize_log_value(msg)
  clean_args <- lapply(list(...), .sanitize_log_value)

  do.call(
    what = log_fun,
    args = c(list(clean_msg), clean_args),
    envir = .caller_env
  )
}

log_info <- function(msg, ...) {
  .forward_log_call(logger::log_info, msg, ..., .caller_env = parent.frame())
}

log_warn <- function(msg, ...) {
  .forward_log_call(logger::log_warn, msg, ..., .caller_env = parent.frame())
}

log_error <- function(msg, ...) {
  .forward_log_call(logger::log_error, msg, ..., .caller_env = parent.frame())
}

log_debug <- function(msg, ...) {
  .forward_log_call(logger::log_debug, msg, ..., .caller_env = parent.frame())
}

log_info("Application starting up...")
# Çözülen log dosyası yolunu açıkça yaz: hem konsolda hem dosyada görünür, böylece
# logların hangi dizine yazıldığı (UNC/yerel) hiçbir zaman belirsiz kalmaz.
log_info("Gunluk log dosyasi (mergen_YYYYMMDD.log): {log_file_path}")

# --- GLOBAL HATA YAKALAYICI ---
# Süreç başına bir kez tanımlanır; argümansız çağrıları da tolere eder
shiny_error_handler <- function(e = NULL) {
  msg <- if (!is.null(e)) {
    if (inherits(e, "error")) conditionMessage(e) else as.character(e)
  } else {
    geterrmessage()
  }
  
  # Log dosyasına yaz
  log_error("[ERROR] {msg}")

  # Yapılandırılmış, sır-redakteli kayıt: yakalanmamış Shiny hataları olay
  # incelemesinde [RUNTIME_ERROR] satırı olarak aranabilir. Yardımcı yoksa veya
  # üretim başarısız olursa sessizce atlanır; bu global handler asla kırılmamalı.
  if (exists("mergen_build_runtime_error_record", mode = "function")) {
    structured_err <- tryCatch({
      rec <- mergen_build_runtime_error_record(
        if (!is.null(e)) e else msg,
        "shiny_uncaught"
      )
      as.character(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null"))
    }, error = function(err) NULL)

    if (!is.null(structured_err)) {
      log_error("[RUNTIME_ERROR] {structured_err}")
    }
  }
  
  # Debug modunda stack trace göster
  if (isTRUE(as.logical(Sys.getenv("MERGEN_DEBUG", "FALSE")))) {
    stack <- sys.calls()
    if (length(stack) > 0) {
      stack_str <- paste(sapply(stack, function(x) paste(deparse(x), collapse = " ")), collapse = " -> ")
      log_debug("[TRACE] {stack_str}")
    }
  }
}

options(shiny.error = shiny_error_handler)

# --- DEBUG DUMPER (logs/ai_debug_YYYYMMDD.log) ---
# Geriye dönük uyumluluk için değişken tanımlı kalır; gerçek yazım hedefi her
# çağrıda güncel tarihe göre yeniden çözülür (mergen log'u ile aynı günlük devir).
dbg_log_path <- file.path(
  mergen_log_dir,
  sprintf("ai_debug_%s.log", format(current_mergen_log_date(), "%Y%m%d"))
)

dbg_dump <- function(label, payload) {
  try({
    payload_json <- jsonlite::toJSON(
      payload,
      auto_unbox = TRUE,
      null = "null",
      pretty = TRUE
    )
    payload_json <- .sanitize_log_value(payload_json)
    label <- .sanitize_log_value(as.character(label))

    cat(
      sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), label),
      payload_json,
      "\n---\n",
      file = file.path(
        mergen_log_dir,
        sprintf("ai_debug_%s.log", format(current_mergen_log_date(), "%Y%m%d"))
      ),
      append = TRUE
    )
  }, silent = TRUE)
}

# --- AI ÇAĞRI LOGLAMA ---
log_ai_call <- function(user_id, model, duration, success, tokens = NA) {
  log_info("AI Call: user={user_id}, model={model}, duration={duration}s, success={success}, tokens={tokens}")
}

# --- BAĞLAMLI HATA LOGLAMA ---
log_error_with_context <- function(error, context = "unknown") {
  # Yapılandırılmış ve sır-redakteli kayıt üret (yardımcı yoksa NULL döner).
  record <- tryCatch(
    mergen_build_runtime_error_record(error, context),
    error = function(e) NULL
  )

  if (!is.null(record)) {
    # Redakte edilmiş bağlam/mesaj ile insan-okur log satırı.
    ctx <- record$context
    msg <- record$message
    log_error("Error in {ctx}: {msg}")

    # İzlenebilir tek satır yapılandırılmış kayıt; olay incelemesinde aranır.
    structured <- tryCatch(
      jsonlite::toJSON(record, auto_unbox = TRUE, null = "null"),
      error = function(e) NULL
    )
    if (!is.null(structured)) {
      structured_line <- as.character(structured)
      log_debug("[RUNTIME_ERROR] {structured_line}")
    }
  } else {
    # Geriye dönük güvenli yol: yardımcı kullanılamıyorsa eski davranışı koru,
    # ancak yine de mümkünse mesajı redakte et.
    error_msg <- if (inherits(error, "error")) error$message else as.character(error)
    if (exists("redact_sensitive_text", mode = "function")) {
      error_msg <- tryCatch(
        as.character(redact_sensitive_text(error_msg))[1],
        error = function(e) error_msg
      )
    }
    log_error("Error in {context}: {error_msg}")
  }

  # Stack trace al
  stack <- sys.calls()
  if (length(stack) > 0) {
    stack_str <- paste(sapply(stack, function(x) paste(deparse(x), collapse = " ")), collapse = " -> ")
    log_debug("Stack trace: {stack_str}")
  }
}

# --- KULLANICI AKSİYON LOGLAMA ---
log_user_action <- function(user_id, action, details = "") {
  log_info("User action: user={user_id}, action={action}, details={details}")
}