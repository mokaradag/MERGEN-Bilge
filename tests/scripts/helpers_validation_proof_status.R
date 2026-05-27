# ==============================================================================
# Dosya Yolu: tests/scripts/helpers_validation_proof_status.R
# Açıklama: AI doğrulama summary.json çıktısı için secret-safe ve makinece
#           okunabilir kanıt sınırı alanlarını üretir.
# ==============================================================================

validation_proof_nullish <- function(x, y) {
  if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x
}

validation_proof_json_escape <- function(x) {
  x <- as.character(validation_proof_nullish(x, ""))
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  enc2utf8(x)
}

validation_proof_json_string <- function(x) {
  sprintf("\"%s\"", validation_proof_json_escape(x))
}

validation_proof_json_nullable_string <- function(x) {
  if (is.null(x) || length(x) == 0L || is.na(x[1])) {
    return("null")
  }

  validation_proof_json_string(x[1])
}

validation_proof_json_bool <- function(x) {
  if (isTRUE(x)) "true" else "false"
}

validation_proof_json_array <- function(x) {
  x <- as.character(x %||% character(0))
  paste0(
    "[",
    paste(vapply(x, validation_proof_json_string, character(1)), collapse = ", "),
    "]"
  )
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

validation_proof_env_flag_true <- function(name) {
  value <- tolower(trimws(Sys.getenv(name, unset = "false")))
  value %in% c("true", "t", "1", "yes", "y")
}

validation_proof_run_git <- function(repo_root,
                                     args,
                                     git_bin = Sys.which("git")) {
  if (!nzchar(git_bin)) {
    return(list(
      ok = FALSE,
      status = 127L,
      stdout = character(0)
    ))
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

	out <- tryCatch(
	  {
		suppressWarnings(
		  system2(
			command = git_bin,
			args = args,
			stdout = TRUE,
			stderr = TRUE
		  )
		)
	  },
	  error = function(e) {
		structure(character(0), status = 127L)
	  }
	)

  status <- attr(out, "status", exact = TRUE)
  if (is.null(status)) {
    status <- 0L
  }

  list(
    ok = identical(as.integer(status), 0L),
    status = as.integer(status),
    stdout = enc2utf8(as.character(out))
  )
}

validation_proof_collect_git_info <- function(repo_root,
                                              git_bin = Sys.which("git")) {
  info <- list(
    git_available = nzchar(git_bin),
    current_branch = NA_character_,
    current_commit_sha = NA_character_,
    dirty_working_tree_status = "unknown",
    dirty_working_tree_entries = NA_integer_
  )

  if (!isTRUE(info$git_available)) {
    return(info)
  }

  branch <- validation_proof_run_git(
    repo_root,
    c("rev-parse", "--abbrev-ref", "HEAD"),
    git_bin = git_bin
  )

  if (isTRUE(branch$ok) && length(branch$stdout) > 0L) {
    value <- trimws(branch$stdout[[1]])
    if (nzchar(value)) {
      info$current_branch <- value
    }
  }

  sha <- validation_proof_run_git(
    repo_root,
    c("rev-parse", "HEAD"),
    git_bin = git_bin
  )

  if (isTRUE(sha$ok) && length(sha$stdout) > 0L) {
    value <- trimws(sha$stdout[[1]])
    if (nzchar(value)) {
      info$current_commit_sha <- value
    }
  }

  dirty <- validation_proof_run_git(
    repo_root,
    c("status", "--porcelain=v1", "--untracked-files=all"),
    git_bin = git_bin
  )

  if (isTRUE(dirty$ok)) {
    entries <- dirty$stdout[nzchar(trimws(dirty$stdout))]
    info$dirty_working_tree_entries <- length(entries)
    info$dirty_working_tree_status <- if (length(entries) > 0L) {
      "dirty"
    } else {
      "clean"
    }
  }

  info
}

validation_proof_read_log <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    return("")
  }

  txt <- tryCatch(
    {
      paste(
        readLines(path, warn = FALSE, encoding = "UTF-8"),
        collapse = "\n"
      )
    },
    error = function(e) ""
  )

  enc2utf8(txt)
}

