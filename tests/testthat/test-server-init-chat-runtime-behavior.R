# ==============================================================================
# Dosya Yolu: tests/testthat/test-server-init-chat-runtime-behavior.R
# Açıklama: serverInitChatRuntime (R/server_init_chat_runtime.R) sohbet çalışma
#           zamanı yardımcı fabrikasının davranışını test eder. Döndürülen dört
#           kapanışın (reset_chat_state / add_message / generate_title_from_prompt
#           / simulate_streaming_stoppable) doğru temsilciye yönlendirdiğini ve
#           özellikle add_message'ın kullanıcı kimliğini ÇAĞRI ANINDA canlı
#           sağlayıcıdan çözdüğünü (SSO anlık görüntü değil) kanıtlar. Sahte
#           oturum/temsilci stub'larıyla çalışır; gerçek DB/LLM/ağ/tarayıcı
#           GEREKMEZ.
# ==============================================================================

# server_init_chat_runtime.R'yi izole bir ortama yükler ve dört temsilci
# fonksiyonu (chat_reset_state / chat_add_message / chat_generate_title_from_prompt
# / chat_simulate_streaming) kaydedici stub'larla değiştirir.
.scr_env <- function() {
  env <- new.env(parent = globalenv())
  env$.rec <- new.env(parent = emptyenv())
  env$.rec$reset <- list()
  env$.rec$add <- list()
  env$.rec$title <- list()
  env$.rec$stream <- list()

  env$chat_reset_state <- function(session, values) {
    env$.rec$reset[[length(env$.rec$reset) + 1L]] <- list(session = session, values = values)
    invisible(NULL)
  }
  env$chat_add_message <- function(...) {
    args <- list(...)
    env$.rec$add[[length(env$.rec$add) + 1L]] <- args
    list(id = "msg-stub", current_user_id = args$current_user_id)
  }
  env$chat_generate_title_from_prompt <- function(prompt, max_len = 60) {
    env$.rec$title[[length(env$.rec$title) + 1L]] <- list(prompt = prompt, max_len = max_len)
    "stub-baslik"
  }
  env$chat_simulate_streaming <- function(...) {
    args <- list(...)
    env$.rec$stream[[length(env$.rec$stream) + 1L]] <- args
    invisible(NULL)
  }

  source(file.path(resolve_repo_root_for_tests(), "R", "server_init_chat_runtime.R"),
         encoding = "UTF-8", local = env)
  env
}

testthat::test_that("serverInitChatRuntime dört adlandırılmış kapanış döndürür", {
  env <- .scr_env()
  rt <- env$serverInitChatRuntime(
    session = list(), values = list(), settings_data = list(),
    output = list(), resolve_current_user_id = function() 1L,
    stop_generation = function() FALSE
  )

  testthat::expect_type(rt, "list")
  testthat::expect_setequal(
    names(rt),
    c("reset_chat_state", "add_message", "generate_title_from_prompt",
      "simulate_streaming_stoppable")
  )
  for (fn in rt) testthat::expect_true(is.function(fn))
})

testthat::test_that("reset_chat_state temsilcisi session ve values ile çağrılır", {
  env <- .scr_env()
  sess <- list(tag = "S1")
  vals <- list(tag = "V1")
  rt <- env$serverInitChatRuntime(
    session = sess, values = vals, settings_data = list(),
    output = list(), resolve_current_user_id = function() 1L,
    stop_generation = function() FALSE
  )

  rt$reset_chat_state()

  testthat::expect_length(env$.rec$reset, 1L)
  testthat::expect_identical(env$.rec$reset[[1]]$session$tag, "S1")
  testthat::expect_identical(env$.rec$reset[[1]]$values$tag, "V1")
})

