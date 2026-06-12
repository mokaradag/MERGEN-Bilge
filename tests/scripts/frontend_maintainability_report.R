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

# Açık tema disiplini metrikleri:
#   - theme_zone_files: www/css/theme_*.css dosyaları (token + alan katmanları)
#   - light_theme_duplicate_selectors: html[data-theme="light"] kapsamlı bir
#     seçicinin birden fazla dosyada tanımlanması. Tema alan dosyaları içinde
#     sıfır olmalıdır (tek-tanım sözleşmesi); tema + bileşen dosyası çiftleri
#     bilinçli desendir ve toplam ratchet bütçesiyle sınırlanır.
theme_zone_css_files <- function(report_data) {
  report_data$file[grepl("^www/css/theme_", report_data$file)]
}

theme_zone_css_total_lines <- function(report_data) {
  sum(report_data$lines[grepl("^www/css/theme_", report_data$file)])
}

light_theme_duplicate_selectors <- function(duplicate_data) {
  if (is.null(duplicate_data) || nrow(duplicate_data) == 0) {
    return(duplicate_data)
  }

  duplicate_data[
    grepl('data-theme="light"', duplicate_data$selector, fixed = TRUE),
    ,
    drop = FALSE
  ]
}

# ------------------------------------------------------------------------------
# Hayalet (orphan) seçici taraması:
# CSS'te stillenen bir sınıf, runtime kaynaklarının (R/, www/js, www/smoke,
# kök R dosyaları) hiçbirinde geçmiyorsa o seçici DOM'da asla eşleşemez.
# Eski 13 dosyalık açık tema zincirinin ~%46'sı böyle hayalet seçicilerden
# oluşuyordu; bu tarama aynı desenin geri dönmesini görünür kılar ve ratchet
# testi toplamı bütçeyle bağlar.
#
# Güvenlik modeli (yanlış pozitif engelleme):
#   1. Vendor/runtime kütüphane sınıfları (Bootstrap, DataTables, Shiny,
#      highcharts, CodeMirror, hljs, ...) ASLA hayalet sayılmaz.
#   2. Dinamik üretilen sınıf aileleri ASLA hayalet sayılmaz. Bu liste,
#      corpus genelinde "önek-ile-biten string literal" taramasının TEK TEK
#      incelenmiş sonucudur (ör. paste0("destek-tag-", renk),
#      "alo-ch alo-tok-" + tok.c, paste0("cc-dir-", tip)). Yeni bir dinamik
#      sınıf ailesi eklerseniz bu listeye önekini ekleyin.
#   3. :not(...) içindeki sınıflar seçiciyi ölü yapmaz.
# ------------------------------------------------------------------------------
frontend_orphan_vendor_patterns <- c(
  "^dataTables?", "^paginate_", "^sorting", "^odd$", "^even$",
  "^tooltip", "^bs-tooltip", "^popover", "^modal", "^dropdown", "^nav-", "^nav$",
  "^active$", "^in$", "^fade$", "^show$", "^collapse", "^open$", "^disabled$",
  "^btn(-|$)", "^form-", "^input-group", "^control-label", "^help-block",
  "^checkbox", "^radio", "^label(-|$)", "^badge$", "^alert", "^well$",
  "^table(-|$)", "^pagination", "^list-group", "^panel", "^progress",
  "^shiny-", "^recalculating$", "^irs-", "^selectize", "^datepicker",
  "^main-header$", "^main-sidebar$", "^main-footer$", "^content-wrapper$",
  "^sidebar", "^navbar", "^logo(-|$)", "^treeview", "^skin-", "^wrapper$",
  "^content$", "^tab-", "^box(-|$)", "^col-", "^row$", "^container",
  "^highcharts-", "^CodeMirror", "^cm-", "^swal", "^fa(-|s$|r$|b$)", "^sr-only$", "^sr-only-focusable$",
  "^dt-", "^dataTable$", "^header-fixed$", "^text-", "^bg-", "^pull-",
  "^close$", "^caret$", "^divider$", "^glyphicon", "^has-feedback",
  "^js-irs", "^slider", "^noUi-", "^leaflet", "^html-?widget", "^htmlwidget_container$",
  "^hidden", "^visible", "^affix", "^carousel", "^jumbotron", "^media$",
  "^action-button$", "^stripe$", "^hover$", "^compact$", "^cell-border$",
  "^hljs", "^language-", "^MathJax", "^katex",
  "^selected$", "^focus$", "^error$", "^success$", "^warning$", "^info$",
  "^ui-", "^clearfix$", "^lead$", "^small$", "^mark$",
  "^blockquote", "^dd$", "^dt$", "^figure", "^img-", "^thumbnail$"
)

