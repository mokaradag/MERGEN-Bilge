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
    "budget_scope",
    "is_vendor",
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
    "www/js/welcome_tooltip_manager.js",
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
  expect_true(all(c("budget_scope", "is_vendor") %in% names(score_report)))

  # Geniş tüm-dosya tabanı korunur; vendor/minified dosyalar da görünür kalır.
  max_js_lines_all <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_JS_LINES", 1250L)
  max_css_lines_all <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_CSS_LINES", 1600L)
  max_very_large_files_all <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_1500_LINE_FILES", 1L)

  all_js_report <- subset(score_report, type == "js")
  all_css_report <- subset(score_report, type == "css")

  largest_js_all <- all_js_report[order(-all_js_report$lines), ][1, , drop = FALSE]
  largest_css_all <- all_css_report[order(-all_css_report$lines), ][1, , drop = FALSE]

  expect_true(
    largest_js_all$lines[1] <= max_js_lines_all,
    info = sprintf(
      "En büyük JS dosyası büyüdü: %s = %d > %d.",
      largest_js_all$file[1],
      largest_js_all$lines[1],
      max_js_lines_all
    )
  )

  expect_true(
    largest_css_all$lines[1] <= max_css_lines_all,
    info = sprintf(
      "En büyük CSS dosyası büyüdü: %s = %d > %d.",
      largest_css_all$file[1],
      largest_css_all$lines[1],
      max_css_lines_all
    )
  )

  expect_true(
    sum(score_report$lines >= 1500) <= max_very_large_files_all,
    info = sprintf(
      "1500+ satır frontend dosya sayısı arttı: %d > %d.",
      sum(score_report$lines >= 1500),
      max_very_large_files_all
    )
  )

  # App-owned dosyalar için daha sıkı ve pratik koruma.
  app_report <- subset(score_report, budget_scope == "app")
  app_js_report <- subset(app_report, type == "js")
  app_css_report <- subset(app_report, type == "css")

  max_app_js_lines <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_APP_JS_LINES", 850L)
  max_app_css_lines <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_APP_CSS_LINES", 1600L)
  max_app_js_functions <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_APP_JS_FUNCTIONS", 60L)
  max_app_js_event_handlers <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_APP_JS_EVENT_HANDLERS", 32L)
  max_app_js_shiny_handlers <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_APP_SHINY_HANDLERS", 20L)

  largest_app_js <- app_js_report[order(-app_js_report$lines), ][1, , drop = FALSE]
  largest_app_css <- app_css_report[order(-app_css_report$lines), ][1, , drop = FALSE]
  most_function_heavy_app_js <- app_js_report[order(-app_js_report$functions), ][1, , drop = FALSE]
  most_event_heavy_app_js <- app_js_report[order(-app_js_report$event_handlers), ][1, , drop = FALSE]
  most_shiny_heavy_app_js <- app_js_report[order(-app_js_report$shiny_handlers), ][1, , drop = FALSE]

  expect_true(
    largest_app_js$lines[1] <= max_app_js_lines,
    info = sprintf(
      "En büyük app-owned JS dosyası büyüdü: %s = %d > %d.",
      largest_app_js$file[1],
      largest_app_js$lines[1],
      max_app_js_lines
    )
  )

  expect_true(
    largest_app_css$lines[1] <= max_app_css_lines,
    info = sprintf(
      "En büyük app-owned CSS dosyası büyüdü: %s = %d > %d.",
      largest_app_css$file[1],
      largest_app_css$lines[1],
      max_app_css_lines
    )
  )

  expect_true(
    most_function_heavy_app_js$functions[1] <= max_app_js_functions,
    info = sprintf(
      "En yoğun app-owned JS fonksiyon sayısı arttı: %s = %d > %d.",
      most_function_heavy_app_js$file[1],
      most_function_heavy_app_js$functions[1],
      max_app_js_functions
    )
  )

  expect_true(
    most_event_heavy_app_js$event_handlers[1] <= max_app_js_event_handlers,
    info = sprintf(
      "En yoğun app-owned JS event/handler sayısı arttı: %s = %d > %d.",
      most_event_heavy_app_js$file[1],
      most_event_heavy_app_js$event_handlers[1],
      max_app_js_event_handlers
    )
  )

  expect_true(
    most_shiny_heavy_app_js$shiny_handlers[1] <= max_app_js_shiny_handlers,
    info = sprintf(
      "En yoğun app-owned JS Shiny handler sayısı arttı: %s = %d > %d.",
      most_shiny_heavy_app_js$file[1],
      most_shiny_heavy_app_js$shiny_handlers[1],
      max_app_js_shiny_handlers
    )
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

test_that("yeni app-owned frontend varlıkları manifest dışında sessizce kalmaz", {
  report <- .load_frontend_maint_report()
  unmanifested_app_assets <- attr(report, "unmanifested_app_assets", exact = TRUE)

  expect_true(is.data.frame(unmanifested_app_assets))

  expect_equal(
    nrow(unmanifested_app_assets),
    0L,
    info = paste(
      "Manifest dışında yeni app-owned frontend varlığı bulundu.",
      "Yeni runtime CSS/JS dosyaları R/config_ui_assets.R içine açık sırayla eklenmelidir.",
      paste(utils::capture.output(print(unmanifested_app_assets, row.names = FALSE)), collapse = "\n"),
      sep = "\n"
    )
  )
})

test_that("frontend bakım raporu top-risk özetini üretir", {
  report <- .load_frontend_maint_report()
  top_risk_summary <- attr(report, "top_risk_summary", exact = TRUE)

  expect_true(is.list(top_risk_summary))

  required_sections <- c(
    "largest_js",
    "largest_css",
    "highest_function_js",
    "highest_event_handler_js",
    "highest_shiny_handler_js",
    "duplicate_css_selectors",
    "legacy_selector_hits",
    "unmanifested_app_assets",
    "allowlisted_unmanifested_assets",
    "smoke_only_assets"
  )

  expect_equal(
    setdiff(required_sections, names(top_risk_summary)),
    character(0),
    info = "Frontend top-risk summary beklenen bölümlerin tamamını üretmelidir."
  )

  invisible(lapply(required_sections, function(section) {
    expect_true(
      is.data.frame(top_risk_summary[[section]]),
      info = sprintf("top_risk_summary$%s data.frame olmalıdır.", section)
    )
  }))

  expect_gt(nrow(top_risk_summary$largest_js), 0L)
  expect_gt(nrow(top_risk_summary$largest_css), 0L)
  expect_gt(nrow(top_risk_summary$highest_function_js), 0L)
  expect_gt(nrow(top_risk_summary$highest_event_handler_js), 0L)
  expect_gt(nrow(top_risk_summary$highest_shiny_handler_js), 0L)

  smoke_assets <- top_risk_summary$smoke_only_assets
  probe_row <- smoke_assets[smoke_assets$file == "www/smoke/ux-smoke-probes.js", , drop = FALSE]

  expect_equal(
    nrow(probe_row),
    1L,
    info = "ux-smoke-probes.js top-risk özetinde smoke-only asset olarak görünmelidir."
  )

  expect_false(
    probe_row$manifest_listed[[1]],
    info = "ux-smoke-probes.js production UI asset manifestine eklenmemelidir."
  )

  expect_true(
    all(c("file", "type", "exists", "manifest_listed", "budget_scope", "note") %in% names(smoke_assets)),
    info = "Smoke-only asset özeti dosya, tür, varlık ve manifest durumunu göstermelidir."
  )
})

test_that("açık tema disiplini: tombstone, tekrar bütçesi ve tema satır bütçesi korunur", {
  report <- .load_frontend_maint_report()

  # 1. Tombstone: eski 13-dosyalık override/patch zincirinin kaldırılan
  #    dosyaları geri getirilemez. Yeni açık tema kuralı, ilgili ALAN
  #    dosyasındaki mevcut seçici genişletilerek eklenir.
  tombstone_hits <- attr(report, "tombstone_hits", exact = TRUE)
  expect_equal(
    length(tombstone_hits),
    0L,
    info = paste(
      "Kaldırılan eski açık tema patch dosyası geri gelmiş:",
      paste(tombstone_hits, collapse = ", "),
      "\nYeni override katmanı eklemek yerine ilgili theme_light_<alan>.css",
      "dosyasındaki kuralı genişletin."
    )
  )

  # 2. Light-scoped tekrar bütçesi: html[data-theme=\"light\"] kapsamlı bir
  #    seçicinin dosyalar arasında tekrar tanımlanması override-zinciri
  #    deseninin imzasıdır. Tema alan dosyaları İÇİNDE sıfır tekrar ayrıca
  #    test-theme-light-modular-contract.R ile korunur; buradaki bütçe tema +
  #    bileşen dosyası çiftlerini de sınırlar (taban: 44, hepsi 2x çift).
  light_dups <- attr(report, "light_theme_duplicate_selectors", exact = TRUE)
  max_light_dups <- .as_int_env_frontend("MERGEN_TEST_MAX_LIGHT_THEME_DUPLICATE_SELECTORS", 44L)
  light_dup_count <- if (is.null(light_dups)) 0L else nrow(light_dups)

  expect_true(
    light_dup_count <= max_light_dups,
    info = sprintf(
      "Light-scoped tekrar seçici sayısı arttı: %d > %d. Aynı seçiciyi ikinci bir dosyada yeniden tanımlamayın.",
      light_dup_count,
      max_light_dups
    )
  )

  # 3. Tema bölgesi toplam satır bütçesi: eski zincir ~10.7k satırdı; alan
  #    konsolidasyonu sonrası taban ~5.9k'dır. Bütçe, patchwork'ün sessizce
  #    geri büyümesini engeller.
  theme_lines <- attr(report, "theme_zone_css_total_lines", exact = TRUE)
  max_theme_lines <- .as_int_env_frontend("MERGEN_TEST_MAX_THEME_ZONE_CSS_LINES", 6400L)

  expect_true(
    is.numeric(theme_lines) && theme_lines <= max_theme_lines,
    info = sprintf(
      "Tema bölgesi CSS toplam satırı bütçeyi aştı: %d > %d.",
      theme_lines,
      max_theme_lines
    )
  )

  # 4. Hayalet (orphan) seçici bütçesi: CSS'te stillenen ama runtime
  #    kaynaklarında hiç geçmeyen sınıflar DOM'da asla eşleşemez. Eski tema
  #    zincirinin ~%46'sı böyleydi; tüm ölü kurallar ve canlı grupların ölü
  #    üyeleri temizlendi. Taban: 0 (SIFIR). Yeni hayalet seçici eklemek
  #    bütçeyi aşar — seçiciyi gerçek DOM sınıfına bağlayın ya da dinamik
  #    üretim önekini rapora bilinçli ekleyin
  #    (frontend_orphan_constructed_prefixes).
  dead_rows <- attr(report, "dead_selector_rows", exact = TRUE)
  theme_dead_rows <- attr(report, "theme_dead_selector_rows", exact = TRUE)
  max_dead <- .as_int_env_frontend("MERGEN_TEST_MAX_FRONTEND_DEAD_SELECTORS", 0L)
  max_theme_dead <- .as_int_env_frontend("MERGEN_TEST_MAX_THEME_DEAD_SELECTORS", 0L)

  expect_true(is.data.frame(dead_rows))
  expect_true(
    nrow(dead_rows) <= max_dead,
    info = paste(
      sprintf("Hayalet seçici sayısı arttı: %d > %d.", nrow(dead_rows), max_dead),
      "Yeni eklenenler:",
      paste(utils::head(
        paste0(dead_rows$file, " :: ", dead_rows$selector), 8
      ), collapse = " | ")
    )
  )

  expect_true(
    nrow(theme_dead_rows) <= max_theme_dead,
    info = sprintf(
      "Tema alan dosyalarında hayalet seçici arttı: %d > %d.",
      nrow(theme_dead_rows),
      max_theme_dead
    )
  )
})

test_that("kritik frontend dosyaları kendi taban çizgilerinden büyümez", {
  report <- .load_frontend_maint_report()

  assert_frontend_file_budget <- function(path,
                                          max_lines,
                                          max_functions = Inf,
                                          max_event_handlers = Inf,
                                          max_shiny_handlers = Inf) {
    row <- report[report$file == path, , drop = FALSE]

    expect_equal(
      nrow(row),
      1L,
      info = sprintf("%s frontend bakım raporunda tek satır olarak görünmelidir.", path)
    )

    expect_true(
      row$lines[1] <= max_lines,
      info = sprintf("%s satır bütçesini aştı: %d > %d.", path, row$lines[1], max_lines)
    )

    expect_true(
      row$functions[1] <= max_functions,
      info = sprintf("%s fonksiyon bütçesini aştı: %d > %d.", path, row$functions[1], max_functions)
    )

    expect_true(
      row$event_handlers[1] <= max_event_handlers,
      info = sprintf("%s event/handler bütçesini aştı: %d > %d.", path, row$event_handlers[1], max_event_handlers)
    )

    expect_true(
      row$shiny_handlers[1] <= max_shiny_handlers,
      info = sprintf("%s Shiny handler bütçesini aştı: %d > %d.", path, row$shiny_handlers[1], max_shiny_handlers)
    )
  }

  assert_frontend_file_budget("www/js/input_handlers.js", 260L, 23L, 16L, 0L)
  assert_frontend_file_budget("www/js/app_core.js", 270L, 28L, 8L, 0L)
  assert_frontend_file_budget("www/js/welcome_tooltip_manager.js", 260L, 22L, 14L, 0L)
  assert_frontend_file_budget("www/js/claude_code.js", 620L, 36L, 16L, 12L)
  assert_frontend_file_budget("www/js/claude_code_streaming.js", 700L, 30L, 8L, 4L)
  assert_frontend_file_budget("www/js/music_manager.js", 650L, 45L, 16L, 8L)
  assert_frontend_file_budget("www/js/audio_lifecycle_guard.js", 220L, 19L, 4L, 0L)

  assert_frontend_file_budget("www/css/claude_code.css", 1150L)
  assert_frontend_file_budget("www/css/claude_code_streaming.css", 280L)
})