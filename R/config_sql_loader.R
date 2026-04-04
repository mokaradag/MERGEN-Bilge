# ==============================================================================
# R/config_sql_loader.R
# Dosya Yolu: R/config_sql_loader.R
# Aciklama: query_library icindeki sql_file tanimlarini zorunlu olarak yukler.
#           sql_file varsa, ilgili dosya her zaman okunur ve q_item$sql alani
#           dosya icerigi ile uzerine yazilir.
#           Dosya bulunamazsa veya okunamazsa uygulama durdurulur.
# ==============================================================================

# --- HATA AYIKLAMA MODU KONTROLU ---
.SQL_LOADER_DEBUG <- isTRUE(as.logical(Sys.getenv("MERGEN_DEBUG", "FALSE")))

# --- YARDIMCI: BOS OLMAYAN KARAKTER KONTROLU ---
.sql_has_text <- function(x) {
  !is.null(x) && nzchar(trimws(as.character(x)[1]))
}

# --- YARDIMCI: SQL DOSYA YOLUNU COZ ---
.resolve_sql_file_path <- function(fpath) {
  fpath <- as.character(fpath)[1]
  fpath <- trimws(fpath)

  if (!nzchar(fpath)) {
    return(NULL)
  }

  aday_yollar <- unique(c(
    fpath,
    tryCatch(
      normalizePath(fpath, winslash = "/", mustWork = FALSE),
      error = function(e) NA_character_
    )
  ))

  aday_yollar <- aday_yollar[!is.na(aday_yollar) & nzchar(aday_yollar)]

  for (aday in aday_yollar) {
    if (file.exists(aday)) {
      return(aday)
    }
  }

  NULL
}

# --- YARDIMCI: UTF-8 BOM TEMIZLIGI ---
.remove_utf8_bom <- function(metin) {
  if (is.null(metin) || !nzchar(metin)) {
    return(metin)
  }

  ilk_karakter <- substr(metin, 1, 1)

  ilk_raw <- tryCatch(
    charToRaw(ilk_karakter),
    error = function(e) raw(0)
  )

  if (length(ilk_raw) >= 3 &&
      identical(as.integer(ilk_raw[1:3]), c(239L, 187L, 191L))) {
    return(substr(metin, 2, nchar(metin)))
  }

  metin
}

