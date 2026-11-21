# ==============================================================================
# Dosya Yolu: tests/testthat/test-worker-future-payload-behavior.R
# Açıklama: tracked_future_promise() future yolunda işçiye giden yükü korur.
#           promises::as.promise() dönüşüm sonucunu future ortamına
#           "converted_promise" özniteliği olarak yazıyor, future da oluşturma
#           anındaki çağrı yığınını (sys.calls) saklıyordu. future'ın iç
#           clusterCall kapanışları bu ortamı yakaladığı için then geri
#           çağrılarına bağlı büyük nesneler (gerçekte Shiny oturum grafiği,
#           yüzlerce MB) her gönderim/tamamlanmada işçi soketine serileştirilip
#           ana olay döngüsünü saniyelerce blokluyordu. Gerçek tek işçili yerel
#           PSOCK kümesiyle soket gönderimleri ölçülür; ağ/DB gerekmez.
# ==============================================================================

.gelecek_yuk_olcumu <- function(senaryo) {
  testthat::skip_if_not_installed("parallelly")
  testthat::skip_if_not_installed("future")
  testthat::skip_if_not_installed("promises")

  ns <- asNamespace("parallel")
  asil <- get("sendData.SOCK0node", envir = ns)
  boyutlar <- numeric(0)
  olcen <- function(node, data) {
    boyutlar <<- c(boyutlar, length(serialize(data, NULL)))
    asil(node, data)
  }
  ata <- function(f) {
    unlockBinding("sendData.SOCK0node", ns)
    assign("sendData.SOCK0node", f, envir = ns)
    lockBinding("sendData.SOCK0node", ns)
    registerS3method("sendData", "SOCK0node", f, envir = ns)
  }

  eski_plan <- future::plan()
  # Ölçüm yalnızca SOCK0node gönderimini sarar: useXDR = FALSE açıkça verilir
  # (parallelly.makeNodePSOCK.useXDR seçeneği ortamda TRUE olsa da düğüm türü
  # sabit kalır; test ortamdan bağımsız ve belirlenimcidir).
  kume <- parallelly::makeClusterPSOCK(1L, outfile = NULL, useXDR = FALSE)
  testthat::expect_s3_class(kume[[1]], "SOCK0node")
  on.exit({
    ata(asil)
    future::plan(eski_plan)
    try(parallel::stopCluster(kume), silent = TRUE)
  }, add = TRUE)
  future::plan(future::cluster, workers = kume, persistent = TRUE)
  ata(olcen)

  sonuc <- senaryo()
  list(sonuc = sonuc, en_buyuk = max(c(0, boyutlar)), adet = length(boyutlar))
}

.later_bosalt <- function(kosul, sure = 20) {
  bitis <- Sys.time() + sure
  while (!isTRUE(kosul()) && Sys.time() < bitis) later::run_now(0.05)
}

