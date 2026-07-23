# ==============================================================================
# Dosya Yolu: tests/testthat/test-stt-module-behavior.R
# Açıklama: R/module_stt.R STT (Konuşma->Metin) modülünün davranışsal testleri.
#           Modal aç/iptal/onayla akışı, modal-active yayını, paket kilidi
#           (accept_chunks) ve API-anahtarı yoksa STT çağrısı yapılmaması.
#           Gerçek mikrofon/STT endpoint/tarayıcı gerektirmez.
# ==============================================================================

testthat::local_edition(3)
suppressMessages(library(promises))

.stt_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_stt.R"),
  encoding = "UTF-8",
  local = .stt_env
)

.stt_settings <- function() list(selected_character = "emre", font_size = "large")

test_that("sttServer start_session ve final_text içeren liste döndürür", {
  skip_if_not_installed("shiny")

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      api <- session$returned
      expect_true(is.list(api))
      expect_true(is.function(api$start_session))
      expect_true(is.function(api$final_text))
      # final_text başlangıçta boş string olmalı.
      expect_identical(api$final_text(), "")
    }
  )
})

test_that("start_session: modal-active 'true' yayını ve ns önekli initSTT mesajı gönderilir", {
  skip_if_not_installed("shiny")

  kayit <- new.env()
  kayit$msgs <- list()
  kayit$codes <- character(0)

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      root <- .subset2(session, "parent")
      root$sendCustomMessage <- function(type, message) kayit$msgs[[type]] <- message

      testthat::local_mocked_bindings(
        runjs = function(code, ...) kayit$codes <- c(kayit$codes, code),
        delay = function(ms, expr) expr,        # gecikmeyi anında çalıştır
        .package = "shinyjs"
      )
      # showModal MockSession'da hata vermesin diye etkisiz kıl.
      testthat::local_mocked_bindings(
        showModal = function(...) invisible(NULL),
        .package = "shiny"
      )

      session$returned$start_session()

      # initSTT mesajı doğru ns öneki ve canvas id'siyle gitmeli.
      expect_true("initSTT" %in% names(kayit$msgs))
      expect_equal(kayit$msgs$initSTT$nsPrefix, "stt")
      expect_equal(kayit$msgs$initSTT$canvasId, "stt-visualizer_canvas")

      # Modal açıldığında stt_modal_active TRUE yayını yapılmalı.
      aktif_kod <- kayit$codes[grepl("stt_modal_active", kayit$codes, fixed = TRUE)]
      expect_true(length(aktif_kod) >= 1)
      expect_true(any(grepl("'stt_modal_active', true", aktif_kod, fixed = TRUE)))
    }
  )
})

test_that("accept_btn: kırpılmış metni final_text'e aktarır ve modal-active 'false' yayını yapar", {
  skip_if_not_installed("shiny")

  kayit <- new.env()
  kayit$codes <- character(0)

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) kayit$codes <- c(kayit$codes, code),
        .package = "shinyjs"
      )

      session$setInputs(transcribed_text = "  selam dünya  ")
      session$setInputs(accept_btn = 1)

      # Boşluklar kırpılarak final_text'e yazılmalı.
      expect_identical(session$returned$final_text(), "selam dünya")

      # Modal kapanırken stt_modal_active FALSE yayını ve temizleme çağrısı olmalı.
      expect_true(any(grepl("'stt_modal_active', false", kayit$codes, fixed = TRUE)))
      expect_true(any(grepl("stopAndCleanup", kayit$codes, fixed = TRUE)))
    }
  )
})

test_that("dismiss_btn: final_text'i değiştirmez ama modal-active 'false' yayını yapar", {
  skip_if_not_installed("shiny")

  kayit <- new.env()
  kayit$codes <- character(0)

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) kayit$codes <- c(kayit$codes, code),
        .package = "shinyjs"
      )

      session$setInputs(transcribed_text = "kaydedilmemeli")
      session$setInputs(dismiss_btn = 1)

      # İptal final_text'i değiştirmemeli.
      expect_identical(session$returned$final_text(), "")
      expect_true(any(grepl("'stt_modal_active', false", kayit$codes, fixed = TRUE)))
      expect_true(any(grepl("stopAndCleanup", kayit$codes, fixed = TRUE)))
    }
  )
})

test_that("audio_chunk: kayıt kabul kapalıyken (kilit) STT çağrısı yapılmaz", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("httr")

  kayit <- new.env()
  kayit$post <- 0L

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      # POST çağrılırsa sayaç artar; kilit nedeniyle hiç çağrılmamalı.
      testthat::local_mocked_bindings(
        POST = function(...) {
          kayit$post <- kayit$post + 1L
          structure(list(), class = "response")
        },
        .package = "httr"
      )

      # start_session çağrılmadı -> accept_chunks varsayılan FALSE (kilit kapalı).
      session$setInputs(audio_chunk = "ZHVtbXk=")  # base64 "dummy"

      expect_identical(kayit$post, 0L)
    }
  )
})

