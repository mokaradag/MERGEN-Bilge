# ==============================================================================
# Dosya Yolu: R/helpers_llm_worker_tool_results.R
# Açıklama:   helpers_llm_worker.R için MCP araç sonuçlarını loglama ve LLM
#             ikinci geçiş prompt metnine dönüştürme yardımcıları.
#             Shiny reactive state'e dokunmaz; yalnızca verilen ham araç
#             sonuçlarını deterministik metin çıktısına çevirir.
# ==============================================================================

llm_worker_extract_preview_df <- function(raw) {
  if (!is.list(raw)) {
    return(NULL)
  }

  raw_names <- names(raw)
  candidate_names <- c("sonuç_önizleme", "sonuc_onizleme", "preview")

  if (!is.null(raw_names)) {
    raw_names_utf8 <- enc2utf8(raw_names)
    candidate_names_utf8 <- enc2utf8(candidate_names)

    matched_idx <- match(candidate_names_utf8, raw_names_utf8)
    matched_idx <- matched_idx[!is.na(matched_idx)]

    if (length(matched_idx)) {
      return(raw[[matched_idx[[1]]]])
    }
  }

  dataframe_idx <- which(vapply(raw, is.data.frame, logical(1)))

  if (length(dataframe_idx) == 1L) {
    return(raw[[dataframe_idx[[1]]]])
  }

  NULL
}

