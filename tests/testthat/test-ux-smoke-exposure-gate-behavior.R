# ==============================================================================
# Dosya Yolu: tests/testthat/test-ux-smoke-exposure-gate-behavior.R
# Açıklama: UX smoke harness'ı gerçek uygulama eylemleri tetikler; üretimde
#           kimliği doğrulanmamış bir eylem yüzeyi olmamalıdır.
#           - /smoke statik yolu yalnızca MERGEN_ENABLE_UX_SMOKE ile kaydedilir.
#           - Sayfa yüklemesi tek başına eylem başlatmaz (açık başlatma gerekir).
# ==============================================================================

.smoke_gate_app_env <- function() {
  # app.R'deki saf karar yardımcıları, uygulamayı başlatmadan değerlendirilir.
  exprs <- parse_r_file_utf8(file.path(resolve_repo_root_for_tests(), "app.R"))
  env <- new.env(parent = globalenv())
  for (e in exprs) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        as.character(e[[2]]) %in% c("mergen_ux_smoke_enabled", "mergen_static_resource_subdirs")) {
      eval(e, env)
    }
  }
  env
}

test_that("smoke statik yolu bakımcı kapısı olmadan kaydedilmez", {
  env <- .smoke_gate_app_env()
  alt <- c("css", "js", "smoke", "lib")

  withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = NA)
  expect_false(env$mergen_ux_smoke_enabled())
  expect_identical(env$mergen_static_resource_subdirs(alt), c("css", "js", "lib"))

  for (deger in c("false", "0", "", "hayir", "TRUE-ish")) {
    withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = deger)
    expect_false(env$mergen_ux_smoke_enabled(), info = deger)
  }
  for (deger in c("true", "TRUE", "1", "evet")) {
    withr::local_envvar(MERGEN_ENABLE_UX_SMOKE = deger)
    expect_true(env$mergen_ux_smoke_enabled(), info = deger)
    expect_identical(env$mergen_static_resource_subdirs(alt), alt)
  }
})

test_that("app.R statik kaynak döngüsü kapı yardımcısından geçer", {
  app_txt <- paste(readLines(file.path(resolve_repo_root_for_tests(), "app.R"), encoding = "UTF-8", warn = FALSE),
                   collapse = "\n")
  expect_match(app_txt, "for (subdir in mergen_static_resource_subdirs(list.dirs(\"www\"", fixed = TRUE)
  expect_false(grepl("for (subdir in list.dirs(\"www\"", app_txt, fixed = TRUE))
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
