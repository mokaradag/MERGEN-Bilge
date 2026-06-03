# ==============================================================================
# Dosya Yolu: tests/testthat/test-startup-screen-module-behavior.R
# Açıklama: R/module_startup_screen.R derin uzay giriş ekranı modülünün
#           davranışsal testleri. UI yapısı/Türkçe metinler, apply_experience_mode
#           mod->ayar eşlemesi ve startup_skip_intro gözlemci kararı doğrulanır.
#           Gerçek Three.js/tarayıcı/müzik gerektirmez.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.startup_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_startup_screen.R"),
  encoding = "UTF-8",
  local = .startup_env
)

# UI ve gözlemci yardımcı bağımlılıklarını yalıtılmış ortamda stub'la.
.startup_env$get_current_version <- function() "1.0"
.startup_env$get_version_history <- function() {
  list(versions = list(), current_version = "1.0")
}

# -----------------------------------------------------------------------------
# createStartupScreenUI
# -----------------------------------------------------------------------------

test_that("createStartupScreenUI derin uzay yapısını ve Türkçe öğeleri üretir", {
  skip_if_not_installed("shiny")

  html <- paste(as.character(.startup_env$createStartupScreenUI()), collapse = "\n")

  expect_true(grepl("deep-space-container", html, fixed = TRUE))
  expect_true(grepl("explore-btn", html, fixed = TRUE))
  expect_true(grepl("KEŞFET", html, fixed = TRUE))
  # Sürüm rozeti stub sürümünü yansıtmalı.
  expect_true(grepl("v1.0 - Yeni!", html, fixed = TRUE))
  # Atlama onay kutusu metni.
  expect_true(grepl("Bir daha gösterme", html, fixed = TRUE))
  expect_true(grepl("Deneyim Seviyenizi Seçin", html, fixed = TRUE))
})

