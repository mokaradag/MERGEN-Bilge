#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/ai_answer_check.R
# Açıklama:
#   Bir AI cevabı gönderilmeden önce temel doğrulama yapar:
#   - Cevapta geçen repo dosya yolları var mı?
#   - testthat::test_file("...") yolları var mı?
#   - Rscript komutları gerçek dosyalara mı işaret ediyor?
#   - R kod blokları parse ediliyor mu?
#   - Tehlikeli shell komutları önerilmiş mi?
#   - "testler geçti" iddiası, validation summary ile çelişiyor mu?
# ==============================================================================

options(warn = 1)

args <- commandArgs(trailingOnly = TRUE)

arg_value <- function(name, default = NULL) {
  prefix <- paste0(name, "=")
  direct <- args[startsWith(args, prefix)]
  if (length(direct) > 0L) return(sub(prefix, "", direct[[1]], fixed = TRUE))

  pos <- match(name, args)
  if (!is.na(pos) && pos < length(args)) return(args[[pos + 1L]])

  default
}

has_flag <- function(name) {
  name %in% args
}

answer_path <- arg_value("--answer", ".ai/proposed_answer.md")
summary_path <- arg_value("--summary", NULL)
strict_paths <- has_flag("--strict-paths")

find_repo_root <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("Repo root bulunamadı.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)

if (!file.exists(answer_path)) {
  stop(sprintf("Answer file bulunamadı: %s", answer_path), call. = FALSE)
}

read_utf8 <- function(path) {
  txt <- readLines(path, warn = FALSE, encoding = "UTF-8")
  paste(enc2utf8(txt), collapse = "\n")
}

answer <- read_utf8(answer_path)

errors <- character(0)
warnings <- character(0)

add_error <- function(...) {
  errors <<- c(errors, sprintf(...))
}

add_warning <- function(...) {
  warnings <<- c(warnings, sprintf(...))
}

cat("== MERGEN AI answer self-check ==\n")
cat(sprintf("Repo root: %s\n", repo_root))
cat(sprintf("Answer: %s\n", answer_path))
cat(sprintf("Strict paths: %s\n", strict_paths))
if (!is.null(summary_path)) {
  cat(sprintf("Summary: %s\n", summary_path))
}
cat("\n")

parse_fences <- function(text) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  fences <- list()

  in_fence <- FALSE
  lang <- ""
  buf <- character(0)
  start_line <- NA_integer_

  for (i in seq_along(lines)) {
    line <- lines[[i]]
    trimmed <- trimws(line)

    if (!in_fence && startsWith(trimmed, "```")) {
      in_fence <- TRUE
      lang <- trimws(sub("^```\\s*", "", trimmed))
      lang <- sub("\\s.*$", "", lang)
      buf <- character(0)
      start_line <- i
      next
    }

    if (in_fence && startsWith(trimmed, "```")) {
      fences[[length(fences) + 1L]] <- list(
        lang = tolower(lang),
        content = paste(buf, collapse = "\n"),
        start_line = start_line,
        end_line = i
      )
      in_fence <- FALSE
      lang <- ""
      buf <- character(0)
      start_line <- NA_integer_
      next
    }

    if (in_fence) {
      buf <- c(buf, line)
    }
  }

  if (in_fence) {
    add_error("Unclosed code fence starting at line %s.", as.character(start_line))
  }

  fences
}

fences <- parse_fences(answer)

r_langs <- c("r", "rscript")
shell_langs <- c("bash", "sh", "shell", "zsh", "powershell", "ps1", "cmd", "bat")

