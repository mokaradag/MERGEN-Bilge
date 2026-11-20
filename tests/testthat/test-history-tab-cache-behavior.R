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
  # Okuma hataları günlüğe maskeleme sınırından (utils_log_redact.R) yazılır.
  for (f in c("utils_log_redact.R", "module_chat_history.R", "module_chat_history_background.R")) {
    source(file.path(kok, "R", f), encoding = "UTF-8", local = env)
  }
  env$showToast <- function(...) invisible(NULL)
  env$load_history_rows_batch <- function(chat_ids, user_id = NULL) {
    kayit$cagri <- kayit$cagri + 1L
    kayit$kimlikler[[length(kayit$kimlikler) + 1L]] <- as.character(chat_ids)
    if (isTRUE(kayit$hata)) stop("veritabanı geçici olarak yok (test)")
    # Okunamayan (sonuçta bulunmayan) kimlikler: kısmi okuma benzetimi.
    chat_ids <- setdiff(as.character(chat_ids), kayit$basarisiz)
    if (length(kayit$bos)) {
      return(stats::setNames(lapply(chat_ids, function(id) {
        if (id %in% kayit$bos) list() else list(list(Chat_ID = paste("Söyleşi", id), Tarih = "01.07.2026 - 10:00",
                                                     Soru = "Türkçe soru çğış", Cevap = "Yanıt"))
      }), as.character(chat_ids)))
    }
    soru <- if (is.null(kayit$etiket)) "Türkçe soru çğış" else kayit$etiket
    stats::setNames(lapply(chat_ids, function(id) list(list(
      Chat_ID = paste("Söyleşi", id), Tarih = "01.07.2026 - 10:00",
      Soru = soru, Cevap = "Yanıt"
    ))), as.character(chat_ids))
  }
  # Açılış hazırlığı işçi sınırından geçer: sahte işçi sonucu bir sonraki
  # döngü turunda (eşzamansız) aynı sahte okuyucudan üretir.
  env$mergen_startup_async_worker_ready <- function() TRUE
  env$history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL, ...) {
    kayit$isci <- c(kayit$isci, list(as.character(chat_ids)))
    promises::promise(function(resolve, reject) {
      later::later(function() {
        tryCatch(resolve(env$load_history_rows_batch(chat_ids, user_id)), error = function(e) reject(e))
      }, 0)
    })
  }
  env
}

# Ertelenmiş partiler sabit tur sayısıyla değil, gözlenebilir tamamlanmayla
# beklenir: her test kendi geçici later döngüsünde koşar (önyükleme
# yardımcılarının küresel döngüdeki promise trafiği karışmaz); döngü boşalana
# dek (süre sınırlı) çalıştırılır, zincir süre içinde sonlanmazsa test başarısız olur.
.zincir_bitene_dek <- function(session, sure = 10) {
  son <- Sys.time() + sure
  repeat {
    while (!later::loop_empty() && Sys.time() < son) later::run_now(0.02)
    # Yayın (trigger_refresh) çıktıları yeniden hesaplatabilir; döngü boş ve
    # reaktif durum durulmuş olana dek beklenir.
    session$flushReact()
    if (later::loop_empty() || Sys.time() >= son) break
  }
  testthat::expect_true(later::loop_empty(), info = "ertelenmiş partiler süre içinde tamamlanmalı")
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

  later::with_temp_loop(shiny::testServer(env$historyServer,
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

    # Elle yenileme bilinçli olarak tüm geçmişi yeniden çeker (alt küme değil).
    session$setInputs(refresh_history = 1)
    testthat::expect_identical(kayit$cagri, 2L)
    testthat::expect_setequal(kayit$kimlikler[[2]], c("1", "2", "3"))
  }))
})

testthat::test_that("tam liste yüklenmeden geçmiş hazır olarak işaretlenmez", {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  env <- .gecmis_modul_ortami(kayit)

  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(2L)), current_user_id = function() 7L), {
    session$userData$mergen_yonetim_hazir <- function(key, ...) kayit$isaret <- c(kayit$isaret, key)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_false("history_rows_ready" %in% kayit$isaret)
  }))
})

testthat::test_that("çok sayıda eksik söyleşi partilerle ısıtılır ve sonunda hazır işaretlenir", {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  env <- .gecmis_modul_ortami(kayit)

  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- function(key, ...) kayit$isaret <- c(kayit$isaret, key)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    # Partiler later ile planlanır; tetikleyici olay döngüsünü tutmaz.
    testthat::expect_identical(kayit$cagri, 0L)
    .zincir_bitene_dek(session)
    testthat::expect_identical(kayit$cagri, 3L)  # 60 + 60 + 10
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)

    session$setInputs(external_refresh_trigger = 2)
    testthat::expect_identical(kayit$cagri, 3L)
  }))
})

testthat::test_that("arka plan hazırlığı yalnızca en yeni 60 söyleşiyi tek sorguda hazırlar", {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  env <- .gecmis_modul_ortami(kayit)

  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- function(key, ...) kayit$isaret <- c(kayit$isaret, key)
    session$flushReact()
    session$setInputs(hazirla = 1)
    .zincir_bitene_dek(session)
    # Sınırlı ön izleme: tek sorgu, en yeni (listenin başındaki) 60 söyleşi.
    testthat::expect_identical(kayit$cagri, 1L)
    # Hazırlık olay döngüsünü tutmaz: tek okuma işçi sınırından geçti (eşzamanlı
    # okuyucu doğrudan çağrılmadı).
    testthat::expect_length(kayit$isci, 1L)
    testthat::expect_identical(kayit$isci[[1]], as.character(1:60))
    testthat::expect_identical(kayit$kimlikler[[1]], as.character(1:60))
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)

    # Sayfa açılınca kalan 70 söyleşi partilerle doldurulur.
    session$setInputs(external_refresh_trigger = 1)
    .zincir_bitene_dek(session)
    testthat::expect_identical(kayit$cagri, 3L)  # 1 + (60 + 10)
    testthat::expect_identical(length(messages_cache()), 130L)
  }))
})

