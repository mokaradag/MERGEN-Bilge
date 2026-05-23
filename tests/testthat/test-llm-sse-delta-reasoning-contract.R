# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-sse-delta-reasoning-contract.R
# Açıklama: SSE delta ayrıştırıcısının reasoning alanlarını yakaladığını ve
# atomic vector içeren uç yanıtlarında çökmediğini doğrular.
# ==============================================================================

.bootstrap_llm_sse_delta_contract <- function() {
  helper_candidates <- c(
    "tests/testthat/helper_bootstrap.R",
    "testthat/helper_bootstrap.R",
    "helper_bootstrap.R"
  )

  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) {
    source(helper_path, encoding = "UTF-8", local = globalenv())
  }

  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() {
      candidates <- c(".", "..", "../..")
      for (cand in candidates) {
        if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
          return(normalizePath(cand, winslash = "/", mustWork = TRUE))
        }
      }
      stop("Repo kökü bulunamadı. Test çalışma dizinini kontrol edin.", call. = FALSE)
    }
  }

  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(x, y) if (is.null(x)) y else x
  }

  if (!exists("log_info", mode = "function", inherits = TRUE)) {
    log_info <<- function(...) invisible(NULL)
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn <<- function(...) invisible(NULL)
  }
  if (!exists("log_debug", mode = "function", inherits = TRUE)) {
    log_debug <<- function(...) invisible(NULL)
  }

  source(file.path(repo_root, "R", "helpers_llm_response_postprocess.R"),
         encoding = "UTF-8", local = globalenv())

  # SSE olay/delta ayrıştırma yardımcıları ayrı dosyaya alındı; izole testte
  # önce yüklenmesi gerekir, aksi halde extract_llm_delta_bundle bulunamaz.
  source(file.path(repo_root, "R", "helpers_llm_sse_events.R"),
         encoding = "UTF-8", local = globalenv())

  source(file.path(repo_root, "R", "helpers_llm_sse.R"),
         encoding = "UTF-8", local = globalenv())

  invisible(TRUE)
}

.bootstrap_llm_sse_delta_contract()

test_that("extract_llm_delta_bundle standart content deltasını ayrıştırır", {
  event <- list(
    id = "evt-1",
    object = "chat.completion.chunk",
    choices = list(
      list(
        delta = list(
          content = "Merhaba"
        )
      )
    )
  )

  out <- extract_llm_delta_bundle(event)

  expect_identical(out$content, "Merhaba")
  expect_identical(out$reasoning, "")
})

test_that("extract_llm_delta_bundle Kimi tarzı reasoning deltasını ayrıştırır", {
  event <- list(
    id = "evt-2",
    object = "chat.completion.chunk",
    choices = list(
      list(
        delta = list(
          reasoning = "Önce problemi anlıyorum."
        )
      )
    )
  )

  out <- extract_llm_delta_bundle(event)

  expect_identical(out$content, "")
  expect_identical(out$reasoning, "Önce problemi anlıyorum.")
})

test_that("extract_llm_delta_bundle reasoning_content alanını ayrıştırır", {
  event <- list(
    choices = list(
      list(
        delta = list(
          reasoning_content = "Bu ayrı reasoning kanalından geldi.",
          content = ""
        )
      )
    )
  )

  out <- extract_llm_delta_bundle(event)

  expect_identical(out$content, "")
  expect_identical(out$reasoning, "Bu ayrı reasoning kanalından geldi.")
})

test_that("extract_llm_delta_bundle atomic delta/message yapılarında çökmez", {
  event <- list(
    id = "evt-atomic",
    choices = list(
      list(
        delta = "atomic-delta",
        message = "atomic-message"
      )
    )
  )

  out <- NULL

  expect_error(
    out <- extract_llm_delta_bundle(event),
    NA
  )

  expect_true(is.list(out))
  expect_true("content" %in% names(out))
  expect_true("reasoning" %in% names(out))
})