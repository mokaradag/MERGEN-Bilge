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

# --- ORTAK YOL YARDIMCILARI ---
# Yol değerlerini tek noktadan güvenli biçimde işler.

.as_scalar_path <- function(path) {
  if (is.null(path) || length(path) == 0) {
    return("")
  }

  candidate <- as.character(path[1])
  if (is.na(candidate) || !nzchar(candidate)) {
    return("")
  }

  candidate
}

.path_exists_any <- function(path) {
  candidate <- .as_scalar_path(path)
  if (!nzchar(candidate)) {
    return(FALSE)
  }

  tryCatch(
    isTRUE(file.exists(candidate)) ||
      isTRUE(dir.exists(candidate)) ||
      isTRUE(fs::file_exists(candidate)) ||
      isTRUE(fs::dir_exists(candidate)),
    error = function(e) FALSE
  )
}

# --- WINDOWS KISA YOL (8.3) DÖNÜŞTÜRÜCÜ ---
# Unicode karakterli yolları Windows'un kısa (8.3) formatına çevirir.
safe_windows_short_path <- function(path, must_exist = FALSE) {
  if (.Platform$OS.type != "windows") {
    return(path)
  }

  candidate <- .as_scalar_path(path)
  if (!nzchar(candidate)) {
    return(candidate)
  }

  candidate_norm <- gsub("\\\\", "/", candidate, fixed = TRUE)

  # UNC ağ paylaşımı için shortPathName kullanma.
  # Bu çağrı bazı Windows/SMB ortamlarda baştaki çift eğik çizgiyi bozup
  # //sunucu/paylasim/... yolunu /sunucu/paylasim/... haline getirebiliyor.
  # Excel tarafındaki "Exists: FALSE" hatasının ana nedeni budur.
  is_unc <- grepl("^//[^/]+/[^/]+", candidate_norm)

  if (is_unc) {
    unc_fixed <- paste0("//", sub("^/+", "", candidate_norm))
    return(unc_fixed)
  }

  candidate_fs <- gsub("/", "\\\\", candidate_norm, fixed = TRUE)
  if (isTRUE(must_exist) && !.path_exists_any(candidate_fs)) {
    return(candidate_norm)
  }

  short_raw <- tryCatch(
    utils::shortPathName(candidate_fs),
    error = function(e) candidate_fs
  )

  if (!nzchar(short_raw)) {
    short_raw <- candidate_fs
  }

  short_norm <- gsub("\\\\", "/", short_raw, fixed = TRUE)
  short_norm
}

# --- UTF-8 YOL NORMALİZASYONU ---
# Yol dizelerini UTF-8 uyumlu hâle getirir; ayırıcıları standartlaştırır.
normalize_utf8_path <- function(path, mustWork = FALSE) {
  candidate <- .as_scalar_path(path)
  if (!nzchar(candidate)) {
    return(candidate)
  }

  candidate_utf8 <- tryCatch(enc2utf8(candidate), error = function(e) candidate)
  candidate_native <- tryCatch(enc2native(candidate_utf8), error = function(e) candidate_utf8)

  variants <- unique(c(
    candidate,
    candidate_utf8,
    candidate_native,
    gsub("/", "\\\\", candidate, fixed = TRUE),
    gsub("/", "\\\\", candidate_utf8, fixed = TRUE),
    gsub("/", "\\\\", candidate_native, fixed = TRUE)
  ))

  variants <- variants[nzchar(variants)]

  for (v in variants) {
    normalized <- tryCatch(
      normalizePath(v, winslash = "/", mustWork = mustWork),
      error = function(e) NA_character_,
      warning = function(w) NA_character_
    )

    if (!is.na(normalized) && nzchar(normalized)) {
      normalized <- gsub("\\\\", "/", normalized, fixed = TRUE)
      exists_now <- .path_exists_any(normalized)
      return(safe_windows_short_path(normalized, must_exist = exists_now))
    }
  }

  fallback <- gsub("\\\\", "/", candidate_utf8, fixed = TRUE)
  safe_windows_short_path(fallback, must_exist = .path_exists_any(fallback))
}

# --- MCP YOL NORMALİZASYONU ---
# UNC, Windows ve Linux yollarını tutarlı biçime dönüştürür.
# Baştaki tekrar eden dizin parçalarını temizler.
normalize_mcp_path <- function(candidate, must_exist = FALSE) {
  candidate <- .as_scalar_path(candidate)
  if (!nzchar(candidate)) {
    return(candidate)
  }

  dedupe_leading_pair <- function(p) {
    if (!nzchar(p)) {
      return(p)
    }

    slashes <- sub("^(//)", "", p)
    parts <- strsplit(slashes, "/", fixed = TRUE)[[1]]

    if (length(parts) >= 4 && identical(parts[1:2], parts[3:4])) {
      return(paste0("//", paste(c(parts[1:2], parts[-(1:4)]), collapse = "/")))
    }

    p
  }

  candidate <- gsub("\\\\", "/", candidate, fixed = TRUE)

  # UNC yolları: sadece çift eğik çizgi ile başlayan ağ yollarını yakala.
  # Tek eğik çizgi ile başlayan /tmp/... gibi Unix mutlak yollar UNC değildir.
  is_unc_path <- grepl("^//[^/]+/[^/]+", candidate)
  if (is_unc_path) {
    cleaned <- paste0("//", sub("^/+", "", candidate))
    cleaned <- dedupe_leading_pair(cleaned)
    return(cleaned)
  }

  normalize_utf8_path(candidate, mustWork = must_exist)
}