.yeni_gecmis_kaydi <- function() {
  kayit <- new.env(); kayit$cagri <- 0L; kayit$kimlikler <- list(); kayit$isaret <- character()
  kayit$detay <- list(); kayit$hata <- FALSE; kayit$bos <- character(); kayit$basarisiz <- character()
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
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    kayit$hata <- TRUE
    session$setInputs(hazirla = 1)
    .zincir_bitene_dek(session)
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
  }))
})

testthat::test_that("gerçekten boş geçmiş başarıyla okunduysa her ziyarette yeniden sorgulanmaz", {
  kayit <- .yeni_gecmis_kaydi()
  kayit$bos <- c("2")
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$cagri, 1L)
    testthat::expect_identical(messages_cache()[["2"]]$rows, list())
    session$setInputs(external_refresh_trigger = 2)
    testthat::expect_identical(kayit$cagri, 1L)
  }))
})

testthat::test_that("60'tan fazla eksikte damgası değişen önbellekli söyleşi de yenilenir", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(hazirla = 1)                     # 1..60 önbellekte
    .zincir_bitene_dek(session)
    # Kayıt damga değişiminden ÖNCE sıfırlanır: değişimin planladığı parti
    # flush sırasında hemen koşsa da okuma kaybolmaz (zamanlamadan bağımsız).
    kayit$kimlikler <- list()
    yeni <- .gecmis_sohbetleri(130L)
    yeni[["5"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    .zincir_bitene_dek(session)
    cekilen <- unlist(kayit$kimlikler)
    testthat::expect_true("5" %in% cekilen, info = "bayat önbellek kaydı yenilenmeli")
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    testthat::expect_identical(length(messages_cache()), 130L)
  }))
})

testthat::test_that("liste değişimi sınırı aşan eşzamanlı SQL çalıştırmaz; ara partiler tabloyu yeniden kurmaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(10L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
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
    # Partiler TEK TEK çalıştırılır ve her birinden sonra Shiny boşaltılır: ara
    # partiler tabloyu yeniden kurmaz, yalnızca zincir sonundaki yayın kurar.
    parti_adimlari <- integer()   # parti çalıştıran her adımdaki yeniden kurulum sayısı
    diger <- 0L                    # parti dışı geri çağrılardaki yeniden kurulumlar
    son <- Sys.time() + 10
    while (!later::loop_empty() && Sys.time() < son) {
      oncesi <- hesap
      cagri_once <- kayit$cagri
      if (isTRUE(later::run_now(0.2, all = FALSE))) {
        session$flushReact()
        if (kayit$cagri > cagri_once) parti_adimlari <- c(parti_adimlari, hesap - oncesi)
        else diger <- diger + (hesap - oncesi)
      }
    }
    testthat::expect_identical(length(messages_cache()), 300L)
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    testthat::expect_identical(parti_adimlari, c(0L, 0L, 0L, 0L, 1L))
    testthat::expect_identical(diger, 0L)
  }))
})

testthat::test_that("tarih aralığı değişince eski nesle ait ertelenmiş partiler önbelleği yeniden dolduramaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)    # 130 eksik: 3 parti planlandı
    testthat::expect_identical(kayit$cagri, 0L)
    # Hiçbir söyleşiyi kapsamayan aralık: önbellek temizlenir, nesil değişir.
    session$setInputs(date_range = c("2020-01-01", "2020-01-31"))
    .zincir_bitene_dek(session)
    testthat::expect_identical(kayit$cagri, 0L, info = "eski planın partileri DB'ye gitmemeli")
    testthat::expect_length(messages_cache(), 0L)
  }))
})

testthat::test_that("ad değişikliği geçmiş tablosunda güncel başlıkla görünür", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(2L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
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
  }))
})

testthat::test_that("ısıtma sırasında eklenen 60'tan fazla yeni söyleşi tamamlanınca sınırlı partilerle alınır", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)    # 130 eksik: ısıtma planlandı
    shiny::isolate(sohbetler(.gecmis_sohbetleri(200L))) # ısıtma sürerken 70 yeni söyleşi
    session$flushReact()
    .zincir_bitene_dek(session)
    session$flushReact()
    testthat::expect_identical(length(messages_cache()), 200L)
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    # Her kimlik en fazla bir kez çekilir (tekrar döngüsü yok).
    testthat::expect_identical(anyDuplicated(unlist(kayit$kimlikler)), 0L)
  }))
})

testthat::test_that("veritabanı kapalıyken ısıtma zinciri yeniden deneme döngüsüne girmez", {
  kayit <- .yeni_gecmis_kaydi()
  kayit$hata <- TRUE
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    shiny::isolate(sohbetler(.gecmis_sohbetleri(200L)))
    session$flushReact()
    .zincir_bitene_dek(session)
    # 130 + 70 kimliğin her biri tam bir kez denenir (0 okuma geçmez, döngü yok).
    denenen <- unlist(kayit$kimlikler)
    testthat::expect_setequal(denenen, as.character(1:200))
    testthat::expect_identical(anyDuplicated(denenen), 0L)
    testthat::expect_lte(kayit$cagri, 5L)
    testthat::expect_length(messages_cache(), 0L)
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)
    testthat::expect_true(isTRUE(utils::tail(kayit$detay, 1)[[1]]$degraded))
  }))
})

testthat::test_that("boş geçmiş ve tamamen önbellekte olan geçmiş 'kısmen' değil 'hazır' bildirilir", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(list()), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$cagri, 0L)
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)
    testthat::expect_false(any(vapply(kayit$detay, function(d) isTRUE(d$degraded), logical(1))),
                           info = "geçerli boş geçmiş kısmen sayılmamalı")
  }))

  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(2L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    .zincir_bitene_dek(session)
    session$setInputs(external_refresh_trigger = 1)   # hepsi önbellekte: okuma yok
    testthat::expect_identical(kayit$cagri, 1L)
    testthat::expect_length(kayit$detay, 2L)
    testthat::expect_false(any(vapply(kayit$detay, function(d) isTRUE(d$degraded), logical(1))))
  }))
})

