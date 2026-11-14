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
  olcum <- .gelecek_yuk_olcumu(function() {
    durum <- new.env()
    # 1) Tek işçiyi meşgul et.
    tracked_future_promise(function() { Sys.sleep(1); 1L },
                           task_type = "test_mesgul", dependency_mode = "explicit")
    # 2) İşçi doluyken ikinci iş; then geri çağrısı büyük bir nesneyi yakalar
    #    (gerçek uygulamada oturum/reaktif grafik).
    oturum_benzeri <- function() {
      buyuk <- raw(20e6)
      p <- tracked_future_promise(function() 2L, task_type = "test_ikinci",
                                  dependency_mode = "explicit")
      promises::then(p, function(v) { length(buyuk); durum$deger <- v })
    }
    oturum_benzeri()
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
  for (i in 1:3) local({
    j <- i
    p <- worker_monitor_future_promise(list(task_fn = function() j), character(0))
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
  assign(".worker_monitor_future_bitti", function(f) stop("beklenmeyen_yoklama_hatasi"), envir = globalenv())

  durum <- new.env()
  p <- worker_monitor_future_promise(list(task_fn = function() 9L), character(0))
  promises::then(p, onFulfilled = function(v) durum$deger <- v,
                 onRejected = function(e) durum$hata <- conditionMessage(e))
  .later_bosalt(function() !is.null(durum$hata) || !is.null(durum$deger), sure = 5)
  testthat::expect_match(durum$hata %||% "", "beklenmeyen_yoklama_hatasi")
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
