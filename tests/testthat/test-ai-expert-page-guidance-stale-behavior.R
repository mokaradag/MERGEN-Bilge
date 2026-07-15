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
  library(promises)
})


# ------------------------------------------------------------------------------
# Test ortamı
# ------------------------------------------------------------------------------

# AI Uzman işleyicisini izole env'e bağımlılık taklitleriyle yükler.
.ai_expert_pg_env <- function(ctrl, spoke) {
  env <- new.env(parent = globalenv())

  # safe_trimws/safe_nzchar/%||% utils_common'da; helper_bootstrap yüklemez.
  source(
    file.path(
      resolve_repo_root_for_tests(),
      "R",
      "utils_common.R"
    ),
    encoding = "UTF-8",
    local = env
  )

  # Worker-safe DB okuyucuları ayrı dosyada; handler bunları çağırır.
  source(
    file.path(
      resolve_repo_root_for_tests(),
      "R",
      "helpers_ai_expert_user_data.R"
    ),
    encoding = "UTF-8",
    local = env
  )

  source(
    file.path(
      resolve_repo_root_for_tests(),
      "R",
      "helpers_ai_expert.R"
    ),
    encoding = "UTF-8",
    local = env
  )

  # Handler saf karar yardımcılarını bu dosyadan çağırır.
  source(
    file.path(
      resolve_repo_root_for_tests(),
      "R",
      "helpers_ai_expert_handlers_support.R"
    ),
    encoding = "UTF-8",
    local = env
  )

  source(
    file.path(
      resolve_repo_root_for_tests(),
      "R",
      "helpers_ai_expert_lifecycle.R"
    ),
    encoding = "UTF-8",
    local = env
  )

  source(
    file.path(
      resolve_repo_root_for_tests(),
      "R",
      "server_ai_expert_handlers.R"
    ),
    encoding = "UTF-8",
    local = env
  )

  # Gerçek API anahtarı çözümlemesini engelle.
  env$mb_api_key_get_feature_key_value <- function(...) {
    "sk-test"
  }

  # Gerçek karakter yapılandırması okunmasın.
  env$get_characters_data <- function() {
    list(
      styles = list(
        list(
          id = "emre",
          tts_voice = "tr-male-1"
        )
      )
    )
  }

  env$normalize_character_id <- function(x) {
    "emre"
  }

  # DB'ye gitmesin: kullanıcı adı çözümleme taklidi.
  env$fetch_user_full_name <- function(...) {
    "Test"
  }

  # Yalnızca sayfa rehberliği görevini kontrollü promise ile yakala.
  # Diğer görevler hiç çözülmeyen promise döndürür.
  env$tracked_future_promise <- function(
    task_fn,
    task_type = NULL,
    ...
  ) {
    if (identical(task_type, "ai_expert_page_guidance")) {
      promises::promise(function(resolve, reject) {
        ctrl$resolve <- resolve
      })
    } else {
      promises::promise(function(resolve, reject) {
        NULL
      })
    }
  }

  env
}


# ------------------------------------------------------------------------------
# AI Uzman taklidi
# ------------------------------------------------------------------------------

.ai_expert_stub <- function(spoke) {
  list(
    is_speaking = function() {
      isTRUE(spoke$is_speaking)
    },

    can_speak = function() {
      TRUE
    },

    start_speaking = function(text, ...) {
      spoke$n <- spoke$n + 1L
      spoke$last_text <- text
      spoke$is_speaking <- TRUE
      invisible(NULL)
    },

    stop_speaking = function(...) {
      spoke$stop_n <- if (is.null(spoke$stop_n)) 1L else spoke$stop_n + 1L
      spoke$is_speaking <- FALSE
      invisible(NULL)
    },

    set_page = function(p) {
      invisible(NULL)
    },

    set_user_active = function(x) {
      invisible(NULL)
    },

    set_tts_vocalizing = function(x) {
      invisible(NULL)
    },

    prewarm_speaking = function(...) {
      invisible(NULL)
    },

    COOLDOWN_GREETING = 1,
    COOLDOWN_PAGE = 1,
    COOLDOWN_IDLE = 1
  )
}


