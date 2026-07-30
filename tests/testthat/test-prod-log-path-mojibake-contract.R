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
  text <- gsub("\r\n?|\r", "\n", text, perl = TRUE)
  Encoding(text) <- "UTF-8"
  text
}

read_prod_launcher_bytes <- function() {
  read_repo_utf8_bytes(
    file.path(resolve_repo_root_for_tests(), "run_mergen_prod.R")
  )
}

read_app_entry_bytes <- function() {
  read_repo_utf8_bytes(
    file.path(resolve_repo_root_for_tests(), "app.R")
  )
}

read_log_bootstrap_bytes <- function() {
  read_repo_utf8_bytes(
    file.path(resolve_repo_root_for_tests(), "R", "bootstrap_log_path.R")
  )
}

load_prod_log_dir_repair <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = baseenv())

  utils_expressions <- parse(
    text = read_repo_utf8_bytes(file.path(repo_root, "R", "utils_text_encoding.R")),
    encoding = "UTF-8",
    keep.source = FALSE
  )
  bootstrap_expressions <- parse(
    text = read_log_bootstrap_bytes(),
    encoding = "UTF-8",
    keep.source = FALSE
  )

  for (expr in utils_expressions) {
    eval(expr, envir = env)
  }
  for (expr in bootstrap_expressions) {
    eval(expr, envir = env)
  }

  expect_true(exists("repair_mergen_log_dir", envir = env, inherits = FALSE))
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
  expected <- prod_log_path(paste0("Geli", prod_log_u(0x015F), "tirme"))
  single_pass <- prod_log_path(paste0("Geli", prod_log_u(0x00C5, 0x0178), "tirme"))
  double_pass <- prod_log_path(paste0(
    "Geli",
    prod_log_u(0x00C3, 0x2026, 0x00C5, 0x00B8),
    "tirme"
  ))

  expect_identical(repair(single_pass), expected)
  expect_identical(repair(double_pass), expected)
})

test_that("karışık geçerli ve bozuk Türkçe bileşenler birlikte onarılır", {
  repair <- load_prod_log_dir_repair()
  valid_segment <- paste0("Do", prod_log_u(0x011F), "ru")
  corrupt_segment <- paste0("Geli", prod_log_u(0x00C5, 0x009F), "tirme")
  repaired_segment <- paste0("Geli", prod_log_u(0x015F), "tirme")
  input <- paste0("//server/", valid_segment, "/", corrupt_segment, "/logs")
  expected <- paste0("//server/", valid_segment, "/", repaired_segment, "/logs")

  expect_identical(repair(input), expected)
})

test_that("karışık Türkçe ve Latin mojibake bileşenleri merkezi yardımcıyla onarılır", {
  repair <- load_prod_log_dir_repair()
  valid_segment <- paste0("Do", prod_log_u(0x011F), "ru")
  corrupt_segment <- paste0("Caf", prod_log_u(0x00C3, 0x00A9))
  repaired_segment <- paste0("Caf", prod_log_u(0x00E9))
  input <- paste0("//server/", valid_segment, "/", corrupt_segment, "/logs")
  expected <- paste0("//server/", valid_segment, "/", repaired_segment, "/logs")

  expect_identical(repair(input), expected)
})

test_that("geçerli karma Unicode bayt çiftleri değiştirilmez", {
  repair <- load_prod_log_dir_repair()
  valid_turkish <- paste0("Do", prod_log_u(0x011F), "ru")
  valid_pair <- prod_log_u(0x00C9, 0x00A9)
  path <- paste0("//server/", valid_turkish, "/", valid_pair, "/logs")

  expect_identical(repair(path), path)
})

test_that("mevcut geçerli belirsiz log dizini korunur", {
  repair <- load_prod_log_dir_repair()
  valid_pair <- prod_log_u(0x00C2, 0x00A9)
  existing_path <- tempfile(pattern = paste0("mergen-", valid_pair, "-"))

  expect_true(dir.create(existing_path, recursive = TRUE))
  on.exit(unlink(existing_path, recursive = TRUE, force = TRUE), add = TRUE)

  expect_identical(repair(existing_path), enc2utf8(existing_path))
})

test_that("henüz oluşturulmamış geçerli belirsiz log adı değiştirilmez", {
  repair <- load_prod_log_dir_repair()
  valid_pair <- prod_log_u(0x00C2, 0x00A9)
  missing_path <- tempfile(pattern = paste0("mergen-", valid_pair, "-"))

  expect_false(dir.exists(missing_path))
  expect_identical(repair(missing_path), enc2utf8(missing_path))
})

test_that("güçlü kanıt yalnız gerçekten onarılan diziye bağlanır", {
  repair <- load_prod_log_dir_repair()
  root <- tempfile(pattern = "mergen-log-root-")
  valid_standalone <- paste0(prod_log_u(0x00C5), "land")
  ambiguous_pair <- prod_log_u(0x00C2, 0x00A9)
  existing_path <- file.path(root, valid_standalone, ambiguous_pair, "logs")

  expect_true(dir.create(existing_path, recursive = TRUE))
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  expect_identical(repair(existing_path), enc2utf8(existing_path))
})

