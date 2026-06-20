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

test_that("acilis gunluk log dosyasi YUKSEK threshold'da bile olusur (esik-bagimsiz)", {
  # Haziran regresyonunun kok belirtisi: dosya yalnizca esigi (threshold) gecen
  # bir logger satiri yazildiginda olusuyordu. MERGEN_LOG_THRESHOLD=warn/error
  # ise acilistaki INFO satirlari filtrelenir ve gun boyu hic uyari/hata olmazsa
  # dosya HIC olusmaz. mergen_ensure_daily_log_file() dogrudan cat() ile yazarak
  # bu durumu kapatir: dosya, threshold ne olursa olsun acilista olusmalidir.
  skip_if_not_installed("logger")

  tmp <- withr::local_tempdir()
  env <- new.env(parent = globalenv())

  withr::with_envvar(c(MERGEN_LOG_DIR = tmp, MERGEN_LOG_THRESHOLD = "error"), {
    expect_no_error(suppressMessages(source(
      file.path(resolve_repo_root_for_tests(), "R", "config_logging.R"),
      encoding = "UTF-8",
      local = env
    )))
  })

  log_file <- file.path(tmp, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))
  expect_true(file.exists(log_file))
  # INFO satirlari error esiginde filtrelenir; ama dogrudan yazilan acilis basligi
  # her zaman dosyada olmalidir.
  expect_match(
    paste(readLines(log_file, warn = FALSE), collapse = "\n"),
    "gunluk log dosyasi hazir",
    fixed = TRUE
  )
})

test_that("yazilamayan birincil log dizini yerel 'logs' dizinine duser ve dosya yine olusur", {
  # UNC paylasimi/izin sorununda loglari sessizce kaybetmek yerine repo kokundeki
  # yerel logs dizinine dusulur ve durum konsola yuksek sesle bildirilir.
  skip_if_not_installed("logger")

  # Ebeveyni bir DOSYA olan yol: dir.create asla basaramaz -> yazilamaz birincil dizin.
  blocker <- withr::local_tempfile()
  file.create(blocker)
  unwritable_dir <- file.path(blocker, "logs")

  # config_logging.R yolunu calisma dizini degismeden ONCE coz: with_dir icinde
  # repo koku tespiti calisma dizinine baglidir ve yanlis dizinde basarisiz olur.
  config_logging_path <- file.path(
    resolve_repo_root_for_tests(), "R", "config_logging.R"
  )

  work_root <- withr::local_tempdir()
  env <- new.env(parent = globalenv())
  captured <- character(0)

  withr::with_dir(work_root, {
    withr::with_envvar(c(MERGEN_LOG_DIR = unwritable_dir, MERGEN_LOG_THRESHOLD = "info"), {
      withCallingHandlers(
        suppressWarnings(source(
          config_logging_path,
          encoding = "UTF-8",
          local = env
        )),
        message = function(m) {
          captured <<- c(captured, conditionMessage(m))
          invokeRestart("muffleMessage")
        }
      )
    })
  })

  # Yerel 'logs' dizinine dusulmus olmali ve bu durum bildirilmis olmali.
  expect_true(any(grepl("Yerel dizine dusuluyor", captured, fixed = TRUE)))
  expect_equal(basename(env$mergen_log_dir), "logs")

  fallback_file <- file.path(
    env$mergen_log_dir,
    sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d"))
  )
  expect_true(file.exists(fallback_file))
})

test_that("config_logging gunluk dosya yardimcilarini calisma dizininden bagimsiz, dogru ortama baglar", {
  # Regresyon: gunluk dosya yardimcilari (mergen_daily_file_appender,
  # current_mergen_log_file_path, ...) ayri bir dosyaya (config_logging_daily_file.R)
  # bolunmustu. Izole test/debug akisinda config_logging.R repo disi bir calisma
  # dizininden ve MERGEN_REPO_ROOT TANIMSIZ iken source() edilebilir; bu durumda
  # kardes dosya getwd()/MERGEN_REPO_ROOT adaylariyla BULUNAMAZ ve yardimcilar ya
  # tanimsiz kalir ya da global (yanlis mergen_log_dir kapanisli) kopyalara duser.
  # Dogru davranis: yardimcilar source edilen ORTAMA baglanmali (inherits = FALSE)
  # ve o ortamin mergen_log_dir'ine yazmalidir.
  skip_if_not_installed("logger")

  config_logging_path <- file.path(
    resolve_repo_root_for_tests(), "R", "config_logging.R"
  )

  work_root <- withr::local_tempdir()       # repo disi bir calisma dizini
  test_log_dir <- file.path(withr::local_tempdir(), "izole-log-dizini")
  env <- new.env(parent = globalenv())

  withr::with_dir(work_root, {
    withr::with_envvar(
      c(
        MERGEN_LOG_DIR = test_log_dir,
        MERGEN_LOG_THRESHOLD = "info",
        MERGEN_REPO_ROOT = NA   # tanimsiz birak: yalnizca ofile-temelli cozumleme kalir
      ),
      suppressMessages(source(config_logging_path, encoding = "UTF-8", local = env))
    )
  })

  # Yardimcilar tam olarak source edilen ortama baglanmali.
  expect_true(exists("current_mergen_log_file_path", envir = env, inherits = FALSE))
  expect_true(exists("mergen_daily_file_appender", envir = env, inherits = FALSE))

  # Cozulen dosya yolu, env'in mergen_log_dir'i altinda olmali (global degil).
  expect_equal(
    normalizePath(dirname(env$log_file_path), winslash = "/", mustWork = FALSE),
    normalizePath(env$mergen_log_dir, winslash = "/", mustWork = FALSE)
  )

  # Acilis garantisi gunun dosyasini bu izole dizinde olusturmali.
  expected_file <- file.path(
    env$mergen_log_dir,
    sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d"))
  )
  expect_true(file.exists(expected_file))
})