# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-user-guard-contract.R
# Açıklama: Bilge Yolaç kullanıcı kimliği hazır olma yardımcılarının SSO yarış
#           koşullarına karşı sözleşmesini korur.
# ==============================================================================

.read_repo_text_cc_user_guard_contract <- function(path) {
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

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.load_cc_user_guard_contract_helpers <- function() {
  repo_root <- resolve_repo_root_for_tests()

  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8")
  source(file.path(repo_root, "R", "helpers_claude_code_user_guard.R"), encoding = "UTF-8")
  source(file.path(repo_root, "R", "helpers_claude_code_server_setup.R"), encoding = "UTF-8")
}

test_that("Claude Code user guard SSO hazır değilken user_id=0 ile devam etmez", {
  .load_cc_user_guard_contract_helpers()

  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())
  session$userData$user_id <- 0L
  session$userData$auth_initialized <- FALSE

  result <- cc_require_ready_user_id(
    session = session,
    current_user_id = function() 42L,
    sso_enabled = TRUE,
    action_label = "komut çalıştırma"
  )

  expect_false(result$ok)
  expect_identical(result$user_id, 0L)
  expect_identical(result$code, "auth_pending")
  expect_match(result$message, "Kimlik doğrulama tamamlanmadan", fixed = TRUE)
})

test_that("Claude Code user guard SSO hazır olduğunda canlı session user_id kullanır", {
  .load_cc_user_guard_contract_helpers()

  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())
  session$userData$user_id <- 123L
  session$userData$auth_initialized <- TRUE

  result <- cc_require_ready_user_id(
    session = session,
    current_user_id = function() 42L,
    sso_enabled = TRUE,
    action_label = "proje dizini listeleme"
  )

  expect_true(result$ok)
  expect_identical(result$user_id, 123L)
  expect_identical(result$code, "ok")
})

test_that("Claude Code user guard local modda fallback provider değerini kabul eder", {
  .load_cc_user_guard_contract_helpers()

  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())

  result <- cc_require_ready_user_id(
    session = session,
    current_user_id = function() 77L,
    sso_enabled = FALSE,
    action_label = "yerel klasör yükleme"
  )

  expect_true(result$ok)
  expect_identical(result$user_id, 77L)
  expect_identical(result$code, "ok")
})

test_that("Claude Code user guard kullanıcı kimliği yoksa açıkça reddeder", {
  .load_cc_user_guard_contract_helpers()

  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())

  result <- cc_require_ready_user_id(
    session = session,
    current_user_id = NULL,
    sso_enabled = FALSE,
    action_label = "yükleme klasörüne geçiş"
  )

  expect_false(result$ok)
  expect_identical(result$user_id, 0L)
  expect_identical(result$code, "user_pending")
  expect_match(result$message, "Kullanıcı kimliği hazır değil", fixed = TRUE)
})

test_that("Claude Code server setup helper ve module wiring sözleşmesi korunur", {
  .load_cc_user_guard_contract_helpers()

  expect_true(is.function(cc_bind_server_setup))

  module_text <- .read_repo_text_cc_user_guard_contract("R/module_claude_code.R")

  expect_true(
    grepl("cc_bind_server_setup\\s*\\(", module_text, perl = TRUE),
    info = "module_claude_code.R setup observer kümesini cc_bind_server_setup() üzerinden bağlamalıdır."
  )

  expect_true(
    grepl("ensure_ready_user_id\\s*<-\\s*server_setup\\$ensure_ready_user_id", module_text, perl = TRUE),
    info = "run_command ve workspace işlemleri hazır kullanıcı kimliği guard'ını kullanmalıdır."
  )

  expect_true(
    grepl("ensure_ready_user_id\\(\"komut çalıştırma\"\\)", module_text, fixed = TRUE),
    info = "Ana komut çalıştırma akışı user_id hazır değilken devam etmemelidir."
  )
})