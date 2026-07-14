# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-profile-preload-behavior.R
# Açıklama: VoxCPM2 profil ön yükleme politikası davranış testleri. Hızlı
#           Başlangıç'ta bloklayıcı TTS işi olmadığını, Odak/Dinamik modda profil
#           yüklenmediğini, konuşma özelliği açıkken/karakter değişince yüklendiğini
#           doğrular. Gerçek TTS/ağ GEREKMEZ.
# ==============================================================================

if (!exists("tts_fixture_source_helpers", mode = "function")) {
  source(file.path(resolve_repo_root_for_tests(), "tests", "testthat", "helper_tts_voice_fixtures.R"),
         encoding = "UTF-8", local = FALSE)
}
tts_fixture_source_helpers()
source(file.path(resolve_repo_root_for_tests(), "R", "helpers_startup_lane.R"),
       encoding = "UTF-8", local = globalenv())

test_that("ön yükleme kararı yalnızca bir konuşma özelliği açıkken doğrudur", {
  expect_false(mergen_tts_profile_preload_decision(FALSE, FALSE))  # Odak/Dinamik
  expect_true(mergen_tts_profile_preload_decision(TRUE, FALSE))    # TTS açık
  expect_true(mergen_tts_profile_preload_decision(FALSE, TRUE))    # AI Uzman açık
  expect_true(mergen_tts_profile_preload_decision(TRUE, TRUE))     # Bütünleşik
})

test_that("Hızlı Başlangıç zorunlu boot anahtarları TTS içermez", {
  fast_keys <- mergen_fast_lane_required_boot_keys()
  rich_keys <- mergen_rich_lane_required_boot_keys()
  expect_false(any(grepl("tts|voice|profil|profile|ses", fast_keys, ignore.case = TRUE)))
  expect_false(any(grepl("tts|voice|profil|profile", rich_keys, ignore.case = TRUE)))
})

test_that("Odak/Dinamik (ikisi de kapalı) hiçbir profil yüklemez", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  rec <- new.env(parent = emptyenv()); rec$calls <- character(0)
  shiny::testServer(function(input, output, session) {
    settings_data <- shiny::reactiveValues(enable_tts_audio = FALSE, enable_ai_expert = FALSE,
                                           selected_character = "emre")
    tts_processor <- list(preload_profile = function(cid) rec$calls <- c(rec$calls, as.character(cid)))
    mergen_tts_bind_profile_preload(session, settings_data, tts_processor)
  }, {
    session$flushReact()
    expect_identical(rec$calls, character(0))
  })
})

test_that("Bütünleşik/başlangıçta TTS açık ise seçili profil yüklenir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  rec <- new.env(parent = emptyenv()); rec$calls <- character(0)
  shiny::testServer(function(input, output, session) {
    settings_data <- shiny::reactiveValues(enable_tts_audio = TRUE, enable_ai_expert = TRUE,
                                           selected_character = "selin")
    tts_processor <- list(preload_profile = function(cid) rec$calls <- c(rec$calls, as.character(cid)))
    mergen_tts_bind_profile_preload(session, settings_data, tts_processor)
  }, {
    session$flushReact()
    expect_true("selin" %in% rec$calls)
  })
})

test_that("kullanıcı TTS'i sonradan açınca profil yüklenir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  rec <- new.env(parent = emptyenv()); rec$calls <- character(0)
  shiny::testServer(function(input, output, session) {
    settings_data <- shiny::reactiveValues(enable_tts_audio = FALSE, enable_ai_expert = FALSE,
                                           selected_character = "deniz")
    tts_processor <- list(preload_profile = function(cid) rec$calls <- c(rec$calls, as.character(cid)))
    mergen_tts_bind_profile_preload(session, settings_data, tts_processor)
  }, {
    session$flushReact()
    expect_identical(rec$calls, character(0))
    settings_data$enable_tts_audio <- TRUE
    session$flushReact()
    expect_true("deniz" %in% rec$calls)
  })
})

test_that("konuşma özelliği açıkken karakter değişince yeni profil yüklenir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  rec <- new.env(parent = emptyenv()); rec$calls <- character(0)
  shiny::testServer(function(input, output, session) {
    settings_data <- shiny::reactiveValues(enable_tts_audio = TRUE, enable_ai_expert = FALSE,
                                           selected_character = "emre")
    tts_processor <- list(preload_profile = function(cid) rec$calls <- c(rec$calls, as.character(cid)))
    mergen_tts_bind_profile_preload(session, settings_data, tts_processor)
  }, {
    session$flushReact()
    settings_data$selected_character <- "ipek"
    session$flushReact()
    expect_true("ipek" %in% rec$calls)
  })
})

test_that("preload_profile fonksiyonu olmayan işlemci güvenli no-op olur", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  shiny::testServer(function(input, output, session) {
    settings_data <- shiny::reactiveValues(enable_tts_audio = TRUE, enable_ai_expert = FALSE,
                                           selected_character = "emre")
    result <- mergen_tts_bind_profile_preload(session, settings_data, list())
    expect_false(isTRUE(result))
  }, {})
})
