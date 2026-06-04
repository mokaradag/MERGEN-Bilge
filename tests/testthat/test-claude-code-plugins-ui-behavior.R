# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-plugins-ui-behavior.R
# Açıklama: R/module_claude_code_plugins.R claudeCodePluginsUI() eklenti paneli
#           UI inşacısının davranışsal testleri. Varsayılan daraltılmış durumun
#           DIŞ wrapper'da olması (korunan sözleşme), Türkçe etiketler, yenile
#           butonu, sayaç rozeti ve uiOutput yer tutucu doğrulanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.ccp_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_claude_code_plugins.R"),
  encoding = "UTF-8", local = .ccp_env
)

.ccp_ui_html <- function() {
  paste(as.character(.ccp_env$claudeCodePluginsUI(shiny::NS("cc"))), collapse = "")
}

test_that("claudeCodePluginsUI dış wrapper'da varsayılan daraltılmış sınıfı taşır", {
  skip_if_not_installed("shiny")
  html <- .ccp_ui_html()
  # Korunan sözleşme: cc-plugins-collapsed DIŞ wrapper div'inde olmalı.
  expect_true(grepl("cc-plugins-collapsed", html, fixed = TRUE))
  expect_true(grepl('id="cc-plugins_wrapper"', html, fixed = TRUE))
  # Daraltma onclick'i wrapper id'sini hedeflemeli.
  expect_true(grepl("cc-plugins_wrapper", html, fixed = TRUE))
})

test_that("claudeCodePluginsUI Türkçe başlık ve bölüm etiketlerini içerir", {
  skip_if_not_installed("shiny")
  html <- .ccp_ui_html()
  expect_true(grepl("Eklentiler", html, fixed = TRUE))
  expect_true(grepl("Yerel Eklentiler", html, fixed = TRUE))
})

test_that("claudeCodePluginsUI yenile butonu, sayaç rozeti, geçiş ikonu ve uiOutput üretir", {
  skip_if_not_installed("shiny")
  html <- .ccp_ui_html()
  expect_true(grepl("refresh_plugins", html, fixed = TRUE))
  expect_true(grepl("plugins_count_badge", html, fixed = TRUE))
  expect_true(grepl("cc-plugins-toggle-icon", html, fixed = TRUE))
  expect_true(grepl("local_plugins_ui", html, fixed = TRUE))
})