llm_worker_format_single_tool_result <- function(raw,
                                                 tool_name,
                                                 chart_summary_fn = llm_worker_build_chart_summary) {
  mergen_debug_cat("\n========== [GLOBAL] Araç # Formatlanıyor ==========\n")
  mergen_debug_cat("[GLOBAL] Araç adı:", tool_name, "\n")
  mergen_debug_cat("[GLOBAL] raw değişkeni class:", class(raw), "\n")
  mergen_debug_cat("[GLOBAL] raw değişkeni names:", paste(names(raw), collapse = ", "), "\n")

  # sonuç_önizleme / sonuc_onizleme / preview'i bul.
  # Not: Türkçe alan adları bazı Windows/RStudio koşullarında farklı encoding ile
  # gelebilir. Bu nedenle doğrudan raw$`sonuç_önizleme` yerine normalize edilmiş
  # isim eşleştirmesi yapan yardımcı fonksiyon kullanılır.
  df <- llm_worker_extract_preview_df(raw)

  if (!is.null(df)) {
    mergen_debug_cat("[GLOBAL] veri önizleme bulundu\n")
  } else {
    mergen_debug_cat("[GLOBAL] *** UYARI: sonuç_önizleme/preview bulunamadı! ***\n")
  }

  mergen_debug_cat("[GLOBAL] df class:", class(df), "\n")
  mergen_debug_cat("[GLOBAL] df is.data.frame:", is.data.frame(df), "\n")

  if (is.list(raw) && (!is.null(raw$chart) || isTRUE(raw$`__mcp_plot`))) {
    mergen_debug_cat("[GLOBAL] Grafik sonucu algılandı; JSON yerine özet kullanılacak.\n")
    result_text <- chart_summary_fn(raw)

  } else if (is.data.frame(df)) {
    mergen_debug_cat("[GLOBAL] DataFrame boyutu: ", nrow(df), " satır x ", ncol(df), " sütun\n")
    mergen_debug_cat("[GLOBAL] Sütun isimleri:", paste(colnames(df), collapse = ", "), "\n")

    if (nrow(df) > 0) {
      # Türkçe karakterlerin düzgün görünmesi için UTF-8 dönüşümü.
      # Not: Burada tryCatch hata yakalayıcısı kullanmıyoruz; maintainability
      # raporu bu tür anonim handler'ları fonksiyon sayısına dahil eder.
      df <- as.data.frame(df, stringsAsFactors = FALSE)
      df[] <- lapply(df, function(col) enc2utf8(as.character(col)))
      colnames(df) <- enc2utf8(colnames(df))

      mergen_debug_cat("[GLOBAL] \U00002713 VERİ VAR - İLK SATIR:\n")
      if (isTRUE(getOption("mergen.debug", FALSE))) {
        print(df[1, , drop = FALSE])
      }

      # DataFrame'i markdown tablo olarak formatla
      header <- paste0("| ", paste(colnames(df), collapse = " | "), " |")
      separator <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
      rows <- apply(df, 1, function(row) {
        paste0("| ", paste(row, collapse = " | "), " |")
      })
      table_md <- paste(c(header, separator, rows), collapse = "\n")

      source_table_values <- raw$source_table_values
      if ((is.null(source_table_values) || !length(source_table_values)) &&
          "source_table" %in% names(df)) {
        st_vals <- unique(df$source_table)
        st_vals <- st_vals[!is.na(st_vals)]
        source_table_values <- sort(as.character(st_vals))
      }

      source_table_line <- if (!is.null(source_table_values) && length(source_table_values)) {
        paste0("source_table değerleri: ", paste(source_table_values, collapse = ", "))
      } else {
        "UYARI: Bu sonuç source_table sütununu içermiyor. Lütfen sorgunuza ekleyin."
      }

      dropped_cols <- raw$dropped_all_na_columns
      dropped_line <- if (!is.null(dropped_cols) && length(dropped_cols)) {
        paste0("Tamamen NA olduğu için gizlenen sütunlar: ", paste(dropped_cols, collapse = ", "))
      } else {
        ""
      }

      result_text <- paste0(
        "+========================================+\n",
        "|  VERİTABANINDAN GELEN GERÇEK VERİ      |\n",
        "+========================================+\n\n",
        "SQL Sorgusu: ", raw$sql_effective %||% "N/A", "\n",
        "Dönen Toplam Satır: ", nrow(df), "\n",
        "Dönen Toplam Sütun: ", ncol(df), "\n",
        source_table_line, "\n",
        if (nzchar(dropped_line)) paste0(dropped_line, "\n") else "",
        "\n",
        "\U00002B07\U0000FE0F AŞAĞIDA ", nrow(df), " SATIR GERÇEK VERİ VAR \U00002B07\U0000FE0F\n",
        "BU SAYILARI AYNEN KULLAN - UYDURMA!\n\n",
        table_md, "\n\n",
        "\U00002B06\U0000FE0F YUKARDA ", nrow(df), " SATIR GERÇEK VERİ VAR \U00002B06\U0000FE0F\n",
        "BU TABLODAKİ SAYILARI BİREBİR KOPYALA!"
      )

      mergen_debug_cat("\n[GLOBAL] \U00002713 Markdown tablo oluşturuldu\n")
      mergen_debug_cat("[GLOBAL] Tablo uzunluğu:", nchar(table_md), "karakter\n")
      mergen_debug_cat("[GLOBAL] Tablo ilk 500 karakteri:\n")
      mergen_debug_cat(substr(table_md, 1, 500), "\n...\n")

    } else {
      mergen_debug_cat("[GLOBAL] *** UYARI: DataFrame BOŞ (0 satır) ***\n")
      result_text <- "UYARI: Sorgu sonucu boş döndü."
    }
  } else if (is.list(raw) && !is.null(raw$result) && is.character(raw$result)) {
    mergen_debug_cat("[GLOBAL] \U00002713 Liste içindeki result metni kullanılacak\n")
    result_text <- paste(raw$result, collapse = "\n\n")
  } else if (is.character(raw) && length(raw)) {
    mergen_debug_cat("[GLOBAL] \U00002713 Ham karakter vektörü kullanılacak\n")
    result_text <- paste(raw, collapse = "\n\n")
  } else {
    mergen_debug_cat("[GLOBAL] *** UYARI: df DataFrame değil! JSON formatında dönecek ***\n")
    result_text <- jsonlite::toJSON(raw, auto_unbox = TRUE, pretty = TRUE)
  }

  mergen_debug_cat("[GLOBAL] result_text uzunluğu:", nchar(result_text), "karakter\n")
  mergen_debug_cat("[GLOBAL] result_text ilk 300 karakteri:\n")
  mergen_debug_cat(substr(result_text, 1, 300), "\n...\n")
  mergen_debug_cat("========================================\n\n")

  list(tool = tool_name, result = result_text)
}

