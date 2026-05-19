# ==============================================================================
# Dosya Yolu: tests/testthat/test-source-manifest-runtime-coverage.R
# Açıklama: Runtime R dosyalarının açık manifestten kaçmasını engeller.
# ==============================================================================

.manifest_coverage_repo_path <- function(paths) {
  repo_root <- normalizePath(resolve_repo_root_for_tests(), winslash = "/", mustWork = TRUE)
  repo_prefix <- paste0(repo_root, "/")
  normalized <- normalizePath(paths, winslash = "/", mustWork = TRUE)

  enc2utf8(ifelse(
    startsWith(normalized, repo_prefix),
    substring(normalized, nchar(repo_prefix) + 1L),
    normalized
  ))
}

.manifest_coverage_runtime_r_files <- function() {
  repo_root <- resolve_repo_root_for_tests()

  root_files <- file.path(
    repo_root,
    c("app.R", "global.R", "ui.R", "server.R", "welcome_screen.R")
  )

  r_files <- list.files(
    file.path(repo_root, "R"),
    pattern = "\\.R$",
    recursive = TRUE,
    full.names = TRUE
  )

  sort(unique(.manifest_coverage_repo_path(c(
    root_files[file.exists(root_files)],
    r_files
  ))))
}

.manifest_coverage_read <- function(path) {
  full_path <- file.path(resolve_repo_root_for_tests(), path)
  size <- suppressWarnings(file.info(full_path)$size[1])

  if (is.na(size) || size <= 0L) {
    return("")
  }

  con <- file(full_path, open = "rb")
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

.manifest_coverage_load_objects <- function() {
  repo_root <- resolve_repo_root_for_tests()
  manifest_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "bootstrap_source_manifest.R"),
    encoding = "UTF-8",
    local = manifest_env
  )

  source(
    file.path(repo_root, "R", "config_source_manifest.R"),
    encoding = "UTF-8",
    local = manifest_env
  )

  manifest_env
}

test_that("runtime R dosyaları manifestte veya açık boot allowlist içinde yer alır", {
  manifest_env <- .manifest_coverage_load_objects()
  runtime_files <- .manifest_coverage_runtime_r_files()
  manifest_paths <- get("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)

  boot_allowlist <- c(
    "app.R",
    "global.R",
    "ui.R",
    "server.R",
    "R/utils_safe_source.R",
    "R/bootstrap_source_manifest.R",
    "R/config_source_manifest.R"
  )

  missing_from_manifest <- setdiff(runtime_files, c(manifest_paths, boot_allowlist))

  expect_equal(
    missing_from_manifest,
    character(0),
    info = paste(
      "Manifest dışında kalan runtime R dosyaları:",
      paste(missing_from_manifest, collapse = ", ")
    )
  )
})

test_that("runtime helper dosyaları manifest dışı source veya safe_source çağırmaz", {
  runtime_files <- .manifest_coverage_runtime_r_files()

  approved_source_files <- c(
    "app.R",
    "global.R",
    "R/bootstrap_source_manifest.R",
    "R/utils_safe_source.R"
  )

  scanned_files <- setdiff(runtime_files, approved_source_files)
  direct_source_pattern <- "(^|[^A-Za-z0-9_.])(?:safe_source|source)\\s*\\("
  offenders <- character(0)

  for (path in scanned_files) {
    txt <- .manifest_coverage_read(path)
    txt_no_comments <- gsub("(?m)#.*$", "", txt, perl = TRUE)

    if (isTRUE(grepl(direct_source_pattern, txt_no_comments, perl = TRUE))) {
      offenders <- c(offenders, path)
    }
  }

  offenders <- sort(unique(offenders))

  expect_equal(
    offenders,
    character(0),
    info = paste(
      "Manifest dışı doğrudan source çağrısı bulunan runtime dosyaları:",
      paste(offenders, collapse = ", ")
    )
  )
})

test_that("source manifest sıra kuralları stale dosya yolu içermez", {
  manifest_env <- .manifest_coverage_load_objects()

  paths <- get("source_manifest_runtime_paths", envir = manifest_env, inherits = FALSE)
  rules <- get("source_manifest_required_order", envir = manifest_env, inherits = FALSE)

  boot_allowlist <- c(
    "app.R",
    "global.R",
    "ui.R",
    "server.R",
    "R/bootstrap_source_manifest.R",
    "R/config_source_manifest.R"
  )

  rule_paths <- unique(unlist(rules, use.names = FALSE))
  stale_paths <- setdiff(rule_paths, c(paths, boot_allowlist))

  expect_equal(
    stale_paths,
    character(0),
    info = paste(
      "Sıra kurallarında manifest/boot allowlist dışında kalan dosyalar:",
      paste(stale_paths, collapse = ", ")
    )
  )
})