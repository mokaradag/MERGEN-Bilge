# ==============================================================================
# R/config_file_store.R
# Dosya deposu altyapısı: kalıcı yükleme dizinleri, indeks okuma/yazma,
# ortam değişkeni doğrulama, bellek yönetimi ve çöp toplama zamanlayıcısı.
# Dosya kayıt/çözümleme sorumlulukları config_file_store_index_mutation.R
# ve config_file_store_registry.R dosyalarına ayrılmıştır.
# global.R tarafından utils_path_helpers.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- ORTAM DEĞİŞKENLERİ AES-GCM VE OPSİYONEL VİZ KÜTÜPHANELERİ ---
# Ortamda AES-GCM var mı? Eski openssl sürümlerinde bu fonksiyon yoktur.
HAVE_AES_GCM <- isTRUE("aes_gcm_encrypt" %in% getNamespaceExports("openssl"))

# Opsiyonel görselleştirme kütüphaneleri (yoksa hata verme)
have_highcharter <- requireNamespace("highcharter", quietly = TRUE)
have_plotly_gg   <- (requireNamespace("plotly", quietly = TRUE) &&
                     requireNamespace("ggplot2", quietly = TRUE))

# ==============================================================================
# PAYLAŞIMLI DOSYA DEPOSU (ana süreç + worker'lar için ortak)
# ==============================================================================
env_or_default_path <- function(env_name, default_path) {
  env_value <- Sys.getenv(env_name, "")
  chosen <- if (nzchar(env_value)) env_value else default_path
  normalize_utf8_path(chosen, mustWork = FALSE)
}

MERGEN_FILES_ROOT <- env_or_default_path(
  "MERGEN_FILES_ROOT",
  tools::R_user_dir("mergen", which = "data")
)
dir.create(MERGEN_FILES_ROOT, showWarnings = FALSE, recursive = TRUE)
MERGEN_FILES_ROOT <- normalize_utf8_path(
  MERGEN_FILES_ROOT,
  mustWork = dir.exists(MERGEN_FILES_ROOT)
)

# Kalıcı yüklemeler dizini: ./mergen_uploads
MERGEN_UPLOADS_DIR <- env_or_default_path(
  "MERGEN_UPLOADS_DIR",
  file.path(getwd(), "mergen_uploads")
)
dir.create(MERGEN_UPLOADS_DIR, showWarnings = FALSE, recursive = TRUE)
MERGEN_UPLOADS_DIR <- normalize_utf8_path(
  MERGEN_UPLOADS_DIR,
  mustWork = dir.exists(MERGEN_UPLOADS_DIR)
)

# MCP tabanlı kalıcı yüklemeler için temel dizin
MERGEN_MCP_BASE_DIR <- resolve_mcp_base_dir()

# Kayıt defteri (indeks) dosya yolu; kullanıcı bazlı kovalar destekler
MERGEN_INDEX_PATH <- env_or_default_path(
  "MERGEN_INDEX_PATH",
  file.path(MERGEN_FILES_ROOT, "index.json")
)

# --- İNDEKS YARDIMCILARI (ana süreç ve worker'lar tarafından kullanılır) ---

# JSON'dan okunan dizeleri UTF-8 olarak İŞARETLEYEN özyinelemeli yardımcı.
# ÖNEMLİ: enc2utf8() yerine Encoding()<-"UTF-8" kullanılır.
# JSON zaten UTF-8'dir; enc2utf8() baytları yeniden dönüştürerek çift kodlamaya neden olur,
# Encoding()<-"UTF-8" ise mevcut baytları olduğu gibi koruyup sadece işaretler.
.mark_utf8 <- function(x) {
  if (exists("mark_text_tree_utf8", mode = "function", inherits = TRUE)) {
    return(mark_text_tree_utf8(x))
  }

  if (is.character(x)) { Encoding(x) <- "UTF-8"; return(x) }
  if (is.list(x)) return(lapply(x, .mark_utf8))
  x
}

