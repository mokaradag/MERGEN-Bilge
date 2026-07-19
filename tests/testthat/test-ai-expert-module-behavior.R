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
# module_ai_expert.R içindeki %...>%/%...!% operatörleri çıplak kullanılır;
# çağrı anında çözülebilmesi için promises paketi burada da eklenmelidir.
if (requireNamespace("promises", quietly = TRUE)) {
  suppressMessages(library(promises))
}

# Modül artık hibrit konuşma politikası yardımcılarına (idle-muted sayfa
# kümesi, öncelik/begin/end, token) dayanır; zinciri globalenv'e yükle.
speech_tests_source_chain()

.aiexp_env <- new.env(parent = globalenv())
# Modül, TTS parça hattı yardımcılarına (chunk pipeline) dayanır; izole
# testte manifest sırasını yansıtarak ÖNCE helper zinciri yüklenir.
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert_chunk_pipeline.R"),
  encoding = "UTF-8",
  local = .aiexp_env
)
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_ai_expert.R"),
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

test_that("manuel durdurma yankısı kuyruklanmış bitiş kancasını çalıştırmaz", {
  skip_if_not_installed("shiny")

  sd <- .aiexp_settings()
  kayit <- new.env(); kayit$msgs <- list(); kayit$bitti <- 0L

  testthat::local_mocked_bindings(delay = function(ms, expr) invisible(NULL), .package = "shinyjs")

  shiny::testServer(
    .aiexp_env$aiExpertServer,
    args = list(id = "ax", settings_data = sd,
                tts_processor = .tts_processor_off(),
                tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message
      session$returned$set_speech_ended_callback(function() kayit$bitti <- kayit$bitti + 1L)

      session$returned$start_speaking("Kuyruklu boşta konuşma", kind = "idle")
      token <- kayit$msgs$aiExpertStartSubtitle$speechToken

      session$setInputs(stop_ai_talk = 0L)
      session$setInputs(stop_ai_talk = 1L)
      session$setInputs(ai_expert_speech_ended = list(at = 1, speechToken = token))

      expect_false(isTRUE(session$returned$is_speaking()))
      expect_identical(kayit$bitti, 0L)
    }
  )
})

test_that(
  paste0("ai_expert_speech_ended: bayat (eski token'a ait) yankı YENİ ",
         "konuşmanın durumunu bozmaz (Codex P2)"),
  {
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

        # İlk konuşma: token T1 kurulur.
        session$returned$start_speaking("İlk konuşma", kind = "idle")
        expect_true(isTRUE(session$returned$is_speaking()))
        t1 <- kayit$msgs$aiExpertStartSubtitle$speechToken
        expect_true(is.numeric(t1))

        # Sayfa rehberliği kesmesi: start_speaking() önce eski konuşmayı
        # stop_speaking(0) ile durdurur, SONRA hemen yeni T2 token'ını kurar
        # (öncelik matrisi page_guidance'ın idle'ı kesmesine izin verir).
        kayit$msgs <- list()
        session$returned$start_speaking("İkinci konuşma", kind = "page_guidance")
        expect_true(isTRUE(session$returned$is_speaking()))
        t2 <- kayit$msgs$aiExpertStartSubtitle$speechToken
        expect_true(is.numeric(t2))
        expect_false(identical(t1, t2))

        # Bayat yankı: eski (kesilen) T1 konuşmasına ait "bitti" sinyali,
        # sunucuya YENİ konuşma (T2) çoktan başladıktan sonra ulaşmış gibi
        # simüle edilir. Bu YENİ konuşmayı KAPATMAMALIDIR.
        session$setInputs(ai_expert_speech_ended = list(at = 1, speechToken = t1))
        expect_true(isTRUE(session$returned$is_speaking()))

        # Güncel yankı: T2'ye ait sinyal konuşmayı gerçekten kapatmalıdır.
        session$setInputs(ai_expert_speech_ended = list(at = 2, speechToken = t2))
        expect_false(isTRUE(session$returned$is_speaking()))
      }
    )
  }
)

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

# İki parçaya bölünecek kadar uzun test metni: sentez sırasına göre kontrol
# edilebilen sahte promise'lerle (registry) kullanılır.
.aiexp_iki_parca_metni <- paste0(
  "Bu ilk cümle testin ilk parçasını oluşturacak kadar uzun ve tek başına ",
  "yeterli bir metindir gerçekten çok uzun bir cümledir. ",
  "Bu ikinci cümle ise ayrı bir TTS parçası olarak sentezlenmesi beklenen ",
  "ikinci kısmı temsil etmektedir simdi ve bu da yeterince uzundur."
)

