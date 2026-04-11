# ==============================================================================
# R/utils_path_helpers.R
# Dosya yolu normalizasyon ve düzeltme yardımcı fonksiyonları.
# Windows kısa yol (8.3), UTF-8 uyumu, UNC yolları ve MCP yolları için
# standart dönüşüm fonksiyonlarını içerir.
# global.R tarafından config_packages.R ve config_logging.R'den sonra,
# config_file_store.R'den ÖNCE source() ile çağrılır.
# ==============================================================================

# --- GÜVENLİ YEDEK DİZİN (resolve_mcp_base_dir için gerekli) ---
# Bu değişken config_file_store.R'de yeniden tanımlanır; burada yalnızca
# resolve_mcp_base_dir() çağrısında MERGEN_UPLOADS_DIR henüz tanımlı
# değilse erken bir yedek sağlar.
if (!exists("MERGEN_UPLOADS_DIR")) {
  MERGEN_UPLOADS_DIR <- file.path(getwd(), "mergen_uploads")
}

# --- WINDOWS KISA YOL (8.3) DÖNÜŞTÜRÜCÜ ---
# Unicode karakterli yolları Windows'un kısa (8.3) formatına çevirir.
safe_windows_short_path <- function(path, must_exist = FALSE) {
  if (.Platform$OS.type != "windows") {
    return(path)
  }

  if (is.null(path) || length(path) == 0) {
    return(path)
  }

  candidate <- as.character(path[1])
  if (is.na(candidate) || !nzchar(candidate)) {
    return(candidate)
  }

  candidate_fs <- gsub("/", "\\\\", candidate, fixed = TRUE)
  if (isTRUE(must_exist) && !file.exists(candidate_fs)) {
    return(candidate)
  }

  short_raw <- tryCatch(utils::shortPathName(candidate_fs), error = function(e) candidate_fs)
  if (!nzchar(short_raw)) {
    short_raw <- candidate_fs
  }

  gsub("\\\\", "/", short_raw, fixed = TRUE)
}

# --- UTF-8 YOL NORMALİZASYONU ---
# Yol dizelerini UTF-8 uyumlu hâle getirir; ayırıcıları standartlaştırır.
normalize_utf8_path <- function(path, mustWork = FALSE) {
  if (is.null(path) || length(path) == 0) {
    return(path)
  }

  candidate <- as.character(path[1])
  if (is.na(candidate) || !nzchar(candidate)) {
    return(candidate)
  }

  normalized <- tryCatch(
    normalizePath(candidate, winslash = "/", mustWork = mustWork),
    error = function(e) candidate
  )

  normalized <- gsub("\\\\", "/", normalized, fixed = TRUE)

  exists_now <- tryCatch(
    isTRUE(file.exists(normalized)) ||
      isTRUE(dir.exists(normalized)) ||
      isTRUE(fs::file_exists(normalized)) ||
      isTRUE(fs::dir_exists(normalized)),
    error = function(e) FALSE
  )

  safe_windows_short_path(normalized, must_exist = exists_now)
}

# --- HATAYI ÖNLEYİCİ: KÖK DİZİN TEKRARI TEMİZLİĞİ ---
# Yanlış yapılandırılmış temel dizinleri (örn. çalışma dizinini zaten
# içeren göreceli yollar) düzeltir.

