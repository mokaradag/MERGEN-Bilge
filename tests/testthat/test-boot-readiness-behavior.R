# ==============================================================================
# Dosya Yolu: tests/testthat/test-boot-readiness-behavior.R
# Açıklama: R/module_boot_readiness.R açılış hazır olma koordinatörünün
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           bootReadinessInit() düz bir karakter vektörü üzerinde çalışan
#           kapanışlar (mark/is_ready/done/required) döndürür. Reaktif bağlam
#           GEREKMEZ; mark() istemciye "bootReadinessCheckpoint" mesajı gönderir.
#           Bu testler mesajları kaydeden sahte bir session ile davranışı
#           doğrular. Ağ/DB/LLM/tarayıcı GEREKMEZ.
# ==============================================================================

.source_boot_readiness_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_boot_readiness.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# bootReadinessCheckpoint mesajlarını kaydeden sahte session.
.fake_boot_session <- function(send_impl = NULL) {
  rec <- new.env()
  rec$msgs <- list()
  list(
    sendCustomMessage = function(type, message) {
      rec$msgs[[length(rec$msgs) + 1L]] <- list(type = type, message = message)
      if (is.function(send_impl)) send_impl(type, message)
      invisible(TRUE)
    },
    rec = rec
  )
}

# ------------------------------------------------------------------------------
# Varsayılan yapı
# ------------------------------------------------------------------------------
testthat::test_that("bootReadinessInit beklenen 6 zorunlu kontrol noktasını döndürür", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess)

  testthat::expect_identical(
    ctrl$required,
    c("auth_ready", "saved_chats_preview_ready", "file_index_ready",
      "character_media_ready", "welcome_client_ready", "management_pages_ready")
  )
  # Henüz hiçbir nokta işaretlenmedi.
  testthat::expect_identical(ctrl$done(), character(0))
  testthat::expect_false(ctrl$is_ready())
})

testthat::test_that("bootReadinessInit özel zorunlu liste kabul eder", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess, required = c("a", "b"))
  testthat::expect_identical(ctrl$required, c("a", "b"))
  testthat::expect_false(ctrl$is_ready())
})

# ------------------------------------------------------------------------------
# mark() geçersiz anahtarlar
# ------------------------------------------------------------------------------
testthat::test_that("mark geçersiz anahtarda FALSE döner, done'a eklemez ve mesaj göndermez", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess, required = c("a", "b"))

  testthat::expect_false(ctrl$mark(NULL))
  testthat::expect_false(ctrl$mark(character(0)))
  testthat::expect_false(ctrl$mark(c("a", "b")))   # uzunluk != 1
  testthat::expect_false(ctrl$mark(""))            # boş dize

  testthat::expect_identical(ctrl$done(), character(0))
  testthat::expect_length(sess$rec$msgs, 0L)
})

# ------------------------------------------------------------------------------
# mark() geçerli akış
# ------------------------------------------------------------------------------
testthat::test_that("mark geçerli anahtarı işaretler ve doğru payload gönderir", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess, required = c("a", "b"))

  testthat::expect_true(ctrl$mark("a", label = "Birinci", pct = 25))
  testthat::expect_identical(ctrl$done(), "a")
  testthat::expect_length(sess$rec$msgs, 1L)

  msg <- sess$rec$msgs[[1]]
  testthat::expect_identical(msg$type, "bootReadinessCheckpoint")
  testthat::expect_identical(msg$message$key, "a")
  testthat::expect_identical(msg$message$label, "Birinci")
  testthat::expect_identical(msg$message$pct, 25)
  testthat::expect_identical(msg$message$required_total, 2L)
  testthat::expect_identical(msg$message$required_done, "a")
  # Henüz tüm zorunlu noktalar tamam değil.
  testthat::expect_false(msg$message$ready)
})

testthat::test_that("mark aynı anahtarı tekrar işaretlemez (done benzersiz kalır)", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess, required = c("a", "b"))

  ctrl$mark("a")
  ctrl$mark("a")
  # done içinde 'a' yalnızca bir kez bulunur.
  testthat::expect_identical(ctrl$done(), "a")
  # Ancak mark her çağrıda mesaj göndermeyi sürdürür (ilerleme bildirimi).
  testthat::expect_length(sess$rec$msgs, 2L)
})

testthat::test_that("tüm zorunlu noktalar işaretlenince ready=TRUE olur", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess, required = c("a", "b"))

  ctrl$mark("a")
  testthat::expect_false(ctrl$is_ready())
  ctrl$mark("b")
  testthat::expect_true(ctrl$is_ready())

  son_msg <- sess$rec$msgs[[length(sess$rec$msgs)]]
  testthat::expect_true(son_msg$message$ready)
  testthat::expect_setequal(son_msg$message$required_done, c("a", "b"))
})

testthat::test_that("zorunlu olmayan anahtar ready durumunu değiştirmez", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess, required = c("a", "b"))

  ctrl$mark("ekstra")          # zorunlu listede yok
  testthat::expect_identical(ctrl$done(), "ekstra")
  testthat::expect_false(ctrl$is_ready())

  son_msg <- sess$rec$msgs[[length(sess$rec$msgs)]]
  # required_done yalnızca zorunlu olanların kesişimini içerir.
  testthat::expect_identical(son_msg$message$required_done, character(0))
})

