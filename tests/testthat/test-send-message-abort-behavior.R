# ==============================================================================
# Dosya Yolu: tests/testthat/test-send-message-abort-behavior.R
# Açıklama: R/helpers_send_message_core.R içindeki mergen_abort_send_message
#           yardımcısının DAVRANIŞSAL testleri. Mevcut
#           test-send-message-request-lifecycle-contract.R cleanup/typing-wrapper
#           çekirdeğini kapsar; abort sarmalayıcısı (cleanup + toast + request-
#           kapsamlı wrapper kaldırma) doğrudan çağrılarak test edilmiyordu:
#             - cleanup çalışır: values$typing <- FALSE, reset_chat_state_fn() çağrılır
#             - toast mesajı varsa showToast çağrılır, yoksa çağrılmaz
#             - request-kapsamlı koruma: bayat req_id newer wrapper'ı kaldırmaz
#             - remove_typing_wrapper = FALSE iken wrapper kaldırılmaz
#           Shiny/DB/LLM/ağ GEREKMEZ; remove_ui ve reset enjekte edilir, showToast
#           geçici stub ile yakalanır ve sonunda eski haline döndürülür.
# ==============================================================================

.abort_source_once <- function() {
  root <- resolve_repo_root_for_tests()
  if (exists("mergen_abort_send_message", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  # Çekirdek dosya, request lifecycle yardımcısı yoksa onu göreli yolla
  # safe_source ile yüklemeye çalışır; bu testthat çalışma dizininde başarısız
  # olabileceği için bağımlılığı önce mutlak yolla yüklüyoruz.
  if (!exists("safe_source", envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "utils_safe_source.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  if (!exists("mergen_new_send_message_request_id", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "helpers_send_message_request_lifecycle.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  source(
    file.path(root, "R", "helpers_send_message_core.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

# Yakalanan toast'ları tutan ortam.
.abort_toast_box <- new.env(parent = emptyenv())

# showToast'ı yakalayıcı stub ile değiştirir; test bitince eski hale döndürür.
.abort_install_toast <- function(envir = parent.frame()) {
  .abort_toast_box$list <- list()
  had <- exists("showToast", envir = globalenv(), inherits = FALSE)
  old <- if (had) get("showToast", envir = globalenv(), inherits = FALSE) else NULL
  assign(
    "showToast",
    function(session, message, type = "warning", ...) {
      idx <- length(.abort_toast_box$list) + 1L
      .abort_toast_box$list[[idx]] <- list(msg = message, type = type)
      invisible(NULL)
    },
    envir = globalenv()
  )
  withr::defer(
    {
      if (had) {
        assign("showToast", old, envir = globalenv())
      } else if (exists("showToast", envir = globalenv(), inherits = FALSE)) {
        rm("showToast", envir = globalenv())
      }
    },
    envir = envir
  )
  invisible()
}

# Sayaçlı remove_ui stub'ı üretir.
.abort_remove_counter <- function() {
  box <- new.env(parent = emptyenv())
  box$n <- 0L
  box$fn <- function(selector = NULL, immediate = FALSE, ...) {
    box$n <- box$n + 1L
    invisible(NULL)
  }
  box
}

# ------------------------------------------------------------------------------
# Temel abort: cleanup + toast
# ------------------------------------------------------------------------------
testthat::test_that("mergen_abort_send_message cleanup yapar ve toast mesajını gönderir", {
  .abort_source_once()
  .abort_install_toast()

  vals <- new.env(parent = emptyenv())
  vals$typing <- TRUE
  reset_box <- new.env(parent = emptyenv())
  reset_box$n <- 0L
  remover <- .abort_remove_counter()

  mergen_abort_send_message(
    session = list(),
    values = vals,
    reset_chat_state_fn = function() reset_box$n <- reset_box$n + 1L,
    toast_message = "Üretim durduruldu",
    toast_type = "warning",
    remove_ui_fn = remover$fn
  )

  testthat::expect_false(vals$typing)
  testthat::expect_identical(reset_box$n, 1L)
  testthat::expect_identical(remover$n, 1L)
  testthat::expect_length(.abort_toast_box$list, 1L)
  testthat::expect_identical(.abort_toast_box$list[[1]]$msg, "Üretim durduruldu")
  testthat::expect_identical(.abort_toast_box$list[[1]]$type, "warning")
})

testthat::test_that("mergen_abort_send_message toast mesajı yoksa showToast çağırmaz", {
  .abort_source_once()
  .abort_install_toast()

  vals <- new.env(parent = emptyenv())
  vals$typing <- TRUE
  remover <- .abort_remove_counter()

  mergen_abort_send_message(
    session = list(),
    values = vals,
    reset_chat_state_fn = function() invisible(NULL),
    toast_message = NULL,
    remove_ui_fn = remover$fn
  )

  testthat::expect_length(.abort_toast_box$list, 0L)
  # cleanup yine de çalışır
  testthat::expect_false(vals$typing)
})

# ------------------------------------------------------------------------------
# Request-kapsamlı wrapper koruması
# ------------------------------------------------------------------------------
testthat::test_that("mergen_abort_send_message bayat req_id ile newer wrapper'ı kaldırmaz", {
  .abort_source_once()
  .abort_install_toast()

  vals <- new.env(parent = emptyenv())
  vals$typing <- TRUE
  remover <- .abort_remove_counter()

  # Aktif request 'current'; bu çağrı 'stale' için -> wrapper kaldırılmamalı.
  mergen_abort_send_message(
    session = list(),
    values = vals,
    reset_chat_state_fn = function() invisible(NULL),
    toast_message = "x",
    remove_ui_fn = remover$fn,
    active_request_id = function() "current",
    req_id = "stale"
  )
  testthat::expect_identical(remover$n, 0L)
  # cleanup'ın diğer kısmı (typing reset) yine çalışır
  testthat::expect_false(vals$typing)
})

testthat::test_that("mergen_abort_send_message eşleşen req_id ile wrapper'ı kaldırır", {
  .abort_source_once()
  .abort_install_toast()

  remover <- .abort_remove_counter()
  mergen_abort_send_message(
    session = list(),
    values = new.env(parent = emptyenv()),
    reset_chat_state_fn = function() invisible(NULL),
    toast_message = "x",
    remove_ui_fn = remover$fn,
    active_request_id = function() "match",
    req_id = "match"
  )
  testthat::expect_identical(remover$n, 1L)
})

testthat::test_that("mergen_abort_send_message remove_typing_wrapper = FALSE iken wrapper kaldırmaz", {
  .abort_source_once()
  .abort_install_toast()

  remover <- .abort_remove_counter()
  mergen_abort_send_message(
    session = list(),
    values = new.env(parent = emptyenv()),
    reset_chat_state_fn = function() invisible(NULL),
    toast_message = "x",
    remove_ui_fn = remover$fn,
    remove_typing_wrapper = FALSE
  )
  testthat::expect_identical(remover$n, 0L)
})
