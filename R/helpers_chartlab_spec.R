# ==============================================================================
# Dosya Yolu: R/helpers_chartlab_spec.R
# Açıklama: ChartLab grafik türü, mapping ve agregasyon kararları için saf
#           yardımcılar. Shiny output kaydı veya widget motoru içermez.
# ==============================================================================

chartlab_is_numeric_or_date <- function(v) {
  is.numeric(v) || inherits(v, c("Date", "POSIXct", "POSIXt"))
}

chartlab_is_numeric <- function(v) {
  is.numeric(v)
}

chartlab_is_date <- function(v) {
  inherits(v, c("Date", "POSIXct", "POSIXt"))
}

chartlab_first_or_null <- function(x) {
  if (length(x)) x[[1]] else NULL
}

chartlab_normalize_chart_type <- function(chart_type) {
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

chartlab_normalize_mapping_value <- function(v) {
  if (is.null(v)) return(NULL)

  vv <- as.character(v)
  vv <- trimws(vv)
  vv <- vv[nzchar(vv)]

  if (!length(vv)) return(NULL)

  vv[[1]]
}

chartlab_auto_guess_spec <- function(sp) {
  sp$type <- chartlab_normalize_chart_type(sp$type)
  sp$mapping <- sp$mapping %||% list()

  df <- sp$data
  if (is.null(df) || !is.data.frame(df)) return(sp)

  date_cols <- names(df)[vapply(df, chartlab_is_date, logical(1))]
  num_cols  <- names(df)[vapply(df, chartlab_is_numeric, logical(1))]
  cat_cols  <- names(df)[vapply(df, function(x) is.character(x) || is.factor(x), logical(1))]

  if (length(date_cols) == 0 && length(cat_cols) > 0) {
    date_pattern <- "date|tarih|zaman|time|yil|year|month|ay|period|donem|gun|day|hafta|week"
    candidates <- grep(date_pattern, tolower(cat_cols), value = TRUE)

    if (length(candidates) > 0) {
      date_cols <- candidates
      cat_cols <- setdiff(cat_cols, candidates)
    }
  }

  x_ex <- chartlab_normalize_mapping_value(sp$mapping$x)
  y_ex <- chartlab_normalize_mapping_value(sp$mapping$y)
  g_ex <- chartlab_normalize_mapping_value(sp$mapping$group)

  all_cols <- names(df)

  if (!is.null(x_ex) && !(x_ex %in% all_cols)) {
    cat("[CHARTLAB] UYARI: x='", x_ex, "' sütunu yok, otomatik seçilecek\n", sep = "")
    x_ex <- NULL
  }

  if (!is.null(y_ex) && !(y_ex %in% all_cols)) {
    cat("[CHARTLAB] UYARI: y='", y_ex, "' sütunu yok, otomatik seçilecek\n", sep = "")
    y_ex <- NULL
  }

  if (!is.null(g_ex) && !(g_ex %in% all_cols)) {
    cat("[CHARTLAB] UYARI: group='", g_ex, "' sütunu yok, görmezden geliniyor\n", sep = "")
    g_ex <- NULL
  }

  known <- c("scatter", "line", "bar", "hist", "area", "pie", "donut", "pareto")

  if (!nzchar(sp$type) || !(sp$type %in% known)) {
    if (length(date_cols) > 0 && length(num_cols) > 0) {
      sp$type <- "line"
    } else if (length(num_cols) >= 2 && length(cat_cols) == 0) {
      sp$type <- "scatter"
    } else if (length(cat_cols) > 0 && length(num_cols) > 0) {
      sp$type <- "bar"
    } else if (length(num_cols) >= 1) {
      sp$type <- "hist"
    } else {
      sp$type <- "bar"
    }

    cat("[CHARTLAB] Grafik türü otomatik seçildi: ", sp$type, "\n", sep = "")
  }

  x <- x_ex
  y <- y_ex
  g <- g_ex

  if (sp$type %in% c("line", "area")) {
    if (is.null(x)) x <- chartlab_first_or_null(date_cols)
    if (is.null(x)) x <- chartlab_first_or_null(num_cols)
    if (is.null(y)) y <- chartlab_first_or_null(setdiff(num_cols, x))
    if (is.null(g) && length(cat_cols) > 0) g <- chartlab_first_or_null(cat_cols)

  } else if (sp$type %in% c("bar", "column")) {
    if (is.null(x)) x <- chartlab_first_or_null(cat_cols)
    if (is.null(x)) x <- chartlab_first_or_null(date_cols)
    if (is.null(x)) x <- names(df)[1]
    if (is.null(y)) y <- chartlab_first_or_null(num_cols)

  } else if (sp$type %in% c("pie", "donut")) {
    if (is.null(x)) x <- chartlab_first_or_null(cat_cols)
    if (is.null(x)) x <- names(df)[1]
    if (is.null(y)) y <- chartlab_first_or_null(num_cols)

  } else if (sp$type == "pareto") {
    if (is.null(x)) x <- chartlab_first_or_null(cat_cols)
    if (is.null(y)) y <- chartlab_first_or_null(num_cols)

  } else if (sp$type == "scatter") {
    if (is.null(x)) x <- chartlab_first_or_null(num_cols)
    if (is.null(y)) y <- chartlab_first_or_null(setdiff(num_cols, x))
    if (is.null(g) && length(cat_cols) > 0) g <- chartlab_first_or_null(cat_cols)

  } else if (sp$type == "hist") {
    if (is.null(x)) x <- chartlab_first_or_null(num_cols)
    y <- NULL
  }

  if (is.null(x) && sp$type != "hist") {
    cat("[CHARTLAB] UYARI: x ekseni bulunamadı, ilk sütun kullanılıyor\n")
    x <- names(df)[1]
  }

  sp$mapping$x <- x
  sp$mapping$y <- y
  sp$mapping$group <- g

  cat("[CHARTLAB] Final mapping: x=", x %||% "NULL", ", y=", y %||% "NULL", ", group=", g %||% "NULL", "\n", sep = "")

  sp
}

chartlab_aggregate_values <- function(z, f = "sum") {
  f <- tolower(f %||% "sum")

  if (identical(f, "mean")) {
    return(mean(z, na.rm = TRUE))
  }

  if (identical(f, "median")) {
    return(stats::median(z, na.rm = TRUE))
  }

  if (identical(f, "min")) {
    return(min(z, na.rm = TRUE))
  }

  if (identical(f, "max")) {
    return(max(z, na.rm = TRUE))
  }

  if (identical(f, "count")) {
    return(sum(!is.na(z)))
  }

  sum(z, na.rm = TRUE)
}