# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-formatters-ui-builders-behavior.R
# Açıklama: R/helpers_health_formatters.R sağlık UI inşa fonksiyonlarının
#           davranışsal testleri. health_metric_tile, health_section_card ve
#           health_checks_table'ın yapısı, durum sınıfı, boş-veri durumu ve
#           HTML kaçışı (XSS koruması) doğrulanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.hfui_env <- new.env(parent = globalenv())

source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_health_formatters.R"),
  encoding = "UTF-8",
  local = .hfui_env
)

source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_health_table.R"),
  encoding = "UTF-8",
  local = .hfui_env
)

.hf_html <- function(ui) paste(as.character(ui), collapse = "")

# -----------------------------------------------------------------------------
# health_metric_tile
# -----------------------------------------------------------------------------

test_that("health_metric_tile başlık, değer, durum sınıfı ve tooltip üretir", {
  skip_if_not_installed("shiny")
  html <- .hf_html(.hfui_env$health_metric_tile("Toplam Kullanıcı", "42", status = "ok"))
  expect_true(grepl("health-metric-tile", html, fixed = TRUE))
  expect_true(grepl("health-status-ok", html, fixed = TRUE))
  expect_true(grepl("Toplam Kullanıcı", html, fixed = TRUE))
  expect_true(grepl(">42<", html, fixed = TRUE))
  # Varsayılan tooltip başlıktan türetilir.
  expect_true(grepl("sağlık göstergesi", html, fixed = TRUE))
})

test_that("health_metric_tile durum kelimesini değer olarak verince Türkçe etiket gösterir", {
  skip_if_not_installed("shiny")
  # value 'critical' bir durum seviyesi olduğu için etikete çevrilir.
  html <- .hf_html(.hfui_env$health_metric_tile("Durum", "critical", status = "critical"))
  expect_true(grepl("health-status-critical", html, fixed = TRUE))
  # Ham 'critical' kelimesi yerine Türkçe etiket gösterilmeli.
  expect_false(grepl(">critical<", html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# health_section_card
# -----------------------------------------------------------------------------

test_that("health_section_card başlık, ikon, tooltip ve çocuk içeriği sarar", {
  skip_if_not_installed("shiny")
  html <- .hf_html(.hfui_env$health_section_card(
    "Bağlantılar", "plug", shiny::div(class = "ic", "içerik"), tooltip = "açıklama ipucu"
  ))
  expect_true(grepl("health-section-card", html, fixed = TRUE))
  expect_true(grepl("Bağlantılar", html, fixed = TRUE))
  expect_true(grepl("açıklama ipucu", html, fixed = TRUE))
  # Çocuk içerik kart içinde yer almalı.
  expect_true(grepl("içerik", html, fixed = TRUE))
})

test_that("health_section_card tooltip verilmezse info-btn üretmez", {
  skip_if_not_installed("shiny")
  html <- .hf_html(.hfui_env$health_section_card("Başlık", "cog", shiny::div("x")))
  expect_false(grepl("info-btn", html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# health_checks_table
# -----------------------------------------------------------------------------

test_that("health_checks_table boş/NULL kontrol setinde boş mesaj döner", {
  skip_if_not_installed("shiny")
  expect_true(grepl("Gösterilecek kontrol sonucu yok",
                    .hf_html(.hfui_env$health_checks_table(NULL)), fixed = TRUE))
  expect_true(grepl("Gösterilecek kontrol sonucu yok",
                    .hf_html(.hfui_env$health_checks_table(data.frame())), fixed = TRUE))
})

test_that("health_checks_table başlıkları, süreyi gösterir ve aktif HTML'i kaçışlar", {
  skip_if_not_installed("shiny")
  checks <- data.frame(
    id = "db.primary",
    label = "<b>DB</b>",
    status = "ok",
    severity = "info",
    value = "SELECT 1",
    detail = "<script>alert(1)</script>",
    duration_ms = 12,
    checked_at = "2026-01-01",
    remediation = "yok",
    stringsAsFactors = FALSE
  )
  html <- .hf_html(.hfui_env$health_checks_table(checks))

  # Türkçe tablo başlıkları.
  for (baslik in c("Durum", "Kontrol", "Değer", "Detay", "Süre", "Zaman", "Öneri")) {
    expect_true(grepl(baslik, html, fixed = TRUE))
  }
  # Kontrol kimliği ve süre görünür.
  expect_true(grepl("db.primary", html, fixed = TRUE))
  expect_true(grepl("12 ms", html, fixed = TRUE))
  # Aktif HTML kaçışlanmalı: ham <b>...</b> ve <script> bloğu render edilmemeli.
  expect_false(grepl("<b>DB</b>", html, fixed = TRUE))
  expect_false(grepl("<script>alert(1)</script>", html, fixed = TRUE))
})

test_that("health_checks_table NA süreyi tire ile gösterir", {
  skip_if_not_installed("shiny")
  checks <- data.frame(
    id = "x.y", label = "L", status = "unknown", severity = "info",
    value = "v", detail = "d", duration_ms = NA_real_,
    checked_at = "2026", remediation = "", stringsAsFactors = FALSE
  )
  html <- .hf_html(.hfui_env$health_checks_table(checks))
  expect_true(grepl("—", html, fixed = TRUE))  # em-dash
})