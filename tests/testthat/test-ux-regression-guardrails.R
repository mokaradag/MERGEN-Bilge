# ==============================================================================
# Dosya Yolu: tests/testthat/test-ux-regression-guardrails.R
# Açıklama: Welcome, hızlı işlemler, TTS/STT/müzik ve reasoning UX davranışlarının
#           refactor sırasında sessizce gerilemesini engelleyen hafif sözleşme testleri.
# ==============================================================================

.find_ux_guard_repo_root <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("UX guard test repo kökünü bulamadı. Testi repo kökünden çalıştırın.", call. = FALSE)
}

.ux_guard_repo_root <- .find_ux_guard_repo_root()

.ux_guard_read_text <- function(path) {
  full_path <- file.path(.ux_guard_repo_root, path)

  if (!file.exists(full_path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", full_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    # BOŞ DOSYA SESSİZCE GEÇMEZ: `""` döndürmek, aşağıdaki tüm NEGATİF
    # iddiaları (`expect_false(grepl(...))`) anlamsız biçimde geçirir ve
    # muhafızın kendisi kaybolmuşken süit başarı raporlar.
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", full_path), call. = FALSE)
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  # `sub` VERİLMEZ (PR #705 incelemesi, P3).
  #
  # `iconv()` bir ögeyi ancak `sub` VARSAYILAN (`NA`) iken çözemediğinde `NA`
  # döndürür. `sub = "byte"` her geçersiz baytı `<ff>` kaçışına çevirip HER
  # ZAMAN bir dize üretir; aşağıdaki `is.na(txt)` kapısı bu yüzden HİÇ
  # tetiklenmiyordu. CP1254 gibi UTF-8 OLMAYAN bir kodlamayla kaydedilmiş
  # kaynak dosya, kaçışlarla dolu bozuk bir metne dönüşüyor ve yalnız olumsuz
  # iddia taşıyan taramalar o dosya için de "geçiyordu".
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8")[[1]]
  )

  # ÇÖZÜMLEME BAŞARISIZLIĞI BOŞ METNE ÇEVRİLMEZ: yalnız olumsuz iddia taşıyan
  # bir koruma (ör. görselleştirici taraması) okunamayan kaynak dosya için de
  # geçerdi.
  if (is.na(txt)) {
    stop(sprintf("Kaynak dosya UTF-8 olarak çözülemedi: %s", full_path), call. = FALSE)
  }
  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)

  # YALNIZ BOŞLUK İÇEREN DOSYA DA REDDEDİLİR: `size > 0` olduğu için yukarıdaki
  # boş-dosya kapısını geçen, ama içeriği tamamen silinmiş (yalnız satır sonu /
  # boşluk kalan) bir kaynak, bu dosyadaki OLUMSUZ taramaların hepsini geçirir
  # ve muhafız edilen bileşen TAMAMEN kaybolmuşken süit başarı raporlardı.
  if (!nzchar(trimws(txt))) {
    stop(sprintf("Kaynak dosya YALNIZCA boşluk içeriyor: %s", full_path),
         call. = FALSE)
  }

  enc2utf8(txt)
}

.ux_guard_has_text <- function(text, needle) {
  # `useBytes = TRUE` KULLANILMAZ: metin `enc2utf8()` ile UTF-8'dir, arama
  # dizesi ise bu TEST DOSYASININ literalidir. Windows VM'de R yereli
  # Türkçe/`WINDOWS-1254` olduğu ve testthat dosyayı UTF-8 beyanı OLMADAN
  # ayrıştırdığı için Türkçe içeren bir literal YERLİ işaretlenir; bayt
  # karşılaştırması sessizce kaçar ve muhafız VAR OLAN bir sözleşmeyi EKSİK
  # raporlardı. `.ux_guard_expect_order()` de `useBytes` geçmez; iki yardımcı
  # artık aynı karşılaştırmayı yapar.
  isTRUE(suppressWarnings(grepl(
    enc2utf8(needle),
    text,
    fixed = TRUE
  )))
}

