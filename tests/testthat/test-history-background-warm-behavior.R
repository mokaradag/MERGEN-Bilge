# ==============================================================================
# Dosya Yolu: tests/testthat/test-history-background-warm-behavior.R
# Açıklama: R/module_chat_history_background.R historyBackgroundWarm()
#           fonksiyonunun DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test
#           tarafından çağrılmıyordu.
#
#           Fonksiyon, sohbet kimliklerini batch_size'a göre partilere böler ve
#           her partiyi later::later ile gecikmeli olarak ısıtır. Testlerde
#           delay_sec=0 kullanılır ve later kuyruğu run_now ile boşaltılır.
#           Gerçek reaktif bağlam için shiny::MockShinySession kullanılır;
#           gerçek DB/LLM/tarayıcı GEREKMEZ.
# ==============================================================================

.source_history_bg_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_chat_history_background.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# later kuyruğunu sınırlı sayıda turla boşaltır (sızıntı/sonsuz döngü önlemi).
.drain_later <- function(times = 20L) {
  for (i in seq_len(times)) later::run_now(0.05)
}

testthat::test_that("historyBackgroundWarm boş kimlik listesinde hiçbir iş planlamaz", {
  testthat::skip_if_not_installed("shiny")
  env <- .source_history_bg_for_test()
  rec <- new.env(); rec$calls <- 0L
  session <- shiny::MockShinySession$new()

  out <- env$historyBackgroundWarm(
    session = session,
    chat_ids = character(0),
    chats = list(),
    ensure_history_cache = function(batch, chats) rec$calls <- rec$calls + 1L
  )
  testthat::expect_null(out)
  .drain_later()
  testthat::expect_identical(rec$calls, 0L)
})

testthat::test_that("historyBackgroundWarm kimlikleri batch_size'a göre partiler", {
  testthat::skip_if_not_installed("shiny")
  env <- .source_history_bg_for_test()
  rec <- new.env(); rec$batches <- list()
  session <- shiny::MockShinySession$new()

  env$historyBackgroundWarm(
    session = session,
    chat_ids = letters[1:5],
    chats = list(meta = TRUE),
    ensure_history_cache = function(batch, chats) {
      rec$batches[[length(rec$batches) + 1L]] <- batch
      rec$last_chats <- chats
    },
    batch_size = 2L,
    delay_sec = 0
  )
  .drain_later()

  # 5 kimlik / 2 = 3 parti: (a,b), (c,d), (e).
  testthat::expect_length(rec$batches, 3L)
  testthat::expect_identical(rec$batches[[1]], c("a", "b"))
  testthat::expect_identical(rec$batches[[2]], c("c", "d"))
  testthat::expect_identical(rec$batches[[3]], "e")
  # chats argümanı her partiye olduğu gibi iletilmeli.
  testthat::expect_identical(rec$last_chats, list(meta = TRUE))
})

testthat::test_that("historyBackgroundWarm tüm partiler bitince on_complete'i bir kez çağırır", {
  testthat::skip_if_not_installed("shiny")
  env <- .source_history_bg_for_test()
  rec <- new.env(); rec$done <- 0L
  session <- shiny::MockShinySession$new()

  env$historyBackgroundWarm(
    session = session,
    chat_ids = as.character(1:4),
    chats = NULL,
    ensure_history_cache = function(batch, chats) invisible(NULL),
    batch_size = 2L,
    delay_sec = 0,
    on_complete = function() rec$done <- rec$done + 1L
  )
  .drain_later()
  testthat::expect_identical(rec$done, 1L)
})

testthat::test_that("historyBackgroundWarm kapalı oturumda cache ısıtmaz", {
  testthat::skip_if_not_installed("shiny")
  env <- .source_history_bg_for_test()
  rec <- new.env(); rec$calls <- 0L
  session <- shiny::MockShinySession$new()
  session$close()  # oturum kapatıldı

  env$historyBackgroundWarm(
    session = session,
    chat_ids = letters[1:3],
    chats = list(),
    ensure_history_cache = function(batch, chats) rec$calls <- rec$calls + 1L,
    batch_size = 1L,
    delay_sec = 0
  )
  .drain_later()
  # session$isClosed() TRUE -> hiçbir parti işlenmemeli.
  testthat::expect_identical(rec$calls, 0L)
})

testthat::test_that("historyBackgroundWarm tek partilik küçük listede de çalışır", {
  testthat::skip_if_not_installed("shiny")
  env <- .source_history_bg_for_test()
  rec <- new.env(); rec$batches <- list()
  session <- shiny::MockShinySession$new()

  env$historyBackgroundWarm(
    session = session,
    chat_ids = c("x", "y"),
    chats = list(),
    ensure_history_cache = function(batch, chats) rec$batches[[length(rec$batches) + 1L]] <- batch,
    batch_size = 120L,  # varsayılan büyük parti
    delay_sec = 0
  )
  .drain_later()
  testthat::expect_length(rec$batches, 1L)
  testthat::expect_identical(rec$batches[[1]], c("x", "y"))
})
