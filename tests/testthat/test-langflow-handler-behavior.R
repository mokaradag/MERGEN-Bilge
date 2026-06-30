# ==============================================================================
# Dosya Yolu: tests/testthat/test-langflow-handler-behavior.R
# Açıklama: R/server_handler_langflow.R handle_langflow_chat_mode() backpressure
#           slot yaşam döngüsü ve erken-dönüş davranışı testleri.
#           send_message slotu values$backpressure_token içine devreder; bu
#           asenkron yol normal cleanup callback'ini çağırmadığından slot, istek
#           bitince (yapılandırma eksik / başarı / hata) AÇIKÇA serbest
#           bırakılmalıdır. Aksi halde MERGEN_BACKPRESSURE_LLM_LIMIT açık
#           ortamlarda diğer kullanıcılar yük altında yanlışlıkla reddedilebilir.
#           Gerçek Langflow uç noktası / future / DB / tarayıcı GEREKMEZ.
# ==============================================================================

.source_langflow_handler_for_test <- function(canned_result = NULL) {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  for (f in c(
    "R/utils_common.R",
    "R/helpers_api_model_config.R",
    "R/helpers_api_model_tool_runtime.R",
    "R/helpers_langflow_runtime.R"
  )) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  # UI / log stub'ları (yan etkisiz).
  env$.removeUI_calls <- 0L
  env$removeUI <- function(...) {
    env$.removeUI_calls <- env$.removeUI_calls + 1L
    invisible(NULL)
  }
  env$insertUI <- function(...) invisible(NULL)
  env$div <- function(...) NULL
  env$showToast <- function(...) invisible(NULL)
  env$log_debug <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)

  # Backpressure slot serbest bırakma çağrılarını kaydet. Gerçek helper'ın req_id
  # korumasını sadık biçimde taklit eder: yalnızca token bu isteğe aitse (req_id
  # eşleşirse) gerçekten serbest bırakır ve kaydeder; aksi halde no-op'tur.
  env$.release_calls <- list()
  env$mergen_send_message_release_values_token <- function(values, req_id = NULL) {
    if (!is.null(req_id)) {
      owner <- as.character(values$backpressure_request_id)[1]
      if (!identical(owner, as.character(req_id)[1])) {
        return(invisible(FALSE))  # koruma: slot yeni isteğe ait, dokunma
      }
    }
    env$.release_calls[[length(env$.release_calls) + 1L]] <- list(req_id = req_id)
    values$backpressure_token <- NULL
    values$backpressure_request_id <- NULL
    invisible(TRUE)
  }

  # future + promise zinciri: success callback'i SENKRON çalıştır.
  env$.future_calls <- 0L
  env$tracked_future_promise <- function(task_fn, ...) {
    env$.future_calls <- env$.future_calls + 1L
    structure(list(), class = "fake_langflow_promise")
  }
  env$.canned_result <- canned_result
  env$`%...>%` <- function(lhs, fn) {
    if (!is.null(env$.canned_result)) fn(env$.canned_result)
    lhs
  }
  env$`%...!%` <- function(lhs, fn) lhs

  source(file.path(repo_root, "R", "server_handler_langflow.R"),
         encoding = "UTF-8", local = env)
  env
}

.make_langflow_ctx <- function(base_url = "https://lf.example.com",
                               flow_id = "pf-1",
                               req_id = "req-1") {
  rec <- new.env()
  rec$messages <- list()
  rec$reset_calls <- 0L

  values <- new.env()
  values$typing <- TRUE
  values$current_chat_id <- "chat-1"
  values$backpressure_token <- "tok-langflow"
  values$backpressure_request_id <- req_id

  config <- list(
    langflow = list(
      base_url = base_url,
      api_key = "fake-key",
      timeout_seconds = 300,
      flow_ids = list(process = flow_id)
    ),
    tool_mode_config = list(
      process = list(
        family = "process",
        runtime = "langflow",
        langflow_flow_id = flow_id,
        model_id = "technical name 1"
      )
    )
  )

  list(
    ctx = list(
      session = list(token = "tok-1"),
      values = values,
      tool_family = "process",
      user_message_text = "merhaba",
      current_user_id = 7L,
      chat_id_val = "chat-1",
      stop_generation = function() FALSE,
      active_request_id = function() req_id,
      add_message_fn = function(content, type, html = NULL) {
        rec$messages[[length(rec$messages) + 1L]] <- list(content = content, type = type)
        list(id = "m1")
      },
      reset_chat_state_fn = function() {
        rec$reset_calls <- rec$reset_calls + 1L
        invisible(NULL)
      },
      api_config = config
    ),
    rec = rec,
    values = values
  )
}

