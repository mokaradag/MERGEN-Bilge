# ==============================================================================
# Dosya Yolu: R/helpers_chartlab.R
# Açıklama: Mesaj içindeki ```chartlab ...``` bloklarını ayrıştırır; bu blokları
#           Shiny içinde gösterilecek grafik yer tutucularına dönüştürür ve
#           uygun grafik motoru ile çıktı üretimini bağlar.
# ==============================================================================

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

      # Gömülü veri varsa doğrudan kullanılır; yoksa chart_store içindeki referans çözülür.
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

# Tek bir grafik çıktı kimliğini verilen grafik tanımına göre üretir.
wire_chart_output <- function(output, out_id, spec) {
  # ---------- Grafik tanımını standartlaştır ----------
  spec <- chartlab_auto_guess_spec(spec)
  type   <- tolower(spec$type %||% "bar")
  map    <- spec$mapping %||% list()
  params <- spec$params  %||% list()
  df     <- tryCatch(as.data.frame(spec$data, stringsAsFactors = FALSE), error = function(e) NULL)

  if (!is.null(df)) {
    num_cols <- names(df)[vapply(df, chartlab_is_numeric_or_date, logical(1))]
    if (length(num_cols)) for (cn in num_cols) df[[cn]] <- ifelse(is.finite(df[[cn]]), df[[cn]], NA_real_)
  }

  x     <- map$x; y <- map$y; grp <- map$group
  bins  <- params$bins  %||% NA_integer_
  agg   <- params$agg   %||% NULL
  topn  <- params$top_n %||% NA_integer_

  # Kutu grafik devre dışıysa güvenli görselleştirmeye düşülür.
  if (identical(type, "box")) {
    # x ekseni için sayısal kolon, yoksa kategorik kolon kullanılır.
    type <- "hist"
  }

  # ---------- Grafik motorları ----------
  if (requireNamespace("highcharter", quietly = TRUE)) {
    output[[out_id]] <- highcharter::renderHighchart({
      tryCatch({
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

        aggfun <- chartlab_aggregate_values

        # Mapping alanları mevcut sütunlarla karşılaştırılır; eksik sütun varsa boş widget yerine anlamlı hata üretilir.
        required_cols <- unique(stats::na.omit(c(x, y, grp)))
        missing_cols <- setdiff(required_cols, names(df))
        if (length(missing_cols)) {
          stop(sprintf("Grafik için gereken sütun(lar) bulunamadı: %s", paste(missing_cols, collapse = ", ")))
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
            dd <- aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) aggfun(z, agg))
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
			  if (is.null(grp)) {
				dd <- stats::aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) aggfun(z, agg %||% "mean"))
				names(dd) <- c(x, "val")
				dd <- dd[order(dd[[x]]), , drop = FALSE]
				hchart(dd, "line", hcaes(x = !!rlang::sym(x), y = val)) %>% hc_add_theme(custom_theme)
			  } else {
				dd <- stats::aggregate(df[[y]], by = list(df[[x]], df[[grp]]), FUN = function(z) aggfun(z, agg %||% "mean"))
				names(dd) <- c(x, grp, "val")
				dd <- dd[order(dd[[grp]], dd[[x]]), , drop = FALSE]
				hchart(dd, "line", hcaes(x = !!rlang::sym(x), y = val, group = !!rlang::sym(grp))) %>% hc_add_theme(custom_theme)
			  }
			} else if (identical(type,"scatter")) {
			  req(x, y)
			  if (is.null(grp)) hchart(df, "scatter", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y))) %>% hc_add_theme(custom_theme)
			  else              hchart(df, "scatter", hcaes(x = !!rlang::sym(x), y = !!rlang::sym(y), group = !!rlang::sym(grp))) %>% hc_add_theme(custom_theme)
			} else if (identical(type,"area")) {
			  req(x, y)
			  if (is.null(grp)) {
				dd <- stats::aggregate(df[[y]], by = list(df[[x]]), FUN = function(z) aggfun(z, agg %||% "mean"))
				names(dd) <- c(x, "val")
				dd <- dd[order(dd[[x]]), , drop = FALSE]
				hchart(dd, "area", hcaes(x = !!rlang::sym(x), y = val)) %>% hc_add_theme(custom_theme)
			  } else {
				dd <- stats::aggregate(df[[y]], by = list(df[[x]], df[[grp]]), FUN = function(z) aggfun(z, agg %||% "mean"))
				names(dd) <- c(x, grp, "val")
				dd <- dd[order(dd[[grp]], dd[[x]]), , drop = FALSE]
				hchart(dd, "area", hcaes(x = !!rlang::sym(x), y = val, group = !!rlang::sym(grp))) %>% hc_add_theme(custom_theme)
			  }
			} else {
          highchart() %>% hc_add_theme(custom_theme) %>% hc_title(text = "Bilinmeyen grafik türü")
        }
      }, error = function(e) {
        highcharter::highchart() %>%
          highcharter::hc_title(text = "Grafik oluşturulamadı") %>%
          highcharter::hc_subtitle(text = htmltools::htmlEscape(conditionMessage(e)))
      })
    })
    return(invisible(TRUE))
  }

  output[[out_id]] <- shiny::renderUI({
    div(style="color:#f87171", "Grafik motoru (highcharter) bulunamadı. Lütfen highcharter paketini yükleyin.")
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

    if (open[1] == -1) {
      parts <- append(parts, list(list(kind = "text", value = remaining)))
      break
    }

    pre <- substr(remaining, 1, open[1] - 1)
    parts <- append(parts, list(list(kind = "text", value = pre)))

    rest <- substr(
      remaining,
      open[1] + attr(open, "match.length"),
      nchar(remaining)
    )

    close <- regexpr("```", rest, perl = TRUE)

    if (close[1] == -1) {
      parts <- append(
        parts,
        list(list(kind = "text", value = paste0("```chartlab\n", rest)))
      )
      break
    }

    json_block <- substr(rest, 1, close[1] - 1)
    parts <- append(parts, list(list(kind = "chart", value = json_block)))

    remaining <- substr(
      rest,
      close[1] + attr(close, "match.length"),
      nchar(rest)
    )
  }

  html_chunks <- list()
  renderers <- list()
  chart_counter <- 0L

  for (p in parts) {
    if (identical(p$kind, "text")) {
      if (nzchar(trimws(p$value))) {
        html_chunks <- append(
          html_chunks,
          commonmark::markdown_html(
            p$value,
            hardbreaks = TRUE,
            extensions = c("strikethrough", "table")
          )
        )
      }

      next
    }

    if (identical(p$kind, "chart")) {
      chart_counter <- chart_counter + 1L
      out_id <- paste0("chart_", message_id, "_", chart_counter)

      spec <- NULL
      try(spec <- jsonlite::fromJSON(p$value, simplifyVector = TRUE), silent = TRUE)

      if (is.null(spec)) {
        html_chunks <- append(
          html_chunks,
          '<div class="chart-card"><div style="color:#f87171">Grafik tanımı çözümlenemedi.</div></div>'
        )
      } else {
        container_html <- if (requireNamespace("highcharter", quietly = TRUE)) {
          as.character(highcharter::highchartOutput(out_id, height = "380px"))
        } else {
          as.character(shiny::uiOutput(out_id, height = "380px"))
        }

        html_chunks <- append(
          html_chunks,
          sprintf('<div class="chart-card">%s</div>', container_html)
        )
        renderers <- append(
          renderers,
          list(list(output_id = out_id, spec = spec))
        )
      }
    }
  }

  list(
    found = chart_counter > 0L,
    html = paste(html_chunks, collapse = ""),
    renderers = renderers
  )
}
