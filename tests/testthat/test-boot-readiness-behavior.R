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
testthat::test_that("bootReadinessInit beklenen 5 zorunlu kontrol noktasını döndürür", {
  env <- .source_boot_readiness_for_test()
  sess <- .fake_boot_session()
  ctrl <- env$bootReadinessInit(sess)

  testthat::expect_identical(
    ctrl$required,
    c("auth_ready", "saved_chats_preview_ready", "file_index_ready",
      "character_media_ready", "welcome_client_ready")
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
