# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-key-server-behavior.R
# Açıklama: apiKeyServer modülü için testServer davranış testleri. Kaydetme
#           işleyicisinin doğrulama/sahiplik/kalıcılık akışı, temizleme
#           işleyicisi ve "varsayılan kurum anahtarı ile devam" akışı
#           doğrulanır. Hiçbir gerçek anahtar, dosya veya uç nokta kullanılmaz;
#           tüm anahtar yardımcıları yerel sahte (fake) stub'lardır.
# ==============================================================================

suppressMessages(library(shiny))

# apiKeyServer'ı kontrollü stub'larla izole ortama yükler
.apiKeyEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "module_api_key.R"), encoding = "UTF-8", local = env)

  # --- Kontrol edilebilir durum ---
  env$.durum <- new.env(parent = emptyenv())
  env$.durum$owner <- NULL            # mb_api_key_resolve_owner dönüşü
  env$.durum$default_key <- ""        # kurum anahtarı var mı?
  env$.durum$validate_result <- list(valid = TRUE, message = "Anahtar doğrulandı.")
  env$.durum$target <- list(allow_user_key = TRUE, endpoint = "http://test.local/v1",
                            model_id = "test-model", fallback_used = FALSE)

  # --- Kayıt tutucular ---
  env$.toastlar <- list()
  env$.kaydedilen <- list()
  env$.oturum_anahtarlari <- list()
  env$.modal_acilislari <- 0L

  # --- Anahtar yardımcısı stub'ları (asla gerçek anahtar/dosya kullanmaz) ---
  env$mb_api_key_clear_session_key <- function(session) invisible(NULL)
  env$mb_api_key_get_default_key <- function() env$.durum$default_key
  env$mb_api_key_resolve_owner <- function(session, require_auth = FALSE) env$.durum$owner
  env$determine_api_key_validation_target <- function(x, api_config) env$.durum$target
  env$validate_api_key <- function(key, model_id = NULL, endpoint = NULL,
                                   timeout_seconds = 6) env$.durum$validate_result
  env$save_user_api_key <- function(username, key_plain) {
    env$.kaydedilen[[length(env$.kaydedilen) + 1L]] <-
      list(username = username, key = key_plain)
    invisible(TRUE)
  }
  env$load_user_api_key <- function(username) ""
  env$mb_api_key_set_session_key <- function(session, key, owner = NULL) {
    env$.oturum_anahtarlari[[length(env$.oturum_anahtarlari) + 1L]] <-
      list(key = key, owner = owner)
    invisible(NULL)
  }
  env$show_api_key_choice_modal <- function(session, default_available = FALSE,
                                            service_desk = NULL) {
    env$.modal_acilislari <- env$.modal_acilislari + 1L
    invisible(NULL)
  }
  env$showToast <- function(session, message, type = "info", duration = NULL) {
    env$.toastlar[[length(env$.toastlar) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }

  env
}

# Belirli türdeki toast mesajlarını döndürür
.toastlarTip <- function(env, tip) {
  Filter(function(t) identical(t$type, tip), env$.toastlar)
}

testthat::test_that("api_key_save_btn boş anahtar ve kimliksiz durumda kaydetmeden uyarır", {
  env <- .apiKeyEnv()

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) invisible(NULL),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    removeModal = function(...) invisible(NULL),
    updateTextInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key_module", serviceDesk = list(),
                                api_config = list()), {
    # 1) Boşluklu anahtar: trimws sonrası boş -> "Anahtar boş olamaz."
    session$setInputs(api_key_plain_input = "   ")
    session$setInputs(api_key_save_btn = 1)
    session$setInputs(api_key_save_btn = 2)

    uyarilar <- .toastlarTip(env, "warning")
    testthat::expect_true(any(vapply(uyarilar, function(t)
      grepl("boş olamaz", t$message, fixed = TRUE), logical(1))))
    testthat::expect_length(env$.kaydedilen, 0L)

    # 2) Kimlik hazır değil (owner NULL): kimlik doğrulama uyarısı, kayıt yok
    session$setInputs(api_key_plain_input = "sahte-anahtar-degeri-123")
    session$setInputs(api_key_save_btn = 3)

    uyarilar <- .toastlarTip(env, "warning")
    testthat::expect_true(any(vapply(uyarilar, function(t)
      grepl("Kimlik doğrulama", t$message, fixed = TRUE), logical(1))))
    testthat::expect_length(env$.kaydedilen, 0L)
  })
})