# İncelenmiş dinamik üretim önekleri (health- / index-health- BİLİNÇLİ dışarıda:
# tempfile pattern'leridir, sınıf üretimi değildir).
frontend_orphan_constructed_prefixes <- c(
  "alo-tok-", "cc-dir-", "cc-message-",
  "destek-cat-", "destek-cat-icon-", "destek-chatbot-message-",
  "destek-dot-", "destek-tag-", "destek-tag-icon-",
  "font-", "health-status-", "hept-", "mbdoc-",
  "settings_yapilandirma_module-", "sso_module-", "shiny-tab-",
  "theme-", "toast-"
)

frontend_orphan_runtime_corpus <- function() {
  corpus_files <- c(
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", full.names = TRUE, recursive = TRUE),
    list.files(file.path(repo_root, "www", "js"), pattern = "\\.js$", full.names = TRUE, recursive = TRUE),
    list.files(file.path(repo_root, "www", "smoke"), pattern = "\\.(js|html)$", full.names = TRUE, recursive = TRUE),
    file.path(repo_root, c("ui.R", "server.R", "global.R", "welcome_screen.R"))
  )
  corpus_files <- corpus_files[file.exists(corpus_files)]
  paste(vapply(corpus_files, read_text, character(1)), collapse = "\n")
}

frontend_orphan_class_is_protected <- function(cls, corpus) {
  if (any(vapply(frontend_orphan_vendor_patterns,
                 function(p) grepl(p, cls, perl = TRUE), logical(1)))) {
    return(TRUE)
  }
  if (any(vapply(frontend_orphan_constructed_prefixes,
                 function(p) startsWith(cls, p) || identical(cls, sub("-$", "", p)),
                 logical(1)))) {
    return(TRUE)
  }
  grepl(cls, corpus, fixed = TRUE, useBytes = TRUE)
}

