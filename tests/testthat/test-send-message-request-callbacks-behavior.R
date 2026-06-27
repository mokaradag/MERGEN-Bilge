# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-request-callbacks-behavior.R
# Açıklama: helpers_send_message_model_runtime.R
#           mergen_build_send_message_request_callbacks() için davranış testleri.
#           cleanup/abort kapanışlarının, oluşturuldukları istek kimliğini (req_id)
#           yakalayıp mergen_cleanup_send_message / mergen_abort_send_message
#           çağrılarına request-scoped olarak ilettiği doğrulanır. Bu, bayat async
#           geri çağırmaların daha yeni bir isteğin durumunu temizlemesini önleyen
#           sözleşmedir. Bağımlılıklar env içinde stub'lanır; gerçek Shiny/DB yok.
# ==============================================================================

.sendMsgCallbacksEnv <- function(capture) {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_send_message_model_runtime.R"),
         encoding = "UTF-8", local = env)

  # Alt çağrıları yakala: argümanların doğru iletildiğini kanıtlamak için.
  env$mergen_cleanup_send_message <- function(...) {
    capture$cleanup <- list(...)
    invisible(NULL)
  }
  env$mergen_abort_send_message <- function(...) {
    capture$abort <- list(...)
    invisible(NULL)
  }
  env$mergen_send_message_release_values_token <- function(...) {
    capture$release <- list(...)
    invisible(TRUE)
  }
  env
}

testthat::test_that("oluşturulan callback listesi cleanup ve abort kapanışlarını içerir", {
  capture <- new.env()
  env <- .sendMsgCallbacksEnv(capture)

  cb <- env$mergen_build_send_message_request_callbacks(
    session = "S", values = "V", reset_chat_state_fn = function() NULL,
    active_request_id = "ARID", req_id = "REQ-1"
  )

  testthat::expect_true(is.list(cb))
  testthat::expect_true(is.function(cb$cleanup))
  testthat::expect_true(is.function(cb$abort))
})

testthat::test_that("cleanup kapanışı req_id'yi yakalar ve mergen_cleanup_send_message'a iletir", {
  capture <- new.env()
  env <- .sendMsgCallbacksEnv(capture)

  reset_fn <- function() "reset"
  cb <- env$mergen_build_send_message_request_callbacks(
    session = "S", values = "V", reset_chat_state_fn = reset_fn,
    active_request_id = "ARID", req_id = "REQ-7"
  )

  cb$cleanup()  # varsayılan remove_typing_wrapper = TRUE

  arglar <- capture$cleanup
  testthat::expect_identical(arglar$values, "V")
  testthat::expect_identical(arglar$reset_chat_state_fn, reset_fn)
  testthat::expect_true(arglar$remove_typing_wrapper)
  testthat::expect_identical(arglar$active_request_id, "ARID")
  # En kritik sözleşme: oluşturulma anındaki req_id yakalanıp iletilir
  testthat::expect_identical(arglar$req_id, "REQ-7")
  testthat::expect_identical(capture$release$values, "V")
  testthat::expect_identical(capture$release$req_id, "REQ-7")
})

testthat::test_that("cleanup remove_typing_wrapper = FALSE bayrağını iletir", {
  capture <- new.env()
  env <- .sendMsgCallbacksEnv(capture)

  cb <- env$mergen_build_send_message_request_callbacks(
    session = "S", values = "V", reset_chat_state_fn = function() NULL,
    active_request_id = "ARID", req_id = "REQ-1"
  )

  cb$cleanup(remove_typing_wrapper = FALSE)
  testthat::expect_false(capture$cleanup$remove_typing_wrapper)
})

testthat::test_that("abort kapanışı toast mesaj/tip + req_id'yi mergen_abort_send_message'a iletir", {
  capture <- new.env()
  env <- .sendMsgCallbacksEnv(capture)

  cb <- env$mergen_build_send_message_request_callbacks(
    session = "SESS", values = "V", reset_chat_state_fn = function() NULL,
    active_request_id = "ARID", req_id = "REQ-9"
  )

  cb$abort(message = "İşlem durduruldu", type = "warning")

  arglar <- capture$abort
  testthat::expect_identical(arglar$session, "SESS")
  testthat::expect_identical(arglar$toast_message, "İşlem durduruldu")
  testthat::expect_identical(arglar$toast_type, "warning")
  testthat::expect_true(arglar$remove_typing_wrapper)
  testthat::expect_identical(arglar$active_request_id, "ARID")
  testthat::expect_identical(arglar$req_id, "REQ-9")
  testthat::expect_identical(capture$release$values, "V")
  testthat::expect_identical(capture$release$req_id, "REQ-9")
})

testthat::test_that("farklı req_id'li iki callback seti birbirinin kimliğini taşımaz (request-scoped)", {
  capture1 <- new.env()
  env1 <- .sendMsgCallbacksEnv(capture1)
  cb1 <- env1$mergen_build_send_message_request_callbacks(
    session = "S", values = "V", reset_chat_state_fn = function() NULL,
    active_request_id = "A", req_id = "REQ-A"
  )

  capture2 <- new.env()
  env2 <- .sendMsgCallbacksEnv(capture2)
  cb2 <- env2$mergen_build_send_message_request_callbacks(
    session = "S", values = "V", reset_chat_state_fn = function() NULL,
    active_request_id = "A", req_id = "REQ-B"
  )

  cb1$cleanup()
  cb2$cleanup()

  testthat::expect_identical(capture1$cleanup$req_id, "REQ-A")
  testthat::expect_identical(capture2$cleanup$req_id, "REQ-B")
})