testthat::test_that("yükleyici sonucunda bulunmayan söyleşi boş geçmiş olarak önbelleğe alınmaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  gercek <- env$load_history_rows_batch
  env$load_history_rows_batch <- function(chat_ids, user_id = NULL) {
    sonuc <- gercek(chat_ids, user_id)
    sonuc[setdiff(names(sonuc), "2")]
  }
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_setequal(names(messages_cache()), c("1", "3"))
    testthat::expect_true(isTRUE(kayit$detay[[1]]$degraded))
    # Eksik kalan söyleşi sonraki ziyarette yeniden denenir.
    session$setInputs(external_refresh_trigger = 2)
    testthat::expect_identical(kayit$kimlikler[[2]], "2")
  }))
})

testthat::test_that("damgası değişen söyleşinin yenilemesi başarısızsa eski satırlar güncelmiş gibi gösterilmez", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(3L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_length(messages_cache(), 3L)
    kayit$hata <- TRUE
    yeni <- shiny::isolate(sohbetler())
    yeni[["2"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    yeni[["2"]]$title <- "Değişen söyleşi"
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    testthat::expect_setequal(names(messages_cache()), c("1", "3"))
    testthat::expect_false("Değişen söyleşi" %in% filtered_history()$Chat_ID)
    testthat::expect_true(any(vapply(kayit$detay, function(d) isTRUE(d$degraded), logical(1))))
  }))
})

testthat::test_that("ısıtma sırasında damgası değişen planlı söyleşi zincir bitince yeniden alınır", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)    # 130 eksik: 3 parti planlandı
    son <- Sys.time() + 5
    # Her yoklamada YALNIZCA bir geri çağrı (all = FALSE): döngü geç başlasa da
    # zamanı gelmiş tüm partiler tek çağrıda koşmaz; değişim ısıtma SÜRERKEN olur.
    while (kayit$cagri < 1L && Sys.time() < son) later::run_now(0.02, all = FALSE)
    testthat::expect_identical(kayit$cagri, 1L)
    # İlk parti (1..60) yazıldı; "5" bu sürümüyle önbellekte.
    testthat::expect_true("5" %in% names(shiny::isolate(messages_cache())))
    yeni <- shiny::isolate(sohbetler())
    yeni[["5"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    .zincir_bitene_dek(session)
    cekilen <- unlist(kayit$kimlikler)
    testthat::expect_identical(sum(cekilen == "5"), 2L, info = "değişen sürüm bir kez daha alınmalı")
    testthat::expect_identical(messages_cache()[["5"]]$stamp, stamp_for_chat(yeni[["5"]]))
  }))
})

testthat::test_that("ısıtma sürerken tekrarlanan sekme ziyareti geçmişi erken 'hazır' bildirmez", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    session$setInputs(external_refresh_trigger = 2)    # tüm eksikler zaten planlı
    testthat::expect_false("history_rows_ready" %in% kayit$isaret,
                           info = "planlı partiler yazılmadan hazır bildirilmemeli")
    .zincir_bitene_dek(session)
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)
    testthat::expect_identical(length(messages_cache()), 130L)
    testthat::expect_false(any(vapply(kayit$detay, function(d) isTRUE(d$degraded), logical(1))))
  }))
})

testthat::test_that("yerinde içerik düzenlemesi ilgili geçmiş kaydını düşürür ve yalnız onu yeniden okutur", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_true("Söyleşi 2" %in% filtered_history()$Chat_ID)
    session$userData$mergen_gecmis_onbellek_dusur("2")
    testthat::expect_setequal(names(messages_cache()), c("1", "3"))
    # Tablo yeniden yayınlanır: silinmiş görselin eski alıntısı açık tabloda kalmaz.
    session$flushReact()
    testthat::expect_false("Söyleşi 2" %in% filtered_history()$Chat_ID)
    session$setInputs(external_refresh_trigger = 2)
    testthat::expect_identical(kayit$kimlikler[[2]], "2")
    session$userData$mergen_gecmis_onbellek_dusur()
    testthat::expect_length(messages_cache(), 0L)
  }))
})

testthat::test_that("başarısız okuma önbelleği boşaltsa da liste değişince açık geçmiş yeniden eşitlenir", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(3L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    kayit$hata <- TRUE
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_length(messages_cache(), 0L)
    # Veritabanı düzeldi; liste değişti (yeni söyleşi). Önbellek boş olsa da
    # geçmiş etkin olduğu için senkronizasyon atlanmaz, sayfa boş kalmaz.
    kayit$hata <- FALSE
    shiny::isolate(sohbetler(.gecmis_sohbetleri(4L)))
    session$flushReact()
    testthat::expect_identical(length(messages_cache()), 4L)
    testthat::expect_identical(kayit$cagri, 2L)
  }))
})

testthat::test_that("başarısız partideki söyleşi yeni damgasıyla başarıyla okunursa hazır-olma 'kısmen' kalmaz", {
  kayit <- .yeni_gecmis_kaydi()
  kayit$basarisiz <- "5"
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    son <- Sys.time() + 5
    while (kayit$cagri < 1L && Sys.time() < son) later::run_now(0.02, all = FALSE)
    # Ara durum gerçekten kuruldu: ilk parti koştu, "5" denendi ve okunamadı,
    # aynı partideki diğer söyleşiler yazıldı; ısıtma hâlâ sürüyor.
    testthat::expect_identical(kayit$cagri, 1L, info = "ilk parti süre içinde çalışmalı")
    testthat::expect_true("5" %in% kayit$kimlikler[[1]])
    testthat::expect_false("5" %in% names(shiny::isolate(messages_cache())))
    testthat::expect_true("1" %in% names(shiny::isolate(messages_cache())))
    testthat::expect_true(isTRUE(isitma$aktif), info = "değişim ısıtma SÜRERKEN olmalı")
    # "5" yeni mesaj aldı (damga değişti) ve artık okunabiliyor.
    kayit$basarisiz <- character()
    yeni <- shiny::isolate(sohbetler())
    yeni[["5"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    .zincir_bitene_dek(session)
    testthat::expect_identical(messages_cache()[["5"]]$stamp, stamp_for_chat(yeni[["5"]]))
    # Başarısız okuma ve yeni damgayla yeniden deneme: "5" tam iki kez okundu.
    testthat::expect_identical(sum(unlist(kayit$kimlikler) == "5"), 2L)
    son_detay <- kayit$detay[[length(kayit$detay)]]
    testthat::expect_false(isTRUE(son_detay$degraded), info = "güncel kayıtlar tamamsa durum 'hazır' olmalı")
  }))
})

