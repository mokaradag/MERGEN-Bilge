# R/helpers_chartlab.R

# Detect and convert ```chartlab ...``` into inline widget placeholders
# Returns list(found=<bool>, html=<html>, renderers=list(list(output_id, spec)))
build_chartlab_message <- function(raw_text, message_id, session) {
  txt <- as.character(raw_text %||% "")
  if (!grepl("```chartlab", txt, fixed = TRUE)) {
    return(list(found = FALSE))
  }

  parts <- list()
  remaining <- txt
  while (TRUE) {
    open <- regexpr("```chartlab\\s*", remaining, perl = TRUE)
    if (open[1] == -1) { parts <- append(parts, list(list(kind="text", value=remaining))); break }
    pre <- substr(remaining, 1, open[1]-1)
    parts <- append(parts, list(list(kind="text", value=pre)))
    rest <- substr(remaining, open[1] + attr(open,"match.length"), nchar(remaining))
    close <- regexpr("```", rest, perl = TRUE)
    if (close[1] == -1) { parts <- append(parts, list(list(kind="text", value=paste0("```chartlab\n", rest)))); break }
    json_block <- substr(rest, 1, close[1]-1)
    parts <- append(parts, list(list(kind="chart", value=json_block)))
    remaining <- substr(rest, close[1]+attr(close,"match.length"), nchar(rest))
  }

  html_chunks <- list()
  renderers <- list()
  chart_counter <- 0

  for (p in parts) {
    if (identical(p$kind, "text")) {
      if (nzchar(trimws(p$value))) {
        html_chunks <- append(
          html_chunks,
          commonmark::markdown_html(p$value, hardbreaks = TRUE, extensions = c("strikethrough", "table"))
        )
      }
    } else if (identical(p$kind, "chart")) {
      chart_counter <- chart_counter + 1
      out_id <- paste0("chart_", message_id, "_", chart_counter)

      spec <- NULL
      try(spec <- jsonlite::fromJSON(p$value, simplifyVector = TRUE), silent = TRUE)

      # Prefer inline data if present; otherwise resolve ref from chart_store
      if (!is.null(spec) && is.null(spec$data) && !is.null(spec$ref) &&
          !is.null(session$userData$chart_store) && is.list(session$userData$chart_store)) {
        stored <- session$userData$chart_store[[as.character(spec$ref)]]
        if (!is.null(stored) && is.list(stored)) spec <- stored
      }

      if (is.null(spec)) {
        html_chunks <- append(
          html_chunks,
          '<div class="chart-card"><div style="color:#f87171">Grafik tanımı çözümlenemedi (geçersiz JSON).</div></div>'
        )
      } else {
        container_html <- if (requireNamespace("highcharter", quietly = TRUE)) {
          as.character(highcharter::highchartOutput(out_id, height = "380px"))
        } else if (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)) {
          as.character(plotly::plotlyOutput(out_id, height = "380px"))
        } else {
          as.character(shiny::uiOutput(out_id, height = "380px"))
        }
        html_chunks <- append(html_chunks, sprintf('<div class="chart-card">%s</div>', container_html))
        renderers   <- append(renderers, list(list(output_id = out_id, spec = spec)))
      }
    }
  }

  list(found = (chart_counter > 0), html = paste(html_chunks, collapse = ""), renderers = renderers)
}

