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

  # Baytları yerel kodlamadan UTF-8'e dönüştür.
  # enc2utf8() yalnızca encoding etiketini değiştirir, baytları dönüştürmez.
  # Sunucu yerel ayarı ISO-8859-9 (Türkçe) ise 0xFE gibi baytlar geçersiz

  # UTF-8 olarak işaretlenir ve addResourcePath gibi C seviyesi fonksiyonlar
  # "invalid multibyte string" hatası verir. iconv(from="") yerel kodlamayı
  # otomatik algılar ve baytları gerçekten UTF-8'e çevirir.
  converted <- tryCatch({
    result <- iconv(normalized, from = "", to = "UTF-8")
    if (is.na(result)) enc2utf8(normalized) else result
  }, error = function(e) {
    tryCatch(enc2utf8(normalized), error = function(e2) normalized)
  })
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

  # İç yardımcı: mutlak yollarda baştaki tekrar eden segmentleri temizle.
  # Örn: /main/uygulamalar/main/uygulamalar/... -> /main/uygulamalar/...
  dedupe_repeated_root_segments <- function(p) {
    if (!nzchar(p) || !startsWith(p, "/")) return(p)

    parts <- strsplit(sub("^/+", "", p), "/", fixed = TRUE)[[1]]
    n <- length(parts)
    if (n < 4) return(p)

    max_k <- floor(n / 2)
    for (k in seq(max_k, 1)) {
      if (all(parts[seq_len(k)] == parts[(k + 1):(2 * k)])) {
        deduped <- c(parts[seq_len(k)], parts[-seq_len(2 * k)])
        return(paste0("/", paste(deduped, collapse = "/")))
      }
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

  normalized <- normalize_utf8_path(candidate, mustWork = must_exist)
  dedupe_repeated_root_segments(normalized)
}

# --- MCP TEMEL DİZİN ÇÖZÜMLEYICI ---
# MCP_FILES_BASE ortam değişkenini okur, dizin yoksa oluşturur,
# başarısız olursa MERGEN_UPLOADS_DIR'e düşer.
# NOT: Bu fonksiyon MERGEN_UPLOADS_DIR global değişkenine bağımlıdır
#      ve config_file_store.R'de çağrılır.
resolve_mcp_base_dir <- function() {
  sanitize_mcp_base_raw <- function(raw_path) {
    raw_chr <- if (is.null(raw_path) || !length(raw_path)) "" else as.character(raw_path[1])
    if (!nzchar(raw_chr)) return(raw_chr)

    raw_chr <- gsub("\\\\", "/", raw_chr, fixed = TRUE)
    is_abs <- startsWith(raw_chr, "/") || grepl("^[A-Za-z]:/", raw_chr)
    if (is_abs) return(raw_chr)

    cwd <- tryCatch(getwd(), error = function(e) "")
    cwd <- gsub("\\\\", "/", cwd, fixed = TRUE)
    cwd <- sub("/+$", "", cwd)
    if (!nzchar(cwd)) return(raw_chr)

    cwd_rel <- sub("^/+", "", cwd)
    if (startsWith(raw_chr, paste0(cwd_rel, "/")) || identical(raw_chr, cwd_rel)) {
      return(paste0("/", raw_chr))
    }

    raw_chr
  }

  path_exists_local <- function(path) {
    if (is.null(path) || !nzchar(path)) return(FALSE)

    variants <- unique(Filter(nzchar, c(
      as.character(path),
      tryCatch(enc2utf8(path), error = function(e) as.character(path)),
      tryCatch(enc2native(path), error = function(e) as.character(path))
    )))

    for (candidate in variants) {
      if (tryCatch(isTRUE(dir.exists(candidate)), error = function(e) FALSE)) return(TRUE)
      if (tryCatch(isTRUE(file.exists(candidate)), error = function(e) FALSE)) return(TRUE)

      parent_dir <- tryCatch(dirname(candidate), error = function(e) "")
      leaf_name <- tryCatch(basename(candidate), error = function(e) "")
      if (nzchar(parent_dir) && nzchar(leaf_name)) {
        listed <- tryCatch(list.files(parent_dir, all.files = TRUE, no.. = TRUE), error = function(e) character(0))
        if (length(listed) && any(tolower(listed) == tolower(leaf_name))) return(TRUE)
      }
    }

    FALSE
  }

  raw <- sanitize_mcp_base_raw(Sys.getenv("MCP_FILES_BASE", MERGEN_UPLOADS_DIR))
  base <- normalize_mcp_path(raw, must_exist = FALSE)

  tryCatch({
    fs::dir_create(base, recurse = TRUE)
  }, error = function(e) NULL)

  if (!isTRUE(path_exists_local(base))) {
    base <- MERGEN_UPLOADS_DIR
    tryCatch({
      fs::dir_create(base, recurse = TRUE)
    }, error = function(e) {
      dir.create(base, showWarnings = FALSE, recursive = TRUE)
    })
  }

  normalize_mcp_path(base, must_exist = path_exists_local(base))
}