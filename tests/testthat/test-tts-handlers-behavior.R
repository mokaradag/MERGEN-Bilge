# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-handlers-behavior.R
# Açıklama: R/server_tts_handlers.R ttsHandlersInit() tarafından döndürülen
#           tts_unavailable_reason() / tts_enabled() karar mantığının
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           ttsHandlersInit reaktif bağlam (reactiveVal/observeEvent/isolate)
#           kullandığından shiny::testServer içinde çalıştırılır. Döndürülen
#           kapanışlar test kapsamında çağrılarak ayar/uç-nokta durumuna göre
#           Türkçe gerekçe doğrulanır. Gerçek TTS uç noktası / ses GEREKMEZ.
# ==============================================================================

.source_tts_handlers_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_tts_handlers.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Verilen ayar/işlemci ile ttsHandlersInit'i çalıştırıp döndürülen listeyi verir.
.build_tts_handlers <- function(env, enable_tts_audio, tts_processor) {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  rec <- new.env()
  shiny::testServer(function(input, output, session) {
    values <- shiny::reactiveValues(messages = list(), current_chat_id = NULL)
    settings_data <- shiny::reactiveValues(
      enable_tts_audio = enable_tts_audio,
      selected_character = "emre"
    )
    tts_visualizer <- list(trigger = function(...) invisible(NULL))
    stop_generation <- shiny::reactiveVal(FALSE)

    rec$handlers <- env$ttsHandlersInit(
      session = session,
      values = values,
      settings_data = settings_data,
      tts_processor = tts_processor,
      tts_visualizer = tts_visualizer,
      stop_generation = stop_generation
    )
    rec$reason <- rec$handlers$tts_unavailable_reason()
    rec$enabled <- rec$handlers$tts_enabled()
  }, {
    session$flushReact()
  })
  rec
}

testthat::test_that("ttsHandlersInit beklenen kapanış listesini döndürür", {
  env <- .source_tts_handlers_for_test()
  rec <- .build_tts_handlers(env, FALSE, list(tts_available = function() TRUE))
  testthat::expect_true(is.list(rec$handlers))
  testthat::expect_true(all(c(
    "tts_warning_shown", "tts_unavailable_reason", "tts_enabled",
    "attach_tts_audio", "trigger_tts_for_message"
  ) %in% names(rec$handlers)))
})

testthat::test_that("TTS ayarı kapalıyken gerekçe 'ayar kapalı' olur ve etkin değildir", {
  env <- .source_tts_handlers_for_test()
  rec <- .build_tts_handlers(env, FALSE, list(tts_available = function() TRUE))
  testthat::expect_identical(rec$reason, "AI yanıtlarını seslendirme ayarı kapalı.")
  testthat::expect_false(rec$enabled)
})

testthat::test_that("TTS açık ama işlemci yüklenmemişse 'modül yüklenemedi' gerekçesi döner", {
  env <- .source_tts_handlers_for_test()
  # tts_processor NULL -> "Seslendirme modülü yüklenemedi."
  rec <- .build_tts_handlers(env, TRUE, NULL)
  testthat::expect_identical(rec$reason, "Seslendirme modülü yüklenemedi.")
  testthat::expect_false(rec$enabled)
})

testthat::test_that("TTS açık ama tts_available fonksiyonu yoksa 'modül yüklenemedi' döner", {
  env <- .source_tts_handlers_for_test()
  # Liste ama tts_available fonksiyonu yok.
  rec <- .build_tts_handlers(env, TRUE, list(baska = 1))
  testthat::expect_identical(rec$reason, "Seslendirme modülü yüklenemedi.")
})

testthat::test_that("TTS açık ama uç nokta hazır değilse 'uç noktası yapılandırılmadı' döner", {
  env <- .source_tts_handlers_for_test()
  rec <- .build_tts_handlers(env, TRUE, list(tts_available = function() FALSE))
  testthat::expect_identical(rec$reason, "Seslendirme uç noktası yapılandırılmadı.")
  testthat::expect_false(rec$enabled)
})

testthat::test_that("TTS açık ve uç nokta hazırsa gerekçe NULL ve etkin olur", {
  env <- .source_tts_handlers_for_test()
  rec <- .build_tts_handlers(env, TRUE, list(tts_available = function() TRUE))
  testthat::expect_null(rec$reason)
  testthat::expect_true(rec$enabled)
})

testthat::test_that("tts_available hata fırlatsa bile gerekçe güvenli şekilde üretilir", {
  env <- .source_tts_handlers_for_test()
  # try(..., silent=TRUE) ile hata yutulur, avail FALSE kalır.
  rec <- .build_tts_handlers(env, TRUE, list(tts_available = function() stop("uç nokta hatası")))
  testthat::expect_identical(rec$reason, "Seslendirme uç noktası yapılandırılmadı.")
})
