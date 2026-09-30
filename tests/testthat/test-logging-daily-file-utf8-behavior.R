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

test_that("NUL baytı taşıyan dosya UTF-8 sayılmaz; zorunlu kesim çok baytlı harfi bölmez", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  yol <- file.path(tmp, "nul.log")
  # UTF-16LE ASCII metni: 41 00 42 00
  writeBin(as.raw(c(0x41, 0x00, 0x42, 0x00, 0x0A, 0x00)), yol)
  expect_false(env$mergen_log_file_is_utf8(yol))

  # Satır sonu olmayan uzun tek satır: parça sınırı 2 baytlı harfin ortasına denk gelir.
  writeBin(c(charToRaw("a"), rep(charToRaw(enc2utf8(intToUtf8(0x015FL))), 60L)), yol)
  expect_true(env$mergen_log_file_is_utf8(yol, chunk = 4))
})

test_that("başka yazıcı sonradan CP1254 eklerse yalnız yeni baytlar denetlenir ve dosya kenara alınır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "karma_20260101.log")
  env$mergen_log_write_utf8("ilk satir", hedef)
  expect_true(env$mergen_log_upgrade_legacy_file(hedef))

  # Eski süreç CP1254 satırı ekler; önbellekteki eski karar kullanılmaz.
  eski <- iconv("İş\n", from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]]
  con <- file(hedef, open = "ab"); writeBin(eski, con); close(con)
  env$mergen_log_write_utf8("yeni satir", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("yeni satir\n"))
  kenar <- list.files(tmp, pattern = "\\.legacy-.*\\.log$", full.names = TRUE)
  expect_length(kenar, 1L)
  expect_identical(.log_utf8_bytes(kenar), c(charToRaw("ilk satir\n"), eski))
})

test_that("aynı saniyedeki ikinci kenara alma önceki legacy dosyasının üzerine yazmaz", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "cakisma_20260101.log")
  eski <- iconv("İ\n", from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]]
  temiz <- function(nabiz = NULL) !file.exists(hedef) || env$mergen_log_file_is_utf8(hedef)
  writeBin(eski, hedef)
  expect_true(env$.mergen_log_move_legacy(hedef, temiz, 1, 60))
  writeBin(c(eski, eski), hedef)
  expect_true(env$.mergen_log_move_legacy(hedef, temiz, 1, 60))
  kenar <- sort(list.files(tmp, pattern = "\\.legacy-.*\\.log$", full.names = TRUE))
  expect_length(kenar, 2L)
  expect_setequal(lapply(kenar, .log_utf8_bytes), list(eski, c(eski, eski)))
})

test_that("kilit sahipliği doğrulanır: kilidi kaybeden süreç dosyayı taşımaz ve başkasının kilidini silmez", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  kilit <- file.path(tmp, "x.lock")
  jeton <- env$.mergen_log_lock_acquire(kilit, 1, 60)
  expect_true(env$.mergen_log_lock_owned(kilit, jeton))
  # Taze kilit (sahibi canlı) başka süreçte kaldırılmaz.
  expect_null(env$.mergen_log_lock_acquire(kilit, 0.1, 60))
  # Başka süreç kilidi devraldıysa eski sahip onu silmez.
  writeLines("baska", file.path(kilit, "sahip"))
  env$.mergen_log_lock_release(kilit, jeton)
  expect_true(dir.exists(kilit))
  unlink(kilit, recursive = TRUE)

  hedef <- file.path(tmp, "sahip_20260101.log")
  eski <- iconv("İ\n", from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]]
  writeBin(eski, hedef)
  # Tarama sırasında kilit başka sürece geçerse taşıma yapılmaz.
  temiz <- function(nabiz = NULL) {
    writeLines("baska", file.path(paste0(hedef, ".lock"), "sahip"))
    FALSE
  }
  expect_false(env$.mergen_log_move_legacy(hedef, temiz, 1, 60))
  expect_identical(.log_utf8_bytes(hedef), eski)
})

test_that("yedek dosyaya düşen satırlar günlük dosya temizlenince ana dosyaya taşınır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "yedek_20260101.log")
  yedek <- sub("\\.log$", ".utf8.log", hedef)
  writeBin(charToRaw("yedekteki satir\n"), yedek)
  env$mergen_log_write_utf8("sonraki satir", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("yedekteki satir\nsonraki satir\n"))
  expect_false(file.exists(yedek))
})

