# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-tab-ui-contract.R
# Açıklama: Yönetici paneli sekme-UI üreticilerinin YAPI/DAVRANIŞ sözleşme
#           testleri. Aşağıdaki yedi modül daha önce hiçbir test tarafından
#           çağrılmıyordu:
#             - R/module_admin_genel_bakis.R        (admin_overview_ui)
#             - R/module_admin_kullanici_analizi.R  (admin_users_ui)
#             - R/module_admin_yz_performans.R      (admin_ai_perf_ui)
#             - R/module_admin_geri_bildirim_genel.R(admin_feedback_ui)
#             - R/module_admin_sohbet_kalitesi.R    (admin_chat_quality_ui)
#             - R/module_admin_zaman_analizi.R      (admin_time_analysis_ui)
#             - R/module_admin_gelismis_analizler.R (admin_advanced_analytics_ui)
#
#           Bu _ui fonksiyonları enjekte edilen create_metric_card /
#           create_info_button / format_number yardımcılarını kullanır ve
#           grafik yer tutucuları için highcharter::highchartOutput çağırır.
#           Bu yüzden highcharter gerektirir (skip_if_not_installed ile korunur).
#           Boş data.frame'ler verilerek güvenli fallback dalları çalıştırılır;
#           metrik kart başlıkları (Türkçe) ve grafik çıktı kimlikleri doğrulanır.
#           Gerçek DB/ağ GEREKMEZ.
# ==============================================================================

# Modül dosyasını izole ortama yükler. _ui fonksiyonları yardımcıları parametre
# olarak aldığından helper modülü kaynaklamaya gerek yoktur.
.source_admin_module_for_test <- function(file_name) {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")
  suppressMessages(library(shiny))
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(file.path(resolve_repo_root_for_tests(), "R", file_name),
         encoding = "UTF-8", local = env)
  env
}

# Enjekte edilen yardımcı stub'ları: başlık/değeri görünür HTML'e işler.
.admin_stub_metric_card <- function(title, value, ...) {
  shiny::div(class = "metric-card", shiny::span(class = "mc-title", title),
             shiny::span(class = "mc-value", as.character(value)))
}
.admin_stub_info_button <- function(text = "") shiny::span(class = "info-btn", text)
.admin_stub_format_number <- function(x) as.character(x %||% 0)

# Tüm sekmelerin alanlarını boş data.frame olarak içeren güvenli veri kabı.
# Boş tablo -> nrow()==0 -> _ui fonksiyonları fallback değerlerini kullanır.
.admin_empty_data <- function() {
  alanlar <- c(
    "total_users", "total_chats", "total_messages", "total_ai_calls",
    "avg_response_time", "error_rate", "active_users_today", "avg_chat_length",
    "feedback_summary", "avg_messages_per_chat", "avg_session_duration",
    "bounce_rate", "total_feedback_count", "user_retention",
    "monthly_growth", "peak_hours", "this_week_stats",
    "first_response_success", "today_stats"
  )
  stats::setNames(lapply(alanlar, function(.) data.frame()), alanlar)
}

.admin_ui_html <- function(env, fn_name, with_data = TRUE) {
  fn <- env[[fn_name]]
  ui <- if (with_data) {
    fn(.admin_empty_data(), NS("adm"), .admin_stub_metric_card,
       .admin_stub_info_button, .admin_stub_format_number)
  } else {
    fn(NS("adm"), .admin_stub_info_button)
  }
  paste(as.character(ui), collapse = "\n")
}

# ------------------------------------------------------------------------------
# admin_overview_ui
# ------------------------------------------------------------------------------
testthat::test_that("admin_overview_ui temel metrik kartlarını ve grafik kimliklerini üretir", {
  env <- .source_admin_module_for_test("module_admin_genel_bakis.R")
  html <- .admin_ui_html(env, "admin_overview_ui")
  testthat::expect_true(grepl("Toplam Kullanıcı", html, fixed = TRUE))
  testthat::expect_true(grepl("Toplam Söyleşi", html, fixed = TRUE))
  testthat::expect_true(grepl("Hata Oranı", html, fixed = TRUE))
  testthat::expect_true(grepl("adm-daily_trend_chart", html, fixed = TRUE))
})