validation_proof_step_labels <- function(steps, predicate) {
  if (length(steps) == 0L) {
    return(character(0))
  }

  labels <- character(0)

  for (step in steps) {
    if (isTRUE(predicate(step))) {
      labels <- c(labels, as.character(step$label %||% ""))
    }
  }

  labels[nzchar(labels)]
}

validation_proof_step_outcome <- function(steps,
                                          label,
                                          skip_markers = character(0)) {
  matching <- steps[vapply(
    steps,
    function(step) identical(as.character(step$label %||% ""), label),
    logical(1)
  )]

  if (length(matching) == 0L) {
    return("not_requested")
  }

  step <- matching[[length(matching)]]

  if (!identical(as.integer(step$status %||% 0L), 0L)) {
    return("failed")
  }

  if (isTRUE(step$skipped)) {
    return("skipped")
  }

  log_text <- validation_proof_read_log(step$log %||% "")

  if (length(skip_markers) > 0L &&
      any(vapply(
        skip_markers,
        function(marker) grepl(marker, log_text, fixed = TRUE, useBytes = TRUE),
        logical(1)
      ))) {
    return("skipped")
  }

  "passed"
}

validation_proof_build_notes <- function(profile_requested,
                                         profile_effective,
                                         boot_smoke,
                                         browser_required,
                                         app_source_smoke_status,
                                         shiny_boot_smoke_status,
                                         browser_smoke_status) {
  notes <- c(sprintf(
    "Requested profile is '%s'; effective repo profile is '%s'.",
    profile_requested,
    profile_effective
  ))

  if (identical(profile_requested, "cloud-quick")) {
    notes <- c(
      notes,
      paste(
        "cloud-quick is a cloud-safe wrapper over the quick repo profile;",
        "it intentionally skips app source smoke and does not prove full",
        "runtime, Shiny boot, real browser UX, VM/SSO/DB, SQL Server Turkish",
        "encoding, or manual fragile-flow behavior."
      )
    )
  }

  if (identical(profile_effective, "quick") &&
      !identical(profile_requested, "cloud-quick")) {
    notes <- c(
      notes,
      paste(
        "quick proves parse sanity, app source smoke when not skipped, and",
        "focused contracts only; it does not prove the full testthat suite,",
        "Shiny HTTP boot, real browser UX, VM/SSO/DB, SQL Server Turkish",
        "encoding, or manual fragile-flow evidence."
      )
    )
  }

  if (identical(profile_effective, "full") && !isTRUE(boot_smoke)) {
    notes <- c(
      notes,
      paste(
        "full without --boot-smoke proves the full testthat suite but does",
        "not prove Shiny HTTP boot or browser UX smoke."
      )
    )
  }

  if (isTRUE(boot_smoke) && identical(browser_smoke_status, "skipped") &&
      !isTRUE(browser_required)) {
    notes <- c(
      notes,
      paste(
        "Browser UX smoke was non-blocking in this run; require it with",
        "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true for browser-gated evidence."
      )
    )
  }

  if (identical(app_source_smoke_status, "skipped")) {
    notes <- c(
      notes,
      "App source smoke was skipped; this run must not be described as app source/runtime proof."
    )
  }

  if (!identical(shiny_boot_smoke_status, "passed")) {
    notes <- c(
      notes,
      "Shiny boot smoke did not pass in this summary; do not claim the app booted from this evidence."
    )
  }

  notes <- c(
    notes,
    paste(
      "ai_validate does not run Windows VM/SSO/real DB preflight, SQL Server",
      "Turkish encoding transactional preflight, or manual fragile-flow evidence;",
      "those gates require their separate commands."
    ),
    paste(
      "Validation doctor artifacts are guidance only and must not be cited as",
      "execution proof."
    )
  )

  unique(enc2utf8(notes))
}