testthat::test_that("meşgul işçi varken kuyruktaki işin geri çağrı grafiği işçiye gönderilmez", {
  basladi <- tempfile("isci_basladi_")
  serbest <- tempfile("isci_serbest_")
  on.exit(unlink(c(basladi, serbest)), add = TRUE)
  olcum <- .gelecek_yuk_olcumu(function() {
    durum <- new.env()
    # 1) Tek işçiyi meşgul et: iş başladığını dosyayla bildirir ve serbest
    #    bırakma işareti gelene dek (süre sınırlı) bekler. Süreye değil açık
    #    sinyallere dayanır; açık sözleşme yalnızca iki yolu taşır.
    mesgul_is <- function() {
      file.create(basladi_yolu)
      son <- Sys.time() + 30
      while (!file.exists(serbest_yolu) && Sys.time() < son) Sys.sleep(0.02)
      1L
    }
    tracked_future_promise(mesgul_is, task_type = "test_mesgul", dependency_mode = "explicit",
                           globals = list(basladi_yolu = basladi, serbest_yolu = serbest))
    .later_bosalt(function() file.exists(basladi))
    testthat::expect_true(file.exists(basladi), info = "meşgul iş işçide başlamış olmalı")
    # 2) İşçi doluyken ikinci iş; then geri çağrısı büyük bir nesneyi yakalar
    #    (gerçek uygulamada oturum/reaktif grafik).
    oturum_benzeri <- function() {
      buyuk <- raw(20e6)
      p <- tracked_future_promise(function() 2L, task_type = "test_ikinci",
                                  dependency_mode = "explicit")
      promises::then(p, function(v) { length(buyuk); durum$deger <- v })
    }
    oturum_benzeri()
    # İkinci iş kuyrukta bekler (tek işçi meşgul); örtüşme kanıtlanmadan
    # meşgul iş serbest bırakılmaz.
    .later_bosalt(function() FALSE, sure = 0.3)
    testthat::expect_null(durum$deger, label = "meşgul işçi varken ikinci işin sonucu")
    file.create(serbest)
    .later_bosalt(function() !is.null(durum$deger))
    durum$deger
  })

  testthat::expect_identical(olcum$sonuc, 2L)
  testthat::expect_gt(olcum$adet, 0L)
  # Eski yol ~20 MB'lık yükü birden çok kez gönderiyordu; future'ın kendi
  # arka uç nesnesi birkaç MB'ın altında kalır.
  testthat::expect_lt(olcum$en_buyuk, 5e6)
})

testthat::test_that("later geri çağrısından gönderimde çağrı yığını işçiye taşınmaz", {
  olcum <- .gelecek_yuk_olcumu(function() {
    durum <- new.env()
    # Çağrı yığınına gömülü büyük nesne (do.call ile argüman değeri olarak).
    gonder <- function(yuk) {
      p <- tracked_future_promise(function() 3L, task_type = "test_yigin",
                                  dependency_mode = "explicit")
      promises::then(p, function(v) durum$deger <- v)
    }
    later::later(function() do.call(gonder, list(raw(20e6))), 0)
    .later_bosalt(function() !is.null(durum$deger))
    durum$deger
  })

  testthat::expect_identical(olcum$sonuc, 3L)
  testthat::expect_lt(olcum$en_buyuk, 5e6)
})

testthat::test_that("SSE görev kapanışı her istekte aynı gövde ve dar ortam şekline sahiptir", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_true_streaming_task.R"),
             envir = env, keep.source = FALSE)
  a <- env$mergen_true_streaming_task_fn(list(1), list(model = "x"), "a.jsonl", "a.stop")
  b <- env$mergen_true_streaming_task_fn(list(2, 3), list(), "b.jsonl", "b.stop")
  # Isıtılan bağımlılık taraması önbelleği ancak gövde/ortam şekli aynıysa eşleşir.
  testthat::expect_identical(body(a), body(b))
  testthat::expect_setequal(ls(environment(a)), c("chat_history_for_sse", "settings_for_sse",
                                                  "stream_file_for_sse", "stop_file_for_sse"))
  testthat::expect_identical(parent.env(environment(a)), env)

  # İşlevsiz bir kapanış (ör. function() NULL) bu testi geçemez: kapanış
  # yakalanan argümanlarla gerçek SSE işçisini çağırmalıdır.
  cagrilar <- list()
  env$call_local_llm_sse_worker <- function(chat_history, current_settings, stream_file, stop_file) {
    cagrilar[[length(cagrilar) + 1L]] <<- list(chat_history, current_settings, stream_file, stop_file)
    "sse_sonucu"
  }
  testthat::expect_identical(a(), "sse_sonucu")
  testthat::expect_identical(b(), "sse_sonucu")
  testthat::expect_identical(cagrilar[[1]], list(list(1), list(model = "x"), "a.jsonl", "a.stop"))
  testthat::expect_identical(cagrilar[[2]], list(list(2, 3), list(), "b.jsonl", "b.stop"))
})

