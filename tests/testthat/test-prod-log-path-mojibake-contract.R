# ==============================================================================
# Dosya Yolu: tests/testthat/test-prod-log-path-mojibake-contract.R
# Açıklama: Üretim log yolu mojibake onarımı ve kaynak sırası sözleşme testleri.
#
#
# ==============================================================================

testthat::local_edition(3)

load_prod_log_dir_repair <- function() {
  expressions <- parse(
    file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R"),
    encoding = "UTF-8"
  )
  function_names <- c(
    "mergen_mojibake_variant",
    "mergen_turkish_mojibake_map",
    "repair_mergen_log_dir"
  )
  env <- new.env(parent = baseenv())

  for (function_name in function_names) {
    is_target <- vapply(expressions, function(expr) {
      is.call(expr) &&
        length(expr) >= 3L &&
        identical(expr[[1]], as.name("<-")) &&
        identical(expr[[2]], as.name(function_name))
    }, logical(1))

    expect_equal(sum(is_target), 1L)
    eval(expressions[[which(is_target)]], envir = env)
  }

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

test_that("karışık geçerli ve bozuk bileşenler birlikte güvenle onarılır", {
  repair <- load_prod_log_dir_repair()
  repo_root <- resolve_repo_root_for_tests()
  valid_segment <- paste0("Do", prod_log_u(0x011F), "ru")
  corrupt_segment <- paste0("Geli", prod_log_u(0x00C5, 0x009F), "tirme")
  repaired_segment <- paste0("Geli", prod_log_u(0x015F), "tirme")
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

test_that("üretim başlatıcısı onarılmış hedefi app kaynaklanmadan önce uygular", {
  script <- readLines(
    file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R"),
    warn = FALSE,
    encoding = "UTF-8"
  )
  code <- paste(script, collapse = "\n")

  expect_match(code, 'file.path(repo_root, "R", "utils_text_encoding.R")', fixed = TRUE)
  expect_match(code, "repair_text_mojibake(path, max_passes = 2L)", fixed = TRUE)
  expect_match(code, "mergen_turkish_mojibake_map()", fixed = TRUE)
  expect_match(code, "Sys.setenv(MERGEN_LOG_DIR = repaired_log_dir)", fixed = TRUE)
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