test_that("toggle_record_btn (Durdur): transcribe_gen ve kuyruk sıfırlanmaz (uçuştaki parçalar korunur)", {
  skip_if_not_installed("shiny")

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        .package = "shinyjs"
      )

      # Kayıt sırasında dispatch edilmiş, henüz sonuçlanmamış bir STT parçasını
      # simüle et (uçuştaki durum).
      rv$is_recording <- TRUE
      rv$accept_chunks <- TRUE
      gen_once_dispatched <- isolate(rv$transcribe_gen)
      rv$next_chunk_seq <- 5L
      rv$next_append_seq <- 3L
      rv$pending_stt_chunks <- 1L

      session$setInputs(toggle_record_btn = 1) # Durdur

      # Duraklatma yeni paket kabulünü kapatmalı...
      expect_false(isolate(rv$accept_chunks))
      expect_false(isolate(rv$is_recording))
      # ...ama üretim jetonunu VE kuyruğu sıfırlamamalı; aksi halde uçuştaki
      # parça sonuçlandığında üretim uyuşmazlığı yüzünden sessizce düşer.
      expect_identical(isolate(rv$transcribe_gen), gen_once_dispatched)
      expect_identical(isolate(rv$next_chunk_seq), 5L)
      expect_identical(isolate(rv$next_append_seq), 3L)
      expect_identical(isolate(rv$pending_stt_chunks), 1L)
    }
  )
})

test_that("Durdur sonrası çözülen STT parçası geçmişe eklenir (düşürülmez)", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  # tracked_future_promise, gerçek future/worker'a gitmeden elle çözülebilir
  # bir promise döndürecek şekilde .stt_env içinde GEÇİCİ olarak değiştirilir
  # (sttServer bu ismi .stt_env -> globalenv() zincirinde arar). Test sonunda
  # geri yüklenir ki diğer testleri etkilemesin.
  had_override <- exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)
  old_override <- if (had_override) get("tracked_future_promise", envir = .stt_env) else NULL
  on.exit({
    if (had_override) {
      assign("tracked_future_promise", old_override, envir = .stt_env)
    } else if (exists("tracked_future_promise", envir = .stt_env, inherits = FALSE)) {
      rm("tracked_future_promise", envir = .stt_env)
    }
  }, add = TRUE)

  resolve_fn <- NULL
  .stt_env$tracked_future_promise <- function(task_fn, ..., globals = list()) {
    promises::promise(function(resolve, reject) {
      resolve_fn <<- resolve
    })
  }

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        delay = function(ms, expr) expr,
        .package = "shinyjs"
      )
      testthat::local_mocked_bindings(
        showModal = function(...) invisible(NULL),
        .package = "shiny"
      )

      session$userData$ai_api_key <- "sk-test"
      session$returned$start_session()
      session$setInputs(audio_chunk = "ZHVtbXk=") # parça dispatch edildi, henüz çözülmedi

      expect_identical(isolate(rv$pending_stt_chunks), 1L)

      # Kullanıcı, parça hâlâ uçuştayken Durdur'a basar.
      session$setInputs(toggle_record_btn = 1)
      expect_false(isolate(rv$accept_chunks))

      # Parça ŞİMDİ (duraklatmadan SONRA) gerçek metinle çözülür.
      resolve_fn("merhaba dünya")
      for (i in seq_len(50)) {
        if (later::loop_empty()) break
        later::run_now(timeout = 0)
      }
      session$flushReact()

      # Metin düşürülmemeli; sunucu geçmişine ve metin alanına eklenmiş olmalı.
      expect_identical(isolate(rv$transcription_history), "merhaba dünya")
      expect_identical(isolate(rv$pending_stt_chunks), 0L)
    }
  )
})

test_that("audio_chunk: kabul açık olsa bile API anahtarı yoksa STT çağrısı yapılmaz", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("httr")

  kayit <- new.env()
  kayit$post <- 0L

  # LOCAL_STT_* anahtarlarını bu test boyunca boş tut.
  withr::local_envvar(c(
    LOCAL_STT_ENDPOINT = "",
    LOCAL_STT_MODEL = "",
    LOCAL_STT_API_KEY = ""
  ))

  shiny::testServer(
    .stt_env$sttServer,
    args = list(id = "stt", parent_session = NULL, settings = .stt_settings()),
    {
      # MockSession userData$ai_api_key NULL döndürmesin diye boş string ata.
      session$userData$ai_api_key <- ""

      testthat::local_mocked_bindings(
        runjs = function(code, ...) invisible(NULL),
        delay = function(ms, expr) expr,
        .package = "shinyjs"
      )
      testthat::local_mocked_bindings(
        showModal = function(...) invisible(NULL),
        .package = "shiny"
      )
      testthat::local_mocked_bindings(
        POST = function(...) {
          kayit$post <- kayit$post + 1L
          structure(list(), class = "response")
        },
        .package = "httr"
      )

      # start_session -> accept_chunks TRUE (kilit açık)
      session$returned$start_session()
      session$setInputs(audio_chunk = "ZHVtbXk=")

      # Anahtar yokken POST yapılmamalı.
      expect_identical(kayit$post, 0L)
    }
  )
})
