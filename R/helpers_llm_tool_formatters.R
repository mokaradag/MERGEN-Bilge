# ==============================================================================
# Dosya Yolu: R/helpers_llm_tool_formatters.R
# Açıklama: LLM araç sonuçlarını formatlama, Excel veri profili çıkarma,
#           MCP Excel yedek yardımcıları ve DOCX->PDF dönüştürme fonksiyonları.
#           global.R tarafından config_api.R'den sonra source() ile çağrılır.
# ==============================================================================

# ------------------------------------------------------------------------------
# DOCX -> PDF DÖNÜŞTÜRMESİ
# LibreOffice (soffice) ile opsiyonel dönüştürme yapar.
# Sadece options(mergen.word_preview_mode) == "pdf" iken kullanılır.
# ------------------------------------------------------------------------------
convert_docx_to_pdf <- function(docx_path) {
  if (!file.exists(docx_path)) {
    stop("Yol bulunamadi: ", docx_path)
  }

  cmd <- Sys.which("soffice")
  if (!nzchar(cmd)) {
    stop(
      "LibreOffice ('soffice') PATH'te bulunamadi. ",
      "Kurun veya options(mergen.word_preview_mode = 'html') ayarlayin."
    )
  }

  outdir <- dirname(docx_path)

  # `system2(timeout = 0)` zaman aşımını KAPATIR; 0/negatif/geçersiz değer
  # yanıt vermeyen soffice sürecinde çağrıyı süresiz bloke ediyordu.
  timeout_sec <- suppressWarnings(as.numeric(
    Sys.getenv("MERGEN_DOCX_PDF_TIMEOUT_SEC", "120")
  )[1])
  if (length(timeout_sec) != 1L || !is.finite(timeout_sec) || timeout_sec <= 0) {
    timeout_sec <- 120
  }
  # `system2()` kesirli saniyeleri YOK SAYAR; 0.5 gibi bir değer timeout = 0
  # (zaman aşımı kapalı) hâline gelip çağrıyı süresiz bloke ediyordu.
  timeout_sec <- ceiling(timeout_sec)

  # Dönüştürme işlemi
  res <- try(
    system2(
      cmd,
      args = c(
        "--headless",
        "--norestore",
        "--convert-to", "pdf",
        "--outdir", shQuote(outdir),
        shQuote(docx_path)
      ),
      stdout = TRUE,
      stderr = TRUE,
      # Yanıt vermeyen LibreOffice süreci çağrıyı süresiz bloke ediyordu.
      timeout = timeout_sec
    ),
    silent = TRUE
  )

  pdf_path <- sub("\\.docx$", ".pdf", docx_path, ignore.case = TRUE)

  # ÇIKIŞ DURUMU dosya denetiminden ÖNCE değerlendirilir. Aksi hâlde soffice
  # başarısız olduğunda ya da zaman aşımına uğradığında ÖNCEDEN var olan eski
  # bir PDF yeni dönüşüm sonucu gibi döndürülüyordu.
  durum <- attr(res, "status")
  basarisiz <- inherits(res, "try-error") ||
    (!is.null(durum) && !identical(as.integer(durum)[1], 0L))

  if (isTRUE(basarisiz)) {
    stop(
      "PDF \u00fcretilemedi (LibreOffice ba\u015Far\u0131s\u0131z veya zaman a\u015F\u0131m\u0131). \u00c7\u0131kt\u0131: ",
      paste(as.character(res), collapse = "\n")
    )
  }

  if (!file.exists(pdf_path)) {
    stop(
      "PDF \u00fcretilemedi. LibreOffice \u00e7\u0131kt\u0131s\u0131: ",
      paste(res, collapse = "\n")
    )
  }

  normalizePath(pdf_path, winslash = "/", mustWork = TRUE)
}

# ------------------------------------------------------------------------------
# ASCII-guvenli liste anahtari okuma yardimcilari
# Bu yardimcilar, VM tarafinda parse sorunu cikarabilen Turkce karakterli
# kod sembollerini ($satir_sayisi gibi) kullanmadan veri okumayi saglar.
# ------------------------------------------------------------------------------
get_list_value_any <- function(x, keys) {
  if (is.null(x) || !is.list(x) || length(keys) == 0) {
    return(NULL)
  }

  for (k in keys) {
    if (!is.null(x[[k]])) {
      return(x[[k]])
    }
  }

  NULL
}

