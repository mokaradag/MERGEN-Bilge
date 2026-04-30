# ==============================================================================
# Dosya Yolu: tests/testthat/test-maintainability-ratchet.R
# Açıklama: Maintainability skorunun ve büyük dosya sayaçlarının mevcut
#           üretim taban çizgisinin altına düşmesini engeller.
# ==============================================================================

.find_repo_root_maint_ratchet <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.as_int_env <- function(name, default) {
  raw <- Sys.getenv(name, as.character(default))
  value <- suppressWarnings(as.integer(raw))

  if (is.na(value)) {
    stop(sprintf("%s geçersiz: %s", name, raw), call. = FALSE)
  }

  value
}

test_that("maintainability skoru mevcut taban çizgisinin altına düşmez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  score <- attr(report, "maintainability_score", exact = TRUE)

  expect_true(
    is.numeric(score) || is.integer(score),
    info = "maintainability_report.R attr(..., 'maintainability_score') üretmelidir."
  )

  min_score <- .as_int_env("MERGEN_TEST_MIN_MAINTAINABILITY_SCORE", 38L)

  expect_true(
    score >= min_score,
    info = sprintf(
      "Maintainability skoru geriledi: %s/100 < minimum %s/100.",
      score,
      min_score
    )
  )
})

test_that("büyük dosya ve fonksiyon sayaçları mevcut taban çizgisinden kötüye gitmez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  score_report <- attr(report, "score_report", exact = TRUE)

  expect_true(
    is.data.frame(score_report),
    info = "maintainability_report.R attr(..., 'score_report') üretmelidir."
  )

  max_large_files <- .as_int_env("MERGEN_TEST_MAX_800_LINE_FILES", 14L)
  max_function_heavy_files <- .as_int_env("MERGEN_TEST_MAX_25_FUNCTION_FILES", 10L)
  max_very_large_files <- .as_int_env("MERGEN_TEST_MAX_1500_LINE_FILES", 0L)
  max_file_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_LINES", 1294L)
  max_file_functions <- .as_int_env("MERGEN_TEST_MAX_FILE_FUNCTIONS", 45L)

  actual_large_files <- sum(score_report$lines >= 800)
  actual_function_heavy_files <- sum(score_report$functions >= 25)
  actual_very_large_files <- sum(score_report$lines >= 1500)
  actual_max_lines <- max(score_report$lines, na.rm = TRUE)
  actual_max_functions <- max(score_report$functions, na.rm = TRUE)

  expect_true(
    actual_large_files <= max_large_files,
    info = sprintf(
      "800+ satır dosya sayısı arttı: %d > %d.",
      actual_large_files,
      max_large_files
    )
  )

  expect_true(
    actual_function_heavy_files <= max_function_heavy_files,
    info = sprintf(
      "25+ fonksiyon dosya sayısı arttı: %d > %d.",
      actual_function_heavy_files,
      max_function_heavy_files
    )
  )

  expect_true(
    actual_very_large_files <= max_very_large_files,
    info = sprintf(
      "1500+ satır dosya sayısı arttı: %d > %d.",
      actual_very_large_files,
      max_very_large_files
    )
  )

  expect_true(
    actual_max_lines <= max_file_lines,
    info = sprintf(
      "En büyük dosya satırı arttı: %d > %d.",
      actual_max_lines,
      max_file_lines
    )
  )

  expect_true(
    actual_max_functions <= max_file_functions,
    info = sprintf(
      "En yüksek fonksiyon sayısı arttı: %d > %d.",
      actual_max_functions,
      max_file_functions
    )
  )
})