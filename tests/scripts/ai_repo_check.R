#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/ai_repo_check.R
# Açıklama:
#   AI ajanlarının tek komutla repo doğrulaması yapabilmesi için ana orkestratör.
#
# Kullanım:
#   Rscript tests/scripts/ai_repo_check.R --profile quick
#   Rscript tests/scripts/ai_repo_check.R --profile full --boot-smoke
#   Rscript tests/scripts/ai_repo_check.R --profile quick --answer .ai/proposed_answer.md
#
# AI cloud notu:
#   Codex / Claude Code cloud ortamlarında ağır runtime paketleri intentionally
#   atlanıyorsa, app.R kaynak smoke testi şu bayrakla atlanabilir:
#   MERGEN_AI_SKIP_APP_SOURCE_SMOKE=true
# ==============================================================================

options(warn = 1)

args <- commandArgs(trailingOnly = TRUE)

arg_value <- function(name, default = NULL) {
  prefix <- paste0(name, "=")
  direct <- args[startsWith(args, prefix)]
  if (length(direct) > 0L) {
    return(sub(prefix, "", direct[[1]], fixed = TRUE))
  }

  pos <- match(name, args)
  if (!is.na(pos) && pos < length(args)) {
    return(args[[pos + 1L]])
  }

  default
}

has_flag <- function(name) {
  name %in% args
}

profile <- arg_value("--profile", "quick")
answer_path <- arg_value("--answer", NULL)
boot_smoke <- has_flag("--boot-smoke")
continue_on_error <- has_flag("--continue-on-error")

if (!profile %in% c("quick", "full")) {
  stop("--profile must be quick or full.", call. = FALSE)
}

env_flag_true <- function(name) {
  identical(tolower(Sys.getenv(name, unset = "false")), "true")
}

skip_app_source_smoke <- env_flag_true("MERGEN_AI_SKIP_APP_SOURCE_SMOKE")