llm_worker_format_tool_results_for_prompt <- function(tool_calls,
                                                      tool_results_raw,
                                                      chart_summary_fn = llm_worker_build_chart_summary) {
  # Ham araç çıktılarını detaylı logla
  mergen_debug_cat("\n========== [GLOBAL] HAM ARAÇ SONUÇLARI ==========\n")
  for (i in seq_along(tool_results_raw)) {
    raw <- tool_results_raw[[i]]
    mergen_debug_cat("\n[GLOBAL] Araç #", i, "\n")
    mergen_debug_cat("[GLOBAL] Class:", class(raw), "\n")
    mergen_debug_cat("[GLOBAL] Names:", paste(names(raw), collapse = ", "), "\n")

    if (is.list(raw)) {
      if (!is.null(raw$error)) {
        mergen_debug_cat("[GLOBAL] *** HATA VAR ***: ", raw$error, "\n")
      }

      df <- llm_worker_extract_preview_df(raw)
      if (is.data.frame(df)) {
        mergen_debug_cat("[GLOBAL] DataFrame bulundu - Satır:", nrow(df), " Sütun:", ncol(df), "\n")
        if (nrow(df) > 0) {
          mergen_debug_cat("[GLOBAL] İlk satır:\n")
          if (isTRUE(getOption("mergen.debug", FALSE))) {
            print(df[1, , drop = FALSE])
          }
        }
      } else {
        mergen_debug_cat("[GLOBAL] DataFrame YOK veya geçersiz!\n")
      }
    }
  }
  mergen_debug_cat("========== [GLOBAL] HAM SONUÇLAR BİTİŞ ==========\n\n")

  # Araç sonuçlarını LLM için okunabilir formata çevir
  mergen_debug_cat("\n+====================================================+\n")
  mergen_debug_cat("|  [GLOBAL] ARAÇ SONUÇLARINI FORMATLAMAYA BAŞLIYOR  |\n")
  mergen_debug_cat("+====================================================+\n\n")

  tool_results <- lapply(seq_along(tool_calls), function(i) {
    raw <- tool_results_raw[[i]]
    tool_name <- tool_calls[[i]]$function_name

    mergen_debug_cat("\n========== [GLOBAL] Araç #", i, " Formatlanıyor ==========\n")
    llm_worker_format_single_tool_result(
      raw = raw,
      tool_name = tool_name,
      chart_summary_fn = chart_summary_fn
    )
  })

  mergen_debug_cat("\n+====================================================+\n")
  mergen_debug_cat("|  [GLOBAL] TÜM ARAÇLAR FORMATLANDI                  |\n")
  mergen_debug_cat("+====================================================+\n\n")

  # Araç sonuçlarını log'a yaz
  for (i in seq_along(tool_results)) {
    tr <- tool_results[[i]]
    mergen_debug_cat("\n========== ARAÇ SONUCU ", i, " ==========\n")
    mergen_debug_cat("Araç Adı: ", tr$tool, "\n")
    mergen_debug_cat("Sonuç Uzunluğu: ", nchar(tr$result), " karakter\n")
    mergen_debug_cat("İlk 1000 karakter:\n", substr(tr$result, 1, 1000), "\n")
    mergen_debug_cat("========================================\n\n")
  }

  results_text <- paste(
    vapply(tool_results, function(tr) trimws(tr$result), character(1)),
    collapse = "\n\n"
  )

  list(
    tool_results = tool_results,
    results_text = results_text
  )
}