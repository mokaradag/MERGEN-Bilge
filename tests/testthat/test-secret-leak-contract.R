# ==============================================================================
# Dosya Yolu: tests/testthat/test-secret-leak-contract.R
# Açıklama: Repo içinde yanlışlıkla gerçek anahtar, token, bearer değeri veya
#           kişisel mutlak Windows yolu commit edilmesini engeller.
# ==============================================================================

.read_repo_text_secret_contract <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("repo gerçek API anahtarı veya bearer token içermiyor", {
  repo_root <- resolve_repo_root_for_tests()

  scan_files <- c(
    "app.R",
    "global.R",
    "ui.R",
    "server.R",
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "tests"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "js"), pattern = "\\.js$", recursive = TRUE, full.names = TRUE)
  )

  scan_files <- unique(normalizePath(
    scan_files[file.exists(scan_files)],
    winslash = "/",
    mustWork = FALSE
  ))

  forbidden_regex <- c(
    "sk-[A-Za-z0-9_-]{20,}",
    "Bearer\\s+[A-Za-z0-9._-]{30,}",
    "api[_-]?key\\s*=\\s*['\"][A-Za-z0-9._-]{24,}['\"]",
    "password\\s*=\\s*['\"][^'\"]{6,}['\"]",
    "secret\\s*=\\s*['\"][A-Za-z0-9._-]{16,}['\"]"
  )

  violations <- character(0)

  for (f in scan_files) {
    txt <- .read_repo_text_secret_contract(f)

    matched <- forbidden_regex[vapply(
      forbidden_regex,
      function(pattern) grepl(pattern, txt, perl = TRUE, ignore.case = TRUE, useBytes = TRUE),
      logical(1)
    )]

    if (length(matched) > 0) {
      rel <- sub(
        paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", repo_root), "/?"),
        "",
        f,
        perl = TRUE
      )

      violations <- c(violations, sprintf("%s -> %s", rel, paste(matched, collapse = ", ")))
    }
  }

  expect_equal(
    violations,
    character(0),
    info = paste(
      "Repo içinde olası secret/token bulundu:",
      paste(violations, collapse = "\n"),
      sep = "\n"
    )
  )
})

test_that("repo kişisel mutlak Windows kullanıcı yolu içermiyor", {
  repo_root <- resolve_repo_root_for_tests()

  scan_files <- c(
    "app.R",
    "global.R",
    "ui.R",
    "server.R",
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "tests"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  )

  scan_files <- unique(normalizePath(
    scan_files[file.exists(scan_files)],
    winslash = "/",
    mustWork = FALSE
  ))

  violations <- character(0)

  for (f in scan_files) {
    txt <- .read_repo_text_secret_contract(f)

    has_user_path <- grepl(
      "[A-Za-z]:/(Users|Kullanıcılar)/[^/[:space:]'\"]+",
      gsub("\\\\", "/", txt),
      perl = TRUE,
      ignore.case = TRUE,
      useBytes = TRUE
    )

    if (isTRUE(has_user_path)) {
      rel <- sub(
        paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", repo_root), "/?"),
        "",
        f,
        perl = TRUE
      )

      violations <- c(violations, rel)
    }
  }

  expect_equal(
    violations,
    character(0),
    info = paste(
      "Repo içinde kişisel mutlak Windows yolu bulundu:",
      paste(violations, collapse = "\n"),
      sep = "\n"
    )
  )
})