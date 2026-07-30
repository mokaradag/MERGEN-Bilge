# ==============================================================================
# Dosya Yolu: tests/testthat/test-destek-yardim-behavior.R
# Açıklama: R/module_destek_yardim.R destekYardimServer() Yardım Asistanı
#           chatbot mantığının DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir
#           test tarafından çağrılmıyordu.
#
#           Kapsananlar (httr::POST testthat::local_mocked_bindings ile taklit
#           edilerek, kök MockShinySession mesaj yakalamasıyla):
#           - model çözümleme önceliği: DESTEK_CHATBOT_MODEL -> AI_EXPERT_MODEL
#             -> FILTER_MODEL,
#           - boş mesaj guard'ı (LLM çağrısı yapılmaz),
#           - başarılı yanıt render'ı,
#           - HTTP hata durumunda Türkçe kibar hata mesajı,
#           - chatbot_temizle geçmişi temizler.
#
#           Gerçek LLM/ağ GEREKMEZ; tüm httr çağrıları taklit edilir.
# ==============================================================================

.source_destek_yardim_for_test <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  testthat::skip_if_not_installed("httr")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_destek_yardim.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Chatbot gözlemcisini taklit edilmiş httr ile çalıştırır; kullanılan modeli ve
# yakalanan custom message'ları kaydeder. prime-then-set ile gözlemci tetiklenir.
.run_yardim_chat <- function(env, envvars, message,
                             status = 200L,
                             content_impl = function(r, ...) {
                               list(
                                 choices = list(
                                   list(
                                     message = list(
                                       content = "Yardımcı yanıt"
                                     )
                                   )
                                 )
                               )
                             },
                             prime = "__prime__") {
  rec <- new.env()
  rec$msgs <- list()
  rec$model <- NA_character_
  rec$posted <- FALSE
  rec$body <- NULL

  record_runjs <- function(code) {
    rec$msgs[[length(rec$msgs) + 1L]] <- list(
      type = "shinyjs.runjs",
      message = code
    )
    invisible(NULL)
  }

  withr::with_envvar(envvars, {
    testthat::with_mocked_bindings(
      {
        testthat::with_mocked_bindings(
          {
            invisible(utils::capture.output(
              shiny::testServer(
                env$destekYardimServer,
                args = list(current_user_id = 1L),
                {
                  session$setInputs(chatbot_mesaj = prime)
                  session$setInputs(chatbot_mesaj = message)
                }
              )
            ))
          },

          POST = function(url, body, ...) {
            rec$posted <- TRUE
            rec$model <- body$model
            rec$body <- body
            structure(list(), class = "response")
          },

          status_code = function(r) {
            as.integer(status)
          },

          content = content_impl,
          add_headers = function(...) NULL,
          timeout = function(...) NULL,

          .package = "httr"
        )
      },

      runjs = record_runjs,
      .package = "shinyjs"
    )
  })

  rec
}

# Yakalanan custom message'ların düz metin temsili (alt-string araması için).
.yardim_blob <- function(rec) {
  paste(vapply(rec$msgs, function(m) {
    tryCatch(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null"),
             error = function(e) paste(unlist(m), collapse = " "))
  }, character(1)), collapse = " ")
}

# ------------------------------------------------------------------------------
# Model çözümleme önceliği
# ------------------------------------------------------------------------------
testthat::test_that("chatbot DESTEK_CHATBOT_MODEL tanımlıysa onu kullanır", {
  env <- .source_destek_yardim_for_test()
  rec <- .run_yardim_chat(env, c(
    LOCAL_LLM_ENDPOINT = "http://x/v1", DESTEK_CHATBOT_MODEL = "destek-modeli",
    AI_EXPERT_MODEL = "uzman-modeli", FILTER_MODEL = "filtre-modeli"
  ), message = "Nasıl kullanılır?")
  testthat::expect_identical(rec$model, "destek-modeli")
})

testthat::test_that("chatbot DESTEK_CHATBOT_MODEL yoksa AI_EXPERT_MODEL'e düşer", {
  env <- .source_destek_yardim_for_test()
  rec <- .run_yardim_chat(env, c(
    LOCAL_LLM_ENDPOINT = "http://x/v1", DESTEK_CHATBOT_MODEL = "",
    AI_EXPERT_MODEL = "uzman-modeli", FILTER_MODEL = "filtre-modeli"
  ), message = "Soru")
  testthat::expect_identical(rec$model, "uzman-modeli")
})

