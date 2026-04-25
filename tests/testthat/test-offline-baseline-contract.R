# ==============================================================================
# Dosya Yolu: tests/testthat/test-offline-baseline-contract.R
# Açıklama: Air-gapped Windows VM üretim ortamı için temel offline sözleşmeleri
#           varsayılan test koşumunda doğrular. Uygulamayı başlatmaz.
# ==============================================================================

.normalize_repo_path_for_offline_contract <- function(path) {
  repo_root <- normalizePath(
    resolve_repo_root_for_tests(),
    winslash = "/",
    mustWork = TRUE
  )

  candidate <- gsub("\\\\", "/", as.character(path)[1])

  if (grepl("^[A-Za-z]:/", candidate) || grepl("^/", candidate)) {
    return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
  }

  normalizePath(file.path(repo_root, candidate), winslash = "/", mustWork = FALSE)
}

.repo_relative_path_for_offline_contract <- function(path) {
  repo_root <- normalizePath(
    resolve_repo_root_for_tests(),
    winslash = "/",
    mustWork = TRUE
  )

  full_path <- .normalize_repo_path_for_offline_contract(path)
  sub(
    paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", repo_root), "/?"),
    "",
    full_path,
    perl = TRUE
  )
}

.read_repo_text_for_offline_contract <- function(path) {
  full_path <- .normalize_repo_path_for_offline_contract(path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  raw_data <- raw_data[raw_data != as.raw(0)]

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.contains_fixed_ignore_case_no_warning <- function(text, pattern) {
  text_norm <- tolower(enc2utf8(text %||% ""))
  pattern_norm <- tolower(enc2utf8(pattern %||% ""))

  grepl(
    pattern_norm,
    text_norm,
    fixed = TRUE,
    useBytes = TRUE
  )
}

test_that("runtime kodu varsayılan koşumda açık CDN/public asset bağımlılığı içermez", {
  repo_root <- normalizePath(
    resolve_repo_root_for_tests(),
    winslash = "/",
    mustWork = TRUE
  )

  runtime_files <- c(
    file.path(repo_root, "app.R"),
    file.path(repo_root, "global.R"),
    file.path(repo_root, "ui.R"),
    file.path(repo_root, "server.R"),
    file.path(repo_root, "welcome_screen.R"),
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "js"), pattern = "\\.js$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "css"), pattern = "\\.css$", recursive = TRUE, full.names = TRUE)
  )

  runtime_files <- unique(normalizePath(
    runtime_files[file.exists(runtime_files)],
    winslash = "/",
    mustWork = FALSE
  ))

  banned_patterns <- c(
    "cdn.jsdelivr.net",
    "cdnjs.cloudflare.com",
    "unpkg.com",
    "fonts.googleapis.com",
    "fonts.gstatic.com",
    "maxcdn.bootstrapcdn.com",
    "stackpath.bootstrapcdn.com",
    "raw.githubusercontent.com",
    "code.jquery.com"
  )

  violations <- character(0)

  for (full_path in runtime_files) {
    rel_path <- .repo_relative_path_for_offline_contract(full_path)
    txt <- .read_repo_text_for_offline_contract(full_path)

    matched <- banned_patterns[vapply(
      banned_patterns,
      function(pattern) .contains_fixed_ignore_case_no_warning(txt, pattern),
      logical(1)
    )]

    if (length(matched) > 0) {
      violations <- c(
        violations,
        sprintf("%s -> %s", rel_path, paste(matched, collapse = ", "))
      )
    }
  }

  expect_equal(
    violations,
    character(0),
    info = paste(
      "Offline üretim sözleşmesi ihlali: runtime dosyalarında dış asset/CDN bağımlılığı bulundu.",
      paste(violations, collapse = "\n"),
      sep = "\n"
    )
  )
})

test_that("testthat ana koşumu strict offline testleri yanlışlıkla zorunlu hale getirmez", {
  runner_text <- .read_repo_text_for_offline_contract("tests/testthat.R")

  expect_false(
    grepl("MERGEN_STRICT_OFFLINE_TESTS", runner_text, fixed = TRUE, useBytes = TRUE),
    info = paste(
      "tests/testthat.R içinde MERGEN_STRICT_OFFLINE_TESTS zorlanmamalı.",
      "Geniş offline tarama opsiyonel kalmalı; temel CDN yasağı ayrı testte zaten çalışıyor."
    )
  )
})