for (f in fences) {
  if (f$lang %in% r_langs) {
    parsed <- tryCatch(
      {
        parse(text = f$content, keep.source = FALSE)
        TRUE
      },
      error = function(e) {
        add_error(
          "R code fence at lines %d-%d does not parse: %s",
          f$start_line,
          f$end_line,
          conditionMessage(e)
        )
        FALSE
      }
    )
  }

  if (f$lang %in% shell_langs) {
    risky_patterns <- c(
      "rm\\s+-rf\\s+/",
      "rm\\s+-rf\\s+\\$\\{?HOME\\}?",
      "git\\s+push\\s+--force",
      "DROP\\s+TABLE",
      "TRUNCATE\\s+TABLE",
      "DELETE\\s+FROM\\s+MB_",
      "MERGEN_REPAIR_MOJIBAKE_APPLY\\s*=\\s*TRUE",
      "MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE\\s*=\\s*TRUE"
    )

    for (pat in risky_patterns) {
      if (grepl(pat, f$content, ignore.case = TRUE, perl = TRUE)) {
        add_error(
          "Potentially dangerous shell command in fence lines %d-%d: pattern `%s`.",
          f$start_line,
          f$end_line,
          pat
        )
      }
    }
  }
}

tokens <- unique(unlist(strsplit(
  answer,
  "[[:space:]`'\"()\\[\\]{}<>,:;]+",
  perl = TRUE
)))

tokens <- tokens[nzchar(tokens)]
tokens <- gsub("\\.$", "", tokens, perl = TRUE)
tokens <- gsub("^\\./", "", tokens, perl = TRUE)

path_like <- tokens[
  grepl("\\.(R|r|js|css|md|yml|yaml|json|sql|html|txt|csv|xlsx|docx|pdf)$", tokens, perl = TRUE) |
    grepl("/", tokens, fixed = TRUE)
]

path_like <- path_like[
  !grepl("^https?://", path_like, ignore.case = TRUE) &
    !grepl("^sandbox:", path_like, ignore.case = TRUE) &
    !grepl("^mailto:", path_like, ignore.case = TRUE) &
    !grepl("^#|^--", path_like)
]

path_like <- unique(path_like)

existing <- character(0)
missing <- character(0)

for (p in path_like) {
  normalized <- p
  normalized <- sub("^repo/", "", normalized)
  normalized <- sub("^MERGEN-Bilge/", "", normalized)

  if (file.exists(normalized) || dir.exists(normalized)) {
    existing <- c(existing, p)
  } else {
    missing <- c(missing, p)
  }
}

if (length(missing) > 0L) {
  msg <- paste(
    "Answer mentions paths that do not currently exist:",
    paste(missing, collapse = ", ")
  )

  if (isTRUE(strict_paths)) {
    add_error("%s", msg)
  } else {
    add_warning("%s", msg)
  }
}

extract_test_file_paths <- function(text) {
  hits <- gregexpr(
    "testthat::test_file\\s*\\(\\s*['\"][^'\"]+['\"]",
    text,
    perl = TRUE
  )[[1]]

  if (identical(hits[1], -1L)) return(character(0))

  raw <- regmatches(text, list(hits))[[1]]
  raw <- sub("^.*test_file\\s*\\(\\s*['\"]", "", raw, perl = TRUE)
  raw <- sub("['\"]$", "", raw, perl = TRUE)
  unique(raw)
}

test_paths <- extract_test_file_paths(answer)
missing_tests <- test_paths[!file.exists(test_paths)]

if (length(missing_tests) > 0L) {
  add_error(
    "Answer recommends testthat::test_file() for missing files: %s",
    paste(missing_tests, collapse = ", ")
  )
}

extract_rscript_paths <- function(text) {
  hits <- gregexpr(
    "Rscript\\s+[^\\s`'\"]+",
    text,
    perl = TRUE
  )[[1]]

  if (identical(hits[1], -1L)) return(character(0))

  raw <- regmatches(text, list(hits))[[1]]
  raw <- sub("^Rscript\\s+", "", raw, perl = TRUE)
  raw <- raw[grepl("\\.(R|r)$", raw, perl = TRUE)]
  unique(raw)
}

rscript_paths <- extract_rscript_paths(answer)
missing_rscript <- rscript_paths[!file.exists(rscript_paths)]

if (length(missing_rscript) > 0L) {
  add_error(
    "Answer recommends Rscript commands for missing files: %s",
    paste(missing_rscript, collapse = ", ")
  )
}

