# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-refresh-button-behavior.R
# Açıklama: Dosya Yönetimi sayfasındaki "Yenile" butonunun UI sözleşmesini
#           doğrular. Buton, "Tümünü Temizle" ile aynı başlık grubunda yer alır,
#           refresh_files girişine bağlıdır ve btn-refresh sınıfını taşır.
#           Gerçek Shiny oturumu/DB GEREKMEZ; yalnızca UI HTML'i incelenir.
# ==============================================================================

testthat::local_edition(3)
if (requireNamespace("shiny", quietly = TRUE)) suppressMessages(library(shiny))

.source_fm_ui <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_file_manager_ui.R"),
    encoding = "UTF-8", local = env
  )
  env
}

.fm_ui_html <- function() {
  env <- .source_fm_ui()
  paste(as.character(env$fileManagerUI("fm")), collapse = "\n")
}

testthat::test_that("Dosya Yönetimi UI'sinde Yenile butonu refresh_files girişine bağlı", {
  html <- .fm_ui_html()
  testthat::expect_true(grepl('id="fm-refresh_files"', html, fixed = TRUE))
})

testthat::test_that("Yenile butonu btn-refresh sınıfını ve yenileme ikonunu taşır", {
  html <- .fm_ui_html()
  testthat::expect_true(grepl("btn-refresh", html, fixed = TRUE))
  # FontAwesome sürümüne göre sync-alt -> fa-rotate / fa-sync olabilir; toleranslı doğrula.
  testthat::expect_true(
    grepl("fa-rotate", html, fixed = TRUE) ||
      grepl("fa-sync", html, fixed = TRUE) ||
      grepl("sync-alt", html, fixed = TRUE)
  )
  testthat::expect_true(grepl("Yenile", html, fixed = TRUE))
})

testthat::test_that("Yenile ve Tümünü Temizle aynı buton grubunda (files-header-actions) yer alır", {
  html <- .fm_ui_html()
  testthat::expect_true(grepl("files-header-actions", html, fixed = TRUE))
  testthat::expect_true(grepl('id="fm-clear_files"', html, fixed = TRUE))
})

testthat::test_that("Yenile butonu Tümünü Temizle butonundan ÖNCE gelir", {
  html <- .fm_ui_html()
  poz_refresh <- regexpr('id="fm-refresh_files"', html, fixed = TRUE)
  poz_clear <- regexpr('id="fm-clear_files"', html, fixed = TRUE)
  testthat::expect_true(poz_refresh > 0 && poz_clear > 0)
  testthat::expect_lt(poz_refresh, poz_clear)
})

testthat::test_that("Tümünü Temizle butonu kırmızı (btn-danger) kimliğini korur", {
  html <- .fm_ui_html()
  testthat::expect_true(grepl("btn-danger", html, fixed = TRUE))
  testthat::expect_true(grepl("Tümünü Temizle", html, fixed = TRUE))
})
