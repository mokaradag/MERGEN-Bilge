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
  sub(
    paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", repo_root), "/?"),
    "",
    normalizePath(path, winslash = "/", mustWork = TRUE),
    perl = TRUE
  )
}

report <- lapply(frontend_files, function(path) {
  text <- read_text(path)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  ext <- tolower(tools::file_ext(path))

  data.frame(
    file = relative_path(path),
    type = ext,
    manifest_listed = normalizePath(path, winslash = "/", mustWork = TRUE) %in% manifest_paths,
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

attr(report, "score_report") <- report
attr(report, "css_duplicate_selectors") <- duplicate_selectors
attr(report, "legacy_selector_hits") <- legacy_hits

invisible(report)