claims_tests_passed <- grepl(
  paste(
    "tests?\\s+(passed|pass|green)",
    "all\\s+checks\\s+(passed|pass|green)",
    "testler\\s+(geçti|başarılı)",
    "kontroller\\s+(geçti|başarılı)",
    "I\\s+ran\\s+the\\s+tests",
    "testleri\\s+çalıştırdım",
    sep = "|"
  ),
  answer,
  ignore.case = TRUE,
  perl = TRUE
)

read_summary_text <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    return("")
  }

  read_utf8(path)
}

summary_text <- read_summary_text(summary_path)

summary_value_for_message <- function(value) {
  if (length(value) == 0L || is.na(value[1])) {
    return("<missing>")
  }

  as.character(value[1])
}

read_summary_string_field <- function(text, field) {
  if (!nzchar(text)) {
    return(NA_character_)
  }

  pattern <- sprintf('"%s"\\s*:\\s*(null|"(?:\\\\.|[^"\\\\])*")', field)
  hit <- regexpr(pattern, text, perl = TRUE)

  if (hit[1] < 0) {
    return(NA_character_)
  }

  raw <- regmatches(text, hit)
  value <- sub(sprintf('^"%s"\\s*:\\s*', field), "", raw, perl = TRUE)

  if (identical(value, "null")) {
    return(NA_character_)
  }

  value <- sub('^"', "", value)
  value <- sub('"$', "", value)
  value <- gsub("\\\\n", "\n", value, fixed = TRUE)
  value <- gsub("\\\\r", "\r", value, fixed = TRUE)
  value <- gsub("\\\\t", "\t", value, fixed = TRUE)
  value <- gsub("\\\\\"", "\"", value, fixed = TRUE)
  value <- gsub("\\\\\\\\", "\\\\", value, fixed = TRUE)

  enc2utf8(value)
}

read_summary_bool_field <- function(text, field) {
  if (!nzchar(text)) {
    return(NA)
  }

  pattern <- sprintf('"%s"\\s*:\\s*(true|false)', field)
  hit <- regexpr(pattern, text, perl = TRUE)

  if (hit[1] < 0) {
    return(NA)
  }

  raw <- regmatches(text, hit)
  value <- sub(sprintf('^"%s"\\s*:\\s*', field), "", raw, perl = TRUE)
  identical(value, "true")
}

summary_string_or <- function(value, fallback) {
  if (length(value) == 0L || is.na(value[1])) {
    return(fallback)
  }

  as.character(value[1])
}

read_failed_steps <- function(path) {
  txt <- if (identical(path, summary_path)) {
    summary_text
  } else {
    read_summary_text(path)
  }

  if (!nzchar(txt)) {
    return(NA_integer_)
  }

  hit <- regexpr("\"failed_steps\"\\s*:\\s*[0-9]+", txt, perl = TRUE)

  if (hit[1] < 0) return(NA_integer_)

  raw <- regmatches(txt, hit)
  as.integer(sub("^.*:\\s*", "", raw, perl = TRUE))
}

claim_matches <- function(...) {
  grepl(
    paste(c(...), collapse = "|"),
    answer,
    ignore.case = TRUE,
    perl = TRUE
  )
}

validation_pass_words_en <- "passed|pass|green|successful|succeeded|completed"
validation_pass_words_tr <- "geçti|başarılı|tamamlandı"
validation_pass_words <- paste(validation_pass_words_en, validation_pass_words_tr, sep = "|")

claims_full_validation_passed <- claim_matches(
  sprintf("full\\s+validation\\s+(%s)", validation_pass_words_en),
  sprintf("full\\s+profile\\s+(%s)", validation_pass_words_en),
  sprintf("tam\\s+doğrulama\\s+(%s)", validation_pass_words_tr),
  sprintf("full\\s+doğrulama\\s+(%s)", validation_pass_words_tr)
)

claims_cloud_quick_passed <- claim_matches(
  sprintf("cloud-quick\\s+(%s)", validation_pass_words),
  sprintf("cloud\\s+quick\\s+(%s)", validation_pass_words)
)

