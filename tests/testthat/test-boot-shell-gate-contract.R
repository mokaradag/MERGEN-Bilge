# ==============================================================================
# Dosya Yolu: tests/testthat/test-boot-shell-gate-contract.R
# Açıklama: Açılış kabuk kapısı (pre-paint dashboard-shell gate) sözleşme
#           testleri. Kenar çubuğu/başlık/içerik kabuğu, GÖSTERİLEN yükleme
#           ilerlemesi %100'e ulaşana dek görünmez kalır; kapı yalnızca
#           app_loading.js kapanış yolunda bırakılır ve katman hiç kurulamazsa
#           DOMContentLoaded yetenek denetimi kabuğu kalıcı gizli bırakmaz.
#           Testler statiktir + render tabanlıdır: tarayıcı/DB/LLM/ağ GEREKMEZ.
# ==============================================================================

.boot_gate_repo_root <- function() {
  resolve_repo_root_for_tests()
}

.boot_gate_oku <- function(rel_path) {
  full_path <- file.path(.boot_gate_repo_root(), rel_path)
  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\r\n?|\r", "\n", txt, perl = TRUE))
}

.boot_gate_has <- function(txt, pattern) {
  grepl(pattern, txt, fixed = TRUE, useBytes = TRUE)
}

testthat::test_that("kabuk kapısı head etiketleri kabuğu gizler, katman/seçici/SSO yüzeyini açık bırakır", {
  testthat::skip_if_not_installed("shiny")
  suppressPackageStartupMessages(library(shiny))

  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(
    file.path(.boot_gate_repo_root(), "R", "module_app_loading.R"),
    encoding = "UTF-8",
    local = env
  )

  testthat::expect_true(is.function(env$app_loading_shell_gate_head_tags))
  html <- paste(as.character(env$app_loading_shell_gate_head_tags()), collapse = "\n")

  # Kapı sınıfı gövde boyanmadan önce <html> üzerine uygulanır.
  testthat::expect_true(grepl("mergen-boot-shell-gate", html, fixed = TRUE))
  testthat::expect_true(grepl('classList.add("mergen-boot-shell-gate")', html, fixed = TRUE))

  # Kabuk gizleme: başlık + kenar çubuğu + içerik kabuğu (visibility; yerleşim
  # korunur, açığa çıkarken sıçrama olmaz).
  testthat::expect_true(grepl("html.mergen-boot-shell-gate .main-header", html, fixed = TRUE))
  testthat::expect_true(grepl("html.mergen-boot-shell-gate .main-sidebar", html, fixed = TRUE))
  testthat::expect_true(grepl("html.mergen-boot-shell-gate .content-wrapper", html, fixed = TRUE))
  testthat::expect_true(grepl("visibility: hidden !important;", html, fixed = TRUE))

  # Açık istisnalar: yükleme katmanı, şerit seçicisi ve SSO hata yüzeyi.
  testthat::expect_true(grepl("#app-loading-overlay", html, fixed = TRUE))
  testthat::expect_true(grepl("#mergen-lane-select", html, fixed = TRUE))
  testthat::expect_true(grepl(".sso-auth-overlay", html, fixed = TRUE))
  testthat::expect_true(grepl("visibility: visible !important;", html, fixed = TRUE))

  # Bırakma API'si + kalıcı-gizli-kalma emniyeti (zamanlayıcı DEĞİL; DOM hazır
  # olduğunda katman/denetleyici yokluğu yetenek denetimiyle saptanır).
  testthat::expect_true(grepl("window.MergenBootShellGate", html, fixed = TRUE))
  testthat::expect_true(grepl("release:", html, fixed = TRUE))
  testthat::expect_true(grepl("isHeld:", html, fixed = TRUE))
  testthat::expect_true(grepl("DOMContentLoaded", html, fixed = TRUE))
  testthat::expect_true(grepl("window.MergenAppLoading", html, fixed = TRUE))
})

testthat::test_that("ui.R kabuk kapısını head içinde varlık manifestinden önce kurar", {
  ui_txt <- .boot_gate_oku("ui.R")

  gate_pos <- regexpr("app_loading_shell_gate_head_tags()", ui_txt, fixed = TRUE)
  assets_pos <- regexpr("ui_asset_tags()", ui_txt, fixed = TRUE)
  testthat::expect_true(gate_pos > 0)
  testthat::expect_true(assets_pos > 0)
  testthat::expect_true(gate_pos < assets_pos)
})

testthat::test_that("app_loading.js kapıyı yalnızca %100 gösteriminde bırakır ve emniyet yolları taşır", {
  txt <- .boot_gate_oku("www/js/app_loading.js")

  # Bırakma yardımcısı ve katman-yok erken çıkış emniyeti.
  testthat::expect_true(.boot_gate_has(txt, "function releaseShellGate()"))
  testthat::expect_true(.boot_gate_has(txt, "window.MergenBootShellGate.release()"))

  overlay_yok <- regexpr("if (!overlay) {", txt, fixed = TRUE)
  overlay_yok_release <- regexpr("releaseShellGate();\n    return;", txt, fixed = TRUE)
  testthat::expect_true(overlay_yok > 0 && overlay_yok_release > overlay_yok)

  # Kapı, gösterilen ilerleme %100'e ulaştığı karede (erime başlamadan hemen
  # önce) bırakılır: fadeStarted -> releaseShellGate -> setTimeout sırası.
  fade_pos <- regexpr("fadeStarted = true;", txt, fixed = TRUE)
  release_pos <- regexpr("fadeStarted = true;\n        releaseShellGate();", txt, fixed = TRUE)
  timeout_pos <- regexpr("overlay.classList.add(\"app-loading-hidden\")", txt, fixed = TRUE)
  testthat::expect_true(fade_pos > 0)
  testthat::expect_true(release_pos > 0)
  testthat::expect_true(timeout_pos > release_pos)

  # %100 eşiği korunur (kapı daha erken bırakılamaz).
  testthat::expect_true(.boot_gate_has(txt, "finished && displayPct >= 99.95 && !fadeStarted"))

  # Temizlik yolu yedek bırakma içerir (kabuk hiçbir uçta gizli kalamaz).
  cleanup_pos <- regexpr("function cleanup() {", txt, fixed = TRUE)
  cleanup_release <- regexpr("function cleanup() {\n    // Yedek güvence", txt, fixed = TRUE)
  testthat::expect_true(cleanup_pos > 0 && cleanup_release > 0)
})

testthat::test_that("hızlı şerit kapanış animasyonu ve bekletmesi kısaltılmıştır", {
  txt <- .boot_gate_oku("www/js/app_loading.js")

  # Hızlı şeritte finish sonrası daha hızlı dolum + kısaltılmış bekletme;
  # zengin şerit değerleri (0.16 / 0.65 / 470) korunur.
  testthat::expect_true(.boot_gate_has(txt, "isFastLane() ? 0.32 : 0.16"))
  testthat::expect_true(.boot_gate_has(txt, "isFastLane() ? 2.1 : 0.65"))
  testthat::expect_true(.boot_gate_has(txt, "isFastLane() ? 180 : 470"))
})