# SIRA MUHAFIZI: yalnızca "her iki dize de dosyada var" demek, bir düzenleme
# ikisinin SIRASINI değiştirdiğinde muhafızın kör kalmasına yol açar. Bu
# yardımcı, verilen dizelerin kaynakta BEKLENEN SIRADA geçmesini doğrular.
# Karakter uzaklığı kullanılır (bayt/karakter karışımı yoktur) ve tüm parçalar
# tek tek konumlandığı için eksik bir parça da ayırt edilebilir hata verir.
.ux_guard_expect_order <- function(text, expected, label) {
  konumlar <- vapply(expected, function(item) {
    # ARAMA DİZESİ DE UTF-8'E NORMALLEŞTİRİLİR (`.ux_guard_has_text()` ile
    # PARİTE). Windows VM'de testthat bu dosyayı UTF-8 beyanı OLMADAN
    # ayrıştırır; `WINDOWS-1254` yerelinde Türkçe karakter taşıyan bir
    # beklenti dizesi NATİF işaretlenir, `text` ise `enc2utf8()` sonrası
    # UTF-8'dir. `fixed = TRUE` karşılaştırması o zaman VAR OLAN bir dizeyi
    # bulamaz ve muhafız doğru kaynak için YANLIŞ "BULUNAMADI" raporlardı.
    p <- regexpr(enc2utf8(item), text, fixed = TRUE)[[1]]
    if (p < 0L) NA_integer_ else as.integer(p)
  }, integer(1))

  testthat::expect_true(
    all(!is.na(konumlar)),
    info = paste(label, "BULUNAMADI:",
                 paste(expected[is.na(konumlar)], collapse = ", "))
  )
  if (any(is.na(konumlar))) return(invisible(FALSE))

  testthat::expect_true(
    !is.unsorted(konumlar, strictly = TRUE),
    info = paste(label, "SIRA BOZUK:", paste(expected, collapse = " -> "))
  )
  invisible(TRUE)
}

.ux_guard_expect_all <- function(text, expected, label) {
  found <- vapply(expected, function(item) {
    .ux_guard_has_text(text, item)
  }, logical(1))

  testthat::expect_true(
    all(found),
    info = paste(label, paste(expected[!found], collapse = ", "))
  )
}

testthat::test_that("welcome UX bileşenleri ve top-gap sözleşmesi korunur", {
  welcome_css <- .ux_guard_read_text("www/css/welcome_modern.css")
  welcome_r <- .ux_guard_read_text("R/welcome_screen_modern.R")
  video_js <- .ux_guard_read_text("www/js/welcome_video_player.js")
  neural_js <- .ux_guard_read_text("www/js/welcome_neural_modern.js")
  greeting_js <- .ux_guard_read_text("www/js/welcome_greeting_personal.js")
  handlers_js <- .ux_guard_read_text("www/js/shiny_message_handlers.js")
  modern_welcome_handler_js <- .ux_guard_read_text("www/js/modern_welcome_handler.js")

  .ux_guard_expect_all(
    welcome_css,
    c(
      ".welcome-fullscreen-wrapper",
      "top: 0 !important;",
      "left: 250px !important;",
      ".sidebar-collapse .welcome-fullscreen-wrapper",
      "left: 50px !important;",
      ".modern-welcome-video",
      ".modern-welcome-neural-canvas",
      ".modern-welcome-action-btn",
      ".modern-welcome-recent-list"
    ),
    "Welcome CSS UX sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    welcome_r,
    c(
      "modern-welcome-root",
      "modern-welcome-video-container",
      "modern-welcome-neural-canvas",
      "dynamic-greeting-text",
      "createModernRecentChatsSection",
      "max_preview <- min(3, length(recent_chats))",
      "for (i in seq_len(max_preview))",
      "data-action-model",
      "data-action-id",
      "window._handleQuickAction(this); return false;"
    ),
    "Modern welcome HTML sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    modern_welcome_handler_js,
    c(
      "initModernWelcome",
      "bootModernWelcome",
      "WelcomeVideoPlayer.init(videoContainer)",
      "WelcomeNeuralNetwork.init(neuralCanvas, accentColor)",
      "WelcomeGreeting.init(greetingText)"
    ),
    "Modern welcome boot sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    video_js,
    c(
      "isInitialized && container === containerElement",
      "document.contains(containerElement)",
      "attemptPlay(0)"
    ),
    "Welcome video yeniden başlatma guard sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    neural_js,
    c(
      "width <= 0 || height <= 0",
      "window.setTimeout(resize, 80)",
      "requestAnimationFrame(animate)"
    ),
    "Welcome neural ölçüm/animasyon guard sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    greeting_js,
    c(
      "MERGEN_PERSONAL_GREETING_HANDLER_REGISTERED",
      "registerShinyHandler(attempt + 1)",
      "initPersonalGreeting",
      "startGreetingSequence(firstName)"
    ),
    "Kişisel greeting handler sözleşmesi eksik:"
  )
})

