# ==============================================================================
# Dosya Yolu: R/helpers_mcp_basic_tools.R
# Açıklama: MCP temel dosya özeti, kolon istatistiği ve SQL araçlarını
#           helpers_mcp_tools ortamına ekler.
# ==============================================================================

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  .mcp_context_path <- file.path("R", "helpers_mcp_context.R")

  if (!file.exists(.mcp_context_path)) {
    stop(
      "R/helpers_mcp_context.R bulunamadı; helpers_mcp_basic_tools.R yüklenemiyor.",
      call. = FALSE
    )
  }

  source(.mcp_context_path, encoding = "UTF-8", local = globalenv())
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

helpers_mcp_tools$safe_has_duckdb <- function() {
  requireNamespace("duckdb", quietly = TRUE)
}

helpers_mcp_tools$analyze_uploaded_file <- function(file_name, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)

  if (!isTRUE(res$ok)) return(list(error = res$error))

  path <- res$path
  df <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)

  if (inherits(df, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s \U2014 %s", basename(path), df$message)))
  }

  n_rows <- nrow(df)
  n_cols <- ncol(df)
  cols <- names(df)

  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  num_table_md <- ""

  if (length(num_cols) > 0) {
    summary_data <- do.call(rbind, lapply(num_cols, function(cn) {
      vals <- df[[cn]]
      d <- data.frame(
        cn,
        mean(vals, na.rm = TRUE),
        median(vals, na.rm = TRUE),
        suppressWarnings(min(vals, na.rm = TRUE)),
        suppressWarnings(max(vals, na.rm = TRUE)),
        sum(!is.na(vals)),
        stringsAsFactors = FALSE
      )
      names(d) <- c("Sütun", "Ortalama", "Medyan", "Min", "Max", "Dolu Kayıt")
      d
    }))

    num_table_md <- paste0(
      "\n\n#### Sayısal Sütun Özeti\n",
      helpers_mcp_tools$create_md_table(summary_data)
    )
  }

  display_name <- res$display %||% basename(path)
  display_name <- tryCatch(enc2utf8(display_name), error = function(e) display_name)

  list(result = sprintf(
    "### Dosya Özeti: %s\n\n- **Satır Sayısı:** %d\n- **Sütun Sayısı:** %d\n- **Sütunlar:** %s%s",
    display_name,
    n_rows,
    n_cols,
    paste(cols, collapse = ", "),
    num_table_md
  ))
}

