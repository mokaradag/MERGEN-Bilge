# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-delayed-dispatch-reactive-context.R
# Açıklama: Windows UTF-8 konuşma fixture sözleşmesi ve kişisel önek deadline
#           callback'inin aktif reactive consumer dışında güvenle statik
#           karşılamayı başlatması için regresyon testleri.
# ==============================================================================

suppressMessages({
  library(shiny)
  library(promises)
})

testthat::test_that(
  "Windows'ta üretilen konuşma fixture manifesti persona başına 150 varlık taşır",
  {
    speech_tests_source_chain()
    speech_tests_reset_caches()
    root <- withr::local_tempdir()

    speech_tests_make_tree(root)
    build <- mergen_speech_manifest_build(root)

    testthat::expect_true(build$ok, info = paste(build$problems, collapse = " | "))
    for (persona in mergen_speech_personas()) {
      testthat::expect_identical(
        length(build$manifest$personas[[persona]]$assets),
        150L,
        info = persona
      )
    }
  }
)

testthat::test_that(
  "gecikmeli karşılama dispatch'i reactive ve Shiny session context dışında çökmez",
  {
    speech_tests_source_chain()
    speech_tests_reset_caches()
    repo_root <- resolve_repo_root_for_tests()
    source(
      file.path(repo_root, "R", "server_speech_assets_runtime.R"),
      encoding = "UTF-8",
      local = globalenv()
    )

    root <- withr::local_tempdir()
    speech_tests_make_tree(root)
    manifest <- mergen_speech_manifest_build(root)$manifest
    mergen_speech_manifest_write(manifest, mergen_speech_manifest_path(root))

    withr::local_envvar(
      MERGEN_SPEECH_ROOT = root,
      VOXCPM2_PREFIX_DEADLINE_MS = "0",
      VOXCPM2_WARMUP_ENABLED = "false"
    )
    withr::defer(speech_tests_reset_caches())

    input <- shiny::reactiveValues(tabs = "chat")
    settings_data <- shiny::reactiveValues(selected_character = "emre")

    session <- shiny::MockShinySession$new()
    session$userData$user_first_name <- "Onur"

    calls <- new.env(parent = emptyenv())
    calls$n <- 0L
    calls$domain_ok <- FALSE
    speaking <- shiny::reactiveVal(FALSE)

    ai_expert <- list(
      start_speaking = function(...) {
        # Gerçek aiExpertServer hem reactiveVal okur hem de ttsVisualizer
        # üzerinden shinyjs çağırır. İlki isolate, ikincisi session domain ister.
        calls$domain_ok <- identical(shiny::getDefaultReactiveDomain(), session)
        if (!isTRUE(calls$domain_ok)) {
          stop("Shiny session domain kurulmadı")
        }
        if (isTRUE(speaking())) return(invisible(NULL))
        speaking(TRUE)
        calls$n <- calls$n + 1L
        invisible(NULL)
      },
      COOLDOWN_GREETING = 10,
      COOLDOWN_PAGE = 8
    )

    never_resolves <- promises::promise(function(resolve, reject) NULL)
    tts_processor <- list(
      synthesize_speech = function(...) never_resolves
    )

    runtime <- speechAssetsRuntimeInit(
      input = input,
      session = session,
      settings_data = settings_data,
      ai_expert = ai_expert,
      tts_processor = tts_processor,
      current_user_id = function() 5L
    )

    testthat::expect_true(runtime$prewarm_welcome("emre"))
    testthat::expect_true(runtime$play_welcome("emre"))

    testthat::expect_no_error(later::run_now(timeoutSecs = 0.1))
    testthat::expect_true(calls$domain_ok)
    testthat::expect_identical(calls$n, 1L)
  }
)

testthat::test_that("iptal edilen karşılama ön hazırlığı sonucu geçersiz kılar; tekrar onay sentezi yığmaz", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("promises")
  kok <- resolve_repo_root_for_tests()
  kaynak <- paste(readLines(file.path(kok, "R", "server_speech_assets_runtime.R"), encoding = "UTF-8", warn = FALSE),
                  collapse = "\n")
  # Geçersiz persona (iptal) yalnız nesli artırıp slotu boşaltır.
  onhazirlik <- regmatches(kaynak, regexpr("prewarm_welcome <- function\\(persona_id\\) \\{[\\s\\S]*?if \\(is.na\\(persona\\)\\) return", kaynak, perl = TRUE))
  testthat::expect_true(grepl("prefix_slot$gen <- prefix_slot$gen + 1L", onhazirlik, fixed = TRUE))
  isleyici <- paste(readLines(file.path(kok, "R", "server_ai_expert_handlers.R"), encoding = "UTF-8", warn = FALSE),
                    collapse = "\n")
  testthat::expect_true(grepl("return(speech_runtime$prewarm_welcome(NA_character_))", isleyici, fixed = TRUE))
})

