# ==============================================================================
# Dosya Yolu: tests/testthat/test-image-generation-handler-behavior.R
# Açıklama: R/server_handler_image_generation.R handle_image_generation_mode()
#           fonksiyonunun API-anahtarı-yok koruma yolu testleri. Bu dosya daha
#           önce hiçbir test tarafından çağrılmıyordu.
#
#           ctx$session$userData$ai_api_key boşsa handler asenkron görsel
#           üretimini HİÇ başlatmadan kullanıcıya Türkçe uyarı mesajı ekler,
#           yazıyor göstergesini kapatır, sohbet durumunu sıfırlar ve TRUE döner.
#           Bu testler yalnızca o erken-dönüş yolunu kapsar. Gerçek görsel uç
#           noktası / future / DB GEREKMEZ.
# ==============================================================================

.source_image_gen_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  # Görsel modu erken-dönüş yolunda kullanılan UI yardımcıları stub'lanır.
  env$.removeUI_calls <- 0L
  env$removeUI <- function(...) {
    env$.removeUI_calls <- env$.removeUI_calls + 1L
    invisible(NULL)
  }
  # Bunlar yalnızca anahtar VARSA çağrılır; guard yolunda çağrılmamalı.
  env$.insertUI_calls <- 0L
  env$insertUI <- function(...) {
    env$.insertUI_calls <- env$.insertUI_calls + 1L
    invisible(NULL)
  }
  env$.future_calls <- 0L
  env$tracked_future_promise <- function(...) {
    env$.future_calls <- env$.future_calls + 1L
    stop("guard ihlali: anahtar yokken görsel üretimi başlatılmamalı")
  }
  env$log_debug <- function(...) invisible(NULL)
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_handler_image_generation.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Mesaj/sıfırlama yan etkilerini kaydeden ctx kurucusu.
.make_image_ctx <- function(api_key = "") {
  rec <- new.env()
  rec$messages <- list()
  rec$reset_calls <- 0L
  values <- new.env()
  values$typing <- TRUE
  values$current_chat_id <- "chat-1"
  list(
    ctx = list(
      input = list(chat_image_size = "1024x1024", chat_image_quality_hd = FALSE),
      settings_data = list(image_size = "1024x1024", image_quality_hd = FALSE),
      session = list(userData = list(ai_api_key = api_key), token = "tok-1"),
      values = values,
      add_message_fn = function(content, type, html = NULL) {
        rec$messages[[length(rec$messages) + 1L]] <- list(content = content, type = type)
        invisible(TRUE)
      },
      reset_chat_state_fn = function() {
        rec$reset_calls <- rec$reset_calls + 1L
        invisible(TRUE)
      },
      current_user_id = 5L,
      user_message_text = "bir kedi çiz"
    ),
    rec = rec,
    values = values
  )
}

testthat::test_that("API anahtarı boşsa handler erken döner ve TRUE verir", {
  env <- .source_image_gen_for_test()
  fix <- .make_image_ctx(api_key = "")

  sonuc <- env$handle_image_generation_mode(fix$ctx)
  testthat::expect_true(sonuc)
})

testthat::test_that("API anahtarı boşsa kullanıcıya Türkçe uyarı mesajı eklenir", {
  env <- .source_image_gen_for_test()
  fix <- .make_image_ctx(api_key = "")

  env$handle_image_generation_mode(fix$ctx)
  testthat::expect_length(fix$rec$messages, 1L)
  msg <- fix$rec$messages[[1]]
  testthat::expect_identical(msg$type, "ai")
  testthat::expect_true(grepl("API anahtarı gerekli", msg$content, fixed = TRUE))
})

testthat::test_that("API anahtarı boşsa yazıyor göstergesi kapatılır ve durum sıfırlanır", {
  env <- .source_image_gen_for_test()
  fix <- .make_image_ctx(api_key = "")

  env$handle_image_generation_mode(fix$ctx)
  testthat::expect_false(fix$values$typing)            # ctx$values$typing <- FALSE
  testthat::expect_identical(fix$rec$reset_calls, 1L)  # reset_chat_state_fn çağrıldı
  testthat::expect_true(env$.removeUI_calls >= 1L)     # yazıyor sarmalayıcı kaldırıldı
})

testthat::test_that("API anahtarı boşsa asenkron görsel üretimi HİÇ başlatılmaz", {
  env <- .source_image_gen_for_test()
  fix <- .make_image_ctx(api_key = "")

  env$handle_image_generation_mode(fix$ctx)
  # Guard yolunda ne future ne de insertUI çağrılmalı.
  testthat::expect_identical(env$.future_calls, 0L)
  testthat::expect_identical(env$.insertUI_calls, 0L)
})

testthat::test_that("guard yolu mevcut sohbet kimliğini değiştirmez", {
  env <- .source_image_gen_for_test()
  fix <- .make_image_ctx(api_key = "")
  env$handle_image_generation_mode(fix$ctx)
  # Anahtar-yok dalı yalnızca uyarı ekler; current_chat_id'ye dokunmamalı.
  testthat::expect_identical(fix$values$current_chat_id, "chat-1")
})