test_that("yapılandırma eksikse slot serbest bırakılır, future başlatılmaz ve net hata eklenir", {
  env <- .source_langflow_handler_for_test()
  fix <- .make_langflow_ctx(base_url = "")  # taban URL yok -> eksik yapılandırma

  out <- env$handle_langflow_chat_mode(fix$ctx)

  expect_true(out)
  # Slot serbest bırakıldı (req_id korumalı)
  expect_equal(length(env$.release_calls), 1L)
  expect_equal(env$.release_calls[[1]]$req_id, "req-1")
  expect_null(fix$values$backpressure_token)
  # Asenkron Langflow çağrısı HİÇ başlatılmadı
  expect_equal(env$.future_calls, 0L)
  # Türkçe yapılandırma-eksik mesajı eklendi ve durum sıfırlandı
  expect_equal(length(fix$rec$messages), 1L)
  expect_match(fix$rec$messages[[1]]$content, "Langflow yapılandırması eksik")
  expect_equal(fix$rec$messages[[1]]$type, "ai")
  expect_equal(fix$rec$reset_calls, 1L)
  expect_false(fix$values$typing)
})

test_that("başarılı Langflow yanıtında slot serbest bırakılır ve cevap AI mesajı olarak eklenir", {
  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  env <- .source_langflow_handler_for_test(
    canned_result = list(success = TRUE, text = "Langflow cevabı", error = NULL, status = 200L)
  )
  fix <- .make_langflow_ctx()

  out <- env$handle_langflow_chat_mode(fix$ctx)

  expect_true(out)
  expect_equal(env$.future_calls, 1L)
  # Slot, asenkron başarı callback'inde serbest bırakıldı
  expect_equal(length(env$.release_calls), 1L)
  expect_equal(env$.release_calls[[1]]$req_id, "req-1")
  expect_null(fix$values$backpressure_token)
  # Cevap AI mesajı olarak eklendi
  expect_equal(length(fix$rec$messages), 1L)
  expect_equal(fix$rec$messages[[1]]$content, "Langflow cevabı")
  expect_equal(fix$rec$messages[[1]]$type, "ai")
  expect_equal(fix$rec$reset_calls, 1L)
})

test_that("durdurma/iptal yolunda bayat callback slotu serbest bırakır (sızıntı önlenir)", {
  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  env <- .source_langflow_handler_for_test(
    canned_result = list(success = TRUE, text = "Langflow cevabı", error = NULL, status = 200L)
  )
  fix <- .make_langflow_ctx()
  # Kullanıcı "Durdur"a bastı: stop_generation TRUE; yeni istek BAŞLAMADI, dolayısıyla
  # slot (backpressure_request_id) hâlâ bu isteğe ("req-1") aittir.
  fix$ctx$stop_generation <- function() TRUE

  out <- env$handle_langflow_chat_mode(fix$ctx)

  expect_true(out)
  # Bayat (durduruldu) callback: req_id korumalı serbest bırakma slotu açar.
  expect_equal(length(env$.release_calls), 1L)
  expect_equal(env$.release_calls[[1]]$req_id, "req-1")
  expect_null(fix$values$backpressure_token)
  # Bayat dalda UI mutasyonu yapılmaz (mesaj eklenmez, durum sıfırlanmaz).
  expect_equal(length(fix$rec$messages), 0L)
  expect_equal(fix$rec$reset_calls, 0L)
})

test_that("yeni istek slotu devraldıysa bayat callback o slotu serbest bırakmaz (no-op)", {
  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  env <- .source_langflow_handler_for_test(
    canned_result = list(success = TRUE, text = "Langflow cevabı", error = NULL, status = 200L)
  )
  fix <- .make_langflow_ctx()
  # Daha yeni bir istek başladı: slot artık "req-2"ye ait ve active_request_id
  # callback çalışırken "req-2" döndürür. Handler en başta "req-1" yakalar.
  fix$values$backpressure_request_id <- "req-2"
  fix$values$backpressure_token <- "tok-2"
  arid_counter <- 0L
  fix$ctx$active_request_id <- function() {
    arid_counter <<- arid_counter + 1L
    if (arid_counter <= 1L) "req-1" else "req-2"
  }

  out <- env$handle_langflow_chat_mode(fix$ctx)

  expect_true(out)
  # Koruma devrede: yeni isteğin ("req-2") slotuna dokunulmaz.
  expect_equal(length(env$.release_calls), 0L)
  expect_equal(fix$values$backpressure_token, "tok-2")
  expect_equal(length(fix$rec$messages), 0L)
  expect_equal(fix$rec$reset_calls, 0L)
})
