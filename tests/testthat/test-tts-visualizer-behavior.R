# ==============================================================================
# Dosya Yolu: tests/testthat/test-tts-visualizer-behavior.R
# Açıklama: R/module_tts_visualizer.R TTS görselleştirici modülünün DAVRANIŞSAL
#           testleri. Bu dosya davranışsal olarak daha önce test edilmiyordu.
#
#           ttsVisualizerUI(): avatar/isim/canvas yapısı.
#           ttsVisualizerServer(): trigger/stop kapanışları "updateTTSVisualizer"
#           custom message'ı gönderir; isim ve aksan rengi seçili personadan
#           türetilir (eski kimlikler normalize edilir). Mesajlar modül
#           session_proxy'si yerine kök MockShinySession üzerinden yakalanır.
#           Persona tek kaynağı helper_bootstrap.R ile yüklüdür. Ağ/DB/ses GEREKMEZ.
# ==============================================================================

.source_tts_visualizer_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_tts_visualizer.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# trigger/stop'u çalıştırır, kök session üzerinden updateTTSVisualizer mesajlarını yakalar.
.run_visualizer <- function(env, character_id, action) {
  rec <- new.env(); rec$msgs <- list()
  shiny::testServer(
    env$ttsVisualizerServer,
    args = list(settings_data = shiny::reactiveValues(
      selected_character = character_id,
      enable_tts_audio = FALSE,
      enable_ai_expert = FALSE,
      experience_mode = "odak"
    )),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) {
        rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
        invisible(TRUE)
      }
      rec$returned <- session$returned
      action(session$returned)
    }
  )
  rec
}

.last_visualizer_msg <- function(rec) {
  hit <- NULL
  for (m in rec$msgs) if (identical(m$type, "updateTTSVisualizer")) hit <- m$message
  hit
}

# ------------------------------------------------------------------------------
# UI yapısı
# ------------------------------------------------------------------------------
testthat::test_that("ttsVisualizerUI ad alanlı konteyner, avatar ve canvas üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_tts_visualizer_for_test()
  html <- paste(as.character(env$ttsVisualizerUI("tv")), collapse = "\n")
  testthat::expect_true(grepl("tv-container", html, fixed = TRUE))
  testthat::expect_true(grepl("tv-char_avatar", html, fixed = TRUE))
  testthat::expect_true(grepl("tts-canvas", html, fixed = TRUE))
  testthat::expect_true(grepl("Seslendirmeyi durdur", html, fixed = TRUE))
  # Boş src yerine şeffaf 1x1 GIF data URI kullanılmalı.
  testthat::expect_true(grepl("data:image/gif;base64", html, fixed = TRUE))
  testthat::expect_false(grepl("src=\"\"", html, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Dönen yapı + trigger/stop
# ------------------------------------------------------------------------------
testthat::test_that("ttsVisualizerServer trigger/stop kapanışlarını döndürür", {
  env <- .source_tts_visualizer_for_test()
  rec <- .run_visualizer(env, "emre", function(r) invisible(NULL))
  testthat::expect_true(is.list(rec$returned))
  testthat::expect_true(is.function(rec$returned$trigger))
  testthat::expect_true(is.function(rec$returned$stop))
})

testthat::test_that("trigger 'talking' durumu ve süreyi persona temasıyla gönderir", {
  env <- .source_tts_visualizer_for_test()
  rec <- .run_visualizer(env, "emre", function(r) r$trigger(duration = 7))
  msg <- .last_visualizer_msg(rec)
  testthat::expect_false(is.null(msg))
  testthat::expect_identical(msg$state, "talking")
  testthat::expect_identical(msg$duration, 7)
  # İsim ve aksan rengi persona kaydından gelmeli (boş olmamalı).
  testthat::expect_true(is.character(msg$name) && nzchar(msg$name))
  testthat::expect_true(grepl("^#", msg$color))
})

testthat::test_that("stop 'stop' durumunu gönderir", {
  env <- .source_tts_visualizer_for_test()
  rec <- .run_visualizer(env, "emre", function(r) r$stop())
  msg <- .last_visualizer_msg(rec)
  testthat::expect_identical(msg$state, "stop")
})

# ------------------------------------------------------------------------------
# Persona kimliği normalize edilir
# ------------------------------------------------------------------------------
testthat::test_that("görselleştirici eski persona kimliğini normalize ederek isim türetir", {
  env <- .source_tts_visualizer_for_test()
  # 'kayra' -> 'deniz' (göç sözleşmesi); deniz'in görünen adı gelmeli.
  beklenen <- get_character_record(normalize_character_id("kayra"))$display_name
  rec <- .run_visualizer(env, "kayra", function(r) r$trigger(duration = 3))
  msg <- .last_visualizer_msg(rec)
  testthat::expect_identical(msg$name, beklenen)
})
