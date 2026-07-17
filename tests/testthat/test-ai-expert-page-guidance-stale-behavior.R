# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-page-guidance-stale-behavior.R
# Açıklama: AI Uzman sayfa rehberliği davranış testi (hibrit statik mimari).
#           Rehberlik artık gezinme anında LLM ÇAĞIRMADAN, önceden üretilmiş
#           persona WAV planıyla SENKRON gönderilir: rehberli sayfada ortak
#           senaryo metni + doğru ses URL'siyle start_speaking çağrılır;
#           sessiz sayfaya (settings_kisisel) geçiş rehberlik üretmez ve aktif
#           konuşmayı durdurur; Ana Söyleşi'ye dönüş ek rehberlik oynatmaz.
#           Gerçek LLM/TTS/ağ GEREKMEZ; geçici varlık ağacı + manifest kullanılır.
# ==============================================================================

suppressMessages({
  library(shiny)
  library(promises)
})

# AI Uzman işleyicisini ve hibrit konuşma çalışma zamanını izole env'e yükler.
.ai_expert_pg_env <- function() {
  speech_tests_source_chain()

  env <- new.env(parent = globalenv())
  repo_root <- resolve_repo_root_for_tests()

  for (f in c(
    "R/utils_common.R",
    "R/helpers_ai_expert_user_data.R",
    "R/helpers_ai_expert.R",
    "R/helpers_ai_expert_handlers_support.R",
    "R/server_speech_assets_runtime.R",
    "R/server_speech_pcm_stream.R",
    "R/server_ai_expert_handlers.R"
  )) {
    source(file.path(repo_root, f), encoding = "UTF-8", local = env)
  }

  # Gerçek API anahtarı çözümlemesini engelle.
  env$mb_api_key_get_feature_key_value <- function(...) "sk-test"

  env$normalize_character_id <- function(x) "emre"

  # DB'ye gitmesin.
  env$fetch_user_full_name <- function(...) "Test"
  env$fetch_recent_user_prompts <- function(...) NULL

  # Boşta konuşma LLM görevi hiç çözülmeyen promise ile taklit edilir.
  env$tracked_future_promise <- function(task_fn, task_type = NULL, ...) {
    promises::promise(function(resolve, reject) NULL)
  }

  env
}

# AI Uzman taklidi: start/stop çağrılarını tür ve statik planla birlikte kaydeder.
.ai_expert_stub <- function(spoke, speaking = FALSE) {
  list(
    is_speaking = function() isTRUE(spoke$speaking),
    can_speak = function() TRUE,
    start_speaking = function(text, cooldown_secs = NULL, kind = "idle",
                              static_plan = NULL) {
      spoke$n <- spoke$n + 1L
      spoke$last_text <- text
      spoke$last_kind <- kind
      spoke$last_plan <- static_plan
      invisible(NULL)
    },
    stop_speaking = function(...) {
      spoke$stops <- spoke$stops + 1L
      spoke$speaking <- FALSE
      invisible(NULL)
    },
    set_page = function(p) invisible(NULL),
    set_user_active = function(x) invisible(NULL),
    set_tts_vocalizing = function(x) invisible(NULL),
    prewarm_speaking = function(...) invisible(NULL),
    COOLDOWN_GREETING = 1,
    COOLDOWN_PAGE = 1,
    COOLDOWN_IDLE = 1
  )
}

.ai_expert_wrapper <- function(env, ai_expert) {
  function(input, output, session) {
    values <- shiny::reactiveValues(is_sending = FALSE)

    env$aiExpertHandlersInit(
      input = input,
      session = session,
      values = values,
      settings_data = list(
        enable_ai_expert = TRUE,
        experience_mode = "kesif",
        selected_character = "emre",
        ai_expert_talk_frequency = "orta",
        ai_expert_talk_length = "orta",
        ai_expert_talk_style = "profesyonel"
      ),
      ai_expert = ai_expert,
      tts_processor = list(
        tts_available = function() FALSE,
        synthesize_speech = function(...) stop("Bu testte sentez çağrılmamalı")
      ),
      current_user_id = function() 5L
    )
  }
}

.pg_spoke <- function(speaking = FALSE) {
  spoke <- new.env(parent = emptyenv())
  spoke$n <- 0L
  spoke$stops <- 0L
  spoke$last_text <- NULL
  spoke$last_kind <- NULL
  spoke$last_plan <- NULL
  spoke$speaking <- speaking
  spoke
}