testthat::test_that("quick action model, tool, intro ve duplicate-event sözleşmesi korunur", {
  quick_r <- .ux_guard_read_text("R/module_quick_actions.R")
  handlers_js <- .ux_guard_read_text("www/js/shiny_message_handlers.js")
  modern_welcome_handler_js <- .ux_guard_read_text("www/js/modern_welcome_handler.js")

  .ux_guard_expect_all(
    handlers_js,
    c(
      "QUICK_ACTION_DEBOUNCE_MS",
      "btn.disabled || btn.getAttribute('aria-disabled') === 'true'",
      "typeof Shiny === 'undefined'",
      "Shiny.setInputValue('quick_template'",
      "action_id: actionId",
      "$('#welcome_fullscreen_container').fadeOut(300)"
    ),
    "Quick action client debounce/dispatch sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    quick_r,
    c(
      "last_quick_action_signature <- reactiveVal",
      "is_duplicate_quick_action_event <- function",
      "Yinelenen hızlı işlem olayı yoksayıldı",
      "get_tool_mode_config(action_id, by = \"quick_action_id\")",
      "show_quick_action_intro(action_id)",
      "build_quick_action_intro_message",
      "persist_to_db = FALSE",
      "include_in_context = FALSE",
      "enable_rdata_tools",
      "enable_mcp_tools",
      "enable_summarization_tools",
      "enable_coding_tools",
      "enable_process_tools",
      "enable_app_expert_tools",
      "enable_image_tools"
    ),
    "Quick action server model/tool/intro sözleşmesi eksik:"
  )
})

testthat::test_that("hızlı özetleme işlemi eski analiz kontrollerini kapatır", {
  quick_r <- .ux_guard_read_text("R/module_quick_actions.R")

  # `useBytes = TRUE` KULLANILMAZ: `regexpr()` bayt uzaklığı döndürürken
  # aşağıdaki `substr()` KARAKTER sayar. Taranan dosyada çapadan önce Türkçe
  # karakterler bulunduğu için pencere amaçlanan çapadan SONRA başlar ve test
  # ya beklenen dizeleri kaçırır ya da sessizce başka bir bölgeyi kapsar.
  summarization_start <- regexpr(
    "if (identical(template_action_id, \"summarization\"))",
    quick_r,
    fixed = TRUE
  )[[1]]

  testthat::expect_gt(summarization_start, 0L)

  summarization_branch <- substr(
    quick_r,
    summarization_start,
    min(
      nchar(quick_r, type = "chars", allowNA = FALSE),
      summarization_start + 3000L
    )
  )

  .ux_guard_expect_all(
    summarization_branch,
    c(
      "session$sendCustomMessage(\"toggleSummaryMode\", list(active = TRUE))",
      "session$sendCustomMessage(\"toggleImageMode\", list(active = FALSE))",
      "session$sendCustomMessage(\"toggleAnalysisMode\", list(active = FALSE))",
      "show_quick_action_intro(\"summarization\")"
    ),
    "Özetleme hızlı işlemi eski analiz kontrollerini kapatma sözleşmesi eksik:"
  )
})

