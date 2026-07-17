# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-warmup-behavior.R
# Açıklama: VoxCPM2 ısındırma durum makinesi davranışları: süreç başına tek
#           ısındırma, eşzamanlı yinelenen başlatma engeli, durum geçişleri,
#           sınırlı yeniden deneme ve başarısızlıkta güvenli sonlanma. Gerçek
#           uç nokta çağrısı yoktur; başlatıcı fonksiyon enjekte edilir.
# ==============================================================================

testthat::test_that("ısındırma bayrağı ve deneme sınırı ortamdan çözülür", {
  speech_tests_source_chain()

  withr::local_envvar(VOXCPM2_WARMUP_ENABLED = "", VOXCPM2_WARMUP_MAX_RETRIES = "")
  testthat::expect_true(mergen_speech_warmup_enabled())
  testthat::expect_identical(mergen_speech_warmup_max_attempts(), 3L)

  withr::local_envvar(VOXCPM2_WARMUP_ENABLED = "false")
  testthat::expect_false(mergen_speech_warmup_enabled())

  withr::local_envvar(VOXCPM2_WARMUP_ENABLED = "TRUE", VOXCPM2_WARMUP_MAX_RETRIES = "0")
  testthat::expect_identical(mergen_speech_warmup_max_attempts(), 1L)
})

testthat::test_that("ısındırma süreçte bir kez koşar; eşzamanlı başlatma birleşir", {
  speech_tests_source_chain()
  mergen_speech_warmup_reset()
  on.exit(mergen_speech_warmup_reset(), add = TRUE)
  withr::local_envvar(VOXCPM2_WARMUP_ENABLED = "TRUE")

  starts <- 0L
  pending <- new.env(parent = emptyenv())

  starter <- function(on_success, on_failure) {
    starts <<- starts + 1L
    pending$resolve <- on_success
  }

  testthat::expect_true(mergen_speech_warmup_start_once(starter))
  testthat::expect_identical(mergen_speech_warmup_state()$status, "warming")

  # Isınırken ikinci/üçüncü oturum yeni ısındırma başlatamaz
  testthat::expect_false(mergen_speech_warmup_start_once(starter))
  testthat::expect_false(mergen_speech_warmup_start_once(starter))
  testthat::expect_identical(starts, 1L)

  pending$resolve()
  testthat::expect_identical(mergen_speech_warmup_state()$status, "ready")

  # Hazırken de yeniden başlatılmaz
  testthat::expect_false(mergen_speech_warmup_start_once(starter))
  testthat::expect_identical(starts, 1L)
})

testthat::test_that("başarısızlık sınırlı denemeyle sonlanır ve durumu raporlar", {
  speech_tests_source_chain()
  mergen_speech_warmup_reset()
  on.exit(mergen_speech_warmup_reset(), add = TRUE)
  withr::local_envvar(VOXCPM2_WARMUP_ENABLED = "TRUE",
                      VOXCPM2_WARMUP_MAX_RETRIES = "1")  # toplam 2 deneme

  starter_fail <- function(on_success, on_failure) on_failure("uç nokta kapalı")

  testthat::expect_true(mergen_speech_warmup_start_once(starter_fail))
  st <- mergen_speech_warmup_state()
  testthat::expect_identical(st$status, "failed")
  testthat::expect_identical(st$attempts, 1L)
  testthat::expect_match(st$last_error, "kapalı")

  # İkinci (son) deneme
  testthat::expect_true(mergen_speech_warmup_start_once(starter_fail))
  testthat::expect_identical(mergen_speech_warmup_state()$attempts, 2L)

  # Denemeler tükendi: bir daha başlatılmaz
  testthat::expect_false(mergen_speech_warmup_start_once(starter_fail))
  testthat::expect_identical(mergen_speech_warmup_state()$attempts, 2L)
})

testthat::test_that("kapalı ısındırma hiç başlamaz ve uygulamayı etkilemez", {
  speech_tests_source_chain()
  mergen_speech_warmup_reset()
  on.exit(mergen_speech_warmup_reset(), add = TRUE)
  withr::local_envvar(VOXCPM2_WARMUP_ENABLED = "false")

  testthat::expect_false(mergen_speech_warmup_should_start())
  testthat::expect_false(mergen_speech_warmup_start_once(function(s, f) s()))
  testthat::expect_identical(mergen_speech_warmup_state()$status, "uninitialized")
})

testthat::test_that("başlatıcı istisnası ısındırmayı güvenle başarısız işaretler", {
  speech_tests_source_chain()
  mergen_speech_warmup_reset()
  on.exit(mergen_speech_warmup_reset(), add = TRUE)
  withr::local_envvar(VOXCPM2_WARMUP_ENABLED = "TRUE")

  # İstisna yukarı fırlamaz; durum failed olur (uygulama akışı kırılmaz)
  testthat::expect_no_error(
    mergen_speech_warmup_start_once(function(s, f) stop("beklenmedik"))
  )
  st <- mergen_speech_warmup_state()
  testthat::expect_identical(st$status, "failed")
  testthat::expect_match(st$last_error, "beklenmedik")
})
