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
  
  # Windows'ta özel karakter içeren yollar için kısa (8.3) formu tercih et
  normalized <- safe_windows_short_path(normalized, must_exist = FALSE)

  enc2utf8(normalized)
}

# --- HATAYI ÖNLEYİCİ: KÖK DİZİN TEKRARI TEMİZLİĞİ ---
# Yanlış yapılandırılmış temel dizinleri (örn. çalışma dizinini zaten
# içeren göreceli yollar) düzeltir.

# --- MCP YOL NORMALİZASYONU ---
# UNC, Windows ve Linux yollarını tutarlı biçime dönüştürür.
# Baştaki tekrar eden dizin parçalarını temizler.
normalize_mcp_path <- function(candidate, must_exist = FALSE) {
  if (is.null(candidate) || !nzchar(candidate)) return(candidate)

  # İç yardımcı: baştaki çift eğik çizgi çiftlerini temizle
  dedupe_leading_pair <- function(p) {
    if (!nzchar(p)) return(p)
    # "//server/share//server/share/..." gibi tekrarları algıla ve düzelt
    slashes <- sub("^(//)", "", p)
    parts <- strsplit(slashes, "/", fixed = TRUE)[[1]]
    if (length(parts) >= 4 && identical(parts[1:2], parts[3:4])) {
      return(paste0("//", paste(c(parts[1:2], parts[-(1:4)]), collapse = "/")))
    }
    p
  }

  candidate <- as.character(candidate)

  # Ters eğik çizgileri düzelt
  candidate <- gsub("\\\\", "/", candidate, fixed = TRUE)

  # UNC yolu kontrolü: /server/share biçimini //server/share'e çevir
  # NOT: Bu dönüşüm YALNIZCA Windows'ta yapılır. Linux'ta tek slash ile başlayan
  # yollar (ör: /opt/uygulamalar/...) normal yerel yollardır ve UNC'ye çevrilmemeli.
  # Linux'ta UNC paylaşımları mount noktası üzerinden erişilir (/mnt/paylasim gibi).
  if (.Platform$OS.type == "windows") {
    maybe_unc <- grepl("^/[^/]+/[^/]+", candidate)
    if (maybe_unc) {
      cleaned <- paste0("//", sub("^/+", "", candidate))
      cleaned <- dedupe_leading_pair(cleaned)
      return(enc2utf8(cleaned))
    }
  }

  normalize_utf8_path(candidate, mustWork = must_exist)
}

# --- MCP TEMEL DİZİN ÇÖZÜMLEYICI ---
# MCP_FILES_BASE ortam değişkenini okur, dizin yoksa oluşturur,
# başarısız olursa MERGEN_UPLOADS_DIR'e düşer.
# NOT: Bu fonksiyon MERGEN_UPLOADS_DIR global değişkenine bağımlıdır
#      ve config_file_store.R'de çağrılır.
resolve_mcp_base_dir <- function() {
  raw <- Sys.getenv("MCP_FILES_BASE", MERGEN_UPLOADS_DIR)
  base <- normalize_mcp_path(raw, must_exist = FALSE)

  created <- tryCatch({
    fs::dir_create(base, recurse = TRUE)
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(created) || !dir.exists(base)) {
    base <- MERGEN_UPLOADS_DIR
    tryCatch({
      fs::dir_create(base, recurse = TRUE)
    }, error = function(e) {
      # Son çare: base R ile oluştur
      dir.create(base, showWarnings = FALSE, recursive = TRUE)
    })
  }

  normalize_mcp_path(base, must_exist = dir.exists(base))
}