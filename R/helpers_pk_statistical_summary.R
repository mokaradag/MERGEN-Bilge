# ==============================================================================
# Dosya Yolu: R/helpers_pk_statistical_summary.R
# Açıklama: Proje ve Kaynak Analizi istatistiksel özet kurucusu.
#
#           `generate_statistical_summary()` helpers_pk_analysis_security_summary.R
#           içinden BİREBİR taşınmıştır (yalnızca D8 özyineleme düzeltmesi
#           uygulanmış hâliyle). Amaç bakım yüzeyidir: RLS/kimlik dosyası
#           sözleşme testindeki 400 satır bütçesinin altında kalmalıdır ve
#           master plan §5.7 bu fonksiyonu Faz 2'de analiz paketiyle
#           DEĞİŞTİRECEKTİR; ayrı bir dosyada olması o değişimi izole eder.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

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
    # D8: v1 ozyinelemesi mode / rls_total_rows / user_filter_applied
    # parametrelerini DUSURUYORDU; bu yuzden "FILTRELEME UYARISI" blogu tam da
    # verinin buyuk oldugu durumda kayboluyordu. v2'de tum baglam aktarilir.
    pk_v2 <- exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
      isTRUE(pk_engine_is_v2())

    # Önce preview satır sayısını yarıya indir
    if (max_preview_rows > 5) {
      if (pk_v2) {
        return(generate_statistical_summary(
          data,
          max_preview_rows = floor(max_preview_rows / 2),
          max_total_chars = max_total_chars,
          mode = mode,
          rls_total_rows = rls_total_rows,
          user_filter_applied = user_filter_applied,
          pre_aggregated_columns = pre_aggregated_columns
        ))
      }
      return(generate_statistical_summary(data, max_preview_rows = floor(max_preview_rows / 2), max_total_chars = max_total_chars, pre_aggregated_columns = pre_aggregated_columns))
    }
    # Eğer hala büyükse, sadece temel özet gönder
    basic_summary <- sprintf("TOPLAM SATIR: %d | TOPLAM SUTUN: %d", total_rows, total_cols)
    if (pk_v2 && isTRUE(user_filter_applied) && !is.null(rls_total_rows) &&
        rls_total_rows > total_rows) {
      basic_summary <- paste0(
        basic_summary,
        sprintf(
          "\n\n\U000026A0\U0000FE0F FİLTRELEME UYARISI:\n- Yetki dahilinde toplam satır: %d\n- Kullanıcı filtreleme sonrası satır: %d\n- BU %d SATIR SPESİFİK FİLTRELEME KRİTERİNE AİTTİR (tüm veri için değil!)\n- Oran/yüzde hesaplarken SADECE filtreleme sonrası %d satırı referans al",
          rls_total_rows, total_rows, total_rows, total_rows
        )
      )
    }
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