testthat::test_that("aynı damgayla okunamayan söyleşi zincir sonunda hazır-olmayı 'kısmen' bırakır", {
  kayit <- .yeni_gecmis_kaydi()
  kayit$basarisiz <- "5"
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    .zincir_bitene_dek(session)
    testthat::expect_true(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded))
    testthat::expect_identical(sum(unlist(kayit$kimlikler) == "5"), 1L, info = "aynı damgayla yeniden denenmemeli")
  }))
})

testthat::test_that("planlandıktan sonra tarih aralığından çıkan söyleşi arka plan partisinde okunmaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    # Kullanıcı Geçmiş sayfasındadır (etkin); aralık değişimi ısıtmayı başlatır.
    isitma$etkin <- TRUE
    session$setInputs(date_range = c("2026-06-01", "2026-07-31"))   # 130 eksik: ısıtma
    son <- Sys.time() + 5
    while (kayit$cagri < 1L && Sys.time() < son) later::run_now(0.02, all = FALSE)
    # Ara durum: yalnızca ilk parti koştu; "100" henüz okunmadı ve planlı.
    testthat::expect_identical(kayit$cagri, 1L, info = "ilk parti süre içinde çalışmalı")
    testthat::expect_false("100" %in% kayit$kimlikler[[1]])
    testthat::expect_true("100" %in% isitma$planli)
    # "100" ikinci partide planlı; aralık dışına taşınır (etkinlik 2026-09).
    yeni <- shiny::isolate(sohbetler())
    yeni[["100"]]$last_message_timestamp <- as.POSIXct("2026-09-15 09:00:00", tz = "UTC")
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    .zincir_bitene_dek(session)
    testthat::expect_false("100" %in% unlist(kayit$kimlikler))
    testthat::expect_false("100" %in% names(messages_cache()))
    # Kalan partiler yine de koştu (zincir kesilmedi).
    testthat::expect_gte(kayit$cagri, 2L)
  }))
})

# Hazırlık işçisinin tamamlanma anını test denetler: sonuç ancak elle
# çözüldüğünde (resolve) ve döngü koşunca uygulanır.
.elle_cozulen_isci <- function(env, kayit) {
  kayit$cozumler <- list()
  env$history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL, ...) {
    kayit$isci <- c(kayit$isci, list(as.character(chat_ids)))
    promises::promise(function(resolve, reject) {
      kayit$cozumler[[length(kayit$cozumler) + 1L]] <- list(resolve = resolve, ids = as.character(chat_ids))
    })
  }
}

.surum_satirlari <- function(ids, etiket) {
  stats::setNames(lapply(ids, function(id) list(list(
    Chat_ID = paste("Söyleşi", id), Tarih = "01.07.2026 - 10:00", Soru = etiket, Cevap = "Yanıt"
  ))), ids)
}

testthat::test_that("geç tamamlanan açılış hazırlığı daha yeni eşzamanlı okumanın önbelleğini ezmez", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  .elle_cozulen_isci(env, kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(3L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)                     # A sürümü işçide okunuyor
    testthat::expect_length(kayit$cozumler, 1L)
    # Hazırlık sürerken "2" yeni mesaj aldı; sekme açılınca B eşzamanlı okunur.
    yeni <- shiny::isolate(sohbetler())
    yeni[["2"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    yeni[["2"]]$message_count <- 2L
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    kayit$etiket <- "B sürümü"
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(messages_cache()[["2"]]$rows[[1]]$Soru, "B sürümü")
    # Eski A sonucu şimdi gelir: B korunmalı, damga güncel kalmalı.
    kayit$cozumler[[1]]$resolve(.surum_satirlari(kayit$cozumler[[1]]$ids, "A sürümü"))
    .zincir_bitene_dek(session)
    testthat::expect_identical(messages_cache()[["2"]]$rows[[1]]$Soru, "B sürümü",
                               info = "eski eşzamansız sonuç yeni önbellek kaydını ezmemeli")
    testthat::expect_identical(messages_cache()[["2"]]$stamp, stamp_for_chat(yeni[["2"]]))
    # Hazırlık sonucu son bildirimde "hazır": tüm kimlikler önbellekte.
    testthat::expect_false(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded))
  }))

  # Ters sıra: hazırlık önce tamamlanır (A), sonra damga değişir ve B okunur.
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  .elle_cozulen_isci(env, kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(3L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(hazirla = 1)
    kayit$cozumler[[1]]$resolve(.surum_satirlari(kayit$cozumler[[1]]$ids, "A sürümü"))
    .zincir_bitene_dek(session)
    testthat::expect_identical(messages_cache()[["2"]]$rows[[1]]$Soru, "A sürümü")
    yeni <- shiny::isolate(sohbetler())
    yeni[["2"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    kayit$etiket <- "B sürümü"
    cagri_once <- kayit$cagri
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    # Arka plan hazırlığı sayfa etkinleştirmesi değildir: geçmiş açılmadan liste
    # değişimi olay döngüsünde eşzamanlı okuma yapmaz.
    testthat::expect_identical(kayit$cagri, cagri_once)
    # Sayfa açılınca yalnız damgası değişen söyleşi güncel sürümüyle okunur.
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(messages_cache()[["2"]]$rows[[1]]$Soru, "B sürümü")
    testthat::expect_identical(messages_cache()[["1"]]$rows[[1]]$Soru, "A sürümü")
    testthat::expect_identical(utils::tail(kayit$kimlikler, 1L)[[1]], "2")
  }))
})

