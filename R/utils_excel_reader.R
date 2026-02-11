# ==============================================================================
# R/utils_excel_reader.R
# Sağlam Excel tablo okuyucu: yol normalizasyonu, başlık algılama,
# otomatik format seçimi (xlsx/xls) ve hata kurtarma mekanizmaları.
# global.R tarafından config_file_store.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- EXCEL YOL NORMALİZASYONU ---
# Excel dosya yollarını düzeltir: UNC, tekrar eden dizin parçaları,
# Windows özel karakterleri ve kodlama sorunlarını ele alır.
normalize_excel_path <- function(path) {
  if (is.null(path) || !nzchar(path)) return(path)

  # Varsa MCP yol normalizasyonunu uygula
  if (exists("normalize_mcp_path", envir = globalenv(), inherits = TRUE)) {
    try_norm <- try(
      get("normalize_mcp_path", envir = globalenv(), inherits = TRUE)(path, must_exist = FALSE),
      silent = TRUE
    )
    if (!inherits(try_norm, "try-error") && !is.null(try_norm) && nzchar(try_norm)) {
      path <- try_norm
    }
  }

  p_fixed <- gsub("\\\\", "/", path)

  # İç yardımcı: baştaki tekrar eden dizin parçalarını temizle
  dedupe_leading_repeat <- function(p) {
    if (!nzchar(p)) return(p)
    slashes <- sub("^(/*)", "\\1", p)
    parts <- strsplit(sub("^/+", "", p), "/", fixed = TRUE)[[1]]
    if (length(parts) < 4) return(p)
    if (identical(parts[1:2], parts[3:4])) {
      rebuilt <- paste(c(slashes, parts[1:2], parts[-(1:4)]), collapse = "/")
      return(gsub("/{2,}", "/", rebuilt))
    }
    p
  }

  p_fixed <- dedupe_leading_repeat(p_fixed)

  # Linux'ta UTF-8 dönüşümü uygula
  if (.Platform$OS.type != "windows") {
    p_fixed <- tryCatch(enc2utf8(p_fixed), error = function(e) p_fixed)
  }

  # Tek eğik çizgiyle başlayan yollara ikinci eğik çizgi ekle (UNC düzeltmesi)
  if (grepl("^/[^/]", p_fixed)) {
    p_fixed <- paste0("/", p_fixed)
  }

  # Çift eğik çizgiyle başlıyorsa (UNC) fazla eğik çizgileri temizle
  if (grepl("^//", p_fixed)) {
    return(gsub("/{3,}", "//", p_fixed))
  }

  # Dosya varlığını kontrol eden yardımcı
  path_exists_check <- function(p) {
    if (is.null(p) || !nzchar(p)) return(FALSE)
    tryCatch({
      if (file.exists(p)) return(TRUE)
      if (requireNamespace("fs", quietly = TRUE) && fs::file_exists(p)) return(TRUE)
      FALSE
    }, error = function(e) FALSE)
  }

  # Windows'ta farklı kodlamalarda varlık kontrolü
  if (.Platform$OS.type == "windows") {
    candidates <- unique(c(p_fixed, tryCatch(enc2utf8(p_fixed), error = function(e) NULL)))
    for (cand in candidates) {
      if (!is.null(cand) && path_exists_check(cand)) {
        return(cand)
      }
    }
  } else {
    if (path_exists_check(p_fixed)) return(enc2utf8(p_fixed))
  }

  normalized <- tryCatch(
    normalizePath(p_fixed, winslash = "/", mustWork = FALSE),
    error = function(e) p_fixed
  )
  dedupe_leading_repeat(normalized)
}