# ------------------------------------------------------------------------------
# Test sunucusu sarmalayıcısı
# ------------------------------------------------------------------------------

.ai_expert_wrapper <- function(env, ai_expert) {
  function(input, output, session) {
    values <- shiny::reactiveValues(
      is_sending = FALSE
    )

    env$aiExpertHandlersInit(
      input = input,
      session = session,
      values = values,

      settings_data = list(
        enable_ai_expert = TRUE,
        experience_mode = "kesif",
        ai_expert_talk_frequency = "orta",
        ai_expert_talk_length = "orta",
        ai_expert_talk_style = "profesyonel"
      ),

      ai_expert = ai_expert,
      tts_processor = list(),
      current_user_id = function() {
        5L
      }
    )
  }
}


# ------------------------------------------------------------------------------
# Promise/later kuyruğunu boşaltma yardımcısı
# ------------------------------------------------------------------------------

.drain_ai_expert_later <- function(max_iter = 100L) {
  for (i in seq_len(max_iter)) {
    if (later::loop_empty()) {
      break
    }

    later::run_now(timeout = 0)
  }

  invisible(NULL)
}


# ------------------------------------------------------------------------------
# Test 1: Bayat rehberlik sonucu seslendirilmemeli
# ------------------------------------------------------------------------------

testthat::test_that(
  "sayfa rehberliği yanıtı dönerken yasaklı sayfaya geçildiyse SESLENDİRMEZ",
  {
    ctrl <- new.env(parent = emptyenv())
    ctrl$resolve <- NULL

    spoke <- new.env(parent = emptyenv())
    spoke$n <- 0L
    spoke$last_text <- NULL

    env <- .ai_expert_pg_env(
      ctrl = ctrl,
      spoke = spoke
    )

    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(
          .ai_expert_wrapper(
            env = env,
            ai_expert = ai_expert
          ),
          {
            # MockShinySession ignoreInit nedeniyle ilk değer tüketilir.
            session$setInputs(
              tabs = "files"
            )

            # History sayfası için rehberlik isteğini başlatır.
            session$setInputs(
              tabs = "history"
            )

            # Rehberlik sonucu dönmeden yasaklı sayfaya geçilir.
            session$setInputs(
              tabs = "settings_kisisel"
            )

            testthat::expect_true(
              is.function(ctrl$resolve)
            )

            ctrl$resolve(
              "Eski sayfa rehberliği"
            )

            .drain_ai_expert_later()

            # Bayat history rehberliği seslendirilmemelidir.
            testthat::expect_identical(
              spoke$n,
              0L
            )

            testthat::expect_null(
              spoke$last_text
            )
          }
        )
      },

      delay = function(ms, expr) {
        invisible(NULL)
      },

      runjs = function(...) {
        invisible(NULL)
      },

      .package = "shinyjs"
    )
  }
)


# ------------------------------------------------------------------------------
# Test 2: Güncel rehberlik sonucu seslendirilmeli
# ------------------------------------------------------------------------------

testthat::test_that(
  "sayfa rehberliği yanıtı dönerken aynı sayfada kalındıysa SESLENDİRİR",
  {
    ctrl <- new.env(parent = emptyenv())
    ctrl$resolve <- NULL

    spoke <- new.env(parent = emptyenv())
    spoke$n <- 0L
    spoke$last_text <- NULL

    env <- .ai_expert_pg_env(
      ctrl = ctrl,
      spoke = spoke
    )

    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(
          .ai_expert_wrapper(
            env = env,
            ai_expert = ai_expert
          ),
          {
            # MockShinySession ignoreInit nedeniyle ilk değer tüketilir.
            session$setInputs(
              tabs = "files"
            )

            # History sayfası için rehberlik isteğini başlatır.
            session$setInputs(
              tabs = "history"
            )

            testthat::expect_true(
              is.function(ctrl$resolve)
            )

            ctrl$resolve(
              "History sayfası rehberliği"
            )

            .drain_ai_expert_later()

            testthat::expect_identical(
              spoke$n,
              1L
            )

            testthat::expect_identical(
              spoke$last_text,
              "History sayfası rehberliği"
            )
          }
        )
      },

      delay = function(ms, expr) {
        invisible(NULL)
      },

      runjs = function(...) {
        invisible(NULL)
      },

      .package = "shinyjs"
    )
  }
)