# Render one chart output id from a chart spec (Highcharter preferred, Plotly fallback)
# NOTE: helper takes 'output' explicitly
wire_chart_output <- function(output, out_id, spec) {
  is_num <- function(v) is.numeric(v) || inherits(v, c("Date","POSIXct","POSIXt"))
  first_or_null <- function(x) if (length(x)) x[[1]] else NULL

  # -------- auto guess missing mapping/type ----------
  auto_guess <- function(sp) {
    sp$type    <- tolower(sp$type %||% "")
    sp$mapping <- sp$mapping %||% list()
    df <- sp$data
    if (is.null(df) || !is.data.frame(df)) return(sp)

    num_cols <- names(df)[vapply(df, is_num, logical(1))]
    cat_cols <- names(df)[vapply(df, function(x) is.character(x) || is.factor(x), logical(1))]

    known <- c("scatter","line","bar","hist","area","pie","donut","pareto")
    if (!nzchar(sp$type) || !(sp$type %in% known)) {
      if (length(num_cols) >= 2)      sp$type <- "scatter"
      else if (length(num_cols) >= 1) sp$type <- "hist"
      else                            sp$type <- "bar"
    }

	norm_map <- function(v) if (is.character(v) && length(v) > 0 && nzchar(v[1])) v else NULL
    x <- norm_map(sp$mapping$x)
    y <- norm_map(sp$mapping$y) # [MODIFIED] Allow vector
    g <- norm_map(sp$mapping$group)

    if (sp$type %in% c("scatter","line","area")) {
      if (is.null(x)) x <- first_or_null(num_cols)
      if (is.null(y)) y <- first_or_null(setdiff(num_cols, x))
      if (is.null(x) || is.null(y)) {
        if (length(num_cols) >= 1) { sp$type <- "hist"; x <- first_or_null(num_cols) }
        else                        { sp$type <- "bar";  x <- first_or_null(cat_cols); y <- NULL }
      }
    } else if (sp$type == "hist") {
      if (is.null(x)) x <- first_or_null(num_cols)
      if (is.null(x) && length(cat_cols)) { sp$type <- "bar"; x <- first_or_null(cat_cols) }
    } else if (sp$type == "bar") {
      if (is.null(x)) x <- if (length(cat_cols)) first_or_null(cat_cols) else first_or_null(num_cols)
    } else if (sp$type %in% c("pie","donut")) {
      if (is.null(x)) x <- if (length(cat_cols)) first_or_null(cat_cols) else first_or_null(num_cols)
    }

    sp$mapping$x <- x; sp$mapping$y <- y; sp$mapping$group <- g
    sp
  }

  # ---------- normalize spec ----------
  spec <- auto_guess(spec)
  type   <- tolower(spec$type %||% "bar")
  map    <- spec$mapping %||% list()
  params <- spec$params  %||% list()
  df     <- tryCatch(as.data.frame(spec$data, stringsAsFactors = FALSE), error = function(e) NULL)

  if (!is.null(df)) {
    num_cols <- names(df)[vapply(df, is_num, logical(1))]
    if (length(num_cols)) for (cn in num_cols) df[[cn]] <- ifelse(is.finite(df[[cn]]), df[[cn]], NA_real_)
  }

  x     <- map$x; y <- map$y; grp <- map$group
  bins  <- params$bins  %||% NA_integer_
  agg   <- params$agg   %||% NULL
  topn  <- params$top_n %||% NA_integer_

  # Kutu grafik devre dışıysa güvenli görselleştirmeye düş (hist → bar)
  if (identical(type, "box")) {
    # Türkçe yorum: x ekseni için sayısal kolonu, yoksa kategorik kolonu kullan
    type <- "hist"
  }

  # ---------- engines ----------
  if (requireNamespace("highcharter", quietly = TRUE)) {
	output[[out_id]] <- highcharter::renderHighchart({
      library(highcharter)
      categorical_colors <- c("#60a5fa", "#a78bfa", "#34d399", "#f472b6", "#fbbf24", "#22d3ee", "#c084fc", "#f97316", "#10b981", "#6366f1")
      custom_theme <- highcharter::hc_theme(
        chart = list(backgroundColor = "transparent"),
        colors = categorical_colors,
        xAxis = list(labels = list(style = list(color = "#999")), gridLineColor = "#333", lineColor = "#444"),
        yAxis = list(labels = list(style = list(color = "#999")), gridLineColor = "#333", lineColor = "#444"),
        legend = list(itemStyle = list(color = "#999")),
        tooltip = list(backgroundColor = "#1a1a1a", borderColor = "#333", style = list(color = "#fff")),
        plotOptions = list(series = list(borderWidth = 0), pie = list(borderWidth = 0, dataLabels = list(color = "#fff", style = list(textOutline = "none")))),
        credits = list(enabled = FALSE)
      )
      hc <- highchart() %>% hc_exporting(enabled = TRUE) %>% hc_add_theme(custom_theme)

      aggfun <- function(z, f) {
        f <- tolower(f %||% "sum")
        fun <- switch(f, sum = sum, mean = mean, median = median, min = min, max = max, sum)
        fun(z, na.rm = TRUE)
      }

	if (identical(type,"hist")) {
        req(x)
        h <- hist(df[[x]], breaks = if (isTRUE(!is.na(bins))) bins else "Sturges", plot = FALSE)
        hchart(h) %>% hc_add_theme(custom_theme) %>% hc_subtitle(text = paste0("Otomatik: hist (x=", x, ")"))

      } else if (identical(type,"bar")) {
        if (!is.null(y)) {
          req(x)
          if (is.null(grp)) {
            dd <- aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) aggfun(z, agg))
            names(dd) <- c(x, "val")
		hchart(dd, "column", hcaes(x = !!rlang::sym(x), y = val)) %>% hc_add_theme(custom_theme)
          } else {
            dd <- stats::aggregate(df[[y]], by = list(df[[x]], df[[grp]]), FUN = function(z) aggfun(z, agg))
            names(dd) <- c(x, grp, "val")
            hchart(dd, "column", hcaes(x = !!rlang::sym(x), y = val, group = !!rlang::sym(grp))) %>% hc_add_theme(custom_theme)
          }
        } else {
          req(x)
          dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
          names(dd) <- c(x, "n")
          if (isTRUE(!is.na(topn))) dd <- head(dd, topn)
		  hchart(dd, "column", hcaes(x = !!rlang::sym(x), y = n)) %>% hc_add_theme(custom_theme)
        }

      } else if (identical(type,"pie") || identical(type,"donut")) {
        req(x)
        if (!is.null(y)) {
          dd <- aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) aggfun(z, params$agg))
          names(dd) <- c(x, "val")
        } else {
          dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
          names(dd) <- c(x, "val")
        }
        if (isTRUE(!is.na(topn))) dd <- head(dd, topn)
		pie_colors <- c("#60a5fa", "#a78bfa", "#34d399", "#f472b6", "#fbbf24", "#22d3ee", "#c084fc", "#f97316", "#10b981", "#6366f1")
        pie_data <- lapply(seq_len(nrow(dd)), function(i) {
          list(name = as.character(dd[[x]][i]), y = dd$val[i], color = pie_colors[((i - 1) %% length(pie_colors)) + 1])
        })
        inner <- if (identical(type,"donut") || isTRUE(params$donut)) "60%" else "0%"
        highchart() %>%
          hc_exporting(enabled = TRUE) %>% hc_add_theme(custom_theme) %>%
          hc_add_series(type = "pie", data = pie_data, innerSize = inner, name = x) %>%
          hc_plotOptions(pie = list(borderWidth = 0, dataLabels = list(enabled = TRUE, format = "<b>{point.name}</b>: {point.percentage:.1f}%", style = list(color = "#fff", textOutline = "none"))))

      } else if (identical(type, "pareto")) {
        req(x)
        if (!is.null(y)) {
          dd <- aggregate(df[[y]], by = list(df[[x]]),
                          FUN = function(z) { f <- tolower(agg %||% "sum"); fun <- switch(f, sum=sum, mean=mean, median=median, min=min, max=max, sum); fun(z, na.rm = TRUE) })
          names(dd) <- c(x, "val")
        } else {
          dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
          names(dd) <- c(x, "val")
        }
        dd <- dd[order(dd$val, decreasing = TRUE), , drop = FALSE]
        if (isTRUE(!is.na(topn))) dd <- head(dd, topn)
        dd$cum <- cumsum(dd$val); tot <- sum(dd$val, na.rm = TRUE)
        dd$cum_pct <- if (tot > 0) 100 * dd$cum / tot else 0
        highchart() %>% hc_add_theme(custom_theme) %>% hc_exporting(enabled = TRUE) %>% hc_xAxis(categories = dd[[x]]) %>%
          hc_yAxis_multiples(
            list(title = list(text = "Değer")),
            list(title = list(text = "Kümülatif %"), opposite = TRUE, max = 100,
                 labels = list(format = "{value}%"))
          ) %>%
          hc_add_series(name = "Değer", type = "column", data = dd$val, yAxis = 0) %>%
          hc_add_series(name = "Kümülatif %", type = "line", data = round(dd$cum_pct, 2), yAxis = 1,
                        tooltip = list(valueSuffix = "%")) %>%
          hc_tooltip(shared = TRUE)
	  } else if (identical(type,"line")) {
        req(x, y)
        if (is.null(grp)) hchart(df, "line", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y))) %>% hc_add_theme(custom_theme)
        else              hchart(df, "line", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y), group = !!rlang::sym(grp))) %>% hc_add_theme(custom_theme)
	  } else if (identical(type,"scatter")) {
        req(x, y)
        if (is.null(grp)) hchart(df, "scatter", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y))) %>% hc_add_theme(custom_theme)
        else              hchart(df, "scatter", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y), group = !!rlang::sym(grp))) %>% hc_add_theme(custom_theme)
	  } else if (identical(type,"area")) {
        req(x, y)
        if (is.null(grp)) hchart(df, "area", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y))) %>% hc_add_theme(custom_theme)
        else              hchart(df, "area", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y), group = !!rlang::sym(grp))) %>% hc_add_theme(custom_theme)
	  } else {
        highchart() %>% hc_add_theme(custom_theme) %>% hc_title(text = "Bilinmeyen grafik türü")
      }
    })
    return(invisible(TRUE))
  }

  if (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)) {
    output[[out_id]] <- plotly::renderPlotly({
      library(ggplot2); library(plotly)
      aggfun <- function(z, f) {
        f <- tolower(f %||% "sum")
        fun <- switch(f, sum = sum, mean = mean, median = median, min = min, max = max, sum)
        fun(z, na.rm = TRUE)
      }
      p <- NULL
      if (identical(type,"hist")) {
        req(x); p <- ggplot(df, aes(x = .data[[x]])) + geom_histogram(bins = ifelse(isTRUE(!is.na(bins)), bins, 30))
      } else if (identical(type,"bar")) {
        if (!is.null(y)) {
          req(x)
          if (is.null(grp)) {
            dd <- aggregate(df[[y]], by=list(df[[x]]), FUN = function(z) aggfun(z, agg)); names(dd) <- c(x, "val")
            p <- ggplot(dd, aes(x = .data[[x]], y = val)) + geom_col()
          } else {
            dd <- stats::aggregate(df[[y]], by=list(df[[x]], df[[grp]]), FUN = function(z) aggfun(z, agg)); names(dd) <- c(x, grp, "val")
            p <- ggplot(dd, aes(x = .data[[x]], y = val, fill = .data[[grp]])) + geom_col(position = "stack")
          }
        } else {
          req(x)
          dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE)); names(dd) <- c(x, "n")
          if (isTRUE(!is.na(topn))) dd <- head(dd, topn)
          p <- ggplot(dd, aes(x = .data[[x]], y = n)) + geom_col()
        }
      } else if (identical(type,"pie") || identical(type,"donut")) {
        req(x)
        if (!is.null(y)) {
          dd <- aggregate(df[[y]], by = list(df[[x]]),
                          FUN = function(z) { f <- tolower(agg %||% "sum"); fun <- switch(f, sum=sum, mean=mean, median=median, min=min, max=max, sum); fun(z, na.rm = TRUE) })
          names(dd) <- c(x, "val")
        } else {
          dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE)); names(dd) <- c(x, "val")
        }
        if (isTRUE(!is.na(topn))) dd <- head(dd, topn)
        return(plotly::plot_ly(dd, labels = ~ .data[[x]], values = ~ val, type = "pie",
                               hole = if (identical(type,"donut") || isTRUE(params$donut)) 0.6 else 0))
      } else if (identical(type, "pareto")) {
        req(x)
        if (!is.null(y)) {
          dd <- aggregate(df[[y]], by = list(df[[x]]),
                          FUN = function(z) { f <- tolower(agg %||% "sum"); fun <- switch(f, sum=sum, mean=mean, median=median, min=min, max=max, sum); fun(z, na.rm = TRUE) })
          names(dd) <- c(x, "val")
        } else {
          dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE)); names(dd) <- c(x, "val")
        }
        dd <- dd[order(dd$val, decreasing = TRUE), , drop = FALSE]
        if (isTRUE(!is.na(topn))) dd <- head(dd, topn)
        dd$cum <- cumsum(dd$val); tot <- sum(dd$val, na.rm = TRUE)
        dd$cum_pct <- if (tot > 0) 100 * dd$cum / tot else 0

        return(
          plotly::plot_ly() %>%
            plotly::add_bars(x = dd[[x]], y = dd$val, name = "Değer", yaxis = "y1") %>%
            plotly::add_lines(x = dd[[x]], y = dd$cum_pct, name = "Kümülatif %", yaxis = "y2") %>%
            plotly::layout(yaxis2 = list(overlaying = "y", side = "right", range = c(0,100), ticksuffix = "%"))
        )
      } else if (identical(type,"line")) {
        req(x, y); p <- ggplot(df, aes(x = .data[[x]], y = .data[[y]], color = .data[[grp]])) + geom_line()
      } else if (identical(type,"scatter")) {
        req(x, y); p <- ggplot(df, aes(x = .data[[x]], y = .data[[y]], color = .data[[grp]])) + geom_point(alpha = 0.8)
      } else if (identical(type,"area")) {
        req(x, y); p <- ggplot(df, aes(x = .data[[x]], y = .data[[y]], fill = .data[[grp]])) + geom_area(position = "stack")
      } else {
        p <- ggplot() + ggtitle("Bilinmeyen grafik türü")
      }
      plotly::ggplotly(p)
    })
    return(invisible(TRUE))
  }

  output[[out_id]] <- shiny::renderUI({
    div(style="color:#f87171", "Grafik motoru bulunamadı (highcharter veya plotly+ggplot2 yükleyin).")
  })
  invisible(FALSE)
}