testthat::test_that("api_key_save_btn geçersiz anahtarı kaydetmez, geçerli anahtarı kaydedip oturuma açar", {
  env <- .apiKeyEnv()
  env$.durum$owner <- list(username = "test.kullanici", user_id = 7L)

  removeModal_sayisi <- 0L
  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) invisible(NULL),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    removeModal = function(...) { removeModal_sayisi <<- removeModal_sayisi + 1L; invisible(NULL) },
    updateTextInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key_module", serviceDesk = list(),
                                api_config = list()), {
    # 1) Doğrulama geçersiz anahtar der: kayıt yapılmaz, hata toast'ı görünür
    env$.durum$validate_result <- list(valid = FALSE, message = "anahtar reddedildi")
    session$setInputs(api_key_plain_input = "sahte-gecersiz-anahtar")
    session$setInputs(api_key_save_btn = 1)
    session$setInputs(api_key_save_btn = 2)

    hatalar <- .toastlarTip(env, "error")
    testthat::expect_true(any(vapply(hatalar, function(t)
      grepl("geçersiz", t$message, fixed = TRUE), logical(1))))
    testthat::expect_length(env$.kaydedilen, 0L)
    testthat::expect_identical(removeModal_sayisi, 0L)

    # 2) Geçerli anahtar: kaydedilir, oturuma açılır, modal kapanır, başarı toast'ı
    env$.durum$validate_result <- list(valid = TRUE, message = "Anahtar doğrulandı.")
    session$setInputs(api_key_plain_input = "  sahte-gecerli-anahtar-456  ")
    session$setInputs(api_key_save_btn = 3)

    testthat::expect_length(env$.kaydedilen, 1L)
    testthat::expect_identical(env$.kaydedilen[[1L]]$username, "test.kullanici")
    # Anahtar trimlenmiş olarak kaydedilir
    testthat::expect_identical(env$.kaydedilen[[1L]]$key, "sahte-gecerli-anahtar-456")

    testthat::expect_length(env$.oturum_anahtarlari, 1L)
    testthat::expect_identical(env$.oturum_anahtarlari[[1L]]$owner$username, "test.kullanici")

    testthat::expect_identical(removeModal_sayisi, 1L)
    testthat::expect_true(isTRUE(session$userData$api_key_onboarding_done))

    basarilar <- .toastlarTip(env, "success")
    testthat::expect_true(any(vapply(basarilar, function(t)
      grepl("API anahtarı", t$message, fixed = TRUE), logical(1))))
  })
})

testthat::test_that("api_key_save_btn kullanıcı anahtarına izin verilmeyen ortamda erken durur", {
  env <- .apiKeyEnv()
  env$.durum$owner <- list(username = "test.kullanici")
  env$.durum$target <- list(allow_user_key = FALSE, endpoint = "")

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) invisible(NULL),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    removeModal = function(...) invisible(NULL),
    updateTextInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key_module", serviceDesk = list(),
                                api_config = list()), {
    session$setInputs(api_key_plain_input = "sahte-anahtar")
    session$setInputs(api_key_save_btn = 1)
    session$setInputs(api_key_save_btn = 2)

    hatalar <- .toastlarTip(env, "error")
    testthat::expect_true(any(vapply(hatalar, function(t)
      grepl("kullanıcı tarafından yönetilen", t$message, fixed = TRUE), logical(1))))
    testthat::expect_length(env$.kaydedilen, 0L)
  })
})

testthat::test_that("api_key_use_default_btn kurum anahtarı varsa devam eder, yoksa uyarır", {
  env <- .apiKeyEnv()

  removeModal_sayisi <- 0L
  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) invisible(NULL),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    removeModal = function(...) { removeModal_sayisi <<- removeModal_sayisi + 1L; invisible(NULL) },
    updateTextInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key_module", serviceDesk = list(),
                                api_config = list()), {
    # 1) Varsayılan anahtar YOK: uyarı, modal kapanmaz, onboarding işaretlenmez
    env$.durum$default_key <- ""
    session$setInputs(api_key_use_default_btn = 1)
    session$setInputs(api_key_use_default_btn = 2)

    uyarilar <- .toastlarTip(env, "warning")
    testthat::expect_true(any(vapply(uyarilar, function(t)
      grepl("kullanılamıyor", t$message, fixed = TRUE), logical(1))))
    testthat::expect_identical(removeModal_sayisi, 0L)
    testthat::expect_false(isTRUE(session$userData$api_key_onboarding_done))

    # 2) Varsayılan anahtar VAR: onboarding tamam, modal kapanır, bilgi toast'ı
    env$.durum$default_key <- "sahte-kurum-anahtari"
    session$setInputs(api_key_use_default_btn = 3)

    testthat::expect_true(isTRUE(session$userData$api_key_onboarding_done))
    testthat::expect_identical(removeModal_sayisi, 1L)

    bilgiler <- .toastlarTip(env, "info")
    testthat::expect_true(any(vapply(bilgiler, function(t)
      grepl("Varsayılan kurum", t$message, fixed = TRUE), logical(1))))
  })
})

testthat::test_that("apiKeyServer açık modül API'si döndürür ve open modalı tetikler", {
  env <- .apiKeyEnv()
  env$.durum$default_key <- "sahte-kurum-anahtari"

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) invisible(NULL),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(
    removeModal = function(...) invisible(NULL),
    updateTextInput = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key_module", serviceDesk = list(),
                                api_config = list()), {
    api <- session$getReturned()
    testthat::expect_true(is.list(api))
    testthat::expect_true(is.function(api$open))

    api$open("API Anahtarı")
    testthat::expect_identical(env$.modal_acilislari, 1L)
  })
})
