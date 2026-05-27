# ==============================================================================
# Dosya Yolu: tests/scripts/frontend_maintainability_report.R
# Açıklama: Frontend JS/CSS dosyaları için bakım raporu.
#           Bu script test değildir; satır/fonksiyon/event yoğunluğu,
#           eski seçici kalıntıları ve CSS seçici tekrarlarını görünür kılar.
# ==============================================================================

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)

if (!file.exists(file.path(repo_root, "app.R")) ||
    !dir.exists(file.path(repo_root, "www"))) {
  stop("Bu script repo kökünden çalıştırılmalıdır.", call. = FALSE)
}

read_text <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

count_pattern <- function(pattern, text) {
  matches <- gregexpr(pattern, text, perl = TRUE)[[1]]
  if (identical(matches[1], -1L)) {
    return(0L)
  }
  length(matches)
}

count_js_functions <- function(text) {
  patterns <- c(
    "\\bfunction\\s*[A-Za-z0-9_$]*\\s*\\(",
    "\\([^)]*\\)\\s*=>",
    "\\b[A-Za-z_$][A-Za-z0-9_$]*\\s*=>"
  )

  sum(vapply(patterns, count_pattern, integer(1), text = text))
}

count_js_event_handlers <- function(text) {
  patterns <- c(
    "\\.addEventListener\\s*\\(",
    "\\$\\s*\\([^\\n;]*\\)\\.on\\s*\\(",
    "\\.on\\s*\\(\\s*['\"]",
    "Shiny\\.addCustomMessageHandler\\s*\\("
  )

  sum(vapply(patterns, count_pattern, integer(1), text = text))
}

count_shiny_handlers <- function(text) {
  count_pattern("Shiny\\.addCustomMessageHandler\\s*\\(", text)
}

extract_css_selectors <- function(text) {
  css <- gsub("/\\*[\\s\\S]*?\\*/", "", text, perl = TRUE)
  matches <- gregexpr("([^{}]+)\\{", css, perl = TRUE)[[1]]

  if (identical(matches[1], -1L)) {
    return(character(0))
  }

  raw <- regmatches(css, list(matches))[[1]]
  raw <- sub("\\{$", "", raw)
  raw <- unlist(strsplit(raw, ",", fixed = TRUE), use.names = FALSE)
  raw <- trimws(gsub("\\s+", " ", raw, perl = TRUE))
  raw <- raw[nzchar(raw)]
  raw <- raw[!grepl("^(@|from$|to$|[0-9.]+%)", raw, perl = TRUE)]

  raw
}

source_manifest <- function() {
  asset_env <- new.env(parent = globalenv())
  source(
    file.path(repo_root, "R/config_ui_assets.R"),
    encoding = "UTF-8",
    local = asset_env
  )
  asset_env
}

asset_env <- source_manifest()

manifest_paths <- file.path(
  "www",
  c(asset_env$ui_asset_all_js(), asset_env$ui_asset_all_css())
)
manifest_paths <- normalizePath(
  file.path(repo_root, manifest_paths),
  winslash = "/",
  mustWork = FALSE
)

frontend_files <- c(
  list.files(file.path(repo_root, "www", "js"), pattern = "\\.js$", full.names = TRUE),
  list.files(file.path(repo_root, "www", "css"), pattern = "\\.css$", full.names = TRUE)
)

frontend_files <- unique(normalizePath(frontend_files, winslash = "/", mustWork = TRUE))

relative_path <- function(path) {
  root_norm <- enc2utf8(normalizePath(repo_root, winslash = "/", mustWork = TRUE))
  path_norm <- enc2utf8(normalizePath(path, winslash = "/", mustWork = TRUE))

  root_prefix <- paste0(root_norm, "/")

  if (startsWith(path_norm, root_prefix)) {
    return(substring(path_norm, nchar(root_prefix) + 1L))
  }

  # Windows/network path safety: if casing differs, still strip the same prefix.
  root_lower <- tolower(root_prefix)
  path_lower <- tolower(path_norm)

  if (startsWith(path_lower, root_lower)) {
    return(substring(path_norm, nchar(root_prefix) + 1L))
  }

  path_norm
}