testthat::test_that("hazırlık sürerken eklenen söyleşi eksikse hazır-olma 'kısmen'dir; silinen söyleşi eksik sayılmaz", {
  # Eklenen söyleşi: gönderilen kimlikler önbellekte olsa da güncel ilk sayfa eksik.
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  .elle_cozulen_isci(env, kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(3L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    yeni <- c(list("9" = list(title = "Yeni", timestamp = as.POSIXct("2026-07-03 10:00:00", tz = "UTC"),
                              last_message_timestamp = as.POSIXct("2026-07-03 10:00:00", tz = "UTC"))),
              shiny::isolate(sohbetler()))
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    kayit$cozumler[[1]]$resolve(.surum_satirlari(kayit$cozumler[[1]]$ids, "A sürümü"))
    .zincir_bitene_dek(session)
    testthat::expect_true(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded),
                          info = "yeni söyleşi önbellekte yokken ilk sayfa 'hazır' bildirilmemeli")
    # Sayfa açılınca yeni söyleşi okunur ve durum 'hazır'a döner.
    session$setInputs(external_refresh_trigger = 1)
    .zincir_bitene_dek(session)
    testthat::expect_false(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded))
  }))

  # Silinen söyleşi: okunmamış sayılmaz; kalanlar önbellekteyse durum 'hazır'.
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  .elle_cozulen_isci(env, kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(3L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    kalan <- shiny::isolate(sohbetler())
    kalan[["2"]] <- NULL
    shiny::isolate(sohbetler(kalan))
    session$flushReact()
    kayit$cozumler[[1]]$resolve(.surum_satirlari(setdiff(kayit$cozumler[[1]]$ids, "2"), "A sürümü"))
    .zincir_bitene_dek(session)
    testthat::expect_false(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded),
                           info = "silinen söyleşi hazır-olmayı 'kısmen' bırakmamalı")
  }))
})

testthat::test_that("önceki tam liste nesline ait ertelenmiş hazırlık tetiği yok sayılır", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    nesil <- new.env(); nesil$guncel <- 4L
    session$userData$mergen_gecmis_hazirla_gecerli <- function(t) identical(as.integer(t), nesil$guncel)
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 3)                     # önceki sahibin tetiği
    .zincir_bitene_dek(session)
    testthat::expect_length(kayit$isci, 0L)
    testthat::expect_length(kayit$isaret, 0L)
    session$setInputs(hazirla = 4)                     # güncel nesil
    .zincir_bitene_dek(session)
    testthat::expect_length(kayit$isci, 1L)
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)
  }))
})

testthat::test_that("hazırlık sürerken damgası değişen söyleşi eski damgayla yazılmaz ve 'hazır' bildirilmez", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  .elle_cozulen_isci(env, kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(3L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    testthat::expect_length(kayit$cozumler, 1L)
    # Sekme hiç açılmadan "2" yeni mesaj alır: eşzamanlı okuma olmaz, sürüm değişmez.
    yeni <- shiny::isolate(sohbetler())
    yeni[["2"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    yeni[["2"]]$message_count <- 2L
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    kayit$cozumler[[1]]$resolve(.surum_satirlari(kayit$cozumler[[1]]$ids, "A sürümü"))
    .zincir_bitene_dek(session)
    testthat::expect_null(messages_cache()[["2"]],
                          info = "eski satırlar eski damgayla önbelleğe yazılmamalı")
    testthat::expect_identical(messages_cache()[["1"]]$rows[[1]]$Soru, "A sürümü")
    testthat::expect_true(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded),
                          info = "yeni mesajı eksik hazırlık 'hazır' bildirilmemeli")
    # Sekme açılınca yalnız değişen söyleşi güncel damgasıyla okunur; durum 'hazır'.
    kayit$etiket <- "B sürümü"
    session$setInputs(external_refresh_trigger = 1)
    .zincir_bitene_dek(session)
    testthat::expect_identical(messages_cache()[["2"]]$rows[[1]]$Soru, "B sürümü")
    testthat::expect_identical(messages_cache()[["2"]]$stamp, stamp_for_chat(yeni[["2"]]))
    testthat::expect_false(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded))
  }))
})

testthat::test_that("görsel silme düşürmesi uçuştaki hazırlık okumasının silinmiş satırları geri yazmasını engeller", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  .elle_cozulen_isci(env, kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    # "2" henüz önbellekte YOK; görsel silindi ve düşürme çağrıldı.
    testthat::expect_false("2" %in% names(messages_cache()))
    session$userData$mergen_gecmis_onbellek_dusur("2")
    kayit$cozumler[[1]]$resolve(.surum_satirlari(kayit$cozumler[[1]]$ids, "[Görsel: silinen.png]"))
    .zincir_bitene_dek(session)
    testthat::expect_false("2" %in% names(messages_cache()),
                           info = "silinmiş görsel alıntısı önbelleğe geri yazılmamalı")
    testthat::expect_setequal(names(messages_cache()), c("1", "3"))
    # Düşürülen söyleşi okunmadığı için durum dürüstçe "kısmen".
    testthat::expect_true(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded))
    # Sonraki ziyaret yalnızca düşen söyleşiyi güncel içerikle okur.
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$kimlikler[[length(kayit$kimlikler)]], "2")
  }))

  # Tüm görseller silindi (kimliksiz düşürme): uçuştaki sonuç hiçbir söyleşiye yazılmaz.
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  .elle_cozulen_isci(env, kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(hazirla = 1)
    session$userData$mergen_gecmis_onbellek_dusur()
    kayit$cozumler[[1]]$resolve(.surum_satirlari(kayit$cozumler[[1]]$ids, "[Görsel: silinen.png]"))
    .zincir_bitene_dek(session)
    testthat::expect_length(messages_cache(), 0L)
  }))
})