find_repo_root <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R")) &&
        dir.exists(file.path(cand, "tests"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("Repo root bulunamadı. Bu betiği repo içinde çalıştırın.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)

source("tests/scripts/helpers_validation_proof_status.R", encoding = "UTF-8")

rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) {
  stop(
    paste(
      "Rscript bulunamadı.",
      "GitHub Actions içinde r-lib/actions/setup-r@v2 kullanın.",
      "Yerelde R kurulumunun PATH içinde olduğundan emin olun."
    ),
    call. = FALSE
  )
}

timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
artifact_root <- file.path(repo_root, "artifacts", "ai-validation", timestamp)
dir.create(artifact_root, recursive = TRUE, showWarnings = FALSE)

cat("== MERGEN AI repository validation ==\n")
cat(sprintf("Repo root: %s\n", repo_root))
cat(sprintf("Profile: %s\n", profile))
cat(sprintf("Rscript: %s\n", rscript))
cat(sprintf("Artifacts: %s\n", artifact_root))
cat(sprintf("Boot smoke: %s\n", boot_smoke))
cat(sprintf("Skip app source smoke: %s\n", skip_app_source_smoke))
if (!is.null(answer_path)) {
  cat(sprintf("Answer check: %s\n", answer_path))
}
cat("\n")

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

env_pair <- function(name, default = "") {
  paste0(name, "=", Sys.getenv(name, unset = default))
}

# LANG=C.utf8 yalnızca POSIX/Linux benzeri ortamlarda güvenli varsayımdır.
# Windows/RStudio/kurumsal VM ortamında child Rscript sürecine LANG=C.utf8
# zorlamak Rscript.exe çökmesine yol açabilir. Bu nedenle Windows'ta LANG
# override edilmez; mevcut sistem locale'i korunur.
base_env <- c(
  if (.Platform$OS.type == "windows") {
    character(0)
  } else {
    paste0("LANG=", if (nzchar(Sys.getenv("LANG"))) Sys.getenv("LANG") else "C.utf8")
  },
  "TZ=UTC",
  "MERGEN_RUN_APP=false",
  "MERGEN_DISABLE_FUTURES=true",
  "LOCAL_LLM_ENDPOINT=http://test.local/v1",
  "DB_DSN=test-dsn",
  "AI_KEYS_MASTER=test-master-key-0123456789",
  env_pair("MERGEN_AI_SKIP_APP_SOURCE_SMOKE", "false"),
  env_pair("MERGEN_AI_SKIP_SOURCE_PACKAGES", ""),
  env_pair("MERGEN_AI_R_PKG_TYPE", "")
)

safe_name <- function(x) {
  x <- gsub("[^A-Za-z0-9_.-]+", "_", x, perl = TRUE)
  x <- gsub("^_+|_+$", "", x, perl = TRUE)
  if (!nzchar(x)) x <- "step"
  x
}

json_escape <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("\\\\", "\\\\\\\\", x, perl = TRUE)
  x <- gsub("\"", "\\\\\"", x, perl = TRUE)
  x <- gsub("\n", "\\\\n", x, perl = TRUE)
  x <- gsub("\r", "\\\\r", x, perl = TRUE)
  x <- gsub("\t", "\\\\t", x, perl = TRUE)
  x
}

steps <- list()

record_step <- function(label, status, duration_seconds, log_path, skipped = FALSE) {
  result <- list(
    label = label,
    status = as.integer(status),
    duration_seconds = as.numeric(duration_seconds),
    log = log_path,
    skipped = isTRUE(skipped)
  )

  steps[[length(steps) + 1L]] <<- result
  invisible(result)
}

record_skipped_step <- function(label, reason) {
  step_id <- sprintf("%02d-%s", length(steps) + 1L, safe_name(label))
  log_path <- file.path(artifact_root, paste0(step_id, ".log"))

  writeLines(
    c(
      sprintf("[%s] SKIPPED", label),
      sprintf("Reason: %s", reason),
      "Full runtime/app boot validation was not performed in this mode."
    ),
    con = log_path,
    useBytes = TRUE
  )

  cat(sprintf("\n[%s] SKIPPED\n", label))
  cat(sprintf("Reason: %s\n", reason))
  cat("Full runtime/app boot validation was not performed in this mode.\n")

  record_step(
    label = label,
    status = 0L,
    duration_seconds = 0,
    log_path = log_path,
    skipped = TRUE
  )
}

# system2() bu konteynerde '-e' argümanı içindeki parantezleri sh üzerinden
# çalıştırırken yanlış yorumlayabiliyor. R ifadesini geçici bir .R dosyasına
# yazıp o dosyayı çalıştırmak daha güvenli ve taşınabilirdir.
run_rscript_expr <- function(label, expr_string, env = base_env) {
  tmp <- tempfile(fileext = ".R")
  writeLines(expr_string, tmp, useBytes = TRUE)
  on.exit(unlink(tmp), add = TRUE)
  run_step(label, rscript, tmp, env = env)
}

run_step <- function(label, command, cmd_args = character(0), env = base_env) {
  step_id <- sprintf("%02d-%s", length(steps) + 1L, safe_name(label))
  log_path <- file.path(artifact_root, paste0(step_id, ".log"))
  stdout_path <- paste0(log_path, ".stdout")
  stderr_path <- paste0(log_path, ".stderr")

  combine_step_logs <- function() {
    parts <- character(0)

    if (file.exists(stdout_path)) {
      stdout_lines <- tryCatch(
        readLines(stdout_path, warn = FALSE, encoding = "UTF-8"),
        error = function(e) sprintf("STDOUT READ ERROR: %s", conditionMessage(e))
      )

      if (length(stdout_lines) > 0L) {
        parts <- c(parts, "--- stdout ---", stdout_lines)
      }
    }

    if (file.exists(stderr_path)) {
      stderr_lines <- tryCatch(
        readLines(stderr_path, warn = FALSE, encoding = "UTF-8"),
        error = function(e) sprintf("STDERR READ ERROR: %s", conditionMessage(e))
      )

      if (length(stderr_lines) > 0L) {
        parts <- c(parts, "--- stderr ---", stderr_lines)
      }
    }

    if (length(parts) == 0L) {
      parts <- "No stdout/stderr captured."
    }

    writeLines(enc2utf8(parts), con = log_path, useBytes = TRUE)
    unlink(c(stdout_path, stderr_path), force = TRUE)
  }

  cat(sprintf("\n[%s] START\n", label))
  cat(sprintf("Command: %s %s\n", command, paste(shQuote(cmd_args), collapse = " ")))
  cat(sprintf("Log: %s\n", log_path))

  start_time <- Sys.time()

  status <- tryCatch(
    {
      suppressWarnings(
        system2(
          command = command,
          args = cmd_args,
          stdout = stdout_path,
          stderr = stderr_path,
          env = env,
          wait = TRUE
        )
      )
    },
    error = function(e) {
      writeLines(
        paste("SYSTEM2 ERROR:", conditionMessage(e)),
        con = stderr_path,
        useBytes = TRUE
      )
      127L
    }
  )

  combine_step_logs()

  if (is.null(status)) status <- 0L
  status <- as.integer(status)

  duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  record_step(
    label = label,
    status = status,
    duration_seconds = duration,
    log_path = log_path,
    skipped = FALSE
  )

  if (identical(status, 0L)) {
    cat(sprintf("[%s] OK in %.1fs\n", label, duration))
  } else {
    cat(sprintf("[%s] FAILED status=%d in %.1fs\n", label, status, duration))

    if (file.exists(log_path)) {
      log_lines <- readLines(log_path, warn = FALSE, encoding = "UTF-8")
      tail_lines <- tail(log_lines, 80L)
      cat("\n--- log tail ---\n")
      cat(paste(tail_lines, collapse = "\n"))
      cat("\n--- end log tail ---\n")
    }

    if (!isTRUE(continue_on_error)) {
      write_summary_and_exit(status = 1L)
    }
  }

  invisible(status)
}

write_summary_and_exit <- function(status = NULL) {
  failed <- vapply(steps, function(s) !identical(s$status, 0L), logical(1))
  skipped <- vapply(steps, function(s) isTRUE(s$skipped), logical(1))
  failed_count <- sum(failed)
  skipped_count <- sum(skipped)

  summary_path <- file.path(artifact_root, "summary.json")

  json <- validation_proof_render_ai_summary(
    profile = profile,
    repo_root = repo_root,
    artifact_root = artifact_root,
    steps = steps,
    boot_smoke = boot_smoke,
    skip_app_source_smoke = skip_app_source_smoke,
    answer_path = answer_path
  )

  writeLines(json, summary_path, useBytes = TRUE)

  cat(sprintf("\nSummary written: %s\n", summary_path))
  cat(sprintf("Failed steps: %d\n", failed_count))
  cat(sprintf("Skipped steps: %d\n", skipped_count))

  if (is.null(status)) {
    status <- if (failed_count > 0L) 1L else 0L
  }

  quit(status = status)
}

on.exit({
  if (exists("steps", inherits = FALSE)) {
    try(write_summary_and_exit(status = NULL), silent = TRUE)
  }
}, add = TRUE)

run_rscript_expr(
  "environment",
  paste(
    "cat('R version:', R.version.string, '\\n')",
    "cat('Rscript:', Sys.which('Rscript'), '\\n')",
    "cat('Working directory:', getwd(), '\\n')",
    "cat('Platform:', .Platform[['OS.type']], '\\n')",
    "cat('Locale:', Sys.getlocale(), '\\n')",
    sep = "\n"
  )
)

run_step(
  "parse sanity",
  rscript,
  c("tests/scripts/parse_sanity_check.R")
)

if (isTRUE(skip_app_source_smoke)) {
  record_skipped_step(
    "app source smoke",
    "MERGEN_AI_SKIP_APP_SOURCE_SMOKE=true for AI cloud light validation."
  )
} else {
  run_rscript_expr(
    "app source smoke",
    paste(
      "Sys.setenv(MERGEN_RUN_APP='false', MERGEN_DISABLE_FUTURES='true', TZ='UTC')",
      "if (!nzchar(Sys.getenv('LOCAL_LLM_ENDPOINT'))) Sys.setenv(LOCAL_LLM_ENDPOINT='http://test.local/v1')",
      "if (!nzchar(Sys.getenv('DB_DSN'))) Sys.setenv(DB_DSN='test-dsn')",
      "if (!nzchar(Sys.getenv('AI_KEYS_MASTER'))) Sys.setenv(AI_KEYS_MASTER='test-master-key-0123456789')",
      "source('app.R', encoding='UTF-8')",
      "validate_boot_state()",
      "cat('OK: app.R sourced and boot state validated.\\n')",
      sep = "\n"
    )
  )
}

quick_tests <- c(
  "tests/testthat/test-source-manifest-contract.R",
  "tests/testthat/test-source-manifest-sections-contract.R",
  "tests/testthat/test-seam-registry-contract.R",
  "tests/testthat/test-ui-asset-zones-contract.R",
  "tests/testthat/test-seam-doctor-contract.R",
  "tests/testthat/test-server-core-observer-runtime-contract.R",
  "tests/testthat/test-global-source-manifest-contract.R",
  "tests/testthat/test-ui-asset-manifest-contract.R",
  "tests/testthat/test-browser-smoke-harness-contract.R",
  "tests/testthat/test-browser-ux-smoke-runner-contract.R",
  "tests/testthat/test-validation-doctor-contract.R",
  "tests/testthat/test-validation-doctor-proof-status-contract.R",
  "tests/testthat/test-ai-validation-proof-status-contract.R",
  "tests/testthat/test-ux-smoke-browser-contract.R",
  "tests/testthat/test-smoke-probes-contract.R",
  "tests/testthat/test-maintainability-ratchet-contract.R",
  "tests/testthat/test-frontend-maintainability-ratchet.R",
  "tests/testthat/test-frontend-complexity-doctor-contract.R",
  "tests/testthat/test-text-encoding-utils.R",
  "tests/testthat/test-db-normalization-contract.R",
  "tests/testthat/test-db-refactor-contract.R",
  "tests/testthat/test-file-manager-display-name-contract.R",
  "tests/testthat/test-log-redact.R",
  "tests/testthat/test-secret-leak-contract.R",
  "tests/testthat/test-claude-code-security-policy-contract.R",
  "tests/testthat/test-claude-code-stream-html-safety-contract.R",
  "tests/testthat/test-claude-code-run-lifecycle-contract.R",
  "tests/testthat/test-streaming-abort-lifecycle-smoke.R",
  "tests/testthat/test-true-streaming-reset-ui-contract.R",
  "tests/testthat/test-audio-lifecycle-owner-smoke.R",
  "tests/testthat/test-chat-input-stop-button-smoke.R",
  "tests/testthat/test-character-personas-contract.R",
  "tests/testthat/test-production-contracts.R"
)

quick_tests <- quick_tests[file.exists(quick_tests)]

r_string_literal <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x, perl = TRUE)
  x <- gsub("\"", "\\\\\"", x, perl = TRUE)
  sprintf("\"%s\"", x)
}

