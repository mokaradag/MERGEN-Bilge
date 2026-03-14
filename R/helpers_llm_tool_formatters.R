# ==============================================================================
# Dosya Yolu: R/helpers_llm_tool_formatters.R
# Açıklama:   LLM araç sonuçlarını formatlama, Excel veri profili çıkarma,
#              MCP Excel yedek yardımcıları ve DOCX->PDF dönüştürme fonksiyonları.
#              global.R tarafından config_api.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- DOCX -> PDF DÖNÜŞTÜRMESİ (LibreOffice ile, opsiyonel) ---
# Sadece options(mergen.word_preview_mode) == "pdf" iken kullanılır
convert_docx_to_pdf <- function(docx_path) {
  if (!file.exists(docx_path)) stop("Yol bulunamadı: ", docx_path)
  cmd <- Sys.which("soffice")
  if (!nzchar(cmd)) stop("LibreOffice ('soffice') PATH'te bulunamadı. Kurun veya options(mergen.word_preview_mode = 'html') ayarlayın.")
  outdir <- dirname(docx_path)
  # Dönüştürme işlemi
  res <- try(
    system2(cmd,
      args = c("--headless", "--norestore", "--convert-to", "pdf", "--outdir", shQuote(outdir), shQuote(docx_path)),
      stdout = TRUE, stderr = TRUE
    ),
    silent = TRUE
  )
  pdf_path <- sub("\\.docx$", ".pdf", docx_path, ignore.case = TRUE)
  if (!file.exists(pdf_path)) stop("PDF üretilemedi. LibreOffice çıktısı: ", paste(res, collapse = "\n"))
  normalizePath(pdf_path, winslash = "/", mustWork = TRUE)
}

# --- HAM ARAÇ SONUÇLARINDAN DOĞRUDAN TÜRKÇE YANIT OLUŞTURMA ---
# Araç sonuçlarındaki TR + EN anahtarları kullanarak kısa ve öz yanıt üretir
format_answer_from_tool_results <- function(tool_results_raw) {
  if (length(tool_results_raw) == 0) return(NULL)
  tr <- tool_results_raw[[1]]
  if (is.null(tr)) return(NULL)

  # İki anahtarlı güvenli erişim yardımcısı
  get2 <- function(x, k1, k2 = NULL) {
    if (!is.null(x[[k1]])) return(x[[k1]])
    if (!is.null(k2) && !is.null(x[[k2]])) return(x[[k2]])
    NULL
  }

  # sql_query_uploaded_file: sonuç önizlemesi (tekli hücre)
  df <- get2(tr, "sonuç_önizleme", "result_preview")
  if (is.data.frame(df) && nrow(df) >= 1 && ncol(df) >= 1) {
    cname <- colnames(df)[1]
    v <- df[1, 1]
    if (is.numeric(v)) {
      val <- as.numeric(v)
      lc <- tolower(cname)
      if (grepl("avg|mean|average", lc))       return(sprintf("Ortalama: %.2f", val))
      if (grepl("max", lc))                    return(sprintf("En yüksek değer: %.2f", val))
      if (grepl("min", lc))                    return(sprintf("En düşük değer: %.2f", val))
      if (grepl("count|distinct", lc))         return(sprintf("Sayı: %d", as.integer(round(val))))
      return(sprintf("%s: %s", cname, format(val, trim = TRUE, scientific = FALSE)))
    } else {
      return(sprintf("%s: %s", cname, as.character(v)))
    }
  }

  # get_column_statistics (sayısal)
  typ <- get2(tr, "tür", "type")
  if (identical(typ, "numeric")) {
    col   <- get2(tr, "sütun", "column")
    meanv <- get2(tr, "ortalama", "mean")
    med   <- get2(tr, "medyan", "median")
    minv  <- get2(tr, "minimum", "min")
    maxv  <- get2(tr, "maksimum", "max")
    return(sprintf(
      "%s sütunu \U2014 Ortalama: %.2f, Medyan: %.2f, Min: %.2f, Max: %.2f",
      col %||% "Seçilen", meanv %||% NA_real_, med %||% NA_real_, minv %||% NA_real_, maxv %||% NA_real_
    ))
  }

  # analyze_uploaded_file
  rows <- get2(tr, "satır_sayısı", "row_count")
  cols <- get2(tr, "sütun_sayısı", "column_count")
  if (!is.null(rows) && !is.null(cols)) {
    return(sprintf("Dosyada %d satır ve %d sütun var.", rows, cols))
  }

  NULL
}