# --- YARDIMCI: SQL DOSYASINI GUVENLI OLARAK OKU ---
.read_sql_file_text <- function(path_to_use) {
  raw_size <- file.info(path_to_use)$size

  if (is.na(raw_size) || raw_size <= 0) {
    stop(sprintf("SQL dosyasi bos veya okunamadi: %s", path_to_use))
  }

  raw_content <- readBin(path_to_use, what = "raw", n = raw_size)

  if (length(raw_content) == 0L) {
    stop(sprintf("SQL dosyasi bos veya okunamadi: %s", path_to_use))
  }

  # Ham byte verisini belirtilen kodlamadan UTF-8'e cevirir
  decode_raw_with_encoding <- function(raw_vec, from_enc) {
    metin <- tryCatch(
      iconv(list(raw_vec), from = from_enc, to = "UTF-8", sub = NA)[[1]],
      error = function(e) NA_character_
    )

    if (is.na(metin)) {
      return(NULL)
    }

    # U+FEFF karakterini regex kullanmadan temizle
    bom_char <- intToUtf8(65279L)
    if (startsWith(metin, bom_char)) {
      metin <- substring(metin, 2L)
    }

    # Satir sonlarini normalize et
    metin <- gsub("\r\n?|\r", "\n", metin, perl = TRUE)

    if (!nzchar(trimws(metin))) {
      return(NULL)
    }

    metin
  }

  # UTF-16 BOM yoksa null byte dagilimina bakarak tahmin yap
  detect_utf16_from_nuls <- function(raw_vec) {
    n <- min(length(raw_vec), 512L)

    if (n < 8L) {
      return(NULL)
    }

    bytes <- as.integer(raw_vec[seq_len(n)])

    tek_indeks <- bytes[seq(1L, n, by = 2L)]
    cift_indeks <- bytes[seq(2L, n, by = 2L)]

    tek_sifir_orani <- if (length(tek_indeks)) mean(tek_indeks == 0L) else 0
    cift_sifir_orani <- if (length(cift_indeks)) mean(cift_indeks == 0L) else 0

    # ASCII agirlikli UTF-16 LE dosyalarda cift byte'larda sifir yogun olur
    if (cift_sifir_orani > 0.20 && tek_sifir_orani < 0.05) {
      return("UTF-16LE")
    }

    # ASCII agirlikli UTF-16 BE dosyalarda tek byte'larda sifir yogun olur
    if (tek_sifir_orani > 0.20 && cift_sifir_orani < 0.05) {
      return("UTF-16BE")
    }

    NULL
  }

  ilk_bytes <- as.integer(raw_content[seq_len(min(length(raw_content), 4L))])

  # UTF-8 BOM: EF BB BF
  if (length(ilk_bytes) >= 3L &&
      identical(ilk_bytes[1:3], c(239L, 187L, 191L))) {
    metin <- decode_raw_with_encoding(raw_content[-(1:3)], "UTF-8")
    if (!is.null(metin)) {
      return(metin)
    }
  }

  # UTF-16 LE BOM: FF FE
  if (length(ilk_bytes) >= 2L &&
      identical(ilk_bytes[1:2], c(255L, 254L))) {
    metin <- decode_raw_with_encoding(raw_content[-(1:2)], "UTF-16LE")
    if (!is.null(metin)) {
      return(metin)
    }
  }

  # UTF-16 BE BOM: FE FF
  if (length(ilk_bytes) >= 2L &&
      identical(ilk_bytes[1:2], c(254L, 255L))) {
    metin <- decode_raw_with_encoding(raw_content[-(1:2)], "UTF-16BE")
    if (!is.null(metin)) {
      return(metin)
    }
  }

  # BOM yoksa UTF-16 tahmini yap
  guessed_utf16 <- detect_utf16_from_nuls(raw_content)
  if (!is.null(guessed_utf16)) {
    metin <- decode_raw_with_encoding(raw_content, guessed_utf16)
    if (!is.null(metin)) {
      return(metin)
    }
  }

  # Sonra tek baytli / UTF-8 kodlamalari dene
  for (kodlama in c("UTF-8", "WINDOWS-1254", "latin1")) {
    metin <- decode_raw_with_encoding(raw_content, kodlama)
    if (!is.null(metin)) {
      return(metin)
    }
  }

  stop(sprintf("SQL dosyasi uygun kodlama ile okunamadi: %s", path_to_use))
}

# --- library_queries.R yuklu degilse yukle ---
if (!exists("query_library", inherits = TRUE)) {
  safe_source("R/library_queries.R", encoding = "UTF-8")
}

if (!exists("query_library", inherits = TRUE) || !is.list(query_library)) {
  stop("[SQL_LOADER] HATA: query_library bulunamadi veya gecerli bir liste degil.")
}

# --- SAYACLAR ---
.sql_total_count <- length(query_library)
.sql_file_declared_count <- 0L
.sql_inline_only_count <- 0L
.sql_loaded_count <- 0L
.sql_failed_count <- 0L
.sql_overwritten_count <- 0L
.sql_missing_id_count <- 0L
.sql_failed_items <- character(0)

cat(sprintf("[SQL_LOADER] getwd() = %s\n", getwd()))
cat(sprintf("[SQL_LOADER] query_library uzunlugu = %d\n", .sql_total_count))