# ==============================================================================
# SAĞLAM EXCEL TABLO OKUYUCU
# Gerçek tablonun sol üst köşesini otomatik algılar; boş satır/sütunları atlar.
# ==============================================================================
safe_read_excel_table <- function(path, sheet = 1, n_max = Inf, min_header_cols = 2) {
  path_prepared <- normalize_excel_path(path)

  if (!file.exists(path_prepared) && !fs::file_exists(path_prepared)) {
    if (file.exists(path)) path_prepared <- path
    else stop(sprintf("Dosya bulunamadı (Yol: %s)", path_prepared))
  }

  # Doğru okuyucuyu seç (xlsx vs xls) — dosya imzasına göre
  # Windows kısa yollarında (örn. DATA~1.XLS) uzantı yanıltıcı olabileceğinden
  # imza tabanlı algılama tercih edilir.
  pick_reader <- function(p) {
    fmt <- tryCatch(readxl::excel_format(p), error = function(e) NULL)
    if (is.null(fmt)) {
      ext <- tolower(tools::file_ext(p))
      if (ext %in% c("xlsx", "xlsm")) return(readxl::read_xlsx)
      return(readxl::read_xls)
    }
    if (fmt %in% c("xlsx", "xlsm")) return(readxl::read_xlsx)
    return(readxl::read_xls)
  }

  # 1. Ön Okuma: başlık satırını algıla (col_names = FALSE)
  raw <- tryCatch({
    reader <- pick_reader(path_prepared)
    reader(path_prepared, sheet = sheet, col_names = FALSE, .name_repair = "minimal")
  }, error = function(e) {
    # Libxls uyumsuzluk kurtarması (ShortPath .XLS → .xlsx içeriği)
    if (grepl("libxls error", conditionMessage(e), ignore.case = TRUE)) {
      return(readxl::read_xlsx(
        path_prepared, sheet = sheet, col_names = FALSE, .name_repair = "minimal"
      ))
    }
    # Windows'ta kısa yolla yeniden dene
    if (.Platform$OS.type == "windows") {
      short_p <- tryCatch(
        utils::shortPathName(gsub("/", "\\\\", path_prepared)),
        error = function(x) NULL
      )
      if (!is.null(short_p) && nzchar(short_p)) {
        reader_s <- pick_reader(short_p)
        return(reader_s(short_p, sheet = sheet, col_names = FALSE, .name_repair = "minimal"))
      }
    }
    stop(e)
  })

  if (is.null(raw) || nrow(raw) == 0) {
    return(data.frame())
  }

  # 2. Başlık Satırını Bul: en az min_header_cols kadar dolu hücre içeren ilk satır
  header_row <- 1
  for (i in seq_len(min(20, nrow(raw)))) {
    vals <- as.character(unlist(raw[i, ]))
    non_empty <- sum(!is.na(vals) & nzchar(trimws(vals)))
    if (non_empty >= min_header_cols) {
      header_row <- i
      break
    }
  }

  # 3. Aralık Hesapla
  rng <- cellranger::cell_limits(
    ul = c(header_row, 1),
    lr = c(NA, ncol(raw))
  )

  # 4. Son Okuma (gerçek başlıklarla)
  df <- tryCatch({
    reader_final <- pick_reader(path_prepared)
    reader_final(
      path_prepared,
      sheet = sheet,
      range = rng,
      col_names = TRUE,
      n_max = if (is.finite(n_max)) n_max else NULL
    )
  }, error = function(e) {
    # Libxls uyumsuzluk kurtarması
    if (grepl("libxls error", conditionMessage(e), ignore.case = TRUE)) {
      return(readxl::read_xlsx(
        path_prepared,
        sheet = sheet,
        range = rng,
        col_names = TRUE,
        n_max = if (is.finite(n_max)) n_max else NULL
      ))
    }
    # Windows'ta kısa yolla yeniden dene
    if (.Platform$OS.type == "windows") {
      short_p <- tryCatch(
        utils::shortPathName(gsub("/", "\\\\", path_prepared)),
        error = function(x) NULL
      )
      if (!is.null(short_p) && nzchar(short_p)) {
        reader_final_s <- pick_reader(short_p)
        return(reader_final_s(
          short_p,
          sheet = sheet,
          range = rng,
          col_names = TRUE,
          n_max = if (is.finite(n_max)) n_max else NULL
        ))
      }
    }
    stop(e)
  })

  # Sütun adlarını düzelt (NA veya boş olanları X1, X2, ... yap)
  if (anyNA(names(df)) || any(names(df) == "")) {
    names(df) <- paste0("X", seq_along(df))
  }
  names(df) <- make.names(names(df), unique = TRUE, allow_ = TRUE)

  as.data.frame(df, stringsAsFactors = FALSE)
}