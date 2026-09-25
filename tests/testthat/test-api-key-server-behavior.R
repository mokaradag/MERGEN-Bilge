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
  env$.hatirlatmalar <- 0L

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
  env$.hatirlanan_kullanicilar <- character(0)
  env$.hatirlatma_sonucu <- TRUE
  env$.hatirlatma_girdisi <- NULL
  env$remember_api_key_choice_default <- function(session, username = NULL, result_input = NULL) {
    env$.hatirlatmalar <- env$.hatirlatmalar + 1L
    env$.hatirlanan_kullanicilar <- c(env$.hatirlanan_kullanicilar, username %||% NA_character_)
    env$.hatirlatma_girdisi <- result_input
    invisible(env$.hatirlatma_sonucu)
  }
  env$.etiket_istekleri <- character(0)
  env$api_key_pref_user_tag <- function(username) {
    env$.etiket_istekleri <- c(env$.etiket_istekleri, username %||% NA_character_)
    paste0("etiket-", username)
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
    testthat::expect_identical(env$.hatirlatmalar, 0L)

    # 2) Varsayılan anahtar VAR ama kimlik düşmüş: karar verilmez, modal açık kalır.
    env$.durum$default_key <- "sahte-kurum-anahtari"
    session$setInputs(api_key_use_default_btn = 3)
    testthat::expect_false(isTRUE(session$userData$api_key_onboarding_done))
    testthat::expect_identical(removeModal_sayisi, 0L)
    testthat::expect_identical(env$.hatirlatmalar, 0L)
    testthat::expect_true(any(vapply(.toastlarTip(env, "warning"), function(t)
      grepl("Kimlik doğrulaması geçerli değil", t$message, fixed = TRUE), logical(1))))

    # 3) "Bu ekranı bir daha gösterme" işaretsiz: yalnız bu oturum için devam edilir.
    env$.durum$owner <- list(username = "yonetici")
    session$setInputs(api_key_use_default_btn = 4)
    testthat::expect_true(isTRUE(session$userData$api_key_onboarding_done))
    testthat::expect_identical(session$userData$api_key_onboarding_owner, "yonetici")
    testthat::expect_identical(removeModal_sayisi, 1L)
    testthat::expect_identical(env$.hatirlatmalar, 0L)

    # 4) Kutu işaretli: kurum anahtarı seçimi sonraki girişler için hatırlanır.
    session$setInputs(api_key_dontshow = TRUE)
    session$setInputs(api_key_use_default_btn = 5)
    testthat::expect_identical(removeModal_sayisi, 2L)
    testthat::expect_identical(env$.hatirlatmalar, 1L)
    testthat::expect_identical(env$.hatirlanan_kullanicilar, "yonetici")

    bilgiler <- .toastlarTip(env, "info")
    testthat::expect_true(any(vapply(bilgiler, function(t)
      grepl("Varsayılan kurum", t$message, fixed = TRUE), logical(1))))
    # "Hatırlanacak" onayı tarayıcı kaydı doğrulamadan verilmez.
    testthat::expect_false(any(vapply(env$.toastlar, function(t)
      grepl("hatırlanacak", t$message, fixed = TRUE), logical(1))))
    testthat::expect_identical(env$.hatirlatma_girdisi, "api_key_module-api_key_choice_remembered")

    session$setInputs(api_key_choice_remembered = list(ok = TRUE, t = 1))
    testthat::expect_true(any(vapply(.toastlarTip(env, "info"), function(t)
      grepl("hatırlanacak", t$message, fixed = TRUE), logical(1))))

    session$setInputs(api_key_choice_remembered = list(ok = FALSE, t = 2))
    testthat::expect_true(any(vapply(.toastlarTip(env, "warning"), function(t)
      grepl("kaydedilemedi", t$message, fixed = TRUE), logical(1))))

    # Tercih tarayıcıya gönderilemezse kullanıcı uyarılır.
    env$.hatirlatma_sonucu <- FALSE
    session$setInputs(api_key_use_default_btn = 6)
    testthat::expect_true(any(vapply(.toastlarTip(env, "warning"), function(t)
      grepl("hatırlanamadı", t$message, fixed = TRUE), logical(1))))
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

testthat::test_that("geç gelen 'bir daha gösterme' bayrağı tolerans içinde dikkate alınır", {
  env <- .apiKeyEnv()
  env$.durum$default_key <- "sahte-kurum-anahtari"
  env$.durum$owner <- list(username = "yonetici")
  env$.saat <- as.POSIXct("2026-01-01 09:00:00", tz = "UTC")
  env$Sys.time <- function() env$.saat

  # Gecikmeli açılış tarayıcı yanıtı beklemeden hemen çalıştırılır; her iki
  # yarı da bu sahteyi kullanır ve çağrı sayısı doğrulanır.
  gecikmeler <- 0L
  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) { gecikmeler <<- gecikmeler + 1L; force(expr) },
    .package = "shinyjs"
  )

  ilerlet <- function(session, saniye) {
    env$.saat <- env$.saat + saniye
    session$elapse(200)
  }

  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key", serviceDesk = list(),
                                api_config = list()), {
    ilerlet(session, 0)
    # Eski 2.5 sn sınırı geçildi; bayrak gelmediği için hâlâ beklenir.
    ilerlet(session, 3)
    testthat::expect_identical(env$.modal_acilislari, 0L)

    # Başka kullanıcının etiketini taşıyan yanıt devralınmaz.
    session$setInputs(api_key_onboarding_suppressed = list(suppressed = TRUE, tag = "etiket-baskasi"))
    ilerlet(session, 1)
    testthat::expect_false(isTRUE(session$userData$api_key_onboarding_done))

    # Bayrak geç geldi: bastırma geçerli, modal hiç açılmaz.
    session$setInputs(api_key_onboarding_suppressed = list(suppressed = TRUE, tag = "etiket-yonetici"))
    ilerlet(session, 1)
    ilerlet(session, 5)
    testthat::expect_identical(env$.modal_acilislari, 0L)
    testthat::expect_true(isTRUE(session$userData$api_key_onboarding_done))
  })
  testthat::expect_identical(gecikmeler, 0L)

  env2 <- .apiKeyEnv()
  env2$.durum$default_key <- "sahte-kurum-anahtari"
  env2$.durum$owner <- list(username = "kullanici")
  env2$.saat <- as.POSIXct("2026-01-01 09:00:00", tz = "UTC")
  env2$Sys.time <- function() env2$.saat
  shiny::testServer(env2$apiKeyServer,
                    args = list(id = "api_key", serviceDesk = list(),
                                api_config = list()), {
    env2$.saat <- env2$.saat + 0; session$elapse(200)
    env2$.saat <- env2$.saat + 7; session$elapse(200)
    # Bayrak hiç gelmezse tolerans sonunda modal yine gösterilir.
    testthat::expect_identical(gecikmeler, 1L)
    testthat::expect_identical(env2$.modal_acilislari, 1L)
  })
})

