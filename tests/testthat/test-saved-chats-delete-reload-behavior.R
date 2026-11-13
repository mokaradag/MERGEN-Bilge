# ==============================================================================
# Dosya Yolu: tests/testthat/test-saved-chats-delete-reload-behavior.R
# Açıklama: Kayıtlı söyleşi silme gözlemcisinin yeniden okuma sözleşmesi.
#           Silme sonrası liste DB'den yeniden kurulamazsa silinen söyleşi
#           yerelden kalkar ve yerel liste "yetkili tam liste" sayılmaz
#           (yetkili sürüm artmaz); süren arka plan tam listesi birleştirmeyle
#           uygulanır. Yeniden okuma başarılıysa sürüm artar. DB gerekmez.
# ==============================================================================

.silme_ortami <- function(kayit) {
  testthat::skip_if_not_installed("shiny")
  paketler <- new.env(parent = globalenv())
  adlar <- getNamespaceExports("shiny")
  list2env(mget(adlar, envir = asNamespace("shiny"), inherits = TRUE), envir = paketler)
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$resolve_effective_user_id <- function(...) 7L
  env$showToast <- function(session, message, ...) kayit$toast <- c(kayit$toast, message)
  env$delete_chat_from_db <- function(chat_id, user_id) {
    kayit$silinen <- c(kayit$silinen, chat_id)
    invisible(1L)
  }
  env$load_chats_from_db <- function(user_id, include_messages = TRUE) {
    if (isTRUE(kayit$okuma_hatasi)) stop("veritabanı geçici olarak yok (test)")
    kayit$db_listesi
  }
  source(file.path(resolve_repo_root_for_tests(), "R", "server_observers_saved_chats.R"),
         encoding = "UTF-8", local = env)
  env
}

.silme_sunucusu <- function(env, kayit, baslangic) {
  function(input, output, session) {
    values <- shiny::reactiveValues(saved_chats = baslangic, current_chat_id = "baska",
                                    messages = list(), show_welcome = FALSE)
    silinecek <- shiny::reactiveVal(NULL)
    env$savedChatsObserversInit(
      input = input, output = output, session = session, values = values, settings_data = list(),
      saved_chats_data = list(
        load_chat_id = shiny::reactiveVal(NULL), delete_chat_id = silinecek,
        clear_all_chats_trigger = shiny::reactiveVal(0L),
        refresh = function() kayit$yenileme <- (kayit$yenileme %||% 0L) + 1L
      ),
      current_user_id = 7L, load_chat_in_progress = shiny::reactiveVal(FALSE)
    )
    session$userData$.values <- values
    session$userData$.sil <- silinecek
  }
}

testthat::test_that("silme sonrası yeniden okuma başarısızsa söyleşi yerelden kalkar ve liste yetkili sayılmaz", {
  kayit <- new.env()
  kayit$okuma_hatasi <- TRUE
  env <- .silme_ortami(kayit)
  baslangic <- list("1" = list(title = "Bir"), "2" = list(title = "İki çğış"))
  shiny::testServer(.silme_sunucusu(env, kayit, baslangic), {
    session$flushReact()
    session$userData$.sil("1")
    session$flushReact()
    testthat::expect_identical(kayit$silinen, "1")
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "2")
    # Yetkili sürüm artmaz: süren tam liste atılmaz, birleştirmeyle uygulanır.
    testthat::expect_null(session$userData$saved_chats_yetkili_surum)
    testthat::expect_identical(kayit$yenileme, 1L)
  })
})

testthat::test_that("silme sonrası yeniden okuma başarılıysa liste DB'den kurulur ve yetkili sürüm artar", {
  kayit <- new.env()
  kayit$db_listesi <- list("2" = list(title = "İki çğış"), "3" = list(title = "Üç"))
  env <- .silme_ortami(kayit)
  baslangic <- list("1" = list(title = "Bir"), "2" = list(title = "İki çğış"))
  shiny::testServer(.silme_sunucusu(env, kayit, baslangic), {
    session$flushReact()
    session$userData$.sil("1")
    session$flushReact()
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), c("2", "3"))
    testthat::expect_identical(session$userData$saved_chats_yetkili_surum, 1L)
  })
})
