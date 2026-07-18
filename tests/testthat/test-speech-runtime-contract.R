# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-runtime-contract.R
# Açıklama: Hibrit konuşma çalışma zamanı kablolama sözleşmesi: kaynak
#           manifesti üyeliği/sırası, seam sahipliği, frontend varlık/bölge
#           üyeliği ve yükleme sırası, JS token korumaları, eski LLM sayfa
#           rehberliği yolunun geri dönmemesi, fail-closed TTS sınırı ve
#           statik öğe kurucusunun davranışı. Uygulama başlatılmaz.
# ==============================================================================

.speech_contract_read <- function(rel_path) {
  path <- file.path(resolve_repo_root_for_tests(), rel_path)
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  iconv(rawToChar(bytes), from = "UTF-8", to = "UTF-8", sub = "byte")
}

testthat::test_that("konuşma katmanı kaynak manifestinde doğru sırada kayıtlıdır", {
  manifest_txt <- .speech_contract_read("R/config_source_manifest.R")

  files <- c(
    "R/config_speech_assets.R",
    "R/config_speech_asset_paths.R",
    "R/helpers_speech_wav.R",
    "R/helpers_speech_voice_profiles.R",
    "R/helpers_speech_voxcpm2_adapter.R",
    "R/helpers_speech_manifest.R",
    "R/helpers_speech_playback_policy.R",
    "R/helpers_speech_warmup.R",
    "R/server_speech_assets_runtime.R",
    "R/server_speech_pcm_stream.R"
  )
  pos <- vapply(files, function(f) {
    regexpr(sprintf('"%s"', f), manifest_txt, fixed = TRUE, useBytes = TRUE)[1]
  }, numeric(1))

  testthat::expect_true(all(pos > 0), info = "Manifest kaydı eksik")
  # Yardımcı zincir sırası korunur; server konuşma dosyaları ai_expert
  # handler'larından ÖNCE yüklenir
  testthat::expect_true(all(diff(pos) > 0))

  handler_pos <- regexpr('"R/server_ai_expert_handlers.R"', manifest_txt,
                         fixed = TRUE, useBytes = TRUE)[1]
  testthat::expect_true(pos[["R/server_speech_assets_runtime.R"]] < handler_pos)
  testthat::expect_true(pos[["R/server_speech_pcm_stream.R"]] < handler_pos)
})

testthat::test_that("speech_assets bölümü medya_ses seam'ine aittir", {
  seam_txt <- .speech_contract_read("R/config_seam_registry.R")
  testthat::expect_true(grepl('"speech_assets"', seam_txt, fixed = TRUE, useBytes = TRUE))
})

testthat::test_that("speech_controller.js varlık manifestinde, bölge haritasında ve doğru sıradadır", {
  assets_txt <- .speech_contract_read("R/config_ui_assets.R")
  zones_txt <- .speech_contract_read("R/config_ui_asset_zones.R")

  testthat::expect_true(grepl('"js/speech_controller.js"', assets_txt,
                              fixed = TRUE, useBytes = TRUE))
  testthat::expect_true(grepl('"js/speech_controller.js"', zones_txt,
                              fixed = TRUE, useBytes = TRUE))

  # Sıra kuralları: denetleyici tüketicilerinden önce
  for (rule in c(
    'c("js/speech_controller.js", "js/tts_manager.js")',
    'c("js/speech_controller.js", "js/ai_expert_manager.js")',
    'c("js/speech_controller.js", "js/ai_expert_handlers.js")'
  )) {
    testthat::expect_true(grepl(rule, assets_txt, fixed = TRUE, useBytes = TRUE),
                          info = rule)
  }
})

testthat::test_that("JS token korumaları ve PCM oynatıcı çıpaları yerindedir", {
  controller <- .speech_contract_read("www/js/speech_controller.js")
  handlers <- .speech_contract_read("www/js/ai_expert_handlers.js")
  manager <- .speech_contract_read("www/js/ai_expert_manager.js")
  tts <- .speech_contract_read("www/js/tts_manager.js")

  for (anchor in c("window.MergenSpeech", "accept: function", "isCurrent: function",
                   "markStopped: function", "speechPcmStreamStart",
                   "speechPcmStreamChunk", "speechPcmStreamEnd",
                   "speech_pcm_drained", "speechPrefetch")) {
    testthat::expect_true(grepl(anchor, controller, fixed = TRUE, useBytes = TRUE),
                          info = anchor)
  }

  # Bağlama katmanı bayat token'ları düşürür
  for (anchor in c("speechTokenAccept", "speechTokenIsCurrent",
                   "MergenSpeech.markStopped")) {
    testthat::expect_true(grepl(anchor, handlers, fixed = TRUE, useBytes = TRUE),
                          info = anchor)
  }

  # Görselleştirici/kısma GERÇEK oynatma olayında başlar
  testthat::expect_true(grepl("_onAudioPlaying", manager, fixed = TRUE, useBytes = TRUE))
  testthat::expect_true(grepl("addEventListener('playing'", manager,
                              fixed = TRUE, useBytes = TRUE))

  # Eski geçiş zamanlayıcıları yeni sayfanın altyazısını gizleyemez
  for (anchor in c("hideToken !== self.state.speechToken",
                   "stopToken !== self.state.speechToken")) {
    testthat::expect_true(grepl(anchor, manager, fixed = TRUE, useBytes = TRUE),
                          info = anchor)
  }

  # Durdurma kontrolleri PCM akışını da durdurur
  testthat::expect_true(grepl("MergenSpeech.pcmStop", tts, fixed = TRUE, useBytes = TRUE))
})