testthat::test_that("SSE görev kapanışı çağıranın çerçevesini tembel argümanla taşımaz", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_true_streaming_task.R"),
             envir = env, keep.source = FALSE)
  isleyici <- function() {
    buyuk_oturum_nesnesi <- raw(20e6)
    gecmis <- list("merhaba çğış")
    env$mergen_true_streaming_task_fn(gecmis, list(), "s.jsonl", "s.stop")
  }
  kapanis <- isleyici()
  # Argümanlar zorlandığı için serileştirilen kapanış işleyici çerçevesini
  # (ve içindeki büyük nesneyi) içermez.
  testthat::expect_lt(length(serialize(kapanis, NULL)), 1e6)
})

testthat::test_that("tüm future görevleri üretim yolundan promises'ın paylaşılan iş kuyruğuna gönderilir", {
  testthat::skip_if_not_installed("future")
  eski_plan <- future::plan()
  on.exit(future::plan(eski_plan), add = TRUE)
  future::plan(future::sequential)
  # Gerçek gönderim yardımcısı çalıştırılır; paylaşılan kuyruk erişimcisi sayaçlı
  # bir kuyrukla değiştirilir. Görev başına ayrı kuyruk kuran ya da kuyruğu
  # atlayan bir gönderim bu sayaçları artırmaz ve test başarısız olur.
  erisim <- 0L
  planlanan <- 0L
  sahte_kuyruk <- list(schedule_work = function(fn) {
    planlanan <<- planlanan + 1L
    fn()
  })
  testthat::local_mocked_bindings(
    future_promise_queue = function() {
      erisim <<- erisim + 1L
      sahte_kuyruk
    },
    .package = "promises"
  )
  durum <- new.env()
  durum$degerler <- list()
  # Görevler gerçek giriş noktasından (tracked_future_promise, açık mod, iptal
  # denetimi yok) gönderilir: yönlendirme paylaşılan kuyruğu atlarsa sayaç artmaz.
  for (i in 1:3) local({
    j <- i
    p <- tracked_future_promise(function() j, task_type = "kuyruk_testi",
                                dependency_mode = "explicit", globals = list(j = j))
    promises::then(p, onFulfilled = function(v) durum$degerler[[length(durum$degerler) + 1L]] <- v)
  })
  .later_bosalt(function() length(durum$degerler) == 3L, sure = 5)
  testthat::expect_identical(planlanan, 3L)
  testthat::expect_identical(erisim, 3L)
  testthat::expect_setequal(unlist(durum$degerler), 1:3)
})

testthat::test_that("yoklamada beklenmeyen hata promise'i asılı bırakmadan reddeder", {
  testthat::skip_if_not_installed("future")
  eski_plan <- future::plan()
  on.exit(future::plan(eski_plan), add = TRUE)
  future::plan(future::sequential)
  eski_bitti <- .worker_monitor_future_bitti
  on.exit(assign(".worker_monitor_future_bitti", eski_bitti, envir = globalenv()), add = TRUE)
  # İlk yoklama (promise kurucusu içinde) FALSE döner; hata PLANLANMIŞ ikinci
  # yoklamada yükselir: kurucunun kendi reddi testi yeşil tutamaz.
  yoklama <- 0L
  assign(".worker_monitor_future_bitti", function(f) {
    yoklama <<- yoklama + 1L
    if (yoklama == 1L) FALSE else stop("beklenmeyen_yoklama_hatasi")
  }, envir = globalenv())

  durum <- new.env()
  p <- worker_monitor_future_promise(list(task_fn = function() 9L), character(0))
  promises::then(p, onFulfilled = function(v) durum$deger <- v,
                 onRejected = function(e) durum$hata <- conditionMessage(e))
  .later_bosalt(function() !is.null(durum$hata) || !is.null(durum$deger), sure = 5)
  testthat::expect_match(durum$hata %||% "", "beklenmeyen_yoklama_hatasi")
  testthat::expect_gte(yoklama, 2L)
})

