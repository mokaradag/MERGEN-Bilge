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
    invisible(if (is.null(kayit$etkilenen)) 1L else kayit$etkilenen)
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
    # Gerçekleşen silme yeniden okumadan bağımsız işaretlenir (geri gelmez).
    testthat::expect_identical(session$userData$saved_chats_silinenler, "1")
  })
})

testthat::test_that("DB'de satır etkilenmeyen (gerçekleşmeyen) silme silindi olarak işaretlenmez", {
  kayit <- new.env()
  kayit$okuma_hatasi <- TRUE
  kayit$etkilenen <- 0L
  env <- .silme_ortami(kayit)
  baslangic <- list("1" = list(title = "Bir"), "2" = list(title = "İki çğış"))
  shiny::testServer(.silme_sunucusu(env, kayit, baslangic), {
    session$flushReact()
    session$userData$.sil("1")
    session$flushReact()
    testthat::expect_identical(kayit$silinen, "1")
    testthat::expect_null(session$userData$saved_chats_silinenler)
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

testthat::test_that("kanonik olmayan kimlikle silme işaret, yerel kaldırma ve etkin söyleşi için aynı kanonik kimliği kullanır", {
  kayit <- new.env()
  kayit$okuma_hatasi <- TRUE
  env <- .silme_ortami(kayit)
  baslangic <- list("7" = list(title = "Yedi çğış"), "2" = list(title = "İki"))
  shiny::testServer(.silme_sunucusu(env, kayit, baslangic), {
    session$flushReact()
    session$userData$.values$current_chat_id <- 7L
    session$userData$.sil("007")
    session$flushReact()
    testthat::expect_identical(kayit$silinen, "7")
    testthat::expect_identical(session$userData$saved_chats_silinenler, "7")
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "2")
    # Etkin söyleşi kanonik eşleşmeyle silindi sayılır ve sıfırlanır.
    testthat::expect_null(shiny::isolate(session$userData$.values$current_chat_id))
  })
})

testthat::test_that("doğrulanmamış silmede yeniden okuma da başarısızsa kart ve açık söyleşi korunur", {
  kayit <- new.env()
  kayit$okuma_hatasi <- TRUE
  kayit$etkilenen <- 0L
  env <- .silme_ortami(kayit)
  baslangic <- list("1" = list(title = "Bir"), "2" = list(title = "İki çğış"))
  shiny::testServer(.silme_sunucusu(env, kayit, baslangic), {
    session$flushReact()
    session$userData$.values$current_chat_id <- "1"
    session$userData$.values$messages <- list(list(type = "user", content = "çğış"))
    session$userData$.sil("1")
    session$flushReact()
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), c("1", "2"))
    testthat::expect_identical(shiny::isolate(session$userData$.values$current_chat_id), "1")
    testthat::expect_length(shiny::isolate(session$userData$.values$messages), 1L)
    testthat::expect_true(any(grepl("doğrulanamadı", kayit$toast, fixed = TRUE)))
    # Doğrulanmamış silme last_deleted_chat_id'yi işaretlemez: korunan kart tekrar tıklanabilir.
    testthat::expect_null(session$userData$saved_chats_silinenler)
  })
})

.yukleme_sunucusu <- function(env, kayit, baslangic, etkin = "baska") {
  function(input, output, session) {
    values <- shiny::reactiveValues(saved_chats = baslangic, current_chat_id = etkin,
                                    messages = list(list(id = "m1", type = "user", content = "açık")),
                                    show_welcome = FALSE)
    yuklenecek <- shiny::reactiveVal(NULL)
    env$savedChatsObserversInit(
      input = input, output = output, session = session, values = values, settings_data = list(),
      saved_chats_data = list(
        load_chat_id = yuklenecek, delete_chat_id = shiny::reactiveVal(NULL),
        clear_all_chats_trigger = shiny::reactiveVal(0L),
        refresh = function() kayit$yenileme <- (kayit$yenileme %||% 0L) + 1L
      ),
      current_user_id = 7L, load_chat_in_progress = shiny::reactiveVal(FALSE)
    )
    session$userData$.values <- values
    session$userData$.yukle <- yuklenecek
  }
}

testthat::test_that("hidrasyonda kaydı bulunamayan açık söyleşi silinenlere yazılır ve Ana Söyleşi sıfırlanır", {
  kayit <- new.env()
  env <- .silme_ortami(kayit)
  env$load_chat_messages_from_db <- function(chat_id, user_id) list(kayit_bulunamadi = TRUE)
  baslangic <- list("7" = list(title = "Yedi", transkript_yenile = TRUE,
                               messages = list(list(id = "m1", type = "user", content = "açık"))),
                    "2" = list(title = "İki"))
  shiny::testServer(.yukleme_sunucusu(env, kayit, baslangic, etkin = 7L), {
    session$flushReact()
    session$userData$.yukle("007")
    session$flushReact()
    testthat::expect_identical(session$userData$saved_chats_silinenler, "7")
    testthat::expect_null(shiny::isolate(session$userData$.values$current_chat_id))
    testthat::expect_length(shiny::isolate(session$userData$.values$messages), 0L)
    testthat::expect_true(any(grepl("artık mevcut değil", kayit$toast)))
    # Kanonik anahtar ("7") önbellekten kalkar; ilgisiz kart korunur.
    testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "2")
  })
})

