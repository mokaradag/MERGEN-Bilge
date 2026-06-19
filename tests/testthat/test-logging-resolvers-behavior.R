# ==============================================================================
# Dosya Yolu: tests/testthat/test-logging-resolvers-behavior.R
# Açıklama: R/config_logging.R ortam-temelli çözümleyicilerinin davranışsal
#           testleri: resolve_mergen_log_dir (MERGEN_LOG_DIR / varsayılan) ve
#           resolve_mergen_log_threshold (MERGEN_LOG_THRESHOLD -> logger seviyesi).
#           CLAUDE.md: log yolu/eşiği ortamdan yapılandırılabilir olmalıdır.
# ==============================================================================

testthat::local_edition(3)

.log_env <- new.env(parent = globalenv())
# config_logging kaynak yüklemede tek seferlik INFO mesajı basar; konsolu temiz tut.
suppressMessages(source(
  file.path(resolve_repo_root_for_tests(), "R", "config_logging.R"),
  encoding = "UTF-8",
  local = .log_env
))

test_that("resolve_mergen_log_dir MERGEN_LOG_DIR ayarlıysa onu kullanır", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(c(MERGEN_LOG_DIR = tmp))
  expect_equal(
    .log_env$resolve_mergen_log_dir(),
    normalizePath(tmp, winslash = "/", mustWork = FALSE)
  )
})

test_that("resolve_mergen_log_dir env boşsa verilen varsayılana düşer", {
  withr::local_envvar(c(MERGEN_LOG_DIR = ""))
  expect_equal(basename(.log_env$resolve_mergen_log_dir()), "logs")
  expect_equal(basename(.log_env$resolve_mergen_log_dir(default = "ozel_kayit")), "ozel_kayit")
})

test_that("resolve_mergen_log_threshold ortam değişkenini logger seviyesine eşler", {
  skip_if_not_installed("logger")

  withr::with_envvar(c(MERGEN_LOG_THRESHOLD = "debug"),
    expect_identical(.log_env$resolve_mergen_log_threshold(), logger::DEBUG))
  withr::with_envvar(c(MERGEN_LOG_THRESHOLD = "warn"),
    expect_identical(.log_env$resolve_mergen_log_threshold(), logger::WARN))
  withr::with_envvar(c(MERGEN_LOG_THRESHOLD = "error"),
    expect_identical(.log_env$resolve_mergen_log_threshold(), logger::ERROR))
  withr::with_envvar(c(MERGEN_LOG_THRESHOLD = "trace"),
    expect_identical(.log_env$resolve_mergen_log_threshold(), logger::TRACE))
})

test_that("resolve_mergen_log_threshold bilinmeyen değerde varsayılana (INFO) döner", {
  skip_if_not_installed("logger")
  withr::with_envvar(c(MERGEN_LOG_THRESHOLD = "anlamsiz_deger"),
    expect_identical(.log_env$resolve_mergen_log_threshold(), logger::INFO))
})

test_that("config_logging açılışta bugünün günlük log dosyasını oluşturur", {
  # Haziran regresyon koruması: config_logging.R source edildiginde (uygulama
  # acilisi) bugune ait mergen_YYYYMMDD.log dosyasi olusmali ve baslangic
  # mesajini icermeli. Konsol logu ayri appender oldugu icin bu, "konsola yaziliyor
  # ama dosya olusmuyor" durumunu dogrudan yakalar.
  skip_if_not_installed("logger")

  tmp <- withr::local_tempdir()
  env <- new.env(parent = globalenv())

  withr::with_envvar(c(MERGEN_LOG_DIR = tmp), {
    expect_no_error(suppressMessages(source(
      file.path(resolve_repo_root_for_tests(), "R", "config_logging.R"),
      encoding = "UTF-8",
      local = env
    )))
  })

  log_file <- file.path(tmp, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))
  expect_true(file.exists(log_file))
  expect_match(
    paste(readLines(log_file, warn = FALSE), collapse = "\n"),
    "Application starting up",
    fixed = TRUE
  )
})