testthat::test_that("görsel silme düşürmesi ilgisiz arka plan ısıtmasını iptal etmez", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)    # 130 eksik: 3 parti planlandı
    son <- Sys.time() + 5
    while (kayit$cagri < 1L && Sys.time() < son) later::run_now(0.02, all = FALSE)
    testthat::expect_identical(kayit$cagri, 1L, info = "ilk parti süre içinde çalışmalı")
    nesil <- isitma$nesil
    session$userData$mergen_gecmis_onbellek_dusur("5")
    testthat::expect_identical(isitma$nesil, nesil)
    .zincir_bitene_dek(session)
    testthat::expect_identical(kayit$cagri, 3L, info = "kalan partiler koşmalı")
    testthat::expect_identical(length(messages_cache()), 129L)
    testthat::expect_false("5" %in% names(messages_cache()))
  }))
})

testthat::test_that("130+ söyleşi ısıtılırken araya giren okunamayan yeni söyleşi hazır-olmayı yanlışlıkla 'tam' bildirtmez", {
  kayit <- .yeni_gecmis_kaydi()
  kayit$basarisiz <- "131"
  env <- .gecmis_modul_ortami(kayit)
  # "Isıtma sürerken" durumu duvar saatine bağlı kalmasın: partiler arası
  # bekleme uzatılır (GC/yük duraklaması ısıtmayı erken bitirip testi oynatmaz).
  asil_isitma <- env$historyBackgroundWarm
  env$historyBackgroundWarm <- function(..., delay_sec) asil_isitma(..., delay_sec = 0.5)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)    # 130 eksik: ısıtma başladı
    testthat::expect_true(isTRUE(isitma$aktif))
    # Isıtma sürerken yeni söyleşi geldi; anlık okuması başarısız.
    shiny::isolate(sohbetler(.gecmis_sohbetleri(131L)))
    session$flushReact()
    testthat::expect_true("131" %in% unlist(kayit$kimlikler), info = "yeni söyleşi ısıtma sırasında denenmeli")
    testthat::expect_false("history_rows_ready" %in% kayit$isaret, info = "ısıtma bitmeden hazır bildirilmemeli")
    .zincir_bitene_dek(session)
    testthat::expect_identical(length(messages_cache()), 130L)
    testthat::expect_false("131" %in% names(messages_cache()))
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)
    # Hiçbir bildirim "tam" demez: okunamayan söyleşi tüm geri çağrılarda kısmen sayılır.
    testthat::expect_true(all(vapply(kayit$detay, function(d) isTRUE(d$degraded), logical(1))),
                          info = "başarısız okuma varken çelişkili 'hazır' bildirimi olmamalı")
    # Aynı damgayla yeniden deneme döngüsü yok.
    testthat::expect_identical(sum(unlist(kayit$kimlikler) == "131"), 1L)
  }))
})

testthat::test_that("ısıtma sırasında önce okunamayıp sonra toparlanan söyleşi bekleyen geri çağrılara çelişkili sonuç vermez", {
  kayit <- .yeni_gecmis_kaydi()
  kayit$basarisiz <- "131"
  env <- .gecmis_modul_ortami(kayit)
  # "Isıtma sürerken" durumu duvar saatine bağlı kalmasın: partiler arası
  # bekleme uzatılır (GC/yük duraklaması ısıtmayı erken bitirip testi oynatmaz).
  asil_isitma <- env$historyBackgroundWarm
  env$historyBackgroundWarm <- function(..., delay_sec) asil_isitma(..., delay_sec = 0.5)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)    # 130 eksik: ısıtma başladı
    shiny::isolate(sohbetler(.gecmis_sohbetleri(131L)))
    session$flushReact()                               # "131" anlık okuması başarısız
    testthat::expect_false("131" %in% names(messages_cache()))
    testthat::expect_true(isTRUE(isitma$aktif), info = "toparlanma ısıtma SÜRERKEN olmalı")
    # "131" yeni mesaj aldı (damga değişti) ve artık okunabiliyor.
    kayit$basarisiz <- character()
    yeni <- .gecmis_sohbetleri(131L)
    yeni[["131"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    testthat::expect_identical(sum(unlist(kayit$kimlikler) == "131"), 2L)
    .zincir_bitene_dek(session)
    testthat::expect_identical(length(messages_cache()), 131L)
    testthat::expect_gte(length(kayit$detay), 2L)
    # Tüm bekleyen geri çağrılar aynı (güncel) sonucu alır: hiçbiri "kısmen" değildir.
    testthat::expect_false(any(vapply(kayit$detay, function(d) isTRUE(d$degraded), logical(1))),
                           info = "toparlanan okuma eski hata nedeniyle kısmen bildirilmemeli")
  }))
})

