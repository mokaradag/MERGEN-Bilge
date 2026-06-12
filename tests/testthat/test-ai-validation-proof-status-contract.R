# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-validation-proof-status-contract.R
# Açıklama: AI doğrulama summary.json kanıt sınırlarının makinece okunabilir,
#           secret-safe ve overclaim yakalamaya uygun kalmasını korur.
# ==============================================================================

.ai_validation_proof_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts")) &&
        dir.exists(file.path(candidate, "tools"))) {
      return(candidate)
    }
  }

  stop("AI validation proof-status contract repo kökü bulunamadı.", call. = FALSE)
}

.ai_validation_proof_read_text <- function(path) {
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

.ai_validation_proof_expect_all <- function(text, tokens, label) {
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

.ai_validation_proof_step <- function(label,
                                      status = 0L,
                                      skipped = FALSE,
                                      log_text = "OK") {
  log_path <- tempfile("ai-validation-proof-step-", fileext = ".log")
  writeLines(enc2utf8(log_text), log_path, useBytes = TRUE)

  list(
    label = label,
    status = as.integer(status),
    duration_seconds = 0.01,
    log = log_path,
    skipped = isTRUE(skipped)
  )
}

testthat::test_that("summary JSON contains machine-readable proof fields", {
  repo_root <- .ai_validation_proof_repo_root()
  source(
    file.path(repo_root, "tests", "scripts", "helpers_validation_proof_status.R"),
    encoding = "UTF-8"
  )

  secret_values <- c(
    "fake_master_key_for_proof_contract_abcdefghijklmnopqrstuvwxyz",
    "Server=tcp;Uid=fake_user;Pwd=fake_pwd_for_proof_contract_abcdefghijklmnopqrstuvwxyz",
    "https://llm.example.invalid/v1/fake-sensitive-proof-endpoint"
  )

  steps <- list(
    .ai_validation_proof_step("environment"),
    .ai_validation_proof_step("parse sanity"),
    .ai_validation_proof_step(
      "app source smoke",
      skipped = TRUE,
      log_text = "SKIPPED\nReason: MERGEN_AI_SKIP_APP_SOURCE_SMOKE=true"
    ),
    .ai_validation_proof_step("focused contract tests")
  )

	json <- withr::with_envvar(
	  c(
		MERGEN_AI_REQUESTED_PROFILE = "cloud-quick",
		MERGEN_AI_EFFECTIVE_PROFILE = "quick",
		MERGEN_REQUIRE_BROWSER_UX_SMOKE = "false",
		MERGEN_BROWSER_UX_BASE_URL = "",
		AI_KEYS_MASTER = secret_values[[1]],
		DB_DSN = secret_values[[2]],
		LOCAL_LLM_ENDPOINT = secret_values[[3]]
	  ),
	  validation_proof_render_ai_summary(
		profile = "quick",
		repo_root = repo_root,
		artifact_root = tempfile("ai-validation-proof-artifact-"),
		steps = steps,
		boot_smoke = FALSE,
		skip_app_source_smoke = TRUE,
		answer_path = NULL
	  )
	)

  .ai_validation_proof_expect_all(
    json,
    c(
      "\"validation_execution_status\":\"ran_by_ai_repo_check\"",
      "\"profile_requested\":\"cloud-quick\"",
      "\"profile_effective\":\"quick\"",
      "\"timestamp\"",
      "\"git_available\"",
      "\"current_branch\"",
      "\"current_commit_sha\"",
      "\"dirty_working_tree_status\"",
      "\"focused_contract_tests_status\":\"passed\"",
      "\"full_testthat_suite_status\":\"not_requested\"",
      "\"cloud_quick_validation_status\":\"passed\"",
      "\"quick_repo_validation_status\":\"not_requested\"",
      "\"full_validation_status\":\"not_requested\"",
      "\"app_source_smoke_status\":\"skipped\"",
      "\"shiny_boot_smoke_status\":\"not_requested\"",
      "\"app_boot_smoke_status\":\"not_requested\"",
      "\"browser_smoke_status\":\"not_requested\"",
      "\"browser_ux_smoke_status\":\"not_requested\"",
      "\"browser_required\":false",
      "\"db_sso_vm_validation_performed\":false",
      "\"db_sso_vm_validation_status\":\"not_performed_by_ai_validate\"",
      "\"vm_sso_preflight_status\":\"not_performed_by_ai_validate\"",
      "\"sql_server_turkish_encoding_preflight_status\":\"not_performed_by_ai_validate\"",
      "\"sql_server_turkish_encoding_validation_status\":\"not_performed_by_ai_validate\"",
      "\"manual_fragile_flow_evidence_status\":\"not_performed_by_ai_validate\"",
      "\"manual_fragile_flow_validation_status\":\"not_performed_by_ai_validate\"",
      "\"failed_step_labels\"",
      "\"skipped_step_labels\"",
      "\"proof_boundary_notes\""
    ),
    "AI validation summary proof alanları eksik:"
  )

  leaked <- secret_values[vapply(
    secret_values,
    function(value) grepl(value, json, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    leaked,
    character(0),
    info = paste("AI validation summary raw secret/env değeri sızdırdı:", paste(leaked, collapse = ", "))
  )
})

testthat::test_that("cloud-quick, quick and full boot boundaries are represented correctly", {
  repo_root <- .ai_validation_proof_repo_root()
  source(
    file.path(repo_root, "tests", "scripts", "helpers_validation_proof_status.R"),
    encoding = "UTF-8"
  )

  cloud_steps <- list(
    .ai_validation_proof_step("environment"),
    .ai_validation_proof_step("parse sanity"),
    .ai_validation_proof_step("app source smoke", skipped = TRUE),
    .ai_validation_proof_step("focused contract tests")
  )

  cloud_proof <- withr::with_envvar(
    c(
      MERGEN_AI_REQUESTED_PROFILE = "cloud-quick",
      MERGEN_AI_EFFECTIVE_PROFILE = "quick",
      MERGEN_REQUIRE_BROWSER_UX_SMOKE = "false"
    ),
    validation_proof_status(
      profile = "quick",
      repo_root = repo_root,
      steps = cloud_steps,
      boot_smoke = FALSE,
      skip_app_source_smoke = TRUE
    )
  )

  testthat::expect_equal(cloud_proof$profile_requested, "cloud-quick")
  testthat::expect_equal(cloud_proof$profile_effective, "quick")
  testthat::expect_equal(cloud_proof$app_source_smoke_status, "skipped")
  testthat::expect_equal(cloud_proof$browser_smoke_status, "not_requested")
  testthat::expect_false(cloud_proof$db_sso_vm_validation_performed)
  testthat::expect_equal(cloud_proof$focused_contract_tests_status, "passed")
  testthat::expect_equal(cloud_proof$cloud_quick_validation_status, "passed")
  testthat::expect_equal(cloud_proof$quick_repo_validation_status, "not_requested")
  testthat::expect_equal(cloud_proof$full_validation_status, "not_requested")

  quick_steps <- list(
    .ai_validation_proof_step("environment"),
    .ai_validation_proof_step("parse sanity"),
    .ai_validation_proof_step("app source smoke"),
    .ai_validation_proof_step("focused contract tests")
  )

  quick_proof <- withr::with_envvar(
    c(
      MERGEN_AI_REQUESTED_PROFILE = "quick",
      MERGEN_AI_EFFECTIVE_PROFILE = "quick",
      MERGEN_REQUIRE_BROWSER_UX_SMOKE = "false"
    ),
    validation_proof_status(
      profile = "quick",
      repo_root = repo_root,
      steps = quick_steps,
      boot_smoke = FALSE,
      skip_app_source_smoke = FALSE
    )
  )

  testthat::expect_equal(quick_proof$app_source_smoke_status, "passed")
  testthat::expect_equal(quick_proof$shiny_boot_smoke_status, "not_requested")
  testthat::expect_equal(quick_proof$browser_smoke_status, "not_requested")
  testthat::expect_equal(quick_proof$focused_contract_tests_status, "passed")
  testthat::expect_equal(quick_proof$cloud_quick_validation_status, "not_requested")
  testthat::expect_equal(quick_proof$quick_repo_validation_status, "passed")
  testthat::expect_equal(quick_proof$full_validation_status, "not_requested")

  full_steps <- list(
    .ai_validation_proof_step("environment"),
    .ai_validation_proof_step("parse sanity"),
    .ai_validation_proof_step("app source smoke"),
    .ai_validation_proof_step("full testthat suite"),
    .ai_validation_proof_step("shiny boot smoke"),
    .ai_validation_proof_step(
      "browser UX smoke",
      log_text = "OK: UX_SMOKE_DONE:PASS found in headless browser DOM output."
    )
  )

  full_proof <- withr::with_envvar(
    c(
      MERGEN_AI_REQUESTED_PROFILE = "full",
      MERGEN_AI_EFFECTIVE_PROFILE = "full",
      MERGEN_REQUIRE_BROWSER_UX_SMOKE = "true"
    ),
    validation_proof_status(
      profile = "full",
      repo_root = repo_root,
      steps = full_steps,
      boot_smoke = TRUE,
      skip_app_source_smoke = FALSE
    )
  )

  testthat::expect_equal(full_proof$profile_effective, "full")
  testthat::expect_equal(full_proof$shiny_boot_smoke_status, "passed")
  testthat::expect_equal(full_proof$browser_smoke_status, "passed")
  testthat::expect_true(full_proof$browser_required)
  testthat::expect_equal(full_proof$full_testthat_suite_status, "passed")
  testthat::expect_equal(full_proof$cloud_quick_validation_status, "not_requested")
  testthat::expect_equal(full_proof$quick_repo_validation_status, "not_requested")
  testthat::expect_equal(full_proof$full_validation_status, "passed")
  testthat::expect_equal(full_proof$app_boot_smoke_status, "passed")
  testthat::expect_equal(full_proof$browser_ux_smoke_status, "passed")
})

testthat::test_that("missing git does not fail proof metadata collection", {
  repo_root <- .ai_validation_proof_repo_root()
  source(
    file.path(repo_root, "tests", "scripts", "helpers_validation_proof_status.R"),
    encoding = "UTF-8"
  )

  git_info <- validation_proof_collect_git_info(
    repo_root = repo_root,
    git_bin = ""
  )

  testthat::expect_false(git_info$git_available)
  testthat::expect_true(is.na(git_info$current_branch))
  testthat::expect_true(is.na(git_info$current_commit_sha))
  testthat::expect_equal(git_info$dirty_working_tree_status, "unknown")
})

testthat::test_that("git metadata collection does not warn when git command fails", {
  repo_root <- .ai_validation_proof_repo_root()
  source(
    file.path(repo_root, "tests", "scripts", "helpers_validation_proof_status.R"),
    encoding = "UTF-8"
  )

  fake_git <- tempfile("fake-git-", fileext = if (.Platform$OS.type == "windows") ".bat" else ".sh")

  if (.Platform$OS.type == "windows") {
    writeLines(
      c(
        "@echo off",
        "echo simulated git failure 1>&2",
        "exit /b 128"
      ),
      fake_git,
      useBytes = TRUE
    )
  } else {
    writeLines(
      c(
        "#!/usr/bin/env sh",
        "echo simulated git failure 1>&2",
        "exit 128"
      ),
      fake_git,
      useBytes = TRUE
    )
    Sys.chmod(fake_git, mode = "0755")
  }

  testthat::expect_warning(
    git_info <- validation_proof_collect_git_info(
      repo_root = repo_root,
      git_bin = fake_git
    ),
    regexp = NA
  )

  testthat::expect_true(git_info$git_available)
  testthat::expect_true(is.na(git_info$current_branch))
  testthat::expect_true(is.na(git_info$current_commit_sha))
  testthat::expect_equal(git_info$dirty_working_tree_status, "unknown")
})

testthat::test_that("validation doctor is not represented as execution proof", {
  repo_root <- .ai_validation_proof_repo_root()
  doctor <- .ai_validation_proof_read_text(
    file.path(repo_root, "tests", "scripts", "validation_doctor.R")
  )

  .ai_validation_proof_expect_all(
    doctor,
    c(
      "doctor_runs_heavy_checks",
      "validation_execution_status",
      "not_run_by_validation_doctor",
      "doctor_execution_notes",
      "Use the listed commands as separate evidence gates; the doctor artifact is guidance, not validation evidence."
    ),
    "Validation doctor execution-proof ayrımı eksik:"
  )
})

testthat::test_that("answer self-check catches validation overclaims from proof fields", {
  rscript <- Sys.which("Rscript")
  testthat::skip_if_not(nzchar(rscript))

  repo_root <- .ai_validation_proof_repo_root()

  answer_file <- tempfile("overclaim-answer-", fileext = ".md")
  summary_file <- tempfile("overclaim-summary-", fileext = ".json")

  writeLines(
    c(
      "Full validation passed.",
      "All validation gates passed.",
      "Validation doctor passed.",
      "Browser UX smoke passed.",
      "VM/SSO preflight passed.",
      "SQL Server Turkish encoding preflight passed.",
      "Manual fragile-flow evidence passed."
    ),
    answer_file,
    useBytes = TRUE
  )

  writeLines(
    c(
      "{",
      "  \"validation_execution_status\":\"ran_by_ai_repo_check\",",
      "  \"profile_requested\":\"cloud-quick\",",
      "  \"profile_effective\":\"quick\",",
      "  \"failed_steps\":0,",
      "  \"cloud_quick_validation_status\":\"passed\",",
      "  \"quick_repo_validation_status\":\"not_requested\",",
      "  \"full_validation_status\":\"not_requested\",",
      "  \"app_source_smoke_status\":\"skipped\",",
      "  \"shiny_boot_smoke_status\":\"not_requested\",",
      "  \"app_boot_smoke_status\":\"not_requested\",",
      "  \"browser_smoke_status\":\"not_requested\",",
      "  \"browser_ux_smoke_status\":\"not_requested\",",
      "  \"browser_required\":false,",
      "  \"db_sso_vm_validation_status\":\"not_performed_by_ai_validate\",",
      "  \"vm_sso_preflight_status\":\"not_performed_by_ai_validate\",",
      "  \"sql_server_turkish_encoding_validation_status\":\"not_performed_by_ai_validate\",",
      "  \"sql_server_turkish_encoding_preflight_status\":\"not_performed_by_ai_validate\",",
      "  \"manual_fragile_flow_validation_status\":\"not_performed_by_ai_validate\"",
      "}"
    ),
    summary_file,
    useBytes = TRUE
  )

	output <- withr::with_dir(
	  repo_root,
	  suppressWarnings(
		system2(
		  rscript,
		  c(
			"tests/scripts/ai_answer_check.R",
			"--answer",
			answer_file,
			"--summary",
			summary_file
		  ),
		  stdout = TRUE,
		  stderr = TRUE
		)
	  )
	)

  status <- attr(output, "status", exact = TRUE)

  testthat::expect_equal(as.integer(status), 1L)

  combined <- paste(output, collapse = "\n")

  .ai_validation_proof_expect_all(
    combined,
    c(
      "Answer claims full validation passed",
      "Answer claims all validation gates passed",
      "Answer treats validation doctor output as a pass/fail gate",
      "Answer claims browser UX smoke passed",
      "Answer claims VM/SSO/DB preflight passed",
      "Answer claims SQL Server Turkish encoding preflight passed",
      "Answer claims manual fragile-flow evidence passed"
    ),
    "Answer-check overclaim hatalarını yakalamadı:"
  )
})