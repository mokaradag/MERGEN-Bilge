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

test_that("Son Konuşmalar ODBC duvar saati ile yerel anı aynı saat düzleminde sıralar ve İstanbul tarihini gösterir", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  sys.source(file.path(kok, "R", "helpers_chat_message_formatting.R"), envir = env, keep.source = FALSE)
  sys.source(file.path(kok, "R", "welcome_screen_modern.R"), envir = env, keep.source = FALSE)
  for (tz in c("UTC", "Europe/Istanbul")) withr::with_envvar(c(TZ = tz), {
    # DB: İstanbul 12:00 (sürücü UTC etiketiyle döndürür) = 09:00Z.
    db <- as.POSIXct("2026-11-20 12:00:00", tz = "UTC")
    # Yerel: gerçek an 10:00Z (İstanbul 13:00) -> daha yeni.
    yerel <- structure(as.numeric(as.POSIXct("2026-11-20 10:00:00", tz = "UTC")), class = c("POSIXct", "POSIXt"))
    gece <- as.POSIXct("2026-11-20 23:30:00", tz = "UTC")  # İstanbul 20.11 23:30 (UTC düzleminde de 20.11)
    sohbetler <- list(
      "db" = list(title = "DB", last_message_timestamp = db),
      "yerel" = list(title = "Yerel", last_message_timestamp = yerel),
      "eksik" = list(title = "Eksik", last_message_timestamp = NA, timestamp = "2026-11-19 08:00:00"),
      "gece" = list(title = "Gece", last_message_timestamp = gece)
    )
    ogeler <- env$mergen_welcome_recent_items(sohbetler)
    expect_identical(vapply(ogeler, function(x) x$id, character(1)), c("gece", "yerel", "db"), info = tz)
    expect_identical(ogeler[[1]]$time, "20.11.2026", info = tz)
  })
})