testthat::test_that(
  "rehberli sayfaya geçiş statik plan ile SENKRON rehberlik gönderir (LLM yok)",
  {
    speech_tests_reset_caches()
    root <- withr::local_tempdir()
    speech_tests_make_tree(root)
    m <- mergen_speech_manifest_build(root)$manifest
    mergen_speech_manifest_write(m, mergen_speech_manifest_path(root))
    withr::local_envvar(MERGEN_SPEECH_ROOT = root,
                        VOXCPM2_WARMUP_ENABLED = "false")
    withr::defer(speech_tests_reset_caches())

    env <- .ai_expert_pg_env()
    spoke <- .pg_spoke()
    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(
          .ai_expert_wrapper(env = env, ai_expert = ai_expert),
          {
            # MockShinySession ignoreInit nedeniyle ilk değer tüketilir.
            session$setInputs(tabs = "files")

            # history: statik rehberlik ANINDA gönderilir (async LLM yok).
            session$setInputs(tabs = "history")

            testthat::expect_identical(spoke$n, 1L)
            testthat::expect_identical(spoke$last_kind, "page_guidance")

            plan <- spoke$last_plan
            testthat::expect_true(is.list(plan) && length(plan$items) == 1L)
            item <- plan$items[[1]]
            testthat::expect_match(item$audio_src,
                                   "^speech/audio/emre/pages/history/history_\\d{2}\\.wav$")
            # Altyazı metni ortak senaryo dosyasının metnidir
            testthat::expect_match(item$text, "Deneme metni history_")
            testthat::expect_identical(spoke$last_text, item$text)
          }
        )
      },
      delay = function(ms, expr) invisible(NULL),
      runjs = function(...) invisible(NULL),
      .package = "shinyjs"
    )
  }
)

testthat::test_that(
  paste0("art arda rehberli sayfalara geçiş aktif konuşma (karşılama/eski ",
         "rehberlik) sürerken bile yeni rehberliği GÖNDERİR (Codex P2: ",
         "can_speak_basic() eski is_speaking() kapısı start_speaking()'in ",
         "kendi öncelik matrisine ulaşmadan erken dönmemelidir)"),
  {
    speech_tests_reset_caches()
    root <- withr::local_tempdir()
    speech_tests_make_tree(root)
    m <- mergen_speech_manifest_build(root)$manifest
    mergen_speech_manifest_write(m, mergen_speech_manifest_path(root))
    withr::local_envvar(MERGEN_SPEECH_ROOT = root,
                        VOXCPM2_WARMUP_ENABLED = "false")
    withr::defer(speech_tests_reset_caches())

    env <- .ai_expert_pg_env()
    # is_speaking() baştan sona TRUE kalır: start_speaking() sahte fonksiyonu
    # bu bayrağı değiştirmez, yani karşılama/önceki rehberlik hâlâ çalıyormuş
    # gibi davranılır.
    spoke <- .pg_spoke(speaking = TRUE)
    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(
          .ai_expert_wrapper(env = env, ai_expert = ai_expert),
          {
            session$setInputs(tabs = "files")  # ignoreInit tüketir

            # İlk rehberli sayfa: aktif konuşma sürüyorken bile GÖNDERİLMELİDİR
            # (kesme kararı start_speaking() içindeki öncelik matrisine aittir).
            session$setInputs(tabs = "history")
            testthat::expect_identical(spoke$n, 1L)
            testthat::expect_identical(spoke$last_kind, "page_guidance")

            # İkinci rehberli sayfa: is_speaking() hâlâ TRUE; eski gate burada
            # da engellememelidir (regresyondan önce ikinci klip hiç çalmazdı).
            session$setInputs(tabs = "saved_chats")
            testthat::expect_identical(spoke$n, 2L)
            testthat::expect_identical(spoke$last_kind, "page_guidance")
          }
        )
      },
      delay = function(ms, expr) invisible(NULL),
      runjs = function(...) invisible(NULL),
      .package = "shinyjs"
    )
  }
)

testthat::test_that(
  paste0("Ana Söyleşi'ye dönüşte sızmış bir page_guidance klibi DURDURULUR ",
         "(Codex P2); karşılama/boşta konuşması ise KORUNUR"),
  {
    speech_tests_reset_caches()
    root <- withr::local_tempdir()
    speech_tests_make_tree(root)
    m <- mergen_speech_manifest_build(root)$manifest
    mergen_speech_manifest_write(m, mergen_speech_manifest_path(root))
    withr::local_envvar(MERGEN_SPEECH_ROOT = root,
                        VOXCPM2_WARMUP_ENABLED = "false")
    withr::defer(speech_tests_reset_caches())

    env <- .ai_expert_pg_env()
    spoke <- .pg_spoke(speaking = TRUE)
    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(
          .ai_expert_wrapper(env = env, ai_expert = ai_expert),
          {
            session$setInputs(tabs = "files")  # ignoreInit tüketir

            # Başka sayfadan sızmış bir page_guidance klibi hâlâ çalıyor
            # gibi durum kur (gerçek session konuşma durumu, sahte
            # ai_expert$is_speaking()'ten bağımsızdır).
            mergen_speech_begin(session, "page_guidance")

            # Ana Söyleşi'ye dönüş: sızmış klip DURDURULMALIDIR.
            session$setInputs(tabs = "chat")
            testthat::expect_identical(spoke$stops, 1L)

            # Şimdi karşılama/boşta konuşması sürüyor gibi durum kur.
            spoke$speaking <- TRUE
            mergen_speech_begin(session, "welcome")

            session$setInputs(tabs = "files")
            session$setInputs(tabs = "chat")
            # welcome/idle bu sayfaya aittir: chat dönüşü EK durdurma
            # ÇAĞIRMAMALIDIR (durdurma sayacı 1'de kalır).
            testthat::expect_identical(spoke$stops, 1L)
          }
        )
      },
      delay = function(ms, expr) invisible(NULL),
      runjs = function(...) invisible(NULL),
      .package = "shinyjs"
    )
  }
)

