# ==============================================================================
# Dosya Yolu: tests/testthat/test-async-handler-stale-request-race-behavior.R
# Açıklama: Görsel oluşturma ve özetleme (non-streaming yedek) işleyicilerinin
#           ASENKRON geri çağrılarındaki YARIŞ KORUMASI davranış testleri.
#
#           Senaryo: kullanıcı uzun süren bir görsel/özet isteği başlatır, sonra
#           durdurup yeni bir istek başlatır. Bayatlamış (stale) asenkron sonuç
#           çözüldüğünde, yeni isteğin yazıyor göstergesini KALDIRMAMALI, yeni
#           sohbete mesaj EKLEMEMELİ ve yeni isteğin durumunu SIFIRLAMAMALIDIR.
#
#           Bu testler gerçek görsel/LLM uç noktası, DB, tarayıcı veya SSO
#           GEREKTİRMEZ. tracked_future_promise / call_llm_non_streaming
#           promises::promise_resolve / promise_reject ile taklit edilir ve
#           later olay döngüsü elle boşaltılır.
# ==============================================================================

suppressMessages(library(promises))

# later kuyruğunu güvenli sınırla boşaltan yardımcı: promise zincirleri
# mikro-görev olarak planlandığından tek run_now yeterli olmayabilir.
.drain_later_queue <- function(max_iter = 100L) {
  for (i in seq_len(max_iter)) {
    if (later::loop_empty()) break
    later::run_now(timeout = 0)
  }
  invisible(NULL)
}

# Değiştirilebilir istek durumu: current_id ve stopped alanlarını test sırasında
# çevirerek "yeni istek başladı" / "durduruldu" senaryolarını modelleriz.
.make_req_state <- function(current_id = "req_A", stopped = FALSE) {
  st <- new.env()
  st$current_id <- current_id
  st$stopped <- stopped
  st
}

# --- GÖRSEL OLUŞTURMA İŞLEYİCİSİ ----------------------------------------------

.source_image_gen_async <- function(promise_factory) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$.removeUI_calls <- 0L
  env$removeUI <- function(...) {
    env$.removeUI_calls <- env$.removeUI_calls + 1L
    invisible(NULL)
  }
  env$insertUI <- function(...) invisible(NULL)
  env$showToast <- function(...) invisible(NULL)
  env$render_generated_image_html <- function(...) "<div>img</div>"
  env$log_debug <- function(...) invisible(NULL)
  # Merkezi özellik anahtarı çözümleyicisini geçerli bir test anahtarıyla taklit et.
  env$mb_api_key_get_feature_key_value <- function(...) "sk-test"
  # task_fn'i hiç çağırmadan, doğrudan kontrol edilen promise'i döndür.
  env$tracked_future_promise <- function(task_fn, ...) promise_factory()
  # Yarış koruması mergen_is_current_request'e dayanır; aynı env'e yüklenir.
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_send_message_request_lifecycle.R"),
    encoding = "UTF-8", local = env
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_handler_image_generation.R"),
    encoding = "UTF-8", local = env
  )
  env
}

.make_image_async_ctx <- function(req_state) {
  rec <- new.env()
  rec$messages <- list()
  rec$reset_calls <- 0L
  values <- new.env()
  values$typing <- TRUE
  values$current_chat_id <- "chat-new"
  list(
    ctx = list(
      input = list(chat_image_size = "1024x1024", chat_image_quality_hd = FALSE),
      settings_data = list(image_size = "1024x1024", image_quality_hd = FALSE),
      session = list(userData = list(ai_api_key = "sk-test"), token = "tok-1"),
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
      user_message_text = "bir kedi çiz",
      active_request_id = function() req_state$current_id,
      stop_generation = function() isTRUE(req_state$stopped)
    ),
    rec = rec,
    values = values
  )
}

