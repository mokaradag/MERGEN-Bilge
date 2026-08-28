# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-simulate-streaming-behavior.R
# Açıklama: chat_simulate_streaming (R/helpers_chat_runtime.R) içindeki KARAR ve
#           ERKEN-ÇIKIŞ dallarını deterministik biçimde test eder:
#             * TTS yok  -> hemen başlatma yolu,
#             * TTS var (promise başarılı/başarısız) -> akış yine başlatılır,
#             * boş yanıt -> TTS beklenmez,
#             * stop_generation TRUE -> akış gözlemcisi (invalidateLater döngüsü)
#               OLUŞTURULMADAN temizlenir (typing kapatılır, reset çağrılır,
#               initStreamingMessage GÖNDERİLMEZ, mesaj eklenmez).
#           Testlerin ÇOĞU stop_generation=TRUE kullanır; böylece kırılgan
#           shiny::observe/invalidateLater döngüsüne girilmez ve test
#           tamamen senkron/deterministik kalır. TEK İSTİSNA bayat-sohbet
#           testidir: orada stop_generation=function() FALSE geçilir ve erken
#           çıkış BİLEREK kimlik kapısına (bayat sohbet tespiti) bırakılır;
#           kapı kaldırılırsa test döngüye girer ve BAŞARISIZ olur — istenen
#           budur. Gerçek DB/LLM/ağ/tarayıcı GEREKMEZ.
# ==============================================================================

# helpers_chat_runtime.R'yi izole ortama yükler; çağrıların yan etkilerini
# kaydeden stub'ları yerleştirir. start_streaming_execution erken-çıkış
# dalında yalnızca format_timestamp / normalize_character_id /
# get_character_record / isolate / removeUI / chat_reset_state çağrılır.
.css_env <- function() {
  env <- new.env(parent = globalenv())
  env$.rec <- new.env(parent = emptyenv())
  env$.rec$removeUI <- list()
  env$.rec$reset <- 0L
  env$.rec$insertUI <- 0L

  # Dosyada TANIMLANMAYAN yardımcılar source ÖNCESİ stub'lanır.
  env$format_timestamp <- function() "2026-01-01 00:00:00"
  env$normalize_character_id <- function(x) "emre"
  env$get_character_record <- function(id) list(id = id, display_name = "Emre")
  env$isolate <- function(x) x
  env$removeUI <- function(selector, ...) {
    env$.rec$removeUI[[length(env$.rec$removeUI) + 1L]] <- selector
    invisible(NULL)
  }
  # Erken-çıkışta ULAŞILMAMASI gereken yardımcılar; çağrılırsa testte yakalanır.
  env$insertUI <- function(...) {
    env$.rec$insertUI <- env$.rec$insertUI + 1L
    invisible(NULL)
  }
  env$render_message_bubble_ui <- function(...) "<div>stub</div>"
  env$process_message_content <- function(content, type) list(html = "<p>x</p>", has_code = FALSE)
  env$build_chartlab_message <- function(...) list(found = FALSE)
  env$save_message_to_db <- function(...) 1L
  env$wire_chart_output <- function(...) invisible(NULL)

  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_chat_runtime.R"),
         encoding = "UTF-8", local = env)

  # Dosyada TANIMLANAN yardımcılar source SONRASI stub'lanmalı; aksi halde
  # gerçek chat_reset_state (freezeReactiveValue/shinyjs) erken-çıkış yolunu kırar.
  env$chat_reset_state <- function(session, values) {
    env$.rec$reset <- env$.rec$reset + 1L
    invisible(NULL)
  }
  env$push_followup_update <- function(...) invisible(NULL)
  env$chat_store_message_in_saved_chats <- function(...) invisible(NULL)
  env
}

# Sahte oturum: sendCustomMessage çağrılarını kaydeder.
.css_session <- function(rec) {
  list(sendCustomMessage = function(type, msg) {
    rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, msg = msg)
    invisible(NULL)
  })
}

