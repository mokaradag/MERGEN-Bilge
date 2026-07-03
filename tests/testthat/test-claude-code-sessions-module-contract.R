# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-sessions-module-contract.R
# Açıklama: Bilge Yolaç Oturumları sayfasının statik sözleşme testleri:
#           navigasyon sekmeleri, modül UI seçicileri, kaynak/varlık manifest
#           kayıtları, JS hidrasyon işleyicisi, tema-token CSS sözleşmesi ve
#           mevcut çalışma alanı davranışının (Çıktıyı Temizle kalıcı geçmişi
#           SİLMEZ) korunması. Uygulamayı başlatmaz; DB/ağ gerektirmez.
# ==============================================================================

# Windows VM'de UTF-8 sorunlarına dayanıklı bayt-güvenli dosya okuyucu.
.ccs_read_file_text <- function(path) {
  bytes <- readBin(path, what = "raw", n = file.size(path))
  text <- rawToChar(bytes)
  iconv(text, from = "UTF-8", to = "UTF-8", sub = "byte")
}

.ccs_repo_file <- function(...) {
  file.path(resolve_repo_root_for_tests(), ...)
}

# ------------------------------------------------------------------------------
test_that("navigasyon Bilge Yolaç grubunu ve Oturumlar sekmesini içerir", {
  ui_metin <- .ccs_read_file_text(.ccs_repo_file("ui.R"))

  expect_true(grepl('tabName = "claude_code"', ui_metin, fixed = TRUE))
  expect_true(grepl('tabName = "claude_code_sessions"', ui_metin, fixed = TRUE))
  expect_true(grepl('menuSubItem("Çalışma Alanı"', ui_metin, fixed = TRUE))
  expect_true(grepl('menuSubItem("Oturumlar"', ui_metin, fixed = TRUE))
  expect_true(grepl(
    'claudeCodeSessionsUI("claude_code_sessions_module")',
    ui_metin,
    fixed = TRUE
  ))
})

test_that("Oturumlar sayfası UI'si beklenen seçicileri üretir ve id çakışmaz", {
  testthat::skip_if_not_installed("shiny")

  ui_env <- new.env(parent = globalenv())
  suppressMessages(library(shiny))

  source(
    .ccs_repo_file("R", "module_claude_code_sessions_ui.R"),
    encoding = "UTF-8",
    local = ui_env
  )

  html <- as.character(ui_env$claudeCodeSessionsUI("test_ccs"))

  beklenen_idler <- c(
    "test_ccs-new_session",
    "test_ccs-goto_workbench",
    "test_ccs-refresh_sessions",
    "test_ccs-filter_query",
    "test_ccs-filter_status",
    "test_ccs-filter_model",
    "test_ccs-filter_sort",
    "test_ccs-summary_metrics",
    "test_ccs-sessions_list",
    "test_ccs-load_more_ui"
  )

  for (id in beklenen_idler) {
    hedef <- paste0('id="', id, '"')
    expect_identical(
      lengths(regmatches(html, gregexpr(hedef, html, fixed = TRUE))),
      1L,
      info = paste("UI id tam olarak bir kez üretilmelidir:", id)
    )
  }

  expect_true(grepl("claude-code-sessions-container", html, fixed = TRUE))
  expect_true(grepl("Bilge Yolaç Oturumları", html, fixed = TRUE))
  expect_true(grepl("ccs-filter-bar", html, fixed = TRUE))
  # Erişilebilirlik: ana eylemler aria-label taşır.
  expect_true(grepl('aria-label="Yeni oturum başlat"', html, fixed = TRUE))
})

