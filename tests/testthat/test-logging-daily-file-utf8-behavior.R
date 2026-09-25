# ==============================================================================
# Dosya Yolu: tests/testthat/test-logging-daily-file-utf8-behavior.R
# Açıklama: Günlük log dosyası (mergen_YYYYMMDD.log) yerel ayardan ve
#           options(encoding) değerinden bağımsız olarak UTF-8 bayt içermelidir.
#           Eski cat(file=) yazımı Windows VM'de (CP1254) dosyaya CP1254
#           baytları düşürüyor, UTF-8 okuyan canlı log görüntüleyicisinde Türkçe
#           karakterler mojibake görünüyordu.
# ==============================================================================

# config_logging.R'yi yükler ve logger'ın süreç-global durumunu (threshold,
# appender/layout, shiny.error) çağıran test bitince geri yükler; geri yükleme
# local_tempdir() dizini silinmeden önce çalışır (defer LIFO).
.log_utf8_env <- function(log_dir) {
  eski_threshold <- logger::log_threshold()
  eski_app1 <- tryCatch(logger::log_appender(index = 1), error = function(e) NULL)
  eski_lay1 <- tryCatch(logger::log_layout(index = 1), error = function(e) NULL)
  eski_shiny_error <- getOption("shiny.error")
  withr::defer({
    tryCatch(logger::delete_logger_index(index = 2), error = function(e) NULL)
    if (!is.null(eski_app1)) tryCatch(logger::log_appender(eski_app1, index = 1), error = function(e) NULL)
    if (!is.null(eski_lay1)) tryCatch(logger::log_layout(eski_lay1, index = 1), error = function(e) NULL)
    tryCatch(logger::log_threshold(eski_threshold), error = function(e) NULL)
    options(shiny.error = eski_shiny_error)
  }, envir = parent.frame())

  env <- new.env(parent = globalenv())
  withr::with_envvar(c(MERGEN_LOG_DIR = log_dir, MERGEN_LOG_THRESHOLD = "info"), {
    suppressMessages(source(
      file.path(resolve_repo_root_for_tests(), "R", "config_logging.R"),
      encoding = "UTF-8",
      local = env
    ))
  })
  env
}

.log_utf8_bytes <- function(path) {
  readBin(path, what = "raw", n = file.info(path)$size)
}

test_that("günlük dosya appender'ı Türkçe satırı options(encoding) ne olursa olsun UTF-8 yazar", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  satir <- paste0("INFO [x] ", intToUtf8(c(0x0130L, 0x015FL, 0x011FL, 0x0131L, 0x00E7L, 0x00F6L, 0x00FCL)))

  withr::local_options(encoding = "latin1")
  env$mergen_daily_file_appender(satir)

  hedef <- env$current_mergen_log_file_path()
  ham <- .log_utf8_bytes(hedef)
  beklenen <- charToRaw(enc2utf8(paste0(satir, "\n")))
  n <- length(beklenen)
  expect_identical(ham[(length(ham) - n + 1L):length(ham)], beklenen)
  expect_true(validUTF8(rawToChar(ham)))
})

test_that("NA satırı ve Türkçe metin ayrı dosyaya da UTF-8 bayt olarak eklenir", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "ayri.log")

  metin <- intToUtf8(c(0x015FL, 0x0131L))
  env$mergen_log_append_utf8(c(metin, NA_character_), hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw(enc2utf8(paste0(metin, "\nNA\n"))))
})

test_that("açılış başlığı ve dbg_dump da UTF-8 ikili yazımı kullanır", {
  kaynak <- paste(readLines(file.path(resolve_repo_root_for_tests(), "R", "config_logging_daily_file.R"),
                            warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  kod <- gsub("#[^\n]*", "", kaynak)
  expect_false(grepl("cat(", kod, fixed = TRUE))
  expect_true(grepl("open = \"ab\"", kod, fixed = TRUE))

  logging <- paste(readLines(file.path(resolve_repo_root_for_tests(), "R", "config_logging.R"),
                             warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  dbg <- regmatches(logging, regexpr("dbg_dump <- function[\\s\\S]*?\n}\n", logging, perl = TRUE))
  expect_length(dbg, 1L)
  expect_true(grepl("mergen_log_append_utf8(", dbg, fixed = TRUE))
})