r_character_vector_literal <- function(x) {
  if (length(x) == 0L) {
    return("character(0)")
  }
  paste0("c(", paste(r_string_literal(x), collapse = ", "), ")")
}

if (profile == "quick") {
  quick_tests_literal <- r_character_vector_literal(quick_tests)

  test_expr <- paste0(
    "Sys.setenv(MERGEN_RUN_APP='false', MERGEN_DISABLE_FUTURES='true', TESTTHAT_EDITION='3', TZ='UTC'); ",
    "library(testthat); ",
    "tests <- ", quick_tests_literal, "; ",
    "tests <- tests[file.exists(tests)]; ",
    "cat('Focused tests:', length(tests), '\\n'); ",
    "for (f in tests) { ",
    "cat('\\n===== RUN ', f, ' =====\\n', sep=''); ",
    "testthat::test_file(f, reporter='summary'); ",
    "}"
  )

  run_rscript_expr("focused contract tests", test_expr)
} else {
  run_step(
    "full testthat suite",
    rscript,
    c("tests/testthat.R")
  )
}

if (isTRUE(boot_smoke)) {
  run_step(
    "shiny boot smoke",
    rscript,
    c("tests/scripts/ai_boot_smoke.R")
  )

  run_step(
    "browser UX smoke",
    rscript,
    c("tests/scripts/ai_browser_ux_smoke.R")
  )
}

if (!is.null(answer_path)) {
  normalized_answer <- normalizePath(answer_path, winslash = "/", mustWork = FALSE)
  latest_summary <- file.path(artifact_root, "summary.json")

  run_step(
    "answer self-check",
    rscript,
    c(
      "tests/scripts/ai_answer_check.R",
      "--answer",
      normalized_answer,
      "--summary",
      latest_summary
    )
  )
}

write_summary_and_exit(status = NULL)