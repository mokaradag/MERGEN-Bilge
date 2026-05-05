# ==============================================================================
# Dosya Yolu: tests/testthat/test-helpers-files-path-contract.R
# Açıklama: helpers_files.R içindeki yol/UNC yardımcılarının ayrı path helper
#           dosyasında kaldığını ve MCP kopyalama hedef adının çakışmadığını
#           doğrular.
# ==============================================================================

.read_repo_text_quiet_helpers_files_path <- function(path) {
  repo_root <- if (exists("resolve_repo_root_for_tests", mode = "function")) {
    resolve_repo_root_for_tests()
  } else {
    normalizePath(".", winslash = "/", mustWork = TRUE)
  }

  full_path <- file.path(repo_root, path)
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
  txt <- rawToChar(raw_data, multiple = FALSE)
  Encoding(txt) <- "UTF-8"
  txt <- enc2utf8(txt)

  gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
}

local({
  gerekli_dosyalar <- c(
    file.path(repo_root_for_tests, "R", "utils_common.R"),
    file.path(repo_root_for_tests, "R", "utils_path_helpers.R"),
    file.path(repo_root_for_tests, "R", "helpers_files_path.R"),
    file.path(repo_root_for_tests, "R", "helpers_files.R")
  )

  for (dosya in gerekli_dosyalar) {
    source(dosya, encoding = "UTF-8", local = globalenv())
  }
})

test_that("dosya yolu yardımcıları helpers_files_path.R içinde tutulur", {
  path_txt <- .read_repo_text_quiet_helpers_files_path("R/helpers_files_path.R")
  files_txt <- .read_repo_text_quiet_helpers_files_path("R/helpers_files.R")
  global_txt <- .read_repo_text_quiet_helpers_files_path("global.R")

  moved_defs <- c(
    "resolve_readable_path <- function",
    "path_exists_relaxed <- function",
    "normalize_for_path_compare <- function",
    "is_under_mcp_base <- function"
  )

  path_has_defs <- vapply(
    moved_defs,
    function(x) grepl(x, path_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  files_has_defs <- vapply(
    moved_defs,
    function(x) grepl(x, files_txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(path_has_defs),
    info = paste("Eksik path helper tanımları:", paste(moved_defs[!path_has_defs], collapse = ", "))
  )

  expect_false(
    any(files_has_defs),
    info = "Yol/UNC helper tanımları helpers_files.R içine geri taşınmamalıdır."
  )

  expect_true(
    grepl('safe_source("R/helpers_files_path.R"', global_txt, fixed = TRUE, useBytes = TRUE),
    info = "helpers_files_path.R global.R manifestinde açıkça yüklenmelidir."
  )
})

test_that("path helper davranışı temel dosya yollarında korunur", {
  tmp <- tempfile(fileext = ".txt")
  writeLines(enc2utf8("Türkçe karakter testi: çğıöşü"), tmp, useBytes = TRUE)

  expect_true(path_exists_relaxed(tmp))
  expect_true(path_exists_relaxed(gsub("\\\\", "/", tmp, fixed = TRUE)))
  expect_true(nzchar(resolve_readable_path(tmp)))

  normalized_a <- normalize_for_path_compare(tmp)
  normalized_b <- normalize_for_path_compare(gsub("\\\\", "/", tmp, fixed = TRUE))

  expect_identical(normalized_a, normalized_b)
})

test_that("copy_to_mcp_base aynı dosyayı aynı anda tekrar kopyalarken hedef çakışması üretmez", {
  base_dir <- tempfile("mcp-base-")
  dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)

  withr::local_options(list(
    mergen.mcp_base_dir = normalizePath(base_dir, winslash = "/", mustWork = FALSE)
  ))

  src <- tempfile(fileext = ".txt")
  writeLines(enc2utf8("Türkçe içerik: çğıöşü"), src, useBytes = TRUE)

  upload <- list(
    name = "dummy_çalışma.txt",
    datapath = src
  )

  first_dest <- copy_to_mcp_base(upload, user_id = 42L)
  second_dest <- copy_to_mcp_base(upload, user_id = 42L)

  expect_true(path_exists_relaxed(first_dest))
  expect_true(path_exists_relaxed(second_dest))

  expect_false(
    identical(
      normalize_for_path_compare(first_dest),
      normalize_for_path_compare(second_dest)
    ),
    info = "Aynı dosya hızlı tekrar kopyalandığında hedef path aynı olmamalıdır."
  )

  expect_true(
    grepl("dummy_çalışma.txt", basename(first_dest), fixed = TRUE, useBytes = TRUE),
    info = "Kopyalanan dosyada okunabilir orijinal ad korunmalıdır."
  )
})