testthat::test_that(
  "sessiz sayfaya (Kişiselleştirme) geçiş rehberlik ÜRETMEZ ve aktif konuşmayı durdurur",
  {
    speech_tests_reset_caches()
    root <- withr::local_tempdir()
    speech_tests_make_tree(root)
    m <- mergen_speech_manifest_build(root)$manifest
    mergen_speech_manifest_write(m, mergen_speech_manifest_path(root))
    withr::local_envvar(MERGEN_SPEECH_ROOT = root,
                        VOXCPM2_WARMUP_ENABLED = "false")
    withr::defer(speech_tests_reset_caches())

    env <- .ai_expert_pg_env()
    spoke <- .pg_spoke(speaking = TRUE)  # aktif konuşma sürüyor
    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(
          .ai_expert_wrapper(env = env, ai_expert = ai_expert),
          {
            session$setInputs(tabs = "files")

            # Persona tanıtım videosu sayfası: konuşma durdurulur, rehberlik yok
            session$setInputs(tabs = "settings_kisisel")

            testthat::expect_identical(spoke$n, 0L)
            testthat::expect_identical(spoke$stops, 1L)

            # Yönetici sayfası da sessizdir
            spoke$speaking <- TRUE
            session$setInputs(tabs = "admin_analytics")
            testthat::expect_identical(spoke$n, 0L)
            testthat::expect_identical(spoke$stops, 2L)
          }
        )
      },
      delay = function(ms, expr) invisible(NULL),
      runjs = function(...) invisible(NULL),
      .package = "shinyjs"
    )
  }
)

testthat::test_that(
  "Ana Söyleşi'ye dönüş ek rehberlik klibi OYNATMAZ (karşılama kapsar)",
  {
    speech_tests_reset_caches()
    root <- withr::local_tempdir()
    speech_tests_make_tree(root)
    m <- mergen_speech_manifest_build(root)$manifest
    mergen_speech_manifest_write(m, mergen_speech_manifest_path(root))
    withr::local_envvar(MERGEN_SPEECH_ROOT = root,
                        VOXCPM2_WARMUP_ENABLED = "false")
    withr::defer(speech_tests_reset_caches())

    env <- .ai_expert_pg_env()
    spoke <- .pg_spoke()
    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(
          .ai_expert_wrapper(env = env, ai_expert = ai_expert),
          {
            session$setInputs(tabs = "files")

            # Ana Söyleşi'ye dönüş: konuşma/rehberlik tetiklenmez
            session$setInputs(tabs = "chat")
            testthat::expect_identical(spoke$n, 0L)
            testthat::expect_identical(spoke$stops, 0L)
          }
        )
      },
      delay = function(ms, expr) invisible(NULL),
      runjs = function(...) invisible(NULL),
      .package = "shinyjs"
    )
  }
)

testthat::test_that(
  "statik varlıklar üretilmemişse rehberlik güvenle atlanır (başka sesle konuşulmaz)",
  {
    speech_tests_reset_caches()
    root <- withr::local_tempdir()  # boş kök: manifest/kilit yok
    withr::local_envvar(MERGEN_SPEECH_ROOT = root,
                        VOXCPM2_WARMUP_ENABLED = "false")
    withr::defer(speech_tests_reset_caches())

    env <- .ai_expert_pg_env()
    spoke <- .pg_spoke()
    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(
          .ai_expert_wrapper(env = env, ai_expert = ai_expert),
          {
            session$setInputs(tabs = "files")
            session$setInputs(tabs = "history")

            # Varlık yok -> konuşma YOK; hata da yok (zarif atlama)
            testthat::expect_identical(spoke$n, 0L)
          }
        )
      },
      delay = function(ms, expr) invisible(NULL),
      runjs = function(...) invisible(NULL),
      .package = "shinyjs"
    )
  }
)
