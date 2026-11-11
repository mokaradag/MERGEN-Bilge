# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-pending-bubble-behavior.R
# Açıklama: İyimser (bekleyen) istem balonu sözleşmesi. İstemci istemi sunucu
#           turunu beklemeden çizer; sunucu her istem için "kabul"/"ret"
#           kararını istemci kimliğiyle geri bildirir. Kabul ölçütü kullanıcı
#           mesajının gerçekten eklenmesidir; hız sınırı/uzunluk/erken ret
#           yolları "ret" döner ve send_message çağrılmaz. İstemci davranışı
#           gerçek input_handlers.js ile Node üzerinde doğrulanır.
# ==============================================================================

.istem_ortami <- function(kayit, hiz_siniri_gecer = TRUE, mesaj_ekle = TRUE) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$resolve_effective_user_id <- function(...) 7L
  env$check_rate_limit <- function(...) hiz_siniri_gecer
  env$check_global_rate_limit <- function(...) list(allowed = TRUE, message = "")
  env$showToast <- function(session, message, type = "info", ...) {
    kayit$toast <- c(kayit$toast, message)
  }
  source(file.path(resolve_repo_root_for_tests(), "R", "server_observers_chat_input.R"),
         encoding = "UTF-8", local = env)
  env
}

.istem_sunucusu <- function(env, kayit, mesaj_ekle) {
  function(input, output, session) {
    values <- shiny::reactiveValues(messages = list(), is_sending = FALSE, typing = FALSE)
    yakalayan <- list(
      sendCustomMessage = function(type, message) {
        kayit$mesajlar[[length(kayit$mesajlar) + 1L]] <- list(type = type, message = message)
      },
      userData = session$userData, token = "test"
    )
    env$chatInputObserversInit(
      input = input, session = yakalayan, values = values, settings_data = list(),
      stop_generation = shiny::reactiveVal(FALSE), active_request_id = shiny::reactiveVal(NULL),
      reset_chat_state = function() NULL,
      send_message = function(text) {
        kayit$gonderilen <- c(kayit$gonderilen, text)
        if (isTRUE(mesaj_ekle)) {
          values$messages <- append(shiny::isolate(values$messages), list(list(type = "user", content = text)))
        }
      },
      current_user_id = 7L, file_manager_data = NULL, session_files = shiny::reactiveVal(list()),
      file_to_add = shiny::reactiveVal(NULL),
      stt_data = list(start_session = function() NULL, final_text = shiny::reactiveVal(""))
    )
  }
}

.istem_sonuclari <- function(kayit) {
  Filter(function(m) identical(m$type, "mergenIstemSonucu"), kayit$mesajlar)
}

testthat::test_that("kabul edilen istem istemci kimliğiyle 'kabul' olarak bildirilir", {
  testthat::skip_if_not_installed("shiny")
  kayit <- new.env(); kayit$mesajlar <- list(); kayit$gonderilen <- character(); kayit$toast <- character()
  env <- .istem_ortami(kayit)
  shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = TRUE), {
    session$setInputs(send_prompt_from_js = list(text = "Merhaba çğış", nonce = 1, client_id = "istem_abc_1"))
  })
  sonuc <- .istem_sonuclari(kayit)
  testthat::expect_identical(kayit$gonderilen, "Merhaba çğış")
  testthat::expect_length(sonuc, 1L)
  testthat::expect_identical(sonuc[[1]]$message, list(client_id = "istem_abc_1", durum = "kabul"))
})

testthat::test_that("mesaj eklemeden dönen gönderim 'ret' olarak bildirilir", {
  testthat::skip_if_not_installed("shiny")
  kayit <- new.env(); kayit$mesajlar <- list(); kayit$gonderilen <- character(); kayit$toast <- character()
  env <- .istem_ortami(kayit)
  shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = FALSE), {
    session$setInputs(send_prompt_from_js = list(text = "erken ret", nonce = 2, client_id = "istem_abc_2"))
  })
  testthat::expect_identical(.istem_sonuclari(kayit)[[1]]$message$durum, "ret")
})

testthat::test_that("hız sınırı ve uzunluk retleri send_message çağırmadan 'ret' döner", {
  testthat::skip_if_not_installed("shiny")
  kayit <- new.env(); kayit$mesajlar <- list(); kayit$gonderilen <- character(); kayit$toast <- character()
  env <- .istem_ortami(kayit, hiz_siniri_gecer = FALSE)
  shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = TRUE), {
    session$setInputs(send_prompt_from_js = list(text = "hızlı", nonce = 3, client_id = "istem_hiz"))
  })
  testthat::expect_length(kayit$gonderilen, 0L)
  testthat::expect_identical(.istem_sonuclari(kayit)[[1]]$message$durum, "ret")

  kayit2 <- new.env(); kayit2$mesajlar <- list(); kayit2$gonderilen <- character(); kayit2$toast <- character()
  env2 <- .istem_ortami(kayit2)
  shiny::testServer(.istem_sunucusu(env2, kayit2, mesaj_ekle = TRUE), {
    session$setInputs(send_prompt_from_js = list(text = strrep("a", 20001), nonce = 4, client_id = "istem_uzun"))
  })
  testthat::expect_length(kayit2$gonderilen, 0L)
  testthat::expect_identical(.istem_sonuclari(kayit2)[[1]]$message$durum, "ret")
})

testthat::test_that("geçersiz istemci kimliği geri yansıtılmaz ama gönderim çalışır", {
  testthat::skip_if_not_installed("shiny")
  kayit <- new.env(); kayit$mesajlar <- list(); kayit$gonderilen <- character(); kayit$toast <- character()
  env <- .istem_ortami(kayit)
  shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = TRUE), {
    session$setInputs(send_prompt_from_js = list(text = "kimliksiz", nonce = 5, client_id = "<script>x</script>"))
  })
  testthat::expect_identical(kayit$gonderilen, "kimliksiz")
  testthat::expect_length(.istem_sonuclari(kayit), 0L)
})

testthat::test_that("bekleyen istem balonu istemci davranışı gerçek JavaScript ile korunur", {
  node <- Sys.which("node")
  testthat::skip_if(!nzchar(node), "Node kullanılamıyor")
  script <- file.path(resolve_repo_root_for_tests(), "tests", "scripts", "chat_pending_bubble_regressions.js")
  out <- suppressWarnings(system2(node, shQuote(script), stdout = TRUE, stderr = TRUE))
  durum <- attr(out, "status") %||% 0L
  testthat::expect_identical(as.integer(durum), 0L, info = paste(out, collapse = "\n"))
  testthat::expect_true(any(grepl("chat_pending_bubble_regressions: OK", out, fixed = TRUE)))
})
