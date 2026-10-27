# ==============================================================================
# Dosya Yolu: tests/testthat/test-ux-smoke-exposure-gate-behavior.R
# Açıklama: UX smoke harness'ı gerçek uygulama eylemleri tetikler; üretimde
#           kimliği doğrulanmamış bir eylem yüzeyi olmamalıdır.
#           - Harness www/ dışında (tests/smoke) tutulur: www alt dizinleri,
#             img -> www takma adı ve Windows harf varyantları onu sunamaz.
#           - /smoke statik yolu yalnızca MERGEN_ENABLE_UX_SMOKE ile kaydedilir.
#           - Sayfa yüklemesi tek başına eylem başlatmaz (açık başlatma gerekir).
# ==============================================================================

.smoke_gate_app_env <- function() {
  # app.R'deki saf kapı yardımcıları uygulamayı başlatmadan değerlendirilir.
  exprs <- parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), "app.R"))
  env <- new.env(parent = globalenv())
  for (e in exprs) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        as.character(e[[2]]) %in% c("mergen_ux_smoke_enabled", "mergen_register_ux_smoke_resource",
                                    "safe_add_resource_path")) {
      eval(e, env)
    }
  }
  env
}

test_that("smoke harness www statik ağacında hiçbir adla bulunmaz", {
  root <- resolve_repo_root_for_tests()
  www_dosyalari <- list.files(file.path(root, "www"), recursive = TRUE, all.files = TRUE)
  # Büyük/küçük harf duyarsız: Windows/NTFS'te harf varyantı aynı dosyayı açar.
  expect_false(any(grepl("ux-smoke", www_dosyalari, ignore.case = TRUE)))
  expect_false(dir.exists(file.path(root, "www", "smoke")))
  expect_true(file.exists(file.path(root, "tests", "smoke", "ux-smoke.html")))
})

test_that("/smoke yolu yalnızca bakımcı kapısı açıkken kaydedilir", {
  env <- .smoke_gate_app_env()
  withr::local_dir(resolve_repo_root_for_tests())
  if ("smoke" %in% names(shiny::resourcePaths())) shiny::removeResourcePath("smoke")
  withr::defer(if ("smoke" %in% names(shiny::resourcePaths())) shiny::removeResourcePath("smoke"))

  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = NA)
  expect_false(env$mergen_ux_smoke_enabled())
  expect_false(isTRUE(env$mergen_register_ux_smoke_resource()))
  expect_false("smoke" %in% names(shiny::resourcePaths()))

  for (deger in c("false", "0", "", "hayir", "TRUE-ish")) {
    withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = deger)
    expect_false(env$mergen_ux_smoke_enabled(), info = deger)
  }

  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = "true")
  expect_true(isTRUE(env$mergen_register_ux_smoke_resource()))
  kayit <- shiny::resourcePaths()[["smoke"]]
  expect_identical(normalizePath(kayit, winslash = "/"),
                   normalizePath(file.path("tests", "smoke"), winslash = "/"))
  for (deger in c("TRUE", "1", "evet")) {
    withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = deger)
    expect_true(env$mergen_ux_smoke_enabled(), info = deger)
  }
})

test_that("app.R smoke kaydını yalnızca kapı yardımcısı üzerinden yapar", {
  app_txt <- paste(readLines(file.path(resolve_repo_root_for_tests(), "app.R"), encoding = "UTF-8", warn = FALSE),
                   collapse = "\n")
  expect_match(app_txt, "  mergen_register_ux_smoke_resource()\n", fixed = TRUE)
  expect_false(grepl("safe_add_resource_path(\"smoke\", \"", app_txt, fixed = TRUE))
})

test_that("smoke harness sayfa yüklemesiyle eylem başlatmaz", {
  node <- Sys.which("node")
  skip_if(!nzchar(node), "Node kullanılamıyor")
  script <- file.path(resolve_repo_root_for_tests(), "tests", "scripts", "ux_smoke_start_gate_regressions.js")
  sonuc <- system2(node, shQuote(script), stdout = TRUE, stderr = TRUE)
  expect_null(attr(sonuc, "status"), info = paste(sonuc, collapse = "\n"))
  expect_match(paste(sonuc, collapse = "\n"), "ux smoke start gate regressions passed")
})

test_that("otomatik tarayıcı koşucusu kapıyı açar ve açık başlatma ister", {
  oku <- function(yol) paste(readLines(file.path(resolve_repo_root_for_tests(), yol), encoding = "UTF-8",
                                       warn = FALSE), collapse = "\n")
  kosucu <- oku("tests/scripts/ai_browser_ux_smoke.R")
  expect_match(kosucu, "MERGEN_ENABLE_UX_SMOKE='true'", fixed = TRUE)
  expect_match(kosucu, "/smoke/ux-smoke.html?autostart=1", fixed = TRUE)
  expect_match(oku("tests/scripts/run_browser_concurrency_lane.R"), "/smoke/ux-smoke.html?autostart=1", fixed = TRUE)
})