testthat::test_that("bastırma tercihi kimlik hazır olunca kullanıcı etiketiyle istenir", {
  env <- .apiKeyEnv()
  env$.durum$default_key <- "sahte-kurum-anahtari"
  env$.saat <- as.POSIXct("2026-01-01 09:00:00", tz = "UTC")
  env$Sys.time <- function() env$.saat

  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) force(expr),
    .package = "shinyjs"
  )

  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key", serviceDesk = list(),
                                api_config = list()), {
    # Kimlik yokken tercih istenmez: tarayıcıdaki bayrak kime ait bilinmez.
    session$elapse(200)
    env$.saat <- env$.saat + 2; session$elapse(200)
    testthat::expect_length(env$.etiket_istekleri, 0L)

    env$.durum$owner <- list(username = "ayilmaz")
    session$elapse(200)
    testthat::expect_identical(env$.etiket_istekleri, "ayilmaz")

    session$setInputs(api_key_onboarding_suppressed = list(suppressed = TRUE, tag = "etiket-ayilmaz"))
    session$elapse(200)
    testthat::expect_identical(env$.modal_acilislari, 0L)
    testthat::expect_true(isTRUE(session$userData$api_key_onboarding_done))
  })
})

testthat::test_that("kişisel anahtar yolu da tercih etiketini gönderir", {
  env <- .apiKeyEnv()
  env$.durum$owner <- list(username = "ayilmaz")
  env$load_user_api_key <- function(username) "sahte-kisisel-anahtar"
  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) force(expr),
    .package = "shinyjs"
  )
  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key", serviceDesk = list(), api_config = list()), {
    session$elapse(200)
    testthat::expect_identical(env$.etiket_istekleri, "ayilmaz")
    testthat::expect_length(env$.oturum_anahtarlari, 1L)
    testthat::expect_identical(env$.modal_acilislari, 0L)
  })
})

testthat::test_that("aynı oturum başka kullanıcıya geçince onboarding kararı yeniden işler", {
  env <- .apiKeyEnv()
  env$.durum$default_key <- "sahte-kurum-anahtari"
  env$.durum$owner <- list(username = "a_kisi")
  env$.saat <- as.POSIXct("2026-01-01 09:00:00", tz = "UTC")
  env$Sys.time <- function() env$.saat
  anahtarlar <- list(b_kisi = "sahte-b-anahtari")
  env$load_user_api_key <- function(username) anahtarlar[[username]] %||% ""
  testthat::local_mocked_bindings(
    runjs = function(...) invisible(NULL),
    delay = function(ms, expr) force(expr),
    .package = "shinyjs"
  )
  shiny::testServer(env$apiKeyServer,
                    args = list(id = "api_key", serviceDesk = list(), api_config = list()), {
    session$elapse(200)
    session$setInputs(api_key_onboarding_suppressed = list(suppressed = TRUE, tag = "etiket-a_kisi"))
    session$elapse(200)
    testthat::expect_identical(session$userData$api_key_onboarding_owner, "a_kisi")
    testthat::expect_length(env$.oturum_anahtarlari, 0L)

    # Karar sonrası kimlik seyrek izlenir; geçiş algılanana dek zaman ilerletilir.
    gecisi_bekle <- function(kullanici) {
      for (i in seq_len(15L)) {
        if (identical(tail(env$.etiket_istekleri, 1L), kullanici)) break
        session$elapse(200)
      }
    }

    # B'ye geçiş: A'nın bayrağı/kararı devralınmaz, B'nin kişisel anahtarı yüklenir.
    env$.durum$owner <- list(username = "b_kisi")
    gecisi_bekle("b_kisi")
    testthat::expect_length(env$.oturum_anahtarlari, 1L)
    testthat::expect_identical(env$.oturum_anahtarlari[[1]]$owner$username, "b_kisi")
    testthat::expect_identical(tail(env$.etiket_istekleri, 1L), "b_kisi")

    # C'ye geçiş: anahtarı yok; A'nın bastırma yanıtı C için geçerli sayılmaz.
    env$.durum$owner <- list(username = "c_kisi")
    gecisi_bekle("c_kisi")
    testthat::expect_identical(env$.modal_acilislari, 0L)
    env$.saat <- env$.saat + 7
    session$elapse(200)
    testthat::expect_identical(env$.modal_acilislari, 1L)
    testthat::expect_identical(session$userData$api_key_onboarding_owner, "c_kisi")
  })
})