# --- HIZLI EXCEL PROFİLİ ---
# DataFrame için istatistiksel profil çıkarır (sunucu + MCP araçları ortak kullanır)
fast_profile <- function(df, top_levels = 12) {
  dt <- data.table::as.data.table(df)
  n  <- nrow(dt)

  types <- vapply(dt, function(x) class(x)[1], character(1))
  miss  <- vapply(dt, function(x) mean(is.na(x)), numeric(1))

  num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
  cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]

  num_stats <- if (length(num_cols)) {
    data.table::rbindlist(lapply(num_cols, function(cn) {
      x <- dt[[cn]]
      data.table::data.table(
        column = cn,
        min    = suppressWarnings(min(x, na.rm = TRUE)),
        p25    = suppressWarnings(as.numeric(stats::quantile(x, 0.25, na.rm = TRUE))),
        median = suppressWarnings(stats::median(x, na.rm = TRUE)),
        mean   = suppressWarnings(mean(x, na.rm = TRUE)),
        p75    = suppressWarnings(as.numeric(stats::quantile(x, 0.75, na.rm = TRUE))),
        max    = suppressWarnings(max(x, na.rm = TRUE)),
        sd     = suppressWarnings(stats::sd(x,  na.rm = TRUE))
      )
    }), fill = TRUE, use.names = TRUE)
  } else data.table::data.table()

  cat_top <- if (length(cat_cols)) {
    data.table::rbindlist(lapply(cat_cols, function(cn) {
      tbl <- sort(table(dt[[cn]]), decreasing = TRUE)
      head_tbl <- head(tbl, top_levels)
      data.table::data.table(column = cn, level = names(head_tbl), n = as.integer(head_tbl))
    }), fill = TRUE, use.names = TRUE)
  } else data.table::data.table()

  list(
    shape     = list(rows = n, cols = ncol(dt)),
    col_types = as.list(types),
    missing   = as.list(miss),
    numeric   = num_stats,
    categories= cat_top
  )
}

# --- EXCEL ÖZET JSON'U OLUŞTURMA ---
# Dosya yolundan Excel profilini JSON formatında döndürür
build_excel_digest_json <- function(path, top_levels = 12) {
  df <- safe_read_excel_table(path)
  prof <- fast_profile(df, top_levels = top_levels)
  jsonlite::toJSON(prof, dataframe = "rows", na = "string", auto_unbox = TRUE)
}

# --- MCP EXCEL YEDEK YARDIMCILARI ---

# Oturumdaki MCP Excel dosya adaylarını döndürür
get_mcp_excel_candidates <- function(session_obj) {
  if (is.null(session_obj)) return(character())
  files <- session_obj$userData$current_session_files
  if (is.null(files) || !length(files)) return(character())
  display_names <- vapply(files, function(obj) {
    nm <- obj$name %||% obj$display %||% ""
    if (!is.character(nm) || length(nm) == 0) nm <- ""
    as.character(nm[1])
  }, character(1))
  display_names <- unique(display_names[nzchar(display_names)])
  if (!length(display_names)) {
    display_names <- unique(names(files))
    display_names <- display_names[nzchar(display_names)]
  }
  display_names
}

# Analiz sonucundan MCP Excel özeti oluşturur
build_mcp_excel_summary <- function(analysis_result, display_name) {
  if (is.null(analysis_result) || !is.list(analysis_result)) return(NULL)
  satir <- analysis_result$satır_sayısı %||% analysis_result$row_count
  sutun <- analysis_result$sütun_sayısı %||% analysis_result$column_count
  cols  <- analysis_result$sütun_isimleri %||% analysis_result$columns
  nums  <- analysis_result$sayısal_sütunlar %||% analysis_result$numeric_columns

  lines <- c(
    sprintf("Dosya: %s", display_name %||% analysis_result$dosya_adı %||% "(bilinmiyor)"),
    sprintf("Toplam satır: %s", satir %||% "(bilinmiyor)"),
    sprintf("Toplam sütun: %s", sutun %||% "(bilinmiyor)")
  )

  if (length(cols)) {
    lines <- c(lines, sprintf("Sütunlar (%d): %s", length(cols), paste(cols, collapse = ", ")))
  }
  if (length(nums)) {
    lines <- c(lines, sprintf("Sayısal sütunlar: %s", paste(nums, collapse = ", ")))
  }

  paste(lines, collapse = "\n")
}

# Araç çağrısı yapılamadığında Excel dosyasını doğrudan analiz eden yedek fonksiyon
mcp_excel_tool_fallback <- function(session_obj) {
  if (!exists("helpers_mcp_tools", inherits = TRUE) ||
      !is.function(helpers_mcp_tools$analyze_uploaded_file)) {
    return(NULL)
  }
  candidates <- get_mcp_excel_candidates(session_obj)
  if (!length(candidates)) return(NULL)

  for (disp in candidates) {
    res <- try(helpers_mcp_tools$analyze_uploaded_file(disp, session_obj), silent = TRUE)
    if (!inherits(res, "try-error") && is.list(res) && is.null(res$error)) {
      text <- build_mcp_excel_summary(res, disp)
      if (!is.null(text)) {
        return(list(text = text, citation = disp))
      }
    }
  }
  NULL
}