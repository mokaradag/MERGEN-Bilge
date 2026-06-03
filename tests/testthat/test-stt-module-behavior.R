# ==============================================================================
# Dosya Yolu: tests/testthat/test-stt-module-behavior.R
# Açıklama: R/module_stt.R STT (Konuşma->Metin) modülünün davranışsal testleri.
#           Modal aç/iptal/onayla akışı, modal-active yayını, paket kilidi
#           (accept_chunks) ve API-anahtarı yoksa STT çağrısı yapılmaması.
#           Gerçek mikrofon/STT endpoint/tarayıcı gerektirmez.
# ==============================================================================

testthat::local_edition(3)

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