# later kuyruğunu sınırlı biçimde boşaltır (promise callback'lerini çalıştırır).
.css_drain <- function() {
  for (i in seq_len(200)) {
    if (later::loop_empty()) break
    later::run_now(timeout = 0)
  }
}

testthat::test_that("TTS yok + stop_generation=TRUE: gözlemci oluşturulmadan temizlenir", {
  env <- .css_env()
  rec <- new.env(parent = emptyenv()); rec$msgs <- list()
  vals <- new.env(parent = emptyenv())
  vals$messages <- list()
  vals$typing <- TRUE

  invisible(utils::capture.output(
    env$chat_simulate_streaming(
      full_response = "merhaba dünya",
      session = .css_session(rec),
      values = vals,
      settings_data = list(selected_character = "emre"),
      output = list(),
      stop_generation = function() TRUE,
      tts_engine = NULL
    )
  ))

  # Erken çıkış: typing kapatıldı, reset çağrıldı, typing-wrapper kaldırıldı.
  testthat::expect_false(vals$typing)
  testthat::expect_identical(env$.rec$reset, 1L)
  testthat::expect_true("#typing-animation-wrapper" %in% unlist(env$.rec$removeUI))
  # Akış başlamadı: initStreamingMessage gönderilmedi, mesaj eklenmedi, insertUI yok.
  testthat::expect_length(rec$msgs, 0L)
  testthat::expect_length(vals$messages, 0L)
  testthat::expect_identical(env$.rec$insertUI, 0L)
})

testthat::test_that("boş yanıt TTS engine olsa bile hemen başlatma yoluna girer", {
  env <- .css_env()
  rec <- new.env(parent = emptyenv()); rec$msgs <- list()
  vals <- new.env(parent = emptyenv()); vals$messages <- list(); vals$typing <- TRUE
  tts_called <- new.env(parent = emptyenv()); tts_called$n <- 0L

  invisible(utils::capture.output(
    env$chat_simulate_streaming(
      full_response = "",  # nzchar FALSE -> TTS beklenmez
      session = .css_session(rec),
      values = vals,
      settings_data = list(selected_character = "emre"),
      output = list(),
      stop_generation = function() TRUE,
      tts_engine = function(text, voice) { tts_called$n <- tts_called$n + 1L; NULL }
    )
  ))

  # Boş yanıt: TTS engine ÇAĞRILMAZ, doğrudan erken çıkışa düşülür.
  testthat::expect_identical(tts_called$n, 0L)
  testthat::expect_identical(env$.rec$reset, 1L)
  testthat::expect_length(rec$msgs, 0L)
})

testthat::test_that("TTS başarılı promise: seslendirme beklenir, sonra akış başlatma yoluna girilir", {
  env <- .css_env()
  rec <- new.env(parent = emptyenv()); rec$msgs <- list()
  vals <- new.env(parent = emptyenv()); vals$messages <- list(); vals$typing <- TRUE
  tts_called <- new.env(parent = emptyenv()); tts_called$n <- 0L

  out <- utils::capture.output({
    env$chat_simulate_streaming(
      full_response = "akan metin",
      session = .css_session(rec),
      values = vals,
      settings_data = list(selected_character = "emre"),
      output = list(),
      stop_generation = function() TRUE,  # gözlemci oluşturulmadan dur
      tts_engine = function(text, voice) {
        tts_called$n <- tts_called$n + 1L
        promises::promise_resolve(list(success = TRUE, audio_src = "data:audio", voice = "v1", duration = 1.5))
      },
      tts_voice = "v1"
    )
    .css_drain()  # promise callback'i (ve cat çıktısını) capture içinde çalıştır
  })

  # TTS engine bir kez çağrıldı; başarı satırı loglandı; akış başlatma yoluna ulaşıldı.
  testthat::expect_identical(tts_called$n, 1L)
  blob <- paste(out, collapse = "\n")
  testthat::expect_true(grepl("Seslendirme başlatılıyor", blob, fixed = TRUE))
  testthat::expect_true(grepl("Seslendirme başarılı", blob, fixed = TRUE))
  # start_streaming_execution çalıştı ama stop=TRUE olduğundan erken çıktı.
  testthat::expect_identical(env$.rec$reset, 1L)
  testthat::expect_length(rec$msgs, 0L)
})

