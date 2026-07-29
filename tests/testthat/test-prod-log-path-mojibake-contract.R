testthat::local_edition(3)

load_prod_log_dir_repair <- function() {
  expressions <- parse(
    file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R"),
    encoding = "UTF-8"
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

test_that("log yolu merkezi çok geçişli onarımla aynı hedefte düzeltilir", {
  repair <- load_prod_log_dir_repair()
  repo_root <- resolve_repo_root_for_tests()

  expect_identical(
    repair("//server/GeliÅŸtirme/MERGEN Bilge/logs", repo_root),
    "//server/Geliştirme/MERGEN Bilge/logs"
  )
  expect_identical(
    repair("//server/GeliÃ…Å¸tirme/MERGEN Bilge/logs", repo_root),
    "//server/Geliştirme/MERGEN Bilge/logs"
  )
})

test_that("geçerli özel log yolları değiştirilmez", {
  repair <- load_prod_log_dir_repair()
  repo_root <- resolve_repo_root_for_tests()

  expect_identical(
    repair("//server/Årsrapporter/logs", repo_root),
    "//server/Årsrapporter/logs"
  )
  expect_identical(
    repair("//server/Ãrea/logs", repo_root),
    "//server/Ãrea/logs"
  )
  expect_identical(
    repair("//server/MERGEN Bilge/logs", repo_root),
    "//server/MERGEN Bilge/logs"
  )
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
