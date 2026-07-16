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
.build_basename_index <- function(base_path, pattern = "\\.(docx|docm|doc|pdf|pptx|ppt|xlsx|xls|csv|txt|json|md|r|py|log)$", force = FALSE) {
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
  # İpucu skoru yalnızca gerçekten sol parçaların TÜMÜ aday yolunda geçtiğinde
  # güvenilir kabul edilir. Aksi halde, aynı basename'e sahip ama bambaşka bir
  # klasörde duran alakasız dosyayı açmak yerine NULL dönüp sonraki güvenli
  # arama/fallback adımlarına bırakırız.
  if (!length(scores) || max(scores, na.rm = TRUE) < length(left)) return(NULL)

  ord <- order(scores, decreasing = TRUE, na.last = NA)
  for (i in ord) {
    if (scores[[i]] < length(left)) next
    p <- cand[[i]]
    if (path_exists_relaxed(p)) return(p)
  }
  NULL
}

# '&&' parçalarının TÜMÜNÜ (son parça dahil) yol içinde barındıran indeks
# girişini seçer. '&&' düz dosya adının parçasıysa (dizin değil; disk basename'i
# 'A&&B&&dosya.pdf' gibi '&&' içerir) tam ad bu yolla yakalanır: '.search_with_hint'
# yalnızca son parçayı basename varsayıp başarısız olur, bu yardımcı ise tüm
# parçaların geçtiği en iyi adayı bulur. Boşluk/büyük-küçük harf farklarına da
# dayanıklıdır. Tüm parçalar geçmiyorsa (best < parça sayısı) NULL döner.
#
# GÜVENLİK: bu son çare yalnızca UZANTISIZ son parça için etkindir (opt-in).
# Bu noktaya gelindiğinde tam basename eşleşmesi (adım 1) VE ipucu-skorlu
# arama (adım 2, son parçanın TAM basename eşleşmesini arar) zaten başarısız
# olmuştur. Son parçanın bir uzantısı varsa (ör. "prosedur.pdf"), yalnızca
# alt-dize içerme skoruna dayanarak dosya açmak, atıflanan gerçek dosya DİSKTE
# YOKKEN yanlışlıkla benzer adlı ALAKASIZ bir dosyayı (ör. "eski-prosedur.pdf")
# önizlemeye açabilir. Bu durumda "bulunamadı" demek, yanlış belge açmaktan
# daha güvenlidir; bu yüzden uzantılı son parçalarda bu son çare devre dışıdır.
.search_all_parts_contained <- function(base_path, hint) {
  if (!is.character(hint) || length(hint) == 0 || is.na(hint[1])) return(NULL)
  parts <- trimws(strsplit(as.character(hint[1]), "&&", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)
  if (nzchar(tools::file_ext(parts[length(parts)]))) return(NULL)

  idx <- .build_basename_index(base_path)
  if (!length(idx$map)) return(NULL)
  all_paths <- unlist(idx$map, use.names = FALSE)
  if (!length(all_paths)) return(NULL)

  scores <- vapply(all_paths, .score_path_by_parts, integer(1), parts = parts)
  if (max(scores) < length(parts)) return(NULL)
  ord <- order(scores, decreasing = TRUE, na.last = NA)
  for (i in ord) {
    p <- all_paths[[i]]
    if (path_exists_relaxed(p)) return(p)
  }
  NULL
}

# Akıllı arama: önce TAM basename eşleşmesi, sonra ipucu, son çare parça içerme.
search_file_in_folder <- function(base_path, target_filename) {
  log_info("[FILE SEARCH] base='{base_path}', target='{target_filename}'")
  if (!dir.exists(base_path)) {
    log_error("[FILE SEARCH] taban klasör yok: '{base_path}'")
    return(NULL)
  }
  # 1) ÖNCE tam basename eşleşmesi (düz '&&' dosya adı tam eşleşmesi dahil).
  #    Bu adım ipucu-skorlu aramadan (2) ÖNCE gelmelidir: gerçek disk adı '&&'
  #    İÇEREN düz bir dosyaysa (kategori öneki gömülü ad), '.search_with_hint'
  #    yalnızca ipucunun SON parçasını basename sayıp arar; taban klasörde aynı
  #    son-parça adına sahip alakasız bir dosya varsa (ör. başka bir yerdeki
  #    düz "prosedur.pdf"), tam eşleşme önce denenmezse o alakasız dosya
  #    yanlışlıkla döndürülebilir.
  hit <- .search_from_index(base_path, target_filename)
  if (!is.null(hit)) {
    log_info("[FILE SEARCH] tam eşleşme: {hit}")
    return(hit)
  }
  # 2) '&&' ipucu varsa (gerçek alt klasör ipucu biçimi) skorlu arama dene.
  if (is.character(target_filename) && grepl("&&", target_filename, fixed = TRUE)) {
    hit_hint <- .search_with_hint(base_path, target_filename)
    if (!is.null(hit_hint)) {
      log_info("[FILE SEARCH] ipucu ile bulundu: {hit_hint}")
      return(hit_hint)
    }
  }
  # 3) '&&' düz dosya adı için son çare: tüm parçaları içeren en iyi aday
  if (is.character(target_filename) && grepl("&&", target_filename, fixed = TRUE)) {
    hit_all <- .search_all_parts_contained(base_path, target_filename)
    if (!is.null(hit_all)) {
      log_info("[FILE SEARCH] parça içerme ile bulundu: {hit_all}")
      return(hit_all)
    }
  }
  log_warn("[FILE SEARCH] eşleşme yok: target='{target_filename}'")
  NULL
}