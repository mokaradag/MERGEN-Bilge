# ==============================================================================
# Dosya Yolu: tests/testthat/test-prod-log-path-mojibake-contract.R
# Açıklama: Üretim log yolu mojibake onarımı ve kaynak sırası sözleşme testleri.
#
#
# ==============================================================================

testthat::local_edition(3)

read_repo_utf8_bytes <- function(path) {
  size <- suppressWarnings(file.info(path)$size[[1]])
  expect_false(is.na(size))

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_content <- readBin(con, what = "raw", n = size)
  text <- iconv(
    list(raw_content),
    from = "UTF-8",
    to = "UTF-8",
    sub = "byte"
  )[[1]]

  expect_false(is.na(text))
  Encoding(text) <- "UTF-8"
  text
}

read_prod_launcher_bytes <- function() {
  read_repo_utf8_bytes(
    file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R")
  )
}

load_prod_log_dir_repair <- function() {
  expressions <- parse(
    text = read_prod_launcher_bytes(),
    encoding = "UTF-8",
    keep.source = FALSE
  )
  is_repair <- vapply(expressions, function(expr) {
    is.call(expr) &&
      length(expr) >= 3L &&
      identical(expr[[1]], as.name("<-")) &&
      identical(expr[[2]], as.name("repair_mergen_log_dir"))
  }, logical(1))

  expect_equal(sum(is_repair), 1L)
  env <- new.env(parent = baseenv())
  eval(expressions[[which(is_repair)]], envir = env)
  env$repair_mergen_log_dir
}

prod_log_u <- function(...) {
  intToUtf8(as.integer(c(...)))
}

prod_log_path <- function(segment) {
  paste0("//server/", segment, "/MERGEN Bilge/logs")
}

test_that("log yolu tek ve çift geçişli bozulmada aynı hedefte düzeltilir", {
  repair <- load_prod_log_dir_repair()
  repo_root <- resolve_repo_root_for_tests()
  expected <- prod_log_path(paste0("Geli", prod_log_u(0x015F), "tirme"))
  single_pass <- prod_log_path(paste0("Geli", prod_log_u(0x00C5, 0x0178), "tirme"))
  double_pass <- prod_log_path(paste0(
    "Geli",
    prod_log_u(0x00C3, 0x2026, 0x00C5, 0x00B8),
    "tirme"
  ))

  expect_identical(repair(single_pass, repo_root), expected)
  expect_identical(repair(double_pass, repo_root), expected)
})

test_that("karışık geçerli ve bozuk Türkçe bileşenler birlikte onarılır", {
  repair <- load_prod_log_dir_repair()
  repo_root <- resolve_repo_root_for_tests()
  valid_segment <- paste0("Do", prod_log_u(0x011F), "ru")
  corrupt_segment <- paste0("Geli", prod_log_u(0x00C5, 0x009F), "tirme")
  repaired_segment <- paste0("Geli", prod_log_u(0x015F), "tirme")
  input <- paste0("//server/", valid_segment, "/", corrupt_segment, "/logs")
  expected <- paste0("//server/", valid_segment, "/", repaired_segment, "/logs")

  expect_identical(repair(input, repo_root), expected)
})

test_that("karışık Türkçe ve Latin mojibake bileşenleri merkezi yardımcıyla onarılır", {
  repair <- load_prod_log_dir_repair()
  repo_root <- resolve_repo_root_for_tests()
  valid_segment <- paste0("Do", prod_log_u(0x011F), "ru")
  corrupt_segment <- paste0("Caf", prod_log_u(0x00C3, 0x00A9))
  repaired_segment <- paste0("Caf", prod_log_u(0x00E9))
  input <- paste0("//server/", valid_segment, "/", corrupt_segment, "/logs")
  expected <- paste0("//server/", valid_segment, "/", repaired_segment, "/logs")

  expect_identical(repair(input, repo_root), expected)
})

test_that("geçerli özel log yolları değiştirilmez", {
  repair <- load_prod_log_dir_repair()
  repo_root <- resolve_repo_root_for_tests()
  valid_paths <- c(
    paste0("//server/", prod_log_u(0x00C5), "rsrapporter/logs"),
    paste0("//server/", prod_log_u(0x00C3), "rea/logs"),
    prod_log_path(paste0("Geli", prod_log_u(0x015F), "tirme"))
  )

  for (path in valid_paths) {
    expect_identical(repair(path, repo_root), path)
  }
})

test_that("ortak mojibake çözücüsü büyüyen çıktıyı yeniden kopyalamaz", {
  code <- read_repo_utf8_bytes(
    file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R")
  )

  expect_match(code, "output <- character(length(codepoints))", fixed = TRUE)
  expect_match(code, "output_count <- output_count + 1L", fixed = TRUE)
  expect_false(grepl("output <- c(output", code, fixed = TRUE))
})

test_that("üretim başlatıcısı bayt güvenli taranır ve yardımcıyı UTF-8 yükler", {
  code <- read_prod_launcher_bytes()
  script <- strsplit(code, "\n", fixed = TRUE)[[1]]
  script <- sub("\r$", "", script)

  expect_match(code, 'file.path(repo_root, "R", "utils_text_encoding.R")', fixed = TRUE)
  expect_match(code, 'encoding = "UTF-8"', fixed = TRUE)
  expect_match(code, "repair_text_mojibake(path, max_passes = 2L)", fixed = TRUE)
  expect_match(code, "text_has_mojibake(repaired)", fixed = TRUE)
  expect_match(code, "Sys.setenv(MERGEN_LOG_DIR = repaired_log_dir)", fixed = TRUE)
  expect_false(grepl("sys.source(", code, fixed = TRUE))
  expect_false(grepl("mergen_turkish_mojibake_map", code, fixed = TRUE))
  expect_false(grepl('file.path(repo_root, "logs")', code, fixed = TRUE))

  repair_line <- grep(
    "Sys.setenv(MERGEN_LOG_DIR = repaired_log_dir)",
    script,
    fixed = TRUE
  )
  app_source_line <- grep('source("app.R"', script, fixed = TRUE)

  expect_length(repair_line, 1L)
  expect_length(app_source_line, 1L)
  expect_lt(repair_line, app_source_line)
})