build_chartlab_message_static <- function(raw_text, message_id) {
  txt <- as.character(raw_text %||% "")
  if (!grepl("```chartlab", txt, fixed = TRUE)) {
    return(list(found = FALSE))
  }

  parts <- list()
  remaining <- txt
  while (TRUE) {
    open <- regexpr("```chartlab\\s*", remaining, perl = TRUE)
    if (open[1] == -1) { parts <- append(parts, list(list(kind="text", value=remaining))); break }
    pre <- substr(remaining, 1, open[1]-1)
    parts <- append(parts, list(list(kind="text", value=pre)))
    rest <- substr(remaining, open[1] + attr(open,"match.length"), nchar(remaining))
    close <- regexpr("```", rest, perl = TRUE)
    if (close[1] == -1) { parts <- append(parts, list(list(kind="text", value=paste0("```chartlab\n", rest)))); break }
    json_block <- substr(rest, 1, close[1]-1)
    parts <- append(parts, list(list(kind="chart", value=json_block)))
    remaining <- substr(rest, close[1]+attr(close,"match.length"), nchar(rest))
  }

  html_chunks <- list()
  chart_counter <- 0
  renderers <- list()

  for (p in parts) {
    if (identical(p$kind, "text")) {
      if (nzchar(trimws(p$value))) {
        html_chunks <- append(
          html_chunks,
          commonmark::markdown_html(p$value, hardbreaks = TRUE, extensions = c("strikethrough", "table"))
        )
      }
    } else if (identical(p$kind, "chart")) {
      chart_counter <- chart_counter + 1
      out_id <- paste0("chart_", message_id, "_", chart_counter)

      spec <- NULL
      try(spec <- jsonlite::fromJSON(p$value, simplifyVector = TRUE), silent = TRUE)

      if (is.null(spec)) {
        html_chunks <- append(
          html_chunks,
          '<div class="chart-card"><div style="color:#f87171">Grafik tanımı çözümlenemedi.</div></div>'
        )
      } else {
        container_html <- sprintf(
          '<div class="chart-card" data-chartlab-spec="%s" data-chart-id="%s"><div class="chartlab-placeholder" id="%s" style="min-height:380px;display:flex;align-items:center;justify-content:center;"><span style="color:#9ca3af;">Grafik yükleniyor...</span></div></div>',
          htmltools::htmlEscape(p$value, attribute = TRUE),
          out_id,
          out_id
        )
        html_chunks <- append(html_chunks, container_html)
        renderers <- append(renderers, list(list(output_id = out_id, spec = spec)))
      }
    }
  }

  list(found = (chart_counter > 0), html = paste(html_chunks, collapse = ""), renderers = renderers)
}