claims_quick_validation_passed <- claim_matches(
  sprintf("quick\\s+validation\\s+(%s)", validation_pass_words_en),
  sprintf("quick\\s+repo\\s+validation\\s+(%s)", validation_pass_words_en),
  sprintf("quick\\s+doğrulama\\s+(%s)", validation_pass_words_tr)
)

claims_app_source_smoke_passed <- claim_matches(
  sprintf("app\\s+source\\s+smoke\\s+(%s)", validation_pass_words),
  sprintf("app\\s+source\\s+smoke.{0,40}(%s)", validation_pass_words)
)

claims_boot_smoke_passed <- claim_matches(
  sprintf("(shiny\\s+boot|app\\s+boot|boot)\\s+smoke\\s+(%s)", validation_pass_words),
  sprintf("(shiny\\s+boot|app\\s+boot|boot)\\s+smoke.{0,40}(%s)", validation_pass_words)
)

claims_browser_smoke_passed <- claim_matches(
  sprintf("browser\\s+UX\\s+smoke\\s+(%s)", validation_pass_words),
  sprintf("browser\\s+UX\\s+smoke.{0,40}(%s)", validation_pass_words)
)

claims_vm_sso_db_passed <- claim_matches(
  sprintf("(VM|SSO|DB).{0,40}(preflight|validation|doğrulama).{0,40}(%s)", validation_pass_words),
  sprintf("run_vm_preflight_real\\.R.{0,80}(%s)", validation_pass_words)
)

claims_sql_encoding_passed <- claim_matches(
  sprintf("(SQL Server|Turkish encoding|Türkçe kodlama|encoding preflight).{0,80}(%s)", validation_pass_words),
  sprintf("run_vm_encoding_preflight_real\\.R.{0,80}(%s)", validation_pass_words)
)

claims_manual_fragile_flow_passed <- claim_matches(
  sprintf("(manual fragile-flow|fragile-flow|manual fragile flow|manuel kırılgan akış|kırılgan akış).{0,80}(%s)", validation_pass_words),
  sprintf("run_fragile_flow_manual_preflight\\.R.{0,80}(%s)", validation_pass_words)
)

claims_all_validation_passed <- claim_matches(
  sprintf("(all|complete|entire)\\s+(validation|validations|checks|tests?|gates?)\\s+(%s)", validation_pass_words_en),
  sprintf("(everything|all)\\s+(%s)", validation_pass_words_en),
  sprintf("tüm\\s+(doğrulama|kontrol|test|kapılar)\\s+(%s)", validation_pass_words_tr),
  sprintf("hepsi\\s+(%s)", validation_pass_words_tr)
)

claims_validation_doctor_passed <- claim_matches(
  sprintf("validation\\s+doctor\\s+(%s)", validation_pass_words_en),
  sprintf("doğrulama\\s+doktoru\\s+(%s)", validation_pass_words_tr)
)

specific_validation_claim <- any(c(
  claims_full_validation_passed,
  claims_cloud_quick_passed,
  claims_quick_validation_passed,
  claims_app_source_smoke_passed,
  claims_boot_smoke_passed,
  claims_browser_smoke_passed,
  claims_vm_sso_db_passed,
  claims_sql_encoding_passed,
  claims_manual_fragile_flow_passed,
  claims_all_validation_passed,
  claims_validation_doctor_passed
))

summary_profile_requested <- read_summary_string_field(summary_text, "profile_requested")
summary_profile_effective <- read_summary_string_field(summary_text, "profile_effective")

if (is.na(summary_profile_requested)) {
  summary_profile_requested <- read_summary_string_field(summary_text, "profile")
}

if (is.na(summary_profile_effective)) {
  summary_profile_effective <- read_summary_string_field(summary_text, "profile")
}