testthat::test_that("add_message kullanıcı kimliğini ÇAĞRI ANINDA canlı çözer (anlık görüntü değil)", {
  env <- .scr_env()
  # Canlı sağlayıcı: her çağrıda değişen kimlik döndürür (SSO geç gelen kimlik senaryosu).
  uid_box <- new.env(parent = emptyenv())
  uid_box$value <- 0L
  provider <- function() uid_box$value

  rt <- env$serverInitChatRuntime(
    session = list(), values = list(), settings_data = list(),
    output = list(), resolve_current_user_id = provider,
    stop_generation = function() FALSE
  )

  # İlk çağrı: kimlik henüz placeholder.
  uid_box$value <- 7L
  rt$add_message("merhaba")
  # İkinci çağrı: kimlik artık gerçek kullanıcı (canlı sağlayıcı yeniden okunur).
  uid_box$value <- 42L
  rt$add_message("tekrar")

  testthat::expect_length(env$.rec$add, 2L)
  testthat::expect_identical(env$.rec$add[[1]]$current_user_id, 7L)
  testthat::expect_identical(env$.rec$add[[2]]$current_user_id, 42L)
})

testthat::test_that("add_message tüm argümanları chat_add_message'a iletir", {
  env <- .scr_env()
  rt <- env$serverInitChatRuntime(
    session = list(s = TRUE), values = list(v = TRUE),
    settings_data = list(d = TRUE), output = list(o = TRUE),
    resolve_current_user_id = function() 99L,
    stop_generation = function() FALSE
  )

  rt$add_message(
    content = "soru", type = "ai", html = "<p>x</p>",
    followups = c("a", "b"), audio_src = "data:audio", audio_voice = "ses1",
    reasoning_content = "akil yurutme"
  )

  testthat::expect_length(env$.rec$add, 1L)
  a <- env$.rec$add[[1]]
  testthat::expect_identical(a$content, "soru")
  testthat::expect_identical(a$type, "ai")
  testthat::expect_identical(a$html, "<p>x</p>")
  testthat::expect_identical(a$followups, c("a", "b"))
  testthat::expect_identical(a$audio_src, "data:audio")
  testthat::expect_identical(a$audio_voice, "ses1")
  testthat::expect_identical(a$reasoning_content, "akil yurutme")
  testthat::expect_identical(a$current_user_id, 99L)
  # session/values/settings_data/output da iletilmeli.
  testthat::expect_true(isTRUE(a$session$s))
  testthat::expect_true(isTRUE(a$values$v))
  testthat::expect_true(isTRUE(a$settings_data$d))
  testthat::expect_true(isTRUE(a$output$o))
})

testthat::test_that("generate_title_from_prompt temsilciye prompt ve max_len iletir", {
  env <- .scr_env()
  rt <- env$serverInitChatRuntime(
    session = list(), values = list(), settings_data = list(),
    output = list(), resolve_current_user_id = function() 1L,
    stop_generation = function() FALSE
  )

  out <- rt$generate_title_from_prompt("Bir başlık metni", max_len = 30)

  testthat::expect_identical(out, "stub-baslik")
  testthat::expect_length(env$.rec$title, 1L)
  testthat::expect_identical(env$.rec$title[[1]]$prompt, "Bir başlık metni")
  testthat::expect_identical(env$.rec$title[[1]]$max_len, 30)
})

testthat::test_that("simulate_streaming_stoppable bağlam ve stop_generation'ı iletir", {
  env <- .scr_env()
  sg <- function() TRUE
  oc <- function(m) m
  os <- function(id) id
  te <- function(text, voice) NULL
  rt <- env$serverInitChatRuntime(
    session = list(s = "SS"), values = list(v = "VV"),
    settings_data = list(d = "DD"), output = list(o = "OO"),
    resolve_current_user_id = function() 1L,
    stop_generation = sg
  )

  rt$simulate_streaming_stoppable(
    full_response = "tam yanit", followups = c("f1"),
    on_complete = oc, on_start = os, tts_engine = te, tts_voice = "v2"
  )

  testthat::expect_length(env$.rec$stream, 1L)
  s <- env$.rec$stream[[1]]
  testthat::expect_identical(s$full_response, "tam yanit")
  testthat::expect_identical(s$followups, c("f1"))
  testthat::expect_identical(s$tts_voice, "v2")
  # Bağlam nesneleri ve stop_generation aynen iletilmeli.
  testthat::expect_identical(s$session$s, "SS")
  testthat::expect_identical(s$values$v, "VV")
  testthat::expect_identical(s$settings_data$d, "DD")
  testthat::expect_identical(s$output$o, "OO")
  testthat::expect_identical(s$stop_generation, sg)
  testthat::expect_identical(s$on_complete, oc)
  testthat::expect_identical(s$on_start, os)
  testthat::expect_identical(s$tts_engine, te)
})