testthat::test_that("hidrasyonda kaydı bulunamayan başka söyleşi açık söyleşiyi değiştirmez", {
  kayit <- new.env()
  env <- .silme_ortami(kayit)
  env$load_chat_messages_from_db <- function(chat_id, user_id) list(kayit_bulunamadi = TRUE)
  baslangic <- list("5" = list(title = "Beş", transkript_yenile = TRUE), "7" = list(title = "Yedi"))
  shiny::testServer(.yukleme_sunucusu(env, kayit, baslangic, etkin = 7L), {
    session$flushReact()
    session$userData$.yukle("5")
    session$flushReact()
    testthat::expect_identical(session$userData$saved_chats_silinenler, "5")
    testthat::expect_identical(shiny::isolate(session$userData$.values$current_chat_id), 7L)
    testthat::expect_length(shiny::isolate(session$userData$.values$messages), 1L)
  })
})

testthat::test_that("başarısız hidrasyon okuması silinenlere yazılmaz ve uyarıda bağlantı kimliği görünmez", {
  kayit <- new.env()
  env <- .silme_ortami(kayit)
  env$load_chat_messages_from_db <- function(chat_id, user_id) {
    stop("[Microsoft][ODBC] Login failed; DSN=GizliKaynak;UID=gizli_kullanici;PWD=sir123")
  }
  # Üretimdeki maskeleme yardımcısı kullanılır (yedek yol değil).
  source(file.path(resolve_repo_root_for_tests(), "R", "utils_log_redact.R"), encoding = "UTF-8", local = env)
  testthat::expect_true(exists("mergen_db_error_log_summary", envir = env, inherits = FALSE))
  # Önbellekte olmayan söyleşi: okuma hatasında açılmaz, açık söyleşi değişmez.
  baslangic <- list("9" = list(title = "Dokuz"))
  uyarilar <- character()
  withCallingHandlers({
    shiny::testServer(.yukleme_sunucusu(env, kayit, baslangic, etkin = 9L), {
      session$flushReact()
      session$userData$.yukle("5")
      session$flushReact()
      testthat::expect_null(session$userData$saved_chats_silinenler)
      testthat::expect_identical(shiny::isolate(session$userData$.values$current_chat_id), 9L)
      testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), "9")
    })
  }, warning = function(w) {
    uyarilar <<- c(uyarilar, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  hidrasyon <- grep("Failed to load chat", uyarilar, value = TRUE)
  testthat::expect_length(hidrasyon, 1L)
  testthat::expect_false(any(grepl("GizliKaynak|gizli_kullanici|sir123", hidrasyon)))
})

testthat::test_that("başarılı silme yeniden kurulumu kalan söyleşilerin kayıtsız mesajlarını korur ve başarıyı doğrulamadan sonra bildirir", {
  kayit <- new.env()
  env <- .silme_ortami(kayit)
  kayit$db_listesi <- list("2" = list(title = "İki", message_count = 1L))
  kayitsiz <- list(id = "yerel_1", db_id = NULL, type = "user", content = "kaydedilemeyen istem")
  baslangic <- list("1" = list(title = "Bir"),
                    "2" = list(title = "İki", message_count = 2L,
                               messages = list(list(id = "11", db_id = 11L, type = "user", content = "kayıtlı"), kayitsiz)))
  shiny::testServer(.silme_sunucusu(env, kayit, baslangic), {
    session$flushReact()
    session$userData$.sil("1")
    session$flushReact()
    sonuc <- shiny::isolate(session$userData$.values$saved_chats)
    testthat::expect_identical(names(sonuc), "2")
    testthat::expect_length(sonuc[["2"]]$messages, 2L)
    testthat::expect_identical(sonuc[["2"]]$messages[[2]]$content, "kaydedilemeyen istem")
    testthat::expect_true(isTRUE(sonuc[["2"]]$transkript_yenile))
    testthat::expect_true("Söyleşi silindi." %in% kayit$toast)
  })
})

testthat::test_that("silme DB hatası oturumu kapatmaz; doğrulanamayan silme başarı bildirmez", {
  kayit <- new.env()
  env <- .silme_ortami(kayit)
  env$delete_chat_from_db <- function(chat_id, user_id) stop("[ODBC] bağlantı koptu; UID=gizli_kullanici")
  kayit$db_listesi <- list("1" = list(title = "Bir"), "2" = list(title = "İki"))
  baslangic <- kayit$db_listesi
  uyarilar <- character()
  withCallingHandlers({
    shiny::testServer(.silme_sunucusu(env, kayit, baslangic), {
      session$flushReact()
      session$userData$.sil("1")
      session$flushReact()
      testthat::expect_identical(names(shiny::isolate(session$userData$.values$saved_chats)), c("1", "2"))
      testthat::expect_null(session$userData$saved_chats_silinenler)
    })
  }, warning = function(w) { uyarilar <<- c(uyarilar, conditionMessage(w)); invokeRestart("muffleWarning") })
  testthat::expect_true(any(grepl("silindiği doğrulanamadı", kayit$toast)))
  testthat::expect_false("Söyleşi silindi." %in% kayit$toast)
  testthat::expect_false(any(grepl("gizli_kullanici", uyarilar)))
})

testthat::test_that("özet önbellekteki söyleşinin detay okuması başarısızsa boş söyleşi açılmaz ve hata bildirilir", {
  kayit <- new.env()
  env <- .silme_ortami(kayit)
  env$load_chat_messages_from_db <- function(chat_id, user_id) stop("okuma_hatasi_test")
  baslangic <- list("5" = list(title = "Beş", message_count = 4L), "9" = list(title = "Dokuz"))
  suppressWarnings(shiny::testServer(.yukleme_sunucusu(env, kayit, baslangic, etkin = 9L), {
    session$flushReact()
    session$userData$.yukle("5")
    session$flushReact()
    testthat::expect_identical(shiny::isolate(session$userData$.values$current_chat_id), 9L)
    testthat::expect_length(shiny::isolate(session$userData$.values$messages), 1L)
  }))
  testthat::expect_true(any(grepl("şu anda okunamadı", kayit$toast)))
})

testthat::test_that("etkin söyleşi silinince süren istek oturumdaki durdurma yoluyla bırakılır", {
  kayit <- new.env()
  env <- .silme_ortami(kayit)
  kayit$db_listesi <- list("2" = list(title = "İki"))
  shiny::testServer(function(input, output, session) {
    .silme_sunucusu(env, kayit, list("1" = list(title = "Bir"), "2" = list(title = "İki")))(input, output, session)
    session$userData$.values$current_chat_id <- "1"
    session$userData$mergen_etkin_istegi_durdur <- function() kayit$durdur <- (kayit$durdur %||% 0L) + 1L
  }, {
    session$flushReact()
    session$userData$.sil("1")
    session$flushReact()
    testthat::expect_identical(kayit$durdur, 1L)
    testthat::expect_null(shiny::isolate(session$userData$.values$current_chat_id))
  })
})
