testthat::local_edition(3)

load_prod_log_mojibake_detector <- function() {
  expressions <- parse(
    file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R"),
    encoding = "UTF-8"
  )
  is_detector <- vapply(expressions, function(expr) {
    is.call(expr) &&
      length(expr) >= 3L &&
      identical(expr[[1]], as.name("<-")) &&
      identical(expr[[2]], as.name("mergen_log_dir_has_mojibake"))
  }, logical(1))

  expect_equal(sum(is_detector), 1L)
  env <- new.env(parent = baseenv())
  eval(expressions[[which(is_detector)]], envir = env)
  env$mergen_log_dir_has_mojibake
}

test_that("mojibake denetimi yalnızca bilinen Türkçe bozulma çiftlerini yakalar", {
  detector <- load_prod_log_mojibake_detector()

  expect_true(detector("//server/Geli\u00C5\u0178tirme/MERGEN Bilge/logs"))
  expect_true(detector("//server/Geli\u00C5\u009Ftirme/MERGEN Bilge/logs"))
  expect_false(detector("//server/\u00C5rsrapporter/logs"))
  expect_false(detector("//server/\u00C3rea/logs"))
  expect_false(detector("//server/MERGEN Bilge/logs"))
})

test_that("üretim başlatıcısı bozuk log yolunu app kaynaklanmadan önce düzeltir", {
  script <- readLines(
    file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )
  code <- paste(script, collapse = "\n")

  expect_match(
    code,
    "mergen_log_dir_has_mojibake(configured_log_dir)",
    fixed = TRUE
  )
  expect_match(code, "shortPathName(local_log_dir)", fixed = TRUE)
  expect_match(code, "Sys.setenv(MERGEN_LOG_DIR = local_log_dir)", fixed = TRUE)

  repair_line <- grep(
    "Sys.setenv(MERGEN_LOG_DIR = local_log_dir)",
    script,
    fixed = TRUE
  )
  app_source_line <- grep('source("app.R"', script, fixed = TRUE)

  expect_length(repair_line, 1L)
  expect_length(app_source_line, 1L)
  expect_lt(repair_line, app_source_line)
})
