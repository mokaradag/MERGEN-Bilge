# ==============================================================================
# Dosya Yolu: tests/testthat/test-history-tab-cache-behavior.R
# Açıklama: Söyleşi Geçmişi sekme önbelleği davranış testleri. Eskiden her sekme
#           ziyareti (external_refresh_trigger) önbelleği silip tüm geçmişi
#           yeniden çekiyordu; artık yalnızca yeni/değişen söyleşiler çekilir,
#           "Yenile" düğmesi ise bilinçli tam yenileme yapar. Çok sayıda eksik
#           söyleşi küçük partilerle ısıtılır ve hazır-olma yalnızca tam liste
#           yüklendiğinde işaretlenir. Gerçek DB/tarayıcı gerekmez.
# ==============================================================================

.gecmis_modul_ortami <- function(kayit) {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")
  testthat::skip_if_not_installed("data.table")
  # Çalışma zamanında shiny/DT ekli (attached) olduğu için modül nitelemesiz
  # adları kullanır; test ortamı bunu ekli paket dışa aktarımlarıyla taklit eder.
  paketler <- new.env(parent = globalenv())
  for (pkt in c("DT", "shiny")) {
    adlar <- getNamespaceExports(pkt)
    list2env(mget(adlar, envir = asNamespace(pkt), inherits = TRUE), envir = paketler)
  }
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$`%>%` <- get("%>%", envir = asNamespace("magrittr"))
  kok <- resolve_repo_root_for_tests()
  for (f in c("module_chat_history.R", "module_chat_history_background.R")) {
    source(file.path(kok, "R", f), encoding = "UTF-8", local = env)
  }
  env$showToast <- function(...) invisible(NULL)
  env$load_history_rows_batch <- function(chat_ids, user_id = NULL) {
    kayit$cagri <- kayit$cagri + 1L
    kayit$kimlikler[[length(kayit$kimlikler) + 1L]] <- as.character(chat_ids)
    if (isTRUE(kayit$hata)) stop("veritabanı geçici olarak yok (test)")
    if (length(kayit$bos)) {
      return(stats::setNames(lapply(chat_ids, function(id) {
        if (id %in% kayit$bos) list() else list(list(Chat_ID = paste("Söyleşi", id), Tarih = "01.07.2026 - 10:00",
                                                     Soru = "Türkçe soru çğış", Cevap = "Yanıt"))
      }), as.character(chat_ids)))
    }
    stats::setNames(lapply(chat_ids, function(id) list(list(
      Chat_ID = paste("Söyleşi", id), Tarih = "01.07.2026 - 10:00",
      Soru = "Türkçe soru çğış", Cevap = "Yanıt"
    ))), as.character(chat_ids))
  }
  env
}

.gecmis_sohbetleri <- function(n) {
  zaman <- as.POSIXct("2026-07-01 10:00:00", tz = "UTC")
  stats::setNames(lapply(seq_len(n), function(i) list(
    title = paste("Söyleşi", i), timestamp = zaman, last_message_timestamp = zaman
  )), as.character(seq_len(n)))
}

testthat::test_that("sekme ziyareti önbelleği korur, Yenile düğmesi tam yenileme yapar", {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- .gecmis_sohbetleri(3L)

  shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(sohbetler), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- function(key, ...) kayit$isaret <- c(kayit$isaret, key)
    # Gerçek oturumdaki ilk flush (ignoreInit) sekme tetikleyicisinden önce olur.
    session$flushReact()

    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$cagri, 1L)
    testthat::expect_setequal(kayit$kimlikler[[1]], c("1", "2", "3"))
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)

    # İkinci ziyaret: veri değişmediği için DB'ye gidilmez.
    session$setInputs(external_refresh_trigger = 2)
    testthat::expect_identical(kayit$cagri, 1L)

    # Elle yenileme bilinçli olarak tüm geçmişi yeniden çeker.
    session$setInputs(refresh_history = 1)
    testthat::expect_identical(kayit$cagri, 2L)
  })
})

testthat::test_that("tam liste yüklenmeden geçmiş hazır olarak işaretlenmez", {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  env <- .gecmis_modul_ortami(kayit)

  shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(2L)), current_user_id = function() 7L), {
    session$userData$mergen_yonetim_hazir <- function(key, ...) kayit$isaret <- c(kayit$isaret, key)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_false("history_rows_ready" %in% kayit$isaret)
  })
})

testthat::test_that("çok sayıda eksik söyleşi partilerle ısıtılır ve sonunda hazır işaretlenir", {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  env <- .gecmis_modul_ortami(kayit)

  shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- function(key, ...) kayit$isaret <- c(kayit$isaret, key)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    # Partiler later ile planlanır; tetikleyici olay döngüsünü tutmaz.
    testthat::expect_identical(kayit$cagri, 0L)
    for (i in 1:40) later::run_now(0.02)
    testthat::expect_identical(kayit$cagri, 3L)  # 60 + 60 + 10
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)

    session$setInputs(external_refresh_trigger = 2)
    testthat::expect_identical(kayit$cagri, 3L)
  })
})