test_that("çok-süreçli dağıtımda eklemeler kilitle sıralanır ve kilit bırakılır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "paylasim_20260101.log")
  withr::local_envvar(c(MERGEN_APP_WORKER_COUNT = "3"))
  expect_true(env$.mergen_log_shared_writers())
  env$mergen_log_write_utf8("satir", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("satir\n"))
  expect_false(dir.exists(paste0(hedef, ".append.lock")))
  withr::local_envvar(c(MERGEN_APP_WORKER_COUNT = "1"))
  expect_false(env$.mergen_log_shared_writers())
})

test_that("paylaşılan ekleme kilidi alınamazsa satır süreç yedeğine yazılır ve sonra birleştirilir", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "kilitli_20260101.log")
  withr::local_envvar(c(MERGEN_APP_WORKER_COUNT = "3"))
  writeBin(charToRaw("ilk\n"), hedef)
  kilit <- paste0(hedef, ".append.lock")
  dir.create(kilit)
  writeLines("baska", file.path(kilit, "sahip"))
  host <- gsub("[^A-Za-z0-9_-]", "_", c(Sys.info()["nodename"], "h")[1])
  surec <- sub("\\.log$", sprintf(".p%s-%d.log", host, Sys.getpid()), hedef)

  basla <- Sys.time()
  env$mergen_log_write_utf8("kilitsiz", hedef)
  env$mergen_log_write_utf8("ertelenen", hedef)
  expect_lt(as.numeric(difftime(Sys.time(), basla, units = "secs")), 1.5)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ilk\n"))
  expect_identical(.log_utf8_bytes(surec), charToRaw("kilitsiz\nertelenen\n"))

  unlink(kilit, recursive = TRUE)
  rm(list = ls(env$.MERGEN_LOG_LOCK_BACKOFF, all.names = TRUE), envir = env$.MERGEN_LOG_LOCK_BACKOFF)
  env$mergen_log_write_utf8("sonra", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ilk\nkilitsiz\nertelenen\nsonra\n"))
  expect_false(file.exists(surec))
})

test_that("sahip dosyası yazılamazsa kilit dizini yetim bırakılmaz", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  kilit <- file.path(tmp, "y.lock")
  env$writeLines <- function(...) stop("disk dolu")
  expect_null(env$.mergen_log_lock_acquire(kilit, 0.1, 60))
  expect_false(dir.exists(kilit))
})

test_that("aynı boyutta değiştirilen dosya önbellek kararıyla kabul edilmez", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "degisen_20260101.log")
  env$mergen_log_write_utf8("ab", hedef)
  expect_true(env$mergen_log_upgrade_legacy_file(hedef))
  eski <- iconv("İş\n", from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]]
  expect_equal(length(eski), file.info(hedef)$size)
  writeBin(eski, hedef)
  Sys.setFileTime(hedef, Sys.time() + 5)
  env$mergen_log_write_utf8("yeni", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("yeni\n"))
  expect_length(list.files(tmp, pattern = "\\.legacy-.*\\.log$"), 1L)
})

test_that("araya giren yabancı baytlar varsa doğrulanan boyut ilerletilmez", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "yaris_20260101.log")
  env$mergen_log_write_utf8("ilk", hedef)
  once <- file.info(hedef)$size
  asil <- env$mergen_log_append_utf8
  # Eski süreç bu yazımla son boyut ölçümü arasında CP1254 baytı ekler.
  env$mergen_log_append_utf8 <- function(lines, target_file) {
    n <- asil(lines, target_file)
    con <- file(target_file, open = "ab"); writeBin(as.raw(0xFD), con); close(con)
    n
  }
  env$mergen_log_write_utf8("benim", hedef)
  anahtar <- normalizePath(hedef, winslash = "/", mustWork = FALSE)
  expect_identical(env$.MERGEN_LOG_UTF8_CHECKED[[anahtar]]$boyut, once)
  env$mergen_log_append_utf8 <- asil
  env$mergen_log_write_utf8("sonra", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("sonra\n"))
  expect_length(list.files(tmp, pattern = "\\.legacy-.*\\.log$"), 1L)
})

test_that("yedek birleştirilemezse yeni satırlar yedeğe eklenir; yarım kopya geri alınır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "sira_20260101.log")
  yedek <- sub("\\.log$", ".utf8.log", hedef)
  writeBin(charToRaw("ana\n"), hedef)
  writeBin(charToRaw("eski yedek\n"), yedek)
  dir.create(paste0(hedef, ".lock"))
  env$mergen_log_write_utf8("yeni", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\n"))
  expect_identical(.log_utf8_bytes(yedek), charToRaw("eski yedek\nyeni\n"))
  unlink(paste0(hedef, ".lock"), recursive = TRUE)

  cagri <- 0L
  env$writeBin <- function(object, con, ...) {
    cagri <<- cagri + 1L
    base::writeBin(object, con, ...)
    stop("UNC hatası")
  }
  expect_false(env$.mergen_log_merge_fallback(hedef, yedek))
  expect_identical(cagri, 1L)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\n"))
  expect_true(file.exists(yedek))
  rm("writeBin", envir = env)
  expect_true(env$.mergen_log_merge_fallback(hedef, yedek, nabiz = function() cagri <<- cagri + 10L))
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\neski yedek\nyeni\n"))
  expect_gt(cagri, 1L)
})

