# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-hata-badges-behavior.R
# Açıklama: R/helpers_admin_hata_detail_runtime.R saf rozet yardımcılarının
#           davranışsal testleri: admin_ha_badge_text_color (parlaklığa göre
#           metin rengi) ve admin_ha_badge_html (renk/etiket eşlemeli HTML rozet,
#           bilinmeyen değer için gri fallback ve değerin kendisi).
# ==============================================================================

testthat::local_edition(3)

.adb_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_hata_detail_runtime.R"),
  encoding = "UTF-8",
  local = .adb_env
)

test_that("admin_ha_badge_text_color açık arka planda koyu, koyu arka planda beyaz metin verir", {
  expect_equal(.adb_env$admin_ha_badge_text_color("#ffffff"), "#1a1a1a")
  expect_equal(.adb_env$admin_ha_badge_text_color("#000000"), "#ffffff")
  # Turuncu (parlak) -> koyu metin; kırmızı (orta-koyu) -> beyaz metin.
  expect_equal(.adb_env$admin_ha_badge_text_color("#f59e0b"), "#1a1a1a")
  expect_equal(.adb_env$admin_ha_badge_text_color("#ef4444"), "#ffffff")
})

test_that("admin_ha_badge_html bilinen değer için renk/etiket eşlemeli rozet üretir", {
  html <- .adb_env$admin_ha_badge_html(
    "kritik",
    colors = c(kritik = "#ef4444", dusuk = "#3b82f6"),
    labels = c(kritik = "Kritik", dusuk = "Düşük")
  )
  expect_true(grepl("background:#ef4444", html, fixed = TRUE))
  expect_true(grepl("color:#ffffff", html, fixed = TRUE))   # kırmızı -> beyaz metin
  expect_true(grepl(">Kritik<", html, fixed = TRUE))
})

test_that("admin_ha_badge_html bilinmeyen değer için gri fallback ve değerin kendisini kullanır", {
  html <- .adb_env$admin_ha_badge_html(
    "tanimsiz",
    colors = c(kritik = "#ef4444"),
    labels = c(kritik = "Kritik")
  )
  expect_true(grepl("background:#94a3b8", html, fixed = TRUE))  # fallback renk
  expect_true(grepl(">tanimsiz<", html, fixed = TRUE))          # etiket yoksa değerin kendisi
})