test_that("oturum kartı üreticisi XSS kaçışlaması ve eylem girişleri içerir", {
  testthat::skip_if_not_installed("shiny")

  ui_env <- new.env(parent = globalenv())
  suppressMessages(library(shiny))
  source(
    .ccs_repo_file("R", "module_claude_code_sessions_ui.R"),
    encoding = "UTF-8",
    local = ui_env
  )

  satir <- list(
    ClaudeSessionRecordID = 12L,
    SessionTitle = "Başlık <script>alert(1)</script>",
    Workdir = "C:/proje",
    SourceWorkdir = "C:/proje",
    LastPrompt = "son komut <img src=x onerror=alert(1)>",
    ModelUsed = "m1",
    RuntimeModel = "m1-rt",
    ClaudeCliSessionID = "cli-1",
    Status = "completed",
    RunCount = 3L,
    FailedRunCount = 0L,
    RunsWithFiles = 1L,
    IsDeleted = 0L,
    CreatedAt = "2026-07-01 10:00:00",
    LastRunAt = "2026-07-01 11:00:00"
  )

  kart <- as.character(ui_env$ccs_session_card(satir, ns = shiny::NS("test_ccs")))

  # XSS sınırı: kullanıcı-kontrollü metinler kaçışlanır (ham etiket kalmaz;
  # kaçışlanmış inert metin görünür kalabilir).
  expect_false(grepl("<script>", kart, fixed = TRUE))
  expect_false(grepl("<img ", kart, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", kart, fixed = TRUE))
  expect_true(grepl("&lt;img", kart, fixed = TRUE))

  # Eylemler Shiny.setInputValue ile modül girişlerine bağlanır.
  expect_true(grepl("test_ccs-session_open", kart, fixed = TRUE))
  expect_true(grepl("test_ccs-session_resume", kart, fixed = TRUE))
  expect_true(grepl("test_ccs-session_archive", kart, fixed = TRUE))
  expect_true(grepl('data-record-id="12"', kart, fixed = TRUE))

  # Durum rozeti ve devam edilebilirlik çipi
  expect_true(grepl("ccs-badge-success", kart, fixed = TRUE))
  expect_true(grepl("Devam edilebilir", kart, fixed = TRUE))

  # Arşivlenmiş kart: devam/arşivle eylemleri gizlenir.
  satir$IsDeleted <- 1L
  arsiv_kart <- as.character(ui_env$ccs_session_card(satir, ns = shiny::NS("test_ccs")))
  expect_true(grepl("Arşivlendi", arsiv_kart, fixed = TRUE))
  expect_false(grepl("session_resume", arsiv_kart, fixed = TRUE))
})

test_that("durum rozeti ve göreli zaman yardımcıları doğru eşleşir", {
  testthat::skip_if_not_installed("shiny")

  ui_env <- new.env(parent = globalenv())
  suppressMessages(library(shiny))
  source(
    .ccs_repo_file("R", "module_claude_code_sessions_ui.R"),
    encoding = "UTF-8",
    local = ui_env
  )

  expect_identical(ui_env$ccs_status_badge_info("completed")$label, "Tamamlandı")
  expect_identical(ui_env$ccs_status_badge_info("failed")$class, "ccs-badge-danger")
  expect_identical(ui_env$ccs_status_badge_info("stopped")$label, "Durduruldu")
  expect_identical(
    ui_env$ccs_status_badge_info("completed", is_deleted = TRUE)$label,
    "Arşivlendi"
  )
  expect_identical(ui_env$ccs_status_badge_info("bilinmeyen")$class, "ccs-badge-muted")

  simdi <- as.POSIXct("2026-07-01 12:00:00", tz = "Europe/Istanbul")
  expect_identical(
    ui_env$ccs_time_label(as.POSIXct("2026-07-01 11:59:40", tz = "Europe/Istanbul"), now = simdi),
    "az önce"
  )
  expect_identical(
    ui_env$ccs_time_label(as.POSIXct("2026-07-01 11:30:00", tz = "Europe/Istanbul"), now = simdi),
    "30 dk önce"
  )
  expect_identical(
    ui_env$ccs_time_label(as.POSIXct("2026-07-01 08:00:00", tz = "Europe/Istanbul"), now = simdi),
    "4 sa önce"
  )
  expect_identical(ui_env$ccs_time_label(NA), "-")
})

test_that("kaynak manifesti yeni oturum katmanı dosyalarını doğru sırada içerir", {
  yeni_dosyalar <- c(
    "R/helpers_db_claude_code_session_queries.R",
    "R/helpers_db_claude_code_sessions.R",
    "R/helpers_claude_code_session_persistence.R",
    "R/helpers_claude_code_workbench_session_api.R",
    "R/module_claude_code_sessions_ui.R",
    "R/module_claude_code_sessions.R"
  )

  for (dosya in yeni_dosyalar) {
    expect_source_manifest_contains_for_tests(dosya)
    expect_true(
      file.exists(.ccs_repo_file(dosya)),
      info = paste("Manifest dosyası repoda yok:", dosya)
    )
  }

  # Kritik yükleme sırası: saf sorgular -> DB orkestrasyonu -> persist köprüsü
  # -> Oturumlar UI -> Oturumlar server -> ana çalışma alanı modülü.
  expect_source_manifest_order_for_tests(c(
    "R/helpers_db_claude_code_session_queries.R",
    "R/helpers_db_claude_code_sessions.R",
    "R/helpers_claude_code_session_persistence.R",
    "R/helpers_claude_code_workbench_session_api.R",
    "R/module_claude_code_sessions_ui.R",
    "R/module_claude_code_sessions.R",
    "R/module_claude_code.R"
  ))
})

test_that("varlık manifesti ve bölge haritası yeni CSS/JS dosyalarını içerir", {
  manifest_metin <- .ccs_read_file_text(.ccs_repo_file("R", "config_ui_assets.R"))
  zones_metin <- .ccs_read_file_text(.ccs_repo_file("R", "config_ui_asset_zones.R"))

  expect_true(grepl("css/claude_code_sessions.css", manifest_metin, fixed = TRUE))
  expect_true(grepl("js/claude_code_sessions.js", manifest_metin, fixed = TRUE))

  # Sıra kuralı: hidrasyon köprüsü claude_code.js'ten sonra yüklenir.
  expect_true(grepl(
    'c("js/claude_code.js", "js/claude_code_sessions.js")',
    manifest_metin,
    fixed = TRUE
  ))
  expect_true(grepl(
    'c("css/claude_code_plugins.css", "css/claude_code_sessions.css")',
    manifest_metin,
    fixed = TRUE
  ))

  expect_true(grepl("css/claude_code_sessions.css", zones_metin, fixed = TRUE))
  expect_true(grepl("js/claude_code_sessions.js", zones_metin, fixed = TRUE))

  expect_true(file.exists(.ccs_repo_file("www", "css", "claude_code_sessions.css")))
  expect_true(file.exists(.ccs_repo_file("www", "js", "claude_code_sessions.js")))
})

test_that("hidrasyon JS işleyicisi mevcut ve güvenli render yolunu kullanır", {
  sessions_js <- .ccs_read_file_text(.ccs_repo_file("www", "js", "claude_code_sessions.js"))
  claude_js <- .ccs_read_file_text(.ccs_repo_file("www", "js", "claude_code.js"))

  expect_true(grepl(
    "Shiny.addCustomMessageHandler('cc-hydrate-session'",
    sessions_js,
    fixed = TRUE
  ))

  # Mesaj görünümü tek kaynaktan: claude_code.js köprüsü kullanılır.
  expect_true(grepl("window.MergenClaudeCode.addMessage", sessions_js, fixed = TRUE))
  expect_true(grepl("window.MergenClaudeCode.addMessage = addMessage", claude_js, fixed = TRUE))

  # Köprü yoksa yedek yol inert kalır (innerHTML değil textContent).
  expect_true(grepl("textContent", sessions_js, fixed = TRUE))

  # Aynı mesaj işleyici manifest JS'lerinde ikinci kez kayıt edilmez.
  js_dizini <- .ccs_repo_file("www", "js")
  tum_js <- list.files(js_dizini, pattern = "\\.js$", full.names = TRUE)
  kayit_sayisi <- 0L
  for (dosya in tum_js) {
    metin <- .ccs_read_file_text(dosya)
    if (grepl("addCustomMessageHandler('cc-hydrate-session'", metin, fixed = TRUE)) {
      kayit_sayisi <- kayit_sayisi + 1L
    }
  }
  expect_identical(kayit_sayisi, 1L)
})

test_that("Oturumlar CSS'i tema token'larını kullanır; koyu-sabit yüzey içermez", {
  css_metin <- .ccs_read_file_text(.ccs_repo_file("www", "css", "claude_code_sessions.css"))

  beklenen_tokenlar <- c(
    "var(--color-bg)",
    "var(--color-surface)",
    "var(--color-surface-2)",
    "var(--color-text)",
    "var(--color-muted)",
    "var(--color-border)",
    "var(--color-primary)",
    "var(--color-success)",
    "var(--color-danger)",
    "var(--shadow-card)"
  )
  for (token in beklenen_tokenlar) {
    expect_true(
      grepl(token, css_metin, fixed = TRUE),
      info = paste("CSS token bekleniyor:", token)
    )
  }

  # Koyu temaya sabitlenmiş yüzey renkleri kullanılmamalıdır.
  koyu_sabitler <- c("#0f0f0f", "#141414", "#1a1a1a", "#1f1f1f", "#242424")
  for (renk in koyu_sabitler) {
    expect_false(
      grepl(renk, css_metin, fixed = TRUE, ignore.case = FALSE),
      info = paste("Koyu-sabit yüzey rengi kullanılmamalı:", renk)
    )
  }

  # Hareket azaltma tercihi desteklenir; yatay taşma engellenir.
  expect_true(grepl("prefers-reduced-motion", css_metin, fixed = TRUE))
  expect_true(grepl("overflow-x: hidden", css_metin, fixed = TRUE))
})

test_that("çalışma alanı runtime'ı kalıcı oturum köprüsünü doğru kullanır", {
  modul <- .ccs_read_file_text(.ccs_repo_file("R", "module_claude_code.R"))
  api <- .ccs_read_file_text(.ccs_repo_file("R", "helpers_claude_code_workbench_session_api.R"))
  poll <- .ccs_read_file_text(.ccs_repo_file("R", "module_claude_code_stream_poll.R"))
  setup <- .ccs_read_file_text(.ccs_repo_file("R", "helpers_claude_code_server_setup.R"))
  wiring <- .ccs_read_file_text(.ccs_repo_file("R", "server_module_wiring.R"))
  kopru <- .ccs_read_file_text(.ccs_repo_file("R", "helpers_claude_code_session_persistence.R"))

  # rv kalıcı oturum alanları ve çalıştırma öncesi oturum başlatma
  expect_true(grepl("claude_session_record_id = NULL", modul, fixed = TRUE))
  expect_true(grepl("claude_session_persistence_available = NULL", modul, fixed = TRUE))
  expect_true(grepl("cc_persist_session_begin(", modul, fixed = TRUE))
  expect_true(grepl("cc_create_workbench_session_api(", modul, fixed = TRUE))
  expect_true(grepl("load_persisted_session", modul, fixed = TRUE))
  expect_true(grepl("start_new_session", modul, fixed = TRUE))
  expect_true(grepl("open_sessions_page", modul, fixed = TRUE))

  # Hidrasyon mesajı ve resume güvenlik akışı workbench oturum API'sinde
  expect_true(grepl("cc-hydrate-session", api, fixed = TRUE))
  expect_true(grepl("cc_session_hydration_plan(", api, fixed = TRUE))
  expect_true(grepl("suppress_workdir_reset_once", api, fixed = TRUE))

  # Akış tamamlanınca başarılı VE başarısız çalıştırmalar kalıcılaştırılır.
  expect_true(grepl('status = "completed"', poll, fixed = TRUE))
  expect_true(grepl('status = "failed"', poll, fixed = TRUE))
  expect_true(grepl('status = "stopped"', poll, fixed = TRUE))
  expect_identical(
    lengths(regmatches(poll, gregexpr("cc_persist_run_result(", poll, fixed = TRUE))),
    4L
  )

  # Çıktıyı Temizle / model / workdir değişimi yalnızca bağı koparır;
  # kalıcı geçmişi SİLMEZ.
  expect_true(grepl("cc_persist_detach_session", setup, fixed = TRUE))
  expect_false(grepl("cc_db_soft_delete_session", setup, fixed = TRUE))
  expect_true(grepl("suppress_workdir_reset_once", setup, fixed = TRUE))

  # Detach yardımcısı silme çağrısı içermez.
  expect_false(grepl("soft_delete", kopru, fixed = TRUE))
  expect_false(grepl("DELETE", kopru, fixed = TRUE))

  # Wiring: Oturumlar modülü bağlanır ve çalışma alanı dönüş değeri aktarılır.
  expect_true(grepl(
    "claude_code_sessions_server_fn = claudeCodeSessionsServer",
    wiring,
    fixed = TRUE
  ))
  expect_true(grepl('"claude_code_sessions_module"', wiring, fixed = TRUE))
  expect_true(grepl("workbench = claude_code_workbench", wiring, fixed = TRUE))
})

test_that("Oturumlar sunucu modülü stub DB ile liste/metrik render eder", {
  testthat::skip_if_not_installed("shiny")

  suppressMessages(library(shiny))
  repo_root <- resolve_repo_root_for_tests()

  test_env <- new.env(parent = globalenv())
  source(file.path(repo_root, "R", "module_claude_code_sessions_ui.R"),
         encoding = "UTF-8", local = test_env)
  source(file.path(repo_root, "R", "module_claude_code_sessions.R"),
         encoding = "UTF-8", local = test_env)

  # Modülün aradığı runtime bağımlılıkları test ortamında stub'lanır.
  test_env$SSO_ENABLED <- FALSE
  test_env$`%||%` <- function(a, b) if (is.null(a)) b else a
  test_env$cc_create_dir_refresh_guard <- function() {
    sayac <- 0L
    list(
      next_id = function() { sayac <<- sayac + 1L; sayac },
      is_latest = function(id) identical(id, sayac)
    )
  }
  test_env$cc_require_ready_user_id <- function(...) list(ok = TRUE, user_id = 7L)
  test_env$cc_db_claude_tables_available <- function(...) TRUE
  test_env$cc_db_load_session <- function(...) NULL
  test_env$cc_db_soft_delete_session <- function(...) TRUE
  test_env$cc_session_hydration_plan <- function(...) list(resume = list(ok = FALSE))
  test_env$cc_db_list_sessions <- function(...) data.frame(
    ClaudeSessionRecordID = 1L, UserID = 7L, ClaudeCliSessionID = "cli-1",
    SessionTitle = "Türkçe oturum başlığı", Workdir = "C:/proje",
    SourceWorkdir = "C:/proje", RuntimeWorkdir = "", ModelUsed = "m1",
    RuntimeModel = "m1", CharacterID = "emre", Status = "completed",
    CreatedAt = "2026-07-01 10:00:00", LastRunAt = "2026-07-01 11:00:00",
    IsDeleted = 0L, RunCount = 2L, FailedRunCount = 0L, RunsWithFiles = 1L,
    LastPrompt = "son komut", stringsAsFactors = FALSE
  )

  # Modül fonksiyonunun ortamını stub'lu test ortamına bağla.
  server_fn <- test_env$claudeCodeSessionsServer
  environment(server_fn) <- test_env

  shiny::testServer(
    server_fn,
    args = list(current_user_id = function() 7L),
    {
      session$setInputs(
        filter_query = "",
        filter_status = "",
        filter_model = "",
        filter_sort = "last_activity"
      )

      session$returned$refresh("test")
      session$flushReact()

      # Tüm doğrulamalar testServer bloğu İÇİNDE yapılır (oturum yıkımı
      # sonrası reaktif erişim hatasına karşı Windows/CI güvenli desen).
      testthat::expect_identical(nrow(rv$sessions), 1L)

      liste <- output$sessions_list
      liste_html <- if (is.list(liste) && !is.null(liste$html)) {
        as.character(liste$html)
      } else {
        as.character(liste)
      }
      testthat::expect_true(grepl("ccs-session-card", liste_html, fixed = TRUE))
      testthat::expect_true(grepl("Türkçe oturum başlığı", liste_html, fixed = TRUE))

      metrik <- output$summary_metrics
      metrik_html <- if (is.list(metrik) && !is.null(metrik$html)) {
        as.character(metrik$html)
      } else {
        as.character(metrik)
      }
      testthat::expect_true(grepl("ccs-metric-card", metrik_html, fixed = TRUE))
    }
  )
})

test_that("DB oturum katmanı parametreli SQL ve merkez encoding yolunu kullanır", {
  db_metin <- .ccs_read_file_text(.ccs_repo_file("R", "helpers_db_claude_code_sessions.R"))

  expect_true(grepl("normalize_db_params", db_metin, fixed = TRUE))
  expect_true(grepl("normalize_db_visible_value", db_metin, fixed = TRUE))
  expect_true(grepl("normalize_db_technical_value", db_metin, fixed = TRUE))

  # Yumuşak silme: fiziksel DELETE ifadesi bulunmaz.
  expect_false(grepl("DELETE FROM", db_metin, fixed = TRUE))
  expect_true(grepl("SET IsDeleted = 1", db_metin, fixed = TRUE))

  # Kurulum betiği repoda mevcut ve yıkıcı ifade içermiyor.
  sql_yolu <- .ccs_repo_file("docs", "sql", "2026-07-bilge-yolac-sessions.sql")
  expect_true(file.exists(sql_yolu))
  sql_metin <- toupper(.ccs_read_file_text(sql_yolu))
  expect_false(grepl("DROP TABLE", sql_metin, fixed = TRUE))
  expect_false(grepl("TRUNCATE", sql_metin, fixed = TRUE))
  expect_false(grepl("DELETE FROM", sql_metin, fixed = TRUE))
  expect_true(grepl("MB_CLAUDECODE_SESSIONS", sql_metin, fixed = TRUE))
  expect_true(grepl("MB_CLAUDECODE_RUNS", sql_metin, fixed = TRUE))
})