validation_proof_gate_statuses <- function(profile_requested,
                                           profile_effective,
                                           failed_labels,
                                           app_source_smoke_status,
                                           focused_contract_tests_status,
                                           full_testthat_suite_status) {
  no_failed_steps <- length(failed_labels) == 0L

  cloud_quick_validation_status <- "not_requested"
  if (identical(profile_requested, "cloud-quick")) {
    cloud_quick_validation_status <- if (
      isTRUE(no_failed_steps) &&
        identical(profile_effective, "quick") &&
        identical(app_source_smoke_status, "skipped") &&
        identical(focused_contract_tests_status, "passed")
    ) {
      "passed"
    } else {
      "failed"
    }
  }

  quick_repo_validation_status <- "not_requested"
  if (identical(profile_requested, "quick") &&
      identical(profile_effective, "quick")) {
    quick_repo_validation_status <- if (
      isTRUE(no_failed_steps) &&
        identical(app_source_smoke_status, "passed") &&
        identical(focused_contract_tests_status, "passed")
    ) {
      "passed"
    } else {
      "failed"
    }
  }

  full_validation_status <- "not_requested"
  if (identical(profile_effective, "full")) {
    full_validation_status <- if (
      isTRUE(no_failed_steps) &&
        identical(app_source_smoke_status, "passed") &&
        identical(full_testthat_suite_status, "passed")
    ) {
      "passed"
    } else {
      "failed"
    }
  }

  list(
    cloud_quick_validation_status = cloud_quick_validation_status,
    quick_repo_validation_status = quick_repo_validation_status,
    full_validation_status = full_validation_status
  )
}

validation_proof_status <- function(profile,
                                    repo_root,
                                    steps,
                                    boot_smoke,
                                    skip_app_source_smoke,
                                    profile_requested = Sys.getenv(
                                      "MERGEN_AI_REQUESTED_PROFILE",
                                      unset = profile
                                    ),
                                    profile_effective = Sys.getenv(
                                      "MERGEN_AI_EFFECTIVE_PROFILE",
                                      unset = profile
                                    ),
                                    generated_at = Sys.time()) {
  failed_labels <- validation_proof_step_labels(
    steps,
    function(step) !identical(as.integer(step$status %||% 0L), 0L)
  )

  skipped_labels <- validation_proof_step_labels(
    steps,
    function(step) isTRUE(step$skipped)
  )

  app_source_smoke_status <- validation_proof_step_outcome(
    steps,
    "app source smoke"
  )

  focused_contract_tests_status <- validation_proof_step_outcome(
    steps,
    "focused contract tests"
  )

  full_testthat_suite_status <- validation_proof_step_outcome(
    steps,
    "full testthat suite"
  )

  shiny_boot_smoke_status <- validation_proof_step_outcome(
    steps,
    "shiny boot smoke"
  )

  browser_smoke_status <- validation_proof_step_outcome(
    steps,
    "browser UX smoke",
    skip_markers = c(
      "SKIP: Chrome/Chromium/Edge binary bulunamadı",
      "This skip yalnızca gerçek browser UX smoke içindir"
    )
  )

  browser_required <- validation_proof_env_flag_true(
    "MERGEN_REQUIRE_BROWSER_UX_SMOKE"
  )

  gate_statuses <- validation_proof_gate_statuses(
    profile_requested = profile_requested,
    profile_effective = profile_effective,
    failed_labels = failed_labels,
    app_source_smoke_status = app_source_smoke_status,
    focused_contract_tests_status = focused_contract_tests_status,
    full_testthat_suite_status = full_testthat_suite_status
  )

  git <- validation_proof_collect_git_info(repo_root)

  proof_boundary_notes <- validation_proof_build_notes(
    profile_requested = profile_requested,
    profile_effective = profile_effective,
    boot_smoke = boot_smoke,
    browser_required = browser_required,
    app_source_smoke_status = app_source_smoke_status,
    shiny_boot_smoke_status = shiny_boot_smoke_status,
    browser_smoke_status = browser_smoke_status
  )

  list(
    validation_execution_status = "ran_by_ai_repo_check",
    profile_requested = profile_requested,
    profile_effective = profile_effective,
    timestamp = format(generated_at, "%Y-%m-%d %H:%M:%S %z"),
    git_available = isTRUE(git$git_available),
    current_branch = git$current_branch,
    current_commit_sha = git$current_commit_sha,
    dirty_working_tree_status = git$dirty_working_tree_status,
    dirty_working_tree_entries = git$dirty_working_tree_entries,
    focused_contract_tests_status = focused_contract_tests_status,
    full_testthat_suite_status = full_testthat_suite_status,
    cloud_quick_validation_status = gate_statuses$cloud_quick_validation_status,
    quick_repo_validation_status = gate_statuses$quick_repo_validation_status,
    full_validation_status = gate_statuses$full_validation_status,
    app_source_smoke_status = app_source_smoke_status,
    shiny_boot_smoke_status = shiny_boot_smoke_status,
    app_boot_smoke_status = shiny_boot_smoke_status,
    browser_smoke_status = browser_smoke_status,
    browser_ux_smoke_status = browser_smoke_status,
    browser_required = browser_required,
    db_sso_vm_validation_performed = FALSE,
    db_sso_vm_validation_status = "not_performed_by_ai_validate",
    vm_sso_preflight_status = "not_performed_by_ai_validate",
    sql_server_turkish_encoding_preflight_status = "not_performed_by_ai_validate",
    sql_server_turkish_encoding_validation_status = "not_performed_by_ai_validate",
    manual_fragile_flow_evidence_status = "not_performed_by_ai_validate",
    manual_fragile_flow_validation_status = "not_performed_by_ai_validate",
    failed_step_labels = failed_labels,
    skipped_step_labels = skipped_labels,
    proof_boundary_notes = proof_boundary_notes,
    skip_app_source_smoke = isTRUE(skip_app_source_smoke),
    boot_smoke = isTRUE(boot_smoke)
  )
}

