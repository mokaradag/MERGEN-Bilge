# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_security_summary.R
# Açıklama: Proje/Kaynak Analizi için RLS, kullanıcı kimliği hazır olma kontrolü
#           ve istatistiksel özet yardımcıları. Shiny observer başlatmaz.
# ==============================================================================

resolve_pk_analysis_username <- function(session, fallback = "Unknown") {
  fallback <- as.character(fallback %||% "Unknown")[1]
  if (is.na(fallback) || !nzchar(fallback)) {
    fallback <- "Unknown"
  }

  user_data <- NULL
  if (!is.null(session) && !is.null(session$userData)) {
    user_data <- session$userData
  }

  if (is.null(user_data)) {
    return(list(
      ready = FALSE,
      username = fallback,
      reason = "session_user_data_missing"
    ))
  }

  sso_active <- isTRUE(user_data$sso_active)
  auth_initialized <- user_data$auth_initialized

  if (isTRUE(sso_active) && !isTRUE(auth_initialized)) {
    return(list(
      ready = FALSE,
      username = fallback,
      reason = "auth_not_ready"
    ))
  }

  username <- user_data$system_username %||% NULL

  if ((is.null(username) || !nzchar(trimws(as.character(username)[1]))) &&
      is.list(user_data$user_identity)) {
    username <- user_data$user_identity$username %||% NULL
  }

  username <- as.character(username %||% "")[1]
  if (is.na(username)) {
    username <- ""
  }
  username <- trimws(username)

  if (!nzchar(username)) {
    return(list(
      ready = !isTRUE(sso_active),
      username = fallback,
      reason = "username_missing"
    ))
  }

  list(
    ready = TRUE,
    username = username,
    reason = NULL
  )
}

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