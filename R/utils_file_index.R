# ==============================================================================
# R/utils_file_index.R
# Dosya Yolu: R/utils_file_index.R
# Açıklama: Ağ/yerel klasörlerde hızlı dosya arama için önbellekli indeks
# mekanizması. basename -> tam yol eşlemesi tutar ve TTL ile yenilenir.
# global.R tarafından utils_path_helpers.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- HIZLI DOSYA İNDEKSİ (önbellekli) ---
.FILE_INDEX_CACHE <- new.env(parent = emptyenv())
FILE_INDEX_TTL_MIN <- suppressWarnings(as.numeric(Sys.getenv("MCP_INDEX_TTL_MIN", "10")))
if (is.na(FILE_INDEX_TTL_MIN) || FILE_INDEX_TTL_MIN <= 0) FILE_INDEX_TTL_MIN <- 10

# Belirtilen klasördeki dosyaları tarar ve basename -> tam yol haritası oluşturur
.build_basename_index <- function(base_path, pattern = "\\.(docx|doc|pdf|xlsx|xls|csv|txt|json|md|r|py|log)$", force = FALSE) {
  # not: büyük ağ klasörlerinde tekrar taramayı sınırlamak için TTL
  now <- Sys.time()
  key <- normalizePath(base_path, winslash = "/", mustWork = FALSE)
  ent <- .FILE_INDEX_CACHE[[key]]

  is_stale <- TRUE
  if (is.list(ent) && !is.null(ent$ts)) {
    age <- as.numeric(difftime(now, ent$ts, units = "mins"))
    is_stale <- isTRUE(age > FILE_INDEX_TTL_MIN)
  }

  if (force || is_stale || is.null(ent) || is.null(ent$map)) {
    if (!dir.exists(base_path)) {
      log_warn("[INDEX] Klasör yok, indeks oluşturulamadı: {base_path}")
      .FILE_INDEX_CACHE[[key]] <- list(ts = now, map = list())
      return(.FILE_INDEX_CACHE[[key]])
    }
    log_info("[INDEX] Taranıyor (TTL {FILE_INDEX_TTL_MIN}dk): {base_path}")

    # Yalnızca yaygın belge türleri.
    # Windows VM / UNC klasörlerinde geçici erişim hataları tüm uygulamayı
    # düşürmemeli; indeks boş döner ve sonraki TTL döngüsünde tekrar denenir.
    all_files <- tryCatch(
      list.files(
        base_path,
        pattern = pattern,
        full.names = TRUE,
        recursive = TRUE,
        include.dirs = FALSE,
        ignore.case = TRUE
      ),
      error = function(e) {
        log_warn("[INDEX] Klasör taraması başarısız: {base_path} | {conditionMessage(e)}")
        character(0)
      }
    )

    all_files <- enc2utf8(as.character(all_files))
    all_files <- gsub("\\", "/", all_files, fixed = TRUE)
    all_files <- sort(unique(all_files[nzchar(all_files)]))

    # basename -> tam yol listesi (aynı ad birden fazlaysa liste tut)
    map <- split(all_files, tolower(basename(all_files)))
    .FILE_INDEX_CACHE[[key]] <- list(ts = now, map = map)
  }

  .FILE_INDEX_CACHE[[key]]
}

# İndeksten basename eşleşmesi arar
.search_from_index <- function(base_path, target_filename) {
  idx <- .build_basename_index(base_path)
  if (!length(idx$map)) return(NULL)
  key <- tolower(basename(target_filename))
  cand <- idx$map[[key]]
  if (is.null(cand) || !length(cand)) return(NULL)
  for (p in cand) { if (path_exists_relaxed(p)) return(p) }
  NULL
}

# Yardımcı: ipucu parçalarını yol ile skorla (kaç parça geçiyor?)
.score_path_by_parts <- function(path, parts) {
  if (length(parts) == 0) return(0L)
  p <- tolower(path)
  sum(vapply(parts, function(s) grepl(tolower(trimws(s)), p, fixed = TRUE), logical(1)))
}

# 'A&&B&&C.docx' ipucu ile arama (indeksteki tüm C.docx adaylarını A/B parçalarına göre puanla)
.search_with_hint <- function(base_path, hint) {
  if (!is.character(hint) || length(hint) == 0 || is.na(hint[1])) {
    return(NULL)
  }

  parts <- tryCatch(strsplit(as.character(hint[1]), "&&", fixed = TRUE)[[1]], error = function(e) character(0))
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)
  last <- tail(parts, 1)
  idx <- .build_basename_index(base_path)
  cand <- idx$map[[tolower(basename(last))]]
  if (is.null(cand) || !length(cand)) return(NULL)

  left <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
  if (!length(left)) {
    for (p in cand) { if (path_exists_relaxed(p)) return(p) }
    return(NULL)
  }

  scores <- vapply(cand, .score_path_by_parts, integer(1), parts = left)
  ord <- order(scores, decreasing = TRUE, na.last = NA)
  for (i in ord) {
    p <- cand[[i]]
    if (path_exists_relaxed(p)) return(p)
  }
  NULL
}

# Akıllı arama: önce TAM ipucu ile dene, sonra klasik basename
search_file_in_folder <- function(base_path, target_filename) {
  log_info("[FILE SEARCH] base='{base_path}', target='{target_filename}'")
  if (!dir.exists(base_path)) {
    log_error("[FILE SEARCH] taban klasör yok: '{base_path}'")
    return(NULL)
  }
  # 1) '&&' ipucu varsa onu kullan (indeks içi aday daraltma + puanlama)
  if (is.character(target_filename) && grepl("&&", target_filename, fixed = TRUE)) {
    hit_hint <- .search_with_hint(base_path, target_filename)
    if (!is.null(hit_hint)) {
      log_info("[FILE SEARCH] ipucu ile bulundu: {hit_hint}")
      return(hit_hint)
    }
  }
  # 2) Sade basename araması
  hit <- .search_from_index(base_path, target_filename)
  if (!is.null(hit)) {
    log_info("[FILE SEARCH] indeks eşleşmesi: {hit}")
    return(hit)
  }
  log_warn("[FILE SEARCH] eşleşme yok: target='{target_filename}'")
  NULL
}