testthat::test_that("geçmiş işçi okuması dar açık sözleşmeyle gönderilir; geçersiz kimlikte işçiye gidilmez", {
  testthat::skip_if_not_installed("promises")
  testthat::skip_if_not_installed("later")
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  for (f in c("helpers_db_chat_read_queries.R", "helpers_startup_chat_preview.R",
              "module_chat_history_background.R")) {
    source(file.path(kok, "R", f), encoding = "UTF-8", local = env)
  }
  env$load_history_rows_batch <- function(chat_ids, user_id = NULL, result = NULL) {
    list(ham = result, ids = chat_ids, uid = user_id)
  }
  rec <- new.env(parent = emptyenv())
  env$tracked_future_promise <- function(task_fn, task_type = "generic", session_token = NULL,
                                         meta = list(), globals = NULL,
                                         dependency_mode = c("auto", "explicit"), packages = NULL, ...) {
    rec$adet <- (rec$adet %||% 0L) + 1L
    rec$task_type <- task_type
    rec$mode <- match.arg(dependency_mode)
    rec$globals <- globals
    promises::promise_resolve(data.frame(ChatID = 3L))
  }
  sonuc <- NULL
  later::with_temp_loop({
    promises::then(env$history_rows_worker_promise(c("3", "4"), 7L, "oturum"), function(v) sonuc <<- v)
    son <- Sys.time() + 5
    while (is.null(sonuc) && Sys.time() < son) later::run_now(0.02)
  })
  testthat::expect_identical(rec$task_type, "history_rows_prepare")
  testthat::expect_identical(rec$mode, "explicit")
  testthat::expect_setequal(names(rec$globals), c(
    "gecmis_sql", "gecmis_parametreler", "gecmis_dsn", "gecmis_kodlama", "gecmis_ad_kodlama",
    "gecmis_login", "gecmis_sure", "mergen_bounded_db_fetch_raw"))
  # Sahiplik SQL içindedir: kullanıcı kimliği son parametre, söyleşiler tam sayı.
  testthat::expect_identical(rec$globals$gecmis_parametreler, list(3L, 4L, 7L))
  testthat::expect_match(rec$globals$gecmis_sql, "c.UserID = ?", fixed = TRUE)
  testthat::expect_true(is.finite(rec$globals$gecmis_sure) && rec$globals$gecmis_sure > 0)
  for (nm in setdiff(names(rec$globals), "mergen_bounded_db_fetch_raw")) {
    testthat::expect_true(is.atomic(rec$globals[[nm]]) || is.list(rec$globals[[nm]]), label = nm)
    testthat::expect_false(is.environment(rec$globals[[nm]]), label = nm)
  }
  # Biçimlendirme tek okuyucuda: ham çerçeve DB'siz yoluyla aynı kimlik ve kullanıcıyla verilir.
  testthat::expect_identical(sonuc$ids, c("3", "4"))
  testthat::expect_identical(sonuc$uid, 7L)
  testthat::expect_identical(sonuc$ham, data.frame(ChatID = 3L))

  # Kimlik doğrulanamıyorsa (0, NA) ya da kimlik sayısal değilse işçiye gidilmez.
  rec$adet <- 0L
  for (gecersiz in list(list(c("3"), 0L), list(c("3"), NA_integer_), list(c("x"), 7L))) {
    hata <- NULL
    later::with_temp_loop({
      promises::catch(env$history_rows_worker_promise(gecersiz[[1]], gecersiz[[2]]), function(e) hata <<- conditionMessage(e))
      son <- Sys.time() + 5
      while (is.null(hata) && Sys.time() < son) later::run_now(0.02)
    })
    testthat::expect_false(is.null(hata))
  }
  testthat::expect_identical(rec$adet, 0L)
})

testthat::test_that("geçmiş okuma hatası günlüğe bağlantı ayrıntısı maskelenmiş yazılır", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  # Sürücü hatası bağlantı tanımlayıcıları taşır (örnek değerler, gerçek değil).
  env$history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL, ...) {
    promises::promise_reject(simpleError("[ODBC] baglanti hatasi DSN=ornek_dsn;UID=ornek_kullanici;PWD=ornek_parola"))
  }
  # Hata paylaşılan logger'a (log_warn) gider; konsola ham cat() yazılmaz.
  logger_kayitlari <- character()
  env$log_warn <- function(msg, ...) logger_kayitlari <<- c(logger_kayitlari, msg)
  cikti <- utils::capture.output(later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(2L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    .zincir_bitene_dek(session)
    testthat::expect_true(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded))
  })))
  gunluk <- paste(logger_kayitlari, collapse = "\n")
  testthat::expect_match(gunluk, "açılış hazırlığı okunamadı", fixed = TRUE)
  testthat::expect_false(grepl("ornek_dsn|ornek_kullanici|ornek_parola", gunluk))
  testthat::expect_false(grepl("açılış hazırlığı okunamadı", paste(cikti, collapse = "\n"), fixed = TRUE))
})

testthat::test_that("işçide okunmuş ham geçmiş çerçevesi DB'ye gitmeden aynı biçimlendiriciden geçer; kimlik koruması sürer", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(kok, "R", "helpers_db_chat_readers.R"), encoding = "UTF-8", local = env)
  env$get_connection <- function(...) stop("DB'ye gidilmemeli (test)")
  ham <- data.frame(ChatID = c(3L, 3L), ChatTitle = c("Başlık çğış", "Başlık çğış"),
                    MessageTimestamp = as.POSIXct(c("2026-07-01 10:00:00", "2026-07-01 11:00:00"), tz = "UTC"),
                    Soru = c("Soru bir", "Soru iki"), Cevap = c("Yanıt bir", "Yanıt iki"),
                    stringsAsFactors = FALSE)
  sonuc <- env$load_history_rows_batch(c("3", "4"), user_id = 7L, result = ham)
  testthat::expect_identical(names(sonuc), c("3", "4"))
  testthat::expect_length(sonuc[["3"]], 2L)
  testthat::expect_identical(sonuc[["3"]][[1]]$Chat_ID, "Başlık çğış")
  testthat::expect_identical(sonuc[["3"]][[1]]$Tarih, "01.07.2026 - 10:00")
  testthat::expect_identical(sonuc[["4"]], list())
  # Geçersiz kimlikte (çerçeve verilse de) sonuç üretilmez.
  testthat::expect_identical(env$load_history_rows_batch(c("3"), user_id = 0L, result = ham), list())
})

testthat::test_that("sayfa yüklenirken gelen tarih aralığı geçmişi etkinleştirmez; tam liste gelince okuma yapılmaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(3L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(date_range = c("2026-06-01", "2026-07-31"))
    testthat::expect_false(isTRUE(isitma$etkin))
    shiny::isolate(sohbetler(.gecmis_sohbetleri(10L)))
    session$flushReact()
    .zincir_bitene_dek(session)
    testthat::expect_identical(kayit$cagri, 0L, info = "açılışta geçmiş okunmamalı")
    # Kullanıcı Geçmiş'i açınca okunur; sonraki aralık değişimi uygulanır.
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$cagri, 1L)
    session$setInputs(date_range = c("2026-07-01", "2026-07-31"))
    testthat::expect_identical(kayit$cagri, 2L)
  }))
})

testthat::test_that("Yenile sıfırlamayı hemen yayımlar, başarıyı yeni satırlar yayımlanınca bildirir", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  kayit$toast <- character()
  env$showToast <- function(session, message, ...) kayit$toast <- c(kayit$toast, message)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(130L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    .zincir_bitene_dek(session)
    testthat::expect_identical(nrow(filtered_history()), 130L)
    kayit$etiket <- "yenilenmiş soru"
    session$setInputs(refresh_history = 1)
    # Partili yenileme sürüyor: eski görüntü "güncel" gösterilmez, başarı henüz duyurulmaz.
    testthat::expect_identical(nrow(filtered_history()), 0L)
    testthat::expect_false(any(kayit$toast == "Geçmiş tablosu yenilendi."))
    .zincir_bitene_dek(session)
    testthat::expect_identical(sum(kayit$toast == "Geçmiş tablosu yenilendi."), 1L)
    testthat::expect_identical(nrow(filtered_history()), 130L)
    testthat::expect_true(all(filtered_history()$Soru == "yenilenmiş soru"))
  }))
})