testthat::test_that("TTS, STT ve müzik state guardrail sözleşmeleri korunur", {
  music_js <- .ux_guard_read_text("www/js/music_manager.js")
  tts_js <- .ux_guard_read_text("www/js/tts_manager.js")
  stt_js <- .ux_guard_read_text("www/js/stt_client.js")
  chat_input_r <- .ux_guard_read_text("R/server_observers_chat_input.R")
  llm_handlers_r <- .ux_guard_read_text("R/server_llm_response_handlers.R")
  messaging_r <- .ux_guard_read_text("R/helpers_messaging.R")
  module_tts_r <- .ux_guard_read_text("R/module_tts.R")
  audio_guard_js <- .ux_guard_read_text("www/js/audio_lifecycle_guard.js")
  intro_music_js <- .ux_guard_read_text("www/js/space_intro_music.js")
  cinematic_js <- .ux_guard_read_text("www/js/explore_cinematic.js")
  character_step_js <- .ux_guard_read_text("www/js/explore_character_step.js")
  visualizer_js <- .ux_guard_read_text("www/js/tts_visualizer.js")
  ai_expert_js <- .ux_guard_read_text("www/js/ai_expert_manager.js")

  .ux_guard_expect_all(
    music_js,
    c(
      "window.MusicManager",
      "_audio: null",
      "_pendingRequestId",
      "_pendingRequestType",
      "playingFileName = src.split('/').pop()",
      "decodeErr",
      "duckForSTT",
      "unduckAfterSTT",
      "duck: function(owner)",
      "unduck: function(owner)",
      "MergenAudioLifecycle.duck",
      "MergenAudioLifecycle.release"
    ),
    "MusicManager tek-audio/duck sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    tts_js,
    c(
      "window.mergenTTS",
      "queue.sort",
      "stopTTSPlayback",
      "window.mergenTTS.stop()",
      "audio.onplay = null",
      "audio.removeAttribute('src')",
      "MusicManager.duck('tts')",
      "MusicManager.unduck('tts')",
      "tts_is_playing"
    ),
    "TTS kuyruk/duck/stop sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    stt_js,
    c(
      "window.STT_Client",
      "restoreMusicAfterSTT",
      "config = config || {}",
      "if (!canvasId)",
      "canvasCtx.setTransform",
      "MusicManager.duckForSTT()",
      "MusicManager.unduckAfterSTT()",
      "bindModalHiddenCleanup",
      "hidden.bs.modal.mergenSttCleanup",
      "setSttModalInactive",
      "stopAndCleanup"
    ),
    "STT müzik pause/resume sözleşmesi eksik:"
  )
  
  play_reject_pos <- regexpr(
    "playPromise.catch(function(err)",
    ai_expert_js,
    fixed = TRUE
  )[[1]]

  testthat::expect_true(
    play_reject_pos > 0L,
    info = "AI Expert autoplay rejection branch bulunmalıdır."
  )

  play_reject_branch <- substr(
    ai_expert_js,
    play_reject_pos,
    min(nchar(ai_expert_js), play_reject_pos + 1200L)
  )

  .ux_guard_expect_all(
    play_reject_branch,
    c(
      "self._stopAudio();",
      "MusicManager.unduck('ai_expert')",
      # ÇAĞRININ KENDİSİ İSTENİR, YALNIZCA TANIMLAYICI DEĞİL: `setIdle` adı hem
      # kullanılabilirlik denetiminde (`&& window.ttsVisualizerState.setIdle`)
      # hem çağrıda geçer; çağrı SİLİNİP `if` koşulu kalsaydı muhafız geçer ve
      # otomatik oynatma reddi TTS görselleştiricisini SIFIRLAMAZDI.
      "ttsVisualizerState.setIdle()",
      "self._scheduleHide(self._estimateReadTime(self.state.currentText))"
    ),
    "AI Expert autoplay rejection cleanup sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    chat_input_r,
    c(
      "observeEvent(input$send_stop_btn",
      "stop_generation(TRUE)",
      "active_request_id(paste0(\"cancelled_\"",
      "session$sendCustomMessage(\"stopTTSPlayback\""
    ),
    "Stop butonu TTS/reasoning cleanup sözleşmesi eksik:"
  )

  # TTS DEKORE EDİLMEMİŞ METNİ ALIR.
  #
  # Bu iddia eskiden `trigger_tts_fn(ai_msg$id, result$content)` arıyordu;
  # `result$content` o satıra gelindiğinde `pk_provenance_decorate()` ile
  # köken alt bilgisi EKLENMİŞ hâldedir ve alt bilgi SESLİ OKUNUYORDU.
  # `R/helpers_chat_runtime.R` benzetimli akışta AYNI sözleşmeyi uygular.
  .ux_guard_expect_all(
    llm_handlers_r,
    c(
      "seslendirilecek_metin <- result$content",
      "trigger_tts_fn(ai_msg$id, seslendirilecek_metin)",
      "if (!is.null(ai_msg) && !isTRUE(stop_generation()))"
    ),
    "TTS yalnızca yeni AI yanıtından (DEKORE EDİLMEMİŞ metinle) tetiklenmeli sözleşmesi eksik:"
  )

  # SIRA DA SÖZLEŞMENİN PARÇASIDIR: yalnızca varlık denetlenirse, bir düzenleme
  # dekorasyonu kopyanın ÜSTÜNE taşıdığında her iki dize de yerinde kalır,
  # muhafız yeşil raporlar ve TTS köken alt bilgisini yeniden SESLİ OKUR.
  # Ham gövde ÖNCE yakalanır; `result$content` ancak sonra doğrulanmış
  # `display` ile değiştirilir.
  .ux_guard_expect_order(
    llm_handlers_r,
    c(
      "seslendirilecek_metin <- result$content",
      "result$content <- as.character(pk_metinler$display)[1]",
      "trigger_tts_fn(ai_msg$id, seslendirilecek_metin)"
    ),
    "TTS metni dekorasyondan ÖNCE yakalanmalıdır:"
  )

  # BENZETİMLİ AKIŞ (SIMULATED STREAMING) DA AYNI SÖZLEŞMEYİ TAŞIR.
  #
  # Yukarıdaki iddialar yalnızca `R/server_llm_response_handlers.R` dosyasını
  # denetliyordu; oysa `R/helpers_chat_runtime.R` de TTS'i tetikler. Orada
  # dekorasyon SONLANDIRMADA yapılır ve YALNIZCA ekrana/DB'ye giden
  # `final_text`i değiştirir; TTS motoru DAHA ÖNCE `tts_metni` ile çağrılmıştır.
  # Bu dosya denetlenmezse, benzetimli akış köken alt bilgisini SESLİ OKUMAYA
  # başlasa bile süit yeşil kalırdı.
  ct_runtime_r <- .ux_guard_read_text("R/helpers_chat_runtime.R")

  .ux_guard_expect_all(
    ct_runtime_r,
    c(
      "tts_metni <- .cr_metin(blok$tts, yedek_blok$tts)",
      "tts_engine(tts_metni, tts_voice)",
      "final_text <- pk_stream_display_text(final_text, session, pk_request_id, .cr_blok_aktif)"
    ),
    "Benzetimli akış TTS/dekorasyon sözleşmesi eksik:"
  )

  # BU DOSYADA METİNSEL SIRA SÖZLEŞME DEĞİLDİR: dekorasyon,
  # `start_streaming_execution()` gövdesinde (dosyada DAHA YUKARIDA) yer alır
  # ama ÇALIŞMA sırasında TTS promise'i çözüldükten SONRA çalışır. Sözleşme,
  # dekorasyonun YALNIZCA gösterilecek metne uygulanmasıdır; bu yüzden OLUMSUZ
  # iddialarla kilitlenir.
  testthat::expect_false(
    .ux_guard_has_text(ct_runtime_r, "pk_stream_display_text(tts_metni"),
    info = "Köken dekorasyonu TTS metnine UYGULANMAMALIDIR."
  )
  testthat::expect_false(
    .ux_guard_has_text(ct_runtime_r, "tts_engine(final_text"),
    info = "TTS motoru DEKORE EDİLMİŞ metinle çağrılmamalıdır."
  )
  testthat::expect_false(
    .ux_guard_has_text(ct_runtime_r, "tts_engine(pk_stream_display_text"),
    info = "TTS motoru dekorasyon çıktısını almamalıdır."
  )

  .ux_guard_expect_all(
    messaging_r,
    c(
      "audio_block <- build_tts_audio_ui",
      "if (!is.null(audio_block)) audio_block"
    ),
    "Geçmiş mesajlarda kayıtlı audio UI çağrısı sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    module_tts_r,
    c(
      "build_tts_audio_ui <- function",
      "tags$audio(",
      "controls = \"controls\"",
      "src = audio_src"
    ),
    "Geçmiş mesajlarda autoplay yerine kontrollü audio UI sözleşmesi eksik:"
  )
  
  .ux_guard_expect_all(
    audio_guard_js,
    c(
      "window.MergenAudioLifecycle",
      "duckOwners",
      "activeDuckOwners",
      "stopIntroBeforeMain",
      "cleanupTransient",
      "markAudio",
      "getAudioOwner"
    ),
    "Audio lifecycle sahiplik koruması sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    intro_music_js,
    c(
      "_failedTrackUrls",
      "_consecutiveTrackErrors",
      "_maxConsecutiveTrackErrors",
      "_errorRetryDelay",
      "fadeOutAndStop: function(callback)"
    ),
    "Intro müzik sonsuz hata döngüsü/handoff sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    cinematic_js,
    c(
      "dismissDeepSpace(function()",
      "stopIntroBeforeMain",
      "afterIntroStopped"
    ),
    "Cinematic intro-main müzik handoff sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    character_step_js,
    c(
      "sendSelectionToShiny",
      "dismissDeepSpace(sendSelectionToShiny)"
    ),
    "Karakter seçim intro-main müzik handoff sözleşmesi eksik:"
  )

  testthat::expect_false(
    .ux_guard_has_text(visualizer_js, "$('audio').each"),
    info = "TTS görselleştirici tüm audio elemanlarını durdurmamalıdır."
  )
})

