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

.fail_unless <- function(condition, message) {
  if (!isTRUE(condition)) {
    testthat::fail(message)
  }
  invisible(TRUE)
}

test_that("tüm temel R dosyaları UTF-8 ile parse edilebilir", {
  r_files <- c(
    list.files(
      file.path(.repo_root, "R"),
      pattern = "\\.R$",
      full.names = TRUE,
      recursive = TRUE
    ),
    file.path(.repo_root, c("app.R", "global.R", "ui.R", "server.R", "welcome_screen.R"))
  )

  r_files <- unique(r_files[file.exists(r_files)])

  .fail_unless(
    length(r_files) > 10L,
    sprintf("Parse testi için beklenenden az R dosyası bulundu: %d", length(r_files))
  )

  parse_errors <- list()

  for (f in r_files) {
    err <- tryCatch(
      {
        parse(file = f, encoding = "UTF-8", keep.source = FALSE)
        NULL
      },
      error = function(e) e,
      warning = function(w) w
    )

    if (!is.null(err)) {
      parse_errors[[length(parse_errors) + 1L]] <- sprintf(
        "%s\n  -> %s",
        normalizePath(f, winslash = "/", mustWork = FALSE),
        conditionMessage(err)
      )
    }
  }

  if (length(parse_errors) > 0L) {
    testthat::fail(paste(
      "Aşağıdaki R dosyaları UTF-8 parse kontrolünden geçemedi:",
      paste(parse_errors, collapse = "\n\n"),
      sep = "\n"
    ))
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

  eksikler <- beklenenler[!vapply(
    beklenenler,
    function(beklenen) grepl(beklenen, global_text, fixed = TRUE),
    logical(1)
  )]

  if (length(eksikler) > 0L) {
    testthat::fail(paste(
      "global.R manifestinde eksik üretim helper source kayıtları:",
      paste(eksikler, collapse = "\n"),
      sep = "\n"
    ))
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

  eksikler <- beklenenler[!vapply(
    beklenenler,
    function(beklenen) grepl(beklenen, app_text, fixed = TRUE),
    logical(1)
  )]

  if (length(eksikler) > 0L) {
    testthat::fail(paste(
      "app.R boot sözleşmesinde eksik kayıtlar:",
      paste(eksikler, collapse = "\n"),
      sep = "\n"
    ))
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

  ihlaller <- unique(ihlaller)

  if (length(ihlaller) > 0L) {
    testthat::fail(paste(
      "future_promise doğrudan kullanılmamalı; tracked_future_promise kullanın:",
      paste(ihlaller, collapse = "\n"),
      sep = "\n"
    ))
  }
})

test_that("test runner Shiny/future başlatmayı kapatan env bayraklarını içeriyor", {
  runner_path <- file.path(.repo_root, "tests", "testthat.R")

  .fail_unless(
    file.exists(runner_path),
    sprintf("tests/testthat.R bulunamadı: %s", runner_path)
  )

  runner_text <- paste(.read_utf8(runner_path), collapse = "\n")

  beklenenler <- c(
    'MERGEN_RUN_APP = "false"',
    'MERGEN_DISABLE_FUTURES = "true"',
    "stop_on_failure = TRUE",
    "stop_on_warning = TRUE"
  )

  eksikler <- beklenenler[!vapply(
    beklenenler,
    function(beklenen) grepl(beklenen, runner_text, fixed = TRUE),
    logical(1)
  )]

  if (length(eksikler) > 0L) {
    testthat::fail(paste(
      "tests/testthat.R üretim güvenliği sözleşmesinde eksik kayıtlar:",
      paste(eksikler, collapse = "\n"),
      sep = "\n"
    ))
  }
})