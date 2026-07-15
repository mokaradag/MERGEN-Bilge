# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-speech-sequence-behavior.R
# Açıklama: AI Uzman parçalı TTS konuşma dizisi orkestratörünün davranış testleri
#           (R/helpers_ai_expert_speech.R). Gerçek TTS/LLM/Shiny/tarayıcı GEREKMEZ:
#           enjekte edilen sahte promise'ler ve kayıt eden send_message ile
#           deterministik doğrulanır. Kapsam:
#             - 2..N parçaları 1. parça çözülmeden ÖNCE eager sentezlenir
#             - oynatma sırası sentez sırası ne olursa olsun KESİN parça sırası
#             - her parça en fazla BİR kez sentez kuyruğuna verilir (at-most-once)
#             - durdurulmuş/değiştirilmiş dizi geç sonuçları YOK SAYAR (eskime)
#             - bir sonraki parça başarısız olsa da dizi durmaz (altyazı-yalnız)
#             - 1. parça başarısız -> tüm-metin altyazı geri dönüşü
# ==============================================================================

if (!requireNamespace("promises", quietly = TRUE) || !requireNamespace("later", quietly = TRUE)) {
  testthat::skip("promises/later gerekli")
}

source(file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert_speech.R"),
       encoding = "UTF-8", local = TRUE)

# later kuyruğunu koşul sağlanana ya da sınıra dek boşaltır.
.seq_drain <- function(pred = function() FALSE, max_iter = 300L) {
  for (i in seq_len(max_iter)) {
    later::run_now(timeoutSecs = 0)
    if (isTRUE(tryCatch(pred(), error = function(e) FALSE))) break
    Sys.sleep(0.002)
  }
}

# Elle çözülebilen (deferred) promise üretir.
.seq_deferred <- function() {
  env <- new.env(parent = emptyenv())
  p <- promises::promise(function(resolve, reject) {
    env$resolve <- resolve
    env$reject <- reject
  })
  list(promise = p,
       resolve = function(v) env$resolve(v),
       reject = function(e) env$reject(e))
}

.seq_ok <- function(dur = 1) {
  list(success = TRUE, audio_src = sprintf("data:audio/wav;base64,AAA%s", dur),
       duration = dur, media_duration = dur)
}
.seq_fail <- function(retryable = TRUE) {
  list(success = FALSE, audio_src = NULL, retryable = retryable, duration = 0)
}

.seq_meta <- function(total_text = "Tam metin.") {
  list(ns_prefix = "ns-", avatar_src = "a", accent_color = "#000",
       font_size = "medium", full_text = total_text)
}

test_that("2..N parçaları 1. parça çözülmeden önce eager sentezlenir", {
  calls <- character(0)
  defs <- list()
  priorities <- logical(0)
  indexes <- integer(0)
  synth <- function(text, startup_priority = FALSE, chunk_index = NULL) {
    calls[[length(calls) + 1L]] <<- text
    priorities[[length(priorities) + 1L]] <<- startup_priority
    indexes[[length(indexes) + 1L]] <<- chunk_index
    d <- .seq_deferred(); defs[[text]] <<- d; d$promise
  }
  sent <- list()
  send <- function(type, data) sent[[length(sent) + 1L]] <<- list(type = type, index = data$index)

  seq <- mergen_ai_expert_new_speech_sequence(
    chunks = list("Bir.", "Iki.", "Uc."),
    synthesize = synth, send_message = send, is_active = function() TRUE,
    meta = .seq_meta()
  )
  seq$start()

  # start() döner dönmez 3 sentez isteği yapılmış olmalı (henüz hiçbiri çözülmedi).
  expect_identical(length(calls), 3L)
  expect_setequal(calls, c("Bir.", "Iki.", "Uc."))
  expect_identical(priorities, c(TRUE, FALSE, FALSE))
  expect_identical(indexes, 1:3)
  expect_identical(length(sent), 0L)   # hiçbir şey gönderilmedi (1. parça çözülmedi)
})

