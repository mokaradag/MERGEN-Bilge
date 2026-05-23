#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/ci_install_packages.R
# Açıklama:
#   GitHub Actions / Codex / AI agent ortamlarında R paketlerini kurar.
#   R/config_packages.R içindeki required_packages listesini statik olarak okur;
#   config_packages.R dosyasını source etmez, çünkü eksik paket varsa source işlemi
#   bilinçli olarak stop() üretir.
# ==============================================================================

options(warn = 1)

cat("== MERGEN CI package installer ==\n")

find_repo_root <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) &&
        dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("Repo root bulunamadı. Bu betiği repo içinde çalıştırın.", call. = FALSE)
}

repo_root <- find_repo_root()
setwd(repo_root)

config_path <- file.path(repo_root, "R", "config_packages.R")
if (!file.exists(config_path)) {
  stop("R/config_packages.R bulunamadı.", call. = FALSE)
}

read_utf8 <- function(path) {
  txt <- readLines(path, warn = FALSE, encoding = "UTF-8")
  paste(enc2utf8(txt), collapse = "\n")
}

extract_required_packages <- function(path) {
  txt <- read_utf8(path)

  hit <- regexpr(
    "required_packages\\s*<-\\s*c\\((.*?)\\)",
    txt,
    perl = TRUE
  )

  if (hit[1] < 0) {
    stop("required_packages <- c(...) bloğu bulunamadı.", call. = FALSE)
  }

  block <- regmatches(txt, hit)

  string_hits <- gregexpr(
    "\"[^\"]+\"|'[^']+'",
    block,
    perl = TRUE
  )[[1]]

  if (identical(string_hits[1], -1L)) {
    return(character(0))
  }

  values <- regmatches(block, list(string_hits))[[1]]
  values <- gsub("^['\"]|['\"]$", "", values, perl = TRUE)
  unique(values[nzchar(values)])
}

repo_packages <- extract_required_packages(config_path)

extra_ci_packages <- c(
  "testthat",
  "withr",
  "processx",
  "callr"
)

packages <- sort(unique(c(repo_packages, extra_ci_packages)))

cat(sprintf("Packages requested: %d\n", length(packages)))
cat(paste(packages, collapse = ", "), "\n\n")

repos <- Sys.getenv(
  "RSPM",
  unset = "https://cloud.r-project.org"
)

options(
  repos = c(CRAN = repos),
  install.packages.compile.from.source = "never"
)

Sys.setenv(
  LIBARROW_BINARY = "true",
  NOT_CRAN = "true"
)

lib <- .libPaths()[1]
dir.create(lib, recursive = TRUE, showWarnings = FALSE)

is_installed <- function(pkg) {
  requireNamespace(pkg, quietly = TRUE)
}

missing <- packages[!vapply(packages, is_installed, logical(1))]

if (length(missing) == 0L) {
  cat("OK: all packages already installed.\n")
  quit(status = 0)
}

cat(sprintf("Missing packages: %d\n", length(missing)))
cat(paste(missing, collapse = ", "), "\n\n")

install_one <- function(pkg) {
  cat(sprintf("\n--- Installing package: %s ---\n", pkg))

  ok <- FALSE
  last_error <- NULL

  for (attempt in seq_len(2L)) {
    cat(sprintf("Attempt %d for %s\n", attempt, pkg))

    tryCatch(
      {
        install.packages(pkg, dependencies = TRUE, lib = lib)
        ok <<- requireNamespace(pkg, quietly = TRUE)
      },
      error = function(e) {
        last_error <<- conditionMessage(e)
        ok <<- FALSE
      }
    )

    if (isTRUE(ok)) {
      cat(sprintf("OK: %s installed.\n", pkg))
      return(TRUE)
    }
  }

  cat(sprintf("FAILED: %s\n", pkg))
  if (!is.null(last_error)) {
    cat(sprintf("Last error: %s\n", last_error))
  }

  FALSE
}

results <- vapply(missing, install_one, logical(1))

still_missing <- packages[!vapply(packages, is_installed, logical(1))]

if (length(still_missing) > 0L) {
  cat("\nThe following packages are still missing:\n")
  cat(paste(still_missing, collapse = ", "), "\n")
  quit(status = 1)
}

cat("\nOK: all requested packages are installed and loadable.\n")
quit(status = 0)