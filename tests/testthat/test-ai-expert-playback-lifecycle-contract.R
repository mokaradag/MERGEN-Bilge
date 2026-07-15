# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-playback-lifecycle-contract.R
# Açıklama: AI Uzman tarayıcı oynatma yaşam döngüsü sözleşmesi (statik).
#           www/js/ai_expert_manager.js içindeki yapısal güvenceleri doğrular:
#             - ses HATA != BİTTİ (error, başarılı-bitiş yolunu doğrudan çağırmaz)
#             - sınırlı oynatma yeniden denemesi (maxPlaybackRetries)
#             - token-korumalı ended/error/timer geri çağrımları (eskime)
#             - başarısız parça için altyazı-yalnız geri dönüş (dizi durmaz)
#             - ses erken bitince altyazı KESİLMEZ (_completeCurrentSubtitle)
#             - handler temizliği (removeEventListener)
#             - konuşma-bitti sinyali tek sefer (yinelenme koruması)
#             - loadedmetadata ile gerçek süre (sentez gecikmesi değil)
#             - istemci tarafında kesin parça sırası
#           Uygulamayı başlatmaz; tarayıcı/DB/LLM/ağ GEREKMEZ. Windows VM'de
#           geçersiz UTF-8'e dayanıklı bayt-güvenli okuyucu kullanır.
# ==============================================================================

