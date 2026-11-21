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
  # Önbellek politikası yardımcıları ayrı dosyadadır (manifestte hemen sonra).
  source(file.path(resolve_repo_root_for_tests(), "R", "module_chat_history_cache_policy.R"),
         encoding = "UTF-8", local = env)
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
  # Döngü her yoklamada EN ÇOK bir geri çağrı çalıştırır: her geri çağrı en çok
  # bir dilim biçimlendirmelidir (iki dilim arka arkaya işlenmez).
  bitis <- Sys.time() + 5
  while (is.null(sonuc) && Sys.time() < bitis) {
    once <- length(cagrilar)
    later::run_now(0.05, all = FALSE)
    testthat::expect_lte(length(cagrilar) - once, 1L)
  }
  testthat::expect_identical(cagrilar, c(500L, 500L, 320L))

  testthat::expect_true(all(cagrilar <= 500L))
  testthat::expect_identical(sum(cagrilar), nrow(cerceve))
  testthat::expect_identical(sonuc, beklenen)
  testthat::expect_identical(sonuc[["9"]], list())
  # Küçük sonuç doğrudan (promise olmadan) biçimlendirilir.
  testthat::expect_identical(env$history_rows_format_staged(ids, 42L, satir(5L, 20L)),
                             gercek(ids, user_id = 42L, result = satir(5L, 20L)))
})

testthat::test_that("geçmiş hazırlığı bayatlayınca kalan dilimler biçimlendirilmez ve söz NULL ile kapanır", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  env <- .source_history_bg_for_test()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_db_chat_readers.R"),
         encoding = "UTF-8", local = env)
  cerceve <- data.frame(
    ChatID = rep(3L, 1600L), ChatTitle = "Başlık çğış",
    MessageTimestamp = as.POSIXct("2026-07-01 10:00:00", tz = "UTC") + seq_len(1600L),
    Soru = "soru", Cevap = "yanıt", PairOrder = seq_len(1600L), stringsAsFactors = FALSE)
  gercek <- env$load_history_rows_batch
  cagrilar <- integer()
  env$load_history_rows_batch <- function(chat_ids, user_id = NULL, result = NULL) {
    cagrilar <<- c(cagrilar, nrow(result))
    gercek(chat_ids, user_id = user_id, result = result)
  }
  gecerli_mi <- TRUE
  p <- env$history_rows_format_staged("3", 42L, cerceve, gecerli = function() gecerli_mi)
  testthat::expect_identical(cagrilar, 500L)
  # Sahip değişti: kalan üç dilim olay döngüsünde işlenmez.
  gecerli_mi <- FALSE
  sonuc <- "bekleniyor"
  promises::then(p, onFulfilled = function(v) sonuc <<- v)
  bitis <- Sys.time() + 5
  while (identical(sonuc, "bekleniyor") && Sys.time() < bitis) later::run_now(0.05)
  testthat::expect_null(sonuc)
  testthat::expect_identical(cagrilar, 500L)
})

testthat::test_that("yeniden doğrulama yalnızca ilk sayfanın yaşlı kayıtlarını bayat işaretler", {
  env <- .source_history_bg_for_test()
  simdi <- as.POSIXct("2026-07-01 12:00:00", tz = "UTC")
  kayit <- function(okuma, soru = "s") list(rows = list(list(Soru = soru)), stamp = "d", okuma = okuma)
  onbellek <- list("1" = kayit(simdi - 120, "bir"), "2" = kayit(simdi - 5), "3" = kayit(simdi + 300, "üç"),
                   "4" = list(rows = list(list(Soru = "dört")), stamp = "d"), "5" = kayit(simdi - 999))
  sonuc <- env$history_mark_stale_for_revalidation(onbellek, c("1", "2", "3", "4"), 60, simdi = simdi)
  # Yaşlı, saati geri alınmış (gelecekte) ve okuma zamanı olmayan kayıtlar bayat;
  # satırların her biri aynen korunur.
  for (id in c("1", "3", "4")) {
    testthat::expect_null(sonuc[[id]]$stamp)
    testthat::expect_identical(sonuc[[id]]$rows, onbellek[[id]]$rows, info = id)
  }
  # Yalnızca damgası gerçekten düşürülenler bildirilir.
  testthat::expect_identical(attr(sonuc, "temizlenen"), c("1", "3", "4"))
  # Taze kayıt ve ilk sayfa dışındaki kayıt dokunulmaz.
  testthat::expect_identical(sonuc[["2"]]$stamp, "d")
  testthat::expect_identical(sonuc[["5"]]$stamp, "d")
})

testthat::test_that("açık geçersizleştirme aynı zincirde yeniden okumaya izin verir; diğer denemeler korunur", {
  env <- .source_history_bg_for_test()
  isitma <- new.env()
  isitma$zincir <- c("1" = "d1", "2" = "d2", "3" = "d3")
  isitma$planli <- c("2", "3")
  env$history_allow_reread(isitma, c("2", "9"))
  testthat::expect_identical(isitma$zincir, c("1" = "d1", "3" = "d3"))
  testthat::expect_identical(isitma$planli, "3")
  env$history_allow_reread(isitma, character())
  testthat::expect_identical(names(isitma$zincir), c("1", "3"))
})

testthat::test_that("okumadan sonra değişen liste başlığı özgün değerine dönse de yerel işaretli kalır", {
  env <- .source_history_bg_for_test()
  onbellek <- list("1" = list(rows = list(), liste_baslik = "Eski"), "2" = list(rows = list(), liste_baslik = "Aynı"))
  sohbetler <- list("1" = list(title = "Yeni"), "2" = list(title = "Aynı"))
  sonuc <- env$history_mark_local_titles(onbellek, sohbetler)
  testthat::expect_true(isTRUE(sonuc[["1"]]$baslik_yerel))
  testthat::expect_null(sonuc[["2"]]$baslik_yerel)
  sohbetler[["1"]]$title <- "Eski"
  testthat::expect_true(isTRUE(env$history_mark_local_titles(sonuc, sohbetler)[["1"]]$baslik_yerel))
  # Değişiklik yoksa önbellek aynen döner (gereksiz yayın olmaz).
  testthat::expect_identical(env$history_mark_local_titles(onbellek[2], sohbetler[2]), onbellek[2])
})

testthat::test_that("en yeni söyleşi seçimi liste konumuna değil etkinliğe göre yapılır; eşitlikte sıra korunur", {
  env <- .source_history_bg_for_test()
  z <- as.POSIXct("2026-07-01 10:00:00", tz = "UTC")
  sohbetler <- list("1" = list(last_message_timestamp = z), "2" = list(last_message_timestamp = z),
                    "61" = list(last_message_timestamp = z + 3600), "9" = list(timestamp = z - 60),
                    "x" = list())
  testthat::expect_identical(env$history_ids_by_activity(names(sohbetler), sohbetler), c("61", "1", "2", "9", "x"))
  testthat::expect_identical(env$history_ids_by_activity("5", list()), "5")
})