testthat::test_that("kuyrukta beklerken geçersizleşen iş işçiye başlatılmaz ve promise reddedilir", {
  testthat::skip_if_not_installed("future")
  baslatma <- 0L
  eski_baslat <- .worker_monitor_future_baslat
  on.exit(assign(".worker_monitor_future_baslat", eski_baslat, envir = globalenv()), add = TRUE)
  assign(".worker_monitor_future_baslat", function(...) { baslatma <<- baslatma + 1L; stop("başlatılmamalıydı") },
         envir = globalenv())
  sahte_kuyruk <- list(schedule_work = function(fn) fn())
  testthat::local_mocked_bindings(future_promise_queue = function() sahte_kuyruk, .package = "promises")
  durum <- new.env()
  # İzleme defterinde kaydı olmayan (oturum temizliğiyle silinmiş) görev başlatılmaz.
  p <- worker_monitor_future_promise(list(task_fn = function() 1L), character(0), gorev_kimligi = "kaydi_silinmis_gorev")
  promises::then(p, onFulfilled = function(v) durum$deger <- v, onRejected = function(e) durum$hata <- conditionMessage(e))
  .later_bosalt(function() !is.null(durum$hata) || !is.null(durum$deger), sure = 5)
  testthat::expect_identical(baslatma, 0L)
  testthat::expect_match(durum$hata %||% "", "geçersizleşti")
  # Oturum temizliği izleme kaydını silince tracked_future_promise işi başlatmaz.
  testthat::local_mocked_bindings(future_promise_queue = function() list(schedule_work = function(fn) {
    cleanup_worker_tasks_for_session("kapanan_oturum")
    fn()
  }), .package = "promises")
  durum2 <- new.env()
  p2 <- tracked_future_promise(function() 1L, task_type = "kapanan_oturum_testi", session_token = "kapanan_oturum",
                               dependency_mode = "explicit", globals = list())
  promises::then(p2, onFulfilled = function(v) durum2$deger <- v, onRejected = function(e) durum2$hata <- conditionMessage(e))
  .later_bosalt(function() !is.null(durum2$hata) || !is.null(durum2$deger), sure = 5)
  testthat::expect_identical(baslatma, 0L)
  testthat::expect_false(is.null(durum2$hata))
})

testthat::test_that("kuyrukta beklerken eskiyen iş (başlangıç yüklemi FALSE) işçiye başlatılmaz; izleme kaydı kapanır", {
  testthat::skip_if_not_installed("future")
  baslatma <- 0L
  eski_baslat <- .worker_monitor_future_baslat
  on.exit(assign(".worker_monitor_future_baslat", eski_baslat, envir = globalenv()), add = TRUE)
  assign(".worker_monitor_future_baslat", function(...) { baslatma <<- baslatma + 1L; stop("başlatılmamalıydı") },
         envir = globalenv())
  # Yüklem iş kuyruktan çıkarken sorulur: gönderimde geçerli, çıkışta eskimiş.
  gecerli <- TRUE
  testthat::local_mocked_bindings(future_promise_queue = function() list(schedule_work = function(fn) {
    gecerli <<- FALSE
    fn()
  }), .package = "promises")
  durum <- new.env()
  p <- tracked_future_promise(function() 1L, task_type = "eskiyen_gecmis_testi", session_token = "acik_oturum",
                              dependency_mode = "explicit", globals = list(), start_check = function() gecerli)
  promises::then(p, onFulfilled = function(v) durum$deger <- v, onRejected = function(e) durum$hata <- conditionMessage(e))
  .later_bosalt(function() !is.null(durum$hata) || !is.null(durum$deger), sure = 5)
  testthat::expect_identical(baslatma, 0L)
  testthat::expect_match(durum$hata %||% "", "eskidi")
  kalan <- Filter(function(t) identical(t$task_type, "eskiyen_gecmis_testi"), as.list(init_worker_monitor()$tasks))
  testthat::expect_length(kalan, 0L)
  # Yüklem hata verirse de iş başlatılmaz (kapalı-başarısız).
  durum2 <- new.env()
  p2 <- worker_monitor_future_promise(list(task_fn = function() 1L), character(0),
                                      baslangic_gecerli = function() stop("yüklem hatası"))
  promises::then(p2, onFulfilled = function(v) durum2$deger <- v, onRejected = function(e) durum2$hata <- conditionMessage(e))
  .later_bosalt(function() !is.null(durum2$hata) || !is.null(durum2$deger), sure = 5)
  testthat::expect_identical(baslatma, 0L)
  testthat::expect_false(is.null(durum2$hata))
})

