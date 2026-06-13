# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-logging-sinks-behavior.R
# Açıklama: config_logging.R log sink'leri için davranış testleri:
#           log_ai_call, log_user_action, log_error_with_context ve
#           .forward_log_call. Gerçek logger dosya appender'ı geçici dizine
#           yönlendirilir ve dosyaya yazılan satırlar doğrulanır; böylece
#           kırılgan frame-sayımlı glue stub'larına gerek kalmaz. Çağıran-frame
#           glue çözümleme sözleşmesi (CLAUDE.md 9C) da burada korunur.
#           Test sonunda logger global durumu geri yüklenir.
# ==============================================================================

testthat::skip_if_not_installed("logger")

# config_logging.R'yi izole ortama, geçici log dizini ile yükler ve logger'ın
# süreç-global durumunu (threshold + appender/layout) test sonunda geri yükler.
.loggingSinksEnv <- function(log_dir, env_extra = c()) {
  # Mevcut global logger durumunu yakala (yalnızca var olan indeksler)
  eski_threshold <- logger::log_threshold()
  eski_app1 <- tryCatch(logger::log_appender(index = 1), error = function(e) NULL)
  eski_lay1 <- tryCatch(logger::log_layout(index = 1), error = function(e) NULL)
  eski_shiny_error <- getOption("shiny.error")

  withr::defer({
    # İkinci appender'ı kaldır; birinciyi ve threshold'u geri yükle
    tryCatch(logger::delete_logger_index(index = 2), error = function(e) NULL)
    if (!is.null(eski_app1)) tryCatch(logger::log_appender(eski_app1, index = 1), error = function(e) NULL)
    if (!is.null(eski_lay1)) tryCatch(logger::log_layout(eski_lay1, index = 1), error = function(e) NULL)
    tryCatch(logger::log_threshold(eski_threshold), error = function(e) NULL)
    options(shiny.error = eski_shiny_error)
  }, envir = parent.frame())

  env <- new.env(parent = globalenv())
  withr::with_envvar(
    c(MERGEN_LOG_DIR = log_dir, MERGEN_LOG_THRESHOLD = "debug", env_extra),
    suppressMessages(
      source(file.path(resolve_repo_root_for_tests(), "R", "config_logging.R"),
             encoding = "UTF-8", local = env)
    )
  )

  # Konsol appender'ını (index 2) test koşumunda susturarak gürültüyü önle;
  # dosya appender'ı (index 1) doğrulama hedefi olarak kalır.
  logger::log_appender(function(lines) invisible(NULL), index = 2)

  env
}

# Bugünün log dosyasını okur (config_logging.R aynı adlandırmayı kullanır)
.readTodaysLog <- function(log_dir) {
  yol <- file.path(log_dir, sprintf("mergen_%s.log", format(Sys.Date(), "%Y%m%d")))
  if (!file.exists(yol)) return(character(0))
  readLines(yol, warn = FALSE, encoding = "UTF-8")
}

testthat::test_that("log_ai_call AI çağrı alanlarını dosya appender'ına interpolasyonla yazar", {
  log_dir <- withr::local_tempdir()
  env <- .loggingSinksEnv(log_dir)

  env$log_ai_call(user_id = 42L, model = "test-model", duration = 1.5,
                  success = TRUE, tokens = 128L)

  satirlar <- .readTodaysLog(log_dir)
  hedef <- satirlar[grepl("AI Call:", satirlar, fixed = TRUE)]
  testthat::expect_length(hedef, 1L)
  # Glue interpolasyonu log_ai_call'un KENDİ frame'inde çözülmüş olmalı
  testthat::expect_true(grepl("user=42", hedef, fixed = TRUE))
  testthat::expect_true(grepl("model=test-model", hedef, fixed = TRUE))
  testthat::expect_true(grepl("duration=1.5s", hedef, fixed = TRUE))
  testthat::expect_true(grepl("success=TRUE", hedef, fixed = TRUE))
  testthat::expect_true(grepl("tokens=128", hedef, fixed = TRUE))
})

testthat::test_that("log_user_action kullanıcı aksiyonunu Türkçe ayrıntıyla dosyaya yazar", {
  log_dir <- withr::local_tempdir()
  env <- .loggingSinksEnv(log_dir)

  env$log_user_action(7L, "dosya_yukleme", "Türkçe_çalışma_özeti.pdf")

  satirlar <- .readTodaysLog(log_dir)
  hedef <- satirlar[grepl("User action:", satirlar, fixed = TRUE)]
  testthat::expect_length(hedef, 1L)
  testthat::expect_true(grepl("user=7", hedef, fixed = TRUE))
  testthat::expect_true(grepl("action=dosya_yukleme", hedef, fixed = TRUE))
  # Türkçe karakterler dosya yolunda bozulmadan durur
  testthat::expect_true(grepl("Türkçe_çalışma_özeti.pdf", hedef, fixed = TRUE))
})