testthat::test_that("sekme açılışı ilk sayfanın yaşlı kayıtlarını yeniden doğrular; taze kayıtları okumaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(3L)), current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$cagri, 1L)
    # Taze kayıtlar: ikinci ziyaret DB'ye gitmez.
    session$setInputs(external_refresh_trigger = 2)
    testthat::expect_identical(kayit$cagri, 1L)
    # Başka oturum alıntıyı yerinde değiştirdi (damga aynı); kayıtlar yaşlandı.
    kayit$etiket <- "güncel alıntı çğış"
    withr::with_options(list(mergen.history_revalidate_secs = 0), {
      Sys.sleep(0.01)
      session$setInputs(external_refresh_trigger = 3)
    })
    testthat::expect_identical(kayit$cagri, 2L)
    testthat::expect_setequal(kayit$kimlikler[[2]], c("1", "2", "3"))
    testthat::expect_true(all(filtered_history()$Soru == "güncel alıntı çğış"))
  }))
})

testthat::test_that("başarısız sekme okuması süren açılış hazırlığının başarılı sonucunu attırmaz", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  # Hazırlık işçisi DB hatasından bağımsız başarılı sonuç döndürür (bir sonraki turda).
  env$history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL, ...) {
    promises::promise(function(resolve, reject) later::later(function() {
      resolve(stats::setNames(lapply(chat_ids, function(id) list(list(
        Chat_ID = paste("Söyleşi", id), Tarih = "01.07.2026 - 10:00", Soru = "hazırlık sorusu", Cevap = "Yanıt"))),
        chat_ids))
    }, 0.2))
  }
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(2L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    # Hazırlık sürerken kullanıcı Geçmiş'i açar; eşzamanlı okuma başarısız olur.
    kayit$hata <- TRUE
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_length(messages_cache(), 0L)
    .zincir_bitene_dek(session)
    # Sahip ve damga değişmedi: hazırlığın başarılı sonucu yazılır.
    testthat::expect_setequal(names(messages_cache()), c("1", "2"))
    testthat::expect_identical(messages_cache()[["1"]]$rows[[1]]$Soru, "hazırlık sorusu")
  }))
})

testthat::test_that("260 söyleşilik kesintide takip partisi deneme defterini korur ve kısmi tamamlanır", {
  kayit <- .yeni_gecmis_kaydi()
  kayit$hata <- TRUE
  env <- .gecmis_modul_ortami(kayit)
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(130L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    # Isıtma sürerken 130 yeni söyleşi daha gelir (toplam 260).
    shiny::isolate(sohbetler(.gecmis_sohbetleri(260L)))
    session$flushReact()
    .zincir_bitene_dek(session)
    denenen <- unlist(kayit$kimlikler)
    testthat::expect_setequal(denenen, as.character(1:260))
    testthat::expect_identical(anyDuplicated(denenen), 0L)
    testthat::expect_length(messages_cache(), 0L)
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)
    testthat::expect_true(isTRUE(utils::tail(kayit$detay, 1)[[1]]$degraded))
  }))
})

testthat::test_that("işçi hazır değilken otomatik hazirla DB okuması başlatmaz, kısmen hazır bildirir", {
  testthat::skip_if_not_installed("future")
  eski_plan <- future::plan(future::sequential)
  on.exit(future::plan(eski_plan), add = TRUE)
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_startup_chat_preview.R"),
         encoding = "UTF-8", local = env)
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(2L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    .zincir_bitene_dek(session)
    # Sequential planda otomatik hazırlık DB'ye gitmez, kısmen hazır sinyali verir.
    testthat::expect_identical(kayit$cagri, 0L)
    testthat::expect_length(kayit$isci, 0L)
    testthat::expect_true("history_rows_ready" %in% kayit$isaret)
    testthat::expect_true(isTRUE(utils::tail(kayit$detay, 1)[[1]]$degraded))
    # İlk sekme ziyareti normal çalışmaya devam eder.
    session$setInputs(external_refresh_trigger = 1)
    testthat::expect_identical(kayit$cagri, 1L)
    testthat::expect_setequal(names(messages_cache()), c("1", "2"))
  }))
})

testthat::test_that("açılış işçisi liste_baslik tabanını saklar: yeni DB başlığı korunur, sonraki yerel ad değişimi yansır", {
  kayit <- .yeni_gecmis_kaydi()
  env <- .gecmis_modul_ortami(kayit)
  env$mergen_startup_async_worker_ready <- function() TRUE
  env$history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL, ...) {
    promises::promise_resolve(stats::setNames(lapply(chat_ids, function(id) list(list(
      Chat_ID = "DB Yeni Başlık", Tarih = "01.07.2026 - 10:00", Soru = "Soru", Cevap = "Yanıt"))),
      chat_ids))
  }
  sohbetler <- shiny::reactiveVal(.gecmis_sohbetleri(1L))
  later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = sohbetler, current_user_id = function() 7L), {
    session$flushReact()
    session$setInputs(hazirla = 1)
    .zincir_bitene_dek(session)
    # Yerel liste başlığı değişmedi -> DB'den gelen yeni başlık korunur.
    testthat::expect_identical(filtered_history()$Chat_ID[1], "DB Yeni Başlık")
    # Gönderim sonrası yerel yeniden adlandırma -> yeni yerel başlık görünür.
    guncel <- shiny::isolate(sohbetler())
    guncel[["1"]]$title <- "Yerel Ad"
    shiny::isolate(sohbetler(guncel))
    session$flushReact()
    testthat::expect_identical(filtered_history()$Chat_ID[1], "Yerel Ad")
  }))
})