# --- TÜRKÇE MOJIBAKE ONARIM YARDIMCILARI ---
# Windows ortam değişkenlerinden gelen klasik UTF-8 bozulmalarını düzeltir.
# Bu onarım yalnızca ortam değişkeni okuma sınırında uygulanır.

.build_mojibake_pair <- function(bad_codepoints, good_codepoints) {
  list(
    bad = paste0(vapply(bad_codepoints, intToUtf8, character(1), USE.NAMES = FALSE), collapse = ""),
    good = paste0(vapply(good_codepoints, intToUtf8, character(1), USE.NAMES = FALSE), collapse = "")
  )
}

.get_turkish_mojibake_pairs <- function() {
  list(
    .build_mojibake_pair(c(195L, 188L), c(252L)),   # Ã¼ -> ü
    .build_mojibake_pair(c(195L, 156L), c(220L)),   # Ãœ -> Ü
    .build_mojibake_pair(c(195L, 182L), c(246L)),   # Ã¶ -> ö
    .build_mojibake_pair(c(195L, 150L), c(214L)),   # Ã– -> Ö
    .build_mojibake_pair(c(195L, 167L), c(231L)),   # Ã§ -> ç
    .build_mojibake_pair(c(195L, 135L), c(199L)),   # Ã‡ -> Ç
    .build_mojibake_pair(c(196L, 177L), c(305L)),   # Ä± -> ı
    .build_mojibake_pair(c(196L, 176L), c(304L)),   # Ä° -> İ
    .build_mojibake_pair(c(197L, 376L), c(351L)),   # ÅŸ -> ş
    .build_mojibake_pair(c(197L, 382L), c(350L)),   # Åž -> Ş
    .build_mojibake_pair(c(196L, 376L), c(287L)),   # ÄŸ -> ğ
    .build_mojibake_pair(c(196L, 382L), c(286L)),   # Äž -> Ğ
    .build_mojibake_pair(c(194L, 160L), c(32L)),    # NBSP -> boşluk
    .build_mojibake_pair(c(194L), integer(0))       # Yalnız kalan Â -> sil
  )
}

path_has_turkish_mojibake <- function(path) {
  val <- .as_scalar_path(path)
  if (!nzchar(val)) {
    return(FALSE)
  }

  pairs <- .get_turkish_mojibake_pairs()
  any(vapply(pairs, function(pair) grepl(pair$bad, val, fixed = TRUE), logical(1)))
}

repair_turkish_mojibake_path <- function(path) {
  val <- .as_scalar_path(path)
  if (!nzchar(val)) {
    return(val)
  }

  fixed <- val
  pairs <- .get_turkish_mojibake_pairs()

  for (pair in pairs) {
    fixed <- gsub(pair$bad, pair$good, fixed, fixed = TRUE)
  }

  enc2utf8(fixed)
}

# Ortam değişkeninden yol okur.
# Gerekirse yalnızca bu sınırda Türkçe karakter bozulmasını onarır.
read_env_path_safe <- function(var_name, fallback = "") {
  raw <- Sys.getenv(var_name, "")
  if (!nzchar(raw)) {
    return(fallback)
  }

  if (!path_has_turkish_mojibake(raw)) {
    return(raw)
  }

  repaired <- repair_turkish_mojibake_path(raw)

  raw_exists <- .path_exists_any(raw)
  repaired_exists <- .path_exists_any(repaired)

  if (nzchar(repaired) && (isTRUE(repaired_exists) || !isTRUE(raw_exists))) {
    log_warn("[MCP_FILES_BASE] Türkçe karakter bozulması tespit edildi; yol onarıldı.")
    return(repaired)
  }

  raw
}

# --- MCP TEMEL DİZİN ÇÖZÜMLEYİCİ ---
# MCP_FILES_BASE ortam değişkenini okur, dizin yoksa oluşturur,
# başarısız olursa MERGEN_UPLOADS_DIR'e düşer.
# NOT: Bu fonksiyon MERGEN_UPLOADS_DIR global değişkenine bağımlıdır
#      ve config_file_store.R'de çağrılır.
resolve_mcp_base_dir <- function() {
  raw <- read_env_path_safe("MCP_FILES_BASE", fallback = MERGEN_UPLOADS_DIR)
  if (!nzchar(raw)) {
    raw <- MERGEN_UPLOADS_DIR
  }

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
    tryCatch({
      fs::dir_create(base, recurse = TRUE)
    }, error = function(e) {
      dir.create(base, showWarnings = FALSE, recursive = TRUE)
    })
  }

  normalize_mcp_path(base, must_exist = TRUE)
}