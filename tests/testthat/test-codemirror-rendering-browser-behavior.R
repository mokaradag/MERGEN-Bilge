# ==============================================================================
# Dosya Yolu: tests/testthat/test-codemirror-rendering-browser-behavior.R
# Açıklama: Kod blokları gerçek tarayıcıda GERÇEK CodeMirror ile çizilir:
#           Python/R/JavaScript/SQL için dil belirteçleri üretilir, koyu ve açık
#           temada zemin/oluk/satır numarası/belirteç renkleri okunur ve
#           ayrışır, oluk tıklaması katlar, uzun kodun tüm satırları çizilir ve
#           kopyalama tam orijinal kodu verir. Ayrıntılar:
#           tests/scripts/codemirror_rendering_check.R ve
#           tests/scripts/codemirror_rendering_probe.js.
#
#           Yerel Chrome/Chromium/Edge yoksa (veya tarayıcı hiç başlatılamazsa)
#           test atlanır; sayfa çizilip denetim başarısız olursa test düşer.
# ==============================================================================

test_that("kod blokları gerçek CodeMirror ile vurgulanır, katlanır ve tam kopyalanır", {
  skip_if_not_installed("processx")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")

  root <- resolve_repo_root_for_tests()
  runner <- new.env(parent = globalenv())
  exprs <- parse(text = readLines(file.path(root, "tests", "scripts", "codemirror_rendering_check.R"),
                                 warn = FALSE, encoding = "UTF-8"),
                 keep.source = FALSE, encoding = "UTF-8")
  for (expr in exprs) eval(expr, runner)

  browser <- runner$cm_render_check_find_browser()
  required <- nzchar(Sys.getenv("MERGEN_BROWSER_BIN", unset = ""))
  if (!nzchar(browser)) {
    if (required) fail("MERGEN_BROWSER_BIN ayarlı ama tarayıcı bulunamadı.")
    skip("Yerel Chrome/Chromium/Edge bulunamadı (MERGEN_BROWSER_BIN).")
  }

  res <- runner$cm_render_check_run(root, browser)
  skip_if(!required && !isTRUE(res$page_rendered) &&
            !identical(res$browser_status, 0L) && !identical(res$browser_status, 124L),
          paste("Tarayıcı başlatılamadı:", substr(res$stderr, 1L, 300L)))

  report <- runner$cm_render_check_plain(paste(res$status, res$log, sep = "\n"))
  expect_true(isTRUE(res$page_rendered), info = report)
  expect_true(isTRUE(res$passed), info = report)
})
