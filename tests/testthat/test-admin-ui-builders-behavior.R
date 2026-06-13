# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-ui-builders-behavior.R
# Açıklama: Admin sayfa UI builder'larının saf davranışını doğrular:
#           adminYanitAnaliziUI (Yanıt Geri Bildirimi Analizi sekmeleri),
#           admin_doc_group_tab_panels + adminDokumantasyonUI (Dokümantasyon
#           grup sekmeleri). admin_page_layout (helpers_admin_analytics.R) gerçek
#           kullanılır; sekme value/başlık/ns sözleşmesi render edilen HTML
#           üzerinden kontrol edilir. Çevrimdışı/deterministik; DB/ağ/LLM yok.
# ==============================================================================

# Türkçe yorum: admin_page_layout htmlwidgets::JS'i source-time kullanır; bu
# nedenle htmlwidgets yüklenir. utils_text_encoding admin_doc_registry için yedek.
suppressMessages({
  library(shiny)
  library(htmlwidgets)
})

.adminUiBuildersEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "utils_text_encoding.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_admin_analytics.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_admin_documentation.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_admin_yanit_analizi.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_admin_documentation.R"), encoding = "UTF-8", local = env)
  env
}

.renderHtml <- function(ui) paste(as.character(ui), collapse = "\n")

test_that("adminYanitAnaliziUI dört sekmeyi doğru value ve Türkçe başlıkla üretir", {
  env <- .adminUiBuildersEnv()
  html <- .renderHtml(env$adminYanitAnaliziUI("ya"))

  # Türkçe yorum: sekme value'ları (tabPanel value -> data-value)
  for (deger in c("ya_overview", "ya_model", "ya_etiket", "ya_zaman")) {
    expect_true(grepl(deger, html, fixed = TRUE), info = deger)
  }
  # Türkçe başlıklar
  expect_true(grepl("Genel Bakış", html, fixed = TRUE))
  expect_true(grepl("Model Performansı", html, fixed = TRUE))
  expect_true(grepl("Etiket & Yorum Analizi", html, fixed = TRUE) ||
                grepl("Etiket &amp; Yorum Analizi", html, fixed = TRUE))
  expect_true(grepl("Zaman & Kullanıcı Analizi", html, fixed = TRUE) ||
                grepl("Zaman &amp; Kullanıcı Analizi", html, fixed = TRUE))
  # Sayfa başlığı
  expect_true(grepl("Yanıt Geri Bildirimi Analizi", html, fixed = TRUE))
})

test_that("adminYanitAnaliziUI ns ile namespace'lenmiş id'ler üretir", {
  env <- .adminUiBuildersEnv()
  html <- .renderHtml(env$adminYanitAnaliziUI("ya"))
  # Türkçe yorum: admin_page_layout ns ile refresh/tabs id'lerini namespace'ler
  expect_true(grepl("ya-admin_tabs", html, fixed = TRUE))
  expect_true(grepl("ya-refresh_analytics", html, fixed = TRUE))
})

test_that("admin_doc_group_tab_panels her kayıt grubu için bir sekme üretir", {
  env <- .adminUiBuildersEnv()
  gruplar <- env$admin_doc_registry()
  paneller <- env$admin_doc_group_tab_panels()

  expect_type(paneller, "list")
  expect_length(paneller, length(gruplar))

  html <- .renderHtml(paneller)
  # Türkçe yorum: her grup id'si bir sekme value'su olmalı, grup başlığı görünmeli
  for (g in gruplar) {
    expect_true(grepl(g$id, html, fixed = TRUE), info = g$id)
    expect_true(grepl(g$title, html, fixed = TRUE), info = g$title)
  }
})

test_that("adminDokumantasyonUI doküman sayfasını grup sekmeleriyle üretir", {
  env <- .adminUiBuildersEnv()
  html <- .renderHtml(env$adminDokumantasyonUI("doc"))

  expect_true(grepl("Dokümantasyon", html, fixed = TRUE))
  # En az bir kayıt grubunun value'su sayfa içinde olmalı
  gruplar <- env$admin_doc_registry()
  expect_true(grepl(gruplar[[1]]$id, html, fixed = TRUE))
  # ns sözleşmesi
  expect_true(grepl("doc-admin_tabs", html, fixed = TRUE))
})