testthat::test_that("A->B->A seçimi süren A sentezini yeniden kullanır; sahip değişimi kişisel öneki düşürür", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("promises")
  speech_tests_source_chain()
  speech_tests_reset_caches()
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_user_session_identity.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "server_speech_assets_runtime.R"), encoding = "UTF-8", local = env)
  # Son konu işçisi taklit edilir (paketin diğer testlerinden kalan tanım kullanılmaz).
  env$ai_expert_recent_prompt_promise <- function(session, user_id) promises::promise_resolve(NULL)
  root <- withr::local_tempdir()
  speech_tests_make_tree(root)
  mergen_speech_manifest_write(mergen_speech_manifest_build(root)$manifest, mergen_speech_manifest_path(root))
  withr::local_envvar(MERGEN_SPEECH_ROOT = root, VOXCPM2_PREFIX_DEADLINE_MS = "0",
                      VOXCPM2_WARMUP_ENABLED = "false")
  withr::defer(speech_tests_reset_caches())

  session <- shiny::MockShinySession$new()
  session$userData$user_first_name <- "Onur"
  session$userData$kimlik_sahibi <- 5L
  cagri <- 0L
  cozuculer <- list()
  tts <- list(synthesize_speech = function(text, persona_id = NULL) {
    cagri <<- cagri + 1L
    promises::promise(function(resolve, reject) cozuculer[[length(cozuculer) + 1L]] <<- resolve)
  })
  ogeler <- NULL
  ai_expert <- list(start_speaking = function(..., static_plan = NULL) {
    ogeler <<- static_plan$items
    invisible(NULL)
  }, COOLDOWN_GREETING = 10, COOLDOWN_PAGE = 8)
  runtime <- env$speechAssetsRuntimeInit(
    input = shiny::reactiveValues(tabs = "chat"), session = session,
    settings_data = shiny::reactiveValues(selected_character = "emre"),
    ai_expert = ai_expert, tts_processor = tts, current_user_id = function() 5L
  )
  personalar <- mergen_speech_personas()
  for (p in personalar[c(1, 2, 1)]) {
    runtime$prewarm_welcome(p)
    later::run_now(timeoutSecs = 0.1)
  }
  testthat::expect_identical(cagri, 2L)

  # A'nın sentezi B'ye geçişten sonra biter: önek B'nin karşılamasına eklenmez.
  env$mergen_session_owner_transition(session$userData, 5L, 6L)
  cozuculer[[1]](list(success = TRUE, audio_src = "data:audio/wav;base64,AA", duration = 1))
  later::run_now(timeoutSecs = 0.1)
  testthat::expect_true(runtime$play_welcome(personalar[1]))
  later::run_now(timeoutSecs = 0.1)
  testthat::expect_length(ogeler, 1L)
})

testthat::test_that("karşılama önekinin son konusu ana süreçte DB sorgusu yapmadan işçiden okunur", {
  testthat::skip_if_not_installed("promises")
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "helpers_ai_expert_greeting_topic.R"), encoding = "UTF-8", local = env)
  env$get_connection <- function(...) stop("ana süreçte DB bağlantısı açılmamalı")
  gonderimler <- list()
  env$tracked_future_promise <- function(task_fn, task_type = NULL, session_token = NULL,
                                         dependency_mode = "auto", globals = NULL, packages = NULL, ...) {
    gonderimler[[length(gonderimler) + 1L]] <<- list(tur = task_type, kip = dependency_mode, globals = globals)
    promises::promise_resolve("Bütçe raporu")
  }
  oturum <- list(userData = new.env(), token = "tok")
  sonuc <- NULL
  env$ai_expert_recent_prompt_promise(oturum, 5L)$then(function(x) sonuc <<- x)
  env$ai_expert_recent_prompt_promise(oturum, 5L)
  for (i in 1:5) later::run_now(timeoutSecs = 0.05)
  testthat::expect_identical(sonuc, "Bütçe raporu")
  testthat::expect_length(gonderimler, 1L)
  testthat::expect_identical(gonderimler[[1]]$kip, "explicit")
  testthat::expect_true(is.function(gonderimler[[1]]$globals$ai_expert_recent_prompt_fetch_raw))
  env$ai_expert_recent_prompt_promise(oturum, 6L)
  testthat::expect_length(gonderimler, 2L)
  bos <- "x"
  env$ai_expert_recent_prompt_promise(oturum, 0L)$then(function(x) bos <<- x)
  later::run_now(timeoutSecs = 0.1)
  testthat::expect_null(bos)
  testthat::expect_length(gonderimler, 2L)
})