validation_proof_steps_json <- function(steps) {
  vapply(steps, function(step) {
    sprintf(
      paste0(
        "{",
        "\"label\":\"%s\",",
        "\"status\":%d,",
        "\"duration_seconds\":%.3f,",
        "\"log\":\"%s\",",
        "\"skipped\":%s",
        "}"
      ),
      validation_proof_json_escape(step$label %||% ""),
      as.integer(step$status %||% 0L),
      as.numeric(step$duration_seconds %||% 0),
      validation_proof_json_escape(normalizePath(
        step$log %||% "",
        winslash = "/",
        mustWork = FALSE
      )),
      validation_proof_json_bool(isTRUE(step$skipped))
    )
  }, character(1))
}

validation_proof_render_ai_summary <- function(profile,
                                               repo_root,
                                               artifact_root,
                                               steps,
                                               boot_smoke,
                                               skip_app_source_smoke,
                                               answer_path = NULL) {
  failed <- vapply(
    steps,
    function(step) !identical(as.integer(step$status %||% 0L), 0L),
    logical(1)
  )

  skipped <- vapply(
    steps,
    function(step) isTRUE(step$skipped),
    logical(1)
  )

  proof <- validation_proof_status(
    profile = profile,
    repo_root = repo_root,
    steps = steps,
    boot_smoke = boot_smoke,
    skip_app_source_smoke = skip_app_source_smoke
  )

  step_json <- validation_proof_steps_json(steps)

  paste0(
    "{\n",
    sprintf("  \"validation_execution_status\":%s,\n", validation_proof_json_string(proof$validation_execution_status)),
    sprintf("  \"profile\":\"%s\",\n", validation_proof_json_escape(profile)),
    sprintf("  \"profile_requested\":%s,\n", validation_proof_json_string(proof$profile_requested)),
    sprintf("  \"profile_effective\":%s,\n", validation_proof_json_string(proof$profile_effective)),
    sprintf("  \"timestamp\":%s,\n", validation_proof_json_string(proof$timestamp)),
    sprintf("  \"repo_root\":\"%s\",\n", validation_proof_json_escape(repo_root)),
    sprintf("  \"artifact_root\":\"%s\",\n", validation_proof_json_escape(normalizePath(artifact_root, winslash = "/", mustWork = FALSE))),
    sprintf("  \"git_available\":%s,\n", validation_proof_json_bool(proof$git_available)),
    sprintf("  \"current_branch\":%s,\n", validation_proof_json_nullable_string(proof$current_branch)),
    sprintf("  \"current_commit_sha\":%s,\n", validation_proof_json_nullable_string(proof$current_commit_sha)),
    sprintf("  \"dirty_working_tree_status\":%s,\n", validation_proof_json_string(proof$dirty_working_tree_status)),
    sprintf(
      "  \"dirty_working_tree_entries\":%s,\n",
      if (is.na(proof$dirty_working_tree_entries)) {
        "null"
      } else {
        as.character(as.integer(proof$dirty_working_tree_entries))
      }
    ),
    sprintf("  \"total_steps\":%d,\n", length(steps)),
    sprintf("  \"failed_steps\":%d,\n", sum(failed)),
    sprintf("  \"skipped_steps\":%d,\n", sum(skipped)),
    sprintf("  \"failed_step_labels\":%s,\n", validation_proof_json_array(proof$failed_step_labels)),
    sprintf("  \"skipped_step_labels\":%s,\n", validation_proof_json_array(proof$skipped_step_labels)),
    sprintf("  \"boot_smoke\":%s,\n", validation_proof_json_bool(proof$boot_smoke)),
    sprintf("  \"skip_app_source_smoke\":%s,\n", validation_proof_json_bool(proof$skip_app_source_smoke)),
    sprintf("  \"focused_contract_tests_status\":%s,\n", validation_proof_json_string(proof$focused_contract_tests_status)),
    sprintf("  \"full_testthat_suite_status\":%s,\n", validation_proof_json_string(proof$full_testthat_suite_status)),
    sprintf("  \"cloud_quick_validation_status\":%s,\n", validation_proof_json_string(proof$cloud_quick_validation_status)),
    sprintf("  \"quick_repo_validation_status\":%s,\n", validation_proof_json_string(proof$quick_repo_validation_status)),
    sprintf("  \"full_validation_status\":%s,\n", validation_proof_json_string(proof$full_validation_status)),
    sprintf("  \"app_source_smoke_status\":%s,\n", validation_proof_json_string(proof$app_source_smoke_status)),
    sprintf("  \"shiny_boot_smoke_status\":%s,\n", validation_proof_json_string(proof$shiny_boot_smoke_status)),
    sprintf("  \"app_boot_smoke_status\":%s,\n", validation_proof_json_string(proof$app_boot_smoke_status)),
    sprintf("  \"browser_smoke_status\":%s,\n", validation_proof_json_string(proof$browser_smoke_status)),
    sprintf("  \"browser_ux_smoke_status\":%s,\n", validation_proof_json_string(proof$browser_ux_smoke_status)),
    sprintf("  \"browser_required\":%s,\n", validation_proof_json_bool(proof$browser_required)),
    sprintf("  \"db_sso_vm_validation_performed\":%s,\n", validation_proof_json_bool(proof$db_sso_vm_validation_performed)),
    sprintf("  \"db_sso_vm_validation_status\":%s,\n", validation_proof_json_string(proof$db_sso_vm_validation_status)),
    sprintf("  \"vm_sso_preflight_status\":%s,\n", validation_proof_json_string(proof$vm_sso_preflight_status)),
    sprintf("  \"sql_server_turkish_encoding_preflight_status\":%s,\n", validation_proof_json_string(proof$sql_server_turkish_encoding_preflight_status)),
    sprintf("  \"sql_server_turkish_encoding_validation_status\":%s,\n", validation_proof_json_string(proof$sql_server_turkish_encoding_validation_status)),
    sprintf("  \"manual_fragile_flow_evidence_status\":%s,\n", validation_proof_json_string(proof$manual_fragile_flow_evidence_status)),
    sprintf("  \"manual_fragile_flow_validation_status\":%s,\n", validation_proof_json_string(proof$manual_fragile_flow_validation_status)),
    sprintf("  \"proof_boundary_notes\":%s,\n", validation_proof_json_array(proof$proof_boundary_notes)),
    sprintf("  \"answer_path\":%s,\n", validation_proof_json_nullable_string(answer_path)),
    "  \"steps\":[\n    ",
    paste(step_json, collapse = ",\n    "),
    "\n  ]\n",
    "}\n"
  )
}