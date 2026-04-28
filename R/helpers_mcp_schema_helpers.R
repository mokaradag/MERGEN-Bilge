# ==============================================================================
# Dosya Yolu: R/helpers_mcp_schema_helpers.R
# Açıklama: MCP dosya şeması, akıllı kolon eşleştirme, argüman normalizasyonu
#           ve çıktı sütun adı yardımcılarını helpers_mcp_tools ortamına ekler.
# ==============================================================================

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  .mcp_context_path <- file.path("R", "helpers_mcp_context.R")

  if (!file.exists(.mcp_context_path)) {
    stop(
      "R/helpers_mcp_context.R bulunamadı; helpers_mcp_schema_helpers.R yüklenemiyor.",
      call. = FALSE
    )
  }

  source(.mcp_context_path, encoding = "UTF-8", local = globalenv())
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

# Dosya şemasını AI için okunabilir formatta çıkar
helpers_mcp_tools$extract_mcp_file_schema <- function(file_name, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(NULL)

  path <- res$path
  dt <- tryCatch({
    helpers_mcp_tools$safe_read_table_generic(path)
  }, error = function(e) NULL)

  if (is.null(dt) || nrow(dt) == 0) return(NULL)

  col_names <- names(dt)
  col_types <- vapply(dt, function(x) class(x)[1], character(1))

  # Her sütun için detaylı bilgi oluştur
  schema_lines <- vapply(seq_along(col_names), function(i) {
    cn <- col_names[i]
    ct <- col_types[i]
    vals <- dt[[cn]]

    type_tr <- switch(ct,
      "numeric" = "Sayısal",
      "integer" = "Tam Sayı",
      "character" = "Metin",
      "factor" = "Kategori",
      "Date" = "Tarih",
      "POSIXct" = "Tarih/Saat",
      "POSIXt" = "Tarih/Saat",
      "logical" = "Mantıksal",
      ct
    )

    if (ct %in% c("character", "factor")) {
      # Kategorik sütun: benzersiz değerleri göster
      unique_vals <- unique(as.character(vals))
      unique_vals <- unique_vals[!is.na(unique_vals)]
      unique_count <- length(unique_vals)

      if (unique_count <= 15) {
        sample_text <- paste(unique_vals, collapse = ", ")
      } else {
        sample_text <- paste0(paste(head(unique_vals, 10), collapse = ", "), " ... (toplam ", unique_count, " farklı değer)")
      }
      sprintf("  - **%s** (%s): Değerler = [%s]", cn, type_tr, sample_text)
    } else if (ct %in% c("numeric", "integer")) {
      # Sayısal sütun: istatistikler
      vals_num <- suppressWarnings(as.numeric(vals))
      vals_num <- vals_num[!is.na(vals_num)]
      if (length(vals_num) > 0) {
        mn <- round(min(vals_num), 2)
        mx <- round(max(vals_num), 2)
        avg <- round(mean(vals_num), 2)
        sprintf("  - **%s** (%s): Min=%s, Max=%s, Ort=%s", cn, type_tr, mn, mx, avg)
      } else {
        sprintf("  - **%s** (%s): Boş veya geçersiz", cn, type_tr)
      }
    } else {
      sprintf("  - **%s** (%s)", cn, type_tr)
    }
  }, character(1))

  display_name <- res$display %||% basename(path)

  paste0(
    "## DOSYA ŞEMASI: ", display_name, "\n",
    "**Toplam Satır:** ", nrow(dt), " | **Toplam Sütun:** ", ncol(dt), "\n\n",
    "### SÜTUNLAR (GERÇEK İSİMLER):\n",
    paste(schema_lines, collapse = "\n"),
    "\n\n**ÖNEMLİ:** Araç çağrılarında yukarıdaki GERÇEK sütun isimlerini kullan!"
  )
}