vendor_frontend_files <- c(
  "www/js/highlight.min.js",
  "www/js/fontfaceobserver.js",
  "www/css/all.min.css"
)

allowlisted_unmanifested_frontend_files <- c(
  # Loaded directly by R/helpers_admin_analytics.R via tags$head().
  # Keep visible, but do not force global manifest loading in this patch.
  "www/css/admin_analytics.css",
  # Açılış yükleme ekranı varlıkları: R/module_app_loading.R tarafından ilk
  # boyamada satır içine gömülür; bilinçli olarak UI manifestine eklenmez.
  "www/css/app_loading.css",
  "www/js/app_loading.js",
  "www/js/app_loading_codestream.js",
  "www/js/app_loading_snippets.js",
  "www/js/app_loading_content.js",
  "www/js/app_loading_media.js"
)

is_vendor_frontend_asset <- function(rel_path) {
  rel_path %in% vendor_frontend_files ||
    grepl("(^|/)www/(lib|codemirror)/", rel_path, perl = TRUE) ||
    grepl("\\.min\\.(js|css)$", rel_path, perl = TRUE)
}

frontend_budget_scope <- function(rel_path, manifest_listed) {
  if (is_vendor_frontend_asset(rel_path)) {
    return("vendor")
  }

  if (rel_path %in% allowlisted_unmanifested_frontend_files) {
    return("allowlisted_unmanifested")
  }

  "app"
}

report <- lapply(frontend_files, function(path) {
  text <- read_text(path)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  ext <- tolower(tools::file_ext(path))
  rel_path <- relative_path(path)
  manifest_listed <- normalizePath(path, winslash = "/", mustWork = TRUE) %in% manifest_paths
  scope <- frontend_budget_scope(rel_path, manifest_listed)

  data.frame(
    file = rel_path,
    type = ext,
    manifest_listed = manifest_listed,
    budget_scope = scope,
    is_vendor = identical(scope, "vendor"),
    lines = length(lines),
    bytes = suppressWarnings(file.info(path)$size[1]),
    functions = if (identical(ext, "js")) count_js_functions(text) else 0L,
    event_handlers = if (identical(ext, "js")) count_js_event_handlers(text) else 0L,
    shiny_handlers = if (identical(ext, "js")) count_shiny_handlers(text) else 0L,
    stringsAsFactors = FALSE
  )
})

report <- do.call(rbind, report)
report <- report[order(report$type, -report$lines, report$file), ]

css_selector_rows <- lapply(frontend_files[grepl("\\.css$", frontend_files)], function(path) {
  selectors <- extract_css_selectors(read_text(path))
  if (length(selectors) == 0) {
    return(NULL)
  }

  data.frame(
    selector = selectors,
    file = relative_path(path),
    stringsAsFactors = FALSE
  )
})

css_selector_rows <- do.call(rbind, css_selector_rows)

if (is.null(css_selector_rows) || nrow(css_selector_rows) == 0) {
  duplicate_selectors <- data.frame(
    selector = character(0),
    count = integer(0),
    files = character(0),
    stringsAsFactors = FALSE
  )
} else {
  selector_counts <- sort(table(css_selector_rows$selector), decreasing = TRUE)
  duplicate_names <- names(selector_counts[selector_counts > 1])

  duplicate_selectors <- do.call(rbind, lapply(duplicate_names, function(selector) {
    rows <- css_selector_rows[css_selector_rows$selector == selector, , drop = FALSE]
    data.frame(
      selector = selector,
      count = nrow(rows),
      files = paste(sort(unique(rows$file)), collapse = ", "),
      stringsAsFactors = FALSE
    )
  }))

  if (is.null(duplicate_selectors)) {
    duplicate_selectors <- data.frame(
      selector = character(0),
      count = integer(0),
      files = character(0),
      stringsAsFactors = FALSE
    )
  }
}