# --- MCP YOL NORMALİZASYONU ---
# UNC, Windows ve Linux yollarını tutarlı biçime dönüştürür.
# Baştaki tekrar eden dizin parçalarını temizler.
# ÖNEMLİ: UNC dalında regex (grepl/sub) kullanılmaz; çünkü R'nin regex
# motoru Windows'ta encoding dönüşümü tetikleyerek Türkçe karakterleri
# bozabilir (ör. "Geliştirme" → "GeliÅŸtirme"). Bunun yerine yalnızca
# substr/substring ve fixed=TRUE işlemleri kullanılır.
normalize_mcp_path <- function(candidate, must_exist = FALSE) {
  if (is.null(candidate) || !nzchar(candidate)) return(candidate)

  # Baştaki tekrarlanan dizin çiftlerini temizle (encoding güvenli)
  dedupe_leading_pair <- function(p) {
    if (!nzchar(p)) return(p)
    # Baştaki // kısmını atla (substring encoding korur, regex kullanmaz)
    govde <- substring(p, 3)
    parts <- strsplit(govde, "/", fixed = TRUE)[[1]]
    if (length(parts) >= 4 && identical(parts[1:2], parts[3:4])) {
      return(paste0("//", paste(c(parts[1:2], parts[-(1:4)]), collapse = "/")))
    }
    p
  }

  candidate <- as.character(candidate)
  # Ters eğik çizgileri düz eğik çizgiye dönüştür (byte düzeyinde, encoding güvenli)
  candidate <- gsub("\\\\", "/", candidate, fixed = TRUE)

  # UNC yol tespiti: regex yerine substr() kullanılır (encoding bozulması engellenir)
  n <- nchar(candidate)
  maybe_unc <- FALSE
  if (n >= 4L) {
    c1 <- substr(candidate, 1, 1)
    c2 <- substr(candidate, 2, 2)
    c3 <- substr(candidate, 3, 3)
    if (c1 == "/" && c2 == "/" && c3 != "/") {
      # //sunucu/paylasim formatı
      maybe_unc <- grepl("/", substring(candidate, 3), fixed = TRUE)
    } else if (c1 == "/" && c2 != "/") {
      # /sunucu/paylasim formatı (tek eğik çizgiyle başlayan UNC benzeri)
      maybe_unc <- grepl("/", substring(candidate, 2), fixed = TRUE)
    }
  }

  if (maybe_unc) {
    # Baştaki eğik çizgileri atla, sonra // ekle (encoding güvenli, regex yok)
    pos <- 1L
    while (pos <= n && substr(candidate, pos, pos) == "/") {
      pos <- pos + 1L
    }
    cleaned <- paste0("//", substring(candidate, pos))
    cleaned <- dedupe_leading_pair(cleaned)
    return(cleaned)
  }

  normalize_utf8_path(candidate, mustWork = must_exist)
}

# --- MCP TEMEL DİZİN ÇÖZÜMLEYICI ---
# MCP_FILES_BASE ortam değişkenini okur, dizin yoksa oluşturur,
# başarısız olursa MERGEN_UPLOADS_DIR'e düşer.
# NOT: Bu fonksiyon MERGEN_UPLOADS_DIR global değişkenine bağımlıdır
#      ve config_file_store.R'de çağrılır.
# ÖNEMLİ: MERGEN_UPLOADS_DIR kullanılırken normalize_mcp_path() çağrılmaz.
# Windows UNC yollarında normalizasyon Türkçe karakterleri bozar.
# Eklenti sistemiyle aynı yaklaşım: getwd() tabanlı yolu olduğu gibi kullan.
resolve_mcp_base_dir <- function() {
  raw <- Sys.getenv("MCP_FILES_BASE", "")

  # MCP_FILES_BASE ayarlanmadığında MERGEN_UPLOADS_DIR'i olduğu gibi kullan
  if (!nzchar(raw)) {
    base <- MERGEN_UPLOADS_DIR
    tryCatch(
      fs::dir_create(base, recurse = TRUE),
      error = function(e) dir.create(base, showWarnings = FALSE, recursive = TRUE)
    )
    return(base)
  }

  # MCP_FILES_BASE ayarlanmışsa normalize et (harici yol)
  base <- normalize_mcp_path(raw, must_exist = FALSE)

  created <- tryCatch({
    fs::dir_create(base, recurse = TRUE)
    TRUE
  }, error = function(e) FALSE)

  base_exists <- tryCatch(
    isTRUE(dir.exists(base)) || isTRUE(fs::dir_exists(base)),
    error = function(e) FALSE
  )

  if (!isTRUE(created) || !isTRUE(base_exists)) {
    base <- MERGEN_UPLOADS_DIR
    tryCatch(
      fs::dir_create(base, recurse = TRUE),
      error = function(e) dir.create(base, showWarnings = FALSE, recursive = TRUE)
    )
  }

  base
}