# ------------------------------------------------------------------------------
# HAM ARAC SONUCLARINDAN DOGRUDAN TURKCE YANIT OLUSTURMA
# Arac sonuclarindaki TR + EN anahtarlari kullanarak kisa ve oz yanit uretir.
# ------------------------------------------------------------------------------
format_answer_from_tool_results <- function(tool_results_raw) {
  if (length(tool_results_raw) == 0) {
    return(NULL)
  }

  tr <- tool_results_raw[[1]]
  if (is.null(tr)) {
    return(NULL)
  }

  # sql_query_uploaded_file: sonuc onizlemesi (tekli hucre)
  df <- get_list_value_any(
    tr,
    c(
      "sonuc_onizleme",
      "sonu\u00e7_\u00f6nizleme",
      "result_preview"
    )
  )

  if (is.data.frame(df) && nrow(df) >= 1 && ncol(df) >= 1) {
    cname <- colnames(df)[1]
    v <- df[1, 1]

    if (is.numeric(v)) {
      val <- as.numeric(v)
      lc <- tolower(cname)

      if (grepl("avg|mean|average", lc)) {
        return(sprintf("Ortalama: %.2f", val))
      }
      if (grepl("max", lc)) {
        return(sprintf("En yuksek deger: %.2f", val))
      }
      if (grepl("min", lc)) {
        return(sprintf("En dusuk deger: %.2f", val))
      }
      if (grepl("count|distinct", lc)) {
        return(sprintf("Sayi: %d", as.integer(round(val))))
      }

      return(sprintf(
        "%s: %s",
        cname,
        format(val, trim = TRUE, scientific = FALSE)
      ))
    }

    return(sprintf("%s: %s", cname, as.character(v)))
  }

  # get_column_statistics (sayisal)
  typ <- get_list_value_any(
    tr,
    c("tur", "t\u00fcr", "type")
  )

  if (identical(typ, "numeric")) {
    col <- get_list_value_any(
      tr,
      c("sutun", "s\u00fctun", "column")
    )
    meanv <- get_list_value_any(tr, c("ortalama", "mean"))
    med <- get_list_value_any(tr, c("medyan", "median"))
    minv <- get_list_value_any(tr, c("minimum", "min"))
    maxv <- get_list_value_any(tr, c("maksimum", "max"))

    return(sprintf(
      "%s sutunu \u2014 Ortalama: %.2f, Medyan: %.2f, Min: %.2f, Max: %.2f",
      col %||% "Secilen",
      meanv %||% NA_real_,
      med %||% NA_real_,
      minv %||% NA_real_,
      maxv %||% NA_real_
    ))
  }

  # analyze_uploaded_file
  rows <- get_list_value_any(
    tr,
    c("satir_sayisi", "sat\u0131r_say\u0131s\u0131", "row_count")
  )
  cols <- get_list_value_any(
    tr,
    c("sutun_sayisi", "s\u00fctun_say\u0131s\u0131", "column_count")
  )

  if (!is.null(rows) && !is.null(cols)) {
    return(sprintf("Dosyada %d satir ve %d sutun var.", rows, cols))
  }

  NULL
}

# ------------------------------------------------------------------------------
# HIZLI EXCEL PROFILI
# DataFrame icin istatistiksel profil cikarir.
# Sunucu + MCP araclari ortak kullanir.
# ------------------------------------------------------------------------------
fast_profile <- function(df, top_levels = 12) {
  dt <- data.table::as.data.table(df)
  n <- nrow(dt)

  types <- vapply(dt, function(x) class(x)[1], character(1))
  miss <- vapply(dt, function(x) mean(is.na(x)), numeric(1))

  num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
  cat_cols <- names(dt)[vapply(
    dt,
    function(x) is.character(x) || is.factor(x),
    logical(1)
  )]

  num_stats <- if (length(num_cols)) {
    data.table::rbindlist(
      lapply(num_cols, function(cn) {
        x <- dt[[cn]]
        data.table::data.table(
          column = cn,
          min = suppressWarnings(min(x, na.rm = TRUE)),
          p25 = suppressWarnings(as.numeric(stats::quantile(x, 0.25, na.rm = TRUE))),
          median = suppressWarnings(stats::median(x, na.rm = TRUE)),
          mean = suppressWarnings(mean(x, na.rm = TRUE)),
          p75 = suppressWarnings(as.numeric(stats::quantile(x, 0.75, na.rm = TRUE))),
          max = suppressWarnings(max(x, na.rm = TRUE)),
          sd = suppressWarnings(stats::sd(x, na.rm = TRUE))
        )
      }),
      fill = TRUE,
      use.names = TRUE
    )
  } else {
    data.table::data.table()
  }

  cat_top <- if (length(cat_cols)) {
    data.table::rbindlist(
      lapply(cat_cols, function(cn) {
        tbl <- sort(table(dt[[cn]]), decreasing = TRUE)
        head_tbl <- head(tbl, top_levels)
        data.table::data.table(
          column = cn,
          level = names(head_tbl),
          n = as.integer(head_tbl)
        )
      }),
      fill = TRUE,
      use.names = TRUE
    )
  } else {
    data.table::data.table()
  }

  list(
    shape = list(rows = n, cols = ncol(dt)),
    col_types = as.list(types),
    missing = as.list(miss),
    numeric = num_stats,
    categories = cat_top
  )
}