testthat::test_that("görsel: güncel istekte başarı sonucu mesaj ekler ve durumu sıfırlar", {
  req_state <- .make_req_state("req_A")
  env <- .source_image_gen_async(function() {
    promises::promise_resolve(list(success = TRUE, revised_prompt = "bir kedi", local_path = "/tmp/x.png"))
  })
  fix <- .make_image_async_ctx(req_state)

  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  out <- env$handle_image_generation_mode(fix$ctx)
  testthat::expect_true(out)
  .drain_later_queue()

  # Güncel istek: tam akış çalışmalı.
  testthat::expect_length(fix$rec$messages, 1L)
  testthat::expect_identical(fix$rec$reset_calls, 1L)
  testthat::expect_false(fix$values$typing)
})

testthat::test_that("görsel: BAYAT istekte başarı sonucu yeni isteğin durumunu EZMEZ", {
  req_state <- .make_req_state("req_A")
  env <- .source_image_gen_async(function() {
    promises::promise_resolve(list(success = TRUE, revised_prompt = "bir kedi", local_path = "/tmp/x.png"))
  })
  fix <- .make_image_async_ctx(req_state)

  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  env$handle_image_generation_mode(fix$ctx)
  # Kullanıcı durdurup yeni istek başlattı: aktif kimlik değişti.
  req_state$current_id <- "req_B"
  .drain_later_queue()

  # Bayat sonuç hiçbir UI/sohbet mutasyonu yapmamalı.
  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$reset_calls, 0L)
  testthat::expect_true(fix$values$typing)
})

testthat::test_that("görsel: DURDURULMUŞ istekte başarı sonucu yoksayılır", {
  req_state <- .make_req_state("req_A", stopped = FALSE)
  env <- .source_image_gen_async(function() {
    promises::promise_resolve(list(success = TRUE, revised_prompt = "bir kedi", local_path = "/tmp/x.png"))
  })
  fix <- .make_image_async_ctx(req_state)

  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  env$handle_image_generation_mode(fix$ctx)
  req_state$stopped <- TRUE
  .drain_later_queue()

  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$reset_calls, 0L)
})

testthat::test_that("görsel: BAYAT istekte hata sonucu yeni isteğe hata mesajı eklemez", {
  req_state <- .make_req_state("req_A")
  env <- .source_image_gen_async(function() {
    promises::promise_reject(simpleError("boom"))
  })
  fix <- .make_image_async_ctx(req_state)

  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  env$handle_image_generation_mode(fix$ctx)
  req_state$current_id <- "req_B"
  .drain_later_queue()

  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$reset_calls, 0L)
})

testthat::test_that("görsel: güncel istekte hata sonucu Türkçe hata mesajı ekler", {
  req_state <- .make_req_state("req_A")
  env <- .source_image_gen_async(function() {
    promises::promise_reject(simpleError("boom"))
  })
  fix <- .make_image_async_ctx(req_state)

  testthat::local_mocked_bindings(runjs = function(...) invisible(NULL), .package = "shinyjs")

  env$handle_image_generation_mode(fix$ctx)
  .drain_later_queue()

  testthat::expect_length(fix$rec$messages, 1L)
  testthat::expect_true(grepl("Görsel oluşturma hatası", fix$rec$messages[[1]]$content, fixed = TRUE))
  testthat::expect_identical(fix$rec$reset_calls, 1L)
})

# --- ÖZETLEME İŞLEYİCİSİ (NON-STREAMING YEDEK) --------------------------------

