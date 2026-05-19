# ==============================================================================
# Dosya Yolu: tests/testthat/test-streaming-abort-lifecycle-smoke.R
# Açıklama: True streaming stop/cancel karar helper'ını saf şekilde doğrular.
# ==============================================================================

.find_stream_abort_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Streaming abort smoke repo kökünü bulamadı.", call. = FALSE)
}

repo_root_stream_abort <- .find_stream_abort_repo_root()

source(
  file.path(repo_root_stream_abort, "R", "utils_common.R"),
  encoding = "UTF-8",
  local = globalenv()
)

source(
  file.path(repo_root_stream_abort, "R", "helpers_streaming_abort_lifecycle.R"),
  encoding = "UTF-8",
  local = globalenv()
)

.identity_normalize <- function(x) {
  if (is.null(x)) return("")
  value <- as.character(x)[1]
  if (is.na(value)) "" else enc2utf8(value)
}

testthat::test_that("stream abort without partial removes placeholder and resets cleanly", {
  plan <- mergen_stream_abort_cleanup_plan(
    accumulated_text = "",
    result = list(aborted = TRUE, duration = 1.25),
    normalize_fn = .identity_normalize
  )

  testthat::expect_identical(plan$action, "remove_placeholder")
  testthat::expect_false(plan$track_error)
  testthat::expect_false(plan$show_toast)
  testthat::expect_identical(plan$final_text, "")
})

testthat::test_that("stream abort with partial finalizes partial once without error toast", {
  plan <- mergen_stream_abort_cleanup_plan(
    accumulated_text = enc2utf8("Kısmi yanıt"),
    result = list(aborted = TRUE, duration = 2.5),
    normalize_fn = .identity_normalize
  )

  testthat::expect_identical(plan$action, "finalize_partial")
  testthat::expect_identical(plan$final_text, enc2utf8("Kısmi yanıt"))
  testthat::expect_false(plan$track_error)
  testthat::expect_false(plan$show_toast)
  testthat::expect_false(plan$request_success)
})

testthat::test_that("stream non-abort error without partial shows error toast", {
  plan <- mergen_stream_abort_cleanup_plan(
    accumulated_text = "",
    result = list(
      aborted = FALSE,
      error = enc2utf8("Bağlantı kesildi"),
      duration = 3
    ),
    normalize_fn = .identity_normalize
  )

  testthat::expect_identical(plan$action, "remove_placeholder")
  testthat::expect_true(plan$track_error)
  testthat::expect_true(plan$show_toast)
  testthat::expect_identical(plan$toast_type, "error")
})

testthat::test_that("stream non-abort error with partial preserves partial and warns", {
  plan <- mergen_stream_abort_cleanup_plan(
    accumulated_text = enc2utf8("Yanıtın görünen kısmı"),
    result = list(
      aborted = FALSE,
      error = enc2utf8("Model bağlantısı kapandı"),
      duration = 4
    ),
    normalize_fn = .identity_normalize
  )

  testthat::expect_identical(plan$action, "finalize_partial")
  testthat::expect_identical(plan$toast_type, "warning")
  testthat::expect_true(plan$track_error)
})