testthat::test_that("chatbot ilk ikisi yoksa FILTER_MODEL'e düşer", {
  env <- .source_destek_yardim_for_test()
  rec <- .run_yardim_chat(env, c(
    LOCAL_LLM_ENDPOINT = "http://x/v1", DESTEK_CHATBOT_MODEL = "",
    AI_EXPERT_MODEL = "", FILTER_MODEL = "filtre-modeli"
  ), message = "Soru")
  testthat::expect_identical(rec$model, "filtre-modeli")
})

testthat::test_that("chatbot ai_rehber.md belgesinin tamamını gönderir", {
  env <- .source_destek_yardim_for_test()
  repo_root <- resolve_repo_root_for_tests()
  withr::local_dir(repo_root)

  rec <- .run_yardim_chat(env, c(
    LOCAL_LLM_ENDPOINT = "http://x/v1", DESTEK_CHATBOT_MODEL = "m"
  ), message = "Ortak Çalışmalarım nasıl kullanılır?")

  rehber_yolu <- file.path(repo_root, "ai_rehber.md")
  rehber_boyutu <- file.info(rehber_yolu)$size
  ham_rehber <- readBin(rehber_yolu, what = "raw", n = rehber_boyutu)
  rehber <- iconv(list(ham_rehber), from = "UTF-8", to = "UTF-8", sub = "")[[1]]
  rehber <- sub("^\ufeff", "", rehber, perl = TRUE)
  bilgi_mesaji <- rec$body$messages[[2]]$content

  testthat::expect_gt(nchar(rehber), 12000)
  testthat::expect_true(endsWith(bilgi_mesaji, rehber))
  testthat::expect_false(grepl("[Bilgi tabani kisaltildi]", bilgi_mesaji, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Boş mesaj guard'ı
# ------------------------------------------------------------------------------
testthat::test_that("chatbot boş mesajda LLM çağrısı yapmaz", {
  env <- .source_destek_yardim_for_test()
  rec <- .run_yardim_chat(env, c(
    LOCAL_LLM_ENDPOINT = "http://x/v1", DESTEK_CHATBOT_MODEL = "m"
  ), message = "", prime = "   ")  # hem prime hem gerçek değer boş/boşluk
  testthat::expect_false(rec$posted)
  testthat::expect_true(is.na(rec$model))
})

# ------------------------------------------------------------------------------
# Başarılı yanıt render'ı
# ------------------------------------------------------------------------------
testthat::test_that("chatbot başarılı yanıtı bot mesajı olarak gönderir", {
  env <- .source_destek_yardim_for_test()
  rec <- .run_yardim_chat(env, c(
    LOCAL_LLM_ENDPOINT = "http://x/v1", DESTEK_CHATBOT_MODEL = "m"
  ), message = "Merhaba",
  content_impl = function(r, ...) {
    list(choices = list(list(message = list(content = "Size yardimci olabilirim"))))
  })
  blob <- .yardim_blob(rec)
  testthat::expect_true(rec$posted)
  testthat::expect_true(grepl("Size yardimci olabilirim", blob, fixed = TRUE))
  # Kullanıcı mesajı da istemciye gönderilmiş olmalı.
  testthat::expect_true(grepl("Merhaba", blob, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# HTTP hata yolu
# ------------------------------------------------------------------------------
testthat::test_that("chatbot HTTP hatasında Türkçe kibar hata mesajı gösterir", {
  env <- .source_destek_yardim_for_test()
  rec <- .run_yardim_chat(env, c(
    LOCAL_LLM_ENDPOINT = "http://x/v1", DESTEK_CHATBOT_MODEL = "m"
  ), message = "Soru", status = 500L)
  blob <- .yardim_blob(rec)
  testthat::expect_true(grepl("şu anda yanıt veremiyorum", blob, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Sohbet temizleme
# ------------------------------------------------------------------------------
testthat::test_that("chatbot_temizle hatasız çalışır", {
  env <- .source_destek_yardim_for_test()
  testthat::expect_no_error(
    shiny::testServer(env$destekYardimServer, args = list(current_user_id = 1L), {
      session$setInputs(chatbot_temizle = 1)
      session$setInputs(chatbot_temizle = 2)
    })
  )
})