test_that("oynatma sırası sentez sırası ne olursa olsun kesin parça sırasıdır", {
  defs <- list()
  synth <- function(text, startup_priority = FALSE, chunk_index = NULL) { d <- .seq_deferred(); defs[[text]] <<- d; d$promise }
  sent <- list()
  send <- function(type, data) sent[[length(sent) + 1L]] <<- list(type = type, index = data$index %||% NA)

  seq <- mergen_ai_expert_new_speech_sequence(
    chunks = list("Bir.", "Iki.", "Uc."),
    synthesize = synth, send_message = send, is_active = function() TRUE,
    meta = .seq_meta()
  )
  seq$start()

  # Ters sırada çöz: 3, 2, sonra 1.
  defs[["Uc."]]$resolve(.seq_ok(3)); .seq_drain(max_iter = 6)
  defs[["Iki."]]$resolve(.seq_ok(2)); .seq_drain(max_iter = 6)
  expect_identical(length(sent), 0L)   # 1. parça hâlâ çözülmedi -> hiçbir şey gönderilmez

  defs[["Bir."]]$resolve(.seq_ok(1))
  .seq_drain(function() length(sent) >= 3L)

  types <- vapply(sent, function(s) s$type, character(1))
  expect_identical(types[1], "aiExpertStartWithAudio")
  queue_idx <- vapply(sent[types == "aiExpertQueueAudioChunk"], function(s) s$index, numeric(1))
  expect_identical(queue_idx, c(1, 2))   # JS indeksleri: 2. parça=1, 3. parça=2 (sıralı)
})

test_that("her parça en fazla bir kez sentez kuyruğuna verilir", {
  calls <- character(0)
  synth <- function(text, startup_priority = FALSE, chunk_index = NULL) { calls[[length(calls) + 1L]] <<- text; promises::promise_resolve(.seq_ok(1)) }
  send <- function(type, data) invisible(NULL)

  seq <- mergen_ai_expert_new_speech_sequence(
    chunks = list("A.", "B.", "C."),
    synthesize = synth, send_message = send, is_active = function() TRUE,
    meta = .seq_meta()
  )
  seq$start()
  .seq_drain(max_iter = 20)
  snap <- seq$snapshot()
  expect_true(all(snap$submitted))
  expect_identical(length(calls), 3L)   # tam olarak 3 sentez (yineleme yok)
})

test_that("durdurulmuş dizi geç promise çözümlerini yok sayar", {
  defs <- list()
  synth <- function(text, startup_priority = FALSE, chunk_index = NULL) { d <- .seq_deferred(); defs[[text]] <<- d; d$promise }
  sent <- list()
  send <- function(type, data) sent[[length(sent) + 1L]] <<- type
  stopped <- FALSE

  seq <- mergen_ai_expert_new_speech_sequence(
    chunks = list("A.", "B."),
    synthesize = synth, send_message = send, is_active = function() !stopped,
    meta = .seq_meta()
  )
  seq$start()
  stopped <- TRUE   # kullanıcı durdurdu / dizi değiştirildi
  defs[["A."]]$resolve(.seq_ok(1)); defs[["B."]]$resolve(.seq_ok(1))
  .seq_drain(max_iter = 30)
  expect_identical(length(sent), 0L)   # durdurulan diziden hiçbir şey oynatılmaz
})

test_that("yeni dizi önceki diziye (token) ait geri çağrımları yok sayar", {
  # is_active bir dizi belirtecine bağlanır. Yeni bir konuşma başlayınca eski
  # dizinin is_active'i FALSE olur; eski promise'lerin geç çözümleri oynatılmaz.
  defs <- list()
  synth <- function(text, startup_priority = FALSE, chunk_index = NULL) { d <- .seq_deferred(); defs[[text]] <<- d; d$promise }
  old_sent <- list()
  active_token <- 1L
  seq_id <- 1L   # eski dizinin belirteci

  seq_old <- mergen_ai_expert_new_speech_sequence(
    chunks = list("Bir.", "Iki."),
    synthesize = synth,
    send_message = function(type, data) old_sent[[length(old_sent) + 1L]] <<- type,
    is_active = function() identical(active_token, seq_id),
    meta = .seq_meta()
  )
  seq_old$start()

  # Yeni konuşma başladı -> aktif belirteç değişti (eski dizi artık güncel değil).
  active_token <- 2L

  # Eski dizinin promise'leri geç çözülür -> hiçbir şey oynatılmamalı.
  defs[["Bir."]]$resolve(.seq_ok(1)); defs[["Iki."]]$resolve(.seq_ok(1))
  .seq_drain(max_iter = 30)
  expect_identical(length(old_sent), 0L)
})

