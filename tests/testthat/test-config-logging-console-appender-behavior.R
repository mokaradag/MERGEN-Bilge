# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-logging-console-appender-behavior.R
# Açıklama: config_logging.R içindeki mergen_console_appender davranışını doğrular.
#           Bu appender konsola yazılan log satırlarını normalize eder, native
#           kodlamaya çevirir (Windows "wide string" uyarısını önlemek için) ve
#           cat ile basar. config_logging.R kaynak-zamanı logger global durumunu
#           değiştirdiği için (threshold/appender/layout) geçici log dizini ile
#           yüklenir ve global logger durumu test sonunda geri yüklenir.
#           Çevrimdışı, deterministik; gerçek log dosyasına bağımlılık yok.
# ==============================================================================

testthat::skip_if_not_installed("logger")

# Türkçe yorum: config_logging.R'yi izole ortama, geçici log dizini ile yükler ve
# logger'ın süreç-global durumunu test sonunda geri yükler (test-config-logging-
# sinks-behavior.R ile aynı korumalı desen).
.consoleAppenderEnv <- function() {
  log_dir <- withr::local_tempdir(.local_envir = parent.frame())

  eski_threshold <- logger::log_threshold()
  eski_app1 <- tryCatch(logger::log_appender(index = 1), error = function(e) NULL)
  eski_lay1 <- tryCatch(logger::log_layout(index = 1), error = function(e) NULL)

  withr::defer({
    tryCatch(logger::delete_logger_index(index = 2), error = function(e) NULL)
    if (!is.null(eski_app1)) tryCatch(logger::log_appender(eski_app1, index = 1), error = function(e) NULL)
    if (!is.null(eski_lay1)) tryCatch(logger::log_layout(eski_lay1, index = 1), error = function(e) NULL)
    tryCatch(logger::log_threshold(eski_threshold), error = function(e) NULL)
  }, envir = parent.frame())

  env <- new.env(parent = globalenv())
  withr::with_envvar(
    c(MERGEN_LOG_DIR = log_dir, MERGEN_LOG_CONSOLE_COLORS = "false"),
    suppressMessages(
      source(file.path(resolve_repo_root_for_tests(), "R", "config_logging.R"),
             encoding = "UTF-8", local = env)
    )
  )
  # Konsol appender'ını (index 2) test koşumunda susturarak gürültüyü önle
  logger::log_appender(function(lines) invisible(NULL), index = 2)
  env
}

test_that("mergen_console_appender tek satırı cat ile basar", {
  env <- .consoleAppenderEnv()
  cikti <- utils::capture.output(env$mergen_console_appender("merhaba dunya"))
  expect_true(any(grepl("merhaba dunya", cikti, fixed = TRUE)))
})

test_that("mergen_console_appender NULL girdide hata vermez", {
  env <- .consoleAppenderEnv()
  # Türkçe yorum: NULL -> "" -> yalnızca yeni satır; hata olmamalı
  expect_silent(suppressWarnings(invisible(utils::capture.output(
    env$mergen_console_appender(NULL)
  ))))
})

test_that("mergen_console_appender birden fazla satırı basar", {
  env <- .consoleAppenderEnv()
  cikti <- utils::capture.output(env$mergen_console_appender(c("satir-a", "satir-b")))
  duz <- paste(cikti, collapse = "\n")
  expect_true(grepl("satir-a", duz, fixed = TRUE))
  expect_true(grepl("satir-b", duz, fixed = TRUE))
})

test_that("mergen_console_appender normalize_text_for_log mevcutsa onu kullanır", {
  env <- .consoleAppenderEnv()
  # Türkçe yorum: env'e tanınabilir önekli stub koyunca appender onu kullanmalı
  env$normalize_text_for_log <- function(lines) paste0("NORM:", lines)
  cikti <- utils::capture.output(env$mergen_console_appender("icerik"))
  expect_true(any(grepl("NORM:icerik", cikti, fixed = TRUE)))
})

test_that("mergen_console_appender Linux UTF-8'de Türkçe karakterleri korur", {
  env <- .consoleAppenderEnv()
  # Türkçe yorum: C.UTF-8 yerel kodlamada native dönüşüm kimliktir -> Türkçe korunur
  cikti <- utils::capture.output(env$mergen_console_appender("Türkçe: çğışöü"))
  expect_true(any(grepl("Türkçe: çğışöü", cikti, fixed = TRUE)))
})
