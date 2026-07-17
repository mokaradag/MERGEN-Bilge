# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-handler-streaming-tts-contract.R
# Açıklama: TTS açık streaming dalının send_message'tan ayrı işleyiciye
#           (R/server_handler_streaming_tts.R -> handle_streaming_tts_mode)
#           çıkarılması sözleşmesi. Yapısal ayrım + promise zinciri davranışı
#           (başarı / başarısız / durdurulmuş / reddedilmiş yollar) test edilir.
#           Davranış send_message içindeki eski satır içi daldan birebir taşındı.
# ==============================================================================

testthat::local_edition(3)

.sht_repo_root <- resolve_repo_root_for_tests()
.sht_handler_path <- file.path(.sht_repo_root, "R", "server_handler_streaming_tts.R")
.sht_send_path <- file.path(.sht_repo_root, "R", "server_send_message.R")

# ASCII çapaları için bayt-güvenli okuyucu (Windows VM'de geçersiz UTF-8'e dayanıklı).
.sht_read_bytes <- function(path) {
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8", sub = "byte")
}

# -----------------------------------------------------------------------------
# Yapısal ayrım sözleşmesi
# -----------------------------------------------------------------------------

test_that("handle_streaming_tts_mode yeni handler dosyasında tanımlıdır", {
  expect_true(file.exists(.sht_handler_path))

  handler_env <- new.env(parent = globalenv())
  source(.sht_handler_path, encoding = "UTF-8", local = handler_env)

  expect_true(exists("handle_streaming_tts_mode", envir = handler_env, inherits = FALSE))
  expect_true(is.function(get("handle_streaming_tts_mode", envir = handler_env, inherits = FALSE)))
})