# ------------------------------------------------------------------------------
# Test 3: Aktif A rehberliği gezinmede durur; B rehberliği hemen başlayabilir
# ------------------------------------------------------------------------------

testthat::test_that(
  "sayfa geçişi aktif eski rehberliği durdurur ve yenisini engellemez",
  {
    ctrl <- new.env(parent = emptyenv()); ctrl$resolve <- NULL
    spoke <- new.env(parent = emptyenv())
    spoke$n <- 0L; spoke$stop_n <- 0L; spoke$last_text <- NULL
    env <- .ai_expert_pg_env(ctrl = ctrl, spoke = spoke)
    ai_expert <- .ai_expert_stub(spoke)

    testthat::with_mocked_bindings(
      {
        shiny::testServer(.ai_expert_wrapper(env = env, ai_expert = ai_expert), {
          session$setInputs(tabs = "files")
          session$setInputs(tabs = "history")
          ctrl$resolve("History rehberliği")
          .drain_ai_expert_later()
          testthat::expect_true(spoke$is_speaking)

          session$setInputs(tabs = "files")
          testthat::expect_identical(spoke$stop_n, 1L)
          testthat::expect_false(spoke$is_speaking)
          testthat::expect_true(is.function(ctrl$resolve))

          ctrl$resolve("Dosyalar rehberliği")
          .drain_ai_expert_later()
          testthat::expect_identical(spoke$n, 2L)
          testthat::expect_identical(spoke$last_text, "Dosyalar rehberliği")
          testthat::expect_true(spoke$is_speaking)
        })
      },
      delay = function(ms, expr) invisible(NULL),
      runjs = function(...) invisible(NULL),
      .package = "shinyjs"
    )
  }
)


testthat::test_that("nesil belirteci eski LLM/TTS işini geçersizleştirir", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert_lifecycle.R"),
         encoding = "UTF-8", local = env)
  generation <- 1L; page <- "files"
  cancel_a <- env$mergen_ai_expert_cancel_predicate(
    1L, "files", function() generation, function() page
  )
  testthat::expect_false(cancel_a())
  generation <- env$mergen_ai_expert_next_generation(generation); page <- "analysis"
  testthat::expect_true(cancel_a())
  line <- env$mergen_ai_expert_trace_context_line("tts_worker_complete",
    list(sequence_id = 7L, page_id = "files<script>", chunk_index = 1L),
    duration_ms = 125.4, at = as.POSIXct("2026-07-15 09:00:00", tz = "UTC"))
  testthat::expect_match(line, "seq=7", fixed = TRUE)
  testthat::expect_match(line, "duration_ms=125", fixed = TRUE)
  testthat::expect_false(grepl("<script>", line, fixed = TRUE))
})


testthat::test_that("kritik yol izleri içerik taşımadan worker aşamalarını kapsar", {
  root <- resolve_repo_root_for_tests()
  tts <- paste(readLines(file.path(root, "R", "module_tts.R"),
                         warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  module <- paste(readLines(file.path(root, "R", "module_ai_expert.R"),
                            warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  testthat::expect_match(tts,
    'mergen_ai_expert_trace_context_line("tts_worker_start"', fixed = TRUE)
  testthat::expect_match(tts,
    'mergen_ai_expert_trace_context_line("tts_worker_complete"', fixed = TRUE)
  lifecycle <- paste(readLines(file.path(root, "R", "helpers_ai_expert_lifecycle.R"),
                               warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  testthat::expect_match(lifecycle, "chunk_index = context$chunk_index", fixed = TRUE)
  testthat::expect_match(module, "should_cancel = function()", fixed = TRUE)
  testthat::expect_match(module, "!is_active() ||", fixed = TRUE)
  testthat::expect_match(module, "is.function(should_cancel)", fixed = TRUE)
  testthat::expect_match(module, "tryCatch(should_cancel(), error = function(e) FALSE)", fixed = TRUE)
})