.aem_read_text <- function(...) {
  path <- file.path(resolve_repo_root_for_tests(), ...)
  if (!file.exists(path)) stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(path, open = "rb"); on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

.aem_expect_all <- function(text, tokens, label) {
  missing <- tokens[!vapply(tokens, function(t) grepl(t, text, fixed = TRUE, useBytes = TRUE), logical(1))]
  testthat::expect_equal(missing, character(0), info = paste(label, paste(missing, collapse = ", ")))
}

.aem_pos <- function(needle, hay) regexpr(needle, hay, fixed = TRUE, useBytes = TRUE)[[1]]

test_that("AI Expert manager: HATA != BİTTİ, sınırlı yeniden deneme ve altyazı-yalnız geçiş", {
  js <- .aem_read_text("www", "js", "ai_expert_manager.js")

  # Eski birleşik "error da _onAudioEnded çağırır" davranışı KALDIRILMIŞ olmalı.
  expect_false(grepl("_onAudioEnded", js, fixed = TRUE, useBytes = TRUE))

  .aem_expect_all(
    js,
    c(
      "maxPlaybackRetries: 1",
      "chunkRetryCount",
      "var onError = function()",
      "var onEnded = function()",
      "audio.error && audio.error.code",       # media error code loglanır
      "self._attachAudio(src, token, chunkIndex, false)",  # yeniden deneme (bir kez)
      "self._advanceAfterChunk(token, 'error')",           # deneme tükenince altyazı-yalnız geç
      "self._advanceAfterChunk(token, 'ended')"            # normal bitiş ayrı
    ),
    "AI Expert error/retry sözleşmesi eksik:"
  )

  # onError içinde: önce yeniden deneme dalı, SONRA fallback advance gelmeli
  # (yani hata doğrudan başarılı-bitiş yolu değildir).
  err_pos    <- .aem_pos("var onError = function()", js)
  retry_pos  <- .aem_pos("self._attachAudio(src, token, chunkIndex, false)", js)
  errfall_pos<- .aem_pos("self._advanceAfterChunk(token, 'error')", js)
  expect_true(err_pos > 0L && retry_pos > err_pos && errfall_pos > retry_pos)
})

test_that("AI Expert manager: token-korumalı eskime güvenceleri", {
  js <- .aem_read_text("www", "js", "ai_expert_manager.js")

  # ended/error/loadedmetadata/autoplay ve advance geri çağrımları speechToken korur.
  guard <- "token !== self.state.speechToken"
  n_guard <- length(gregexpr(guard, js, fixed = TRUE, useBytes = TRUE)[[1]])
  expect_true(n_guard >= 4L)   # onMeta, onEnded, onError, autoplay-catch (+timer)

  .aem_expect_all(
    js,
    c(
      "_advanceAfterChunk: function(token, reason)",
      "if (token !== this.state.speechToken) return;",   # advance eskime koruması
      "token !== self.state.speechToken) return;"        # wait/subtitle-only timer koruması
    ),
    "AI Expert token eskime sözleşmesi eksik:"
  )

  # Durdurma konuşma belirtecini ilerletir (uçuştaki eski geri çağrımlar geçersizleşir).
  .aem_expect_all(js, c("this.state.speechToken += 1;"), "Durdurma token artışı eksik:")
})

test_that("AI Expert manager: altyazı erken kesilmez ve handler temizliği yapılır", {
  js <- .aem_read_text("www", "js", "ai_expert_manager.js")

  .aem_expect_all(
    js,
    c(
      "_completeCurrentSubtitle: function()",
      "this._completeCurrentSubtitle();",          # advance içinde çağrılır
      "_cleanupAudioElement: function(audio)",
      "audio.removeEventListener('ended', h.ended)",
      "audio.removeEventListener('error', h.error)",
      "audio.removeEventListener('loadedmetadata', h.meta)",
      "_clearAllTimers: function()",
      "chunkAdvanceTimer"
    ),
    "AI Expert altyazı-tamamlama / temizlik sözleşmesi eksik:"
  )

  # advance: önce mevcut altyazıyı tamamla, SONRA sıradaki parçaya geç.
  adv_pos      <- .aem_pos("_advanceAfterChunk: function(token, reason)", js)
  complete_pos <- .aem_pos("this._completeCurrentSubtitle();", js)
  next_pos     <- .aem_pos("if (this._tryPlayNextQueuedChunk())", js)
  expect_true(adv_pos > 0L && complete_pos > adv_pos && next_pos > complete_pos)
})

test_that("AI Expert manager: konuşma-bitti tek sefer, loadedmetadata ve sıralı oynatma", {
  js <- .aem_read_text("www", "js", "ai_expert_manager.js")

  .aem_expect_all(
    js,
    c(
      "_emitSpeechEnded: function(overridePrefix)",
      "if (this.state.endedEmitted) return;",       # yinelenme koruması
      "this.state.endedEmitted = true;",
      "loadedmetadata",                              # gerçek medya süresi
      "self.state.currentAudioDuration = audio.duration",
      # Sessiz (altyazı-yalnız) parça yolu:
      "hasAudio === false",
      "_scheduleSubtitleOnlyAdvance: function(token)",
      # İstemci sırası: yalnızca beklenen indeks oynatılır.
      "return item.index === expectedIndex;",
      # Kuyruk öğesi index + hasAudio + token taşır ve eski server speechSeq'i reddeder:
      "hasAudio: hasAudio",
      "token: this.state.speechToken",
      "this.state.serverSpeechSeq !== null",
      "data.speechSeq === undefined || data.speechSeq === null",
      "Number(data.speechSeq) !== Number(this.state.serverSpeechSeq)",
      "Eski/eksik speechSeq parçası yok sayıldı",
      "Eski/eksik speechSeq fallback yok sayıldı"
    ),
    "AI Expert emit/metadata/sıralama sözleşmesi eksik:"
  )

  # _hideSubtitle ve stopSubtitle ham Shiny.setInputValue yerine _emitSpeechEnded kullanır.
  hide_pos  <- .aem_pos("_hideSubtitle: function()", js)
  stop_pos  <- .aem_pos("stopSubtitle: function(data)", js)
  emit_calls <- gregexpr("this._emitSpeechEnded(", js, fixed = TRUE, useBytes = TRUE)[[1]]
  expect_true(length(emit_calls[emit_calls > 0L]) >= 2L)
  expect_true(hide_pos > 0L && stop_pos > 0L)
})

test_that("AI Expert sunucu (R): eager konuşma dizisi + speech_seq eskime belirteci kullanır", {
  r_js <- .aem_read_text("R", "module_ai_expert.R")
  helper <- .aem_read_text("R", "helpers_ai_expert_speech.R")

  .aem_expect_all(
    r_js,
    c(
      "speech_seq      <- reactiveVal(0L)",
      "mergen_ai_expert_new_speech_sequence(",
      "identical(isolate(speech_seq()), seq_id)",   # eskime-korumalı is_active
      "speech_sequence$start()",
      "speech_seq(isolate(speech_seq()) + 1L)"       # stop/ended token artışı
    ),
    "module_ai_expert.R eager dizi / token sözleşmesi eksik:"
  )

  # Helper: JS indeks eşlemesi (idx-1) ve hasAudio bayrağı; sınırlı yeniden deneme.
  .aem_expect_all(
    helper,
    c(
      "mergen_ai_expert_new_speech_sequence <- function",
      "index = idx - 1L",
      "hasAudio = has_audio",
      "aiExpertStartWithAudio",
      "aiExpertQueueAudioChunk",
      "aiExpertStartSubtitle",
      "synth_with_retry",
      "max_retries"
    ),
    "helpers_ai_expert_speech.R sözleşmesi eksik:"
  )
})
