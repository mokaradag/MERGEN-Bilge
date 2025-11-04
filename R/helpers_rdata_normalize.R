# R/helpers_rdata_normalize.R
# -------------------------------------------------------------
# Veri Normalizasyonu ve JOIN Mantığı
# Staging tablolarını doğru şekilde birleştir
# -------------------------------------------------------------

helpers_rdata_normalize <- new.env(parent = globalenv())

# =============================================================================
# TABLOLARIN ORTAK ANAHTARLARINI BUL
# =============================================================================

helpers_rdata_normalize$find_join_keys <- function(con, tables) {
  # Her tablonun sütunlarını al
  all_cols <- list()
  for (tbl in tables) {
    info <- try(DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s)", tbl)), silent = TRUE)
    if (!inherits(info, "try-error") && nrow(info)) {
      all_cols[[tbl]] <- as.character(info$name)
    }
  }
  
  if (length(all_cols) < 2) return(NULL)
  
  # Ortak sütunları bul
  common_cols <- Reduce(intersect, all_cols)
  
  # Tipik ID sütunları (öncelik sırası)
  priority_keys <- c(
    "ProjeKodu", "ProjeAdi",  # Proje seviyes
    "SicilNo", "KaynakAdi",   # Kişi seviyesi
    "Yil", "Ay", "Donem",     # Zaman
    "AktiviteKodu"            # Aktivite
  )
  
  # Öncelikli olanları seç
  join_keys <- intersect(priority_keys, common_cols)
  
  if (!length(join_keys)) {
    # Öncelikli bulunamazsa, tüm ortak sütunları kullan
    join_keys <- common_cols
  }
  
  cat("[NORMALIZE] Bulunan join keys:", paste(join_keys, collapse = ", "), "\n")
  join_keys
}

# =============================================================================
# TABLOLARI JOIN İLE BİRLEŞTİR (UNION yerine)
# =============================================================================

helpers_rdata_normalize$build_joined_fact <- function(con, staging_tables, canon_cols) {
  # Join key'leri bul
  join_keys <- helpers_rdata_normalize$find_join_keys(con, staging_tables)
  
  if (is.null(join_keys) || !length(join_keys)) {
    cat("[NORMALIZE] Join keys bulunamadı, UNION ALL kullanılıyor\n")
    # Eski sisteme geri dön
    return(FALSE)
  }
  
  # Tablolarıİ grain'lerine göre grupla
  # (Aynı grain'deki tabloları birleştir)
  
  table_grains <- list()
  for (tbl in staging_tables) {
    # Her tablonun kaç tane join key'i var
    info <- try(DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s)", tbl)), silent = TRUE)
    if (inherits(info, "try-error")) next
    
    tbl_cols <- as.character(info$name)
    has_keys <- intersect(join_keys, tbl_cols)
    
    grain_sig <- paste(sort(has_keys), collapse = "_")
    if (!grain_sig %in% names(table_grains)) {
      table_grains[[grain_sig]] <- list()
    }
    table_grains[[grain_sig]] <- c(table_grains[[grain_sig]], tbl)
  }
  
  cat("[NORMALIZE] Bulunan grain grupları:", length(table_grains), "\n")
  for (g in names(table_grains)) {
    cat("  -", g, ":", length(table_grains[[g]]), "tablo\n")
  }
  
  # Her grain grubu için ayrı view oluştur
  # Sonra bunları UNION ALL yap
  
  # ... (Bu kısım fact_universe'in nasıl oluşturulduğuna bağlı)
  # Şimdilik mevcut sistemi bozma, sadece ileride kullanmak için hazırla
  
  return(FALSE)  # Henüz aktif değil
}

# =============================================================================
# VERİ KALİTESİ KONTROLÜ
# =============================================================================

helpers_rdata_normalize$check_data_quality <- function(con) {
  cat("[NORMALIZE] Veri kalitesi kontrolü...\n")
  
  # fact_universe'deki NULL oranları
  info <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
  if (inherits(info, "try-error")) return(invisible(FALSE))
  
  cols <- as.character(info$name)
  total_rows <- as.numeric(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM fact_universe")$n)
  
  null_stats <- data.frame(
    column = character(0),
    null_count = integer(0),
    null_pct = numeric(0),
    stringsAsFactors = FALSE
  )
  
  for (col in cols) {
    null_count <- DBI::dbGetQuery(con, sprintf(
      'SELECT COUNT(*) AS n FROM fact_universe WHERE "%s" IS NULL',
      col
    ))$n
    
    null_pct <- (null_count / total_rows) * 100
    
    null_stats <- rbind(null_stats, data.frame(
      column = col,
      null_count = null_count,
      null_pct = null_pct,
      stringsAsFactors = FALSE
    ))
  }
  
  # Çok fazla NULL olan sütunları raporla
  high_null <- null_stats[null_stats$null_pct > 80, ]
  if (nrow(high_null)) {
    cat("[NORMALIZE] UYARI: Aşağıdaki sütunlarda %80'den fazla NULL var:\n")
    print(high_null[order(-high_null$null_pct), ])
  }
  
  invisible(null_stats)
}