# Kaydetmeden önce native encoding dizeleri UTF-8'e çeviren yardımcı
.convert_to_utf8 <- function(x) {
  if (exists("normalize_text_tree_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_tree_utf8(x, repair_mojibake = FALSE))
  }

  if (is.character(x)) return(enc2utf8(x))
  if (is.list(x)) return(lapply(x, .convert_to_utf8))
  x
}

.save_index <- function(idx) {
  idx <- .convert_to_utf8(idx)

  # Atomik yazım ortak utils_atomic_write.R yardımcısı üzerinden yapılır.
  # Bu sayede aynı pattern başka dosyalarda kopyalanmaz ve Windows VM üzerinde
  # file.rename fallback davranışı tek yerde evrimleşir.
  atomic_write_json(idx, MERGEN_INDEX_PATH, pretty = TRUE, auto_unbox = TRUE)
  invisible(TRUE)
}

.load_index <- function() {
  if (!file.exists(MERGEN_INDEX_PATH)) {
    return(list())
  }

  json_txt <- tryCatch(
    paste(
      readLines(
        MERGEN_INDEX_PATH,
        warn = FALSE,
        encoding = "UTF-8",
        skipNul = TRUE
      ),
      collapse = "\n"
    ),
    error = function(e) NA_character_
  )

  if (is.na(json_txt)) {
    log_warn("[INDEX] İndeks dosyası UTF-8 olarak okunamadı; boş listeye düşülüyor.")
    return(list())
  }

  json_txt_trim <- tryCatch(
    trimws(json_txt),
    error = function(e) ""
  )

  if (!nzchar(json_txt_trim)) {
    log_warn("[INDEX] İndeks dosyası boş veya okunamadı; boş listeye düşülüyor.")
    return(list())
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(json_txt_trim, simplifyVector = TRUE),
    error = function(e) e
  )

  if (inherits(parsed, "error")) {
    backup_path <- paste0(
      MERGEN_INDEX_PATH,
      ".corrupt_",
      format(Sys.time(), "%Y%m%d%H%M%S")
    )
    try(file.copy(MERGEN_INDEX_PATH, backup_path, overwrite = TRUE), silent = TRUE)
    log_error("[INDEX] İndeks JSON bozuk; yedek alındı ve boş listeye düşüldü.")
    return(list())
  }

  .mark_utf8(parsed)
}

# ==============================================================================
# DOSYA KAYIT / ÇÖZÜMLEME FONKSİYONLARI
# ==============================================================================
# Bu sorumluluklar R/config_file_store_index_mutation.R ve
# R/config_file_store_registry.R dosyalarına ayrılmıştır.
# global.R kaynak sırası bu dosyaları config_file_store.R hemen sonrasında yükler.

# Kullanıcının tüm dosyalarını ve indeks kovasını temizler
mergen_clear_user_bucket <- function(user_id) {
  uid <- as.character(user_id)
  user_folder_name <- sprintf("user_%s", uid)

  # Olası tüm dizin adaylarını topla (UNC, yerel, MCP)
  candidate_dirs <- unique(c(
    tryCatch(mergen_user_upload_dir(user_id), error = function(e) NULL),
    file.path(MERGEN_UPLOADS_DIR, user_folder_name),
    file.path(MERGEN_MCP_BASE_DIR, user_folder_name)
  ))
  candidate_dirs <- candidate_dirs[!vapply(candidate_dirs, is.null, logical(1))]

  # Her aday dizinde fiziksel dosyaları sil
  for (dir in candidate_dirs) {
    dir_ok <- tryCatch(dir.exists(dir), error = function(e) FALSE)
    if (!dir_ok) {
      # path_exists_relaxed ile de dene (UNC yolları için)
      dir_ok <- tryCatch(path_exists_relaxed(dir), error = function(e) FALSE)
    }
    if (isTRUE(dir_ok)) {
      files <- tryCatch(
        list.files(dir, full.names = TRUE, recursive = FALSE, include.dirs = FALSE),
        error = function(e) character(0)
      )
      for (f in files) try(unlink(f, force = TRUE), silent = TRUE)
    }
  }

  # İndeks kovasını temizle
  idx <- .load_index()
  if (!is.null(idx[[uid]])) {
    idx[[uid]] <- NULL
    .save_index(idx)
  }
  invisible(TRUE)
}

# ==============================================================================
# GLOBAL SEÇENEKLERİN AYARLANMASI
# ==============================================================================
# Bu değişkenleri yardımcı modüllere de erişilebilir kıl
options(mergen.files_root   = MERGEN_FILES_ROOT,
        mergen.index_path   = MERGEN_INDEX_PATH,
        mergen.mcp_base_dir = MERGEN_MCP_BASE_DIR)

# Bellek yönetimi ayarları
# Upload sınırı global.R tarafından merkezi olarak belirlenir.
upload_max_mb <- getOption("mergen.upload_max_mb", 25L)

options(
  shiny.maxRequestSize = upload_max_mb * 1024^2,
  future.globals.maxSize = 200 * 1024^2
)

# --- ÇÖP TOPLAMA ZAMANLAYICISI (hata korumalı) ---
gc_scheduler <- function() {
  tryCatch({
    gc(verbose = FALSE)
    later::later(gc_scheduler, delay = 300)
  }, error = function(e) {
    later::later(gc_scheduler, delay = 600)
  })
}

start_gc_scheduler_once <- function() {
  flag_name <- ".mergen_gc_scheduler_started"

  already_started <- isTRUE(
    get0(flag_name, envir = .GlobalEnv, inherits = FALSE, ifnotfound = FALSE)
  )

  if (already_started) {
    return(invisible(FALSE))
  }

  assign(flag_name, TRUE, envir = .GlobalEnv)
  gc_scheduler()
  invisible(TRUE)
}

# Test/bootstrap modunda later::later tabanlı arka plan döngüsü açılmaz.
if (isTRUE(as.logical(Sys.getenv("MERGEN_DISABLE_FUTURES", "false")))) {
  message("MERGEN_DISABLE_FUTURES aktif - gc scheduler atlandı (test/bootstrap modu).")
} else {
  start_gc_scheduler_once()
}

# Veritabanı bağlantı havuzu (server.R'de başlatılır)
pool <- NULL

# ==============================================================================
# ZORUNLU ORTAM DEĞİŞKENLERİ DOĞRULAMASI
# ==============================================================================
required_env_vars <- c("LOCAL_LLM_ENDPOINT", "DB_DSN", "AI_KEYS_MASTER")
missing_vars <- required_env_vars[sapply(required_env_vars, function(v) !nzchar(Sys.getenv(v)))]

if (length(missing_vars) > 0) {
  stop(sprintf(
    "Eksik zorunlu ortam değişkenleri: %s\n\n.Renviron dosyasında yapılandırın:\n%s",
    paste(missing_vars, collapse = ", "),
    paste(sprintf("%s=deger_buraya", missing_vars), collapse = "\n")
  ))
}

message("\u2713 Tüm zorunlu ortam değişkenleri yapılandırılmış")