# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-module-behavior.R
# Açıklama: R/module_ai_expert.R AI Uzman modülünün davranışsal testleri.
#           Altyazı UI yapısı, can_speak() kapı mantığı, start/stop_speaking
#           akışı (TTS yokken altyazı geri dönüşü) ve prewarm koruma yolları.
#           Gerçek TTS/LLM/tarayıcı gerektirmez; sahte işlemci + mock kullanılır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.aiexp_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_ai_expert.R"),
  encoding = "UTF-8",
  local = .aiexp_env
)
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert_chunking.R"),
  encoding = "UTF-8",
  local = .aiexp_env
)
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert_speech.R"),
  encoding = "UTF-8",
  local = .aiexp_env
)

# Varsayılan Bütünleşik mod ayarları (AI Uzman konuşabilir durum).
.aiexp_settings <- function() {
  shiny::reactiveValues(
    enable_ai_expert = TRUE,
    experience_mode = "kesif",
    selected_character = "emre",
    font_size = "medium",
    enable_tts_audio = FALSE
  )
}

# TTS kullanılamayan sahte işlemci (altyazı geri dönüş yolunu test eder).
.tts_processor_off <- function() {
  list(
    tts_available = function() FALSE,
    synthesize_speech = function(...) stop("TTS sentezi bu testte çağrılmamalı")
  )
}

# -----------------------------------------------------------------------------
# aiExpertSubtitleUI
# -----------------------------------------------------------------------------

test_that("aiExpertSubtitleUI altyazı şeridini ns id'leri ve güvenli avatar placeholder'ı ile üretir", {
  skip_if_not_installed("shiny")

  html <- paste(as.character(.aiexp_env$aiExpertSubtitleUI("ax")), collapse = "\n")

  expect_true(grepl("ax-subtitle_strip", html, fixed = TRUE))
  expect_true(grepl("ai-expert-subtitle-strip", html, fixed = TRUE))
  expect_true(grepl("ai-expert-hidden", html, fixed = TRUE))
  expect_true(grepl("ax-subtitle_text", html, fixed = TRUE))
  expect_true(grepl("ax-stop_ai_talk", html, fixed = TRUE))
  expect_true(grepl("AI konuşmasını durdur", html, fixed = TRUE))
  # Boş src yerine saydam 1x1 GIF placeholder kullanılmalı (konsol hijyeni).
  expect_true(grepl("data:image/gif;base64", html, fixed = TRUE))
  expect_false(grepl("src=\"\"", html, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# can_speak() kapı mantığı
# -----------------------------------------------------------------------------

test_that("can_speak: Bütünleşik modda ve uygun koşullarda TRUE döner", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      expect_true(isTRUE(session$returned$can_speak()))
    }
  )
})

test_that("can_speak: AI Uzman kapalıysa veya mod kesif değilse FALSE döner", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      sd$enable_ai_expert <- FALSE
      expect_false(isTRUE(session$returned$can_speak()))

      sd$enable_ai_expert <- TRUE
      sd$experience_mode <- "denge"
      expect_false(isTRUE(session$returned$can_speak()))
    }
  )
})

test_that("can_speak: yasaklı sayfada, kullanıcı aktifken veya TTS seslendirmesinde FALSE döner", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) invisible(NULL)

      # Yasaklı sayfa (health) -> konuşamaz.
      session$returned$set_page("health")
      expect_false(isTRUE(session$returned$can_speak()))

      # Tekrar serbest sayfaya dön -> konuşabilir.
      session$returned$set_page("chat")
      expect_true(isTRUE(session$returned$can_speak()))

      # Kullanıcı aktifken konuşamaz.
      session$returned$set_user_active(TRUE)
      expect_false(isTRUE(session$returned$can_speak()))
      session$returned$set_user_active(FALSE)

      # TTS yanıt seslendirmesi aktifken konuşamaz (yarış önleme).
      session$returned$set_tts_vocalizing(TRUE)
      expect_false(isTRUE(session$returned$can_speak()))
    }
  )
})

# -----------------------------------------------------------------------------
# start_speaking / stop_speaking
# -----------------------------------------------------------------------------

test_that("start_speaking (TTS yok): altyazı + sessiz geri dönüş mesajları gönderir ve konuşma durumunu açar", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  kayit <- new.env(); kayit$msgs <- list(); kayit$trigger <- 0L

  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(
                  trigger = function(duration = 0) kayit$trigger <- kayit$trigger + 1L,
                  stop = function() NULL
                )),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message

      session$returned$start_speaking("Merhaba, bu bir test konuşmasıdır.")

      expect_true(isTRUE(session$returned$is_speaking()))
      expect_true("aiExpertStartSubtitle" %in% names(kayit$msgs))
      expect_true("aiExpertNoAudioFallback" %in% names(kayit$msgs))
      # Altyazı metni mesaja taşınmalı.
      expect_true(grepl("Merhaba", kayit$msgs$aiExpertStartSubtitle$text, fixed = TRUE))
      # Görselleştirici sessizce de tetiklenmeli.
      expect_true(kayit$trigger >= 1L)
    }
  )
})

