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
normalize_mcp_path <- function(candidate, must_exist = FALSE) {
  if (is.null(candidate) || !nzchar(candidate)) return(candidate)

  dedupe_leading_pair <- function(p) {
    if (!nzchar(p)) return(p)
    slashes <- sub("^(//)", "", p)
    parts <- strsplit(slashes, "/", fixed = TRUE)[[1]]
    if (length(parts) >= 4 && identical(parts[1:2], parts[3:4])) {
      return(paste0("//", paste(c(parts[1:2], parts[-(1:4)]), collapse = "/")))
    }
    p
  }

  candidate <- as.character(candidate)
  candidate <- gsub("\\\\", "/", candidate, fixed = TRUE)

  # UNC yolları: tek veya çift eğik çizgiyle başlayan ağ yollarını yakala
  maybe_unc <- grepl("^/{1,2}[^/]+/[^/]+", candidate)
  if (maybe_unc) {
    cleaned <- paste0("//", sub("^/+", "", candidate))
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
resolve_mcp_base_dir <- function() {
  raw <- Sys.getenv("MCP_FILES_BASE", "")
  mcp_belirtildi <- nzchar(raw)

  if (!mcp_belirtildi) {
    raw <- MERGEN_UPLOADS_DIR
  }

  # Ters eğik çizgileri düzelt, UNC baştaki tek slash'ı çift slash yap.
  base <- gsub("\\\\", "/", raw, fixed = TRUE)
  if (grepl("^/[^/]", base)) {
    base <- paste0("/", base)
  }

  # --- ENCODING VARYANTI ÜRETİMİ ---
  # .Renviron farklı encoding'lerde (UTF-8 BOM'lu, UTF-8 BOM'suz, ANSI CP1254)
  # yazılmış olabilir. Sys.getenv() bunu yorumlama biçimi R sürümüne göre değişir.
  # Bu yüzden dizin oluşturmayı ve var olma kontrolünü birden fazla encoding
  # işaretiyle deniyoruz ki HANGİSİ doğruysa o varyant başarıyla çalışsın.
  encoding_varyantlari <- function(p) {
    varyantlar <- list(p)
    eklemek_dene <- function(deneme) {
      if (!is.null(deneme) && nzchar(deneme)) {
        varyantlar[[length(varyantlar) + 1L]] <<- deneme
      }
    }
    # UTF-8 etiketli (bytes olduğu gibi)
    v <- p; tryCatch(Encoding(v) <- "UTF-8", error = function(e) NULL); eklemek_dene(v)
    # Native/unknown etiketli
    v <- p; tryCatch(Encoding(v) <- "unknown", error = function(e) NULL); eklemek_dene(v)
    # enc2utf8 ile dönüştürülmüş
    eklemek_dene(tryCatch(enc2utf8(p), error = function(e) NULL))
    # enc2native ile dönüştürülmüş (Windows CP1254 için)
    eklemek_dene(tryCatch(enc2native(p), error = function(e) NULL))
    unique(varyantlar)
  }

  dizin_var_mi <- function(p) {
    tryCatch(
      isTRUE(dir.exists(p)) || isTRUE(fs::dir_exists(p)),
      error = function(e) FALSE
    )
  }

  dizin_olustur_dene <- function(p) {
    olustu <- tryCatch({ fs::dir_create(p, recurse = TRUE); TRUE },
                       error = function(e) FALSE)
    if (!isTRUE(olustu)) {
      olustu <- tryCatch({ dir.create(p, showWarnings = FALSE, recursive = TRUE); TRUE },
                         error = function(e) FALSE)
    }
    isTRUE(olustu) && dizin_var_mi(p)
  }

  # Dizini oluştur: her encoding varyantını dene, ilk çalışan kazansın
  secilen_base <- NULL
  for (v in encoding_varyantlari(base)) {
    if (dizin_var_mi(v) || dizin_olustur_dene(v)) {
      secilen_base <- v
      break
    }
  }
  if (!is.null(secilen_base)) {
    base <- secilen_base
  }

  # --- KRİTİK: WINDOWS 8.3 KISA YOLU ---
  # Dizin oluşturulduktan sonra Windows'un shortPathName() fonksiyonu ile
  # 8.3 kısa yolu (örn. //rehisds/.../GELIST~1/MERGEN~1) alıyoruz. Bu yol
  # yalnızca ASCII karakter içerir; Türkçe karakter içeren path bileşenleri
  # tamamen elenir. Böylece hiçbir mojibake senaryosu mümkün olmaz ve bütün
  # dosya işlemleri (file.exists, list.files, fs::*) sorunsuz çalışır.
  # shortPathName Windows'un wide-character API'sini kullandığından encoding
  # yorumlama sorunlarına karşı dayanıklıdır.
  if (.Platform$OS.type == "windows" && dizin_var_mi(base)) {
    base_backslash <- gsub("/", "\\\\", base, fixed = TRUE)
    kisa_yol <- tryCatch(
      utils::shortPathName(base_backslash),
      error = function(e) NA_character_
    )
    if (!is.na(kisa_yol) && nzchar(kisa_yol)) {
      kisa_yol_slash <- gsub("\\\\", "/", kisa_yol, fixed = TRUE)
      # Kısa yolun GERÇEKTEN çalıştığını doğrula
      if (dizin_var_mi(kisa_yol_slash)) {
        base <- kisa_yol_slash
      }
    }
  }

  # Yedek: dizin hiçbir varyantta oluşturulamadıysa MERGEN_UPLOADS_DIR'e düş
  if (!dizin_var_mi(base)) {
    base <- gsub("\\\\", "/", MERGEN_UPLOADS_DIR, fixed = TRUE)
    dizin_olustur_dene(base)
  }

  base
}