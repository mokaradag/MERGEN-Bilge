# ==============================================================================
# Dosya Yolu: tests/testthat/test-production-contracts.R
# Açıklama: Üretim sertleştirme sözleşmelerini statik olarak doğrular.
# Bu testler uygulamayı başlatmaz; dosya yapısı, parse edilebilirlik,
# source manifesti ve async sarmalayıcı disiplinini kontrol eder.
# ==============================================================================

.find_repo_root <- function() {
  adaylar <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (aday in adaylar) {
    if (file.exists(file.path(aday, "app.R")) &&
        dir.exists(file.path(aday, "R"))) {
      return(aday)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.repo_root <- .find_repo_root()

.read_utf8 <- function(path) {
  readLines(path, encoding = "UTF-8", warn = FALSE)
}

.strip_comment_lines <- function(x) {
  x[!grepl("^\\s*#", x)]
}

test_that("tüm temel R dosyaları UTF-8 ile parse edilebilir", {
  r_files <- c(
    list.files(file.path(.repo_root, "R"), pattern = "\\.R$", full.names = TRUE, recursive = TRUE),
    file.path(.repo_root, c("app.R", "global.R", "ui.R", "server.R", "welcome_screen.R"))
  )

  r_files <- r_files[file.exists(r_files)]

  expect_gt(length(r_files), 10L)

  for (f in r_files) {
    expect_no_error(
      parse(file = f, encoding = "UTF-8", keep.source = FALSE),
      info = sprintf("Parse edilemeyen dosya: %s", f)
    )
  }
})

test_that("global.R üretim sertleştirme helper'larını manifestte yüklüyor", {
  global_text <- paste(.read_utf8(file.path(.repo_root, "global.R")), collapse = "\n")

  beklenenler <- c(
    'safe_source("R/utils_safe_path.R"',
    'safe_source("R/utils_atomic_write.R"',
    'safe_source("R/utils_upload_validator.R"',
    'safe_source("R/utils_log_redact.R"',
    'safe_source("R/utils_session_cleanup.R"',
    'safe_source("R/utils_safe_worker_run.R"',
    'safe_source("R/helpers_worker_monitor.R"'
  )

  for (beklenen in beklenenler) {
    expect_true(
      grepl(beklenen, global_text, fixed = TRUE),
      info = sprintf("global.R manifestinde eksik: %s", beklenen)
    )
  }
})

test_that("app.R doğrudan source edildiğinde otomatik çalışma kapısı korunuyor", {
  app_text <- paste(.read_utf8(file.path(.repo_root, "app.R")), collapse = "\n")

  beklenenler <- c(
    "validate_boot_state <- function",
    "create_mergen_app <- function",
    "run_mergen_app <- function",
    "MERGEN_RUN_APP",
    "auto_run <- .env_flag_is_true",
    "if (isTRUE(auto_run))"
  )

  for (beklenen in beklenenler) {
    expect_true(
      grepl(beklenen, app_text, fixed = TRUE),
      info = sprintf("app.R boot sözleşmesinde eksik: %s", beklenen)
    )
  }
})

test_that("ham future_promise kullanımı merkezi tracked_future_promise arkasında kalıyor", {
  r_files <- list.files(
    file.path(.repo_root, "R"),
    pattern = "\\.R$",
    full.names = TRUE,
    recursive = TRUE
  )

  izinli_dosyalar <- normalizePath(
    file.path(.repo_root, "R", "helpers_worker_monitor.R"),
    winslash = "/",
    mustWork = FALSE
  )

  ihlaller <- character(0)

  for (f in r_files) {
    f_norm <- normalizePath(f, winslash = "/", mustWork = FALSE)
    txt <- .strip_comment_lines(.read_utf8(f))

    ham_kullanim <- grepl("(^|[^A-Za-z0-9_.])future_promise\\s*\\(", txt) |
      grepl("promises::future_promise\\s*\\(", txt)

    if (any(ham_kullanim) && !(f_norm %in% izinli_dosyalar)) {
      ihlaller <- c(ihlaller, f_norm)
    }
  }

  expect_equal(
    unique(ihlaller),
    character(0),
    info = paste(
      "future_promise doğrudan kullanılmamalı; tracked_future_promise kullanın:",
      paste(unique(ihlaller), collapse = ", ")
    )
  )
})

test_that("test runner Shiny/future başlatmayı kapatan env bayraklarını içeriyor", {
  runner_path <- file.path(.repo_root, "tests", "testthat.R")
  expect_true(file.exists(runner_path))

  runner_text <- paste(.read_utf8(runner_path), collapse = "\n")

  expect_true(grepl('MERGEN_RUN_APP = "false"', runner_text, fixed = TRUE))
  expect_true(grepl('MERGEN_DISABLE_FUTURES = "true"', runner_text, fixed = TRUE))
  expect_true(grepl("stop_on_failure = TRUE", runner_text, fixed = TRUE))
  expect_true(grepl("stop_on_warning = TRUE", runner_text, fixed = TRUE))
})