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

  # (?s) DOTALL modu: required_packages <- c(...) bloğu birden fazla satıra yayılabilir.
  hit <- regexpr(
    "(?s)required_packages\\s*<-\\s*c\\((.*?)\\)",
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

# RSPM erişilemezse CRAN'a geri dön.
rspm_url <- Sys.getenv("RSPM", unset = "")
cran_url  <- "https://cloud.r-project.org"

repository_index_reachable <- function(repo_url) {
  probe_url <- paste0(repo_url, "/src/contrib/PACKAGES")

  ok <- tryCatch({
    con <- url(probe_url, open = "rt")
    on.exit(close(con), add = TRUE)
    first_line <- readLines(con, n = 1L, warn = FALSE)
    length(first_line) > 0L
  }, error = function(e) {
    cat(sprintf("Repository probe failed for %s: %s\n", repo_url, conditionMessage(e)))
    FALSE
  }, warning = function(w) {
    cat(sprintf("Repository probe warning for %s: %s\n", repo_url, conditionMessage(w)))
    FALSE
  })

  isTRUE(ok)
}

repos <- if (nzchar(rspm_url) && repository_index_reachable(rspm_url)) {
  cat(sprintf("RSPM erişilebilir: %s\n", rspm_url))
  rspm_url
} else if (repository_index_reachable(cran_url)) {
  if (nzchar(rspm_url)) {
    cat(sprintf("RSPM erişilemiyor (%s), CRAN kullanılıyor.\n", rspm_url))
  } else {
    cat(sprintf("CRAN kullanılıyor: %s\n", cran_url))
  }
  cran_url
} else {
  stop(
    sprintf(
      paste(
        "R paket deposuna erişilemiyor.",
        "Denenen RSPM: %s",
        "Denenen CRAN: %s",
        "Codex ortamında agent internet allowlist ayarlarını kontrol edin.",
        sep = "\n"
      ),
      if (nzchar(rspm_url)) rspm_url else "<unset>",
      cran_url
    ),
    call. = FALSE
  )
}

repo_is_linux_binary <- grepl("/__linux__/", repos, fixed = TRUE)

# Posit Package Manager Linux binary repositories are still consumed by R through
# install.packages() using source-style package type on Linux. Setting
# pkgType = "binary" on Linux can fail with:
#   type 'binary' is not supported on this platform
default_pkg_type <- "source"
pkg_type_env <- tolower(trimws(Sys.getenv("MERGEN_AI_R_PKG_TYPE", unset = "")))

if (nzchar(pkg_type_env) && pkg_type_env %in% c("source", "binary")) {
  pkg_type <- pkg_type_env
  cat(sprintf("Package type override from MERGEN_AI_R_PKG_TYPE: %s\n", pkg_type))
} else {
  pkg_type <- default_pkg_type
  if (nzchar(pkg_type_env)) {
    cat(sprintf("WARNING: Invalid MERGEN_AI_R_PKG_TYPE=%s. Falling back to %s.\n", pkg_type_env, default_pkg_type))
  }
}

cat(sprintf("Selected repository: %s\n", repos))
cat(sprintf("Selected package type: %s\n", pkg_type))

options(
  repos = c(CRAN = repos),
  pkgType = pkg_type,
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

skip_source_raw <- Sys.getenv("MERGEN_AI_SKIP_SOURCE_PACKAGES", unset = "")
skip_source_packages <- trimws(unlist(strsplit(skip_source_raw, ",", fixed = TRUE)))
skip_source_packages <- unique(skip_source_packages[nzchar(skip_source_packages)])

skipped_missing <- intersect(missing, skip_source_packages)
install_queue <- setdiff(missing, skipped_missing)

if (length(skipped_missing) > 0L) {
  cat("WARNING: Skipping heavy source packages for AI cloud bootstrap:\n")
  cat(paste(skipped_missing, collapse = ", "), "\n")
  cat("These packages remain required by the real app; this skip only affects AI validation bootstrap.\n\n")
}

if (length(missing) == 0L) {
  cat("OK: all packages already installed.\n")
  quit(status = 0)
}

cat(sprintf("Missing packages: %d\n", length(missing)))
cat(paste(missing, collapse = ", "), "\n\n")

cat(sprintf("Install queue after AI skip list: %d\n", length(install_queue)))
if (length(install_queue) > 0L) {
  cat(paste(install_queue, collapse = ", "), "\n\n")
}

install_one <- function(pkg) {
  cat(sprintf("\n--- Installing package: %s ---\n", pkg))

  ok <- FALSE
  last_error <- NULL

  for (attempt in seq_len(2L)) {
    cat(sprintf("Attempt %d for %s\n", attempt, pkg))

    tryCatch(
      {
		install.packages(
		  pkg,
		  dependencies = TRUE,
		  lib = lib,
		  type = getOption("pkgType", "source")
		)
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

results <- vapply(install_queue, install_one, logical(1))

still_missing <- packages[!vapply(packages, is_installed, logical(1))]
blocking_missing <- setdiff(still_missing, skipped_missing)

if (length(still_missing) > 0L) {
  cat("\nThe following packages are still missing:\n")
  cat(paste(still_missing, collapse = ", "), "\n")
}

if (length(blocking_missing) > 0L) {
  cat("\nThe following non-skipped packages are still missing:\n")
  cat(paste(blocking_missing, collapse = ", "), "\n")
  quit(status = 1)
}

if (length(skipped_missing) > 0L) {
  cat("\nOK with AI cloud skipped packages still missing:\n")
  cat(paste(skipped_missing, collapse = ", "), "\n")
}

cat("\nOK: all requested packages are installed and loadable.\n")
quit(status = 0)