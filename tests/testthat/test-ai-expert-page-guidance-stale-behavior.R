# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-page-guidance-stale-behavior.R
# Açıklama: AI Uzman sayfa rehberliği BAYATLIK koruması davranış testi.
#           LLM rehberlik yanıtı dönerken kullanıcı başka (örn. yasaklı
#           settings_kisisel) sayfaya geçmişse, eski sayfanın rehberlik metni
#           SESLENDİRİLMEMELİDİR; aynı sayfada kalındıysa seslendirilmelidir.
#           tracked_future_promise task_type'a göre kontrollü promise ile taklit
#           edilir; shinyjs::delay/runjs mock'lanır. Gerçek LLM/TTS/ağ GEREKMEZ.
# ==============================================================================

suppressMessages({
  library(shiny)
  library(promises)  # %...>% / %...!% akış operatörleri sayfa rehberliği geri çağrısında kullanılır
})

# AI Uzman işleyicisini izole env'e bağımlılık taklitleriyle yükler.
.ai_expert_pg_env <- function(ctrl, spoke) {
  env <- new.env(parent = globalenv())
  # safe_trimws/safe_nzchar/%||% utils_common'da; helper_bootstrap yüklemez.
  source(file.path(resolve_repo_root_for_tests(), "R", "utils_common.R"),
         encoding = "UTF-8", local = env)
  # Worker-safe DB okuyucuları ayrı dosyada; handler bunları çağırır.
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert_user_data.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert.R"),
         encoding = "UTF-8", local = env)
  # Handler artık saf karar yardımcılarını (sayfa adı vb.) bu dosyadan çağırır.
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert_handlers_support.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "server_ai_expert_handlers.R"),
         encoding = "UTF-8", local = env)

  env$mb_api_key_get_feature_key_value <- function(...) "sk-test"
  env$get_characters_data <- function() list(styles = list(list(id = "emre", tts_voice = "tr-male-1")))
  env$normalize_character_id <- function(x) "emre"
  # DB'ye gitmesin: kullanıcı adı çözümleme taklidi.
  env$fetch_user_full_name <- function(...) "Test"

  # Yalnızca sayfa rehberliği görevini kontrollü promise ile yakala; diğer
  # görevler (karşılama/boşta) hiç çözülmeyen promise döndürür.
  env$tracked_future_promise <- function(task_fn, task_type = NULL, ...) {
    if (identical(task_type, "ai_expert_page_guidance")) {
      promises::promise(function(resolve, reject) ctrl$resolve <- resolve)
    } else {
      promises::promise(function(resolve, reject) NULL)
    }
  }
  env
}

.ai_expert_stub <- function(spoke) {
  list(
    is_speaking = function() FALSE,
    can_speak = function() TRUE,
    start_speaking = function(text, ...) {
      spoke$n <- spoke$n + 1L
      spoke$last_text <- text
    },
    stop_speaking = function(...) invisible(NULL),
    set_page = function(p) invisible(NULL),
    set_user_active = function(x) invisible(NULL),
    set_tts_vocalizing = function(x) invisible(NULL),
    prewarm_speaking = function(...) invisible(NULL),
    COOLDOWN_GREETING = 1, COOLDOWN_PAGE = 1, COOLDOWN_IDLE = 1
  )
}

.ai_expert_wrapper <- function(env, ai_expert) {
  function(input, output, session) {
    values <- reactiveValues(is_sending = FALSE)
    env$aiExpertHandlersInit(
      input, session, values,
      settings_data = list(
        enable_ai_expert = TRUE, experience_mode = "kesif",
        ai_expert_talk_frequency = "orta", ai_expert_talk_length = "orta",
        ai_expert_talk_style = "profesyonel"
      ),
      ai_expert = ai_expert, tts_processor = list(),
      current_user_id = function() 5L
    )
  }
}

.drain_ai_expert_later <- function(max_iter = 100L) {
  for (i in seq_len(max_iter)) {
    if (later::loop_empty()) break
    later::run_now(timeout = 0)
  }
}

testthat::test_that("sayfa rehberliği yanıtı dönerken yasaklı sayfaya geçildiyse SESLENDİRMEZ", {
  ctrl <- new.env(); ctrl$resolve <- NULL
  spoke <- new.env(); spoke$n <- 0L
  env <- .ai_expert_pg_env(ctrl, spoke)
  ai_expert <- .ai_expert_stub(spoke)

  testthat::local_mocked_bindings(
    delay = function(ms, expr) invisible(NULL),
    runjs = function(...) invisible(NULL),
    .package = "shinyjs"
  )

  shiny::testServer(.ai_expert_wrapper(env, ai_expert), {
    # MockShinySession ignoreInit: ilk setInputs tüketilir, bu yüzden prime-then-set.
    session$setInputs(tabs = "files")             # PRIME (tüketilir)
    session$setInputs(tabs = "history")           # rehberlik tetiklenir (promise beklemede)
    session$setInputs(tabs = "settings_kisisel")  # yasaklı sayfaya geçiş
    if (!is.null(ctrl$resolve)) ctrl$resolve("Eski sayfa rehberliği")
    .drain_ai_expert_later()

    # Bayat (history) rehberliği settings_kisisel'de seslendirilmemeli.
    testthat::expect_identical(spoke$n, 0L)
  })
})

testthat::test_that("sayfa rehberliği yanıtı dönerken aynı sayfada kalındıysa SESLENDİRİR", {
  ctrl <- new.env(); ctrl$resolve <- NULL
  spoke <- new.env(); spoke$n <- 0L; spoke$last_text <- NULL
  env <- .ai_expert_pg_env(ctrl, spoke)
  ai_expert <- .ai_expert_stub(spoke)

  testthat::local_mocked_bindings(
    delay = function(ms, expr) invisible(NULL),
    runjs = function(...) invisible(NULL),
    .package = "shinyjs"
  )

  shiny::testServer(.ai_expert_wrapper(env, ai_expert), {
    # MockShinySession ignoreInit: ilk setInputs tüketilir, bu yüzden prime-then-set.
    session$setInputs(tabs = "files")    # PRIME (tüketilir)
    session$setInputs(tabs = "history")  # rehberlik tetiklenir, sayfada kalınır
    if (!is.null(ctrl$resolve)) ctrl$resolve("History sayfası rehberliği")
    .drain_ai_expert_later()

    testthat::expect_identical(spoke$n, 1L)
    testthat::expect_identical(spoke$last_text, "History sayfası rehberliği")
  })
})
