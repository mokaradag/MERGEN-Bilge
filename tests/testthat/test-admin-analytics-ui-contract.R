# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-analytics-ui-contract.R
# Açıklama: R/module_admin_analytics.R adminAnalyticsUI() koordinatör UI'sinin
#           YAPI testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           adminAnalyticsUI(), admin_page_layout() yardımcısıyla 7 sekmeli
#           (Genel Bakış / Kullanıcı / YZ Performansı / Geri Bildirim / Sohbet
#           Kalitesi / Zaman / Gelişmiş) "Genel Analiz" panelini üretir.
#           highcharter GEREKTİRMEZ (yalnızca sekme kabuğu). Ağ/DB GEREKMEZ.
# ==============================================================================

.source_admin_analytics_ui_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  # helpers_admin_analytics.R kaynak-zamanı JS(...) çağırır; güvenli stub verilir.
  env$JS <- function(...) paste0(...)
  env$showToast <- function(...) invisible(NULL)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_analytics.R"),
         encoding = "UTF-8", local = env)
  # Bilge Yolaç sekmesi ayrı modül dosyasında (diğer admin sekmeleriyle aynı desen).
  source(file.path(resolve_repo_root_for_tests(), "R", "module_admin_bilge_yolac.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "module_admin_analytics.R"),
         encoding = "UTF-8", local = env)
  env
}

testthat::test_that("adminAnalyticsUI 'Genel Analiz' başlıklı panel kabuğunu üretir", {
  env <- .source_admin_analytics_ui_for_test()
  html <- paste(as.character(env$adminAnalyticsUI("adm")), collapse = "\n")
  testthat::expect_true(grepl("Genel Analiz", html, fixed = TRUE))
})

testthat::test_that("adminAnalyticsUI yedi sekmenin Türkçe başlıklarını içerir", {
  env <- .source_admin_analytics_ui_for_test()
  html <- paste(as.character(env$adminAnalyticsUI("adm")), collapse = "\n")
  for (baslik in c("Genel Bakış", "Kullanıcı Analizi", "YZ Performansı",
                   "Geri Bildirim", "Sohbet Kalitesi", "Zaman Analizi",
                   "Gelişmiş Analizler")) {
    testthat::expect_true(grepl(baslik, html, fixed = TRUE),
                          info = paste("eksik sekme başlığı:", baslik))
  }
})

testthat::test_that("adminAnalyticsUI sekme 'value' kimliklerini korur", {
  env <- .source_admin_analytics_ui_for_test()
  html <- paste(as.character(env$adminAnalyticsUI("adm")), collapse = "\n")
  for (deger in c("overview", "users", "ai_perf", "feedback",
                  "chat_quality", "time_analysis", "advanced_analytics")) {
    testthat::expect_true(grepl(deger, html, fixed = TRUE),
                          info = paste("eksik sekme value:", deger))
  }
})

testthat::test_that("adminAnalyticsUI Bilge Yolaç sekmesini (başlık + value) içerir", {
  env <- .source_admin_analytics_ui_for_test()
  html <- paste(as.character(env$adminAnalyticsUI("adm")), collapse = "\n")
  testthat::expect_true(grepl("Bilge Yolaç", html, fixed = TRUE))
  testthat::expect_true(grepl("bilge_yolac", html, fixed = TRUE))
})

testthat::test_that("admin_bilge_yolac_queries enjekte edilen safe_query ile beklenen anahtarları üretir", {
  env <- .source_admin_analytics_ui_for_test()

  cagrilan <- character(0)
  fake_safe_query <- function(query) {
    cagrilan <<- c(cagrilan, query)
    data.frame()
  }

  sonuc <- env$admin_bilge_yolac_queries(fake_safe_query)
  testthat::expect_true(is.list(sonuc))
  testthat::expect_setequal(
    names(sonuc),
    c("session_totals", "run_totals", "daily_trend", "status_dist",
      "top_users", "recent_sessions")
  )
  # Tüm sorgular Bilge Yolaç kalıcı oturum tablolarını hedefler.
  testthat::expect_true(any(grepl("MB_ClaudeCode_Sessions", cagrilan, fixed = TRUE)))
  testthat::expect_true(any(grepl("MB_ClaudeCode_Runs", cagrilan, fixed = TRUE)))
})

testthat::test_that("admin_bilge_yolac_ui boş veriyle güvenli metrik kartları üretir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")
  testthat::skip_if_not_installed("DT")

  env <- .source_admin_analytics_ui_for_test()
  bos <- env$admin_bilge_yolac_queries(function(query) data.frame())

  html <- paste(as.character(env$admin_bilge_yolac_ui(
    bos, shiny::NS("adm"),
    env$admin_create_metric_card, env$admin_create_info_button, env$admin_format_number
  )), collapse = "\n")

  testthat::expect_true(grepl("Toplam Oturum", html, fixed = TRUE))
  testthat::expect_true(grepl("adm-by_daily_trend_chart", html, fixed = TRUE))
  testthat::expect_true(grepl("adm-by_top_users_table", html, fixed = TRUE))
})
