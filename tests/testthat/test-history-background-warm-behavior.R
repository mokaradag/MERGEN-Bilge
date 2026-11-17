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

# Söyleşi sayısı satır sayısını sınırlamaz: büyük geçmiş sonucu tek geri
# çağrıda biçimlendirilmez, satır dilimleriyle ayrı döngü turlarında işlenir.
# Sonuç (söyleşi içi sıra dahil) tek seferlik biçimlendirmeyle aynıdır.
testthat::test_that("büyük geçmiş sonucu satır dilimleriyle aşamalı biçimlendirilir, sonuç değişmez", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  env <- .source_history_bg_for_test()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_db_chat_readers.R"),
         encoding = "UTF-8", local = env)
  satir <- function(chat, n) data.frame(
    ChatID = rep(chat, n), ChatTitle = rep(paste("Başlık", chat, "çğış"), n),
    MessageTimestamp = as.POSIXct("2026-07-01 10:00:00", tz = "UTC") + seq_len(n),
    Soru = paste0("soru ", chat, "-", seq_len(n)), Cevap = paste0("yanıt ", chat, "-", seq_len(n)),
    PairOrder = seq_len(n), stringsAsFactors = FALSE)
  cerceve <- rbind(satir(3L, 700L), satir(5L, 20L), satir(8L, 600L))
  ids <- c("8", "3", "5", "9")
  beklenen <- env$load_history_rows_batch(ids, user_id = 42L, result = cerceve)

  gercek <- env$load_history_rows_batch
  cagrilar <- integer()
  env$load_history_rows_batch <- function(chat_ids, user_id = NULL, result = NULL) {
    cagrilar <<- c(cagrilar, nrow(result))
    gercek(chat_ids, user_id = user_id, result = result)
  }
  p <- env$history_rows_format_staged(ids, 42L, cerceve)
  testthat::expect_true(promises::is.promise(p))
  # İlk dilimden sonra kalan iş ayrı döngü turlarına bırakılır.
  testthat::expect_identical(cagrilar, 500L)
  sonuc <- NULL
  promises::then(p, onFulfilled = function(v) sonuc <<- v)
  bitis <- Sys.time() + 5
  while (is.null(sonuc) && Sys.time() < bitis) later::run_now(0.05)

  testthat::expect_true(all(cagrilar <= 500L))
  testthat::expect_identical(sum(cagrilar), nrow(cerceve))
  testthat::expect_identical(sonuc, beklenen)
  testthat::expect_identical(sonuc[["9"]], list())
  # Küçük sonuç doğrudan (promise olmadan) biçimlendirilir.
  testthat::expect_identical(env$history_rows_format_staged(ids, 42L, satir(5L, 20L)),
                             gercek(ids, user_id = 42L, result = satir(5L, 20L)))
})
