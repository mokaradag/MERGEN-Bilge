# ==============================================================================
# Dosya Yolu: tests/testthat/test-nonstreaming-handler-stale-request-race-behavior.R
# Açıklama: NON-STREAMING LLM yanıt işleyicisinin (generate_non_streaming_stoppable)
#           ASENKRON geri çağrılarındaki YARIŞ KORUMASI davranış testleri.
#
#           Senaryo: kullanıcı uzun süren bir MCP/non-streaming isteği başlatır,
#           sonra durdurup yeni bir istek başlatır. Bayatlamış (stale) asenkron
#           sonuç çözüldüğünde/reddedildiğinde, yeni isteğin yazıyor göstergesini
#           KALDIRMAMALI, yeni isteğe mesaj EKLEMEMELİ, bayat hata toast'ı
#           GÖSTERMEMELİ ve yeni isteğin sohbet durumunu SIFIRLAMAMALIDIR.
#
#           Bu testler gerçek LLM uç noktası, DB, tarayıcı veya SSO GEREKTİRMEZ.
#           ai_processor$call_llm_non_streaming promises ile taklit edilir ve
#           later olay döngüsü elle boşaltılır.
# ==============================================================================

suppressMessages(library(promises))

# later kuyruğunu güvenli sınırla boşaltan yardımcı.
.nonstream_drain_later <- function(max_iter = 200L) {
  for (i in seq_len(max_iter)) {
    if (later::loop_empty()) break
    later::run_now(timeout = 0)
  }
  invisible(NULL)
}

# Değiştirilebilir istek durumu: current_id ve stopped alanlarını test sırasında
# çevirerek "yeni istek başladı" / "durduruldu" senaryolarını modelleriz.
.nonstream_req_state <- function(current_id = "req_A", stopped = FALSE) {
  st <- new.env()
  st$current_id <- current_id
  st$stopped <- stopped
  st
}

# İşleyici ortamını hazırlar: ağır bağımlılıkları taklit eder, gerçek istek
# yaşam döngüsü yardımcılarını ve LLM yanıt işleyicisini aynı env'e yükler.
.source_nonstream_handler <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Ağır / yan etkili bağımlılıkların güvenli taklitleri
  env$dbg_dump <- function(...) invisible(NULL)
  env$log_debug <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$log_info <- function(...) invisible(NULL)
  env$showToast <- function(...) invisible(NULL)
  env$log_ai_usage <- function(...) invisible(NULL)
  env$build_followup_suggestions <- function(...) list()
  env$normalize_character_id <- function(x) "emre"
  env$get_characters_data <- function() NULL
  env$update_message_reasoning_content <- function(...) invisible(NULL)
  env$decode_stream_delta_payload <- function(...) ""
  env$path_exists_relaxed <- function(...) FALSE

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_send_message_request_lifecycle.R"),
    encoding = "UTF-8", local = env
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_llm_response_handlers.R"),
    encoding = "UTF-8", local = env
  )
  env
}

# generate_non_streaming_stoppable closure'unu hazır kayıt-defteriyle döndürür.
.make_nonstream_fixture <- function(env, req_state, llm_promise_factory) {
  rec <- new.env()
  rec$messages <- list()
  rec$reset_calls <- 0L
  rec$tts_calls <- 0L
  rec$toast_calls <- 0L

  values <- new.env()
  values$typing <- TRUE
  values$is_sending <- TRUE

  # showToast taklidini sayaçlı yap (bayat hata toast'ı görünmemeli kontrolü)
  env$showToast <- function(...) {
    rec$toast_calls <- rec$toast_calls + 1L
    invisible(NULL)
  }

  session <- list(userData = list(), token = "tok-1")

  handlers <- env$llmResponseHandlersInit(
    session = session,
    values = values,
    settings_data = list(enable_tts_audio = FALSE),
    ai_processor = list(
      call_llm_non_streaming = function(...) llm_promise_factory()
    ),
    perf_tracker = list(
      track_error = function(...) invisible(NULL),
      track_request = function(...) invisible(NULL)
    ),
    # reactiveVal taklidi: argümansız çağrı OKUR, argümanlı çağrı YAZAR.
    # generate_non_streaming_stoppable başlangıçta active_request_id(req_id)
    # ile kendini aktif eder; bayat senaryoda testi current_id'yi sonradan
    # değiştirerek modelleriz.
    active_request_id = function(v) {
      if (missing(v)) return(req_state$current_id)
      req_state$current_id <- v
      invisible(v)
    },
    stop_generation = function() isTRUE(req_state$stopped),
    reset_chat_state_fn = function() {
      rec$reset_calls <- rec$reset_calls + 1L
      invisible(TRUE)
    },
    add_message_fn = function(content, type, ...) {
      rec$messages[[length(rec$messages) + 1L]] <- list(content = content, type = type)
      list(id = "m1", db_id = 1L)
    },
    trigger_tts_fn = function(...) {
      rec$tts_calls <- rec$tts_calls + 1L
      invisible(NULL)
    },
    followup_tools = NULL,
    fallback_followup_tool = NULL,
    api_config = list()
  )

  list(rec = rec, values = values, gen = handlers$generate_non_streaming_stoppable)
}

