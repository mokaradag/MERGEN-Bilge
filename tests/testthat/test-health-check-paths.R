# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-check-paths.R
# Açıklama: Sistem Durumu dosya yolu ve index JSON kontrollerini test eder.
# ==============================================================================

.bootstrap_health_path_tests <- function() {
  helper_candidates <- c("tests/testthat/helper_bootstrap.R", "testthat/helper_bootstrap.R", "helper_bootstrap.R")
  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) source(helper_path, encoding = "UTF-8", local = globalenv())
  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() normalizePath(if (file.exists("app.R")) "." else "../..", winslash = "/", mustWork = TRUE)
  }
  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_files_path.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_health_checks.R"), encoding = "UTF-8", local = globalenv())
}

.bootstrap_health_path_tests()

test_that("geçici klasör yazılabilir olarak raporlanır", {
  tmp <- tempdir()
  res <- health_check_path_writable("tmp.write", "Temp Yazma", tmp)
  expect_identical(res$status[1], "ok")
  expect_true(all(c("id", "label", "status", "severity", "value", "detail", "duration_ms", "checked_at", "remediation") %in% names(res)))
})

test_that("eksik klasör kritik olarak raporlanır", {
  missing <- file.path(tempdir(), paste0("missing-", as.integer(Sys.time())))
  if (dir.exists(missing)) unlink(missing, recursive = TRUE, force = TRUE)
  res <- health_check_path_writable("missing.write", "Eksik Klasör", missing)
  expect_identical(res$status[1], "critical")
})

test_that("index JSON üst klasöründe okuma yazma kontrolü güvenli çalışır", {
  tmp <- tempfile("index-root-")
  dir.create(tmp, recursive = TRUE)
  idx <- file.path(tmp, "index.json")
  writeLines("{}", idx, useBytes = TRUE)
  res <- health_check_index_json(idx)
  expect_identical(res$status[1], "ok")
  expect_false(file.exists(file.path(tmp, ".index-health-should-not-exist.json")))
})

test_that("henüz oluşmamış index JSON yazılabilir üst klasörde kritik değildir", {
  tmp <- tempfile("index-lazy-root-")
  dir.create(tmp, recursive = TRUE)
  idx <- file.path(tmp, "index.json")

  res <- health_check_index_json(idx)

  expect_identical(res$status[1], "ok")
  expect_match(res$detail[1], "henüz oluşturulmamış", fixed = TRUE)
  expect_false(file.exists(idx))
})

test_that("boş index yolu tanımlı değil olarak döner", {
  res <- health_check_index_json("")
  expect_identical(res$status[1], "not_configured")
})
