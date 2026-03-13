# ==============================================================================
# R/config_sql_loader.R
# Dosya Yolu: R/config_sql_loader.R
# Açıklama: SQL dosyalarını query_library üzerinden ön yükleme ve BOM temizliği.
# global.R tarafından library_queries.R yüklendikten sonra source() ile çağrılır.
# ==============================================================================

# --- HATA AYIKLAMA MODU KONTROLÜ ---
.SQL_LOADER_DEBUG <- isTRUE(as.logical(Sys.getenv("MERGEN_DEBUG", "FALSE")))

# --- SQL DOSYALARINI ÖN YÜKLEME ---
# library_queries.R dosyasının yüklü olduğundan emin ol
if (!exists("query_library")) {
  safe_source("R/library_queries.R", encoding = "UTF-8")
}

.sql_loaded_count <- 0L
.sql_failed_count <- 0L

for (i in seq_along(query_library)) {
  q_item <- query_library[[i]]

  if (!is.null(q_item$sql_file) && (is.null(q_item$sql) || !nzchar(q_item$sql))) {

    fpath <- q_item$sql_file
    fpath_abs <- tryCatch(
      normalizePath(fpath, winslash = "/", mustWork = FALSE),
      error = function(e) fpath
    )

    file_found <- FALSE
    path_to_use <- NULL

    if (file.exists(fpath)) {
      file_found <- TRUE
      path_to_use <- fpath
    } else if (file.exists(fpath_abs)) {
      file_found <- TRUE
      path_to_use <- fpath_abs
    }

    if (file_found) {
      lines <- readLines(path_to_use, warn = FALSE, encoding = "UTF-8")
      full_sql <- paste(lines, collapse = "\n")

      # BOM (Byte Order Mark) temizliği
      full_sql <- gsub("^\ufeff", "", full_sql)

      query_library[[i]]$sql <- full_sql
      .sql_loaded_count <- .sql_loaded_count + 1L

      # Detaylı bilgi sadece hata ayıklama modunda
      if (.SQL_LOADER_DEBUG) {
        cat(sprintf("[SQL_LOADER] OK: %s (%s) -> %d karakter\n",
                    q_item$id, q_item$sql_file, nchar(full_sql)))
      }

    } else {
      .sql_failed_count <- .sql_failed_count + 1L
      # Başarısız yüklemeler her zaman loglanır
      cat(sprintf("[SQL_LOADER] HATA: SQL dosyasi bulunamadi! ID: %s, Yol: %s\n",
                  q_item$id, q_item$sql_file))
      if (.SQL_LOADER_DEBUG) {
        cat(sprintf("[SQL_LOADER] Calisma dizini: %s\n", getwd()))
        cat(sprintf("[SQL_LOADER] Denenen yollar: '%s', '%s'\n", fpath, fpath_abs))
      }
    }
  }
}

# Özet bilgi her zaman gösterilir
if (.sql_loaded_count > 0 || .sql_failed_count > 0) {
  cat(sprintf("[SQL_LOADER] Tamamlandi: %d dosyadan yuklendi, %d basarisiz\n",
              .sql_loaded_count, .sql_failed_count))
} else {
  cat("[SQL_LOADER] Harici SQL dosyasi yok, tum sorgular satir ici tanimli.\n")
}

# Geçici değişkenleri temizle
rm(.sql_loaded_count, .sql_failed_count, .SQL_LOADER_DEBUG)