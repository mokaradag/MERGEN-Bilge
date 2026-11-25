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

# Görsel isteği sürerken etkin söyleşi silinir/sıfırlanırsa (istek kimliği
# değişmese de) sonuç sıfırlanan görünüme ya da sonradan açılan başka söyleşiye
# eklenmez; gönderme durumu serbest bırakılır.
testthat::test_that("görsel sonucu söyleşi sıfırlandıktan sonra gelirse mesaj eklenmez, durum serbest bırakılır", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_async_result_guard.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "server_handler_image_generation.R"), encoding = "UTF-8", local = env)
  env$mergen_resolve_image_api_key <- function(...) "anahtar"
  env$removeUI <- env$insertUI <- env$showToast <- env$log_debug <- function(...) NULL
  env$render_generated_image_html <- function(...) "<img>"
  cozumle <- NULL
  env$tracked_future_promise <- function(...) promises::promise(function(resolve, reject) cozumle <<- resolve)
  env$`%...>%` <- promises::`%...>%`
  env$`%...!%` <- promises::`%...!%`
  testthat::local_mocked_bindings(runjs = function(...) NULL, .package = "shinyjs")
  mesajlar <- list(); sifirlama <- 0L
  values <- new.env(); values$current_chat_id <- 9L; values$typing <- TRUE
  ud <- new.env()
  later::with_temp_loop({
    env$handle_image_generation_mode(list(
      input = list(), settings_data = list(), values = values,
      session = list(token = "gorsel-test", userData = ud), current_user_id = 7, user_message_text = "kedi",
      add_message_fn = function(content, type, html = NULL) mesajlar[[length(mesajlar) + 1L]] <<- content,
      reset_chat_state_fn = function() sifirlama <<- sifirlama + 1L
    ))
    # Etkin söyleşi silindi: kimlik düşer, kaydedilmemiş söyleşi nesli artar.
    values$current_chat_id <- NULL
    ud$pk_unsaved_chat_epoch <- 1L
    cozumle(list(success = TRUE, local_path = "x.png"))
    for (i in seq_len(50L)) { if (later::loop_empty()) break; later::run_now(timeout = 0) }
  })
  testthat::expect_length(mesajlar, 0L)
  testthat::expect_identical(sifirlama, 1L)
  testthat::expect_false(isTRUE(values$typing))
})

# Sahipsiz sonuç senaryoları için ortak kurulum: sonuç sözü elle çözülür.
.gorsel_sahiplik_kur <- function(values, ud, oturum_kapali = FALSE, sahip_hatasi = FALSE) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_async_result_guard.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "server_handler_image_generation.R"), encoding = "UTF-8", local = env)
  if (isTRUE(sahip_hatasi)) env$mergen_chat_owner_guard <- function(...) function() stop("sahiplik denetimi hatası (test)")
  env$mergen_resolve_image_api_key <- function(...) "anahtar"
  env$removeUI <- env$insertUI <- env$showToast <- env$log_debug <- function(...) NULL
  env$render_generated_image_html <- function(...) "<img>"
  kayit <- new.env(); kayit$mesajlar <- list(); kayit$sifirlama <- 0L
  env$tracked_future_promise <- function(...) promises::promise(function(resolve, reject) kayit$cozumle <- resolve)
  env$`%...>%` <- promises::`%...>%`
  env$`%...!%` <- promises::`%...!%`
  kayit$calistir <- function() env$handle_image_generation_mode(list(
    input = list(), settings_data = list(), values = values,
    session = list(token = "gorsel-test", userData = ud, isClosed = function() oturum_kapali),
    current_user_id = 7, user_message_text = "kedi",
    add_message_fn = function(content, type, html = NULL) kayit$mesajlar[[length(kayit$mesajlar) + 1L]] <- content,
    reset_chat_state_fn = function() kayit$sifirlama <- kayit$sifirlama + 1L
  ))
  kayit
}

testthat::test_that("kayıtsız söyleşide yalnızca nesil ilerlerse bayat görsel sonucu reddedilir", {
  testthat::skip_if_not_installed("promises")
  values <- new.env(); values$current_chat_id <- NULL; values$typing <- TRUE
  ud <- new.env(); ud$pk_unsaved_chat_epoch <- 0L
  testthat::local_mocked_bindings(runjs = function(...) NULL, .package = "shinyjs")
  later::with_temp_loop({
    kayit <- .gorsel_sahiplik_kur(values, ud)
    kayit$calistir()
    # Söyleşi kimliği (NULL), kullanıcı ve istek değişmeden yalnızca nesil artar.
    ud$pk_unsaved_chat_epoch <- 1L
    kayit$cozumle(list(success = TRUE, local_path = "x.png"))
    for (i in seq_len(50L)) { if (later::loop_empty()) break; later::run_now(timeout = 0) }
  })
  testthat::expect_length(kayit$mesajlar, 0L)
  testthat::expect_null(values$current_chat_id)
  testthat::expect_identical(kayit$sifirlama, 1L)
})

testthat::test_that("sahiplik denetimi hata verirse görsel sonucu eklenmez (kapalı-başarısız)", {
  testthat::skip_if_not_installed("promises")
  values <- new.env(); values$current_chat_id <- 9L; values$typing <- TRUE
  ud <- new.env()
  testthat::local_mocked_bindings(runjs = function(...) NULL, .package = "shinyjs")
  later::with_temp_loop({
    kayit <- .gorsel_sahiplik_kur(values, ud, sahip_hatasi = TRUE)
    kayit$calistir()
    kayit$cozumle(list(success = TRUE, local_path = "x.png"))
    for (i in seq_len(50L)) { if (later::loop_empty()) break; later::run_now(timeout = 0) }
  })
  testthat::expect_length(kayit$mesajlar, 0L)
  testthat::expect_identical(kayit$sifirlama, 1L)
  testthat::expect_false(isTRUE(values$typing))
})

testthat::test_that("oturum kapandıktan sonra gelen sahipsiz görsel sonucu UI sıfırlaması yapmaz", {
  testthat::skip_if_not_installed("promises")
  values <- new.env(); values$current_chat_id <- 9L; values$typing <- TRUE
  ud <- new.env()
  testthat::local_mocked_bindings(runjs = function(...) NULL, .package = "shinyjs")
  later::with_temp_loop({
    kayit <- .gorsel_sahiplik_kur(values, ud, oturum_kapali = TRUE, sahip_hatasi = TRUE)
    kayit$calistir()
    kayit$cozumle(list(success = TRUE, local_path = "x.png"))
    for (i in seq_len(50L)) { if (later::loop_empty()) break; later::run_now(timeout = 0) }
  })
  testthat::expect_length(kayit$mesajlar, 0L)
  testthat::expect_identical(kayit$sifirlama, 0L)
})