test_that("createStartupScreenUI üç deneyim modu kartını doğru data-mode ile içerir", {
  skip_if_not_installed("shiny")

  html <- paste(as.character(.startup_env$createStartupScreenUI()), collapse = "\n")

  expect_true(grepl("data-mode=\"odak\"", html, fixed = TRUE))
  expect_true(grepl("data-mode=\"denge\"", html, fixed = TRUE))
  expect_true(grepl("data-mode=\"kesif\"", html, fixed = TRUE))
  # Kart başlıkları (kullanıcıya görünen Türkçe etiketler).
  expect_true(grepl("Odak", html, fixed = TRUE))
  expect_true(grepl("Dinamik", html, fixed = TRUE))
  expect_true(grepl("Bütünleşik", html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# apply_experience_mode (saf karar tablosu)
# -----------------------------------------------------------------------------

# apply_experience_mode için sahte session + ayar ortamı kurar.
.kurulum <- function() {
  kayit <- new.env()
  kayit$msgs <- list()
  kayit$inputs <- list()

  sahte_session <- list(
    sendCustomMessage = function(type, message) kayit$msgs[[type]] <- message,
    sendInputMessage = function(inputId, message) kayit$inputs[[inputId]] <- message,
    userData = new.env()
  )

  settings_data <- new.env()
  settings_data$selected_character <- "emre"

  list(kayit = kayit, session = sahte_session, settings = settings_data)
}

test_that("apply_experience_mode 'kesif' modunda tüm özellikleri açar ve müziği senkronlar", {
  k <- .kurulum()
  testthat::local_mocked_bindings(runjs = function(code, ...) invisible(NULL), .package = "shinyjs")
  # updateCheckboxInput gerçek ShinySession ister; sahte session ile no-op'a çevir.
  testthat::local_mocked_bindings(updateCheckboxInput = function(...) invisible(NULL), .package = "shiny")

  .startup_env$apply_experience_mode(k$session, k$settings, "kesif", sync_music = TRUE)

  expect_equal(k$settings$experience_mode, "kesif")
  expect_true(isTRUE(k$settings$enable_tts_audio))
  expect_true(isTRUE(k$settings$enable_followups))
  expect_true(isTRUE(k$settings$enable_background_music))
  expect_true(isTRUE(k$settings$enable_ai_expert))
  # Müzik durumu açık olarak istemciye bildirilmeli.
  expect_true("toggleMusic" %in% names(k$kayit$msgs))
  expect_true(isTRUE(k$kayit$msgs$toggleMusic$enabled))
})

test_that("apply_experience_mode 'odak' modunda tüm özellikleri kapatır", {
  k <- .kurulum()
  testthat::local_mocked_bindings(runjs = function(code, ...) invisible(NULL), .package = "shinyjs")
  testthat::local_mocked_bindings(updateCheckboxInput = function(...) invisible(NULL), .package = "shiny")

  .startup_env$apply_experience_mode(k$session, k$settings, "odak", sync_music = TRUE)

  expect_equal(k$settings$experience_mode, "odak")
  expect_false(isTRUE(k$settings$enable_tts_audio))
  expect_false(isTRUE(k$settings$enable_followups))
  expect_false(isTRUE(k$settings$enable_background_music))
  expect_false(isTRUE(k$settings$enable_ai_expert))
  expect_false(isTRUE(k$kayit$msgs$toggleMusic$enabled))
})

test_that("apply_experience_mode 'denge' modunda takip soruları ve müzik açık, TTS/uzman kapalı", {
  k <- .kurulum()
  testthat::local_mocked_bindings(runjs = function(code, ...) invisible(NULL), .package = "shinyjs")
  testthat::local_mocked_bindings(updateCheckboxInput = function(...) invisible(NULL), .package = "shiny")

  .startup_env$apply_experience_mode(k$session, k$settings, "denge", sync_music = FALSE)

  expect_equal(k$settings$experience_mode, "denge")
  expect_false(isTRUE(k$settings$enable_tts_audio))
  expect_true(isTRUE(k$settings$enable_followups))
  expect_true(isTRUE(k$settings$enable_background_music))
  expect_false(isTRUE(k$settings$enable_ai_expert))
  # sync_music = FALSE -> toggleMusic mesajı gönderilmemeli.
  expect_false("toggleMusic" %in% names(k$kayit$msgs))
})

test_that("apply_experience_mode geçersiz mod için hiçbir ayarı değiştirmez", {
  k <- .kurulum()
  testthat::local_mocked_bindings(runjs = function(code, ...) invisible(NULL), .package = "shinyjs")
  testthat::local_mocked_bindings(updateCheckboxInput = function(...) invisible(NULL), .package = "shiny")

  .startup_env$apply_experience_mode(k$session, k$settings, "gecersiz_mod", sync_music = TRUE)

  expect_null(k$settings$experience_mode)
  expect_null(k$settings$enable_tts_audio)
  expect_false("toggleMusic" %in% names(k$kayit$msgs))
})

test_that("apply_experience_mode localStorage'a mod tercihini yazar", {
  k <- .kurulum()
  kod <- new.env(); kod$js <- character(0)
  testthat::local_mocked_bindings(
    runjs = function(code, ...) kod$js <- c(kod$js, code),
    .package = "shinyjs"
  )
  testthat::local_mocked_bindings(updateCheckboxInput = function(...) invisible(NULL), .package = "shiny")

  .startup_env$apply_experience_mode(k$session, k$settings, "kesif", sync_music = FALSE)

  expect_true(any(grepl("experience_mode = 'kesif'", kod$js, fixed = TRUE)))
})

# -----------------------------------------------------------------------------
# startupScreenObserversInit (startup_skip_intro kararı)
# -----------------------------------------------------------------------------

test_that("startup_skip_intro FALSE iken initDeepSpace mesajı gönderilir, atlama işaretlenmez", {
  skip_if_not_installed("shiny")

  kayit <- new.env(); kayit$msgs <- list()

  testthat::local_mocked_bindings(
    runjs = function(code, ...) invisible(NULL),
    delay = function(ms, expr) expr,
    .package = "shinyjs"
  )

  shiny::testServer(
    function(input, output, session) {
      session$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message
      sd <- shiny::reactiveValues(selected_character = "emre", enable_background_music = TRUE)
      .startup_env$startupScreenObserversInit(input, session, sd, boot_ready = NULL)
    },
    {
      # once = TRUE gözlemci: tek setInputs ile gerçek değeri okuyarak bir kez tetiklenir.
      session$setInputs(startup_skip_intro = FALSE)
      session$flushReact()

      expect_true("initDeepSpace" %in% names(kayit$msgs))
      expect_false(isTRUE(session$userData$deep_space_dismissed))
    }
  )
})

test_that("startup_skip_intro TRUE iken giriş ekranı atlanır ve initDeepSpace gönderilmez", {
  skip_if_not_installed("shiny")

  kayit <- new.env(); kayit$msgs <- list()

  testthat::local_mocked_bindings(
    runjs = function(code, ...) invisible(NULL),
    delay = function(ms, expr) expr,
    .package = "shinyjs"
  )

  shiny::testServer(
    function(input, output, session) {
      session$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message
      sd <- shiny::reactiveValues(selected_character = "emre", enable_background_music = TRUE)
      .startup_env$startupScreenObserversInit(input, session, sd, boot_ready = NULL)
    },
    {
      # once = TRUE gözlemci: tek setInputs ile gerçek değeri okuyarak bir kez tetiklenir.
      session$setInputs(startup_skip_intro = TRUE)
      session$flushReact()

      # Atlama işaretlenmeli ve derin uzay sahnesi başlatılmamalı.
      expect_true(isTRUE(session$userData$deep_space_dismissed))
      expect_false("initDeepSpace" %in% names(kayit$msgs))
      # Varsayılan persona rengi/güncellemesi yayınlanmalı.
      expect_true("updateNeuralColor" %in% names(kayit$msgs))
    }
  )
})