test_that("önceden oluşmuş bozuk log dizini güçlü kanıtla onarılır", {
  repair <- load_prod_log_dir_repair()
  root <- tempfile(pattern = "mergen-log-root-")
  corrupt_segment <- paste0("Geli", prod_log_u(0x00C5, 0x0178), "tirme")
  repaired_segment <- paste0("Geli", prod_log_u(0x015F), "tirme")
  corrupt_path <- file.path(root, corrupt_segment, "logs")
  repaired_path <- file.path(root, repaired_segment, "logs")

  expect_true(dir.create(corrupt_path, recursive = TRUE))
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  expect_true(dir.exists(corrupt_path))
  expect_identical(repair(corrupt_path), enc2utf8(repaired_path))
})

test_that("geçerli özel log yolları değiştirilmez", {
  repair <- load_prod_log_dir_repair()
  valid_paths <- c(
    paste0("//server/", prod_log_u(0x00C5), "rsrapporter/logs"),
    paste0("//server/", prod_log_u(0x00C3), "rea/logs"),
    prod_log_path(paste0("Geli", prod_log_u(0x015F), "tirme"))
  )

  for (path in valid_paths) {
    expect_identical(repair(path), path)
  }
})

test_that("ortak UTF-8 yardımcısı ve log bootstrap bayt güvenli ayrıştırılır", {
  repo_root <- resolve_repo_root_for_tests()
  utils_code <- read_repo_utf8_bytes(
    file.path(repo_root, "R", "utils_text_encoding.R")
  )
  bootstrap_code <- read_log_bootstrap_bytes()

  expect_silent(parse(text = utils_code, encoding = "UTF-8", keep.source = FALSE))
  expect_silent(parse(text = bootstrap_code, encoding = "UTF-8", keep.source = FALSE))
})

test_that("ortak mojibake çözücüsü büyüyen çıktıyı yeniden kopyalamaz", {
  code <- read_repo_utf8_bytes(
    file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R")
  )

  expect_match(code, "output <- character(length(codepoints))", fixed = TRUE)
  expect_match(code, "output_count <- output_count + 1L", fixed = TRUE)
  expect_false(grepl("output <- c(output", code, fixed = TRUE))
})

test_that("üretim başlatıcısı ortak log bootstrap katmanını app.R öncesinde çalıştırır", {
  code <- read_prod_launcher_bytes()
  script <- strsplit(code, "\n", fixed = TRUE)[[1]]
  script <- sub("\r$", "", script)

  expect_match(code, 'file.path(repo_root, "R", "utils_text_encoding.R")', fixed = TRUE)
  expect_match(code, 'file.path(repo_root, "R", "bootstrap_log_path.R")', fixed = TRUE)
  expect_match(code, 'encoding = "UTF-8"', fixed = TRUE)
  expect_match(code, "normalize_mergen_log_dir_env(max_passes = 2L)", fixed = TRUE)
  expect_false(grepl("repair_mergen_log_dir <- function", code, fixed = TRUE))
  expect_false(grepl("sys.source(", code, fixed = TRUE))
  expect_false(grepl("mergen_turkish_mojibake_map", code, fixed = TRUE))
  expect_false(grepl('file.path(repo_root, "logs")', code, fixed = TRUE))

  repair_line <- grep(
    "normalize_mergen_log_dir_env(max_passes = 2L)",
    script,
    fixed = TRUE
  )
  app_source_line <- grep('source("app.R"', script, fixed = TRUE)

  expect_length(repair_line, 1L)
  expect_length(app_source_line, 1L)
  expect_lt(repair_line, app_source_line)
})

test_that("doğrudan app.R ve çok-worker süreçleri ortak log bootstrap katmanını kullanır", {
  app_code <- read_app_entry_bytes()
  app_script <- strsplit(app_code, "\n", fixed = TRUE)[[1]]
  worker_code <- read_repo_utf8_bytes(
    file.path(resolve_repo_root_for_tests(), "tools", "run_mergen_workers.R")
  )

  expect_match(app_code, '"R/utils_text_encoding.R"', fixed = TRUE)
  expect_match(app_code, '"R/bootstrap_log_path.R"', fixed = TRUE)
  expect_match(app_code, "normalize_mergen_log_dir_env(max_passes = 2L)", fixed = TRUE)
  expect_match(worker_code, 'args = c("app.R")', fixed = TRUE)

  repair_line <- grep(
    "normalize_mergen_log_dir_env(max_passes = 2L)",
    app_script,
    fixed = TRUE
  )
  global_line <- grep('boot_step("global.R"', app_script, fixed = TRUE)

  expect_length(repair_line, 1L)
  expect_length(global_line, 1L)
  expect_lt(repair_line, global_line)
})

test_that("log bootstrap güçlü ve belirsiz kanıtı ayrı değerlendirir", {
  code <- read_log_bootstrap_bytes()

  expect_match(code, "original_exists <- dir.exists(path)", fixed = TRUE)
  expect_match(code, "repaired_exists <- dir.exists(repaired)", fixed = TRUE)
  expect_match(code, "strong_evidence <- mergen_log_path_has_strong_mojibake", fixed = TRUE)
  expect_match(code, ".mergen_log_path_pass_has_strong_mojibake", fixed = TRUE)
  expect_match(
    code,
    "original_codepoints[[1]] %in% c(0x00C3L, 0x00C4L, 0x00C5L)",
    fixed = TRUE
  )
  expect_false(grepl(
    "any(codepoints %in% c(0x00C3L, 0x00C4L, 0x00C5L))",
    code,
    fixed = TRUE
  ))
  expect_match(code, "!isTRUE(original_exists) && isTRUE(repaired_exists)", fixed = TRUE)
})
