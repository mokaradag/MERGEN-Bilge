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

read_failed_steps <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    return(NA_integer_)
  }

  txt <- read_utf8(path)
  hit <- regexpr("\"failed_steps\"\\s*:\\s*[0-9]+", txt, perl = TRUE)

  if (hit[1] < 0) return(NA_integer_)

  raw <- regmatches(txt, hit)
  as.integer(sub("^.*:\\s*", "", raw, perl = TRUE))
}

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