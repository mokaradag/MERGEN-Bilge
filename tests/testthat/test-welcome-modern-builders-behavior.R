# ==============================================================================
# Dosya Yolu: tests/testthat/test-welcome-modern-builders-behavior.R
# Açıklama: R/welcome_screen_modern.R saf UI oluşturucularının davranışsal
#           testleri: create_modern_tooltip ve create_modern_preview_button.
#           Üretilen HTML yapısı, veri öznitelikleri ve Türkçe metin doğrulanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.wm_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "welcome_screen_modern.R"),
  encoding = "UTF-8",
  local = .wm_env
)

test_that("create_modern_tooltip data-tooltip-text ve açıklama metnini içeren tooltip üretir", {
  skip_if_not_installed("shiny")

  html <- paste(as.character(.wm_env$create_modern_tooltip("Süreç yönetimi açıklaması")), collapse = "\n")

  expect_true(grepl("modern-tooltip", html, fixed = TRUE))
  expect_true(grepl("data-tooltip-text", html, fixed = TRUE))
  expect_true(grepl("Süreç yönetimi açıklaması", html, fixed = TRUE))
})

test_that("create_modern_preview_button sohbet id'si, yükleme tetikleyici ve başlığı içerir", {
  skip_if_not_installed("shiny")

  html <- paste(as.character(.wm_env$create_modern_preview_button(
    list(id = "c42", title = "Önceki Söyleşi Başlığı")
  )), collapse = "\n")

  expect_true(grepl("modern-welcome-preview-btn", html, fixed = TRUE))
  expect_true(grepl("data-chat-id=\"c42\"", html, fixed = TRUE))
  # Tıklama Shiny welcome_load_chat_id girdisini tetiklemeli.
  expect_true(grepl("welcome_load_chat_id", html, fixed = TRUE))
  expect_true(grepl("Önceki Söyleşi Başlığı", html, fixed = TRUE))
})