test_that("sonraki parça başarısız olsa da dizi durmaz (altyazı-yalnız geçiş)", {
  # 2. parça iki denemede de başarısız (retryable), 1 ve 3 başarılı.
  attempts2 <- 0L
  synth <- function(text, startup_priority = FALSE, chunk_index = NULL) {
    if (identical(text, "Iki.")) { attempts2 <<- attempts2 + 1L; return(promises::promise_resolve(.seq_fail())) }
    promises::promise_resolve(.seq_ok(1))
  }
  sent <- list()
  send <- function(type, data) sent[[length(sent) + 1L]] <<- list(
    type = type, index = data$index %||% NA, hasAudio = isTRUE(data$hasAudio))

  seq <- mergen_ai_expert_new_speech_sequence(
    chunks = list("Bir.", "Iki.", "Uc."),
    synthesize = synth, send_message = send, is_active = function() TRUE,
    meta = .seq_meta(), max_retries = 1L
  )
  seq$start()
  .seq_drain(function() length(sent) >= 3L)

  expect_identical(attempts2, 2L)   # sınırlı yeniden deneme: bir kez tekrar denendi
  types <- vapply(sent, function(s) s$type, character(1))
  expect_identical(types[1], "aiExpertStartWithAudio")
  q <- sent[types == "aiExpertQueueAudioChunk"]
  # 2. parça altyazı-yalnız (hasAudio=FALSE), 3. parça sesli (hasAudio=TRUE); ikisi de sırayla.
  expect_identical(vapply(q, function(s) s$index, numeric(1)), c(1, 2))
  expect_identical(vapply(q, function(s) s$hasAudio, logical(1)), c(FALSE, TRUE))
})

test_that("1. parça başarısız -> tüm-metin altyazı geri dönüşü", {
  synth <- function(text, startup_priority = FALSE, chunk_index = NULL) {
    if (identical(text, "Bir.")) return(promises::promise_resolve(.seq_fail()))
    promises::promise_resolve(.seq_ok(1))
  }
  sent <- list()
  send <- function(type, data) sent[[length(sent) + 1L]] <<- type

  seq <- mergen_ai_expert_new_speech_sequence(
    chunks = list("Bir.", "Iki."),
    synthesize = synth, send_message = send, is_active = function() TRUE,
    meta = .seq_meta("Bir. Iki."), max_retries = 1L
  )
  seq$start()
  .seq_drain(function() length(sent) >= 1L)

  expect_true("aiExpertStartSubtitle" %in% unlist(sent))
  expect_false("aiExpertStartWithAudio" %in% unlist(sent))   # ses başlatılmaz
  snap <- seq$snapshot()
  expect_true(snap$fallback_mode)
})

test_that("ön ısıtma (first_chunk_promise) 1. parça için kullanılır, 2. parça yine eager sentezlenir", {
  calls <- character(0)
  synth <- function(text, startup_priority = FALSE, chunk_index = NULL) { calls[[length(calls) + 1L]] <<- text; promises::promise_resolve(.seq_ok(1)) }
  sent <- list()
  send <- function(type, data) sent[[length(sent) + 1L]] <<- list(type = type, index = data$index %||% NA)

  prewarm <- promises::promise_resolve(.seq_ok(9))
  seq <- mergen_ai_expert_new_speech_sequence(
    chunks = list("Bir.", "Iki."),
    synthesize = synth, send_message = send, is_active = function() TRUE,
    meta = .seq_meta(), first_chunk_promise = prewarm
  )
  seq$start()
  .seq_drain(function() length(sent) >= 2L)

  # 1. parça ön ısıtmadan geldi -> synth yalnızca 2. parça için çağrıldı.
  expect_identical(calls, "Iki.")
  types <- vapply(sent, function(s) s$type, character(1))
  expect_identical(types[1], "aiExpertStartWithAudio")
})