.source_summarization_async <- function(llm_promise_factory) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$.removeUI_calls <- 0L
  env$removeUI <- function(...) {
    env$.removeUI_calls <- env$.removeUI_calls + 1L
    invisible(NULL)
  }
  env$showToast <- function(...) invisible(NULL)
  env$log_debug <- function(...) invisible(NULL)
  env$log_info <- function(...) invisible(NULL)
  # API anahtarı çözümleyici taklidi: geçerli anahtar döndür.
  env$mb_api_key_get_effective_key_value <- function(...) "sk-test"
  # Hazırlık taklidi: non-streaming yola düşmek için enable_streaming = FALSE.
  env$prepare_summarization_request <- function(...) {
    list(
      success = TRUE,
      current_settings = list(enable_streaming = FALSE),
      selected_model = "m",
      messages = list(),
      metadata_block = "\n\nKaynakça",
      file_count = 1L,
      prep_duration = 0
    )
  }
  env$llm_promise_factory <- llm_promise_factory
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_send_message_request_lifecycle.R"),
    encoding = "UTF-8", local = env
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_handler_summarization.R"),
    encoding = "UTF-8", local = env
  )
  env
}

.make_summary_async_ctx <- function(req_state, env) {
  rec <- new.env()
  rec$messages <- list()
  rec$reset_calls <- 0L
  values <- new.env()
  values$typing <- TRUE
  list(
    ctx = list(
      session = list(userData = list(), token = "tok-1"),
      input = list(),
      output = list(),
      values = values,
      settings_data = list(
        summary_detail_level = "standard",
        summary_focus_mode = "general",
        enable_tts_audio = FALSE,
        model_selection = "m"
      ),
      ai_processor = list(
        call_llm_non_streaming = function(...) env$llm_promise_factory()
      ),
      stop_generation = function() isTRUE(req_state$stopped),
      active_request_id = function() req_state$current_id,
      perf_tracker = NULL,
      api_config = list(),
      current_user_id = 5L,
      uploaded_count = 1L,
      user_message_text = "özetle",
      current_session_files = list(),
      user_prompt_msg = NULL,
      chat_id_val = "chat-new",
      saved_chats_data = NULL,
      followup_tools = NULL,
      fallback_followup_tool = NULL,
      request_start_time = Sys.time(),
      add_message_fn = function(content, type, html = NULL) {
        rec$messages[[length(rec$messages) + 1L]] <- list(content = content, type = type)
        invisible(TRUE)
      },
      reset_chat_state_fn = function() {
        rec$reset_calls <- rec$reset_calls + 1L
        invisible(TRUE)
      }
    ),
    rec = rec,
    values = values
  )
}

testthat::test_that("özet: güncel istekte non-streaming başarı sonucu mesaj ekler", {
  req_state <- .make_req_state("req_A")
  env <- .source_summarization_async(function() {
    promises::promise_resolve(list(success = TRUE, content = "özet metni"))
  })
  fix <- .make_summary_async_ctx(req_state, env)

  out <- env$handle_summarization_mode(fix$ctx)
  testthat::expect_true(out)
  .drain_later_queue()

  testthat::expect_length(fix$rec$messages, 1L)
  testthat::expect_true(grepl("özet metni", fix$rec$messages[[1]]$content, fixed = TRUE))
  testthat::expect_identical(fix$rec$reset_calls, 1L)
})

testthat::test_that("özet: BAYAT istekte non-streaming başarı sonucu yeni isteği EZMEZ", {
  req_state <- .make_req_state("req_A")
  env <- .source_summarization_async(function() {
    promises::promise_resolve(list(success = TRUE, content = "özet metni"))
  })
  fix <- .make_summary_async_ctx(req_state, env)

  env$handle_summarization_mode(fix$ctx)
  req_state$current_id <- "req_B"
  .drain_later_queue()

  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$reset_calls, 0L)
  testthat::expect_true(fix$values$typing)
})

testthat::test_that("özet: BAYAT istekte non-streaming hata sonucu yeni isteğe dokunmaz", {
  req_state <- .make_req_state("req_A")
  env <- .source_summarization_async(function() {
    promises::promise_reject(simpleError("özet patladı"))
  })
  fix <- .make_summary_async_ctx(req_state, env)

  env$handle_summarization_mode(fix$ctx)
  req_state$current_id <- "req_B"
  .drain_later_queue()

  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$reset_calls, 0L)
})
