#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/validation_doctor.R
# Açıklama:
#   MERGEN doğrulama profillerinin hangi güvenceyi verip vermediğini açıklar.
#   Ağır testleri, uygulamayı, DB bağlantısını veya tarayıcıyı başlatmaz.
#   Ortamı sınıflandırır, tarayıcı ikilisi varlığını launch etmeden denetler,
#   hassas ortam değişkenlerini yalnızca var/yok ve uzunluk bilgisiyle raporlar.
# ==============================================================================

options(warn = 1)

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x
}

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

first_positional_profile <- function(default = "all") {
  positional <- args[!startsWith(args, "--")]

  if (length(positional) > 0L) {
    return(positional[[1]])
  }

  default
}

find_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(".", "..", "../..", "../../.."),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R")) &&
        dir.exists(file.path(candidate, "tests"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Repo root bulunamadı. Bu betiği repo içinde çalıştırın.", call. = FALSE)
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

json_string <- function(x) {
  sprintf("\"%s\"", json_escape(x))
}

json_bool <- function(x) {
  if (isTRUE(x)) "true" else "false"
}

json_array <- function(x) {
  paste0("[", paste(vapply(x, json_string, character(1)), collapse = ", "), "]")
}

env_raw <- function(name) {
  Sys.getenv(name, unset = "")
}

env_present <- function(name) {
  nzchar(env_raw(name))
}

env_flag_true <- function(name) {
  tolower(trimws(env_raw(name))) %in% c("true", "t", "1", "yes", "y")
}

env_nchar <- function(name) {
  nchar(env_raw(name), type = "bytes", allowNA = FALSE)
}

norm_encoding <- function(value) {
  toupper(gsub("_", "-", trimws(as.character(value %||% "")), fixed = TRUE))
}

repo_root <- find_repo_root()
setwd(repo_root)

profile <- tolower(arg_value("--profile", first_positional_profile("all")))
valid_profiles <- c("cloud", "local", "vm", "all")

if (!profile %in% valid_profiles) {
  stop(
    sprintf(
      "--profile değeri geçersiz: %s. Geçerli değerler: %s",
      profile,
      paste(valid_profiles, collapse = ", ")
    ),
    call. = FALSE
  )
}

artifact_root_arg <- arg_value(
  "--artifact-root",
  file.path("artifacts", "validation-doctor")
)

artifact_root <- if (grepl("^([A-Za-z]:|/|\\\\\\\\)", artifact_root_arg)) {
  artifact_root_arg
} else {
  file.path(repo_root, artifact_root_arg)
}

artifact_root <- normalizePath(artifact_root, winslash = "/", mustWork = FALSE)
dir.create(artifact_root, recursive = TRUE, showWarnings = FALSE)

timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
summary_path <- file.path(
  artifact_root,
  sprintf("validation-doctor-%s.json", timestamp)
)

detect_browser <- function() {
  env_bin <- env_raw("MERGEN_BROWSER_BIN")

  if (nzchar(env_bin)) {
    env_hit <- file.exists(env_bin) || nzchar(Sys.which(env_bin))

    return(list(
      found = isTRUE(env_hit),
      name = basename(env_bin),
      source = "MERGEN_BROWSER_BIN",
      path_length = nchar(env_bin, type = "bytes", allowNA = FALSE)
    ))
  }

  path_candidates <- c(
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
    "microsoft-edge",
    "microsoft-edge-stable",
    "msedge",
    "chrome",
    "brave-browser"
  )

  found <- Sys.which(path_candidates)
  found <- found[nzchar(found)]

  if (length(found) > 0L) {
    first_name <- names(found)[[1]]
    first_path <- unname(found[[1]])

    return(list(
      found = TRUE,
      name = first_name,
      source = "PATH",
      path_length = nchar(first_path, type = "bytes", allowNA = FALSE)
    ))
  }

  if (.Platform$OS.type == "windows") {
    win_candidates <- c(
      file.path(env_raw("PROGRAMFILES"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(env_raw("PROGRAMFILES(X86)"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(env_raw("LOCALAPPDATA"), "Google", "Chrome", "Application", "chrome.exe"),
      file.path(env_raw("PROGRAMFILES"), "Microsoft", "Edge", "Application", "msedge.exe"),
      file.path(env_raw("PROGRAMFILES(X86)"), "Microsoft", "Edge", "Application", "msedge.exe"),
      file.path(env_raw("LOCALAPPDATA"), "Microsoft", "Edge", "Application", "msedge.exe")
    )

    win_candidates <- win_candidates[nzchar(win_candidates)]
    hit <- win_candidates[file.exists(win_candidates)]

    if (length(hit) > 0L) {
      first_path <- hit[[1]]

      return(list(
        found = TRUE,
        name = basename(first_path),
        source = "windows-default-paths",
        path_length = nchar(first_path, type = "bytes", allowNA = FALSE)
      ))
    }
  }

  list(
    found = FALSE,
    name = "",
    source = "not-found",
    path_length = 0L
  )
}

browser <- detect_browser()

cloud_signals <- c(
  "CI",
  "GITHUB_ACTIONS",
  "CODESPACES",
  "CODEBUILD_BUILD_ID",
  "CLOUD_SHELL",
  "CODEX_SANDBOX",
  "OPENAI_SANDBOX"
)

cloud_like <- any(vapply(cloud_signals, env_present, logical(1)))
windows_like <- identical(.Platform$OS.type, "windows")
sso_like <- env_flag_true("SSO_ENABLED")
vm_like <- isTRUE(windows_like) &&
  (isTRUE(sso_like) || (env_present("DB_DSN") && env_present("LOCAL_LLM_ENDPOINT")))

environment_class <- if (isTRUE(cloud_like)) {
  "cloud_or_ci_like"
} else if (isTRUE(vm_like) && isTRUE(sso_like)) {
  "windows_vm_sso_like"
} else if (isTRUE(vm_like)) {
  "windows_vm_or_local_db_like"
} else if (isTRUE(windows_like)) {
  "windows_local_like"
} else {
  "local_or_linux_ai_like"
}

env_names <- c(
  "SSO_ENABLED",
  "MERGEN_REQUIRE_BROWSER_UX_SMOKE",
  "MERGEN_PREFLIGHT_CHECK_FILE_STORE",
  "MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST",
  "MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE",
  "DB_CLIENT_ENCODING",
  "DB_NAME_ENCODING",
  "MERGEN_BROWSER_BIN",
  "LOCAL_LLM_ENDPOINT",
  "DB_DSN",
  "AI_KEYS_MASTER",
  "LOCAL_LLM_API_KEY",
  "SSO_KEYCLOAK_URL",
  "SSO_CLIENT_SECRET",
  "DB_PASSWORD"
)

secret_like_env <- grepl(
  "KEY|SECRET|PASSWORD|TOKEN|DSN|ENDPOINT|URL|BIN",
  env_names,
  ignore.case = TRUE
)

env_summary <- data.frame(
  name = env_names,
  present = vapply(env_names, env_present, logical(1)),
  nchar = vapply(env_names, env_nchar, integer(1)),
  secret_like = secret_like_env,
  matches_windows_1254 = vapply(
    env_names,
    function(name) {
      if (!name %in% c("DB_CLIENT_ENCODING", "DB_NAME_ENCODING")) {
        return(NA)
      }

      identical(norm_encoding(env_raw(name)), "WINDOWS-1254")
    },
    logical(1)
  ),
  stringsAsFactors = FALSE
)

validation_paths <- data.frame(
  id = c(
    "cloud_quick",
    "quick",
    "full_boot_smoke",
    "browser_required",
    "vm_preflight",
    "vm_encoding_preflight",
    "manual_fragile_flow"
  ),
  command = c(
    "bash tools/ai_validate.sh cloud-quick",
    "bash tools/ai_validate.sh quick",
    "bash tools/ai_validate.sh full --boot-smoke",
    "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke",
    'source("tests/scripts/run_vm_preflight_real.R", encoding = "UTF-8")',
    'Sys.setenv(MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST="TRUE"); source("tests/scripts/run_vm_encoding_preflight_real.R", encoding = "UTF-8")',
    'source("tests/scripts/run_fragile_flow_manual_preflight.R", encoding = "UTF-8")'
  ),
  proves = c(
    "Cloud/AI lightweight validation: parse sanity and focused contract tests that can run without heavy runtime packages.",
    "Normal developer validation: parse sanity, app source smoke when MERGEN_AI_SKIP_APP_SOURCE_SMOKE is not true, and focused contract tests.",
    "Runtime-sensitive validation: full testthat suite, Shiny boot smoke, and browser UX smoke when a browser binary exists.",
    "Browser-required runtime gate: full --boot-smoke plus blocking browser UX smoke; fails if Chrome/Chromium/Edge is unavailable or UX_SMOKE_DONE:PASS is not produced.",
    "Windows VM / SSO / SQL Server gate: app source/boot, SSO config, real DB health, LLM endpoint reachability, writable paths, UTF-8 roundtrip, and optional File Store roundtrip.",
    "Windows VM Turkish encoding gate: DB_CLIENT_ENCODING and DB_NAME_ENCODING must be WINDOWS-1254; transactional DB Turkish write/read probe runs and rolls back.",
    "Manual fragile-flow evidence: operator-recorded PASS/FAIL/SKIP evidence for flows too fragile or user-experience-sensitive for static tests."
  ),
  does_not_prove = c(
    "KANITLAMAZ: app source smoke / full runtime / real browser / VM DB validation. cloud-quick is not full runtime or VM validation.",
    "KANITLAMAZ: full testthat suite, live Shiny HTTP boot, real browser UX, VM/SSO DB, SQL Server Turkish write/read, or manual fragile-flow evidence.",
    "KANITLAMAZ: browser UX when no browser exists unless MERGEN_REQUIRE_BROWSER_UX_SMOKE=true, VM/SSO DB behavior, SQL Server transactional encoding, or manual fragile-flow evidence.",
    "KANITLAMAZ: Windows VM SSO/DB/LLM behavior, SQL Server Turkish encoding transactional write/read, or manual fragile-flow evidence.",
    "KANITLAMAZ: transactional Turkish encoding write/read unless run_vm_encoding_preflight_real.R is also run with MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE; manual fragile-flow evidence is separate.",
    "KANITLAMAZ: broader SSO user scoping, File Store roundtrip unless VM preflight is run with MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE, or interactive UI flows.",
    "KANITLAMAZ: automated proof; this is human evidence and must be reviewed with the CSV and attached notes/screenshots."
  ),
  blocking = c(
    "blocking for its own lightweight scope only",
    "blocking for parse/app-source/focused contracts",
    "blocking for full testthat and Shiny boot; browser can be SKIP without required flag",
    "blocking for browser availability and UX_SMOKE_DONE:PASS",
    "blocking by default for SSO, DB, LLM, paths; File Store is blocking only when MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE",
    "blocking for encoding env and transactional write/read when MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE; legacy mojibake scan is warning-only unless strict flag is set",
    "blocking only on FAIL or UNKNOWN; SKIP remains explicit evidence"
  ),
  stringsAsFactors = FALSE
)

profile_ids <- switch(
  profile,
  cloud = c("cloud_quick"),
  local = c("quick", "full_boot_smoke", "browser_required", "manual_fragile_flow"),
  vm = c(
    "full_boot_smoke",
    "browser_required",
    "vm_preflight",
    "vm_encoding_preflight",
    "manual_fragile_flow"
  ),
  all = validation_paths$id
)

selected_paths <- validation_paths[validation_paths$id %in% profile_ids, , drop = FALSE]

cat("== MERGEN Validation Doctor ==\n")
cat(sprintf("Repo root: %s\n", repo_root))
cat(sprintf("Requested profile: %s\n", profile))
cat(sprintf("Environment classification: %s\n", environment_class))
cat(sprintf("OS type: %s\n", .Platform$OS.type))
cat(sprintf("R version: %s\n", R.version.string))
cat(sprintf("Summary artifact: %s\n", summary_path))
cat("\n")

cat("Browser detection without app launch:\n")
cat(sprintf(" - found=%s\n", json_bool(browser$found)))
cat(sprintf(" - name=%s\n", if (nzchar(browser$name)) browser$name else "<none>"))
cat(sprintf(" - source=%s\n", browser$source))
cat(sprintf(" - path_length=%d\n", as.integer(browser$path_length)))
cat("\n")

cat("Secret-safe environment summary:\n")
for (i in seq_len(nrow(env_summary))) {
  row <- env_summary[i, ]

  line <- sprintf(
    " - %s: present=%s nchar=%d secret_like=%s",
    row$name,
    json_bool(row$present),
    as.integer(row$nchar),
    json_bool(row$secret_like)
  )

  if (row$name %in% c("DB_CLIENT_ENCODING", "DB_NAME_ENCODING")) {
    line <- paste0(
      line,
      sprintf(" matches_WINDOWS_1254=%s", json_bool(isTRUE(row$matches_windows_1254)))
    )
  }

  if (row$name %in% c(
    "SSO_ENABLED",
    "MERGEN_REQUIRE_BROWSER_UX_SMOKE",
    "MERGEN_PREFLIGHT_CHECK_FILE_STORE",
    "MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST",
    "MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE"
  )) {
    line <- paste0(line, sprintf(" true=%s", json_bool(env_flag_true(row$name))))
  }

  cat(line, " value=<hidden>\n", sep = "")
}
cat("\n")

cat("Recommended command sequence and proof boundaries:\n")
for (i in seq_len(nrow(selected_paths))) {
  row <- selected_paths[i, ]

  cat(sprintf("\n[%d] %s\n", i, row$command))
  cat(sprintf("    PROVES: %s\n", row$proves))
  cat(sprintf("    DOES NOT PROVE: %s\n", row$does_not_prove))
  cat(sprintf("    Blocking/warning: %s\n", row$blocking))

  if (identical(row$id, "vm_preflight")) {
    cat("    Required VM env: SSO_ENABLED=TRUE unless intentionally local; MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE for full File Store confidence.\n")
  }

  if (identical(row$id, "vm_encoding_preflight")) {
    cat("    Required encoding env: DB_CLIENT_ENCODING=WINDOWS-1254 and DB_NAME_ENCODING=WINDOWS-1254 before sourcing the script.\n")
    cat("    Historical mojibake scan remains warning-only unless MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE=TRUE.\n")
  }
}
cat("\n")

cat("Blocking checks:\n")
blocking_checks <- c(
  "quick/cloud-quick fail on parse or focused contract failures within their declared scope.",
  "full --boot-smoke fails on full testthat or Shiny boot smoke failure.",
  "MERGEN_REQUIRE_BROWSER_UX_SMOKE=true makes missing browser or missing UX_SMOKE_DONE:PASS blocking.",
  "run_vm_preflight_real.R is blocking for SSO/DB/LLM/path checks; File Store becomes blocking with MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE.",
  "run_vm_encoding_preflight_real.R is blocking for WINDOWS-1254 env mismatch and for transactional write/read when MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE.",
  "run_fragile_flow_manual_preflight.R is blocking on FAIL or UNKNOWN evidence."
)

for (item in blocking_checks) {
  cat(sprintf(" - %s\n", item))
}
cat("\n")

warning_checks <- c(
  "In normal full --boot-smoke mode, browser UX smoke can SKIP when no browser binary exists.",
  "Historical MB_Messages mojibake scan is warning-only unless MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE=TRUE.",
  "Manual SKIP evidence is explicit and must be reviewed; it is not automated proof.",
  "Validation doctor itself does not prove runtime behavior; it only prevents profile misuse."
)

doctor_execution_notes <- c(
  "NOT RUN: This doctor did not run bash tools/ai_validate.sh cloud-quick.",
  "NOT RUN: This doctor did not run bash tools/ai_validate.sh quick.",
  "NOT RUN: This doctor did not run bash tools/ai_validate.sh full --boot-smoke.",
  "NOT RUN: This doctor did not run MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke.",
  "NOT RUN: This doctor did not source tests/scripts/run_vm_preflight_real.R.",
  "NOT RUN: This doctor did not source tests/scripts/run_vm_encoding_preflight_real.R.",
  "NOT RUN: This doctor did not source tests/scripts/run_fragile_flow_manual_preflight.R.",
  "Use the listed commands as separate evidence gates; the doctor artifact is guidance, not validation evidence."
)

cat("Warning-only checks:\n")
for (item in warning_checks) {
  cat(sprintf(" - %s\n", item))
}
cat("\n")

cat("Doctor execution status:\n")
for (item in doctor_execution_notes) {
  cat(sprintf(" - %s\n", item))
}
cat("\n")

command_json <- vapply(seq_len(nrow(selected_paths)), function(i) {
  row <- selected_paths[i, ]

  paste0(
    "    {\n",
    sprintf("      \"id\": %s,\n", json_string(row$id)),
    sprintf("      \"command\": %s,\n", json_string(row$command)),
    sprintf("      \"proves\": %s,\n", json_string(row$proves)),
    sprintf("      \"does_not_prove\": %s,\n", json_string(row$does_not_prove)),
    sprintf("      \"blocking\": %s\n", json_string(row$blocking)),
    "    }"
  )
}, character(1))

env_json <- vapply(seq_len(nrow(env_summary)), function(i) {
  row <- env_summary[i, ]

  paste0(
    "    {\n",
    sprintf("      \"name\": %s,\n", json_string(row$name)),
    sprintf("      \"present\": %s,\n", json_bool(row$present)),
    sprintf("      \"nchar\": %d,\n", as.integer(row$nchar)),
    sprintf("      \"secret_like\": %s,\n", json_bool(row$secret_like)),
    sprintf(
      "      \"matches_windows_1254\": %s\n",
      if (is.na(row$matches_windows_1254)) "null" else json_bool(isTRUE(row$matches_windows_1254))
    ),
    "    }"
  )
}, character(1))

summary_json <- paste0(
  "{\n",
  sprintf("  \"generated_at\": %s,\n", json_string(format(Sys.time(), "%Y-%m-%d %H:%M:%S %z"))),
  sprintf("  \"profile\": %s,\n", json_string(profile)),
  sprintf("  \"repo_root\": %s,\n", json_string(repo_root)),
  sprintf("  \"environment_classification\": %s,\n", json_string(environment_class)),
  sprintf("  \"os_type\": %s,\n", json_string(.Platform$OS.type)),
  sprintf("  \"cloud_like\": %s,\n", json_bool(cloud_like)),
  sprintf("  \"windows_like\": %s,\n", json_bool(windows_like)),
  sprintf("  \"sso_like\": %s,\n", json_bool(sso_like)),
  sprintf("  \"vm_like\": %s,\n", json_bool(vm_like)),
  "  \"browser\": {\n",
  sprintf("    \"found\": %s,\n", json_bool(browser$found)),
  sprintf("    \"name\": %s,\n", json_string(browser$name)),
  sprintf("    \"source\": %s,\n", json_string(browser$source)),
  sprintf("    \"path_length\": %d\n", as.integer(browser$path_length)),
  "  },\n",
  "  \"environment\": [\n",
  paste(env_json, collapse = ",\n"),
  "\n  ],\n",
  "  \"commands\": [\n",
  paste(command_json, collapse = ",\n"),
  "\n  ],\n",
  sprintf("  \"blocking_checks\": %s,\n", json_array(blocking_checks)),
  sprintf("  \"warning_only_checks\": %s,\n", json_array(warning_checks)),
  sprintf("  \"doctor_runs_heavy_checks\": %s,\n", json_bool(FALSE)),
  sprintf("  \"validation_execution_status\": %s,\n", json_string("not_run_by_validation_doctor")),
  sprintf("  \"doctor_execution_notes\": %s\n", json_array(doctor_execution_notes)),
  "}\n"
)

writeLines(summary_json, summary_path, useBytes = TRUE)

cat(sprintf("OK: Validation doctor summary artifact written: %s\n", summary_path))
cat("OK: Bu betik ağır doğrulama çalıştırmadı; yalnızca doğrulama profili sınırlarını raporladı.\n")