# --- ZORUNLU SQL DOSYA YUKLEME ---
for (i in seq_along(query_library)) {
  q_item <- query_library[[i]]

  q_id <- if (.sql_has_text(q_item$id)) {
    as.character(q_item$id)[1]
  } else {
    .sql_missing_id_count <- .sql_missing_id_count + 1L
    sprintf("index_%d", i)
  }

  has_sql_file <- .sql_has_text(q_item$sql_file)
  has_sql_inline <- .sql_has_text(q_item$sql)

  if (has_sql_file) {
    .sql_file_declared_count <- .sql_file_declared_count + 1L

    fpath <- as.character(q_item$sql_file)[1]
    path_to_use <- .resolve_sql_file_path(fpath)

    if (is.null(path_to_use)) {
      .sql_failed_count <- .sql_failed_count + 1L
      .sql_failed_items <- c(
        .sql_failed_items,
        sprintf("ID: %s | Yol: %s | Hata: dosya bulunamadi", q_id, fpath)
      )

      cat(sprintf(
        "[SQL_LOADER] HATA: SQL dosyasi bulunamadi! ID: %s, Yol: %s\n",
        q_id, fpath
      ))

      if (.SQL_LOADER_DEBUG) {
        cat(sprintf(
          "[SQL_LOADER] Denenen normalize yol: %s\n",
          tryCatch(normalizePath(fpath, winslash = "/", mustWork = FALSE), error = function(e) fpath)
        ))
      }

      next
    }

    full_sql <- tryCatch(
      .read_sql_file_text(path_to_use),
      error = function(e) e
    )

    if (inherits(full_sql, "error")) {
      .sql_failed_count <- .sql_failed_count + 1L
      .sql_failed_items <- c(
        .sql_failed_items,
        sprintf("ID: %s | Yol: %s | Hata: %s", q_id, path_to_use, conditionMessage(full_sql))
      )

      cat(sprintf(
        "[SQL_LOADER] HATA: SQL dosyasi okunamadi! ID: %s, Yol: %s | Hata: %s\n",
        q_id, path_to_use, conditionMessage(full_sql)
      ))

      next
    }

    if (has_sql_inline) {
      .sql_overwritten_count <- .sql_overwritten_count + 1L
    }

    query_library[[i]]$sql <- full_sql
    query_library[[i]]$sql_source <- "sql_file"
    query_library[[i]]$sql_loaded_path <- path_to_use
    # Ham UTF-8 baytlarini sakla: kodlama donusumlerinde karakter kaybi
    # (ozellikle koseli parantez [...] icindeki Turkce kolon adlari) onlenir
    query_library[[i]]$sql_raw <- charToRaw(enc2utf8(full_sql))

    .sql_loaded_count <- .sql_loaded_count + 1L

    if (.SQL_LOADER_DEBUG) {
      cat(sprintf(
        "[SQL_LOADER] OK: %s (%s) -> %d karakter\n",
        q_id, path_to_use, nchar(full_sql, type = "chars")
      ))
    }

  } else if (has_sql_inline) {
    .sql_inline_only_count <- .sql_inline_only_count + 1L
    query_library[[i]]$sql_source <- "inline"
    query_library[[i]]$sql_loaded_path <- NA_character_

  } else {
    .sql_failed_count <- .sql_failed_count + 1L
    .sql_failed_items <- c(
      .sql_failed_items,
      sprintf("ID: %s | Hata: ne sql_file ne de sql tanimli", q_id)
    )

    cat(sprintf(
      "[SQL_LOADER] HATA: Sorguda ne sql_file ne de sql tanimli! ID: %s\n",
      q_id
    ))
  }
}

cat(sprintf("[SQL_LOADER] sql_file sayisi = %d\n", .sql_file_declared_count))
cat(sprintf("[SQL_LOADER] dosyadan yuklenen sayi = %d\n", .sql_loaded_count))
cat(sprintf("[SQL_LOADER] inline-only sayisi = %d\n", .sql_inline_only_count))
cat(sprintf("[SQL_LOADER] uzerine yazilan sql sayisi = %d\n", .sql_overwritten_count))
cat(sprintf("[SQL_LOADER] basarisiz sayi = %d\n", .sql_failed_count))

if (.sql_failed_count > 0L) {
  cat("[SQL_LOADER] BASARISIZ OGELER:\n")
  for (item in .sql_failed_items) {
    cat(sprintf("[SQL_LOADER] - %s\n", item))
  }

  stop(sprintf(
    "[SQL_LOADER] HATA: %d adet SQL yuklenemedi. Uygulama durduruluyor.",
    .sql_failed_count
  ))
}

cat(sprintf(
  "[SQL_LOADER] Tamamlandi: %d/%d sql_file dosyadan zorunlu yuklendi, %d sorgu inline-only.\n",
  .sql_loaded_count, .sql_file_declared_count, .sql_inline_only_count
))

# --- GECICI NESNELERI TEMIZLE ---
rm(
  .SQL_LOADER_DEBUG,
  .sql_total_count,
  .sql_file_declared_count,
  .sql_inline_only_count,
  .sql_loaded_count,
  .sql_failed_count,
  .sql_overwritten_count,
  .sql_missing_id_count,
  .sql_failed_items,
  .sql_has_text,
  .resolve_sql_file_path,
  .remove_utf8_bom,
  .read_sql_file_text
)