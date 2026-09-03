# ==============================================================================
# Dosya Yolu: R/helpers_mcp_chart_tools.R
# Açıklama: MCP grafik veri hazırlama aracını helpers_mcp_tools ortamına ekler.
# ==============================================================================

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  .mcp_context_path <- file.path("R", "helpers_mcp_context.R")

  if (!file.exists(.mcp_context_path)) {
    stop(
      "R/helpers_mcp_context.R bulunamadı; helpers_mcp_chart_tools.R yüklenemiyor.",
      call. = FALSE
    )
  }

  source(.mcp_context_path, encoding = "UTF-8", local = globalenv())
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

.mcp_prepare_chart_data_fn <- function(
  file_name,
  chart_type,
  x = NULL,
  y = NULL,
  group = NULL,
  agg = NULL,
  bins = NULL,
  top_n = NULL,
  stack = NULL,
  donut = NULL,
  orientation = NULL,
  smooth = NULL,
  filter_sql = NULL,
  limit = 5000,
  session = NULL
) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  chart_type <- helpers_mcp_tools$normalize_chart_type(chart_type)

  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error, ok = FALSE))

  dt <- tryCatch({
    helpers_mcp_tools$safe_read_table_generic(res$path)
  }, error = function(e) e)

  if (inherits(dt, "error")) {
    return(list(
      error = sprintf("Dosya okunamadı: %s \U2014 %s", basename(res$path), dt$message),
      ok = FALSE
    ))
  }

  available_cols <- names(dt)

  smart_match_column <- function(col_name, col_type = "any") {
    if (is.null(col_name) || !nzchar(col_name)) return(NULL)
    if (col_name %in% available_cols) return(col_name)

    matched <- helpers_mcp_tools$find_matching_column(col_name, available_cols)
    if (!is.null(matched)) {
      helpers_mcp_tools$mcp_debug_log(sprintf(
        "[CHART_SMART_MATCH] '%s' -> '%s'",
        col_name,
        matched
      ))
      return(matched)
    }

    NULL
  }

  if (!is.null(x) && nzchar(x) && !(x %in% available_cols)) {
    matched_x <- smart_match_column(x)
    if (!is.null(matched_x)) {
      x <- matched_x
    } else {
      helpers_mcp_tools$mcp_debug_log(sprintf(
        "[CHART] x='%s' sütunu bulunamadı, otomatik seçilecek",
        x
      ))
      x <- NULL
    }
  }

  if (!is.null(y) && nzchar(y)) {
    y_parts <- trimws(strsplit(as.character(y), ",")[[1]])

    resolved_y <- vapply(y_parts, function(yp) {
      if (yp %in% available_cols) return(yp)
      matched <- smart_match_column(yp)
      if (!is.null(matched)) return(matched)
      ""
    }, character(1))

    resolved_y <- resolved_y[nzchar(resolved_y)]

    if (length(resolved_y) > 0) {
      y <- paste(resolved_y, collapse = ", ")
    } else {
      helpers_mcp_tools$mcp_debug_log(sprintf(
        "[CHART] y sütunları bulunamadı: %s, otomatik seçilecek",
        paste(y_parts, collapse = ", ")
      ))
      y <- NULL
    }
  }

  if (!is.null(group) && nzchar(group) && !(group %in% available_cols)) {
    matched_group <- smart_match_column(group)
    if (!is.null(matched_group)) {
      group <- matched_group
    } else {
      helpers_mcp_tools$mcp_debug_log(sprintf(
        "[CHART] group='%s' sütunu bulunamadı, otomatik seçilecek",
        group
      ))
      group <- NULL
    }
  }

  if (tolower(chart_type) %in% c("pie", "donut")) {
    if (is.null(x) || !nzchar(x)) {
      cat_cols <- names(dt)[vapply(dt, function(v) is.character(v) || is.factor(v), logical(1))]
      if (length(cat_cols)) {
        x <- cat_cols[1]
      } else {
        x <- names(dt)[1]
      }
    }

    if (is.null(y) || !nzchar(y)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      num_cols <- setdiff(num_cols, x)
      if (length(num_cols)) {
        y <- num_cols[1]
      }
    }

    if (is.null(agg) || !nzchar(agg)) {
      agg <- "sum"
    }

    if (is.null(top_n) || is.na(top_n) || !is.numeric(top_n)) {
      top_n <- 10
    } else if (top_n > 20) {
      top_n <- 20
    }
  }

  is_date_col <- function(v) inherits(v, c("Date", "POSIXct", "POSIXt"))
  is_numeric_col <- function(v) is.numeric(v)
  is_cat_col <- function(v) is.character(v) || is.factor(v)

  date_cols <- names(dt)[vapply(dt, is_date_col, logical(1))]
  num_cols <- names(dt)[vapply(dt, is_numeric_col, logical(1))]
  cat_cols <- names(dt)[vapply(dt, is_cat_col, logical(1))]

  if (length(date_cols) == 0 && length(cat_cols) > 0) {
    date_pattern <- "date|tarih|zaman|time|yil|year|month|ay|period|donem"
    date_candidates <- grep(date_pattern, tolower(cat_cols), value = TRUE)
    if (length(date_candidates) > 0) {
      date_cols <- date_candidates
      cat_cols <- setdiff(cat_cols, date_candidates)
    }
  }

  first_or_null <- function(vec) if (length(vec)) vec[1] else NULL

  if (tolower(chart_type) %in% c("line", "area")) {
    # Çizgi/alan grafiği için X ekseni öncelik sırası:
    # 1) Tarih sütunu (varsa) -> zaman serisi gerçek çizgi grafik üretir
    # 2) Kategorik sütun -> ay/bölge/kategori bazlı çizgi grafik (orijinal sırayı korur)
    # 3) Sayısal sütun -> son çare; yalnızca tarih ve kategori yoksa kullanılır
    # Eski mantık doğrudan num_cols'a düşüyor ve iki sayısal sütunu noktalarla
    # eşleştirip görsel olarak scatter benzeri çıktı üretiyordu.
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(date_cols)
      if (is.null(x)) x <- first_or_null(cat_cols)
      if (is.null(x)) x <- first_or_null(num_cols)
    }

    if (is.null(y) || !nzchar(y)) {
      y <- first_or_null(setdiff(num_cols, x))
      if (is.null(y)) y <- first_or_null(num_cols)
    }

    # Group sadece X kategorik DEĞİLSE atanır; aksi halde X ve group çakışır
    if (is.null(group) && length(cat_cols) > 0 && !(x %in% cat_cols)) {
      group <- first_or_null(setdiff(cat_cols, x))
    }
  }

  if (tolower(chart_type) %in% c("bar", "column")) {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(cat_cols)
      if (is.null(x)) x <- first_or_null(date_cols)
    }

    if (is.null(y) || !nzchar(y)) {
      y <- first_or_null(num_cols)
    }
  }

  if (tolower(chart_type) == "scatter") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(num_cols)
    }

    if (is.null(y) || !nzchar(y)) {
      y <- first_or_null(setdiff(num_cols, x))
    }

    if (is.null(group) && length(cat_cols) > 0) {
      group <- first_or_null(cat_cols)
    }
  }

  if (tolower(chart_type) == "hist") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(num_cols)
    }

    y <- NULL
  }

  if (tolower(chart_type) == "pareto") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(cat_cols)
    }

    if (is.null(y) || !nzchar(y)) {
      y <- first_or_null(num_cols)
    }

    if (is.null(agg) || !nzchar(agg)) {
      agg <- "sum"
    }
  }

  if (!is.null(filter_sql) && nzchar(filter_sql) && helpers_mcp_tools$safe_has_duckdb()) {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

    DBI::dbWriteTable(con, "t", as.data.frame(dt), temporary = TRUE, overwrite = TRUE)

    q <- sprintf("SELECT * FROM t WHERE %s", filter_sql)
    q <- gsub("`", "\"", q, fixed = TRUE)
    q <- gsub("\\[", "\"", q)
    q <- gsub("\\]", "\"", q)

    filt <- tryCatch(DBI::dbGetQuery(con, q), error = function(e) e)
    if (!inherits(filt, "error")) dt <- data.table::as.data.table(filt)
  }

  if (is.null(y)) {
    y_candidates <- NULL
  } else if (is.character(y) || is.list(y)) {
    raw_y <- unlist(y, use.names = FALSE)
    if (length(raw_y) > 1) {
      y_candidates <- trimws(raw_y)
    } else {
      y_candidates <- trimws(strsplit(as.character(raw_y), ",")[[1]])
    }
  } else {
    y_candidates <- NULL
  }

  if (tolower(chart_type) %in% c("pie", "donut", "bar", "column") && is.null(agg)) {
    row_limit_for_raw <- 20
    if (nrow(dt) > row_limit_for_raw) {
      if (!is.null(y_candidates) && length(y_candidates) > 0) {
        agg <- "sum"
      } else {
        agg <- "count"
      }
    }
  }

  if (length(y_candidates) > 1) {
    missing <- setdiff(c(x, y_candidates, group), names(dt))
    if (length(missing)) {
      return(list(
        error = sprintf("Sütun(lar) bulunamadı: %s", paste(missing, collapse = ", ")),
        ok = FALSE
      ))
    }

    measure_vars <- y_candidates
    id_vars <- c(x, group)
    id_vars <- id_vars[!is.null(id_vars)]

    subset_dt <- data.table::melt(
      dt,
      id.vars = id_vars,
      measure.vars = measure_vars,
      variable.name = "Variable",
      value.name = "Value"
    )

    y <- "Value"

    if (is.null(group)) {
      group <- "Variable"
    } else {
      group <- "Variable"
    }
  } else {
    cols <- unique(na.omit(c(x, y, group)))

    if (!length(cols)) {
      subset_dt <- dt
    } else {
      missing <- setdiff(cols, names(dt))
      if (length(missing)) {
        return(list(
          error = sprintf(
            "Sütun(lar) bulunamadı: %s. Mevcut: %s",
            paste(missing, collapse = ", "),
            paste(names(dt), collapse = ", ")
          ),
          ok = FALSE
        ))
      }

      subset_dt <- dt[, ..cols]
    }
  }

  if (is.finite(limit) && nrow(subset_dt) > limit) {
    subset_dt <- head(subset_dt, limit)
  }

  for (nm in names(subset_dt)) {
    if (inherits(subset_dt[[nm]], "POSIXt")) next
    if (inherits(subset_dt[[nm]], "Date")) next
  }

  schema <- vapply(subset_dt, function(z) class(z)[1], character(1))

  list(
    ok = TRUE,
    `__mcp_plot` = TRUE,
    file = basename(res$path),
    chart = list(
      type = tolower(chart_type),
      mapping = list(x = x, y = y, group = group),
      params = list(
        agg = agg,
        bins = bins,
        top_n = top_n,
        stack = stack,
        donut = donut,
        orientation = orientation,
        smooth = smooth
      ),
      data = as.data.frame(subset_dt),
      schema = as.list(schema),
      n = nrow(subset_dt)
    ),
    message = "Grafik verileri hazırlandı; ChartLab'a iletildi."
  )
}

environment(.mcp_prepare_chart_data_fn) <- helpers_mcp_tools
helpers_mcp_tools$prepare_chart_data <- .mcp_prepare_chart_data_fn
assign("helpers_mcp_tools", helpers_mcp_tools, envir = helpers_mcp_tools)

rm(.mcp_prepare_chart_data_fn)

if (exists(".mcp_context_path", inherits = FALSE)) {
  rm(.mcp_context_path)
}