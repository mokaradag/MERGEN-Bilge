# ==============================================================================
# Dosya Yolu: tests/testthat/test-frontend-complexity-doctor-contract.R
# Açıklama: Frontend complexity doctor çıktısını, artifact sözleşmesini ve
#           smoke-only/runtime manifest ayrımını korur.
# ==============================================================================

.frontend_complexity_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts")) &&
        dir.exists(file.path(candidate, "www"))) {
      return(candidate)
    }
  }

  stop("Frontend complexity doctor contract repo kökü bulunamadı.", call. = FALSE)
}

.frontend_complexity_is_absolute_path <- function(path) {
  grepl("^([A-Za-z]:|/|\\\\\\\\)", as.character(path)[1])
}

.frontend_complexity_read_text <- function(...) {
  parts <- c(...)
  path <- if (length(parts) == 1L &&
              .frontend_complexity_is_absolute_path(parts[[1]])) {
    parts[[1]]
  } else {
    file.path(.frontend_complexity_repo_root(), ...)
  }

  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

.frontend_complexity_expect_all <- function(text, tokens, label) {
  missing <- tokens[!vapply(
    tokens,
    function(token) grepl(token, text, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing,
    character(0),
    info = paste(label, paste(missing, collapse = ", "))
  )
}

testthat::test_that("frontend complexity doctor script and report expose top-risk sections", {
  doctor <- .frontend_complexity_read_text("tests", "scripts", "frontend_complexity_doctor.R")
  report <- .frontend_complexity_read_text("tests", "scripts", "frontend_maintainability_report.R")

  .frontend_complexity_expect_all(
    doctor,
    c(
      "Dosya Yolu: tests/scripts/frontend_complexity_doctor.R",
      "frontend_maintainability_report.R",
      "top_risk_summary",
      "largest_js",
      "largest_css",
      "highest_function_js",
      "highest_event_handler_js",
      "highest_shiny_handler_js",
      "duplicate_css_selectors",
      "unmanifested_app_assets",
      "allowlisted_unmanifested_assets",
      "smoke_only_assets",
      "doctor_runs_runtime",
      "value=<not-collected>",
      "Frontend complexity artifact:"
    ),
    "Frontend complexity doctor sözleşme tokenları eksik:"
  )

  .frontend_complexity_expect_all(
    report,
    c(
      "build_frontend_top_risk_summary",
      "Frontend top-risk summary",
      "largest_js",
      "largest_css",
      "highest_function_js",
      "highest_event_handler_js",
      "highest_shiny_handler_js",
      "duplicate_css_selectors",
      "legacy_selector_hits",
      "unmanifested_app_assets",
      "allowlisted_unmanifested_assets",
      "smoke_only_assets",
      "www/smoke/ux-smoke-probes.js",
      "attr(report, \"top_risk_summary\")"
    ),
    "Frontend maintainability report top-risk sözleşmesi eksik:"
  )
})

testthat::test_that("frontend complexity doctor writes UTF-8 top-risk JSON artifact without secrets", {
  rscript <- Sys.which("Rscript")
  testthat::skip_if_not(nzchar(rscript))

  repo_root <- .frontend_complexity_repo_root()
  artifact_root <- tempfile("frontend-complexity-doctor-contract-")
  dir.create(artifact_root, recursive = TRUE, showWarnings = FALSE)

  secret_values <- c(
    "fake_master_key_abcdefghijklmnopqrstuvwxyz",
    "fake_db_password_abcdefghijklmnopqrstuvwxyz",
    "fake_sso_secret_abcdefghijklmnopqrstuvwxyz",
    "https://llm.example.invalid/v1/fake-sensitive-endpoint"
  )

  secret_env <- c(
    AI_KEYS_MASTER = secret_values[[1]],
    DB_PASSWORD = secret_values[[2]],
    SSO_CLIENT_SECRET = secret_values[[3]],
    LOCAL_LLM_ENDPOINT = secret_values[[4]]
  )

  output <- withr::with_dir(
    repo_root,
    withr::with_envvar(
      secret_env,
      system2(
        rscript,
        c(
          "tests/scripts/frontend_complexity_doctor.R",
          "--artifact-root",
          artifact_root
        ),
        stdout = TRUE,
        stderr = TRUE
      )
    )
  )

  status <- attr(output, "status", exact = TRUE)
  testthat::expect_true(is.null(status) || identical(as.integer(status), 0L))

  artifact_files <- list.files(
    artifact_root,
    pattern = "^frontend-complexity-doctor-.*\\.json$",
    full.names = TRUE
  )

  testthat::expect_length(artifact_files, 1L)

  artifact_text <- .frontend_complexity_read_text(artifact_files[[1]])
  combined <- paste(c(output, artifact_text), collapse = "\n")

  leaked <- secret_values[vapply(
    secret_values,
    function(value) grepl(value, combined, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    leaked,
    character(0),
    info = paste("Frontend complexity doctor raw secret/env value sızdırdı:", paste(leaked, collapse = ", "))
  )

  .frontend_complexity_expect_all(
    combined,
    c(
      "Frontend top-risk summary",
      "\"top_risk\"",
      "\"largest_js\"",
      "\"largest_css\"",
      "\"highest_function_js\"",
      "\"highest_event_handler_js\"",
      "\"highest_shiny_handler_js\"",
      "\"duplicate_css_selectors\"",
      "\"unmanifested_app_assets\"",
      "\"allowlisted_unmanifested_assets\"",
      "\"smoke_only_assets\"",
      "\"www/smoke/ux-smoke-probes.js\"",
      "\"manifest_listed\":false",
      "\"doctor_runs_runtime\":false",
      "\"doctor_runs_browser\":false",
      "\"doctor_runs_database\":false",
      "value=<not-collected>",
      "Frontend complexity artifact:"
    ),
    "Frontend complexity doctor çıktı/artifact top-risk alanları eksik:"
  )
})

testthat::test_that("frontend maintainability report returns top-risk summary data", {
  repo_root <- .frontend_complexity_repo_root()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  report_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/frontend_maintainability_report.R",
    encoding = "UTF-8",
    local = report_env
  )$value

  top_risk_summary <- attr(report, "top_risk_summary", exact = TRUE)

  required_sections <- c(
    "largest_js",
    "largest_css",
    "highest_function_js",
    "highest_event_handler_js",
    "highest_shiny_handler_js",
    "duplicate_css_selectors",
    "legacy_selector_hits",
    "unmanifested_app_assets",
    "allowlisted_unmanifested_assets",
    "smoke_only_assets"
  )

  testthat::expect_true(is.list(top_risk_summary))
  testthat::expect_equal(setdiff(required_sections, names(top_risk_summary)), character(0))

  invisible(lapply(required_sections, function(section) {
    testthat::expect_true(
      is.data.frame(top_risk_summary[[section]]),
      info = sprintf("top_risk_summary$%s data.frame olmalıdır.", section)
    )
  }))

  smoke_assets <- top_risk_summary$smoke_only_assets

  probe_row <- smoke_assets[
    smoke_assets$file == "www/smoke/ux-smoke-probes.js",
    ,
    drop = FALSE
  ]

  testthat::expect_equal(nrow(probe_row), 1L)
  testthat::expect_true(probe_row$exists[[1]])
  testthat::expect_false(probe_row$manifest_listed[[1]])
  testthat::expect_equal(probe_row$budget_scope[[1]], "smoke_only")
})