testthat::test_that("reasoning panel ve chat scroll davranışı korunur", {
  app_core_js <- .ux_guard_read_text("www/js/app_core.js")
  reasoning_js <- .ux_guard_read_text("www/js/premium_reasoning.js")
  chat_runtime_r <- .ux_guard_read_text("R/helpers_chat_runtime.R")
  input_js <- .ux_guard_read_text("www/js/input_handlers.js")

  .ux_guard_expect_all(
    app_core_js,
    c(
      "typing-animation-wrapper",
      "scrollToBottom(true)",
      "attachMessageObserver(true)",
      "#chat_content_container"
    ),
    "Chat observer/scroll sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    reasoning_js,
    c(
      "window.PremiumReasoning",
      "premiumReasoningStart",
      "streamingReasoningDelta",
      "premiumReasoningStreamStart",
      "window.isNearBottom !== false",
      "autoScrollPanel(panel)",
      "fadeOutAndRemove(panel)",
      "onResetChatState"
    ),
    "Reasoning panel lifecycle/scroll sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    chat_runtime_r,
    c(
      "window.PremiumReasoning.onResetChatState()",
      "removeUI(selector = \"#typing-animation-wrapper\")",
      "$('#send_stop_btn').removeClass('stop-mode')"
    ),
    "Chat reset reasoning/stop-button sözleşmesi eksik:"
  )

  .ux_guard_expect_all(
    input_js,
    c(
      "$(document).on('click', '#send_stop_btn'",
      "hasClass('stop-mode')",
      "send_prompt_from_js",
      "window.isNearBottom = isNearBottom"
    ),
    "Input/stop/scroll sözleşmesi eksik:"
  )
})