# Akıllı sütun eşleştirme: Türkçe prompt'tan İngilizce sütun adı bul
helpers_mcp_tools$find_matching_column <- function(search_term, available_columns, context = NULL) {
  if (is.null(search_term) || !nzchar(search_term)) return(NULL)
  if (is.null(available_columns) || length(available_columns) == 0) return(NULL)

  search_lower <- tolower(trimws(search_term))
  cols_lower <- tolower(available_columns)

  # 1. Tam eşleşme kontrolü
  exact_match <- which(cols_lower == search_lower)
  if (length(exact_match) > 0) return(available_columns[exact_match[1]])

  # 2. Kısmi eşleşme (sütun adı arama terimini içeriyor)
  partial_match <- which(grepl(search_lower, cols_lower, fixed = TRUE))
  if (length(partial_match) > 0) return(available_columns[partial_match[1]])

  # 3. Ters kısmi eşleşme (arama terimi sütun adını içeriyor)
  reverse_match <- which(vapply(cols_lower, function(c) grepl(c, search_lower, fixed = TRUE), logical(1)))
  if (length(reverse_match) > 0) return(available_columns[reverse_match[1]])

  # 4. Normalize edilmiş eşleşme (alt çizgi, tire, boşluk yok say)
  normalize <- function(s) {
    s <- tolower(s)
    s <- gsub("[_\\-\\s]+", "", s)
    s <- gsub("ı", "i", s)
    s <- gsub("ğ", "g", s)
    s <- gsub("ü", "u", s)
    s <- gsub("ş", "s", s)
    s <- gsub("ö", "o", s)
    s <- gsub("ç", "c", s)
    s
  }

  search_norm <- normalize(search_lower)
  cols_norm <- vapply(cols_lower, normalize, character(1))

  norm_match <- which(cols_norm == search_norm)
  if (length(norm_match) > 0) return(available_columns[norm_match[1]])

  # 5. Kelime kökü eşleştirme
  norm_partial <- which(grepl(search_norm, cols_norm, fixed = TRUE) |
                        vapply(cols_norm, function(c) grepl(c, search_norm, fixed = TRUE), logical(1)))
  if (length(norm_partial) > 0) return(available_columns[norm_partial[1]])

  # 6. Yaygın Türkçe-İngilizce eşleştirmeler
  common_patterns <- list(
    "dept|bolum|birim" = "department|dept|bolum|birim|unit",
    "maas|ucret|gelir|salary" = "salary|wage|income|pay|maas|ucret|gelir",
    "performans|perf|basari" = "performance|perf|score|rating|basari",
    "yas|age|yasi" = "age|yas|yasi|year",
    "isim|ad|name" = "name|isim|ad|adi",
    "tarih|date|gun" = "date|tarih|gun|day|time",
    "miktar|adet|sayi" = "count|amount|quantity|miktar|adet|sayi|number",
    "cinsiyet|gender" = "gender|sex|cinsiyet",
    "sure|saat|zaman|hour" = "hour|time|duration|sure|saat|zaman",
    "toplam|total|sum" = "total|sum|toplam"
  )

  for (pattern_group in names(common_patterns)) {
    if (grepl(pattern_group, search_norm, perl = TRUE)) {
      target_patterns <- unlist(strsplit(common_patterns[[pattern_group]], "\\|"))
      for (tp in target_patterns) {
        match_idx <- which(grepl(tp, cols_norm, fixed = TRUE))
        if (length(match_idx) > 0) return(available_columns[match_idx[1]])
      }
    }
  }

  NULL
}

# Birden fazla sütun için akıllı eşleştirme
helpers_mcp_tools$find_columns_by_context <- function(dt, search_terms) {
  if (is.null(dt) || !is.data.frame(dt)) return(list())
  if (is.null(search_terms) || length(search_terms) == 0) return(list())

  available_columns <- names(dt)
  results <- list()

  for (term in search_terms) {
    found <- helpers_mcp_tools$find_matching_column(term, available_columns)
    if (!is.null(found)) {
      results[[term]] <- found
    }
  }

  results
}

helpers_mcp_tools$normalize_args <- function(args) {
  if (!is.list(args)) args <- list()

  # Dosya adı eş adları
  if (is.null(args$file_name)) {
    args$file_name <- args$filename %||% args$fileId %||% args$file %||% args$dosya
  }

  # Sütun eş adları
  if (is.null(args$column)) {
    args$column <- args$col %||% args$field %||% args$kolon %||% args$column_name
  }

  # SQL eş adları
  if (is.null(args$sql)) {
    args$sql <- args$query %||% args$sorgu
  }

  args
}