testthat::test_that("admin_overview_ui boş veride güvenli fallback değerleri üretir", {
  env <- .source_admin_module_for_test("module_admin_genel_bakis.R")
  # Dolu veri ile metrik değer çıkarımı.
  data <- .admin_empty_data()
  data$total_users <- data.frame(cnt = 42)
  data$error_rate <- data.frame(rate = 3.5)
  ui <- env$admin_overview_ui(data, NS("adm"), .admin_stub_metric_card,
                              .admin_stub_info_button, .admin_stub_format_number)
  html <- paste(as.character(ui), collapse = "\n")
  testthat::expect_true(grepl(">42<", html, fixed = TRUE))      # format_number(42)
  testthat::expect_true(grepl("3.5%", html, fixed = TRUE))      # error_rate sprintf
})

# ------------------------------------------------------------------------------
# admin_feedback_ui
# ------------------------------------------------------------------------------
testthat::test_that("admin_feedback_ui beğeni/memnuniyet kartlarını ve grafik kimliğini üretir", {
  env <- .source_admin_module_for_test("module_admin_geri_bildirim_genel.R")
  html <- .admin_ui_html(env, "admin_feedback_ui")
  testthat::expect_true(grepl("Beğeni Sayısı", html, fixed = TRUE))
  testthat::expect_true(grepl("Memnuniyet Oranı", html, fixed = TRUE))
  testthat::expect_true(grepl("adm-feedback_trend_chart", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# admin_chat_quality_ui
# ------------------------------------------------------------------------------
testthat::test_that("admin_chat_quality_ui sohbet kalitesi metriklerini üretir", {
  env <- .source_admin_module_for_test("module_admin_sohbet_kalitesi.R")
  html <- .admin_ui_html(env, "admin_chat_quality_ui")
  testthat::expect_true(grepl("Hemen Çıkma Oranı", html, fixed = TRUE))
  testthat::expect_true(grepl("Kullanıcı Tutma Oranı", html, fixed = TRUE))
  testthat::expect_true(grepl("Ortalama Oturum Süresi", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# admin_time_analysis_ui
# ------------------------------------------------------------------------------
testthat::test_that("admin_time_analysis_ui zaman analizi metriklerini ve grafiklerini üretir", {
  env <- .source_admin_module_for_test("module_admin_zaman_analizi.R")
  html <- .admin_ui_html(env, "admin_time_analysis_ui")
  testthat::expect_true(grepl("En Yoğun Saat Dilimleri", html, fixed = TRUE))
  testthat::expect_true(grepl("Aylık Büyüme", html, fixed = TRUE))
  testthat::expect_true(grepl("adm-weekly_trend_chart", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# admin_advanced_analytics_ui
# ------------------------------------------------------------------------------
testthat::test_that("admin_advanced_analytics_ui gelişmiş metrikleri üretir", {
  env <- .source_admin_module_for_test("module_admin_gelismis_analizler.R")
  html <- .admin_ui_html(env, "admin_advanced_analytics_ui")
  testthat::expect_true(grepl("İlk Yanıt Beğeni Oranı", html, fixed = TRUE))
  testthat::expect_true(grepl("Bugünkü Söyleşi", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# admin_users_ui / admin_ai_perf_ui (yalnızca ns + info button)
# ------------------------------------------------------------------------------
testthat::test_that("admin_users_ui kullanıcı analizi grafik kimliklerini üretir", {
  env <- .source_admin_module_for_test("module_admin_kullanici_analizi.R")
  html <- .admin_ui_html(env, "admin_users_ui", with_data = FALSE)
  testthat::expect_true(grepl("adm-top_users_chart", html, fixed = TRUE))
  testthat::expect_true(grepl("adm-usage_by_day_chart", html, fixed = TRUE))
})

testthat::test_that("admin_ai_perf_ui model performans grafik kimliklerini üretir", {
  env <- .source_admin_module_for_test("module_admin_yz_performans.R")
  html <- .admin_ui_html(env, "admin_ai_perf_ui", with_data = FALSE)
  testthat::expect_true(grepl("adm-model_performance_chart", html, fixed = TRUE))
  testthat::expect_true(grepl("adm-model_errors_chart", html, fixed = TRUE))
})
