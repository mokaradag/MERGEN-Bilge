# R/module_proje_kaynak_analizi.R

# Proje/Kaynak Analizi helper'ları büyük modül dışında tutulur.
pk_required_helpers <- list(
  list(
    functions = c("summarize_columns_for_ai", "normalize_sql_server_identifiers"),
    path = file.path("R", "helpers_pk_analysis_core.R")
  ),
  list(
    functions = c("extract_filter_criteria_from_prompt", "apply_smart_filters"),
    path = file.path("R", "helpers_pk_analysis_filters.R")
  )
)

for (helper_spec in pk_required_helpers) {
  missing_helpers <- vapply(
    helper_spec$functions,
    function(fn) !exists(fn, mode = "function", inherits = TRUE),
    logical(1)
  )

  if (!any(missing_helpers)) {
    next
  }

  if (!file.exists(helper_spec$path)) {
    stop(
      sprintf("%s bulunamadı; module_proje_kaynak_analizi.R yüklenemiyor.", helper_spec$path),
      call. = FALSE
    )
  }

  source(helper_spec$path, encoding = "UTF-8", local = globalenv())
}

rm(pk_required_helpers, helper_spec, missing_helpers)

# ==============================================================================
# 1. RLS ve YETKİ YÖNETİMİ (SECURITY ENGINE)
# ==============================================================================

get_user_rls_info <- function(username, conn) {
  cat(sprintf("[PK_ANALIZ] get_user_rls_info calistiriliyor. Kullanici: %s\n", username))
  
  # 1. DC01_user_base tablosundan temel yetkileri çek
  base_query <- "SELECT TOP 1 * FROM DC01_user_base WHERE KullaniciAdi = ?"
  user_base <- tryCatch({
    DBI::dbGetQuery(conn, base_query, params = list(username))
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] HATA (DC01_user_base): %s\n", e$message))
    return(data.frame())
  })
  
  if (nrow(user_base) == 0) {
    cat("[PK_ANALIZ] Kullanici DC01 tablosunda bulunamadi.\n")
    return(list(authorized = FALSE, reason = "Kullanıcı DC01 tablosunda bulunamadı."))
  }
  
  info <- as.list(user_base[1, ])
  info$authorized <- TRUE
  cat(sprintf("[PK_ANALIZ] Yetki Tipi: %s, MasrafYeri: %s\n", info$Yetki, info$MasrafYeriKodu))
  
  # Masraf Yeri (Department) Parse Et
  if (!is.na(info$MasrafYeriKodu) && info$MasrafYeriKodu != "ADMIN") {
    info$allowed_depts <- trimws(unlist(strsplit(as.character(info$MasrafYeriKodu), ",")))
  } else {
    info$allowed_depts <- NULL # ADMIN veya hepsi
  }
  
  # 2. Yetki Tipine Göre Ek Kısıtlamaları (PY, KY-P, DIR-P) Çek
  info$allowed_projects <- NULL
  info$allowed_eps <- NULL
  
  if (info$Yetki == "PY") {
    cat("[PK_ANALIZ] PY yetkisi kontrol ediliyor...\n")
    py_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_py), error = function(e) NULL)
    if (!is.null(py_res)) {
      user_rows <- py_res[py_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_projs <- paste(user_rows$ProjeKodu, collapse = ",")
        info$allowed_projects <- unique(trimws(unlist(strsplit(all_projs, ","))))
        cat(sprintf("[PK_ANALIZ] PY Projeleri: %s\n", paste(info$allowed_projects, collapse=",")))
      }
    }
  }
  
  if (info$Yetki %in% c("KY-P", "DIR-P")) {
    cat("[PK_ANALIZ] Program (EPS) yetkisi kontrol ediliyor...\n")
    eps_res <- tryCatch(DBI::dbGetQuery(conn, sql_permission_eps), error = function(e) NULL)
    if (!is.null(eps_res)) {
      user_rows <- eps_res[eps_res$KullaniciAdi == username, ]
      if (nrow(user_rows) > 0) {
        all_eps <- paste(user_rows$EPSKodu, collapse = ",")
        info$allowed_eps <- unique(trimws(unlist(strsplit(all_eps, ","))))
        cat(sprintf("[PK_ANALIZ] EPS Kodlari: %s\n", paste(info$allowed_eps, collapse=",")))
      }
    }
  }
  
  return(info)
}

