#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/frontend_complexity_doctor.R
# Açıklama:
#   Frontend bakım raporundaki en riskli JS/CSS yoğunluklarını, manifest dışı
#   runtime varlıkları ve smoke-only varlık ayrımını insan-okur ve JSON artifact
#   olarak özetler.
#
#   Bu script runtime UX'i değiştirmez; uygulamayı, tarayıcıyı, DB'yi veya
#   harici bağımlılıkları başlatmaz.
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

find_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(".", "..", "../..", "../../.."),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "www")) &&
        dir.exists(file.path(candidate, "tests", "scripts"))) {
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

json_data_frame <- function(data) {
  if (is.null(data) || nrow(data) == 0L) {
    return("[]")
  }

  rows <- lapply(seq_len(nrow(data)), function(index) {
    row <- lapply(data[index, , drop = FALSE], function(value) {
      if (length(value) == 0L) {
        return("")
      }

      value[[1]]
    })

    json_object(row)
  })

  paste0("[\n", paste(rows, collapse = ",\n"), "\n]")
}

json_vector <- function(x) {
  if (length(x) == 0L) {
    return("[]")
  }

  paste0(
    "[",
    paste(vapply(x, json_value, character(1)), collapse = ","),
    "]"
  )
}

json_object <- function(x) {
  if (length(x) == 0L) {
    return("{}")
  }

  item_names <- names(x)

  if (is.null(item_names) || any(!nzchar(item_names))) {
    return(json_vector(x))
  }

  items <- vapply(seq_along(x), function(index) {
    sprintf(
      "%s:%s",
      json_string(item_names[[index]]),
      json_value(x[[index]])
    )
  }, character(1))

  paste0("{", paste(items, collapse = ","), "}")
}

json_value <- function(x) {
  if (is.null(x)) {
    return("null")
  }

  if (is.data.frame(x)) {
    return(json_data_frame(x))
  }

  if (is.list(x)) {
    return(json_object(x))
  }

  if (is.logical(x)) {
    if (length(x) != 1L) {
      return(json_vector(x))
    }

    if (is.na(x)) {
      return("null")
    }

    return(if (isTRUE(x)) "true" else "false")
  }

  if (is.numeric(x) || is.integer(x)) {
    if (length(x) != 1L) {
      return(json_vector(x))
    }

    if (is.na(x) || !is.finite(x)) {
      return("null")
    }

    return(as.character(x))
  }

  if (length(x) != 1L) {
    return(json_vector(x))
  }

  if (is.na(x)) {
    return("null")
  }

  json_string(x)
}

print_section <- function(title, value, n = 12L) {
  cat(sprintf("\n-- %s --\n", title))

  if (is.null(value) || nrow(value) == 0L) {
    cat("(yok)\n")
    return(invisible(NULL))
  }

  print(utils::head(value, n), row.names = FALSE)
  invisible(NULL)
}

repo_root <- find_repo_root()
setwd(repo_root)

artifact_root_arg <- arg_value(
  "--artifact-root",
  file.path("artifacts", "frontend-complexity-doctor")
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
  sprintf("frontend-complexity-doctor-%s.json", timestamp)
)

report_env <- new.env(parent = globalenv())
report <- source(
  "tests/scripts/frontend_maintainability_report.R",
  encoding = "UTF-8",
  local = report_env
)$value

top_risk_summary <- attr(report, "top_risk_summary", exact = TRUE)

if (!is.list(top_risk_summary)) {
  stop(
    "frontend_maintainability_report.R top_risk_summary attribute üretmelidir.",
    call. = FALSE
  )
}

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

missing_sections <- setdiff(required_sections, names(top_risk_summary))

if (length(missing_sections) > 0L) {
  stop(
    "Frontend top-risk summary eksik bölümler içeriyor: ",
    paste(missing_sections, collapse = ", "),
    call. = FALSE
  )
}

cat("== MERGEN frontend complexity doctor ==\n")
cat("Frontend top-risk summary\n")
cat("Runtime/app/browser/DB başlatılmaz.\n")
cat("Secret policy: value=<not-collected>; ortam değişkenlerinin ham değerleri yazılmaz.\n")

print_section("Top app-owned JS by lines", top_risk_summary$largest_js)
print_section("Top app-owned CSS by lines", top_risk_summary$largest_css)
print_section("Top app-owned JS by function count", top_risk_summary$highest_function_js)
print_section("Top app-owned JS by event/handler count", top_risk_summary$highest_event_handler_js)
print_section("Top app-owned JS by Shiny handler count", top_risk_summary$highest_shiny_handler_js)
print_section("Duplicate CSS selectors", top_risk_summary$duplicate_css_selectors, n = 25L)
print_section("Legacy selector hits", top_risk_summary$legacy_selector_hits)
print_section("Unmanifested app-owned runtime assets", top_risk_summary$unmanifested_app_assets)
print_section("Allowlisted unmanifested assets", top_risk_summary$allowlisted_unmanifested_assets)
print_section("Smoke-only assets", top_risk_summary$smoke_only_assets)

payload <- list(
  generated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  source_report = "tests/scripts/frontend_maintainability_report.R",
  doctor_script = "tests/scripts/frontend_complexity_doctor.R",
  doctor_runs_runtime = FALSE,
  doctor_runs_browser = FALSE,
  doctor_runs_database = FALSE,
  secret_policy = "value=<not-collected>; no raw environment values are written",
  top_risk = top_risk_summary
)

writeLines(
  json_value(payload),
  con = summary_path,
  useBytes = TRUE
)

cat(sprintf("\nFrontend complexity artifact: %s\n", summary_path))

invisible(payload)