forbidden_legacy_selectors <- c(
  "message_input",
  "chat_content_wrapper",
  "#_content_container"
)

legacy_hits <- do.call(rbind, lapply(frontend_files, function(path) {
  text <- read_text(path)
  hits <- forbidden_legacy_selectors[
    vapply(
      forbidden_legacy_selectors,
      function(selector) grepl(selector, text, fixed = TRUE, useBytes = TRUE),
      logical(1)
    )
  ]

  if (length(hits) == 0) {
    return(NULL)
  }

  data.frame(
    file = relative_path(path),
    selector = hits,
    stringsAsFactors = FALSE
  )
}))

if (is.null(legacy_hits)) {
  legacy_hits <- data.frame(
    file = character(0),
    selector = character(0),
    stringsAsFactors = FALSE
  )
}

unmanifested_app_assets <- subset(
  report,
  budget_scope == "app" & !manifest_listed,
  select = c("file", "type", "lines", "bytes", "functions", "event_handlers", "shiny_handlers")
)

frontend_metric_columns <- c(
  "file",
  "type",
  "manifest_listed",
  "budget_scope",
  "lines",
  "bytes",
  "functions",
  "event_handlers",
  "shiny_handlers"
)

frontend_select_columns <- function(data, columns = frontend_metric_columns) {
  if (is.null(data) || nrow(data) == 0) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  existing_columns <- intersect(columns, names(data))
  data[, existing_columns, drop = FALSE]
}

frontend_top_rows <- function(data,
                              order_columns,
                              columns = frontend_metric_columns,
                              n = 12L) {
  if (is.null(data) || nrow(data) == 0) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  order_columns <- intersect(order_columns, names(data))

  if (length(order_columns) == 0) {
    return(frontend_select_columns(utils::head(data, n), columns))
  }

  order_args <- lapply(order_columns, function(column) {
    -data[[column]]
  })

  if ("file" %in% names(data)) {
    order_args <- c(order_args, list(data$file))
  }

  row_order <- do.call(order, order_args)
  frontend_select_columns(utils::head(data[row_order, , drop = FALSE], n), columns)
}

frontend_top_duplicate_selectors <- function(data, n = 25L) {
  if (is.null(data) || nrow(data) == 0) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  ordered <- data[order(-data$count, data$selector), , drop = FALSE]
  utils::head(ordered, n)
}

frontend_smoke_only_assets <- function() {
  smoke_paths <- c(
    "www/smoke/ux-smoke.html",
    "www/smoke/ux-smoke-probes.js"
  )

  smoke_abs <- normalizePath(
    file.path(repo_root, smoke_paths),
    winslash = "/",
    mustWork = FALSE
  )

  data.frame(
    file = smoke_paths,
    type = tools::file_ext(smoke_paths),
    exists = file.exists(file.path(repo_root, smoke_paths)),
    manifest_listed = smoke_abs %in% manifest_paths,
    budget_scope = "smoke_only",
    note = c(
      "Browser UX smoke harness; production UI manifestine eklenmez.",
      "Smoke-only probe helper; production UI manifestine eklenmez."
    ),
    stringsAsFactors = FALSE
  )
}