testthat::test_that("log_* sarmalayıcıları glue ifadesini çağıran frame'de çözer (9C sözleşmesi)", {
  log_dir <- withr::local_tempdir()
  env <- .loggingSinksEnv(log_dir)

  # Çağıran yerel değişkeni yalnızca bu local() frame'inde vardır; logger'ın
  # {nchar(yerel_token)} ifadesini burada çözmesi gerekir.
  local({
    yerel_token <- "abcde"
    env$log_info("TOKEN_UZUNLUK={nchar(yerel_token)}")
  })

  satirlar <- .readTodaysLog(log_dir)
  hedef <- satirlar[grepl("TOKEN_UZUNLUK=", satirlar, fixed = TRUE)]
  testthat::expect_length(hedef, 1L)
  testthat::expect_true(grepl("TOKEN_UZUNLUK=5", hedef, fixed = TRUE))
})

testthat::test_that(".forward_log_call karakter argümanları redakte edip iletır", {
  log_dir <- withr::local_tempdir()
  env <- .loggingSinksEnv(log_dir)

  # utils_log_redact.R aynı ortama yüklenir; .sanitize_log_value bunu bulur
  source(file.path(resolve_repo_root_for_tests(), "R", "utils_log_redact.R"),
         encoding = "UTF-8", local = env)

  # Sahte (gerçek olmayan) anahtar deseni: redaksiyon maskelemeli
  sahte_msg <- "istek hazirlandi api_key=FAKEKEY1234567890TEST durum=ok"
  env$log_info(sahte_msg)

  satirlar <- .readTodaysLog(log_dir)
  hedef <- satirlar[grepl("istek hazirlandi", satirlar, fixed = TRUE)]
  testthat::expect_length(hedef, 1L)
  # Ham sahte anahtar değeri log dosyasına olduğu gibi geçmemeli
  testthat::expect_false(grepl("FAKEKEY1234567890TEST", hedef, fixed = TRUE))
  # Mesajın zararsız kısmı korunur
  testthat::expect_true(grepl("durum=", hedef, fixed = TRUE))
})

testthat::test_that("log_error_with_context yapılandırılmış kayıtla insan-okur satır üretir", {
  log_dir <- withr::local_tempdir()
  env <- .loggingSinksEnv(log_dir)

  # Deterministik yapılandırılmış kayıt üreticisi (redakte edilmiş varsayılır)
  env$mergen_build_runtime_error_record <- function(error, context) {
    list(
      context = context,
      message = "temiz hata mesajı",
      error_class = "simple_error"
    )
  }

  hata <- simpleError("ham hata")
  env$log_error_with_context(hata, context = "TEST_BAGLAMI")

  satirlar <- .readTodaysLog(log_dir)
  # Not: log_error_with_context "Stack trace:" DEBUG satırına test kodunun
  # deparse edilmiş halini de yazar; bu yüzden yalnızca ERROR seviyesindeki
  # satır filtrelenir (kendine-referans yanlış eşleşmesini önler).
  insan_okur <- satirlar[grepl("^ERROR", satirlar) &
                           grepl("Error in TEST_BAGLAMI:", satirlar, fixed = TRUE)]
  testthat::expect_length(insan_okur, 1L)
  testthat::expect_true(grepl("temiz hata mesajı", insan_okur, fixed = TRUE))

  # DEBUG eşiğinde yapılandırılmış [RUNTIME_ERROR] satırı da yazılır
  yapilandirilmis <- satirlar[grepl("[RUNTIME_ERROR]", satirlar, fixed = TRUE)]
  testthat::expect_true(length(yapilandirilmis) >= 1L)
  testthat::expect_true(any(grepl("TEST_BAGLAMI", yapilandirilmis, fixed = TRUE)))
})

testthat::test_that("log_error_with_context kayıt üretici yoksa güvenli geri dönüş yolunu kullanır", {
  log_dir <- withr::local_tempdir()
  env <- .loggingSinksEnv(log_dir)

  # Kayıt üreticisi hata fırlatır -> tryCatch NULL -> fallback yolu
  env$mergen_build_runtime_error_record <- function(error, context) stop("üretici yok")

  env$log_error_with_context(simpleError("ham mesaj"), context = "FALLBACK_BAGLAMI")

  satirlar <- .readTodaysLog(log_dir)
  # Yalnızca ERROR seviyesindeki satır; Stack trace DEBUG satırı test kodunu
  # deparse ettiği için aynı kalıbı içerebilir.
  hedef <- satirlar[grepl("^ERROR", satirlar) &
                      grepl("Error in FALLBACK_BAGLAMI:", satirlar, fixed = TRUE)]
  testthat::expect_length(hedef, 1L)
  testthat::expect_true(grepl("ham mesaj", hedef, fixed = TRUE))
})
