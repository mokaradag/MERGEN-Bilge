# ==============================================================================
# Dosya Yolu: tests/testthat/test-destek-geri-bildirim-behavior.R
# Açıklama: R/module_destek_geri_bildirim.R destekGeriBildirimServer() geri
#           bildirim formu doğrulama/gönderim mantığının DAVRANIŞSAL testleri.
#           Bu dosya daha önce hiçbir test tarafından çağrılmıyordu.
#
#           gonder_geri_bildirim gözlemcisi memnuniyet alanını zorunlu kılar,
#           kimlik hazır değilse engeller ve geçerli durumda
#           destek_geri_bildirim_kaydet() çağırır (memnuniyet/nps tamsayıya,
#           iletişim izni boole'ye dönüştürülür). Alt modül destekHataBildirServer
#           ve DB stub'lanır. Gerçek DB GEREKMEZ.
# ==============================================================================

.source_geri_bildirim_for_test <- function(user_id = 5L) {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("shinyjs")
  suppressMessages({ library(shiny); library(shinyjs) })
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  rec <- new.env()
  rec$toasts <- list()
  rec$saves <- list()

  env$resolve_effective_user_id <- function(session, current_user_id) user_id
  env$showToast <- function(session, message, type = "info") {
    rec$toasts[[length(rec$toasts) + 1L]] <- list(message = message, type = type)
    invisible(NULL)
  }
  env$destek_geri_bildirim_kaydet <- function(...) {
    rec$saves[[length(rec$saves) + 1L]] <- list(...)
    invisible(TRUE)
  }
  # Alt modül (hata bildir) stub'ı: yalnızca basarili reaktifini döndürür.
  env$destekHataBildirServer <- function(id, current_user_id) {
    list(basarili = shiny::reactive(0))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_destek_geri_bildirim.R"),
    encoding = "UTF-8",
    local = env
  )
  list(env = env, rec = rec)
}

.toast_msgs <- function(rec) vapply(rec$toasts, function(t) t$message, character(1))

.submit_feedback <- function(fix, fields) {
  env <- fix$env
  shiny::testServer(env$destekGeriBildirimServer, args = list(current_user_id = 5L), {
    do.call(session$setInputs, fields)
    session$setInputs(gonder_geri_bildirim = 1)
    session$setInputs(gonder_geri_bildirim = 2)
  })
}

# ------------------------------------------------------------------------------
# Memnuniyet zorunluluğu
# ------------------------------------------------------------------------------
testthat::test_that("gonder_geri_bildirim memnuniyet boşsa kaydetmez ve uyarır", {
  fix <- .source_geri_bildirim_for_test()
  .submit_feedback(fix, list(memnuniyet = ""))
  testthat::expect_length(fix$rec$saves, 0L)
  testthat::expect_true(any(grepl("Genel memnuniyetinizi belirtmeniz",
                                  .toast_msgs(fix$rec), fixed = TRUE)))
})

testthat::test_that("gonder_geri_bildirim memnuniyet '0' ise (seçilmemiş) kaydetmez", {
  fix <- .source_geri_bildirim_for_test()
  .submit_feedback(fix, list(memnuniyet = "0"))
  testthat::expect_length(fix$rec$saves, 0L)
})

# ------------------------------------------------------------------------------
# Kimlik hazır değil
# ------------------------------------------------------------------------------
testthat::test_that("gonder_geri_bildirim kimlik hazır değilken kaydetmez", {
  fix <- .source_geri_bildirim_for_test(user_id = 0L)
  .submit_feedback(fix, list(memnuniyet = "4"))
  testthat::expect_length(fix$rec$saves, 0L)
  testthat::expect_true(any(grepl("Kimlik doğrulama tamamlanmadan",
                                  .toast_msgs(fix$rec), fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# Başarılı gönderim + tip dönüşümleri
# ------------------------------------------------------------------------------
testthat::test_that("gonder_geri_bildirim memnuniyet/nps'i tamsayıya çevirir ve kaydeder", {
  fix <- .source_geri_bildirim_for_test(user_id = 9L)
  .submit_feedback(fix, list(
    memnuniyet = "4", nps_puan = "8", secili_etiketler = "Hızlı,Net",
    en_cok_sevilen = "Arayüz", gelistirme = "Daha hızlı olabilir", iletisim_izni = "1"
  ))
  testthat::expect_true(length(fix$rec$saves) >= 1L)
  son <- fix$rec$saves[[length(fix$rec$saves)]]
  testthat::expect_identical(son$user_id, 9L)
  testthat::expect_identical(son$memnuniyet, 4L)
  testthat::expect_identical(son$nps_puan, 8L)
  testthat::expect_identical(son$etiketler, "Hızlı,Net")
  testthat::expect_identical(son$en_cok_sevilen, "Arayüz")
  # iletisim_izni "1" -> TRUE.
  testthat::expect_true(son$iletisim_izni)
})

testthat::test_that("gonder_geri_bildirim boş nps/etiket alanlarını NULL'a indirger", {
  fix <- .source_geri_bildirim_for_test(user_id = 9L)
  .submit_feedback(fix, list(
    memnuniyet = "5", nps_puan = "", secili_etiketler = "",
    en_cok_sevilen = "", gelistirme = "", iletisim_izni = "0"
  ))
  son <- fix$rec$saves[[length(fix$rec$saves)]]
  testthat::expect_null(son$nps_puan)
  testthat::expect_null(son$etiketler)
  testthat::expect_null(son$en_cok_sevilen)
  testthat::expect_null(son$gelistirme)
  # iletisim_izni "0" -> FALSE.
  testthat::expect_false(son$iletisim_izni)
})
