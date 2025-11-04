# R/helpers_rdata_metadata.R
# -------------------------------------------------------------
# RData Metadata Yönetimi - Basit ve Sağlam
# -------------------------------------------------------------

helpers_rdata_metadata <- new.env(parent = globalenv())

# =============================================================================
# 1. SÜTUN METADATA TABLOSUNU OLUŞTUR
# =============================================================================

helpers_rdata_metadata$create_metadata_table <- function(con) {
  cat("[METADATA] Metadata tablosu oluşturuluyor...\n")
  
	sql <- "
	CREATE TABLE IF NOT EXISTS rd_column_metadata (
	  column_name VARCHAR PRIMARY KEY,
	  data_type VARCHAR,
	  sample_values TEXT, -- JSON string (dizi), sürücü uyumlu
	  null_count INTEGER,
	  non_null_count INTEGER,
	  distinct_count INTEGER,
	  min_value DOUBLE,
	  max_value DOUBLE,
	  is_metric BOOLEAN DEFAULT FALSE,
	  is_dimension BOOLEAN DEFAULT FALSE,
	  search_text VARCHAR,  -- lowercase, türkçe karaktersiz, arama için
	  description TEXT,
	  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	"
  
  try(DBI::dbExecute(con, sql), silent = TRUE)
  cat("[METADATA] Metadata tablosu hazır.\n")
  invisible(TRUE)
}

# =============================================================================
# 2. FACT_UNIVERSE'DEN METADATA TOPLA
# =============================================================================

helpers_rdata_metadata$refresh_metadata <- function(con) {
  cat("[METADATA] Metadata yenileniyor...\n")
  
  # fact_universe'deki tüm sütunları al
  info <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
  if (inherits(info, "try-error") || !nrow(info)) {
    cat("[METADATA] HATA: fact_universe bulunamadı!\n")
    return(invisible(FALSE))
  }
  
  cols <- as.character(info$name)
  cat("[METADATA] Bulunan sütun sayısı:", length(cols), "\n")
  
  # Metadata tablosunu temizle
  try(DBI::dbExecute(con, "DELETE FROM rd_column_metadata"), silent = TRUE)
  
  # Her sütun için metadata topla
  for (col in cols) {
    cat("  - Analiz ediliyor:", col, "\n")
    
    # Güvenli sütun adı
    col_quoted <- DBI::dbQuoteIdentifier(con, col)
    
    # Temel istatistikler
    stats_sql <- sprintf("
      SELECT 
        COUNT(*) AS total,
        COUNT(%s) AS non_null,
        COUNT(DISTINCT %s) AS distinct_count
      FROM fact_universe
    ", col_quoted, col_quoted)
    
    stats <- try(DBI::dbGetQuery(con, stats_sql), silent = TRUE)
    if (inherits(stats, "try-error")) next
    
    total_rows <- as.integer(stats$total[1])
    non_null <- as.integer(stats$non_null[1])
    null_count <- total_rows - non_null
    distinct_count <- as.integer(stats$distinct_count[1])
    
    # Örnek değerler (ilk 5)
    sample_sql <- sprintf("
      SELECT DISTINCT %s 
      FROM fact_universe 
      WHERE %s IS NOT NULL 
      LIMIT 5
    ", col_quoted, col_quoted)
    
    samples <- try(DBI::dbGetQuery(con, sample_sql), silent = TRUE)
    sample_values <- if (!inherits(samples, "try-error") && nrow(samples)) {
      as.character(samples[[1]])
    } else {
      character(0)
    }
    
    # Numerik mi kontrol et
    is_numeric <- FALSE
    min_val <- NA_real_
    max_val <- NA_real_
    
    numeric_test <- try({
      num_sql <- sprintf("
        SELECT 
          MIN(TRY_CAST(%s AS DOUBLE)) AS min_val,
          MAX(TRY_CAST(%s AS DOUBLE)) AS max_val,
          COUNT(TRY_CAST(%s AS DOUBLE)) AS num_count
        FROM fact_universe
      ", col_quoted, col_quoted, col_quoted)
      
      num_stats <- DBI::dbGetQuery(con, num_sql)
      
      if (num_stats$num_count[1] > (non_null * 0.8)) {  # %80'den fazlası sayısal ise
        is_numeric <- TRUE
        min_val <- num_stats$min_val[1]
        max_val <- num_stats$max_val[1]
      }
    }, silent = TRUE)
    
    # Metrik mi, boyut mu?
    is_metric <- is_numeric && distinct_count > 50  # Çok farklı değer varsa metrik
    is_dimension <- !is_metric  # Değilse boyut
    
    # Arama metni oluştur (türkçe karaktersiz, küçük harf)
    search_text <- tolower(stringi::stri_trans_general(col, "Latin-ASCII"))
    
    # Metadata'yı kaydet
	insert_sql <- "
	  INSERT INTO rd_column_metadata 
	  (column_name, data_type, sample_values, null_count, non_null_count, 
	   distinct_count, min_value, max_value, is_metric, is_dimension, search_text)
	  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"

	# Türkçe: Örnekleri JSON olarak sakla (sürücü uyumlu)
	samples_json <- jsonlite::toJSON(sample_values, auto_unbox = TRUE, null = "null", ensure_ascii = TRUE)

	DBI::dbExecute(con, insert_sql, params = list(
	  col,
	  if (is_numeric) "NUMERIC" else "VARCHAR",
	  samples_json,
	  null_count,
	  non_null,
	  distinct_count,
	  min_val,
	  max_val,
	  is_metric,
	  is_dimension,
	  search_text
	))
  }
  
  # Özet bilgi
  summary_sql <- "
    SELECT 
      COUNT(*) AS total_columns,
      SUM(CASE WHEN is_metric THEN 1 ELSE 0 END) AS metric_count,
      SUM(CASE WHEN is_dimension THEN 1 ELSE 0 END) AS dimension_count
    FROM rd_column_metadata
  "
  summary <- DBI::dbGetQuery(con, summary_sql)
  
  cat("[METADATA] Tamamlandı!\n")
  cat("[METADATA] Toplam sütun:", summary$total_columns[1], "\n")
  cat("[METADATA] Metrik:", summary$metric_count[1], "\n")
  cat("[METADATA] Boyut:", summary$dimension_count[1], "\n")
  
  invisible(TRUE)
}

# =============================================================================
# 3. SÜTUN ARAMA
# =============================================================================

helpers_rdata_metadata$search_columns <- function(con, query, limit = 10) {
  # Türkçe karaktersiz arama
  query_norm <- tolower(stringi::stri_trans_general(query, "Latin-ASCII"))
  
  sql <- sprintf("
    SELECT 
      column_name,
      data_type,
      is_metric,
      is_dimension,
      sample_values,
      distinct_count,
      non_null_count
    FROM rd_column_metadata
    WHERE search_text LIKE '%%%s%%'
    ORDER BY 
      CASE WHEN search_text = '%s' THEN 0 ELSE 1 END,  -- Tam eşleşme önce
      CASE WHEN is_metric THEN 0 ELSE 1 END,  -- Metrikler önce
      non_null_count DESC
    LIMIT %d
  ", query_norm, query_norm, as.integer(limit))
  
  DBI::dbGetQuery(con, sql)
}

# =============================================================================
# 4. TAM SÜTUN ADI BUL (Fuzzy Matching)
# =============================================================================

helpers_rdata_metadata$find_exact_column <- function(con, partial_name) {
  # Önce metadata'da ara
  all_cols <- DBI::dbGetQuery(con, "SELECT column_name, search_text FROM rd_column_metadata")
  
  partial_norm <- tolower(stringi::stri_trans_general(partial_name, "Latin-ASCII"))
  
  # 1. Tam eşleşme
  exact_match <- all_cols$column_name[all_cols$search_text == partial_norm]
  if (length(exact_match)) return(exact_match[1])
  
  # 2. Başlangıç eşleşmesi
  starts_with <- all_cols$column_name[startsWith(all_cols$search_text, partial_norm)]
  if (length(starts_with)) return(starts_with[1])
  
  # 3. İçerik eşleşmesi
  contains <- all_cols$column_name[grepl(partial_norm, all_cols$search_text, fixed = TRUE)]
  if (length(contains)) return(contains[1])
  
  # 4. Fuzzy matching (Levenshtein distance)
  if (requireNamespace("stringdist", quietly = TRUE)) {
    distances <- stringdist::stringdist(partial_norm, all_cols$search_text, method = "jw")
    best_match_idx <- which.min(distances)
    if (length(best_match_idx) && distances[best_match_idx] < 0.3) {
      return(all_cols$column_name[best_match_idx])
    }
  }
  
  NULL  # Bulunamadı
}

# =============================================================================
# 5. METRİK VE BOYUT LİSTELERİ
# =============================================================================

helpers_rdata_metadata$get_all_metrics <- function(con) {
  sql <- "SELECT column_name FROM rd_column_metadata WHERE is_metric = TRUE ORDER BY non_null_count DESC"
  result <- DBI::dbGetQuery(con, sql)
  result$column_name
}

helpers_rdata_metadata$get_all_dimensions <- function(con) {
  sql <- "SELECT column_name FROM rd_column_metadata WHERE is_dimension = TRUE ORDER BY distinct_count ASC"
  result <- DBI::dbGetQuery(con, sql)
  result$column_name
}

# =============================================================================
# 6. HİZLI İSTATİSTİK
# =============================================================================

helpers_rdata_metadata$get_column_stats <- function(con, column_name) {
  sql <- "SELECT * FROM rd_column_metadata WHERE column_name = ?"
  DBI::dbGetQuery(con, sql, params = list(column_name))
}