apply_rls_to_data <- function(data, user_info, rls_cols) {
  if (nrow(data) == 0) return(data)
  
  cat(sprintf("[PK_ANALIZ] RLS Uygulaniyor. Ham satir sayisi: %d\n", nrow(data)))
  filtered_data <- data
  yetki <- user_info$Yetki
  
  if (yetki == "ADMIN") {
    cat("[PK_ANALIZ] Rol ADMIN -> Filtre uygulanmadi.\n")
    return(filtered_data)
  }
  
  # Masraf Yeri Filtresi
  if (!is.null(user_info$allowed_depts) && !is.null(rls_cols$masraf_yeri_col)) {
    col_name <- rls_cols$masraf_yeri_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_depts, ]
      cat(sprintf("[PK_ANALIZ] Masraf Yeri Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  # PY Filtresi
  if (yetki == "PY" && !is.null(user_info$allowed_projects) && !is.null(rls_cols$proje_kodu_col)) {
    col_name <- rls_cols$proje_kodu_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_projects, ]
      cat(sprintf("[PK_ANALIZ] PY Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  # EPS Filtresi
  if (yetki %in% c("KY-P", "DIR-P") && !is.null(user_info$allowed_eps) && !is.null(rls_cols$eps_kodu_col)) {
    col_name <- rls_cols$eps_kodu_col
    if (col_name %in% names(filtered_data)) {
      filtered_data <- filtered_data[filtered_data[[col_name]] %in% user_info$allowed_eps, ]
      cat(sprintf("[PK_ANALIZ] EPS Filtresi Sonrasi: %d satir\n", nrow(filtered_data)))
    }
  }
  
  return(filtered_data)
}

generate_statistical_summary <- function(data, max_preview_rows = 20, max_total_chars = MAX_ANALYSIS_PROMPT_CHARS, mode = "summary", rls_total_rows = NULL, user_filter_applied = FALSE, pre_aggregated_columns = NULL) {
  # Kolon adlarını okunabilir hale getirme fonksiyonu
  prettify_col_name <- function(col) {
    # CamelCase ayırma
    col <- gsub("([a-z])([A-Z])", "\\1 \\2", col)
    # Alt çizgi ve noktaları boşluk yap
    col <- gsub("_|\\.", " ", col)
    # Baş harfleri büyük yap
    col <- gsub("\\b([a-z])", "\\U\\1", col, perl = TRUE)
    return(col)
  }
  
  if (is.null(data) || nrow(data) == 0) {
    return(list(
      summary_text = "Veri yok.",
      row_count = 0,
      preview_data = NULL
    ))
  }
  
  total_rows <- nrow(data)
  total_cols <- ncol(data)
  col_names <- names(data)
  
  dt <- data.table::as.data.table(data)
  
  num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
  cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]

  # Önceden toplulaştırılmış sütunları sayısal özetten çıkar
  pre_agg_cols <- character(0)
  if (!is.null(pre_aggregated_columns) && length(pre_aggregated_columns) > 0) {
    pre_agg_cols <- intersect(pre_aggregated_columns, num_cols)
    if (length(pre_agg_cols) > 0) {
      num_cols <- setdiff(num_cols, pre_agg_cols)
      cat(sprintf("[PK_ANALIZ] Önceden toplulaştırılmış sütunlar istatistik özetinden çıkarıldı: %s\n",
                  paste(pre_agg_cols, collapse = ", ")))
    }
  }

  summary_parts <- list()
  summary_parts[[1]] <- sprintf("TOPLAM SATIR: %d | TOPLAM SUTUN: %d", total_rows, total_cols)
  
  if (isTRUE(user_filter_applied) && !is.null(rls_total_rows) && rls_total_rows > total_rows) {
    summary_parts[[length(summary_parts) + 1]] <- sprintf(
      "\n\n\U000026A0\U0000FE0F FİLTRELEME UYARISI:\n- Yetki dahilinde toplam satır: %d\n- Kullanıcı filtreleme sonrası satır: %d\n- BU %d SATIR SPESİFİK FİLTRELEME KRİTERİNE AİTTİR (tüm veri için değil!)\n- Oran/yüzde hesaplarken SADECE filtreleme sonrası %d satırı referans al",
      rls_total_rows, total_rows, total_rows, total_rows
    )
  }

  # Önceden toplulaştırılmış sütunlar hakkında AI'a uyarı ekle
  if (length(pre_agg_cols) > 0) {
    pretty_names <- vapply(pre_agg_cols, prettify_col_name, character(1))
    summary_parts[[length(summary_parts) + 1]] <- sprintf(
      paste0(
        "\n\n\U000026A0\U0000FE0F ÖNCEDEN TOPLULAŞTIRILMIŞ SÜTUN UYARISI:\n",
        "Aşağıdaki sütunlar SQL sorgusunda zaten toplulaştırılmıştır (SUM/AVG/COUNT OVER PARTITION BY vb.):\n",
        "- %s\n",
        "Bu sütunlardaki değerler satırlar arasında tekrar edebilir.\n",
        "ASLA bu sütunlara toplam, ortalama veya herhangi bir istatistiksel özet hesaplama UYGULAMA.\n",
        "Bu sütunları YALNIZCA satır bazında yorumla, olduğu gibi aktar."
      ),
      paste(pretty_names, collapse = ", ")
    )
  }
  
	if (length(num_cols) > 0) {
	  num_summary_list <- lapply(num_cols, function(col) {
		vals <- dt[[col]]
		vals <- vals[!is.na(vals)]
		if (length(vals) == 0) return(NULL)
		
		data.frame(
		  Sutun = prettify_col_name(col),
		  Toplam = sum(vals, na.rm = TRUE),
		  Ortalama = mean(vals, na.rm = TRUE),
		  Medyan = median(vals, na.rm = TRUE),
		  Min = min(vals, na.rm = TRUE),
		  Max = max(vals, na.rm = TRUE),
		  StdSapma = sd(vals, na.rm = TRUE),
		  Kayit = length(vals),
		  stringsAsFactors = FALSE
		)
	  })
    
    num_summary_df <- do.call(rbind, Filter(Negate(is.null), num_summary_list))
    
    if (!is.null(num_summary_df) && nrow(num_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nSAYISAL SUTUNLAR OZETI:"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(num_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }
  
  date_cols <- names(dt)[vapply(dt, function(x) inherits(x, "Date") || inherits(x, "POSIXt"), logical(1))]
  if (length(date_cols) > 0) {
    date_summary_list <- lapply(date_cols, function(col) {
      vals <- dt[[col]]
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(NULL)
      
      data.frame(
        Sutun = prettify_col_name(col),
        EnEskiTarih = as.character(min(vals)),
        EnYeniTarih = as.character(max(vals)),
        KayitSayisi = length(vals),
        stringsAsFactors = FALSE
      )
    })
    
    date_summary_df <- do.call(rbind, Filter(Negate(is.null), date_summary_list))
    
    if (!is.null(date_summary_df) && nrow(date_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nTARIH SUTUNLARI OZETI (TUM VERİ UZERINDEN):"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(date_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }
  
	if (length(cat_cols) > 0) {
	  cat_summary_list <- lapply(head(cat_cols, 5), function(col) {
		tbl <- sort(table(dt[[col]], useNA = "no"), decreasing = TRUE)
		top5 <- head(tbl, 5)
		
		# FIX: If top5 is empty, return NULL to skip this column
		if (length(top5) == 0) {
		  return(NULL)
		}
		
		# FIX: Handle potential NA in names explicitly
		top_name <- names(top5)[1]
		if (is.null(top_name) || is.na(top_name)) top_name <- "Yok"
		
		data.frame(
		  Sutun = prettify_col_name(col),
		  EnSikDeger = top_name,
		  Adet = as.integer(top5[1]),
		  BenzerSayi = length(unique(dt[[col]])),
		  stringsAsFactors = FALSE
		)
	  })
    
    # Remove NULL results before rbind (Prevents list of NULLs crashing rbind)
    cat_summary_list <- Filter(Negate(is.null), cat_summary_list)
    cat_summary_df <- do.call(rbind, cat_summary_list)
    
    if (!is.null(cat_summary_df) && nrow(cat_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nKATEGORIK SUTUNLAR OZETI:"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(cat_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }
  
  preview_data <- NULL
  if (mode == "full") {
    full_table_md <- paste0(
      "+===============================================================+\n",
      "|           DETAYLI İSTATİSTİKSEL ANALİZ MODU                 |\n",
      "+===============================================================+\n\n",
      "AŞAĞIDAKİ TÜM SÜTUNLARI DETAYLI ANALİZ ET!\n\n"
    )
    
    full_table_md <- paste0(full_table_md, sprintf("**Toplam Satır Sayısı:** %d | **Toplam Sütun Sayısı:** %d\n", total_rows, total_cols))
    
    if (total_rows > 0) {
      cat_summary <- paste0("\n**Örnek Veri Yapısı (İlk 3 Satır):**\n")
      preview_rows <- head(data, min(3, nrow(data)))
      for (i in seq_len(nrow(preview_rows))) {
        row_data <- paste0(names(preview_rows), ": ", sapply(preview_rows[i, ], as.character), collapse = " | ")
        cat_summary <- paste0(cat_summary, sprintf("Satır %d: %s\n", i, row_data))
      }
      full_table_md <- paste0(full_table_md, cat_summary)
    }
    
    summary_parts[[1]] <- full_table_md
    preview_data <- head(data, min(5, nrow(data)))
  } else {
    if (total_rows > max_preview_rows) {
      preview_data <- head(data, max_preview_rows)
      summary_parts[[length(summary_parts) + 1]] <- sprintf("\n\n(İlk %d satir gosteriliyor; toplam %d satir mevcut)", max_preview_rows, total_rows)
    } else {
      preview_data <- data
    }
  }
  
  # Prompt boyutunu kontrol et ve gerektiğinde kırp
  current_text <- paste(summary_parts, collapse = "\n")
  if (nchar(current_text) > max_total_chars) {
    cat(sprintf("[PK_ANALIZ] UYARI: Prompt çok büyük (%d karakter), kırpılıyor.\n", nchar(current_text)))
    # Önce preview satır sayısını yarıya indir
    if (max_preview_rows > 5) {
      return(generate_statistical_summary(data, max_preview_rows = floor(max_preview_rows / 2), max_total_chars = max_total_chars, pre_aggregated_columns = pre_aggregated_columns))
    }
    # Eğer hala büyükse, sadece temel özet gönder
    basic_summary <- sprintf("TOPLAM SATIR: %d | TOPLAM SUTUN: %d", total_rows, total_cols)
    return(list(
      summary_text = basic_summary,
      row_count = total_rows,
      preview_data = head(data, 5)
    ))
  }
  
  summary_text <- paste(summary_parts, collapse = "\n")
  
  return(list(
    summary_text = summary_text,
    row_count = total_rows,
    preview_data = preview_data
  ))
}

# ==============================================================================
# 2. SORGULAMA MOTORU (EXECUTION ENGINE)
# ==============================================================================

pk_analiz_process_request <- function(user_prompt, chat_history, session, stop_check = NULL) {
  cat("\n[PK_ANALIZ] >>> pk_analiz_process_request BASLATILDI <<<\n")
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (baslangic)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  cat(sprintf("[PK_ANALIZ] Kullanici Prompt: '%s'\n", user_prompt))
  
  # A. Bağlantı Kur
  cat("[PK_ANALIZ] DB Baglantisi aliniyor...\n")
  conn_list <- get_connection()
  conn <- conn_list$conn
  on.exit({
    cat("[PK_ANALIZ] DB Baglantisi serbest birakiliyor.\n")
    release_connection(conn_list)
  })
  
  username <- session$userData$system_username %||% "Unknown"
  
  # B. Kullanıcı RLS Bilgisini Çek
  rls_info <- get_user_rls_info(username, conn)
  if (!isTRUE(rls_info$authorized)) {
    cat("[PK_ANALIZ] Yetki Hatasi: Kullanici bulunamadi.\n")
    return("\U000026A0\U0000FE0F **Yetki Hatası:** Sistemde kullanıcı kaydınız (DC01_user_base) bulunamadı. Lütfen yönetici ile iletişime geçin.")
  }
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (RLS sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  cat("[PK_ANALIZ] Akilli sorgu secimi yapiliyor (select_smart_query)...\n")
  selected_query <- select_smart_query(user_prompt, query_library, chat_history)
  
  if (is.null(selected_query) || (!is.null(selected_query$all_scores) && is.null(selected_query$id))) {
    cat("[PK_ANALIZ] UYARI: Uygun bir sorgu ESLESMESI BULUNAMADI.\n")
    
    if (!is.null(selected_query$all_scores)) {
      best_score <- max(selected_query$all_scores$final_score, na.rm = TRUE)
      best_idx <- which.max(selected_query$all_scores$final_score)
      best_name <- if (length(best_idx) > 0) selected_query$all_scores$query_name[best_idx] else "?"
      cat(sprintf("[PK_ANALIZ] En yuksek skor: %.1f%% - '%s' (Esik altinda kaldi)\n", best_score, best_name))
      
      if (best_score >= 20) {
        cat("[PK_ANALIZ] Dusuk guvenle en yakin sorgu seciliyor (fallback)...\n")
        fallback_query <- query_library[[best_idx]]
        fallback_query$relevance_score <- best_score
        fallback_query$selection_method <- "fallback"
        fallback_query$selection_reason <- "Dusuk esik skoru - en yakin eslesme"
        fallback_query$all_scores <- selected_query$all_scores
        selected_query <- fallback_query
      }
    }
    
    if (is.null(selected_query$id)) {
      return("\U0001F914 Aradığınız bilgi mevcut analiz kütüphanesinde bulunamadı. Lütfen sorunuzu farklı kelimelerle tekrar deneyin veya mevcut analiz kategorilerini inceleyin.")
    }
  }
  
  relevance_pct <- selected_query$relevance_score %||% 0
  method <- selected_query$selection_method %||% "unknown"
  reason <- selected_query$selection_reason %||% ""
  
  cat(sprintf("[PK_ANALIZ] Secilen Sorgu: '%s' | İlgililik: %.1f%% | Yontem: %s\n", 
              selected_query$name, relevance_pct, method))
  if (nchar(reason) > 0) {
    cat(sprintf("[PK_ANALIZ] Secim Nedeni: %s\n", reason))
  }
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (sorgu secimi sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  cat(sprintf("[PK_ANALIZ] Secilen Sorgu: '%s' (Table: %s)\n", selected_query$name, selected_query$description))
   
	# 1. SQL icerigini belirle
	# SQL artik startup sirasinda R/config_sql_loader.R tarafindan yukleniyor.
	# Burada dosyayi yeniden okumuyoruz; dogrudan preload edilmis sql alanini kullaniyoruz.
	sql_query_text <- selected_query$sql %||% ""

	if (!nzchar(trimws(sql_query_text))) {
	  if (!is.null(selected_query$sql_file) && nzchar(selected_query$sql_file)) {
		cat(sprintf("[PK_ANALIZ] HATA: Startup sirasinda preload edilmis SQL bos. Dosya: %s\n", selected_query$sql_file))
		return(paste0(
		  "\u26A0\uFE0F **Yapılandırma Hatası:** SQL dosyası startup sırasında yüklenmemiş görünüyor. Dosya: ",
		  selected_query$sql_file
		))
	  }

	  cat("[PK_ANALIZ] HATA: selected_query$sql bos.\n")
	  return("\u26A0\uFE0F **Yapılandırma Hatası:** Sorgu için SQL kodu bulunamadı.")
	}

	sql_query_text <- as.character(sql_query_text)[1]
	sql_query_text <- enc2utf8(sql_query_text)

	# BOM temizligi
	bom_char <- intToUtf8(65279L)
	if (startsWith(sql_query_text, bom_char)) {
	  sql_query_text <- substring(sql_query_text, 2L)
	}

	# Satir sonlarini normalize et
	sql_query_text <- gsub("\r\n?|\r", "\n", sql_query_text, perl = TRUE)

	cat(sprintf("[PK_ANALIZ] Preload edilmis SQL kullaniliyor. Uzunluk: %d karakter\n", nchar(sql_query_text)))
	cat(sprintf("[PK_ANALIZ] SQL baslangici:\n%s\n[...]\n", substr(sql_query_text, 1, 200)))

	if (grepl("^[a-zA-Z]:[\\\\/]|^[\\\\/]{2}|^\\./|^\\.\\./|^[^/\\\\]+[\\\\/]", sql_query_text)) {
	  cat("[PK_ANALIZ] KRITIK HATA: sql_query_text dosya yolu iceriyor!\n")
	  cat(sprintf("[PK_ANALIZ] Icerik: %s\n", substr(sql_query_text, 1, 300)))
	  return("\u26A0\uFE0F **Sistem Hatası:** SQL sorgusu yüklenemedi (dosya yolu algılandı).")
	}

	if (nchar(sql_query_text) < 10 || !grepl("SELECT|INSERT|UPDATE|DELETE|EXEC", sql_query_text, ignore.case = TRUE)) {
	  cat("[PK_ANALIZ] HATA: Gecersiz SQL icerigi!\n")
	  cat(sprintf("[PK_ANALIZ] Icerik: %s\n", substr(sql_query_text, 1, 200)))
	  return("\u26A0\uFE0F **Sistem Hatası:** Geçersiz SQL sorgusu yüklendi.")
	}

	target_db <- selected_query$db_target %||% DB_TARGETS$PRIMARY %||% "primary"
	target_db <- tolower(trimws(as.character(target_db)[1]))
	if (!nzchar(target_db)) target_db <- "primary"

	if (!is.null(target_db) && target_db != "primary") {
	   cat(sprintf("[PK_ANALIZ] Hedef DB 'primary' degil (%s). Baglanti degistiriliyor...\n", target_db))
	   
	   release_connection(conn_list)
	   
	   conn_list <- get_connection(target = target_db)
	   conn <- conn_list$conn
	}

	# SQL metnini parametre donusumunden gecirme.
	# normalize_db_value() parametreler icin uygundur; tam SQL metni icin kullanilmaz.
	final_sql <- trimws(sql_query_text)
	final_sql <- enc2utf8(final_sql)

	cat(sprintf("[PK_ANALIZ] SQL DB'ye gonderiliyor (Ilk 100 kar.):\n--> %s...\n", substr(final_sql, 1, 100)))

	raw_data <- tryCatch({
	  if (grepl("\\b(DELETE|DROP|TRUNCATE|ALTER)\\b", toupper(final_sql))) {
		stop("Guvenlik ihlali: Yasakli SQL komutu.")
	  }

	  execute_pk_sql_unicode(conn, final_sql)

	}, error = function(e) {
	  err_msg <- conditionMessage(e)

	  cat(sprintf(
		"[PK_ANALIZ] SQL HATASI | DB: %s | Sorgu ID: %s | Sorgu Adi: %s\n",
		selected_query$db_target %||% "primary",
		selected_query$id %||% "?",
		selected_query$name %||% "?"
	  ))
	  cat(sprintf(
		"[PK_ANALIZ] SQL HATASI | SQL dosyasi: %s\n",
		selected_query$sql_file %||% "inline"
	  ))
	  cat(sprintf("[PK_ANALIZ] SQL HATASI DETAY: %s\n", err_msg))
	  cat(sprintf("[PK_ANALIZ] SQL ILK 500 KARAKTER:\n%s\n", substr(final_sql, 1, 500)))

	  return(paste0(
		"\u26A0\uFE0F **Veritabanı Hatası:** Sorgu çalıştırılırken hata oluştu.\n`",
		err_msg,
		"`"
	  ))
	})
  
  if (is.character(raw_data) && startsWith(raw_data, "\U000026A0\U0000FE0F")) return(raw_data)
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (SQL sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
	raw_data <- normalize_pk_dataframe_utf8(raw_data)

	cat(sprintf("[PK_ANALIZ] SQL Basarili. Dönen Satir: %d\n", nrow(raw_data)))
	cat("[PK_ANALIZ] SQL sonucu UTF-8 normalize edildi.\n")
  
  if (!is.null(selected_query$date_columns)) {
    raw_data <- convert_date_columns(raw_data, selected_query$date_columns)
  }
  
  secure_data <- apply_rls_to_data(raw_data, rls_info, selected_query$rls_columns)
  cat(sprintf("[PK_ANALIZ] RLS sonrasi: %d satir\n", nrow(secure_data)))
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (RLS sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  if (nrow(secure_data) == 0) {
      return(paste0("\U0001F50D **Sonuc:** Sorgu calistirildi ancak yetkiniz dahilinde veri bulunamadi."))
  }
    
  # AI fonksiyonuna veriyi de gonderiyoruz ki degerleri gorebilsin
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (filtreleme oncesi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
  
  if (isTRUE(selected_query$disable_ai_filters)) {
    cat("[PK_ANALIZ] Ozel Sorgu Ayari: AI Filtreleme devre disi birakildi. Sadece RLS verisi kullaniliyor.\n")
    filter_criteria <- list(filters = list(), aggregation = NULL)
    filtered_data <- secure_data
	} else {
	available_columns <- names(secure_data)
    filter_criteria <- extract_filter_criteria_from_prompt(user_prompt, secure_data, available_columns, conn, session, stop_check = stop_check)
  
    if (!is.null(filter_criteria$error)) {
      cat(sprintf("[PK_ANALIZ] AI filtreleme hatasi: %s\n", filter_criteria$error))
    }
  
    cat(sprintf("[PK_ANALIZ] AI Filter Sonucu -> column: %s, value: %s, operation: %s, aggregation: %s\n",
                filter_criteria$filter_column %||% "NULL",
                filter_criteria$filter_value %||% "NULL",
                filter_criteria$operation %||% "NULL",
                filter_criteria$aggregation %||% "NULL"))
  
	filtered_data <- apply_smart_filters(secure_data, filter_criteria, user_prompt)
	filtered_data <- normalize_pk_dataframe_utf8(filtered_data)
  }
  
  cat(sprintf("[PK_ANALIZ] Filtreleme sonrası: %d satır (Orijinal: %d)\n", 
              nrow(filtered_data), nrow(secure_data)))
  
  if (is.function(stop_check) && isTRUE(stop_check())) {
    cat("[PK_ANALIZ] Durdurma talebi alindi (filtreleme sonrasi)\n")
    return("\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi.")
  }
			  
	if (nrow(filtered_data) < nrow(secure_data) * 0.05 && nrow(secure_data) > 100) {
	  cat("[PK_ANALIZ] UYARI: Filtreleme sonucu çok az veri kaldı (<%5). Kullanıcı gereksiz filtre uygulanmış olabilir.\n")
	}
  
  if (nrow(filtered_data) == 0) {
    cat("[PK_ANALIZ] Filtreleme sonrasi veri yok, islem tamamlandi.\n")
    return(list(
      type = "error_message",
      content = "\U0001F50D **Sonuç:** Filtreleme sonrası veri bulunamadı. Lütfen farklı kriterlerle tekrar deneyin."
    ))
  }
  
  analysis_mode <- selected_query$analysis_mode %||% "summary"
  user_filter_was_applied <- (nrow(filtered_data) < nrow(secure_data))
  
  dynamic_preview_rows <- if (nrow(filtered_data) <= 500) nrow(filtered_data) else 500
  
  stat_summary <- generate_statistical_summary(
    filtered_data,
    max_preview_rows = dynamic_preview_rows,
    mode = analysis_mode,
    rls_total_rows = nrow(secure_data),
    user_filter_applied = user_filter_was_applied,
    pre_aggregated_columns = selected_query$pre_aggregated_columns
  )
  
  cat(sprintf("[PK_ANALIZ] Istatistiksel ozet olusturuldu: %d satir, %d onizleme\n",
              stat_summary$row_count,
              if (!is.null(stat_summary$preview_data)) nrow(stat_summary$preview_data) else 0))
  
	preview_json <- if (!is.null(stat_summary$preview_data) && nrow(stat_summary$preview_data) > 0) {
	  preview_data_safe <- normalize_pk_dataframe_utf8(stat_summary$preview_data)
	  jsonlite::toJSON(preview_data_safe, auto_unbox = TRUE, pretty = FALSE, na = "null")
	} else {
	  "{}"
	}
  
  data_str <- paste0(
    stat_summary$summary_text,
    "\n\n--- ORNEK SATIRLAR (JSON) ---\n",
    preview_json,
    "\n\n(Not: Yukaridaki istatistikler ", stat_summary$row_count, " satirdan olusturulmustur)"
  )
  
  if (nrow(secure_data) > nrow(filtered_data)) {
    data_str <- paste0(
      data_str,
      sprintf("\n\n(RLS ve filtreleme oncesi toplam %d satir vardi)", nrow(secure_data))
    )
  }
  
  if (analysis_mode == "full") {
	system_prompt <- paste0(
      "Sen Primavera P6 ve SAP PS alanında 15+ yıl deneyimli, sektörde saygın bir veri analistisin. Fortune 500 şirketlerine danışmanlık yapan bir uzman gibi konuş - profesyonel, net ve eyleme dönük.\n\n",
      "Sorgu: ", selected_query$name, "\n",
      "Amaç: ", selected_query$description, "\n\n",
      "\U000026A0\U0000FE0F KRİTİK FİLTRELEME KURALI:\n",
      "Eğer veri setinde 'FİLTRELEME UYARISI' görüyorsan:\n",
      "- Verilen satır sayısı YALNIZCA kullanıcının spesifik filtreleme kriterine aittir\n",
      "- Bu, TÜM projelerin/TÜM veritabanının satır sayısı DEĞİLDİR\n",
      "- ASLA 'X/Y' formatında oran belirtme (örn: '5/4000 aktivite')\n",
      "- Bunun yerine: 'Bu proje/filtre için X kayıt bulundu' şeklinde ifade et\n",
      "- Yüzde hesaplarken payda olarak SADECE 'filtreleme sonrası satır' sayısını kullan\n\n",
      "ANALİZ KRİTERLERİ:\n",
      "1. DERİNLİK: Her sütunun hikayesini anlat - dağılım, anormallikler, eğilimler, sektör benchmarks'leri\n",
      "2. KÖK SEBEP: Gözlemlenen desenlerin ALTINDA YATAN operasyonel/finansal sebepleri veriyle destekle\n",
      "3. EYLEME DÖNÜK: Her bulgu için spesifik, uygulanabilir öneriler sun ve bu önerilerin iş etkisini sayısal olarak göster\n",
      "4. YERSELLEŞTİRME: Verileri şirketin gerçek operasyonel kontekstine bağla - teorik değil pratik yorumla\n",
      "5. TEMELLENDİRME: Sadece sağlanan verilerle konuş; varsayım, spekülasyon veya komik yorumlardan uzak dur\n",
      "6. TON: Doğal, akıcı Türkçe; robotik olmayan, güven veren uzman dili\n\n",
      "ZORUNLU YAPI:\n",
      "- **\U0001F4CB Özet**: 2-3 cümlede kritik bulgular ve iş etkisi\n",
      "- **\U0001F50D Detaylı İnceleme**: Her kritik sütun için ayrı bölüm (##)\n",
      "- **\U0001F3AF Kök Nedenler**: Neden-sonuç ilişkilerini veriyle kanıtla\n",
      "- **\U0001F4A1 Öneriler**: Önceliklendirilmiş, somut adımlar (1, 2, 3...)\n",
      "- **\U000026A0\U0000FE0F Dikkat Edilmesi Gerekenler**: Veride görünen potansiyel sorunları belirt\n\n",
      "TABLO FORMATI KURALI:\n",
      "- Kullanıcı listeleme, sıralama veya karşılaştırma istiyorsa sonuçları MUTLAKA markdown tablo formatında sun\n",
      "- Tablo formatı: | Sütun1 | Sütun2 | ... | şeklinde, başlık satırı ve ayırıcı ile\n",
      "- Tablolarda en önemli sütunları seç, gereksiz sütunları dahil etme\n\n",
      "KESİN KURALLAR:\n",
      "- Sayıları doğrudan kullan, yuvarlama veya tahmin YAPMA\n",
      "- Her yorum mutlaka veriye dayalı olmalı - hayal ürünü yorum yasak\n",
      "- Genel, yüzeysel yorumlardan kaçın\n",
      "- \"Görünüşe göre\", \"muhtemelen\", \"belki\" gibi belirsiz ifadeler KULLANMA\n",
      "- Kullanıcıya ait olmayan ifadelerden (biz, sizin) uzak dur\n"
    )
  } else {
	system_prompt <- paste0(
      "Sen MERGEN'in kıdemli veri analisti asistansın. R tarafından hazırlanan istatistiksel özet, senin tek gerçeğindir. Kullanıcıya değer üretmek için bu verileri derinlemesine yorumla.\n\n",
      "SORGU: ", selected_query$name, "\n",
      "AMACI: ", selected_query$description, "\n\n",
      "\U000026A0\U0000FE0F KRİTİK FİLTRELEME KURALI:\n",
      "Eğer istatistiksel özette 'FİLTRELEME UYARISI' görüyorsan:\n",
      "- Satır sayısı YALNIZCA kullanıcının spesifik filtreleme için geçerlidir\n",
      "- Tüm veri seti için geçerli değildir\n",
      "- ASLA 'X/Y oranında' veya 'toplam Y kayıttan X tanesi' gibi ifadeler kullanma\n",
      "- Bunun yerine: 'Bu filtre kriteri için X kayıt tespit edildi' de\n\n",
      "GÖREV:\n",
      "1. Özeti sadece tekrar etme - anlamını, içgörüsünü ve iş etkisini çıkar\n",
      "2. Her sayısal bulguyu KÖK SEBEP'e bağla: \"Neden bu sayı bu? Ne anlama geliyor?\"\n",
      "3. EYLEME DÖNÜK ÖNERİLER: \"Ne yapılmalı?\" sorusuna veriyle yanıt ver\n",
      "4. TEMELLENDİRME: Sadece sağlanan özetle konuş; varsayım, komik yorum veya spekülasyondan kaçın\n",
      "5. PROFESYONEL TON: Güvenilir, bilge, robotik olmayan dil\n\n",
      "ZORUNLU YAPI:\n",
      "- **\U0001F4CB Özet**: 2-3 cümlede kritik bulgular ve etki\n",
      "- **\U0001F4CA Analiz**: Verilerin hikayesini akıcı şekilde anlat\n",
      "- **\U0001F4A1 Öneriler**: Somut, önceliklendirilmiş eylemler\n",
      "- **\U000026A0\U0000FE0F Dikkat Çekenler**: Uç değerler, anormallikler, riskler\n\n",
      "TABLO FORMATI KURALI:\n",
      "- Kullanıcı listeleme, sıralama veya karşılaştırma istiyorsa sonuçları MUTLAKA markdown tablo formatında sun\n",
      "- Tablo formatı: | Sütun1 | Sütun2 | ... | şeklinde, başlık satırı ve ayırıcı ile\n",
      "- Tablolarda en önemli sütunları seç, gereksiz sütunları dahil etme\n\n",
      "KURALLAR:\n",
      "- Sayıları doğru kullan, tahmin veya varsayım yapma\n",
      "- Her yorumu veriye bağla - hayal ürünü yorum yasak\n",
      "- Yapıcı, çözüm odaklı ol\n",
      "- Kullanıcıya değer katan net ifadeler kullan\n",
      "- \"Muhtemelen\", \"sanırım\" gibi belirsizliklerden kaçın\n"
    )
  }

	if (!is.null(selected_query$info_file) && nzchar(selected_query$info_file)) {
	  file_path_normalized <- gsub("\\\\", "/", selected_query$info_file)
	  system_prompt <- paste0(system_prompt, 
		"\n8. EK DOSYA: Kullaniciya su dosyayi incelemesini oner. Cevabinin en altina su HTML linkini ekle: <br><br>\U0001F449 <span class='analysis-file-link' data-filepath='", file_path_normalized, "' style='color:#007bff; cursor:pointer; text-decoration:underline; font-weight:bold;'>İlgili Dosyayı Görüntüle</span>\n")
	}

	if (!is.null(selected_query$info_url) && nzchar(selected_query$info_url)) {
	  system_prompt <- paste0(system_prompt, 
		"\n9. EK LINK: Kullaniciya su adresi incelemesini oner. Cevabinin en altina su HTML linkini ekle: <br><br>\U0001F310 <a href='", selected_query$info_url, "' target='_blank' rel='noopener noreferrer'><b>Daha Fazla Bilgi</b></a>\n")
	}
  
  user_msg <- paste0(
    "KULLANICI SORUSU:\n",
    user_prompt,
    "\n\n--- R TARAFINDAN HAZIRLANAN ISTATISTIKSEL OZET ---\n",
    data_str,
    "\n\n--- OZET SONU ---\n\n",
    "Talımat: Yukaridaki istatistikleri kullanarak kullanicinin sorusuna DOGRUDAN cevap ver. ",
    "Sayilari AYNEN kullan. Trendleri ve onemli bulgulari vurgula."
  )
  
  cat("[PK_ANALIZ] AI baglami hazirlandi. List donduruluyor.\n")
  
  return(list(
    type = "data_analysis",
    data = secure_data,
    prompt_context = system_prompt,
    user_context = user_msg,
    query_name = selected_query$name,
    max_tokens = 4096
  ))
}

# ==============================================================================
# 3. AKILLI SORGU SEÇİMİ (AI + HEURISTIC HYBRID ENGINE)
# ==============================================================================

# AI Destekli Seçim Fonksiyonu
find_best_query_with_ai <- function(user_prompt, library, session) {
  cat("[PK_ANALIZ] AI tabanli sorgu secimi baslatiliyor...\n")
  
  # Kütüphane özetini hazırla
  library_context <- vapply(seq_along(library), function(i) {
    q <- library[[i]]
    sprintf("ID: %d | ISIM: %s | ACIKLAMA: %s", i, q$name, q$description)
  }, character(1))
  
  library_text <- paste(library_context, collapse = "\n")
  
  system_instruction <- paste0(
    "Sen bir Veritabani Sorgu Yonlendiricisisin. Kullanicinin Turkce sorusunu analiz edip EN UYGUN SQL sorgusunu sec.\n\n",
    
    "### MEVCUT SORGULAR:\n",
    library_text, "\n\n",
    
    "### ESLESTIRME KURALLARI:\n",
    "1. ANLAM ESLESMESI: Kelimelerin birebir eslesip eslesmedigine degil, kullanicinin NIYETINE bak.\n",
    "2. YAKIN KAVRAMLAR: 'butce', 'maliyet', 'harcama' gibi kavramlar birbirine yakindir.\n",
    "3. KISMI ESLESME: Sorgu tam olarak cevap vermese bile, KISMI olarak ilgiliyse sec ve confidence'i dusur.\n",
    "4. Hic alakali sorgu yoksa: match_id: null dondur.\n\n",
    
    "### ZORUNLU JSON CIKTISI:\n",
    "{\"match_id\": 1, \"confidence\": 85, \"reason\": \"Kisa aciklama\"}\n\n",
    "- match_id: Sorgu ID numarasi (1'den baslar) veya null\n",
    "- confidence: 0-100 arasi (100=mukemmel, 50=kismi, 0=alakasiz)\n",
    "- reason: Neden bu sorguyu sectin (tek cumle)\n\n",
    "ONEMLI: Sadece JSON dondur, baska hicbir sey yazma."
  )
  
  messages <- list(
    list(role = "system", content = system_instruction),
    list(role = "user", content = user_prompt)
  )
  
  tryCatch({
    # Model seçimi (Varsayılan model veya filter modeli kullanılabilir)
    model_name <- getOption("mergen.filter_model", api_config$local_models[1])
    creds <- resolve_local_llm_credentials(model_name)
    
    # API Key Yönetimi
    api_key_val <- NULL
    if (!is.null(session) && !is.null(session$userData$ai_api_key)) {
      api_key_val <- as.character(session$userData$ai_api_key)[1]
    }
    if (is.null(api_key_val) || !nzchar(api_key_val)) {
      api_key_val <- creds$default_api_key
    }

    # LLM Çağrısı
    result <- call_local_llm(messages, list(
      model_selection = model_name,
      temperature = 0.0,
      max_output_tokens = 200,
      enable_mcp_tools = FALSE,
      shiny_session = session,
      api_key_override = api_key_val
    ))
    
    if (is.null(result)) return(NULL)
    
    content <- if (is.list(result)) result$content else result
    content <- gsub("```json|```", "", content)
    content <- trimws(content)
    
    parsed <- jsonlite::fromJSON(content, simplifyVector = FALSE)
    
	if (!is.null(parsed$match_id)) {
      idx <- as.integer(parsed$match_id)
	  if (idx > 0 && idx <= length(library)) {
        confidence <- as.numeric(parsed$confidence %||% 0)
        cat(sprintf("[PK_ANALIZ] AI Secimi: ID=%d (%s) | Guven: %.1f%% | Sebep: %s\n", 
                    idx, library[[idx]]$name, confidence, parsed$reason %||% ""))
        
        result <- library[[idx]]
        result$relevance_score <- confidence
        result$selection_method <- "ai"
        result$selection_reason <- parsed$reason %||% ""
        result$.matched_idx <- idx
        return(result)
      }
    }
    
    return(NULL)
    
  }, error = function(e) {
    cat(sprintf("[PK_ANALIZ] AI Secim Hatasi: %s\n", e$message))
    return(NULL)
  })
}

select_smart_query <- function(prompt, library, chat_history) {
  cat("[PK_ANALIZ] Akilli Sorgu Secici (Smart Query Selector) calisiyor...\n")
  
  all_scores <- data.frame(
    query_id = character(length(library)),
    query_name = character(length(library)),
    ai_score = numeric(length(library)),
    heuristic_score = numeric(length(library)),
    final_score = numeric(length(library)),
    stringsAsFactors = FALSE
  )
  
  for (i in seq_along(library)) {
    all_scores$query_id[i] <- library[[i]]$id %||% as.character(i)
    all_scores$query_name[i] <- library[[i]]$name %||% ""
    all_scores$ai_score[i] <- 0
    all_scores$heuristic_score[i] <- 0
    all_scores$final_score[i] <- 0
  }
  
  session_obj <- NULL
  try({ session_obj <- shiny::getDefaultReactiveDomain() }, silent=TRUE)
  
  ai_selection <- NULL
  ai_attempt <- 1
  max_ai_attempts <- 2
  
  while (is.null(ai_selection) && ai_attempt <= max_ai_attempts) {
    cat(sprintf("[PK_ANALIZ] AI secim denemesi: %d/%d\n", ai_attempt, max_ai_attempts))
    ai_selection <- find_best_query_with_ai(prompt, library, session_obj)
    ai_attempt <- ai_attempt + 1
  }
  
  if (!is.null(ai_selection)) {
    matched_idx <- ai_selection$.matched_idx
    
    if (!is.null(matched_idx) && length(matched_idx) == 1 && matched_idx > 0) {
      all_scores$ai_score[matched_idx] <- ai_selection$relevance_score %||% 0
      all_scores$final_score[matched_idx] <- ai_selection$relevance_score %||% 0
      
      cat(sprintf("[PK_ANALIZ] -> AI tarafindan kesin eslesme bulundu: %s (Skor: %.1f%%)\n", 
                  ai_selection$name, ai_selection$relevance_score %||% 0))
      
      print_score_table(all_scores)
      
      ai_selection$all_scores <- all_scores
      return(ai_selection)
    }
  }
  
  cat("[PK_ANALIZ] AI eslesme bulamadi veya hata aldi. Guclendirilmis Heuristic yonteme geciliyor...\n")
  
  prompt_clean <- tolower(prompt)
  prompt_words <- unlist(strsplit(prompt_clean, "\\W+"))
  prompt_words <- prompt_words[nchar(prompt_words) > 2]
  
  scores <- sapply(seq_along(library), function(i) {
    q <- library[[i]]
    score <- 0
    
    desc_clean <- tolower(q$description)
    name_clean <- tolower(q$name)
    
    desc_words <- unlist(strsplit(desc_clean, "\\W+"))
    name_words <- unlist(strsplit(name_clean, "\\W+"))
    
    if (grepl(name_clean, prompt_clean, fixed = TRUE)) {
      score <- score + 50
    }
    
    name_matches <- sum(prompt_words %in% name_words)
    score <- score + (name_matches * 10)
    
    desc_matches <- sum(prompt_words %in% desc_words)
    score <- score + (desc_matches * 2)
    
	if (grepl("bütçe|maliyet|harcama|fiyat|tutar", prompt_clean) && grepl("bütçe|maliyet|cost|budget|tutar|fiyat", desc_clean)) score <- score + 8
    if (grepl("zaman|süre|tarih|gecikme|başlangıç|bitiş", prompt_clean) && grepl("date|start|finish|tarih|süre|gecikme", desc_clean)) score <- score + 8
    if (grepl("kaynak|adam|personel|çalışan|ekip", prompt_clean) && grepl("resource|kaynak|personel|ekip", desc_clean)) score <- score + 8
    if (grepl("aktivite|faaliyet|iş|görev", prompt_clean) && grepl("aktivite|activity|task|iş|görev", desc_clean)) score <- score + 8
    if (grepl("proje|program|portföy", prompt_clean) && grepl("proje|project|program|portföy", desc_clean)) score <- score + 8
    if (grepl("wbs|iş kırılım|kırılım", prompt_clean) && grepl("wbs|kırılım|work breakdown", desc_clean)) score <- score + 8
    if (grepl("rol|atama|görevlendirme", prompt_clean) && grepl("rol|role|atama|assignment", desc_clean)) score <- score + 8
    
    return(score)
  })
  
  max_heuristic <- max(scores, na.rm = TRUE)
  if (max_heuristic > 0) {
    scores_normalized <- (scores / max_heuristic) * 100
  } else {
    scores_normalized <- scores
  }
  
  all_scores$heuristic_score <- round(scores_normalized, 1)
  all_scores$final_score <- all_scores$heuristic_score
  
  best_idx <- which.max(scores)
  max_score <- if (length(best_idx) > 0) scores[best_idx] else 0
  max_score_pct <- if (length(best_idx) > 0) scores_normalized[best_idx] else 0
  
  print_score_table(all_scores)
  
  THRESHOLD_RAW <- 2
  THRESHOLD_PCT <- 30
  
  passes_threshold <- (max_score >= THRESHOLD_RAW) || (max_score_pct >= THRESHOLD_PCT)
  
  if (passes_threshold) {
    result <- library[[best_idx]]
    result$relevance_score <- max_score_pct
    result$selection_method <- "heuristic"
    result$selection_reason <- sprintf("Anahtar kelime eslesmesi (ham skor: %d, yuzde: %.1f%%)", max_score, max_score_pct)
    result$all_scores <- all_scores
    
    cat(sprintf("[PK_ANALIZ] -> Heuristic EN IYI ESLESME: %s (Skor: %.1f%%)\n", 
                result$name, max_score_pct))
    return(result)
  }
  
  cat(sprintf("[PK_ANALIZ] -> Hicbir sorgu yeterli skora ulasamadi. Ham: %d (esik: %d), Yuzde: %.1f%% (esik: %d%%)\n", max_score, THRESHOLD_RAW, max_score_pct, THRESHOLD_PCT))
  result <- list(all_scores = all_scores)
  return(result)
}

print_score_table <- function(scores_df) {
  scores_df <- scores_df[order(-scores_df$final_score), ]
  
  cat("\n")
  cat("+==============================================================================+\n")
  cat("|                        SORGU İLGİLİLİK SKORLARI                             |\n")
  cat("+==============================================================================+\n")
  cat("\n")
  
  max_name_len <- max(nchar(scores_df$query_name), na.rm = TRUE)
  max_name_len <- min(max_name_len, 40)
  
  cat(sprintf("%-6s %-*s %10s %12s %11s\n", 
              "ID", max_name_len, "Sorgu Adı", "AI Skor", "Heur. Skor", "Final Skor"))
  cat(strrep("-", 6 + max_name_len + 10 + 12 + 11 + 5), "\n")

  for (i in seq_len(nrow(scores_df))) {
    row <- scores_df[i, ]
    name_display <- substr(row$query_name, 1, max_name_len)
    if (nchar(row$query_name) > max_name_len) {
      name_display <- paste0(substr(name_display, 1, max_name_len - 3), "...")
    }
    
    ai_str <- if (row$ai_score > 0) sprintf("%.1f%%", row$ai_score) else "-"
    heur_str <- sprintf("%.1f%%", row$heuristic_score)
    final_str <- sprintf("%.1f%%", row$final_score)
    
    cat(sprintf("%-6s %-*s %10s %12s %11s\n", 
                row$query_id, max_name_len, name_display, ai_str, heur_str, final_str))
  }
  
  cat(strrep("-", 6 + max_name_len + 10 + 12 + 11 + 5), "\n")
  cat("\n")
}