# Elle çözülen, çağrı SIRASINA göre indekslenen sahte sentez işlemcisi.
.aiexp_tts_processor_kontrollu <- function() {
  kayit <- new.env(parent = emptyenv())
  kayit$resolvers <- list()
  kayit$istekler <- character(0)

  list(
    tts_available = function() TRUE,
    synthesize_speech = function(text, persona_id = NULL) {
      kayit$istekler <- c(kayit$istekler, text)
      idx <- length(kayit$istekler)
      promises::promise(function(resolve, reject) {
        kayit$resolvers[[idx]] <- resolve
      })
    },
    kayit = kayit,
    coz = function(i, basari = TRUE, src = paste0("wav-", i), sure = 1.2) {
      r <- kayit$resolvers[[i]]
      if (isTRUE(basari)) {
        r(list(success = TRUE, audio_src = src, duration = sure))
      } else {
        r(list(success = FALSE, audio_src = ""))
      }
      for (i in seq_len(50L)) later::run_now(timeoutSecs = 0)
    }
  )
}

test_that(
  paste0("on isitma basarisiz olup yeniden denenince kalan parca sentezi ",
         "ZATEN ustlenilmisse baslangic tamponu ERKEN acilmaz (Codex PR #636 ",
         "P2: Don't open the TTS buffer on an existing pipeline)"),
  {
    skip_if_not_installed("shiny")
    skip_if_not_installed("promises")
    skip_if_not_installed("later")

    sd <- .aiexp_settings()
    tp <- .aiexp_tts_processor_kontrollu()

    testthat::local_mocked_bindings(
      delay = function(ms, expr) invisible(NULL), .package = "shinyjs"
    )

    shiny::testServer(
      .aiexp_env$aiExpertServer,
      args = list(id = "ax", settings_data = sd,
                  tts_processor = tp,
                  tts_visualizer = list(trigger = function(...) NULL, stop = function() NULL)),
      {
        root <- .subset2(session, "parent")
        kayit_msg <- new.env(); kayit_msg$msgs <- list()
        root$sendCustomMessage <- function(type, message) {
          kayit_msg$msgs[[type]] <- message
        }

        # 1) Ön ısıtma başlatılır: 1. parça (chunks[[1]]) sentezi CALL #1.
        expect_true(isTRUE(session$returned$prewarm_speaking(.aiexp_iki_parca_metni)))
        expect_length(tp$kayit$istekler, 1L)

        # 2) start_speaking çağrılır: ön ısıtma hâlâ hazırlanıyor (inflight)
        #    dalına girer -> kalan parça (chunk 2) hattı BAŞLATILIR (CALL #2,
        #    ilk claim_synthesis() burada başarıyla üstlenir). CALL #2 bilerek
        #    HENÜZ ÇÖZÜLMEZ (gerçek pipeline hâlâ beklemede).
        session$returned$start_speaking(.aiexp_iki_parca_metni, kind = "idle")
        expect_length(tp$kayit$istekler, 2L)  # CALL #1 (prewarm) + CALL #2 (chunk2)

        # 3) Ön ısıtılan CALL #1 BAŞARISIZ sonuçlanır -> modül
        #    synthesize_first_chunk_now() ile yeniden dener: chunk 1 için YENİ
        #    bir sentez (CALL #3) başlatır ve queue_remaining_chunks() İKİNCİ
        #    kez çağrılır. claim_synthesis() zaten üstlenilmiş olduğundan bu
        #    ikinci çağrı hiçbir şey BAŞLATMAMALI ve başlangıç tamponu
        #    kapısını ERKEN AÇMAMALIDIR.
        tp$coz(1, basari = FALSE)
        expect_length(tp$kayit$istekler, 3L)  # + CALL #3 (chunk1 yeniden deneme)

        # 4) CALL #3 (chunk1 yeniden deneme) BAŞARILI sonuçlanır. CALL #2
        #    (chunk2, GERÇEK hat) HÂLÂ ÇÖZÜLMEDİ. Düzeltmeden ÖNCEKİ hatalı
        #    davranışta bu an, oynatmayı (aiExpertStartWithAudio) HENÜZ
        #    sonuçlanmamış tamponla erken başlatırdı. Düzeltmeyle: kapı KAPALI
        #    kalmalı, mesaj GÖNDERİLMEMELİDİR.
        tp$coz(3, basari = TRUE, src = "wav-chunk1-retry")
        expect_false("aiExpertStartWithAudio" %in% names(kayit_msg$msgs))

        # 5) Şimdi GERÇEK chunk2 hattı (CALL #2) sonuçlanır: tampon artık
        #    gerçekten hazır, kapı AÇILIR ve oynatma doğru şekilde başlar.
        tp$coz(2, basari = TRUE, src = "wav-chunk2")
        expect_true("aiExpertStartWithAudio" %in% names(kayit_msg$msgs))
        expect_identical(kayit_msg$msgs$aiExpertStartWithAudio$audioSrc, "wav-chunk1-retry")
      }
    )
  }
)

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