testthat::test_that("TTS reddedilen promise: akış yine de başlatma yoluna girer (TTS başarısız fallback)", {
  env <- .css_env()
  rec <- new.env(parent = emptyenv()); rec$msgs <- list()
  vals <- new.env(parent = emptyenv()); vals$messages <- list(); vals$typing <- TRUE

  out <- utils::capture.output({
    env$chat_simulate_streaming(
      full_response = "akan metin",
      session = .css_session(rec),
      values = vals,
      settings_data = list(selected_character = "emre"),
      output = list(),
      stop_generation = function() TRUE,
      tts_engine = function(text, voice) promises::promise_reject(simpleError("ses motoru hatası")),
      tts_voice = "v1"
    )
    .css_drain()
  })

  blob <- paste(out, collapse = "\n")
  # Promise hatası loglandı ve akış yine de başlatma yoluna ulaştı (reset çağrıldı).
  testthat::expect_true(grepl("Promise hatası", blob, fixed = TRUE))
  testthat::expect_identical(env$.rec$reset, 1L)
  testthat::expect_length(rec$msgs, 0L)
})

testthat::test_that("TTS başarısız (success=FALSE) promise: başarısız log + akış başlatma yolu", {
  env <- .css_env()
  rec <- new.env(parent = emptyenv()); rec$msgs <- list()
  vals <- new.env(parent = emptyenv()); vals$messages <- list(); vals$typing <- TRUE

  out <- utils::capture.output({
    env$chat_simulate_streaming(
      full_response = "akan metin",
      session = .css_session(rec),
      values = vals,
      settings_data = list(selected_character = "emre"),
      output = list(),
      stop_generation = function() TRUE,
      tts_engine = function(text, voice) promises::promise_resolve(list(success = FALSE, error = "kota")),
      tts_voice = "v1"
    )
    .css_drain()
  })

  blob <- paste(out, collapse = "\n")
  testthat::expect_true(grepl("Seslendirme başarısız", blob, fixed = TRUE))
  testthat::expect_identical(env$.rec$reset, 1L)
})

# ---------------------------------------------------------------------------
# BAYAT TTS GERİ ÇAĞRISI: Yeni Söyleşi sırasında çözülen promise
# ---------------------------------------------------------------------------

