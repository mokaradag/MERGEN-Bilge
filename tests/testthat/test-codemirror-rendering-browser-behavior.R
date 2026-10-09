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
  # CP1254 Windows'ta readLines() + parse(text=) geçersiz UTF-8 üretebilir.
  for (expr in parse_r_file_utf8(file.path(root, "tests", "scripts", "codemirror_rendering_check.R"))) {
    eval(expr, runner)
  }

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

  report <- runner$cm_render_check_plain(paste(res$status, res$log, res$browser_status,
                                             res$stderr, sep = "\n"))
  expect_true(isTRUE(res$page_rendered), info = report)
  expect_true(isTRUE(res$passed), info = report)
})

test_that("RAF askıya alınsa da gerçek yerleşim PASS veya FAIL sonucunu belirler", {
  node <- Sys.which("node")
  if (!nzchar(node)) skip("Node bulunamadı")
  path <- file.path(resolve_repo_root_for_tests(), "tests/scripts/codemirror_rendering_probe.js")
  source <- rawToChar(readBin(path, what = "raw", n = file.info(path)$size))
  Encoding(source) <- "UTF-8"
  source <- gsub("\r\n", "\n", source, fixed = TRUE)
  for (probe_source in list(source, gsub("\n", "\r\n", source, fixed = TRUE))) {
    probe_source <- gsub("\r\n", "\n", probe_source, fixed = TRUE)
    start <- regexpr("  function nextPaint()", probe_source, fixed = TRUE)[1]
    end <- regexpr("  async function setThemeAndSettle", probe_source, fixed = TRUE)[1]
    expect_gt(start, 0L)
    expect_gt(end, start)
    fn <- substr(probe_source, start, end - 1L)
    helpers <- substr(probe_source, regexpr("  function log(msg)", probe_source, fixed = TRUE)[1],
      regexpr("  function wait(ms)", probe_source, fixed = TRUE)[1] - 1L)
    report_start <- regexpr("    logEl.textContent =", probe_source, fixed = TRUE)[1]
    report_end <- regexpr("\n  }\n\n  run();", probe_source, fixed = TRUE)[1]
    expect_gt(report_start, 0L)
    expect_gt(report_end, report_start)
    report <- substr(probe_source, report_start, report_end - 1L)
    js <- paste0("async function probe(rafWorks, valid) {",
      "let timer, delay, clears = 0, layouts = 0; const failures = [], logLines = [];",
      "const statusEl = {}, logEl = {}; const document = {documentElement: {",
      "getBoundingClientRect: () => {layouts++; return {width: valid ? 100 : 0, height: 100};}}};",
      "const setTimeout = (f, ms) => {timer = f; delay = ms; return 1;};",
      "const clearTimeout = () => {clears++;};",
      "const requestAnimationFrame = f => {if (rafWorks) f();};", helpers, fn,
      "const completion = nextPaint(); if (!rafWorks) timer(); await completion; timer();", report,
      "const expected = valid ? 'CODEMIRROR_RENDER_CHECK:PASS' : 'CODEMIRROR_RENDER_CHECK:FAIL 1';",
      "if (delay !== 1000 || layouts !== 1 || clears !== 1 || statusEl.textContent.split('\\n')[0] !== expected)",
      "throw new Error('RAF/layout/result contract');}",
      "(async () => {for (const raf of [false, true]) for (const valid of [false, true])",
      "await probe(raf, valid); console.log('PASS');})().catch(e => {console.error(e); process.exit(1);});")
    result <- system2(node, c("-e", shQuote(js)), stdout = TRUE, stderr = TRUE)
    expect_null(attr(result, "status"))
    expect_identical(result, "PASS")
  }
})