# Tüm CSS seçicilerinden (file, selector, class) satırları üretir ve hayalet
# sınıf içeren ÖLÜ seçicileri raporlar.
frontend_dead_selector_report <- function(css_selector_rows) {
  if (is.null(css_selector_rows) || nrow(css_selector_rows) == 0) {
    return(data.frame(file = character(0), selector = character(0),
                      orphan_class = character(0), stringsAsFactors = FALSE))
  }

  corpus <- frontend_orphan_runtime_corpus()

  all_classes <- unique(unlist(regmatches(
    css_selector_rows$selector,
    gregexpr("\\.[A-Za-z_][A-Za-z0-9_-]*", css_selector_rows$selector, perl = TRUE)
  ), use.names = FALSE))
  all_classes <- sub("^\\.", "", all_classes)

  orphan_classes <- all_classes[!vapply(
    all_classes,
    frontend_orphan_class_is_protected,
    logical(1),
    corpus = corpus
  )]

  if (length(orphan_classes) == 0) {
    return(data.frame(file = character(0), selector = character(0),
                      orphan_class = character(0), stringsAsFactors = FALSE))
  }

  rows <- list()
  for (i in seq_len(nrow(css_selector_rows))) {
    sel <- css_selector_rows$selector[i]
    sel_no_not <- gsub(":not\\([^)]*\\)", "", sel, perl = TRUE)
    cls_hits <- regmatches(sel_no_not, gregexpr("\\.[A-Za-z_][A-Za-z0-9_-]*", sel_no_not, perl = TRUE))[[1]]
    cls_hits <- sub("^\\.", "", cls_hits)
    dead_hit <- intersect(cls_hits, orphan_classes)
    if (length(dead_hit) > 0) {
      rows[[length(rows) + 1L]] <- data.frame(
        file = css_selector_rows$file[i],
        selector = sel,
        orphan_class = dead_hit[1],
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    return(data.frame(file = character(0), selector = character(0),
                      orphan_class = character(0), stringsAsFactors = FALSE))
  }

  do.call(rbind, rows)
}

# Kaldırılan eski açık tema patch-zinciri dosyaları. Bu adlarla yeni dosya
# eklemek yasaktır; ayrıntılı tombstone sözleşmesi
# tests/testthat/test-theme-light-modular-contract.R içindedir.
tombstoned_theme_files <- c(
  "www/css/theme_light.css",
  "www/css/theme_light_extras.css",
  "www/css/theme_light_refinements.css",
  "www/css/theme_light_polish.css",
  "www/css/theme_light_overhaul.css",
  "www/css/theme_light_overhaul_phase2.css",
  "www/css/theme_light_user_polish.css",
  "www/css/theme_light_user_polish_v2.css"
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

light_theme_duplicates <- light_theme_duplicate_selectors(duplicate_selectors)
theme_zone_lines <- theme_zone_css_total_lines(report)
tombstone_hits <- tombstoned_theme_files[
  file.exists(file.path(repo_root, tombstoned_theme_files))
]
dead_selector_rows <- frontend_dead_selector_report(css_selector_rows)
theme_dead_selector_rows <- dead_selector_rows[
  grepl("^www/css/theme_light_", dead_selector_rows$file),
  ,
  drop = FALSE
]

cat("\nAçık tema disiplini:\n")
cat(sprintf("  tema bölgesi CSS toplam satır: %d\n", theme_zone_lines))
cat(sprintf("  light-scoped tekrar seçici (dosyalar arası): %d\n",
            if (is.null(light_theme_duplicates)) 0L else nrow(light_theme_duplicates)))
cat(sprintf("  tombstone ihlali: %d\n", length(tombstone_hits)))
if (length(tombstone_hits) > 0) {
  cat("  GERİ GELEN ESKİ TEMA DOSYALARI:\n")
  for (hit in tombstone_hits) cat("    ", hit, "\n")
}

cat("\nHayalet (orphan) seçici taraması:\n")
cat(sprintf("  ölü seçici toplam: %d (tema alan dosyalarında: %d)\n",
            nrow(dead_selector_rows), nrow(theme_dead_selector_rows)))
if (nrow(dead_selector_rows) > 0) {
  by_file <- sort(table(dead_selector_rows$file), decreasing = TRUE)
  for (f in names(by_file)) cat(sprintf("    %s: %d\n", f, by_file[[f]]))
}

attr(report, "score_report") <- report
attr(report, "css_duplicate_selectors") <- duplicate_selectors
attr(report, "legacy_selector_hits") <- legacy_hits
attr(report, "unmanifested_app_assets") <- unmanifested_app_assets
attr(report, "vendor_frontend_files") <- vendor_frontend_files
attr(report, "allowlisted_unmanifested_frontend_files") <- allowlisted_unmanifested_frontend_files
attr(report, "top_risk_summary") <- top_risk_summary
attr(report, "light_theme_duplicate_selectors") <- light_theme_duplicates
attr(report, "theme_zone_css_total_lines") <- theme_zone_lines
attr(report, "tombstoned_theme_files") <- tombstoned_theme_files
attr(report, "tombstone_hits") <- tombstone_hits
attr(report, "dead_selector_rows") <- dead_selector_rows
attr(report, "theme_dead_selector_rows") <- theme_dead_selector_rows

invisible(report)