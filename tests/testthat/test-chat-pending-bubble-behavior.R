# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-pending-bubble-behavior.R
# Açıklama: İyimser (bekleyen) istem balonu sözleşmesi. İstemci istemi sunucu
#           turunu beklemeden çizer; sunucu her istem için "kabul"/"ret"
#           kararını istemci kimliğiyle, işleyicinin HER çıkış yolunda tam bir
#           kez bildirir. Kabul ölçütü kullanıcı mesajının gerçekten
#           eklenmesidir (mesaj eklendikten sonraki hata "ret" değildir) ve
#           kabulde eklenen mesajın kimliği döner; hız sınırı/uzunluk/erken ret
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

.istem_sunucusu <- function(env, kayit, mesaj_ekle, gonder = NULL) {
  function(input, output, session) {
    values <- shiny::reactiveValues(messages = kayit$onceki %||% list(), is_sending = FALSE, typing = FALSE)
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
        if (is.function(gonder)) return(gonder(text, values))
        if (isTRUE(mesaj_ekle)) {
          values$messages <- append(shiny::isolate(values$messages),
                                    list(list(id = "msg_42", type = "user", content = text)))
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
  testthat::expect_identical(sonuc[[1]]$message,
                             list(client_id = "istem_abc_1", durum = "kabul", mesaj_id = "msg_42"))
})

.gozlemci_hatalari <- function(expr) {
  hatalar <- character()
  withCallingHandlers(
    tryCatch(expr, error = function(e) hatalar <<- c(hatalar, conditionMessage(e))),
    warning = function(w) {
      hatalar <<- c(hatalar, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  hatalar
}

.yeni_kayit <- function() {
  kayit <- new.env(); kayit$mesajlar <- list(); kayit$gonderilen <- character(); kayit$toast <- character()
  kayit
}

testthat::test_that("mesaj eklendikten sonra hata veren gönderim 'ret' değil 'kabul' bildirilir", {
  testthat::skip_if_not_installed("shiny")
  kayit <- .yeni_kayit()
  env <- .istem_ortami(kayit)
  # Önceden var olan mesaj, kimlik tabanlı tespitin eski mesajı saymadığını da doğrular.
  kayit$onceki <- list(list(id = "msg_1", type = "user", content = "eski"))
  gonder <- function(text, values) {
    values$messages <- append(shiny::isolate(values$messages),
                              list(list(id = "msg_7", type = "user", content = text)))
    stop("model hazırlığı başarısız (test)")
  }
  hata <- .gozlemci_hatalari(shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = FALSE, gonder = gonder), {
    session$setInputs(send_prompt_from_js = list(text = "eklendi sonra hata", nonce = 6, client_id = "istem_hata_1"))
  }))
  sonuc <- .istem_sonuclari(kayit)
  testthat::expect_length(sonuc, 1L)
  testthat::expect_identical(sonuc[[1]]$message$durum, "kabul")
  testthat::expect_identical(sonuc[[1]]$message$mesaj_id, "msg_7")
  # Hata yutulmaz; yukarı taşınır.
  testthat::expect_true(any(grepl("model hazırlığı başarısız", hata, fixed = TRUE)))
})

testthat::test_that("mesaj eklemeden hata veren gönderim tam bir kez 'ret' bildirir", {
  testthat::skip_if_not_installed("shiny")
  kayit <- .yeni_kayit()
  env <- .istem_ortami(kayit)
  gonder <- function(text, values) stop("erken hata (test)")
  hata <- .gozlemci_hatalari(shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = FALSE, gonder = gonder), {
    session$setInputs(send_prompt_from_js = list(text = "erken hata", nonce = 7, client_id = "istem_hata_2"))
  }))
  testthat::expect_true(any(grepl("erken hata", hata, fixed = TRUE)))
  sonuc <- .istem_sonuclari(kayit)
  testthat::expect_length(sonuc, 1L)
  testthat::expect_identical(sonuc[[1]]$message, list(client_id = "istem_hata_2", durum = "ret"))
})

testthat::test_that("hız sınırı denetimi hata verse bile istem sonucu bildirilir (kilit kalmaz)", {
  testthat::skip_if_not_installed("shiny")
  kayit <- .yeni_kayit()
  env <- .istem_ortami(kayit)
  env$check_rate_limit <- function(...) stop("hız sınırı deposu okunamadı (test)")
  hata <- .gozlemci_hatalari(shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = TRUE), {
    session$setInputs(send_prompt_from_js = list(text = "kilit", nonce = 8, client_id = "istem_hata_3"))
  }))
  testthat::expect_true(any(grepl("hız sınırı deposu", hata, fixed = TRUE)))
  testthat::expect_length(kayit$gonderilen, 0L)
  sonuc <- .istem_sonuclari(kayit)
  testthat::expect_length(sonuc, 1L)
  testthat::expect_identical(sonuc[[1]]$message$durum, "ret")
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

testthat::test_that("aynı istemci kimliğiyle yeniden teslim edilen istem ikinci kez işlenmez, ilk sonuç yinelenir", {
  testthat::skip_if_not_installed("shiny")
  kayit <- .yeni_kayit()
  env <- .istem_ortami(kayit)
  shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = TRUE), {
    session$setInputs(send_prompt_from_js = list(text = "tekrar teslim", nonce = 10, client_id = "istem_tekrar"))
    session$setInputs(send_prompt_from_js = list(text = "tekrar teslim", nonce = 11, client_id = "istem_tekrar"))
    # Farklı kimlikli yeni istem normal işlenir.
    session$setInputs(send_prompt_from_js = list(text = "yeni istem", nonce = 12, client_id = "istem_yeni"))
  })
  testthat::expect_identical(kayit$gonderilen, c("tekrar teslim", "yeni istem"))
  sonuc <- .istem_sonuclari(kayit)
  testthat::expect_length(sonuc, 3L)
  testthat::expect_identical(sonuc[[2]]$message, sonuc[[1]]$message)
  testthat::expect_identical(sonuc[[1]]$message$durum, "kabul")
})

testthat::test_that("boşlukla şişirilmiş istem uzunluk sınırını aşamaz; sınır içindeki metin aynen gönderilir", {
  testthat::skip_if_not_installed("shiny")
  kayit <- .yeni_kayit()
  env <- .istem_ortami(kayit)
  shiny::testServer(.istem_sunucusu(env, kayit, mesaj_ekle = TRUE), {
    session$setInputs(send_prompt_from_js = list(text = paste0("a", strrep(" ", 20005)), nonce = 20, client_id = "istem_bosluk"))
    session$setInputs(send_prompt_from_js = list(text = "  sınır içinde çğış  ", nonce = 21, client_id = "istem_normal"))
  })
  testthat::expect_identical(kayit$gonderilen, "  sınır içinde çğış  ")
  sonuc <- .istem_sonuclari(kayit)
  testthat::expect_identical(sonuc[[1]]$message$durum, "ret")
  testthat::expect_identical(sonuc[[2]]$message$durum, "kabul")
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