# ------------------------------------------------------------------------------
# EXCEL OZET JSON'U OLUSTURMA
# Dosya yolundan Excel profilini JSON formatinda dondurur.
# ------------------------------------------------------------------------------
build_excel_digest_json <- function(path, top_levels = 12) {
  df <- safe_read_excel_table(path)
  prof <- fast_profile(df, top_levels = top_levels)
  jsonlite::toJSON(
    prof,
    dataframe = "rows",
    na = "string",
    auto_unbox = TRUE
  )
}

# ------------------------------------------------------------------------------
# MCP EXCEL YEDEK YARDIMCILARI
# ------------------------------------------------------------------------------

# Oturumdaki MCP Excel dosya adaylarini dondurur
get_mcp_excel_candidates <- function(session_obj) {
  if (is.null(session_obj)) {
    return(character())
  }

  files <- session_obj$userData$current_session_files
  if (is.null(files) || !length(files)) {
    return(character())
  }

  display_names <- vapply(files, function(obj) {
    nm <- obj$name %||% obj$display %||% ""
    if (!is.character(nm) || length(nm) == 0) {
      nm <- ""
    }
    as.character(nm[1])
  }, character(1))

  display_names <- unique(display_names[nzchar(display_names)])

  if (!length(display_names)) {
    display_names <- unique(names(files))
    display_names <- display_names[nzchar(display_names)]
  }

  display_names
}

# Analiz sonucundan MCP Excel ozeti olusturur
build_mcp_excel_summary <- function(analysis_result, display_name) {
  if (is.null(analysis_result) || !is.list(analysis_result)) {
    return(NULL)
  }

  satir <- get_list_value_any(
    analysis_result,
    c("satir_sayisi", "sat\u0131r_say\u0131s\u0131", "row_count")
  )
  sutun <- get_list_value_any(
    analysis_result,
    c("sutun_sayisi", "s\u00fctun_say\u0131s\u0131", "column_count")
  )
  cols <- get_list_value_any(
    analysis_result,
    c("sutun_isimleri", "s\u00fctun_isimleri", "columns")
  )
  nums <- get_list_value_any(
    analysis_result,
    c("sayisal_sutunlar", "say\u0131sal_s\u00fctunlar", "numeric_columns")
  )
  dosya_adi <- get_list_value_any(
    analysis_result,
    c("dosya_adi", "dosya_ad\u0131", "file_name", "filename")
  )

  lines <- c(
    sprintf("Dosya: %s", display_name %||% dosya_adi %||% "(bilinmiyor)"),
    sprintf("Toplam satir: %s", satir %||% "(bilinmiyor)"),
    sprintf("Toplam sutun: %s", sutun %||% "(bilinmiyor)")
  )

  if (length(cols)) {
    lines <- c(
      lines,
      sprintf("Sutunlar (%d): %s", length(cols), paste(cols, collapse = ", "))
    )
  }

  if (length(nums)) {
    lines <- c(
      lines,
      sprintf("Sayisal sutunlar: %s", paste(nums, collapse = ", "))
    )
  }

  paste(lines, collapse = "\n")
}

# Arac cagrisi yapilamadiginda Excel dosyasini dogrudan analiz eden yedek fonksiyon
mcp_excel_tool_fallback <- function(session_obj) {
  if (!exists("helpers_mcp_tools", inherits = TRUE) ||
      !is.function(helpers_mcp_tools$analyze_uploaded_file)) {
    return(NULL)
  }

  candidates <- get_mcp_excel_candidates(session_obj)
  if (!length(candidates)) {
    return(NULL)
  }

  for (disp in candidates) {
    res <- try(
      helpers_mcp_tools$analyze_uploaded_file(disp, session_obj),
      silent = TRUE
    )

    if (!inherits(res, "try-error") && is.list(res) && is.null(res$error)) {
      text <- build_mcp_excel_summary(res, disp)
      if (!is.null(text)) {
        return(list(text = text, citation = disp))
      }
    }
  }

  NULL
}