.invoke_nonstream <- function(fix, current_settings = list(enable_mcp_reasoning_stream = FALSE, tool_family = "normal")) {
  fix$gen(
    chat_history = list(),
    current_settings = current_settings,
    user_prompt_msg = list(content = "soru", db_id = 1L),
    chat_id_val = "chat-new",
    model_selected = "m",
    last_user_text = "soru",
    current_user_id = 5L,
    request_id = "req_A"
  )
}

# --- GÜNCEL İSTEK: davranış korunur -------------------------------------------

testthat::test_that("non-streaming: güncel istekte başarı sonucu mesaj ekler ve durumu sıfırlar", {
  testthat::local_mocked_bindings(removeUI = function(...) invisible(NULL), .package = "shiny")
  env <- .source_nonstream_handler()
  req_state <- .nonstream_req_state("req_A")
  fix <- .make_nonstream_fixture(env, req_state, function() {
    promises::promise_resolve(list(success = TRUE, content = "cevap metni", duration = 1, reasoning_content = NULL, chart_store = NULL))
  })

  .invoke_nonstream(fix)
  .nonstream_drain_later()

  testthat::expect_length(fix$rec$messages, 1L)
  testthat::expect_true(grepl("cevap metni", fix$rec$messages[[1]]$content, fixed = TRUE))
  testthat::expect_identical(fix$rec$reset_calls, 1L)
  testthat::expect_false(fix$values$typing)
})

testthat::test_that("non-streaming: güncel istekte hata sonucu Türkçe toast gösterir ve durumu sıfırlar", {
  testthat::local_mocked_bindings(removeUI = function(...) invisible(NULL), .package = "shiny")
  env <- .source_nonstream_handler()
  req_state <- .nonstream_req_state("req_A")
  fix <- .make_nonstream_fixture(env, req_state, function() {
    promises::promise_reject(simpleError("patladı"))
  })

  .invoke_nonstream(fix)
  .nonstream_drain_later()

  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$toast_calls, 1L)
  testthat::expect_identical(fix$rec$reset_calls, 1L)
  testthat::expect_false(fix$values$typing)
})

# --- BAYAT İSTEK: yeni isteğin durumu KORUNUR (yarış koruması) ----------------

testthat::test_that("non-streaming: BAYAT istekte başarı sonucu yeni isteği EZMEZ", {
  testthat::local_mocked_bindings(removeUI = function(...) invisible(NULL), .package = "shiny")
  env <- .source_nonstream_handler()
  req_state <- .nonstream_req_state("req_A")
  fix <- .make_nonstream_fixture(env, req_state, function() {
    promises::promise_resolve(list(success = TRUE, content = "cevap metni", duration = 1, reasoning_content = NULL, chart_store = NULL))
  })

  .invoke_nonstream(fix)
  # Kullanıcı durdurup yeni istek başlattı: aktif kimlik değişti.
  req_state$current_id <- "req_B"
  .nonstream_drain_later()

  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$reset_calls, 0L)
  testthat::expect_identical(fix$rec$tts_calls, 0L)
  testthat::expect_true(fix$values$typing)
})

testthat::test_that("non-streaming: BAYAT istekte hata sonucu yeni isteğe toast/sıfırlama yapmaz", {
  testthat::local_mocked_bindings(removeUI = function(...) invisible(NULL), .package = "shiny")
  env <- .source_nonstream_handler()
  req_state <- .nonstream_req_state("req_A")
  fix <- .make_nonstream_fixture(env, req_state, function() {
    promises::promise_reject(simpleError("bayat hata"))
  })

  .invoke_nonstream(fix)
  req_state$current_id <- "req_B"
  .nonstream_drain_later()

  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$toast_calls, 0L)
  testthat::expect_identical(fix$rec$reset_calls, 0L)
  testthat::expect_true(fix$values$typing)
})

# --- DURDURULMUŞ İSTEK (iptal): yeni isteğe mesaj/toast yok -------------------

testthat::test_that("non-streaming: DURDURULMUŞ (cancelled) istekte başarı sonucu mesaj/toast eklemez", {
  testthat::local_mocked_bindings(removeUI = function(...) invisible(NULL), .package = "shiny")
  env <- .source_nonstream_handler()
  # Durdurma sonrası: aktif kimlik cancelled_ olur, stop_generation TRUE.
  req_state <- .nonstream_req_state("cancelled_123", stopped = TRUE)
  fix <- .make_nonstream_fixture(env, req_state, function() {
    promises::promise_resolve(list(success = TRUE, content = "cevap metni", duration = 1, reasoning_content = NULL, chart_store = NULL))
  })

  .invoke_nonstream(fix)
  .nonstream_drain_later()

  # Bayat (durdurulmuş) sonuç sohbete mesaj eklememeli, toast göstermemeli.
  testthat::expect_length(fix$rec$messages, 0L)
  testthat::expect_identical(fix$rec$toast_calls, 0L)
})
