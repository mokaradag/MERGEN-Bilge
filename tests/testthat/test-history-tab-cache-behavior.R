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
    stats::setNames(lapply(chat_ids, function(id) list(list(
      Chat_ID = paste("Söyleşi", id), Tarih = "01.07.2026 - 10:00",
      Soru = "Türkçe soru çğış", Cevap = "Yanıt"
    ))), as.character(chat_ids))
  }
  # Açılış hazırlığı işçi sınırından geçer: sahte işçi sonucu bir sonraki
  # döngü turunda (eşzamansız) aynı sahte okuyucudan üretir.
  env$history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL) {
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
    oncesi <- hesap
    .zincir_bitene_dek(session)
    session$flushReact()
    testthat::expect_identical(length(messages_cache()), 300L)
    testthat::expect_true(all(lengths(kayit$kimlikler) <= 60L))
    # 5 arka plan partisi için tablo en çok bir kez (sondaki yayında) yeniden kurulur.
    testthat::expect_lte(hesap - oncesi, 1L)
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
    session$flushReact()
    session$setInputs(external_refresh_trigger = 1)
    shiny::isolate(sohbetler(.gecmis_sohbetleri(200L)))
    session$flushReact()
    .zincir_bitene_dek(session)
    # 130 + 70 kimlik, her biri en fazla bir kez denenir (60'lık partiler).
    testthat::expect_lte(kayit$cagri, 5L)
    testthat::expect_length(messages_cache(), 0L)
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
    testthat::expect_false("5" %in% names(shiny::isolate(messages_cache())))
    # "5" yeni mesaj aldı (damga değişti) ve artık okunabiliyor.
    kayit$basarisiz <- character()
    yeni <- shiny::isolate(sohbetler())
    yeni[["5"]]$last_message_timestamp <- as.POSIXct("2026-07-02 09:00:00", tz = "UTC")
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    .zincir_bitene_dek(session)
    testthat::expect_identical(messages_cache()[["5"]]$stamp, stamp_for_chat(yeni[["5"]]))
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
    session$setInputs(date_range = c("2026-06-01", "2026-07-31"))   # 130 eksik: ısıtma
    son <- Sys.time() + 5
    while (kayit$cagri < 1L && Sys.time() < son) later::run_now(0.02, all = FALSE)
    # "100" ikinci partide planlı; aralık dışına taşınır (etkinlik 2026-09).
    yeni <- shiny::isolate(sohbetler())
    yeni[["100"]]$last_message_timestamp <- as.POSIXct("2026-09-15 09:00:00", tz = "UTC")
    shiny::isolate(sohbetler(yeni))
    session$flushReact()
    .zincir_bitene_dek(session)
    testthat::expect_false("100" %in% unlist(kayit$kimlikler))
    testthat::expect_false("100" %in% names(messages_cache()))
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
  env$history_rows_worker_promise <- function(chat_ids, user_id, session_token = NULL) {
    promises::promise_reject(simpleError("[ODBC] baglanti hatasi DSN=ornek_dsn;UID=ornek_kullanici;PWD=ornek_parola"))
  }
  cikti <- utils::capture.output(later::with_temp_loop(shiny::testServer(env$historyServer,
                    args = list(all_messages = shiny::reactive(.gecmis_sohbetleri(2L)), current_user_id = function() 7L), {
    session$userData$saved_chats_full_loaded <- TRUE
    session$userData$mergen_yonetim_hazir <- .isaretleyici(kayit)
    session$flushReact()
    session$setInputs(hazirla = 1)
    .zincir_bitene_dek(session)
    testthat::expect_true(isTRUE(kayit$detay[[length(kayit$detay)]]$degraded))
  })))
  gunluk <- paste(cikti, collapse = "\n")
  testthat::expect_match(gunluk, "açılış hazırlığı okunamadı", fixed = TRUE)
  testthat::expect_false(grepl("ornek_dsn|ornek_kullanici|ornek_parola", gunluk))
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