build_frontend_top_risk_summary <- function(report,
                                            duplicate_selectors,
                                            legacy_hits,
                                            unmanifested_app_assets,
                                            allowlisted_unmanifested_frontend_files) {
  app_report <- subset(report, budget_scope == "app")
  app_js_report <- subset(app_report, type == "js")
  app_css_report <- subset(app_report, type == "css")

  allowlisted_rows <- report[
    report$file %in% allowlisted_unmanifested_frontend_files,
    ,
    drop = FALSE
  ]

  list(
    largest_js = frontend_top_rows(app_js_report, "lines"),
    largest_css = frontend_top_rows(app_css_report, "lines"),
    highest_function_js = frontend_top_rows(app_js_report, c("functions", "lines")),
    highest_event_handler_js = frontend_top_rows(app_js_report, c("event_handlers", "lines")),
    highest_shiny_handler_js = frontend_top_rows(app_js_report, c("shiny_handlers", "lines")),
    duplicate_css_selectors = frontend_top_duplicate_selectors(duplicate_selectors),
    legacy_selector_hits = legacy_hits,
    unmanifested_app_assets = unmanifested_app_assets,
    allowlisted_unmanifested_assets = frontend_select_columns(allowlisted_rows),
    smoke_only_assets = frontend_smoke_only_assets()
  )
}

print_frontend_top_risk_table <- function(title, value, n = 12L) {
  cat(sprintf("\n%s:\n", title))

  if (is.null(value) || nrow(value) == 0) {
    cat("(yok)\n")
    return(invisible(NULL))
  }

  print(utils::head(value, n), row.names = FALSE)
  invisible(NULL)
}

top_risk_summary <- build_frontend_top_risk_summary(
  report = report,
  duplicate_selectors = duplicate_selectors,
  legacy_hits = legacy_hits,
  unmanifested_app_assets = unmanifested_app_assets,
  allowlisted_unmanifested_frontend_files = allowlisted_unmanifested_frontend_files
)

cat("\nEn büyük JS dosyaları:\n")
print(utils::head(subset(report, type == "js")[order(-subset(report, type == "js")$lines), ], 12), row.names = FALSE)

cat("\nEn büyük CSS dosyaları:\n")
print(utils::head(subset(report, type == "css")[order(-subset(report, type == "css")$lines), ], 12), row.names = FALSE)

cat("\nFonksiyon/event yoğun JS dosyaları:\n")
js_report <- subset(report, type == "js")
print(utils::head(js_report[order(-js_report$functions, -js_report$event_handlers), ], 12), row.names = FALSE)

cat("\nCSS tekrar eden seçiciler, ilk 25:\n")
print(utils::head(duplicate_selectors, 25), row.names = FALSE)

cat("\nYasak eski seçici eşleşmeleri:\n")
print(legacy_hits, row.names = FALSE)

cat("\nFrontend top-risk summary:\n")
print_frontend_top_risk_table("Top app-owned JS by lines", top_risk_summary$largest_js)
print_frontend_top_risk_table("Top app-owned CSS by lines", top_risk_summary$largest_css)
print_frontend_top_risk_table("Top app-owned JS by function count", top_risk_summary$highest_function_js)
print_frontend_top_risk_table("Top app-owned JS by event/handler count", top_risk_summary$highest_event_handler_js)
print_frontend_top_risk_table("Top app-owned JS by Shiny handler count", top_risk_summary$highest_shiny_handler_js)
print_frontend_top_risk_table("Duplicate CSS selectors", top_risk_summary$duplicate_css_selectors, n = 25L)
print_frontend_top_risk_table("Unmanifested app-owned runtime assets", top_risk_summary$unmanifested_app_assets)
print_frontend_top_risk_table("Allowlisted unmanifested assets", top_risk_summary$allowlisted_unmanifested_assets)
print_frontend_top_risk_table("Smoke-only assets", top_risk_summary$smoke_only_assets)

attr(report, "score_report") <- report
attr(report, "css_duplicate_selectors") <- duplicate_selectors
attr(report, "legacy_selector_hits") <- legacy_hits
attr(report, "unmanifested_app_assets") <- unmanifested_app_assets
attr(report, "vendor_frontend_files") <- vendor_frontend_files
attr(report, "allowlisted_unmanifested_frontend_files") <- allowlisted_unmanifested_frontend_files
attr(report, "top_risk_summary") <- top_risk_summary

invisible(report)