testthat::test_that("future başlatıcı çağrı yığınını boşaltır ve hata promise'i reddeder", {
  testthat::skip_if_not_installed("future")
  eski_plan <- future::plan()
  on.exit(future::plan(eski_plan), add = TRUE)
  future::plan(future::sequential)

  f <- .worker_monitor_future_baslat(list(task_fn = function() 5L), character(0))
  testthat::expect_null(f[["calls"]])
  testthat::expect_identical(future::value(f), 5L)

  durum <- new.env()
  p <- worker_monitor_future_promise(list(task_fn = function() stop("kasitli_hata")), character(0))
  promises::then(p, onFulfilled = function(v) durum$deger <- v,
                 onRejected = function(e) durum$hata <- conditionMessage(e))
  .later_bosalt(function() !is.null(durum$hata) || !is.null(durum$deger), sure = 5)
  testthat::expect_match(durum$hata, "kasitli_hata")
})

testthat::test_that("otomatik modda görsel oluşturma kapanışı işleyici bağlamını (ctx) taşımaz", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(resolve_repo_root_for_tests(), "R", "server_handler_image_generation.R"),
             envir = env, keep.source = FALSE)
  isleyici <- function() {
    # Gerçek işleyicideki gibi büyük oturum bağlamı çerçevededir.
    ctx <- list(session = raw(20e6), values = new.env())
    env$mergen_image_generation_task_fn("istem çğış", "anahtar", "1024x1024", "hd", 7L, "42")
  }
  gorev <- isleyici()
  testthat::expect_setequal(ls(environment(gorev)),
                            c("prompt", "api_key", "size", "quality", "user_id", "chat_id"))
  testthat::expect_false(exists("ctx", envir = environment(gorev), inherits = FALSE))
  testthat::expect_lt(length(serialize(gorev, NULL)), 1e6)
  # Otomatik bağımlılık taraması kapanışın gerçekten kullandığı yardımcıyı bulur.
  env$generate_image <- function(...) list(...)
  if (exists("worker_monitor_detect_task_deps", mode = "function")) {
    bagimliliklar <- worker_monitor_detect_task_deps(gorev)
    testthat::expect_true("generate_image" %in% names(bagimliliklar$globals))
    testthat::expect_false("ctx" %in% names(bagimliliklar$globals))
  }
  sonuc <- gorev()
  testthat::expect_identical(sonuc$prompt, "istem çğış")
  testthat::expect_identical(sonuc$user_id, 7L)
  testthat::expect_identical(sonuc$chat_id, "42")
})

testthat::test_that("SSE ısıtması yalnızca bağımlılık önbelleği gerçekten doldurulduysa başarılı sayılır", {
  env <- new.env(parent = globalenv())
  sys.source(file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_true_streaming_task.R"),
             envir = env, keep.source = FALSE)
  env$mergen_true_streaming_worker_globals <- function(...) list(x = 1)
  kayit <- new.env()
  kayit$onbellek <- NULL
  env$worker_monitor_auto_globals <- function(task_type, task_fn, promise_globals) list(ok = TRUE)
  env$worker_monitor_dep_cache_get <- function(task_type, task_fn, promise_globals) kayit$onbellek
  # Tarama başarılı ama kayıt reddedildi (önbellek boş): ısıtma başarısızdır.
  testthat::expect_false(env$mergen_true_streaming_warm_dependencies())
  # Kayıt oluştu: ısıtma başarılıdır.
  kayit$onbellek <- list(packages = character())
  testthat::expect_true(env$mergen_true_streaming_warm_dependencies())
  # Tarama başarısızsa önbellek sorulmadan başarısızdır.
  env$worker_monitor_auto_globals <- function(...) list(ok = FALSE)
  testthat::expect_false(env$mergen_true_streaming_warm_dependencies())
})
