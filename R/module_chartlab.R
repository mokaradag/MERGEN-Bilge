# R/module_chartlab.R

#' ChartLab UI
chartLabUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$head(tags$style(HTML("
      .chartlab-wrap { padding: 16px; }
      .chart-card {
        background: #0f0f10; border: 1px solid #262626; border-radius: 12px;
        padding: 16px; margin-bottom: 16px;
      }
      .chart-card .chart-title { font-weight: 700; margin-bottom: 8px; }
      .chart-card .chart-meta  { color: #9ca3af; font-size: 12px; margin-bottom: 8px; }
    "))),
    div(class = "chartlab-wrap",
        uiOutput(ns("charts_container"))
    )
  )
}

mergen_dark_theme <- function() {
  categorical_colors <- c("#60a5fa", "#a78bfa", "#34d399", "#f472b6", "#fbbf24", "#22d3ee", "#c084fc", "#f97316", "#10b981", "#6366f1")
  sequential_colors <- c("#1e3a5f", "#2563eb", "#3b82f6", "#60a5fa", "#93c5fd", "#bfdbfe", "#dbeafe")
  diverging_colors <- c("#ef4444", "#f97316", "#fbbf24", "#fef3c7", "#a7f3d0", "#34d399", "#10b981")
  highcharter::hc_theme(
    chart = list(
      backgroundColor = "transparent",
      style = list(fontFamily = "Inter, system-ui, -apple-system, sans-serif")
    ),
    colors = categorical_colors,
    title = list(style = list(color = "#fff", fontWeight = "600")),
    subtitle = list(style = list(color = "#999")),
    xAxis = list(
      labels = list(style = list(color = "#999")),
      title = list(style = list(color = "#999")),
      gridLineColor = "#333",
      lineColor = "#444",
      tickColor = "#444"
    ),
    yAxis = list(
      labels = list(style = list(color = "#999")),
      title = list(style = list(color = "#999")),
      gridLineColor = "#333",
      lineColor = "#444",
      tickColor = "#444"
    ),
    legend = list(
      itemStyle = list(color = "#999"),
      itemHoverStyle = list(color = "#fff"),
      itemHiddenStyle = list(color = "#666")
    ),
    tooltip = list(
      backgroundColor = "#1a1a1a",
      borderColor = "#333",
      style = list(color = "#fff")
    ),
    plotOptions = list(
      series = list(borderWidth = 0),
      column = list(borderWidth = 0, borderRadius = 4),
      bar = list(borderWidth = 0, borderRadius = 4),
      pie = list(
        borderWidth = 0,
        dataLabels = list(
          color = "#fff",
          style = list(textOutline = "none")
        )
      ),
      area = list(
        fillOpacity = 0.25,
        marker = list(enabled = FALSE)
      ),
      areaspline = list(
        fillOpacity = 0.25,
        marker = list(enabled = FALSE)
      ),
      line = list(
        lineWidth = 2.5,
        marker = list(enabled = TRUE, radius = 3)
      ),
      spline = list(
        lineWidth = 2.5,
        marker = list(enabled = TRUE, radius = 3)
      ),
      scatter = list(
        marker = list(radius = 5, symbol = "circle")
      )
    ),
    credits = list(enabled = FALSE)
  )
}

#' ChartLab Server
#' Exposes: $push_spec(spec)  where spec is result$chart from prepare_chart_data
chartLabServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rv <- reactiveValues(items = list(), order = character(0), counter = 0)

    # helpers ---------------------------------------------------------
    have_hc <- reactive({ requireNamespace("highcharter", quietly = TRUE) })
    have_pl <- reactive({ requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE) })

    make_id <- function() paste0("cl_", as.integer(as.numeric(Sys.time())*1000), "_", sample(1000:9999,1))
	
	# === NEW: auto-guess mapping/type when tool spec lacks them ===
    auto_guess_chart_spec <- function(sp) {
      is_num <- function(v) is.numeric(v)
      is_date <- function(v) inherits(v, c("Date","POSIXct","POSIXt"))
      first_or_null <- function(x) if (length(x)) x[[1]] else NULL

      sp$type    <- tolower(sp$type %||% "")
      # box/boxplot is no longer supported - hard-fallback to histogram
      if (sp$type %in% c("box","boxplot","box_plot","bx")) sp$type <- "hist"
      sp$mapping <- sp$mapping %||% list()
      
      df <- tryCatch(as.data.frame(sp$data, stringsAsFactors = FALSE), error = function(e) NULL)
      if (is.null(df) || !is.data.frame(df) || !ncol(df)) return(sp)

      # Sütun tiplerini daha hassas ayır
      date_cols <- names(df)[vapply(df, is_date, logical(1))]
      num_cols  <- names(df)[vapply(df, is_num, logical(1))]
      cat_cols  <- names(df)[vapply(df, function(x) is.character(x) || is.factor(x), logical(1))]

      # String formatında tarih varsa yakala (basit kontrol)
      if (length(date_cols) == 0 && length(cat_cols) > 0) {
         candidates <- grep("date|tarih|zaman|time|yil|year|month|ay", tolower(cat_cols), value=TRUE)
         if (length(candidates) > 0) {
             date_cols <- candidates
             cat_cols <- setdiff(cat_cols, candidates)
         }
      }

      known <- c("scatter","line","bar","hist","area","pie","donut","pareto")
      
      # 1. Grafik Türü Tahmini (Eğer belirtilmemişse)
      if (!nzchar(sp$type) || !(sp$type %in% known)) {
        if (length(date_cols) > 0 && length(num_cols) > 0) {
           sp$type <- "line" # Zaman serisi öncelikli
        } else if (length(num_cols) >= 2 && length(cat_cols) == 0) {
           sp$type <- "scatter"
        } else if (length(cat_cols) > 0 && length(num_cols) > 0) {
           sp$type <- "bar"
        } else if (length(num_cols) >= 1) {
           sp$type <- "hist"
        } else {
           sp$type <- "bar" # Fallback
        }
      }

      x <- sp$mapping$x
      y <- sp$mapping$y
      g <- sp$mapping$group

      # 2. Eksen Tahmini (Grafik türüne göre)
      if (sp$type %in% c("line", "area")) {
         # X: Tarih > Sayısal (Index)
         if (is.null(x)) x <- first_or_null(date_cols)
         if (is.null(x)) x <- first_or_null(num_cols)
         # Y: Sayısal (X olmayan)
         if (is.null(y)) y <- first_or_null(setdiff(num_cols, x))
         # Group: Kategori
         if (is.null(g)) g <- first_or_null(cat_cols)
         
      } else if (sp$type %in% c("bar", "column", "pie", "donut", "pareto")) {
         # X: Kategori > Tarih
         if (is.null(x)) x <- first_or_null(cat_cols)
         if (is.null(x)) x <- first_or_null(date_cols)
         # Y: Sayısal
         if (is.null(y)) y <- first_or_null(num_cols)
         
      } else if (sp$type == "scatter") {
         if (is.null(x)) x <- first_or_null(num_cols)
         if (is.null(y)) y <- first_or_null(setdiff(num_cols, x))
         if (is.null(g)) g <- first_or_null(cat_cols)
         
      } else if (sp$type == "hist") {
         if (is.null(x)) x <- first_or_null(num_cols)
      }

      sp$mapping$x <- x; sp$mapping$y <- y; sp$mapping$group <- g
      sp
    }

    # renderer for one item ------------------------------------------
	render_one <- function(out_id, spec, file_label) {
      # NEW: fill in missing type/mapping before we read variables
      spec   <- auto_guess_chart_spec(spec)

      type   <- spec$type %||% "scatter"
      map    <- spec$mapping %||% list()
      # [MODIFIED] Ensure y is captured as vector if list
      if (!is.null(map$y)) map$y <- unlist(map$y, use.names = FALSE)
      params <- spec$params  %||% list()
      df     <- tryCatch(as.data.frame(spec$data, stringsAsFactors = FALSE), error = function(e) NULL)

      x <- map$x; y <- map$y; grp <- map$group
      bins <- params$bins %||% NA_integer_
      agg  <- params$agg  %||% NULL
      top_n <- params$top_n %||% NA_integer_

      # new rendering params
      donut       <- isTRUE(params$donut)
      stack       <- tolower(params$stack %||% "none")     # "none" | "normal" | "percent"
      orientation <- tolower(params$orientation %||% "v")  # "v" (column) | "h" (bar)
      smooth      <- isTRUE(params$smooth)                 # line/area smoothing

      # ensure x,y exist if referenced
      if (!is.null(x) && !x %in% names(df)) x <- NULL
      if (!is.null(y) && !y %in% names(df)) y <- NULL
      if (!is.null(grp) && !grp %in% names(df)) grp <- NULL

      # numeric sanitiser: replace non-finite numerics with NA to avoid JS issues
      if (!is.null(df)) {
        num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
        if (length(num_cols)) {
          for (cn in num_cols) df[[cn]] <- ifelse(is.finite(df[[cn]]), df[[cn]], NA_real_)
        }
      }

      # choose engine
      if (have_hc()) {
		output[[out_id]] <- highcharter::renderHighchart({
          library(highcharter)
          hc <- highchart() %>% hc_exporting(enabled = TRUE) %>%
            hc_title(text = paste0(toupper(type), " \U2014 ", file_label)) %>%
            hc_add_theme(mergen_dark_theme())

          # Flip chart to horizontal if requested (safer than switching to 'bar' in complex combos)
          if (orientation %in% c("h","horizontal")) {
            hc <- hc %>% hc_chart(inverted = TRUE)
          }

          if (identical(type,"hist")) {
            if (is.null(x)) stop("hist requires x")
            h <- hist(df[[x]], breaks = if (isTRUE(!is.na(bins))) bins else "Sturges", plot = FALSE)
            hc <- hc %>% hchart(h)
			} else if (identical(type, "pie") || identical(type, "donut")) {
			  # Pie/Donut: prefer a categorical x; auto-pick if missing
			  if (is.null(x) || !nzchar(x)) {
				cat_cols <- names(df)[vapply(df, function(v) is.character(v) || is.factor(v), logical(1))]
				if (length(cat_cols)) x <- cat_cols[1]
			  }
              # [MODIFIED] Fallback: If no categorical, use the first column as X (force string)
              if (is.null(x) && ncol(df) > 0) x <- names(df)[1]

			  validate(need(!is.null(x) && nzchar(x), "Pie/Donut için veri sütunu eksik."))

			  # y varsa x'e göre özet; yoksa x sayımları
			  if (!is.null(y)) {
				f  <- if (is.null(agg)) "sum" else tolower(agg)
				fn <- switch(f, sum = sum, mean = mean, median = median, min = min, max = max, sum)
				dd <- aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) fn(z, na.rm = TRUE))
				names(dd) <- c(x, "val")
			  } else {
				dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
				names(dd) <- c(x, "val")
			  }
			  if (isTRUE(!is.na(top_n))) dd <- head(dd, top_n)

			  # Consistently build on the same 'hc' to avoid flicker
			pie_colors <- c("#60a5fa", "#a78bfa", "#34d399", "#f472b6", "#fbbf24", "#22d3ee", "#c084fc", "#f97316", "#10b981", "#6366f1")
			  pie_data <- lapply(seq_len(nrow(dd)), function(i) {
			    list(name = as.character(dd[[x]][i]), y = dd$val[i], color = pie_colors[((i - 1) %% length(pie_colors)) + 1])
			  })
			  hc <- hc %>%
			    hc_add_series(type = "pie", data = pie_data, name = x) %>%
			    hc_plotOptions(pie = list(
			      innerSize = if (identical(type, "donut") || donut) "60%" else "0%",
			      borderWidth = 0,
			      dataLabels = list(enabled = TRUE, format = "<b>{point.name}</b>: {point.percentage:.1f}%", style = list(color = "#fff", textOutline = "none"))
			    ))
          } else if (identical(type,"bar")) {
            # Unified vertical/horizontal bars with optional stacking and optional y-aggregation
            chart_type <- if (orientation %in% c("h", "horizontal")) "bar" else "column"

            if (!is.null(y)) {
              f <- if (is.null(agg)) "sum" else tolower(agg)
              fun <- switch(f, sum = sum, mean = mean, median = median, min = min, max = max, sum)
              if (is.null(grp)) {
                dd <- aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) fun(z, na.rm = TRUE))
                names(dd) <- c(x, "val")
                hc <- hc %>%
                  hchart(dd, chart_type, hcaes(x = !!rlang::sym(x), y = val))
              } else {
                dd <- stats::aggregate(df[[y]], by = list(df[[x]], df[[grp]]),
                                       FUN = function(z) fun(z, na.rm = TRUE))
                names(dd) <- c(x, grp, "val")
                hc <- hc %>%
                  hchart(dd, chart_type, hcaes(x = !!rlang::sym(x), y = val, group = !!rlang::sym(grp)))
              }
            } else {
              # counts of x
              dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
              names(dd) <- c(x, "n")
              if (isTRUE(!is.na(top_n))) dd <- head(dd, top_n)
              hc <- hc %>% hchart(dd, chart_type, hcaes(x = !!rlang::sym(x), y = n))
            }

            # stacking: "none" | "normal" | "percent"
            st <- switch(stack,
                         "normal" = "normal",
                         "percent" = "percent",
                         NULL)
            if (!is.null(st)) {
              hc <- hc %>% hc_plotOptions(series = list(stacking = st))
            }

          } else if (identical(type,"line")) {
            req(x, y)
            ltype <- if (smooth) "spline" else "line"
            if (is.null(grp)) {
              hc <- hc %>% hchart(df, ltype, hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y)))
            } else {
              hc <- hc %>% hchart(df, ltype, hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y), group = !!rlang::sym(grp)))
            }

          } else if (identical(type,"scatter")) {
            req(x, y)
            if (is.null(grp)) {
              hc <- hc %>% hchart(df, "scatter", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y)))
            } else {
              hc <- hc %>% hchart(df, "scatter", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y), group = !!rlang::sym(grp)))
            }

          } else if (identical(type,"area")) {
            req(x, y)
            atype <- if (smooth) "areaspline" else "area"

            if (is.null(grp)) {
              hc <- hc %>% hchart(df, atype, hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y)))
            } else {
              hc <- hc %>% hchart(df, atype, hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y), group = !!rlang::sym(grp)))
            }

            st <- switch(stack,
                         "normal" = "normal",
                         "percent" = "percent",
                         NULL)
            if (!is.null(st)) {
              hc <- hc %>% hc_plotOptions(series = list(stacking = st))
            }

          } else if (identical(type, "pareto")) {
            # Pareto = bars (values) + line (cumulative %), dual axis
            req(x)
            # Use y-agg by x if provided, otherwise counts(x)
            if (!is.null(y)) {
              f <- if (is.null(agg)) "sum" else tolower(agg)
              fun <- switch(f, sum = sum, mean = mean, median = median, min = min, max = max, sum)
              dd <- aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) fun(z, na.rm = TRUE))
              names(dd) <- c(x, "val")
            } else {
              dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
              names(dd) <- c(x, "val")
            }

            dd <- dd[order(dd$val, decreasing = TRUE), , drop = FALSE]
            if (isTRUE(!is.na(top_n))) dd <- head(dd, top_n)
            dd$cum <- cumsum(dd$val)
            tot <- sum(dd$val, na.rm = TRUE)
            dd$cum_pct <- if (tot > 0) 100 * dd$cum / tot else 0

            # keep 'column' type and rely on inverted chart when horizontal
            hc <- hc %>%
              hc_xAxis(categories = dd[[x]]) %>%
              hc_yAxis_multiples(
                list(title = list(text = "Değer")),
                list(title = list(text = "Kümülatif %"), opposite = TRUE, max = 100,
                     labels = list(format = "{value}%"))
              ) %>%
              hc_add_series(name = "Değer", type = "column", data = dd$val, yAxis = 0) %>%
              hc_add_series(name = "Kümülatif %", type = if (smooth) "spline" else "line",
                            data = round(dd$cum_pct, 2), yAxis = 1,
                            tooltip = list(valueSuffix = "%")) %>%
              hc_tooltip(shared = TRUE)

          } else {
            stop("Unknown chart type")
          }

          hc
        })
        return(TRUE)
      }

      if (have_pl()) {
        output[[out_id]] <- plotly::renderPlotly({
          library(ggplot2); library(plotly)
          p <- NULL
          if (identical(type,"hist")) {
            req(x); p <- ggplot(df, aes(x = .data[[x]])) + geom_histogram(bins = ifelse(isTRUE(!is.na(bins)), bins, 30))

          } else if (identical(type, "pie") || identical(type, "donut")) {
            req(x)
            if (!is.null(y)) {
              f <- if (is.null(agg)) "sum" else tolower(agg)
              fun <- switch(f, sum = sum, mean = mean, median = median, min = min, max = max, sum)
              dd <- aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) fun(z, na.rm = TRUE))
              names(dd) <- c(x, "val")
            } else {
              dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
              names(dd) <- c(x, "val")
            }
            if (isTRUE(!is.na(top_n))) dd <- head(dd, top_n)
            return(plotly::plot_ly(dd, labels = ~ .data[[x]], values = ~ val, type = "pie",
                                   hole = if (identical(type,"donut") || donut) 0.6 else 0))

          } else if (identical(type,"bar")) {
            chart_type <- if (orientation %in% c("h","horizontal")) "bar" else "column"
            if (!is.null(y)) {
              f <- if (is.null(agg)) "sum" else tolower(agg)
              fun <- switch(f, sum = sum, mean = mean, median = median, min = min, max = max, sum)
              if (is.null(grp)) {
                dd <- aggregate(df[[y]], by=list(df[[x]]), FUN = function(z) fun(z, na.rm = TRUE))
                names(dd) <- c(x, "val")
                p <- ggplot(dd, aes(x = .data[[x]], y = val)) + geom_col()
              } else {
                dd <- stats::aggregate(df[[y]], by=list(df[[x]], df[[grp]]),
                                       FUN = function(z) fun(z, na.rm = TRUE))
                names(dd) <- c(x, grp, "val")
                pos <- if (stack == "percent") "fill" else "stack"
                p <- ggplot(dd, aes(x = .data[[x]], y = val, fill = .data[[grp]])) + geom_col(position = pos)
              }
            } else {
              dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
              names(dd) <- c(x, "n")
              if (isTRUE(!is.na(top_n))) dd <- head(dd, top_n)
              p <- ggplot(dd, aes(x = .data[[x]], y = n)) + geom_col()
            }
            if (orientation %in% c("h","horizontal")) {
              p <- p + coord_flip()
            }

          } else if (identical(type,"line")) {
            req(x, y)
            p <- ggplot(df, aes(x = .data[[x]], y = .data[[y]], color = .data[[grp]])) +
              { if (smooth) geom_smooth(se = FALSE, method = "loess", span = 0.6) else geom_line() }

          } else if (identical(type,"scatter")) {
            req(x, y)
            p <- ggplot(df, aes(x = .data[[x]], y = .data[[y]], color = .data[[grp]])) + geom_point(alpha = 0.8)

          } else if (identical(type,"area")) {
            req(x, y)
            geom_fun <- if (stack == "percent") geom_area else geom_area
            p <- ggplot(df, aes(x = .data[[x]], y = .data[[y]], fill = .data[[grp]])) +
              { if (smooth) geom_smooth(aes(group = .data[[grp]]), se = FALSE, method = "loess", span = 0.6) else geom_fun(position = "stack") }

          } else if (identical(type,"pareto")) {
            req(x)
            if (!is.null(y)) {
              f <- if (is.null(agg)) "sum" else tolower(agg)
              fun <- switch(f, sum = sum, mean = mean, median = median, min = min, max = max, sum)
              dd <- aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) fun(z, na.rm = TRUE))
              names(dd) <- c(x, "val")
            } else {
              dd <- as.data.frame(sort(table(df[[x]]), decreasing = TRUE))
              names(dd) <- c(x, "val")
            }
            dd <- dd[order(dd$val, decreasing = TRUE), , drop = FALSE]
            if (isTRUE(!is.na(top_n))) dd <- head(dd, top_n)
            dd$cum <- cumsum(dd$val)
            tot <- sum(dd$val, na.rm = TRUE)
            dd$cum_pct <- if (tot > 0) 100 * dd$cum / tot else 0

            return(
              plotly::plot_ly() %>%
                plotly::add_bars(x = dd[[x]], y = dd$val, name = "Değer", yaxis = "y1") %>%
                plotly::add_lines(x = dd[[x]], y = dd$cum_pct, name = "Kümülatif %", yaxis = "y2") %>%
                plotly::layout(
                  yaxis2 = list(overlaying = "y", side = "right", range = c(0,100), ticksuffix = "%")
                )
            )

          } else {
            stop("Unknown chart type")
          }
          plotly::ggplotly(p)
        })
        return(TRUE)
      }

      # no engine available:
      output[[out_id]] <- renderUI({
        div(style="color:#f87171", "Ne highcharter ne de plotly+ggplot2 kurulu. Lütfen birini yükleyin.")
      })
      FALSE
    }

    # public API ------------------------------------------------------
    push_spec <- function(spec_payload) {
      # spec_payload is typically result$chart
      spec_payload <- auto_guess_chart_spec(spec_payload)   # \U2190 ensure mapping exists for UI meta
      id <- make_id()
      rv$items[[id]] <- list(spec = spec_payload, file = spec_payload$file %||% NULL)
      rv$order <- c(id, rv$order)  # newest first
      rv$counter <- rv$counter + 1
      invisible(id)
    }

    # render list -----------------------------------------------------
    output$charts_container <- renderUI({
      ids <- rv$order
      if (!length(ids)) return(div(style="color:#9ca3af", "Henüz grafik yok."))
      tagList(lapply(ids, function(id) {
        sp <- rv$items[[id]]$spec
        file_label <- sp$file %||% ""
        tagList(
          div(class="chart-card",
              div(class="chart-title", paste0(toupper(sp$type), " \U2014 ", file_label)),
              div(class="chart-meta",
                  paste0("x=", sp$mapping$x %||% "-", "  y=", sp$mapping$y %||% "-", "  group=", sp$mapping$group %||% "-")),
              if (requireNamespace("highcharter", quietly = TRUE))
                highcharter::highchartOutput(ns(paste0("hc_", id)), height = "380px")
              else if (requireNamespace("plotly", quietly = TRUE))
                plotly::plotlyOutput(ns(paste0("hc_", id)), height = "380px")
              else
                uiOutput(ns(paste0("hc_", id)))
          ),
          # wire renderer
          isolate(render_one(paste0("hc_", id), sp, file_label))
        )
      }))
    })

    # return api
    list(
      push_spec = push_spec
    )
  })
}