testthat::test_that("sohbet DEGISTIYSE gec cozulen TTS akisi baslatmaz", {
  # GERİLEME: TTS promise'i beklerken kullanıcı Yeni Söyleşi başlatırsa,
  # `onFulfilled` ESKİ yanıt için `start_streaming_execution()` çağırıyor ve
  # boşaltılmış `values$messages` listesine eski yanıtı ekliyordu.
  env <- .css_env()
  rec <- new.env(parent = emptyenv()); rec$msgs <- list()
  vals <- new.env(parent = emptyenv())
  vals$messages <- list()
  vals$typing <- TRUE
  vals$current_chat_id <- "sohbet-A"

  # Üretim yardımcısıyla AYNI sözleşme: kaydedilmiş sohbet kimliği damgalanır.
  env$mergen_pk_chat_identity <- function(session, values) {
    paste0("chat:", as.character(values$current_chat_id)[1])
  }

  cozucu <- NULL
  env_tts <- function(text, voice) {
    promises::promise(function(resolve, reject) cozucu <<- resolve)
  }

  invisible(utils::capture.output(
    env$chat_simulate_streaming(
      full_response = "eski yanit",
      session = .css_session(rec),
      values = vals,
      settings_data = list(selected_character = "emre"),
      output = list(),
      stop_generation = function() FALSE,
      tts_engine = env_tts,
      tts_voice = "ses"
    )
  ))

  # Kullanıcı Yeni Söyleşi başlattı: kimlik DEĞİŞTİ ve mesaj listesi boşaldı.
  vals$current_chat_id <- "sohbet-B"
  vals$messages <- list()

  testthat::expect_false(is.null(cozucu))
  # POZITIF AYIRT EDICI: geri cagri kapiya ULASMADAN sessizce reddedilirse
  # asagidaki NEGATIF beklentiler de gecer ve kapinin CALISTIGI kanitlanmaz.
  onceki_reset <- env$.rec$reset
  invisible(utils::capture.output(cozucu(list(success = TRUE, duration = 0))))
  .css_drain()

  testthat::expect_length(vals$messages, 0L)
  testthat::expect_identical(env$.rec$insertUI, 0L)
  # POZITIF AYIRT EDICI: bayat kapisi calistiginda `chat_reset_state()` bir kez
  # cagrilir. Geri cagri kapiya ULASMADAN sessizce reddedilseydi sayac AYNI
  # kalirdi ve asagidaki negatif beklentiler yine gecerdi.
  testthat::expect_identical(env$.rec$reset, onceki_reset + 1L)
  # AYIRT EDICI SINYAL: `initStreamingMessage` akis govdesinin BASINDA
  # gonderilir; kimlik kapisi kaldirilirsa bu kayit DOLAR. Sadece
  # `vals$messages`/`insertUI` bakmak yetmez, cunku onlar dongunun SONUNDA
  # dokunulur ve bu kosum ortami `observe`/`invalidateLater` calistirmaz.
  testthat::expect_length(rec$msgs, 0L)
})

testthat::test_that("sohbet AYNIYSA TTS geri cagrisi akisi baslatir", {
  env <- .css_env()
  rec <- new.env(parent = emptyenv()); rec$msgs <- list()
  vals <- new.env(parent = emptyenv())
  vals$messages <- list()
  vals$typing <- TRUE
  vals$current_chat_id <- "sohbet-A"

  env$mergen_pk_chat_identity <- function(session, values) {
    paste0("chat:", as.character(values$current_chat_id)[1])
  }

  cozucu <- NULL
  env_tts <- function(text, voice) {
    promises::promise(function(resolve, reject) cozucu <<- resolve)
  }

  invisible(utils::capture.output(
    env$chat_simulate_streaming(
      full_response = "guncel yanit",
      session = .css_session(rec),
      values = vals,
      settings_data = list(selected_character = "emre"),
      output = list(),
      # `TRUE` DEĞİL (PR #705 incelemesi, P2): erken çıkışla hem BAYAT hem
      # GEÇEN yol `chat_reset_state()` fonksiyonunu TAM BİR KEZ çağırır, bu
      # yüzden `reset` sayacı iki dalı AYIRT EDEMİYORDU. Kimlik damgası
      # biçimi bozulup her geri çağrı bayat sayılsaydı bu test YİNE geçer,
      # paket yeşil kalır ve TTS sonrası benzetimli akış TAMAMEN ÖLÜRDÜ.
      # `FALSE` ile kapı geçilince akış gövdesine GİRİLİR.
      stop_generation = function() FALSE,
      tts_engine = env_tts,
      tts_voice = "ses"
    )
  ))

  testthat::expect_false(is.null(cozucu))
  invisible(utils::capture.output(cozucu(list(success = TRUE, duration = 0))))
  .css_drain()

  # AYIRT EDİCİ SİNYAL: `initStreamingMessage` YALNIZCA akış gövdesine
  # girildiğinde gönderilir. Bayat testi (yukarıda) aynı kaydın BOŞ kaldığını
  # iddia eder; iki test birlikte kapının HER İKİ yönünü de kilitler.
  tipler <- vapply(rec$msgs, function(m) as.character(m$type %||% "")[1], character(1))
  testthat::expect_true("initStreamingMessage" %in% tipler)
})