test_that("önbellekteki baş baytlar farklıysa aynı boyut/mtime dosya yeniden taranır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "bas_20260101.log")
  env$mergen_log_write_utf8("ab", hedef)
  expect_true(env$mergen_log_upgrade_legacy_file(hedef))
  zaman <- file.info(hedef)$mtime
  eski <- iconv("İş\n", from = "UTF-8", to = "WINDOWS-1254", toRaw = TRUE)[[1]]
  writeBin(eski, hedef)
  Sys.setFileTime(hedef, zaman)
  env$mergen_log_write_utf8("yeni", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("yeni\n"))
  expect_length(list.files(tmp, pattern = "\\.legacy-.*\\.log$"), 1L)
})

test_that("UNC log dizini ve açık ayar paylaşılan yazıcı sayılır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  withr::local_envvar(c(MERGEN_APP_WORKER_COUNT = "1", MERGEN_LOG_SHARED_WRITERS = ""))
  expect_true(env$.mergen_log_shared_writers("\\\\srv\\paylasim\\mergen_20260101.log"))
  expect_true(env$.mergen_log_shared_writers("//srv/paylasim/mergen_20260101.log"))
  expect_false(env$.mergen_log_shared_writers(file.path(tmp, "mergen_20260101.log")))
  withr::local_envvar(c(MERGEN_LOG_SHARED_WRITERS = "true"))
  expect_true(env$.mergen_log_shared_writers(file.path(tmp, "mergen_20260101.log")))
})

test_that("kapanmış işçinin eski yedeği kilit altında birleştirilir; taze yedeğe dokunulmaz", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  withr::local_envvar(c(MERGEN_APP_WORKER_COUNT = "3"))
  hedef <- file.path(tmp, "isci_20260101.log")
  writeBin(charToRaw("ana\n"), hedef)
  eski <- sub("\\.log$", ".pbaska-11.log", hedef)
  taze <- sub("\\.log$", ".pbaska-12.log", hedef)
  writeBin(charToRaw("yetim\n"), eski)
  Sys.setFileTime(eski, Sys.time() - 600)
  writeBin(charToRaw("canli\n"), taze)
  env$mergen_log_write_utf8("yeni", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\nyetim\nyeni\n"))
  expect_false(file.exists(eski))
  expect_identical(.log_utf8_bytes(taze), charToRaw("canli\n"))
})

test_that("geri alma doğrulanamazsa yedek yeniden denenmez ve satırlar iki kez eklenmez", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "geri_20260101.log")
  yedek <- sub("\\.log$", ".utf8.log", hedef)
  writeBin(charToRaw("ana\n"), hedef)
  writeBin(charToRaw("yedek\n"), yedek)
  env$writeBin <- function(object, con, ...) {
    base::writeBin(object, con, ...)
    stop("UNC hatası")
  }
  env$truncate <- function(con, ...) stop("kesilemedi")
  expect_false(env$.mergen_log_merge_fallback(hedef, yedek))
  expect_false(file.exists(yedek))
  expect_length(list.files(tmp, pattern = "\\.birlesmedi-.*\\.log$"), 1L)
})

test_that("ekleme kilidinin sahipliği kaybedilirse satır ana dosyaya yazılmaz", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  withr::local_envvar(c(MERGEN_APP_WORKER_COUNT = "3"))
  hedef <- file.path(tmp, "sahip_20260101.log")
  writeBin(charToRaw("ana\n"), hedef)
  env$.mergen_log_lock_owned <- function(kilit, jeton) !grepl("append", kilit)
  env$mergen_log_write_utf8("kayip", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\n"))
  expect_length(list.files(tmp, pattern = "\\.p.*\\.log$"), 1L)
})

test_that("MERGEN_LOG_SHARED_WRITERS 1/yes/on değerleri de paylaşılan yazıcı sayılır", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  withr::local_envvar(c(MERGEN_APP_WORKER_COUNT = "1"))
  for (deger in c("1", "yes", "ON")) {
    withr::local_envvar(c(MERGEN_LOG_SHARED_WRITERS = deger))
    expect_true(env$.mergen_log_shared_writers(file.path(tmp, "mergen_20260101.log")))
  }
  withr::local_envvar(c(MERGEN_LOG_SHARED_WRITERS = "0"))
  expect_false(env$.mergen_log_shared_writers(file.path(tmp, "mergen_20260101.log")))
})

