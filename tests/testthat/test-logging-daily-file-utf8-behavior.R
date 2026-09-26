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

# Kaynak dosyayı yerel kod sayfasından bağımsız UTF-8 metin olarak okur
# (CP1254 oturumunda readLines(encoding = "UTF-8") geçersiz UTF-8 verebilir).
.log_utf8_source_text <- function(rel_path) {
  metin <- rawToChar(.log_utf8_bytes(file.path(resolve_repo_root_for_tests(), rel_path)))
  Encoding(metin) <- "UTF-8"
  gsub("\r\n?", "\n", sub("^\ufeff", "", metin))
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
  kaynak <- .log_utf8_source_text("R/config_logging_daily_file.R")
  expect_true(validUTF8(kaynak))
  kod <- gsub("#[^\n]*", "", kaynak)
  expect_false(grepl("cat(", kod, fixed = TRUE))
  expect_true(grepl("open = \"ab\"", kod, fixed = TRUE))

  logging <- .log_utf8_source_text("R/config_logging.R")
  expect_true(validUTF8(logging))
  dbg <- regmatches(logging, regexpr("dbg_dump <- function[\\s\\S]*?\n}\n", logging, perl = TRUE))
  expect_length(dbg, 1L)
  expect_true(grepl("mergen_log_write_utf8(", dbg, fixed = TRUE))
})

test_that("eski yazıcının CP1254 satırlı dosyası bayt bayt kenara alınır, yeni satırlar temiz UTF-8 dosyaya yazılır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- env$current_mergen_log_file_path()
  eski <- paste0("INFO [x] ", intToUtf8(c(0x0130L, 0x015FL, 0x0131L, 0x011FL)))
  utf8_satir <- paste0("INFO [y] ", intToUtf8(c(0x00E7L, 0x00FCL)))
  # Aynı gün dosyası: eski yazıcının CP1254 satırı + zaten UTF-8 olan bir satır.
  eski_bayt <- c(iconv(paste0(eski, "\n"), from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]],
                 charToRaw(enc2utf8(paste0(utf8_satir, "\n"))))
  writeBin(eski_bayt, hedef)
  expect_false(env$mergen_log_file_is_utf8(hedef))

  # Yeni süreç: dosya bu süreçte henüz denetlenmedi.
  denetlenen <- env$.MERGEN_LOG_UTF8_CHECKED
  rm(list = ls(denetlenen, all.names = TRUE), envir = denetlenen)
  yeni <- paste0("INFO [z] ", intToUtf8(c(0x015EL, 0x0130L)))
  withr::local_options(encoding = "latin1")
  env$mergen_daily_file_appender(yeni)

  # Günün dosyası yalnız yeni UTF-8 satırı taşır; eski dosya kod sayfası tahmini
  # yapılmadan, bayt bayt kenara alınmıştır.
  expect_identical(.log_utf8_bytes(hedef), charToRaw(enc2utf8(paste0(yeni, "\n"))))
  kenar <- list.files(tmp, pattern = "\\.legacy-.*\\.log$", full.names = TRUE)
  expect_length(kenar, 1L)
  expect_identical(.log_utf8_bytes(kenar), eski_bayt)
  expect_false(any(grepl("utf8tmp|\\.lock$", list.files(tmp, all.files = TRUE))))

  # Süreç başına tek denetim: ikinci yazım dosyayı yeniden taramaz.
  expect_true(env$mergen_log_upgrade_legacy_file(hedef))
})

test_that("kilit başka süreçteyken eski dosyaya UTF-8 eklenmez, yedek dosyaya yazılır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "ai_debug_20260101.log")
  eski_bayt <- iconv("INFO \u0130\u015F\n", from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]]
  writeBin(eski_bayt, hedef)
  # Başka süreç kilidi tutuyor (taze kilit).
  dir.create(paste0(hedef, ".lock"))

  env$mergen_log_write_utf8("yeni satir", hedef)
  expect_identical(.log_utf8_bytes(hedef), eski_bayt)
  expect_identical(.log_utf8_bytes(sub("\\.log$", ".utf8.log", hedef)), charToRaw("yeni satir\n"))
  # Başarısızlık önbelleklenir; dosya her satırda yeniden taranmaz.
  expect_false(env$mergen_log_upgrade_legacy_file(hedef))

  # Bayat kilit kaldırılır ve taşıma tamamlanır.
  rm(list = ls(env$.MERGEN_LOG_UTF8_CHECKED, all.names = TRUE), envir = env$.MERGEN_LOG_UTF8_CHECKED)
  expect_true(env$mergen_log_upgrade_legacy_file(hedef, stale_after = -1))
  expect_false(file.exists(hedef))
  expect_false(dir.exists(paste0(hedef, ".lock")))
})

test_that("UTF-8 doğrulaması sınırlı parçalarla yapılır ve parça sınırında çok baytlı harfi bölmez", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  yol <- file.path(tmp, "parcali.log")
  satir <- paste0(strrep(intToUtf8(0x015FL), 7L), "\n")
  writeBin(rep(charToRaw(enc2utf8(satir)), 20L), yol)
  expect_true(env$mergen_log_file_is_utf8(yol, chunk = 5))
  # Satır sonu olmayan uzun kuyruk da doğrulanır.
  writeBin(c(charToRaw(enc2utf8(strrep(intToUtf8(0x0131L), 40L))), as.raw(0xFD)), yol)
  expect_false(env$mergen_log_file_is_utf8(yol, chunk = 5))
  writeBin(raw(0), yol)
  expect_true(env$mergen_log_file_is_utf8(yol))
})
