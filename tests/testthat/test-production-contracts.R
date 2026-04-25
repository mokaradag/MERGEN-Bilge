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
    list.files(
      file.path(.repo_root, "R"),
      pattern = "\\.R$",
      full.names = TRUE,
      recursive = TRUE
    ),
    file.path(.repo_root, c("app.R", "global.R", "ui.R", "server.R", "welcome_screen.R"))
  )

  r_files <- unique(r_files[file.exists(r_files)])

  expect_gt(length(r_files), 10L)

  parse_errors <- character(0)
  parse_warnings <- character(0)

  for (f in r_files) {
    file_label <- normalizePath(f, winslash = "/", mustWork = FALSE)

    err <- tryCatch(
      withCallingHandlers(
        {
          parse(file = f, encoding = "UTF-8", keep.source = FALSE)
          NULL
        },
        warning = function(w) {
          # test_dir(stop_on_warning=TRUE) bu uyarıları dışarı taşırsa koşum
          # gürültülü/sonsuz gibi görünür. Burada yakalayıp kaydediyoruz.
          parse_warnings <<- c(
            parse_warnings,
            sprintf("%s\n  -> %s", file_label, conditionMessage(w))
          )
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) e
    )

    if (!is.null(err)) {
      parse_errors <- c(
        parse_errors,
        sprintf("%s\n  -> %s", file_label, conditionMessage(err))
      )
    }
  }

  if (length(parse_warnings) > 0L) {
    message(sprintf(
      "[production-contracts] %d parse warning yakalandı ve test koşumuna sızdırılmadı.",
      length(parse_warnings)
    ))
  }

  expect_equal(
    parse_errors,
    character(0),
    label = paste(parse_errors, collapse = "\n\n")
  )
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

  bulunanlar <- vapply(
    beklenenler,
    function(beklenen) grepl(beklenen, global_text, fixed = TRUE),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    label = paste("Eksik source kayıtları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
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

  bulunanlar <- vapply(
    beklenenler,
    function(beklenen) grepl(beklenen, app_text, fixed = TRUE),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    label = paste("Eksik app.R boot kayıtları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
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

    ham_kullanim <- suppressWarnings(
      grepl("(^|[^A-Za-z0-9_.])future_promise\\s*\\(", txt, useBytes = TRUE) |
        grepl("promises::future_promise\\s*\\(", txt, useBytes = TRUE)
    )

    if (any(ham_kullanim) && !(f_norm %in% izinli_dosyalar)) {
      ihlaller <- c(ihlaller, f_norm)
    }
  }

  ihlaller <- unique(ihlaller)

  expect_equal(
    ihlaller,
    character(0),
    label = paste("Doğrudan future_promise kullanan dosyalar:", paste(ihlaller, collapse = ", "))
  )
})

test_that("test runner Shiny/future başlatmayı kapatan env bayraklarını içeriyor", {
  runner_path <- file.path(.repo_root, "tests", "testthat.R")

  expect_true(file.exists(runner_path))

  runner_text <- paste(.read_utf8(runner_path), collapse = "\n")

  beklenenler <- c(
    'MERGEN_RUN_APP = "false"',
    'MERGEN_DISABLE_FUTURES = "true"',
    "stop_on_failure = TRUE",
    "stop_on_warning = TRUE"
  )

  bulunanlar <- vapply(
    beklenenler,
    function(beklenen) grepl(beklenen, runner_text, fixed = TRUE),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    label = paste("Eksik test runner güvenlik kayıtları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
})