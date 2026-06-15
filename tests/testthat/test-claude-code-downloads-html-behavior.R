# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-downloads-html-behavior.R
# Açıklama: format_claude_code_generated_downloads_html
#           (R/helpers_claude_code_downloads_html.R) Bilge Yolaç üretilen-dosya
#           indirme kartı HTML üreticisinin DAVRANIŞINI test eder. Bu fonksiyon
#           daha önce yalnızca policy-split contract'ında statik string olarak
#           referans alınıyordu; davranışsal (özellikle HTML/XSS güvenlik sınırı)
#           kapsaması yoktu. Kapsananlar:
#             * boş/NULL indirme listesi -> boş metin,
#             * geçerli kayıt -> kart HTML'i (display_name + url + size_label + İndir),
#             * çoklu kayıt -> her biri için kart,
#             * HTML metakarakterli url/dosya adı/yol -> htmlEscape (öznitelik
#               bağlamı attribute=TRUE; element bağlamı varsayılan) ile nötrlenir.
#           Gerçek CLI/dosya/DB/ağ GEREKMEZ; saf HTML üreticisi.
# ==============================================================================

testthat::local_edition(3)

# Saf HTML üreticisini izole ortama yükler (utils_common + downloads_html).
.ccdh_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_claude_code_downloads_html.R"), encoding = "UTF-8", local = env)
  env
}

testthat::test_that("format_claude_code_generated_downloads_html boş/NULL listede boş döner", {
  env <- .ccdh_env()
  testthat::expect_identical(env$format_claude_code_generated_downloads_html(list()), "")
  testthat::expect_identical(env$format_claude_code_generated_downloads_html(NULL), "")
})

testthat::test_that("format_claude_code_generated_downloads_html geçerli kayıt için kart üretir", {
  env <- .ccdh_env()
  downloads <- list(list(
    url = "bilge_yolac_downloads/user_1/session_a/20260101_01_rapor.txt",
    download_name = "rapor.txt",
    display_name = "rapor.txt",
    display_path = "cikti/rapor.txt",
    original_path = "/tmp/wd/cikti/rapor.txt",
    size_label = "1.2 KB"
  ))

  html <- env$format_claude_code_generated_downloads_html(downloads)

  testthat::expect_true(nzchar(html))
  testthat::expect_true(grepl("cc-generated-file-card", html, fixed = TRUE))
  testthat::expect_true(grepl("Oluşturulan Dosyalar", html, fixed = TRUE))
  testthat::expect_true(grepl("rapor.txt", html, fixed = TRUE))
  testthat::expect_true(grepl("cikti/rapor.txt", html, fixed = TRUE))
  testthat::expect_true(grepl("1.2 KB", html, fixed = TRUE))
  testthat::expect_true(grepl(paste0(intToUtf8(0x0130), "ndir"), html, fixed = TRUE))  # "İndir"
})

testthat::test_that("format_claude_code_generated_downloads_html birden çok kayıt için ayrı kart üretir", {
  env <- .ccdh_env()
  downloads <- list(
    list(url = "u/a", display_name = "a.txt", download_name = "a.txt", size_label = "1 KB"),
    list(url = "u/b", display_name = "b.txt", download_name = "b.txt", size_label = "2 KB")
  )

  html <- env$format_claude_code_generated_downloads_html(downloads)

  testthat::expect_identical(
    length(gregexpr("cc-generated-file-card", html, fixed = TRUE)[[1]]), 2L
  )
  testthat::expect_true(grepl("a.txt", html, fixed = TRUE))
  testthat::expect_true(grepl("b.txt", html, fixed = TRUE))
})

testthat::test_that("HTML metakarakterli alanlar htmlEscape ile nötrlenir (XSS/öznitelik enjeksiyonu sınırı)", {
  env <- .ccdh_env()
  downloads <- list(list(
    url = "u/a\"x",                       # öznitelikte tırnak -> escape edilmeli
    download_name = "kotu\"x.txt",        # öznitelikte tırnak
    display_name = "ad<b>\"x.txt",        # element + tırnak
    display_path = "yol<i>",
    original_path = "/tmp/\"x<y>",        # title özniteliği
    size_label = "1 KB"
  ))

  html <- env$format_claude_code_generated_downloads_html(downloads)

  # Açı parantezleri her bağlamda escape edilmeli.
  testthat::expect_true(grepl("&lt;b&gt;", html, fixed = TRUE))
  testthat::expect_false(grepl("<b>", html, fixed = TRUE))
  testthat::expect_false(grepl("<i>", html, fixed = TRUE))
  testthat::expect_false(grepl("<y>", html, fixed = TRUE))
  # Öznitelik bağlamındaki çift tırnak escape edilmeli (öznitelikten kaçış olmamalı).
  testthat::expect_true(grepl("&quot;", html, fixed = TRUE))
})