test_that("send_message satır içi TTS streaming promise zincirini handler'a devreder", {
  send_text <- .sht_read_bytes(.sht_send_path)

  # Handler çağrısı send_message içinde olmalı.
  expect_true(grepl("handle_streaming_tts_mode(streaming_tts_ctx)", send_text, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("streaming_tts_ctx <- list(", send_text, fixed = TRUE, useBytes = TRUE))

  # Satır içi promise zinciri / LLM streaming çağrısı send_message'ta KALMAMALI;
  # gerçek SSE ve non-streaming dalları gibi handler'a taşındı.
  expect_false(grepl("ai_processor$call_llm_streaming", send_text, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("simulate_streaming_stoppable_fn(", send_text, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl("LLM_REQUEST_STREAMING", send_text, fixed = TRUE, useBytes = TRUE))

  # handler dosyası bu sorumluluğun yeni sahibidir.
  handler_text <- .sht_read_bytes(.sht_handler_path)
  expect_true(grepl("ai_processor$call_llm_streaming", handler_text, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("simulate_streaming_stoppable_fn(", handler_text, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("handle_streaming_tts_mode <- function(ctx)", handler_text, fixed = TRUE, useBytes = TRUE))
})

test_that("manifest handler'ı send_message'tan önce yükler (bağımlılık-önce)", {
  expect_source_manifest_contains_for_tests(c(
    "R/server_handler_streaming_tts.R",
    "R/server_send_message.R"
  ))
  expect_source_manifest_order_for_tests(c(
    "R/server_handler_streaming_tts.R",
    "R/server_send_message.R"
  ))
})

# -----------------------------------------------------------------------------
# Promise zinciri davranışı (deterministik, gerçek LLM/Shiny olmadan)
# -----------------------------------------------------------------------------

# Handler'ı kontrol edilebilir stub'larla yükleyen yardımcı. mergen_send_message
# _request_state çağrısı holder$value döndürerek dal seçimi deterministik tutulur.
.sht_make_handler_env <- function(request_state = "current", recorder = NULL) {
  env <- new.env(parent = globalenv())

  # Handler gövdesinin ihtiyaç duyduğu global'lerin no-op stub'ları.
  env[["%||%"]] <- function(a, b) if (is.null(a)) b else a
  env[["%...!%"]] <- promises::`%...!%`
  env$log_debug <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$dbg_dump <- function(...) invisible(NULL)
  env$mergen_log_llm_request_debug <- function(...) invisible(NULL)
  env$mb_api_key_invalidate_send_cache_on_auth_error <- function(...) invisible(FALSE)
  env$log_ai_usage <- function(...) invisible(NULL)
  env$build_followup_suggestions <- function(...) list("Takip sorusu 1")
  env$normalize_character_id <- function(x) "emre"
  env$get_characters_data <- function() NULL
  # Kilitli referans modunda çözümlenen ses persona kimliğinin kendisidir;
  # mod çözümleyicisi gerçek adaptör dosyasından gelir (tek kaynak).
  env$mergen_speech_voice_mode <- function() "locked_reference"
  # Dal kararını doğrudan kontrol et (gerçek helper'ın kendi testi vardır).
  env$mergen_send_message_request_state <- function(active_request_id, req_id, stop_generation) request_state

  source(.sht_handler_path, encoding = "UTF-8", local = env)
  env
}

# later kuyruğunu sınırlı biçimde boşaltır (koşul sağlanana ya da sınıra dek).
.sht_drain_later <- function(done_fn, max_iter = 200L) {
  for (i in seq_len(max_iter)) {
    later::run_now(timeoutSecs = 0)
    if (isTRUE(done_fn())) break
    Sys.sleep(0.005)
  }
}

# Çağrıları kaydeden ortak yarış-koruması/iletişim stub'ları üretir.
.sht_make_ctx <- function(env, res = NULL, reject_with = NULL, enable_tts = FALSE, recorder) {
  ai_processor <- list(
    call_llm_streaming = function(messages, settings, model) {
      if (!is.null(reject_with)) {
        return(promises::promise_reject(reject_with))
      }
      promises::promise_resolve(res)
    }
  )

  list(
    session = new.env(),
    values = local({ v <- new.env(); v$is_sending <- FALSE; v }),
    settings_data = list(enable_tts_audio = enable_tts),
    stop_generation = function(...) FALSE,
    active_request_id = function(...) "req-1",
    perf_tracker = list(
      track_request = function(d) recorder$track_request <- TRUE,
      track_error = function() recorder$track_error <- TRUE
    ),
    api_config = list(),
    ai_processor = ai_processor,
    tts_processor = list(synthesize_speech = function(...) NULL),
    followup_tools = NULL,
    fallback_followup_tool = NULL,
    simulate_streaming_stoppable_fn = function(content, followups = NULL, ...) {
      recorder$simulate_called <- TRUE
      recorder$simulate_content <- content
      recorder$simulate_followups <- followups
    },
    cleanup_send_message = function(...) recorder$cleanup_called <- TRUE,
    abort_send_message = function(message = NULL, type = "warning", ...) {
      recorder$abort_called <- TRUE
      recorder$abort_message <- message
    },
    current_settings = list(selected_character = "emre"),
    model_selected = "test-model",
    messages_to_process = list(),
    user_message_text = "Merhaba",
    user_prompt_msg = list(id = "m1", db_id = 1L),
    chat_id_val = 10L,
    current_user_id = 7L,
    request_id = "req-1"
  )
}

test_that("başarılı yanıt simulate_streaming_stoppable_fn'i içerik+takip ile çağırır", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  recorder <- new.env()
  env <- .sht_make_handler_env(request_state = "current")
  ctx <- .sht_make_ctx(
    env,
    res = list(success = TRUE, content = "AI cevabı", duration = 1.2, error = NULL, chart_store = NULL),
    enable_tts = TRUE,
    recorder = recorder
  )

  get("handle_streaming_tts_mode", envir = env)(ctx)
  .sht_drain_later(function() isTRUE(recorder$simulate_called))

  expect_true(isTRUE(recorder$simulate_called))
  expect_identical(recorder$simulate_content, "AI cevabı")
  expect_identical(recorder$simulate_followups, list("Takip sorusu 1"))
  expect_true(isTRUE(recorder$track_request))
  expect_null(recorder$abort_called)
})

test_that("başarısız yanıt (success=FALSE) abort_send_message tetikler, simulate çağırmaz", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  recorder <- new.env()
  env <- .sht_make_handler_env(request_state = "current")
  ctx <- .sht_make_ctx(
    env,
    res = list(success = FALSE, content = NULL, duration = 0.5, error = "Sunucu hatası", chart_store = NULL),
    recorder = recorder
  )

  get("handle_streaming_tts_mode", envir = env)(ctx)
  .sht_drain_later(function() isTRUE(recorder$abort_called))

  expect_true(isTRUE(recorder$abort_called))
  expect_identical(recorder$abort_message, "Sunucu hatası")
  expect_true(isTRUE(recorder$track_error))
  expect_null(recorder$simulate_called)
})

test_that("durdurulmuş istek cleanup_send_message çağırır, simulate/abort çağırmaz", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  recorder <- new.env()
  env <- .sht_make_handler_env(request_state = "stopped")
  ctx <- .sht_make_ctx(
    env,
    res = list(success = TRUE, content = "AI cevabı", duration = 1.0, error = NULL, chart_store = NULL),
    recorder = recorder
  )

  get("handle_streaming_tts_mode", envir = env)(ctx)
  .sht_drain_later(function() isTRUE(recorder$cleanup_called))

  expect_true(isTRUE(recorder$cleanup_called))
  expect_null(recorder$simulate_called)
  expect_null(recorder$abort_called)
})

test_that("reddedilen promise current durumda abort_send_message tetikler (önek soyulur)", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  recorder <- new.env()
  env <- .sht_make_handler_env(request_state = "current")
  ctx <- .sht_make_ctx(
    env,
    reject_with = simpleError("API_ERROR: bağlantı koptu"),
    recorder = recorder
  )

  get("handle_streaming_tts_mode", envir = env)(ctx)
  .sht_drain_later(function() isTRUE(recorder$abort_called))

  expect_true(isTRUE(recorder$abort_called))
  # "API_ERROR: " öneki soyulmalı.
  expect_identical(recorder$abort_message, "bağlantı koptu")
  expect_null(recorder$simulate_called)
})