helpers_mcp_tools$normalize_chart_type <- function(chart_type) {
  chart_type <- tolower(trimws(as.character(chart_type %||% "")))

  aliases <- list(
    line = c("line", "line graph", "line chart", "çizgi", "çizgi grafiği", "trend", "trend graph", "trend chart", "zaman serisi", "time series"),
    scatter = c("scatter", "scatter plot", "scatter graph", "saçılım", "saçılım grafiği"),
    area = c("area", "area graph", "area chart", "alan", "alan grafiği"),
    pareto = c("pareto", "pareto graph", "pareto chart", "pareto grafiği"),
    bar = c("bar", "bar graph", "bar chart", "column", "column chart", "çubuk", "çubuk grafiği", "sütun", "sütun grafiği"),
    pie = c("pie", "pie chart", "pie graph", "pasta", "pasta grafiği"),
    donut = c("donut", "doughnut", "donut chart", "doughnut chart", "halka", "halka grafiği"),
    hist = c("hist", "histogram", "histogram chart", "dağılım")
  )

  for (nm in names(aliases)) {
    if (chart_type %in% aliases[[nm]]) return(nm)
  }

  if (chart_type %in% c("box", "boxplot", "box_plot", "bx")) return("hist")

  chart_type
}

helpers_mcp_tools$prettify_column_name <- function(nm) {
  if (is.null(nm) || length(nm) == 0) return("")
  raw <- as.character(nm[1])
  if (!nzchar(raw)) return("")

  # Tırnak/köşeli parantez sarmalayıcılarını temizle
  cleaned <- gsub("^[`\"\\[]|[`\"\\]]$", "", raw)
  cleaned <- gsub("_+", " ", cleaned)
  cleaned <- gsub("(?<=[a-z])(?=[A-Z])", " ", cleaned, perl = TRUE)
  cleaned <- trimws(cleaned)

  lower <- tolower(cleaned)
  if (grepl("^(avg|mean)", lower)) cleaned <- paste("Ortalama", trimws(sub("(?i)^(avg|mean)", "", cleaned)))
  if (grepl("^(sum|total)", lower)) cleaned <- paste("Toplam", trimws(sub("(?i)^(sum|total)", "", cleaned)))
  if (grepl("count", lower)) cleaned <- paste("Adet", trimws(sub("(?i)count", "", cleaned)))
  if (grepl("max", lower)) cleaned <- paste("Maksimum", trimws(sub("(?i)max", "", cleaned)))
  if (grepl("min", lower)) cleaned <- paste("Minimum", trimws(sub("(?i)min", "", cleaned)))

  cleaned <- trimws(cleaned)
  if (identical(cleaned, "")) cleaned <- raw

  tryCatch(enc2utf8(cleaned), error = function(e) cleaned)
}

helpers_mcp_tools$prettify_result_colnames <- function(df) {
  if (!is.data.frame(df)) return(df)
  colnames(df) <- vapply(colnames(df), helpers_mcp_tools$prettify_column_name, character(1))
  df
}

assign("helpers_mcp_tools", helpers_mcp_tools, envir = helpers_mcp_tools)

for (.mcp_schema_fn in c(
  "extract_mcp_file_schema",
  "find_matching_column",
  "find_columns_by_context",
  "normalize_args",
  "normalize_chart_type",
  "prettify_column_name",
  "prettify_result_colnames"
)) {
  if (exists(.mcp_schema_fn, envir = helpers_mcp_tools, inherits = FALSE)) {
    .mcp_schema_fun <- get(.mcp_schema_fn, envir = helpers_mcp_tools, inherits = FALSE)

    if (is.function(.mcp_schema_fun)) {
      environment(.mcp_schema_fun) <- helpers_mcp_tools
      assign(.mcp_schema_fn, .mcp_schema_fun, envir = helpers_mcp_tools)
    }
  }
}

if (exists(".mcp_schema_fn", inherits = FALSE)) {
  rm(.mcp_schema_fn)
}

if (exists(".mcp_schema_fun", inherits = FALSE)) {
  rm(.mcp_schema_fun)
}

if (exists(".mcp_context_path", inherits = FALSE)) {
  rm(.mcp_context_path)
}