summary_execution_status <- read_summary_string_field(
  summary_text,
  "validation_execution_status"
)
summary_app_source_status <- read_summary_string_field(
  summary_text,
  "app_source_smoke_status"
)
summary_boot_status <- read_summary_string_field(
  summary_text,
  "shiny_boot_smoke_status"
)
summary_browser_status <- read_summary_string_field(
  summary_text,
  "browser_smoke_status"
)
summary_vm_sso_status <- read_summary_string_field(
  summary_text,
  "vm_sso_preflight_status"
)
summary_sql_encoding_status <- read_summary_string_field(
  summary_text,
  "sql_server_turkish_encoding_preflight_status"
)
summary_browser_required <- read_summary_bool_field(
  summary_text,
  "browser_required"
)
summary_cloud_quick_validation_status <- read_summary_string_field(
  summary_text,
  "cloud_quick_validation_status"
)
summary_quick_repo_validation_status <- read_summary_string_field(
  summary_text,
  "quick_repo_validation_status"
)
summary_full_validation_status <- read_summary_string_field(
  summary_text,
  "full_validation_status"
)
summary_app_boot_status <- summary_string_or(
  read_summary_string_field(summary_text, "app_boot_smoke_status"),
  summary_boot_status
)
summary_browser_ux_status <- summary_string_or(
  read_summary_string_field(summary_text, "browser_ux_smoke_status"),
  summary_browser_status
)
summary_db_sso_vm_status <- summary_string_or(
  read_summary_string_field(summary_text, "db_sso_vm_validation_status"),
  summary_vm_sso_status
)
summary_sql_encoding_validation_status <- summary_string_or(
  read_summary_string_field(summary_text, "sql_server_turkish_encoding_validation_status"),
  summary_sql_encoding_status
)
summary_manual_fragile_flow_status <- read_summary_string_field(
  summary_text,
  "manual_fragile_flow_validation_status"
)

if (isTRUE(claims_tests_passed)) {
  failed_steps <- read_failed_steps(summary_path)

  if (is.na(failed_steps)) {
    add_warning(
      "Answer appears to claim tests/checks were run or passed, but no readable summary.json was provided."
    )
  } else if (failed_steps > 0L) {
    add_error(
      "Answer appears to claim tests/checks passed, but summary.json has failed_steps=%d.",
      failed_steps
    )
  }
}

if (isTRUE(claims_validation_doctor_passed)) {
  add_error(
    paste(
      "Answer treats validation doctor output as a pass/fail gate.",
      "validation_doctor is guidance only; cite it only as guidance, not execution proof."
    )
  )
}

if (isTRUE(specific_validation_claim) && !nzchar(summary_text)) {
  add_error(
    "Answer makes specific validation proof claims, but no readable summary.json was provided."
  )
}

