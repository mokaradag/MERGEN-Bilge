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

    session <- speech_tests_fake_session()
    session$userData$user_first_name <- "Onur"
    session$sendCustomMessage <- function(...) invisible(NULL)

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
