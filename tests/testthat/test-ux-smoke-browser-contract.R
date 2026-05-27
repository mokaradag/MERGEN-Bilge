# ==============================================================================
# Dosya Yolu: tests/testthat/test-ux-smoke-browser-contract.R
# Açıklama: www/smoke/ux-smoke.html manuel browser smoke kapsamını korur.
# ==============================================================================

.ux_smoke_browser_read_text <- function(...) {
  full_path <- file.path(resolve_repo_root_for_tests(), ...)

  if (!file.exists(full_path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", full_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("UX smoke keeps media lifecycle and saved-chat TTS probes", {
  repo_root <- resolve_repo_root_for_tests()
  smoke_path <- file.path(repo_root, "www", "smoke", "ux-smoke.html")
  smoke_probe_path <- file.path(repo_root, "www", "smoke", "ux-smoke-probes.js")

  expect_true(file.exists(smoke_path))
  expect_true(file.exists(smoke_probe_path))

  smoke <- paste(
    c(
      .ux_smoke_browser_read_text("www", "smoke", "ux-smoke.html"),
      .ux_smoke_browser_read_text("www", "smoke", "ux-smoke-probes.js")
    ),
    collapse = "\n"
  )

  required_tokens <- c(
    "UX_SMOKE_DONE:PASS",
    "ux-smoke-probes.js",
    "testMediaAndSavedChat",
    "testNavigationAndFileManagerSmoke",
    "MergenUxSmokeProbes",
    "runNavigationAndFileManagerSmoke",
    "MusicManager global API var",
    "TTS global API var",
    "STT global API var",
    "Audio lifecycle smoke API var",

    # TTS/medya duck testi: Windows native encoding sözleşmeyi bozamaması için
    # Türkçe assertion metni yerine ASCII yapısal dayanaklar kullanılır.
    "ttsAudio.dispatchEvent(new win.Event(\"play\"",
    "win.MusicManager.state.isDucked === true",
    "win.MergenAudioLifecycle.activeDuckOwners()",
    "win.MergenAudioLifecycle.releaseAll(\"ux-smoke-start\")",
    "tek background music source aktif kalır",

    # Çakışan owner testi: STT duck sahibi iken TTS release işlemi sesi geri yüklememelidir.
    "win.MusicManager.duck(\"tts\")",
    "win.MusicManager.duckForSTT();",
    "owners.indexOf(\"tts\") >= 0",
    "owners.indexOf(\"stt\") >= 0",
    "win.MusicManager.unduck(\"tts\")",
    "activeDuckOwners().length === 0",

    # STT temizleme/geri yükleme testi.
    "win.MusicManager.unduckAfterSTT();",
    "win.MusicManager.state._sttActive === false",
    "win.MusicManager.state.isDucked === false",

    # Streaming yaşam döngüsü ve finalize testi.
    "testStreamingLifecycle",
    "MergenStreamingSmoke",
    "win.MergenStreamingSmoke.init",
    "win.MergenStreamingSmoke.delta",
    "win.MergenStreamingSmoke.finalize",
    "requestId: \"req-stream-1\"",
    "requestId: \"req-stream-old\"",
    "streaming delta görünür içeriğe işlendi",
    "stale requestId delta yoksayılır",
    "followup_container_ux_stream_ai",
    "class='followup-container pending'",
    "stream finalize dataset temizler",
    "stream finalize state finalized yapar",
    "stream finalize follow-up pending state temizlenir",
    "stream action butonları geri açılır",
    "stream finalize duplicate mesaj üretmez",

    # Streaming HTML güvenliği testi: tehlikeli HTML benzeri içerik etkisiz metin olarak kalmalıdır.
    "rawScriptPayload",
    "rawImgPayload",
    "jsProtocolPrefix",
    "jsProtocolSuffix",
    "streaming markdown başlık üretir",
    "streaming markdown kalın metin üretir",
    "streaming markdown madde listesi üretir",
    "streaming markdown inline code üretir",
    "streaming markdown eksik kod bloğunu güvenli wrapper ile gösterir",
    "streaming markdown script elementi üretmez",
    "streaming markdown img elementi üretmez",
    "streaming markdown a elementi üretmez",
    "streaming markdown tehlikeli HTML çalıştırmaz",
    "&lt;script&gt;alert(1)&lt;/script&gt;",
    "javascript:alert(1)",
    "streaming markdown javascript: metnini yalnızca metin olarak tutar",

    # Kayıtlı sohbet tarihsel TTS otomatik oynatmama testi.
    "load_chat_from_storage",
    "historicalMessages",
    "win.mergenTTS.queue.length === 0",
    "win.mergenTTS.isPlaying !== true",
    "!win.mergenTTS.currentAudio",
    "kayıtlı sohbet yüklenince tarihsel TTS autoplay başlamaz",

    # Navigasyon / video yaşam döngüsü / Dosya Yönetimi görünen ad testi.
    "Navigation/File Manager smoke probe tamamlandı",
    "snapshotTransientState",
    "snapshotToolState",
    "WelcomeVideoPlayer smoke state API var",
    "Bilge Yolaç sekme linki tıklanabilir",
    "Bilge Yolaç geçişinde doğru tool paneli aktif görünür",
    "Bilge Yolaç geçişinde tek background music source kalır",
    "Bilge Yolaç geçişinde stale audio duck owner kalmaz",
    "Bilge Yolaç geçişinde stale TTS audio kalmaz",
    "Ana Söyleşi sekme linki tıklanabilir",
    "Ana Söyleşi dönüşü welcome video gereksiz destroy etmez",
    "Ana Söyleşi dönüşü welcome video gereksiz reinit etmez",
    "Ana Söyleşi dönüşü chat paneli aktif kalır",
    "Ana Söyleşi dönüşü stale Bilge Yolaç tool paneli aktif kalmaz",
    "Ana Söyleşi dönüşü URL hash stale Bilge Yolaç state taşımaz",
    "Ana Söyleşi dönüşü stale tool modal/backdrop kalmaz",
    "Ana Söyleşi dönüşü tek background music source kalır",
    "Ana Söyleşi dönüşü stale audio duck owner kalmaz",
    "File Manager synthetic listing Türkçe adı okunur tutar",
    "File Manager synthetic listing mojibake üretmez",
    "File Manager attach data-filename görünen Türkçe adı kullanır",
    "File Manager synthetic refresh sonrası Türkçe adı korur",
    "Türkçe_çalışma_özeti_İstanbul.pdf"
  )

  missing <- required_tokens[!vapply(
    required_tokens,
    function(token) grepl(token, smoke, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing,
    character(0),
    info = paste("UX smoke kapsamı eksik:", paste(missing, collapse = ", "))
  )
})