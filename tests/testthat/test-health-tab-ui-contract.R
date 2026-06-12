# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-tab-ui-contract.R
# Açıklama: Sistem Durumu panelinin sekme UI üreticilerinin YAPI/DAVRANIŞ
#           sözleşme testleri. Aşağıdaki beş modül daha önce hiçbir test
#           tarafından çağrılmıyordu:
#             - R/module_health_overview.R     (health_overview_ui)
#             - R/module_health_storage.R      (health_storage_ui / path_item)
#             - R/module_health_security.R     (health_security_ui)
#             - R/module_health_connectivity.R (health_connectivity_ui)
#             - R/module_health_diagnostics.R  (health_diagnostics_ui)
#
#           Bunlar saf UI üreticileridir; ortak biçimlendiriciler
#           (helpers_health_formatters.R) ile çalışır. Her test örnek bir
#           checks data.frame'i kurar, UI'yi üretir ve Türkçe başlıklar,
#           değerler ve erişilebilirlik ipuçlarını doğrular. Ağ/DB/LLM GEREKMEZ.
# ==============================================================================

.source_health_tabs_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(file.path(repo_root, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_health_table.R"), encoding = "UTF-8", local = env)
  for (f in c("module_health_overview.R", "module_health_storage.R",
              "module_health_security.R", "module_health_connectivity.R",
              "module_health_diagnostics.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = env)
  }
  env
}

# Tüm sekmelerin ihtiyaç duyduğu kapsamlı örnek checks tablosu.
.health_full_checks <- function(env) {
  mk <- function(id, label, status, value = "", detail = "") {
    env$health_result(id, label, status, value, detail)
  }
  do.call(rbind, list(
    mk("security.sso", "SSO", "ok", "Kapalı (yerel)"),
    mk("runtime.uptime", "Çalışma Süresi", "ok", "1s 5dk"),
    mk("runtime.workers", "İşçi", "ok", "4 / 1 / 0"),
    mk("app.version", "Sürüm", "ok", "v1.0", "commit abc123"),
    mk("db.primary", "DB Primary", "ok", "ok"),
    mk("db.secondary", "DB Secondary", "not_configured", "not_configured"),
    mk("db.tertiary", "DB Tertiary", "not_configured", "not_configured"),
    mk("db.schema", "DB Şema", "ok", "Hazır"),
    mk("llm.endpoint", "LLM", "warning", "warning"),
    mk("llm.reasoning", "LLM Reasoning", "ok", "ok"),
    mk("tts.endpoint", "TTS", "not_configured", "not_configured"),
    mk("stt.endpoint", "STT", "not_configured", "not_configured"),
    mk("image.endpoint", "Görsel", "not_configured", "not_configured"),
    mk("storage.files_root", "Files Root", "ok", "/tmp/mergen/files"),
    mk("storage.uploads_root", "Uploads", "ok", "/tmp/mergen/uploads"),
    mk("storage.index_json", "Index", "critical", "/tmp/mergen/index.json"),
    mk("storage.log_dir", "Log", "ok", "/tmp/mergen/logs"),
    mk("storage.mcp_base", "MCP", "ok", "/tmp/mergen/mcp"),
    mk("storage.disk_free", "Disk", "ok", "10.0 GB"),
    mk("storage.upload_disk_free", "Upload Disk", "ok", "10.0 GB"),
    mk("env.LOCAL_LLM_ENDPOINT", "LLM Env", "ok", "configured"),
    mk("env.DB_DSN", "DB Env", "ok", "configured"),
    mk("env.AI_KEYS_MASTER", "Master Env", "ok", "configured"),
    mk("runtime.memory", "Bellek", "ok", "256 MB")
  ))
}

# ------------------------------------------------------------------------------
# health_overview_ui
# ------------------------------------------------------------------------------
testthat::test_that("health_overview_ui skor/kahraman bölümü ve 10 saniyelik özeti üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()

  html <- paste(as.character(env$health_overview_ui(.health_full_checks(env), "2026-06-03 10:00")), collapse = "\n")
  testthat::expect_true(grepl("Sistem Durumu", html, fixed = TRUE))
  testthat::expect_true(grepl("10 Saniyelik Özet", html, fixed = TRUE))
  testthat::expect_true(grepl("Son yenileme:", html, fixed = TRUE))
  testthat::expect_true(grepl("2026-06-03 10:00", html, fixed = TRUE))
  # Skor halkası /100 içermeli.
  testthat::expect_true(grepl("/100", html, fixed = TRUE))
  # Özet listesinde temel sinyaller (DB Primary, LLM Endpoint) yer almalı.
  testthat::expect_true(grepl("DB Primary:", html, fixed = TRUE))
  testthat::expect_true(grepl("LLM Endpoint:", html, fixed = TRUE))
})

testthat::test_that("health_overview_ui last_update NULL ise tire gösterir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()
  html <- paste(as.character(env$health_overview_ui(.health_full_checks(env), NULL)), collapse = "\n")
  testthat::expect_true(grepl("Son yenileme: —", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# health_storage_ui
# ------------------------------------------------------------------------------
testthat::test_that("health_storage_ui ortam değişkeni yollarını ve dosya sistemi kartını gösterir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()

  html <- paste(as.character(env$health_storage_ui(.health_full_checks(env))), collapse = "\n")
  testthat::expect_true(grepl("MERGEN_FILES_ROOT", html, fixed = TRUE))
  testthat::expect_true(grepl("MERGEN_UPLOADS_DIR", html, fixed = TRUE))
  testthat::expect_true(grepl("MERGEN_INDEX_PATH", html, fixed = TRUE))
  testthat::expect_true(grepl("Dosya Sistemi ve Disk", html, fixed = TRUE))
})

testthat::test_that("health_storage_path_item ad, değer ve ipucunu işler", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()
  html <- paste(as.character(
    env$health_storage_path_item("MERGEN_FILES_ROOT", "/veri/kok", "Kalıcı dosya deposu")
  ), collapse = "\n")
  testthat::expect_true(grepl("MERGEN_FILES_ROOT", html, fixed = TRUE))
  testthat::expect_true(grepl("Kalıcı dosya deposu", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# health_security_ui
# ------------------------------------------------------------------------------
testthat::test_that("health_security_ui zorunlu env sayımını ve maskeleme notunu gösterir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()

  html <- paste(as.character(env$health_security_ui(.health_full_checks(env))), collapse = "\n")
  # Üç zorunlu env değişkeni de 'ok' -> "3/3".
  testthat::expect_true(grepl("3/3", html, fixed = TRUE))
  testthat::expect_true(grepl("Güvenlik ve Yapılandırma", html, fixed = TRUE))
  # Gizli değerlerin maskelendiği belirtilmeli.
  testthat::expect_true(grepl("Maskeli", html, fixed = TRUE))
})

testthat::test_that("health_security_ui eksik zorunlu env'de kritik sayım üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()

  checks <- .health_full_checks(env)
  # DB_DSN env'ini kritik yap -> 2/3.
  checks$status[checks$id == "env.DB_DSN"] <- "critical"
  html <- paste(as.character(env$health_security_ui(checks)), collapse = "\n")
  testthat::expect_true(grepl("2/3", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# health_connectivity_ui
# ------------------------------------------------------------------------------
testthat::test_that("health_connectivity_ui DB/LLM bağlantı kartlarını ve tabloyu üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()

  html <- paste(as.character(env$health_connectivity_ui(.health_full_checks(env))), collapse = "\n")
  testthat::expect_true(grepl("Bağlantı Kontrolleri", html, fixed = TRUE))
  testthat::expect_true(grepl("DB Primary", html, fixed = TRUE))
  testthat::expect_true(grepl("DB Secondary", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# health_diagnostics_ui
# ------------------------------------------------------------------------------
testthat::test_that("health_diagnostics_ui uyarıları ve tüm sonuçları ayrı kartlarda gösterir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()

  html <- paste(as.character(env$health_diagnostics_ui(.health_full_checks(env))), collapse = "\n")
  testthat::expect_true(grepl("Uyarılar ve İyileştirme Önerileri", html, fixed = TRUE))
  testthat::expect_true(grepl("Tüm Kontrol Sonuçları", html, fixed = TRUE))
})

testthat::test_that("health_diagnostics_ui hiç kritik/uyarı yoksa boş durum mesajı verir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_health_tabs_for_test()

  # Tümü 'ok' olan checks -> uyarı kartı boş durum metni göstermeli.
  checks <- do.call(rbind, list(
    env$health_result("db.primary", "DB", "ok", "ok"),
    env$health_result("llm.endpoint", "LLM", "ok", "ok")
  ))
  html <- paste(as.character(env$health_diagnostics_ui(checks)), collapse = "\n")
  testthat::expect_true(grepl("Aktif kritik uyarı yok.", html, fixed = TRUE))
})