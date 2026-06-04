# ==============================================================================
# Dosya Yolu: tests/testthat/test-welcome-modern-action-builder-behavior.R
# Açıklama: R/welcome_screen_modern.R create_modern_welcome_action() hızlı işlem
#           buton inşacısının davranışsal testleri. data-action-id/model,
#           _handleQuickAction bağlama, ikon, başlık ve tema renginin RGB CSS
#           değişkenlerine çevrimi doğrulanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.wma_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "welcome_screen_modern.R"),
  encoding = "UTF-8", local = .wma_env
)

.wma_action <- function() {
  list(
    id = "excel_analysis",
    title = "Excel Analizi",
    description = "Excel dosyalarını analiz et",
    themeColor = "#3b82f6",
    model_value = "model-x",
    icon_name = "table"
  )
}

test_that("create_modern_welcome_action quick-action veri özniteliklerini ve onclick'i bağlar", {
  skip_if_not_installed("shiny")
  html <- paste(as.character(.wma_env$create_modern_welcome_action(.wma_action())), collapse = "")

  expect_true(grepl('data-action-id="excel_analysis"', html, fixed = TRUE))
  expect_true(grepl('data-action-model="model-x"', html, fixed = TRUE))
  expect_true(grepl("_handleQuickAction", html, fixed = TRUE))
})

test_that("create_modern_welcome_action başlık, açıklama (title) ve ikonu yerleştirir", {
  skip_if_not_installed("shiny")
  html <- paste(as.character(.wma_env$create_modern_welcome_action(.wma_action())), collapse = "")

  expect_true(grepl("Excel Analizi", html, fixed = TRUE))
  # Açıklama buton title özniteliğinde tooltip olarak yer alır.
  expect_true(grepl("Excel dosyalarını analiz et", html, fixed = TRUE))
  # İkon FontAwesome sınıfı olarak gelir.
  expect_true(grepl("fa-table", html, fixed = TRUE))
})

test_that("create_modern_welcome_action tema rengini RGB CSS değişkenlerine çevirir", {
  skip_if_not_installed("shiny")
  html <- paste(as.character(.wma_env$create_modern_welcome_action(.wma_action())), collapse = "")
  # #3b82f6 -> rgb(59, 130, 246)
  expect_true(grepl("--theme-r: 59", html, fixed = TRUE))
  expect_true(grepl("--theme-g: 130", html, fixed = TRUE))
  expect_true(grepl("--theme-b: 246", html, fixed = TRUE))
  # Stroke rengi tema rengini taşır.
  expect_true(grepl("#3b82f6", html, fixed = TRUE))
})
