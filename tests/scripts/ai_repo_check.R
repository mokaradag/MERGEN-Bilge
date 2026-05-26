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
if (!is.null(answer_path)) {
  cat(sprintf("Answer check: %s\n", answer_path))
}
cat("\n")

# LANG=C.utf8: POSIX lokalinde R, UTF-8 kaynak dosyalarını (Türkçe karakter içeren)
# "invalid input" uyarısıyla okuyabilir. C.utf8 hem taşınabilir hem UTF-8 güvenlidir.
utf8_lang <- if (nzchar(Sys.getenv("LANG"))) Sys.getenv("LANG") else "C.utf8"
base_env <- c(
  paste0("LANG=", utf8_lang),
  "TZ=UTC",
  "MERGEN_RUN_APP=false",
  "MERGEN_DISABLE_FUTURES=true",
  "LOCAL_LLM_ENDPOINT=http://test.local/v1",
  "DB_DSN=test-dsn",
  "AI_KEYS_MASTER=test-master-key-0123456789"
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

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

steps <- list()

# system2() bu konteynerde '-e' argümanı içindeki parantezleri sh üzerinden
# çalıştırırken yanlış yorumlayabiliyor. R ifadesini geçici bir .R dosyasına
# yazıp o dosyayı çalıştırmak daha güvenli ve taşınabilirdir.
run_rscript_expr <- function(label, expr_string, env = base_env) {
  tmp <- tempfile(fileext = ".R")
  writeLines(expr_string, tmp)
  on.exit(unlink(tmp), add = TRUE)
  run_step(label, rscript, tmp, env = env)
}

run_step <- function(label, command, cmd_args = character(0), env = base_env) {
  step_id <- sprintf("%02d-%s", length(steps) + 1L, safe_name(label))
  log_path <- file.path(artifact_root, paste0(step_id, ".log"))

  cat(sprintf("\n[%s] START\n", label))
  cat(sprintf("Command: %s %s\n", command, paste(shQuote(cmd_args), collapse = " ")))
  cat(sprintf("Log: %s\n", log_path))

  start_time <- Sys.time()

  status <- tryCatch(
    {
      system2(
        command = command,
        args = cmd_args,
        stdout = log_path,
        stderr = log_path,
        env = env,
        wait = TRUE
      )
    },
    error = function(e) {
      writeLines(
        paste("SYSTEM2 ERROR:", conditionMessage(e)),
        con = log_path,
        useBytes = TRUE
      )
      127L
    }
  )

  if (is.null(status)) status <- 0L
  status <- as.integer(status)

  duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  result <- list(
    label = label,
    status = status,
    duration_seconds = duration,
    log = log_path
  )

  steps[[length(steps) + 1L]] <<- result

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

  invisible(result)
}

write_summary_and_exit <- function(status = NULL) {
  failed <- vapply(steps, function(s) !identical(s$status, 0L), logical(1))
  failed_count <- sum(failed)

  summary_path <- file.path(artifact_root, "summary.json")

  step_json <- vapply(steps, function(s) {
    sprintf(
      paste0(
        "{",
        "\"label\":\"%s\",",
        "\"status\":%d,",
        "\"duration_seconds\":%.3f,",
        "\"log\":\"%s\"",
        "}"
      ),
      json_escape(s$label),
      as.integer(s$status),
      as.numeric(s$duration_seconds),
      json_escape(normalizePath(s$log, winslash = "/", mustWork = FALSE))
    )
  }, character(1))

  json <- paste0(
    "{\n",
    sprintf("  \"profile\":\"%s\",\n", json_escape(profile)),
    sprintf("  \"repo_root\":\"%s\",\n", json_escape(repo_root)),
    sprintf("  \"artifact_root\":\"%s\",\n", json_escape(normalizePath(artifact_root, winslash = "/", mustWork = FALSE))),
    sprintf("  \"total_steps\":%d,\n", length(steps)),
    sprintf("  \"failed_steps\":%d,\n", failed_count),
    sprintf("  \"boot_smoke\":%s,\n", if (isTRUE(boot_smoke)) "true" else "false"),
    sprintf("  \"answer_path\":%s,\n", if (is.null(answer_path)) "null" else sprintf("\"%s\"", json_escape(answer_path))),
    "  \"steps\":[\n    ",
    paste(step_json, collapse = ",\n    "),
    "\n  ]\n",
    "}\n"
  )

  writeLines(json, summary_path, useBytes = TRUE)

  cat(sprintf("\nSummary written: %s\n", summary_path))
  cat(sprintf("Failed steps: %d\n", failed_count))

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

quick_tests <- c(
  "tests/testthat/test-source-manifest-contract.R",
  "tests/testthat/test-server-core-observer-runtime-contract.R",
  "tests/testthat/test-global-source-manifest-contract.R",
  "tests/testthat/test-ui-asset-manifest-contract.R",
  "tests/testthat/test-maintainability-ratchet-contract.R",
  "tests/testthat/test-frontend-maintainability-ratchet.R",
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
  "tests/testthat/test-chat-input-stop-button-smoke.R",
  "tests/testthat/test-character-personas-contract.R",
  "tests/testthat/test-production-contracts.R"
)

quick_tests <- quick_tests[file.exists(quick_tests)]

if (profile == "quick") {
  test_expr <- paste0(
    "Sys.setenv(MERGEN_RUN_APP='false', MERGEN_DISABLE_FUTURES='true', TZ='UTC'); ",
    "library(testthat); ",
    "testthat::local_edition(3); ",
    "tests <- c(",
    paste(sprintf("%s", deparse(quick_tests)), collapse = ","),
    "); ",
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