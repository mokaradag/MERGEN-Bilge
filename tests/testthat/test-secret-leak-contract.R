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

.normalize_path_secret_contract <- function(path) {
  out <- normalizePath(path, winslash = "/", mustWork = FALSE)
  gsub("\\\\", "/", out)
}

.repo_relative_secret_contract <- function(repo_root, path) {
  repo_root_norm <- .normalize_path_secret_contract(repo_root)
  path_norm <- .normalize_path_secret_contract(path)

  escaped_root <- gsub(
    "([\\^$.|?*+(){}\\[\\]\\\\])",
    "\\\\\\1",
    repo_root_norm
  )

  sub(
    paste0("^", escaped_root, "/?"),
    "",
    path_norm,
    perl = TRUE
  )
}

.is_allowed_secret_fixture_file <- function(rel_path) {
  rel_norm <- gsub("\\\\", "/", rel_path)
  rel_norm <- sub("^/+", "", rel_norm)

  identical(rel_norm, "tests/testthat/test-config-logging-redaction.R") ||
    grepl("/tests/testthat/test-config-logging-redaction\\.R$", rel_norm, perl = TRUE)
}

.strip_allowed_secret_fixtures <- function(text, rel_path) {
  # Bu dosya gerçek secret sızıntısını değil, log redaction davranışını test eder.
  # İçindeki sahte değerler bilerek uzun tutulmuştur. UNC / network path altında
  # relative path çözümü farklı dönebildiği için hem exact hem suffix kontrolü
  # kullanılır.
  if (.is_allowed_secret_fixture_file(rel_path)) {
    text <- gsub(
      "supersekretkey_abcdef1234",
      "<allowed-redaction-fixture>",
      text,
      fixed = TRUE
    )
    text <- gsub(
      "abc123def456ghi789",
      "<allowed-redaction-fixture>",
      text,
      fixed = TRUE
    )
    text <- gsub(
      "gizli_anahtar_123",
      "<allowed-redaction-fixture>",
      text,
      fixed = TRUE
    )
  }

  text
}

test_that("repo gerçek API anahtarı veya bearer token içermiyor", {
  repo_root <- resolve_repo_root_for_tests()

  scan_files <- c(
    file.path(repo_root, "app.R"),
    file.path(repo_root, "global.R"),
    file.path(repo_root, "ui.R"),
    file.path(repo_root, "server.R"),
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "tests"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "www", "js"), pattern = "\\.js$", recursive = TRUE, full.names = TRUE)
  )

  scan_files <- unique(.normalize_path_secret_contract(
    scan_files[file.exists(scan_files)]
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
    rel <- .repo_relative_secret_contract(repo_root, f)
    txt <- .read_repo_text_secret_contract(f)
    txt <- .strip_allowed_secret_fixtures(txt, rel)

    matched <- forbidden_regex[vapply(
      forbidden_regex,
      function(pattern) grepl(pattern, txt, perl = TRUE, ignore.case = TRUE, useBytes = TRUE),
      logical(1)
    )]

    if (length(matched) > 0) {
      violations <- c(
        violations,
        sprintf("%s -> %s", rel, paste(matched, collapse = ", "))
      )
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
    file.path(repo_root, "app.R"),
    file.path(repo_root, "global.R"),
    file.path(repo_root, "ui.R"),
    file.path(repo_root, "server.R"),
    list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(repo_root, "tests"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  )

  scan_files <- unique(.normalize_path_secret_contract(
    scan_files[file.exists(scan_files)]
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
      violations <- c(violations, .repo_relative_secret_contract(repo_root, f))
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

test_that("validation report scripts avoid raw endpoint and DB-content echo patterns", {
  repo_root <- resolve_repo_root_for_tests()

  vm_preflight <- .read_repo_text_secret_contract(
    file.path(repo_root, "tests", "scripts", "run_vm_preflight_real.R")
  )

  vm_encoding_preflight <- .read_repo_text_secret_contract(
    file.path(repo_root, "tests", "scripts", "run_vm_encoding_preflight_real.R")
  )

  expect_true(
    grepl("preflight_redact_sensitive_text", vm_preflight, fixed = TRUE, useBytes = TRUE),
    info = "VM preflight hata metinlerini secret-safe redaction yolundan geçirmelidir."
  )

  expect_true(
    grepl("preflight_value_metadata", vm_preflight, fixed = TRUE, useBytes = TRUE),
    info = "VM preflight endpoint/client gibi değerleri ham yazmak yerine metadata yazmalıdır."
  )

  expect_false(
    grepl("issuer=%s", vm_preflight, fixed = TRUE, useBytes = TRUE),
    info = "VM preflight raw issuer endpoint yazmamalıdır."
  )

  expect_false(
    grepl("client_id=%s", vm_preflight, fixed = TRUE, useBytes = TRUE),
    info = "VM preflight raw client_id yazmamalıdır; metadata yeterlidir."
  )

  expect_false(
    grepl(", Preview=", vm_encoding_preflight, fixed = TRUE, useBytes = TRUE),
    info = "VM encoding preflight MB_Messages içerik preview'i yazmamalıdır."
  )

  expect_true(
    grepl("MessageContentBytes=", vm_encoding_preflight, fixed = TRUE, useBytes = TRUE),
    info = "VM encoding preflight içerik yerine byte sayısı gibi güvenli metadata yazmalıdır."
  )
})