# ------------------------------------------------------------------------------
# Oturum kapanması / gönderim hatası
# ------------------------------------------------------------------------------
testthat::test_that("mark sendCustomMessage hata fırlatsa bile TRUE döner (geç promise güvenliği)", {
  env <- .source_boot_readiness_for_test()
  # Oturum kapanmış gibi davranan, hata fırlatan session.
  sess <- .fake_boot_session(send_impl = function(type, message) stop("oturum kapalı"))
  ctrl <- env$bootReadinessInit(sess, required = c("a"))

  # Hata tryCatch ile yutulmalı; mark yine de done'a ekler ve TRUE döner.
  testthat::expect_true(ctrl$mark("a"))
  testthat::expect_identical(ctrl$done(), "a")
  testthat::expect_true(ctrl$is_ready())
})

testthat::test_that("mark sayısal/karaktere zorlanabilir anahtarı karaktere çevirir", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess, required = c("42"))
  # Sayısal 42 -> "42" olarak normalize edilir ve zorunlu "42" ile eşleşir.
  testthat::expect_true(ctrl$mark(42))
  testthat::expect_identical(ctrl$done(), "42")
  testthat::expect_true(ctrl$is_ready())
})

testthat::test_that("dört Söyleşi Yönetimi sayfası hazır olunca toplu kontrol noktası bir kez işaretlenir", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess)
  for (k in c("auth_ready", "saved_chats_preview_ready", "file_index_ready",
              "character_media_ready", "welcome_client_ready")) ctrl$mark(k)

  for (k in c("saved_chats_full_loaded", "history_rows_ready", "ortak_list_ready")) ctrl$mark(k)
  # Galeri hazır değilken zengin şerit açılışı hazır sayılmaz.
  testthat::expect_false("management_pages_ready" %in% ctrl$done())
  testthat::expect_false(ctrl$is_ready())

  ctrl$mark("gallery_index_ready")
  testthat::expect_true("management_pages_ready" %in% ctrl$done())
  testthat::expect_true(ctrl$is_ready())
  son <- sess$rec$msgs[[length(sess$rec$msgs)]]$message
  testthat::expect_identical(son$key, "management_pages_ready")
  testthat::expect_true(isTRUE(son$ready))

  # Sonraki tekrarlar toplu anahtarı yeniden üretmez: istemciye giden
  # management_pages_ready MESAJ sayısı da artmaz (done() benzersizliği yetmez).
  toplu_mesaj <- function() sum(vapply(sess$rec$msgs, function(m) identical(m$message$key, "management_pages_ready"), logical(1)))
  testthat::expect_identical(toplu_mesaj(), 1L)
  ctrl$mark("gallery_index_ready")
  ctrl$mark("history_rows_ready")
  testthat::expect_identical(toplu_mesaj(), 1L)
  testthat::expect_identical(sum(ctrl$done() == "management_pages_ready"), 1L)
})

testthat::test_that("mark_once aynı kontrol noktası için istemciye yinelenen bildirim göndermez", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess, required = c("a", "b"))
  testthat::expect_true(ctrl$mark_once("a", detail = list(count = 1L)))
  testthat::expect_false(ctrl$mark_once("a", detail = list(count = 2L)))
  testthat::expect_length(sess$rec$msgs, 1L)
  testthat::expect_identical(sess$rec$msgs[[1]]$message$detail$count, 1L)
})

testthat::test_that("kısmen hazır alt sayfa toplu Söyleşi Yönetimi durumunu da kısmen yapar", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess)
  ctrl$mark("saved_chats_full_loaded")
  ctrl$mark("history_rows_ready", detail = list(degraded = TRUE))
  ctrl$mark("ortak_list_ready", detail = list(count = 0L, available = FALSE))
  ctrl$mark("gallery_index_ready")
  testthat::expect_true("management_pages_ready" %in% ctrl$done())
  toplu <- Filter(function(m) identical(m$message$key, "management_pages_ready"), sess$rec$msgs)
  testthat::expect_length(toplu, 1L)
  testthat::expect_true(isTRUE(toplu[[1]]$message$detail$degraded))
  testthat::expect_setequal(toplu[[1]]$message$detail$kismen, c("history_rows_ready", "ortak_list_ready"))
  testthat::expect_match(toplu[[1]]$message$label, "kısmen", fixed = TRUE)
  testthat::expect_true("management_pages_ready" %in% ctrl$degraded())
})

testthat::test_that("tüm alt sayfalar başarılıysa toplu durum kısmen değildir", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess)
  for (k in c("saved_chats_full_loaded", "history_rows_ready", "ortak_list_ready", "gallery_index_ready")) {
    ctrl$mark(k, detail = list(count = 1L, available = TRUE))
  }
  toplu <- Filter(function(m) identical(m$message$key, "management_pages_ready"), sess$rec$msgs)
  testthat::expect_length(toplu, 1L)
  testthat::expect_false(isTRUE(toplu[[1]]$message$detail$degraded))
  testthat::expect_length(ctrl$degraded(), 0L)
})