test_that("silinemeyen yedek birleşen bayt kaydıyla sürer; satırlar iki kez eklenmez", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "sil_20260101.log")
  yedek <- sub("\\.log$", ".utf8.log", hedef)
  writeBin(charToRaw("ana\n"), hedef)
  writeBin(charToRaw("yedek\n"), yedek)
  env$unlink <- function(x, ...) if (identical(x, yedek)) invisible(1L) else base::unlink(x, ...)
  expect_true(env$.mergen_log_merge_fallback(hedef, yedek))
  expect_true(file.exists(yedek))
  env$mergen_log_write_utf8("yeni", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\nyedek\nyeni\n"))
  rm("unlink", envir = env)
  env$mergen_log_write_utf8("son", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\nyedek\nyeni\nson\n"))
  expect_false(file.exists(yedek))
  expect_false(file.exists(paste0(yedek, ".birlesen")))
})

test_that("geri alma ve karantina başarısızsa kısmi kopya kaydedilir; yeniden deneme çoğaltmaz", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "kar_20260101.log")
  yedek <- sub("\\.log$", ".utf8.log", hedef)
  writeBin(charToRaw("ana\n"), hedef)
  writeBin(charToRaw("bir\niki\n"), yedek)
  env$readBin <- function(con, what, n, ...) base::readBin(con, what, n = min(n, 4L), ...)
  sayac <- 0L
  env$writeBin <- function(object, con, ...) {
    sayac <<- sayac + 1L
    if (sayac > 1L) stop("UNC hatası")
    base::writeBin(object, con, ...)
  }
  env$truncate <- function(con, ...) stop("kesilemedi")
  env$file.rename <- function(from, to) FALSE
  expect_false(env$.mergen_log_merge_fallback(hedef, yedek))
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\nbir\n"))
  expect_true(file.exists(yedek))
  rm(list = c("readBin", "writeBin", "truncate", "file.rename"), envir = env)
  expect_true(env$.mergen_log_merge_fallback(hedef, yedek))
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\nbir\niki\n"))
})

test_that("sahiplenilip birleştirilemeyen yetim yedek sonraki yazımda yeniden denenir", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  withr::local_envvar(c(MERGEN_APP_WORKER_COUNT = "3"))
  hedef <- file.path(tmp, "yetim_20260101.log")
  writeBin(charToRaw("ana\n"), hedef)
  eski <- sub("\\.log$", ".pbaska-11.log", hedef)
  writeBin(charToRaw("yetim\n"), eski)
  Sys.setFileTime(eski, Sys.time() - 600)
  asil <- env$.mergen_log_merge_fallback
  env$.mergen_log_merge_fallback <- function(target_file, yedek, nabiz = NULL) {
    if (grepl("-m[0-9]+\\.log$", yedek)) return(invisible(FALSE))
    asil(target_file, yedek, nabiz)
  }
  env$mergen_log_write_utf8("bir", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\n"))
  env$.mergen_log_merge_fallback <- asil
  env$mergen_log_write_utf8("iki", hedef)
  expect_identical(.log_utf8_bytes(hedef), charToRaw("ana\nyetim\nbir\niki\n"))
  expect_length(list.files(tmp, pattern = "\\.pbaska"), 0L)
})


test_that("yetim günlük sahiplenilirken bayt kaydı kopyalanamazsa yeniden eklenmez", {
  skip_if_not_installed("logger")
  tmp <- withr::local_tempdir()
  env <- .log_utf8_env(tmp)
  hedef <- file.path(tmp, "deneme.log")
  yedek <- file.path(tmp, "deneme.peski-1.log")
  writeBin(charToRaw("bir\niki\n"), yedek)
  writeBin(charToRaw("bir\n"), hedef)
  writeLines("4", paste0(yedek, ".birlesen"))
  Sys.setFileTime(yedek, Sys.time() - 120)
  env$file.copy <- function(...) FALSE
  expect_length(env$.mergen_log_orphan_fallbacks(hedef, "kendi.log", TRUE), 0L)
  expect_true(file.exists(yedek))
  rm("file.copy", envir = env)
  sahip <- env$.mergen_log_orphan_fallbacks(hedef, "kendi.log", TRUE)
  expect_length(sahip, 1L)
  expect_equal(env$.mergen_log_merged_offset(sahip), 4)
  expect_true(env$.mergen_log_merge_fallback(hedef, sahip))
  expect_identical(rawToChar(.log_utf8_bytes(hedef)), "bir\niki\n")
})
