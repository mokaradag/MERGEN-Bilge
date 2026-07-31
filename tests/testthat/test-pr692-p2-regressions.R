# ==============================================================================
# Dosya Yolu: tests/testthat/test-pr692-p2-regressions.R
# Açıklama: PR #692 için Codex tarafından bildirilen dört P2 gerilemesini
#           doğrudan sözleşme düzeyinde doğrular.
# ==============================================================================

.find_repo_root_pr692 <- function() {
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
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

repo_root_pr692 <- .find_repo_root_pr692()

.read_pr692 <- function(...) {
  paste(readLines(
    file.path(repo_root_pr692, ...),
    warn = FALSE,
    encoding = "UTF-8"
  ), collapse = "\n")
}

test_that("Selectize açıkken yapılandırma ipucu bastırılır", {
  css <- .read_pr692("www", "css", "settings_page.css")

  expect_true(grepl(
    ":has\\(\\.selectize-input\\.dropdown-active\\)::after",
    css,
    perl = TRUE
  ))
  expect_false(grepl(
    ":has\\(\\.selectize-control\\.dropdown-active\\)::after",
    css,
    perl = TRUE
  ))
})

test_that("mesaj güvenlik tavanı tamsayı taşmasında varsayılana düşer", {
  validation_env <- new.env(parent = baseenv())
  sys.source(
    file.path(repo_root_pr692, "R", "helpers_db_validation.R"),
    envir = validation_env,
    encoding = "UTF-8"
  )

  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "3000000000"), {
    expect_identical(validation_env$mergen_max_message_chars(), 1000000L)
    expect_true(validation_env$validate_message_content("geçerli ileti"))
  })

  withr::with_envvar(c(MERGEN_MAX_MESSAGE_CHARS = "Inf"), {
    expect_identical(validation_env$mergen_max_message_chars(), 1000000L)
  })
})

test_that("MCP ikinci geçişi çıktı token ortam ayarını uygular", {
  second_pass_env <- new.env(parent = baseenv())
  sys.source(
    file.path(repo_root_pr692, "R", "helpers_llm_worker_second_pass.R"),
    envir = second_pass_env,
    encoding = "UTF-8"
  )

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "12000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(list()),
      12000L
    )
  })

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "12000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(
        list(max_output_tokens = 9000L)
      ),
      9000L
    )
  })

  withr::with_envvar(c(MERGEN_MAX_OUTPUT_TOKENS = "3000000000"), {
    expect_identical(
      second_pass_env$llm_worker_resolve_max_output_tokens(list()),
      32768L
    )
  })
})

test_that("yerel CodeMirror yapısı yönetici API'sini ve tam çizimi sağlar", {
  core_js <- .read_pr692("www", "codemirror", "codemirror.min.js")
  manager_js <- .read_pr692("www", "js", "codemirror-manager.js")
  core_css <- .read_pr692("www", "codemirror", "codemirror.min.css")

  expect_false(grepl("extension placeholder", core_js, fixed = TRUE))
  expect_true(grepl("OfflineCodeMirror.prototype.on", core_js, fixed = TRUE))
  expect_true(grepl("OfflineCodeMirror.prototype.setSize", core_js, fixed = TRUE))
  expect_true(grepl("OfflineCodeMirror.prototype.refresh", core_js, fixed = TRUE))
  expect_true(grepl("this._wrapper.CodeMirror = this", core_js, fixed = TRUE))
  expect_true(grepl("this._code.appendChild(row)", core_js, fixed = TRUE))
  expect_true(grepl("viewportMargin: Infinity", manager_js, fixed = TRUE))
  expect_true(grepl(".CodeMirror-line-row", core_css, fixed = TRUE))
})