testthat::test_that("arka plan hazırlığı yalnızca en yeni 60 söyleşiyi tek sorguda hazırlar", {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  env <- .gecmis_modul_ortami(kayit)

  shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- function(key, ...) kayit$isaret <- c(kayit$isaret, key)
    session$flushReact()
    session$setInputs(hazirla = 1)
    # Sınırlı ön izleme: tek sorgu, en yeni (listenin başındaki) 60 söyleşi.
    testthat::expect_identical(kayit$cagri, 1L)
    testthat::expect_identical(kayit$kimlikler[[1]], as.character(1:60))
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)

    # Sayfa açılınca kalan 70 söyleşi partilerle doldurulur.
    session$setInputs(external_refresh_trigger = 1)
    for (i in 1:40) later::run_now(0.02)
    testthat::expect_identical(kayit$cagri, 3L)  # 1 + (60 + 10)
    testthat::expect_identical(length(messages_cache()), 130L)
  })
})

.yeni_gecmis_kaydi <- function() {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  kayit$detay <- list(); kayit$hata <- FALSE; kayit$bos <- character()
  kayit
}

.isaretleyici <- function(kayit) {
  function(key, label = key, detail = NULL, ...) {
    kayit$isaret <- c(kayit$isaret, key)
    kayit$detay[[length(kayit$detay) + 1L]] <- detail
  }
}

testthat::test_that("başarısız geçmiş okuması boş geçmiş olarak önbelleğe alınmaz, kısmen bildirilir ve yeniden denenir", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    kayit$hata <- TRUE
    session$setInputs(hazirla = 1)
    testthat::expect_identical(kayit$cagri, 1L)
    testthat::expect_length(messages_cache(), 0L)
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)
    testthat::expect_true(isTRUE(kayit$detay[[1]]$degraded), info = "başarısız okuma 'hazır' gibi bildirilmemeli")

    # Veritabanı düzelince bir sonraki ziyaret aynı söyleşileri yeniden dener.
    kayit$hata <- FALSE
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$cagri, 2L)
    testthat::expect_setequal(kayit$kimlikler[[2]], c("1", "2", "3"))
    testthat::expect_length(messages_cache(), 3L)
  })
})

testthat::test_that("gerçekten boş geçmiş başarıyla okunduysa her ziyarette yeniden sorgulanmaz", {
  kayit <- .yeni_gecmis_kaydi()
  kayit$bos <- c("2")
  env <- .gecmis_modul_ortami(kayit)
  shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$cagri, 1L)
    testthat::expect_identical(messages_cache()[["2"]]$rows, list())
    session$setInputs(external_refresh_trigger = 2)
    testthat::expect_identical(kayit$cagri, 1L)
  })
})

testthat::test_that("60'tan fazla eksikte damgası değişen önbellekli söyleşi de yenilenir", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(hazirla = 1)                     # 1..60 önbellekte
    yeni <- .gecmis_sohbetleri(130L)
    yeni[["5"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    kayit$kimlikler <- list()
    session$setInputs(external_refresh_trigger = 1)
    for (i in 1:40) later::run_now(0.02)
    cekilen <- unlist(kayit$kimlikler)
    testthat::expect_true("5" %in% cekilen, info = "bayat önbellek kaydı yenilenmeli")
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    testthat::expect_identical(length(messages_cache()), 130L)
  })
})

testthat::test_that("liste değişimi sınırı aşan eşzamanlı SQL çalıştırmaz; ara partiler tabloyu yeniden kurmaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(10L))
  shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)    # önbellek dolu (10)
    kayit$kimlikler <- list()
    hesap <- 0L
    shiny::observe({ filtered_history(); hesap <<- hesap + 1L })
    session$flushReact()
    hesap <- 0L
    # Tam liste geldi: 300 söyleşi. Gözlemci tek seferde 290 söyleşiyi çekmemeli.
    shiny::isolate(sohbetler(.gecmis_sohbetleri(300L)))
    session$flushReact()
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    oncesi <- hesap
    for (i in 1:60) later::run_now(0.02)
    session$flushReact()
    testthat::expect_identical(length(messages_cache()), 300L)
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    # 5 arka plan partisi için tablo en çok bir kez (sondaki yayında) yeniden kurulur.
    testthat::expect_lte(hesap - oncesi, 1L)
  })
})

testthat::test_that("tarih aralığı değişince eski nesle ait ertelenmiş partiler önbelleği yeniden dolduramaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)    # 130 eksik: 3 parti planlandı
    testthat::expect_identical(kayit$cagri, 0L)
    # Hiçbir söyleşiyi kapsamayan aralık: önbellek temizlenir, nesil değişir.
    session$setInputs(date_range = c("2020-01-01", "2020-01-31"))
    for (i in 1:40) later::run_now(0.02)
    testthat::expect_identical(kayit$cagri, 0L, info = "eski planın partileri DB'ye gitmemeli")
    testthat::expect_length(messages_cache(), 0L)
  })
})

testthat::test_that("ad değişikliği geçmiş tablosunda güncel başlıkla görünür", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(2L))
  shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    yeni <- shiny::isolate(sohbetler())
    yeni[["1"]]$title <- "Yeni ad çğışÖÜ"
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    tablo <- filtered_history()
    testthat::expect_true("Yeni ad çğışÖÜ" %in% tablo$Chat_ID)
    testthat::expect_false("Söyleşi 1" %in% tablo$Chat_ID)
  })
})