if (nzchar(summary_text)) {
  failed_steps <- read_failed_steps(summary_path)

  if (identical(summary_execution_status, "not_run_by_validation_doctor") &&
      isTRUE(specific_validation_claim)) {
    add_error(
      "Answer appears to use validation doctor guidance as execution proof. validation_execution_status=%s.",
      summary_value_for_message(summary_execution_status)
    )
  }

  if (isTRUE(claims_all_validation_passed)) {
    aggregate_required_statuses <- c(
      full_validation = summary_full_validation_status,
      app_source_smoke = summary_app_source_status,
      app_boot_smoke = summary_app_boot_status,
      browser_ux_smoke = summary_browser_ux_status,
      db_sso_vm_validation = summary_db_sso_vm_status,
      sql_server_turkish_encoding = summary_sql_encoding_validation_status,
      manual_fragile_flow = summary_manual_fragile_flow_status
    )

    not_passed <- aggregate_required_statuses[
      !(aggregate_required_statuses %in% "passed")
    ]

    if (length(not_passed) > 0L) {
      add_error(
        "Answer claims all validation gates passed, but not all proof gates are passed: %s.",
        paste(
          sprintf(
            "%s=%s",
            names(not_passed),
            vapply(not_passed, summary_value_for_message, character(1))
          ),
          collapse = ", "
        )
      )
    }
  }

  if (isTRUE(claims_full_validation_passed) &&
      !identical(summary_full_validation_status, "passed")) {
    add_error(
      paste(
        "Answer claims full validation passed, but summary",
        "full_validation_status=%s profile_requested=%s profile_effective=%s."
      ),
      summary_value_for_message(summary_full_validation_status),
      summary_value_for_message(summary_profile_requested),
      summary_value_for_message(summary_profile_effective)
    )
  }

  if (isTRUE(claims_cloud_quick_passed) &&
      !identical(summary_cloud_quick_validation_status, "passed")) {
    add_error(
      paste(
        "Answer claims cloud-quick passed, but summary",
        "cloud_quick_validation_status=%s profile_requested=%s profile_effective=%s."
      ),
      summary_value_for_message(summary_cloud_quick_validation_status),
      summary_value_for_message(summary_profile_requested),
      summary_value_for_message(summary_profile_effective)
    )
  }

  if (isTRUE(claims_quick_validation_passed) &&
      !identical(summary_quick_repo_validation_status, "passed")) {
    add_error(
      paste(
        "Answer claims quick validation passed, but summary",
        "quick_repo_validation_status=%s profile_requested=%s profile_effective=%s."
      ),
      summary_value_for_message(summary_quick_repo_validation_status),
      summary_value_for_message(summary_profile_requested),
      summary_value_for_message(summary_profile_effective)
    )
  }

  if (isTRUE(claims_app_source_smoke_passed) &&
      !identical(summary_app_source_status, "passed")) {
    add_error(
      "Answer claims app source smoke passed, but summary app_source_smoke_status=%s.",
      summary_value_for_message(summary_app_source_status)
    )
  }

  if (isTRUE(claims_boot_smoke_passed) &&
      !identical(summary_app_boot_status, "passed")) {
    add_error(
      "Answer claims boot smoke passed, but summary app_boot_smoke_status=%s.",
      summary_value_for_message(summary_app_boot_status)
    )
  }

  if (isTRUE(claims_browser_smoke_passed) &&
      !identical(summary_browser_ux_status, "passed")) {
    add_error(
      paste(
        "Answer claims browser UX smoke passed, but summary",
        "browser_ux_smoke_status=%s browser_required=%s."
      ),
      summary_value_for_message(summary_browser_ux_status),
      summary_value_for_message(summary_browser_required)
    )
  }

  if (isTRUE(claims_vm_sso_db_passed) &&
      !identical(summary_db_sso_vm_status, "passed")) {
    add_error(
      "Answer claims VM/SSO/DB preflight passed, but summary db_sso_vm_validation_status=%s.",
      summary_value_for_message(summary_db_sso_vm_status)
    )
  }

  if (isTRUE(claims_sql_encoding_passed) &&
      !identical(summary_sql_encoding_validation_status, "passed")) {
    add_error(
      paste(
        "Answer claims SQL Server Turkish encoding preflight passed, but summary",
        "sql_server_turkish_encoding_validation_status=%s."
      ),
      summary_value_for_message(summary_sql_encoding_validation_status)
    )
  }

  if (isTRUE(claims_manual_fragile_flow_passed) &&
      !identical(summary_manual_fragile_flow_status, "passed")) {
    add_error(
      "Answer claims manual fragile-flow evidence passed, but summary manual_fragile_flow_validation_status=%s.",
      summary_value_for_message(summary_manual_fragile_flow_status)
    )
  }

  if (!is.na(failed_steps) && failed_steps > 0L && isTRUE(specific_validation_claim)) {
    add_error(
      "Answer makes specific validation pass claims, but summary.json has failed_steps=%d.",
      failed_steps
    )
  }
}

if (length(warnings) > 0L) {
  cat("\nWarnings:\n")
  for (w in warnings) {
    cat(sprintf("  - %s\n", w))
  }
}

if (length(errors) > 0L) {
  cat("\nErrors:\n")
  for (e in errors) {
    cat(sprintf("  - %s\n", e))
  }
  quit(status = 1)
}

cat("\nOK: answer self-check passed.\n")
if (length(warnings) > 0L) {
  cat("Note: warnings were present; review them before sending the answer.\n")
}
quit(status = 0)