helpers_mcp_tools$get_column_statistics <- function(file_name, column, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)

  if (!isTRUE(res$ok)) return(list(error = res$error))
  if (is.null(column) || !nzchar(column)) return(list(error = "column parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)

  if (inherits(dt, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s \U2014 %s", basename(path), dt$message)))
  }

  if (!(column %in% names(dt))) {
    return(list(error = sprintf(
      "Sütun bulunamadı: **%s**. Mevcut sütunlar: %s",
      column,
      paste(names(dt), collapse = ", ")
    )))
  }

  vec <- dt[[column]]
  header <- sprintf("### İstatistikler: %s (%s)", column, basename(path))

  output_md <- ""
  if (is.numeric(vec)) {
    stats_df <- data.frame(
      c("Kayıt Sayısı", "Ortalama", "Medyan", "Minimum", "Maksimum", "Toplam", "Standart Sapma", "Boş Değer"),
      c(
        sum(!is.na(vec)),
        mean(vec, na.rm = TRUE),
        median(vec, na.rm = TRUE),
        suppressWarnings(min(vec, na.rm = TRUE)),
        suppressWarnings(max(vec, na.rm = TRUE)),
        sum(vec, na.rm = TRUE),
        sd(vec, na.rm = TRUE),
        sum(is.na(vec))
      ),
      stringsAsFactors = FALSE
    )
    names(stats_df) <- c("Metrik", "Değer")
    output_md <- paste0(header, "\n\n", helpers_mcp_tools$create_md_table(stats_df))
  } else {
    tb <- sort(table(vec, useNA = "ifany"), decreasing = TRUE)
    top5 <- head(tb, 10)

    stats_df <- data.frame(
      Deger = names(top5),
      Adet = as.numeric(top5),
      Oran = sprintf("%.1f%%", 100 * as.numeric(top5) / length(vec)),
      stringsAsFactors = FALSE
    )
    names(stats_df) <- c("De\u011fer", "Adet", "Oran")

    summary_text <- sprintf(
      "- **Benzersiz Değer Sayısı:** %d\n- **Boş Değer Sayısı:** %d",
      length(unique(vec)),
      sum(is.na(vec))
    )

    output_md <- paste0(
      header,
      "\n",
      summary_text,
      "\n\n#### En Sık Görülen Değerler\n",
      helpers_mcp_tools$create_md_table(stats_df)
    )
  }

  list(result = output_md)
}

helpers_mcp_tools$sql_query_uploaded_file <- function(file_name, sql, session = NULL) {
  if (!helpers_mcp_tools$safe_has_duckdb()) {
    return(list(error = "DuckDB yüklü değil. Lütfen install.packages('duckdb') çalıştırın."))
  }

  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)

  if (!isTRUE(res$ok)) return(list(error = res$error))
  if (is.null(sql) || !nzchar(sql)) return(list(error = "sql parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)

  if (inherits(dt, "error")) {
    return(list(error = sprintf("Excel dosyası okunamadı: %s \U2014 %s", basename(path), dt$message)))
  }

  for (nm in names(dt)) {
    if (inherits(dt[[nm]], "POSIXt") || inherits(dt[[nm]], "Date")) {
      dt[[nm]] <- as.character(dt[[nm]])
    }
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  DBI::dbWriteTable(con, "t", as.data.frame(dt), temporary = TRUE, overwrite = TRUE)

  q <- sql
  q <- gsub("`", "\"", q, fixed = TRUE)
  q <- gsub("\\[", "\"", q)
  q <- gsub("\\]", "\"", q)

  ans <- tryCatch(DBI::dbGetQuery(con, q), error = function(e) e)
  if (inherits(ans, "error")) {
    return(list(result = sprintf(
      "**SQL Hatası:** %s\n\n_İpucu: Tablo adı 't' olmalıdır. Stringler tek tırnak ile yazılmalıdır._",
      ans$message
    )))
  }

  ans <- helpers_mcp_tools$prettify_result_colnames(ans)

  preview <- ans
  limit_msg <- ""
  if (nrow(preview) > 20) {
    preview <- head(preview, 20)
    limit_msg <- sprintf("\n_(İlk 20 satır gösteriliyor. Toplam sonuç: %d satır)_", nrow(ans))
  }

  display_name <- res$display %||% basename(path)
  display_name <- tryCatch(enc2utf8(display_name), error = function(e) display_name)

  list(result = paste0(
    "### Sorgu Sonucu\n**Dosya:** ",
    display_name,
    "\n**SQL:** `",
    sql,
    "`\n\n",
    helpers_mcp_tools$create_md_table(preview),
    limit_msg
  ))
}

assign("helpers_mcp_tools", helpers_mcp_tools, envir = helpers_mcp_tools)

for (.mcp_basic_tool_fn in c(
  "safe_has_duckdb",
  "analyze_uploaded_file",
  "get_column_statistics",
  "sql_query_uploaded_file"
)) {
  if (exists(.mcp_basic_tool_fn, envir = helpers_mcp_tools, inherits = FALSE)) {
    .mcp_basic_tool_fun <- get(.mcp_basic_tool_fn, envir = helpers_mcp_tools, inherits = FALSE)

    if (is.function(.mcp_basic_tool_fun)) {
      environment(.mcp_basic_tool_fun) <- helpers_mcp_tools
      assign(.mcp_basic_tool_fn, .mcp_basic_tool_fun, envir = helpers_mcp_tools)
    }
  }
}

if (exists(".mcp_basic_tool_fn", inherits = FALSE)) {
  rm(.mcp_basic_tool_fn)
}

if (exists(".mcp_basic_tool_fun", inherits = FALSE)) {
  rm(.mcp_basic_tool_fun)
}

if (exists(".mcp_context_path", inherits = FALSE)) {
  rm(.mcp_context_path)
}