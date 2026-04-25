# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-refactor-contract.R
# Açıklama: helpers_database.R dosyasından DB bağlantı ve doğrulama katmanlarının
#           ayrı dosyalara taşındığını, source sırasının korunduğunu ve eski
#           monolitik yapının geri dönmediğini doğrular.
# ==============================================================================

.read_repo_text_db_refactor_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
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

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.byte_pos_db_refactor_contract <- function(pattern, text) {
  pos <- regexpr(pattern, text, fixed = TRUE, useBytes = TRUE)[1]
  if (is.na(pos) || pos < 0L) NA_integer_ else as.integer(pos)
}

test_that("DB bağlantı ve doğrulama dosyaları repoda var", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(repo_root, "R", "helpers_db_connection.R")))
  expect_true(file.exists(file.path(repo_root, "R", "helpers_db_validation.R")))
  expect_true(file.exists(file.path(repo_root, "R", "helpers_database.R")))
})

test_that("global.R DB dosyalarını doğru sırada source eder", {
  global_text <- .read_repo_text_db_refactor_contract("global.R")

  expected_order <- c(
    'safe_source("R/helpers_db_connection.R"',
    'safe_source("R/helpers_db_validation.R"',
    'safe_source("R/helpers_database.R"',
    'safe_source("R/library_queries.R"',
    'safe_source("R/config_sql_loader.R"'
  )

  positions <- vapply(
    expected_order,
    .byte_pos_db_refactor_contract,
    integer(1),
    text = global_text
  )

  expect_false(
    any(is.na(positions)),
    info = paste(
      "global.R içinde eksik DB source kayıtları:",
      paste(expected_order[is.na(positions)], collapse = ", ")
    )
  )

  expect_true(
    all(diff(positions) > 0L),
    info = paste(
      "global.R DB source sırası bozulmuş:",
      paste(expected_order, collapse = " -> ")
    )
  )
})

test_that("test bootstrap DB dosyalarını üretim sırasına uyumlu yükler", {
  bootstrap_text <- .read_repo_text_db_refactor_contract("tests/testthat/helper_bootstrap.R")

  expected_order <- c(
    '"helpers_db_connection.R"',
    '"helpers_db_validation.R"',
    '"helpers_database.R"'
  )

  positions <- vapply(
    expected_order,
    .byte_pos_db_refactor_contract,
    integer(1),
    text = bootstrap_text
  )

  expect_false(
    any(is.na(positions)),
    info = paste(
      "helper_bootstrap.R içinde eksik DB source kayıtları:",
      paste(expected_order[is.na(positions)], collapse = ", ")
    )
  )

  expect_true(
    all(diff(positions) > 0L),
    info = "helper_bootstrap.R DB source sırası üretim sırası ile uyumlu değil."
  )
})

test_that("helpers_db_connection.R beklenen bağlantı yardımcılarını içerir", {
  txt <- .read_repo_text_db_refactor_contract("R/helpers_db_connection.R")

  expected <- c(
    "normalize_db_value <- function",
    "normalize_db_params <- function",
    "get_pool_info <- function",
    "db_pool_healthy <- function",
    "get_connection <- function",
    "release_connection <- function",
    "worker_db_connect <- function"
  )

  found <- vapply(
    expected,
    function(pattern) grepl(pattern, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "helpers_db_connection.R içinde eksik fonksiyonlar:",
      paste(expected[!found], collapse = ", ")
    )
  )
})

test_that("helpers_db_validation.R beklenen doğrulama yardımcılarını içerir", {
  txt <- .read_repo_text_db_refactor_contract("R/helpers_db_validation.R")

  expected <- c(
    "validate_username <- function",
    "validate_chat_title <- function",
    "validate_message_content <- function"
  )

  found <- vapply(
    expected,
    function(pattern) grepl(pattern, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )

  expect_true(
    all(found),
    info = paste(
      "helpers_db_validation.R içinde eksik fonksiyonlar:",
      paste(expected[!found], collapse = ", ")
    )
  )
})

test_that("helpers_database.R bağlantı/doğrulama monolitini geri almıyor", {
  txt <- .read_repo_text_db_refactor_contract("R/helpers_database.R")

  forbidden <- c(
    "get_connection <- function",
    "release_connection <- function",
    "worker_db_connect <- function",
    "db_pool_healthy <- function",
    "validate_username <- function",
    "validate_chat_title <- function",
    "validate_message_content <- function"
  )

  matched <- forbidden[vapply(
    forbidden,
    function(pattern) grepl(pattern, txt, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    matched,
    character(0),
    info = paste(
      "helpers_database.R içine taşınmış olması gereken fonksiyonlar geri dönmüş:",
      paste(matched, collapse = ", ")
    )
  )
})