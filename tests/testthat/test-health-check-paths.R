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
  expect_warning(
    res <- health_check_path_writable("missing.write", "Eksik Klasör", missing),
    regexp = NA
  )
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

test_that("UNC varlık sorguları yanlış negatif olsa da gerçek yazma kanıttır", {
  tmp <- tempfile("unc-health-probe-")
  dir.create(tmp, recursive = TRUE)
  idx <- file.path(tmp, "index.json")

  had_dir_exists <- exists("dir.exists", envir = .GlobalEnv, inherits = FALSE)
  old_dir_exists <- if (had_dir_exists) get("dir.exists", envir = .GlobalEnv, inherits = FALSE) else NULL
  had_relaxed <- exists("path_exists_relaxed", envir = .GlobalEnv, inherits = FALSE)
  old_relaxed <- if (had_relaxed) get("path_exists_relaxed", envir = .GlobalEnv, inherits = FALSE) else NULL

  withr::defer({
    if (had_dir_exists) assign("dir.exists", old_dir_exists, envir = .GlobalEnv)
    else if (exists("dir.exists", envir = .GlobalEnv, inherits = FALSE)) rm(list = "dir.exists", envir = .GlobalEnv)

    if (had_relaxed) assign("path_exists_relaxed", old_relaxed, envir = .GlobalEnv)
    else if (exists("path_exists_relaxed", envir = .GlobalEnv, inherits = FALSE)) rm(list = "path_exists_relaxed", envir = .GlobalEnv)
  })

  assign("dir.exists", function(...) FALSE, envir = .GlobalEnv)
  assign("path_exists_relaxed", function(...) FALSE, envir = .GlobalEnv)

  root_res <- health_check_path_writable("unc.write", "UNC Yazma", tmp)
  index_res <- health_check_index_json(idx)

  expect_identical(root_res$status[1], "ok")
  expect_identical(index_res$status[1], "ok")
  expect_false(file.exists(idx))
})

test_that("index kontrolü ham ortam değeri yerine kanonik runtime yolunu kullanır", {
  tmp <- tempfile("index-runtime-root-")
  dir.create(tmp, recursive = TRUE)
  idx <- file.path(tmp, "index.json")
  invalid_idx <- file.path(tmp, "missing-parent", "index.json")

  old_option <- options(mergen.index_path = idx)
  old_env <- Sys.getenv("MERGEN_INDEX_PATH", unset = NA_character_)
  withr::defer({
    options(old_option)
    if (is.na(old_env)) Sys.unsetenv("MERGEN_INDEX_PATH") else Sys.setenv(MERGEN_INDEX_PATH = old_env)
  })
  Sys.setenv(MERGEN_INDEX_PATH = invalid_idx)

  res <- health_check_index_json()

  expect_identical(res$status[1], "ok")
  expect_identical(res$value[1], idx)
})

test_that("boş index yolu tanımlı değil olarak döner", {
  res <- health_check_index_json("")
  expect_identical(res$status[1], "not_configured")
})
