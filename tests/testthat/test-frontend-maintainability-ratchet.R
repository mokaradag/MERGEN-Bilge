# ==============================================================================
# Dosya Yolu: tests/testthat/test-frontend-maintainability-ratchet.R
# Açıklama: Frontend JS/CSS bakım taban çizgisini korur.
# ==============================================================================

.find_repo_root_frontend_maint <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "www", "js")) &&
        dir.exists(file.path(candidate, "www", "css"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.as_int_env_frontend <- function(name, default) {
  raw <- Sys.getenv(name, as.character(default))
  value <- suppressWarnings(as.integer(raw))

  if (is.na(value)) {
    stop(sprintf("%s geçersiz: %s", name, raw), call. = FALSE)
  }

  value
}

.load_frontend_maint_report <- function() {
  repo_root <- .find_repo_root_frontend_maint()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  report_env <- new.env(parent = globalenv())
  source(
    "tests/scripts/frontend_maintainability_report.R",
    encoding = "UTF-8",
    local = report_env
  )$value
}

test_that("frontend maintainability report JS/CSS dosyalarını kapsar", {
  report <- .load_frontend_maint_report()

  expect_true(is.data.frame(report))
  expect_true(all(c(
    "file",
    "type",
    "manifest_listed",
    "lines",
    "bytes",
    "functions",
    "event_handlers",
    "shiny_handlers"
  ) %in% names(report)))

  expect_true(any(report$type == "js"))
  expect_true(any(report$type == "css"))

  required_files <- c(
    "www/js/input_handlers.js",
    "www/js/app_core.js",
    "www/js/claude_code_pixel_chars.js",
    "www/js/claude_code.js",
    "www/js/claude_code_streaming.js",
    "www/js/music_manager.js",
    "www/js/audio_lifecycle_guard.js",
    "www/css/claude_code.css",
    "www/css/claude_code_streaming.css"
  )

  missing_required_files <- setdiff(required_files, report$file)

  expect_equal(
    missing_required_files,
    character(0),
    info = paste(
      "Frontend bakım raporu kritik JS/CSS dosyalarını kapsamalıdır. Eksik dosyalar:",
      paste(missing_required_files, collapse = ", "),
      "\nRapor dosyaları örneği:",
      paste(utils::head(report$file, 20), collapse = ", ")
    )
  )
})

test_that("frontend JS/CSS büyüklük ve yoğunluk bütçeleri sessizce aşılmaz", {
  report <- .load_frontend_maint_report()
  score_report <- attr(report, "score_report", exact = TRUE)

  expect_true(is.data.frame(score_report))

  # İlk frontend taban çizgisi mevcut üretim durumunu kırmamalıdır.
  # Amaç hemen refactor zorlamak değil, bundan sonraki sessiz büyümeyi yakalamaktır.
  max_js_lines <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_JS_LINES", 1250L)
  max_css_lines <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_CSS_LINES", 1600L)
  max_js_functions <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_JS_FUNCTIONS", 200L)
  max_js_event_handlers <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_JS_EVENT_HANDLERS", 80L)
  max_very_large_files <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_1500_LINE_FILES", 1L)

  js_report <- subset(score_report, type == "js")
  css_report <- subset(score_report, type == "css")

  largest_js <- js_report[order(-js_report$lines), ][1, , drop = FALSE]
  largest_css <- css_report[order(-css_report$lines), ][1, , drop = FALSE]
  most_function_heavy_js <- js_report[order(-js_report$functions), ][1, , drop = FALSE]
  most_event_heavy_js <- js_report[order(-js_report$event_handlers), ][1, , drop = FALSE]

  actual_max_js_lines <- largest_js$lines[1]
  actual_max_css_lines <- largest_css$lines[1]
  actual_max_js_functions <- most_function_heavy_js$functions[1]
  actual_max_js_event_handlers <- most_event_heavy_js$event_handlers[1]
  actual_very_large_files <- sum(score_report$lines >= 1500)
  
  expect_true(
    actual_max_js_lines <= max_js_lines,
    info = sprintf(
      "En büyük JS dosyası büyüdü: %s = %d > %d.",
      largest_js$file[1],
      actual_max_js_lines,
      max_js_lines
    )
  )

  expect_true(
    actual_max_css_lines <= max_css_lines,
    info = sprintf(
      "En büyük CSS dosyası büyüdü: %s = %d > %d.",
      largest_css$file[1],
      actual_max_css_lines,
      max_css_lines
    )
  )

  expect_true(
    actual_max_js_functions <= max_js_functions,
    info = sprintf(
      "En yoğun JS fonksiyon sayısı arttı: %s = %d > %d.",
      most_function_heavy_js$file[1],
      actual_max_js_functions,
      max_js_functions
    )
  )

  expect_true(
    actual_max_js_event_handlers <= max_js_event_handlers,
    info = sprintf(
      "En yoğun JS event/handler sayısı arttı: %s = %d > %d.",
      most_event_heavy_js$file[1],
      actual_max_js_event_handlers,
      max_js_event_handlers
    )
  )

  expect_true(
    actual_very_large_files <= max_very_large_files,
    info = sprintf("1500+ satır frontend dosya sayısı arttı: %d > %d.", actual_very_large_files, max_very_large_files)
  )
})

test_that("frontend eski seçicileri geri getirmez ve CSS tekrar raporu üretir", {
  report <- .load_frontend_maint_report()

  legacy_hits <- attr(report, "legacy_selector_hits", exact = TRUE)
  duplicate_selectors <- attr(report, "css_duplicate_selectors", exact = TRUE)

  expect_true(is.data.frame(legacy_hits))
  expect_true(is.data.frame(duplicate_selectors))

  expect_equal(
    nrow(legacy_hits),
    0L,
    info = paste(
      "Yasak eski frontend seçici bulundu:",
      paste(utils::capture.output(print(legacy_hits, row.names = FALSE)), collapse = "\n")
    )
  )

  expect_true(
    all(c("selector", "count", "files") %in% names(duplicate_selectors)),
    info = "CSS tekrar seçici raporu selector/count/files kolonlarını üretmelidir."
  )
})