testthat::test_that("sayfa rehberliği ve karşılama artık LLM çağırmaz", {
  handlers_txt <- .speech_contract_read("R/server_ai_expert_handlers.R")

  # Statik yol çıpaları
  testthat::expect_true(grepl("speechAssetsRuntimeInit", handlers_txt,
                              fixed = TRUE, useBytes = TRUE))
  testthat::expect_true(grepl("speech_runtime$play_welcome", handlers_txt,
                              fixed = TRUE, useBytes = TRUE))
  testthat::expect_true(grepl("speech_runtime$play_page_guidance", handlers_txt,
                              fixed = TRUE, useBytes = TRUE))
  testthat::expect_true(grepl("speech_runtime$prewarm_welcome", handlers_txt,
                              fixed = TRUE, useBytes = TRUE))

  # Eski LLM yolları geri dönmemeli (boşta konuşma LLM'i kalır)
  testthat::expect_false(grepl("ai_expert_page_guidance", handlers_txt,
                               fixed = TRUE, useBytes = TRUE))
  testthat::expect_false(grepl("ai_expert_greeting", handlers_txt,
                               fixed = TRUE, useBytes = TRUE))
  testthat::expect_true(grepl("ai_expert_idle_chat", handlers_txt,
                              fixed = TRUE, useBytes = TRUE))

  # Tek yetkili politika kullanımı; dağınık sessiz-liste geri dönmemeli
  testthat::expect_true(grepl("mergen_speech_guidance_policy", handlers_txt,
                              fixed = TRUE, useBytes = TRUE))
})

testthat::test_that("TTS modülü fail-closed persona sınırını uygular", {
  tts_txt <- .speech_contract_read("R/module_tts.R")

  for (anchor in c("mergen_speech_voice_mode", "mergen_speech_canonical_persona",
                   "mergen_speech_reference_payload", "mergen_voxcpm2_request_body",
                   "persona_id = NULL")) {
    testthat::expect_true(grepl(anchor, tts_txt, fixed = TRUE, useBytes = TRUE),
                          info = anchor)
  }

  handlers_tts <- .speech_contract_read("R/server_tts_handlers.R")
  testthat::expect_true(grepl("mergen_speech_canonical_persona", handlers_tts,
                              fixed = TRUE, useBytes = TRUE))
  testthat::expect_true(grepl("mergen_speech_pcm_stream_start", handlers_tts,
                              fixed = TRUE, useBytes = TRUE))
  # Eski genel ses takma adı yanıt seslendirmesine geri dönmemeli
  testthat::expect_false(grepl('"tr-male-1"', handlers_tts,
                               fixed = TRUE, useBytes = TRUE))
})

testthat::test_that("AI Uzman modülü statik plan + öncelik + token sözleşmesini taşır", {
  module_txt <- .speech_contract_read("R/module_ai_expert.R")

  for (anchor in c("static_plan = NULL", "mergen_speech_begin",
                   "mergen_speech_priority_decision", "mergen_speech_end",
                   "speechToken", "mergen_speech_idle_muted_pages",
                   "speech_is_current", "remaining_chunks_started",
                   "first_chunk_promise")) {
    testthat::expect_true(grepl(anchor, module_txt, fixed = TRUE, useBytes = TRUE),
                          info = anchor)
  }

  first_submit <- regexpr(
    "first_chunk_promise <- tts_processor$synthesize_speech",
    module_txt, fixed = TRUE, useBytes = TRUE
  )[1]
  eager_submit <- regexpr(
    "queue_remaining_chunks(chunks, 2L)",
    module_txt, fixed = TRUE, useBytes = TRUE
  )[1]
  first_wait <- regexpr(
    "first_chunk_promise %...>%",
    module_txt, fixed = TRUE, useBytes = TRUE
  )[1]
  testthat::expect_true(first_submit < eager_submit && eager_submit < first_wait)
})

testthat::test_that("statik öğe kurucusu metin+URL+süre döndürür ve eksikte NULL verir", {
  speech_tests_source_chain()
  speech_tests_reset_caches()
  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "server_speech_assets_runtime.R"),
         encoding = "UTF-8", local = globalenv())

  root <- withr::local_tempdir()
  speech_tests_make_tree(root)
  m <- mergen_speech_manifest_build(root)$manifest

  item <- .speech_build_static_item(m, "emre", "page_guidance", "files", 3L, root)
  testthat::expect_true(nzchar(item$text))
  testthat::expect_identical(item$audio_src, "speech/audio/emre/pages/files/files_03.wav")
  testthat::expect_true(item$duration_ms > 0)

  # Ses dosyası silinirse öğe kurulamaz (bozuk gönderim engellenir)
  unlink(file.path(root, "audio", "emre", "pages", "files", "files_03.wav"))
  testthat::expect_null(.speech_build_static_item(m, "emre", "page_guidance",
                                                  "files", 3L, root))
})

testthat::test_that("PCM akış kaydı iptal işaretini oturum durumunda tutar", {
  speech_tests_source_chain()
  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "server_speech_assets_runtime.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "server_speech_pcm_stream.R"),
         encoding = "UTF-8", local = globalenv())

  session <- speech_tests_fake_session()
  reg <- .speech_pcm_registry(session)
  rec <- new.env(parent = emptyenv())
  rec$cancelled <- FALSE
  assign("akis_1", rec, envir = reg)

  testthat::expect_true(mergen_speech_pcm_stream_cancel(session, "akis_1"))
  testthat::expect_true(rec$cancelled)
  # Bilinmeyen akış kimliği güvenle FALSE döner
  testthat::expect_false(mergen_speech_pcm_stream_cancel(session, "olmayan"))
})
