# ==============================================================================
# Dosya Yolu: tests/testthat/test-release-candidate-gate-contract.R
# Açıklama: Release candidate kapısının hardening gate + maintainability score
#           kontrolünü içerdiğini doğrular. Script'i çalıştırmaz; sözleşmeyi
#           kaynak kod üzerinden denetler.
# ==============================================================================

.read_repo_text_rc_gate <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(abs_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("release candidate gate exists and composes hardening + maintainability checks", {
  script_path <- file.path(
    repo_root_for_tests,
    "tests",
    "scripts",
    "run_release_candidate_gate.R"
  )

  expect_true(
    file.exists(script_path),
    info = "tests/scripts/run_release_candidate_gate.R eklenmelidir."
  )

  txt <- .read_repo_text_rc_gate("tests/scripts/run_release_candidate_gate.R")

  expect_true(
    grepl("run_hardening_gate_local.R", txt, fixed = TRUE),
    info = "Release candidate gate önce hardening gate'i çalıştırmalıdır."
  )

  expect_true(
    grepl("maintainability_report.R", txt, fixed = TRUE),
    info = "Release candidate gate maintainability_report.R skorunu okumalıdır."
  )

  expect_true(
    grepl("MERGEN_MIN_MAINTAINABILITY_SCORE", txt, fixed = TRUE),
    info = "Minimum skor ortam değişkeniyle yönetilebilir olmalıdır."
  )

  expect_true(
    grepl("maintainability_score", txt, fixed = TRUE),
    info = "Script attr(..., 'maintainability_score') sözleşmesini kullanmalıdır."
  )
})