test_that("start_speaking: boş metinde hiçbir şey yapmaz; zaten konuşurken yeni mesaj göndermez", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  kayit <- new.env(); kayit$msgs <- list()

  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message

      # Boş metin -> konuşma açılmamalı.
      session$returned$start_speaking("")
      expect_false(isTRUE(session$returned$is_speaking()))
      expect_false("aiExpertStartSubtitle" %in% names(kayit$msgs))

      # İlk geçerli konuşma açılır.
      session$returned$start_speaking("İlk konuşma metni")
      expect_true(isTRUE(session$returned$is_speaking()))

      # Mesaj kaydını sıfırla ve ikinci kez çağır: zaten konuşurken yeni mesaj olmamalı.
      kayit$msgs <- list()
      session$returned$start_speaking("İkinci konuşma metni")
      expect_false("aiExpertStartSubtitle" %in% names(kayit$msgs))
    }
  )
})

test_that("stop_speaking: konuşma durumunu kapatır, durdurma mesajı gönderir ve görselleştiriciyi durdurur", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  kayit <- new.env(); kayit$msgs <- list(); kayit$stop <- 0L

  testthat::local_mocked_bindings(delay = function(ms, expr) invisible(NULL), .package = "shinyjs")

  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(
                  trigger = function(duration = 0) NULL,
                  stop = function() kayit$stop <- kayit$stop + 1L
                )),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message

      session$returned$start_speaking("Durdurulacak konuşma")
      expect_true(isTRUE(session$returned$is_speaking()))

      session$returned$stop_speaking(0)
      expect_false(isTRUE(session$returned$is_speaking()))
      expect_true("aiExpertStopSubtitle" %in% names(kayit$msgs))
      expect_true(kayit$stop >= 1L)
    }
  )
})

test_that("stop_speaking pozitif bekleme süresiyle çağrılınca can_speak bekleme nedeniyle FALSE olur", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()

  # shinyjs::delay gövdesini çalıştırma -> is_cooldown TRUE kalsın.
  testthat::local_mocked_bindings(delay = function(ms, expr) invisible(NULL), .package = "shinyjs")

  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) invisible(NULL)

      session$returned$stop_speaking(5)  # 5 sn bekleme başlat
      # Bekleme aktif olduğu için konuşamaz.
      expect_false(isTRUE(session$returned$can_speak()))
    }
  )
})



test_that("start_speaking (TTS açık): speech token ilk parça geri çağrısını aktif tutar", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  sd <- .aiexp_settings()
  sd$enable_tts_audio <- TRUE
  kayit <- new.env(); kayit$msgs <- list(); kayit$trigger <- 0L
  tts_on <- list(
    tts_available = function() TRUE,
    synthesize_speech = function(...) promises::promise_resolve(list(
      success = TRUE,
      audio_src = "data:audio/wav;base64,QUJD",
      duration = 1,
      media_duration = 1
    ))
  )

  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = tts_on,
                tts_visualizer = list(
                  trigger = function(duration = 0) kayit$trigger <- kayit$trigger + 1L,
                  stop = function() NULL
                )),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message

      session$returned$start_speaking("Sesli konuşma token testi.")
      for (i in seq_len(40)) {
        later::run_now(timeoutSecs = 0)
        if ("aiExpertStartWithAudio" %in% names(kayit$msgs)) break
        Sys.sleep(0.002)
      }

      expect_true("aiExpertStartWithAudio" %in% names(kayit$msgs))
      expect_true(isTRUE(session$returned$is_speaking()))
      expect_true(kayit$trigger >= 1L)
    }
  )
})


test_that("ai_expert_speech_ended: eski speechSeq yeni konuşmayı kapatmaz", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  kayit <- new.env(); kayit$msgs <- list()
  testthat::local_mocked_bindings(delay = function(ms, expr) invisible(NULL), .package = "shinyjs")

  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message

      session$returned$start_speaking("Sunucu token doğrulama testi.")
      expect_true(isTRUE(session$returned$is_speaking()))

      session$setInputs(ai_expert_speech_ended = list(speechSeq = 0L))
      expect_true(isTRUE(session$returned$is_speaking()))

      session$setInputs(ai_expert_speech_ended = list(speechSeq = 1L))
      expect_false(isTRUE(session$returned$is_speaking()))
    }
  )
})

# -----------------------------------------------------------------------------
# prewarm_speaking koruma yolları
# -----------------------------------------------------------------------------

test_that("prewarm_speaking: boş metinde ve TTS kullanılamazken FALSE döner", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      # Boş metin -> FALSE.
      expect_false(isTRUE(session$returned$prewarm_speaking("")))
      # TTS kullanılamaz -> FALSE (synthesize_speech çağrılmadan).
      expect_false(isTRUE(session$returned$prewarm_speaking("ön ısıtılacak metin")))
    }
  )
})

# -----------------------------------------------------------------------------
# Geri dönen sözleşme (bekleme süresi sabitleri)
# -----------------------------------------------------------------------------

test_that("aiExpertServer beklenen kontrol fonksiyonlarını ve bekleme sabitlerini döndürür", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      api <- session$returned
      expect_true(all(c("start_speaking", "prewarm_speaking", "stop_speaking",
                        "is_speaking", "can_speak", "set_page",
                        "set_user_active", "set_tts_vocalizing") %in% names(api)))
      # Bekleme süresi sabitleri dışarıya açılmalı.
      expect_equal(api$COOLDOWN_STOP, 5)
      expect_equal(api$COOLDOWN_PAGE, 8)
      expect_equal(api$COOLDOWN_GREETING, 10)
      expect_equal(api$COOLDOWN_IDLE, 12)
    }
  )
})
