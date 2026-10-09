# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-preview-docx-async-clobber-behavior.R
# Açıklama: R/module_file_preview.R DOCX önizleme modülünün ASENKRON YARIŞ
#           KORUMASI davranış testleri.
#
#           Senaryo: kullanıcı büyük (>10 MB) bir DOCX (A) açar; base64 kodlama
#           bir future işçisinde sürerken kullanıcı ikinci bir DOCX (B) açar.
#           A'nın geç gelen geri çağrısı, sabit hedef kapsayıcıya (ns
#           "docx_preview_container") yazarak B'nin modalına yanlış belge
#           BASMAMALIDIR. docx_preview_seq belirteci her açılışta artırılır ve
#           asenkron geri çağrı yalnızca belirteç hâlâ kendi açılışıyla aynıysa
#           openDocxPreview mesajını gönderir.
#
#           Gerçek dosya, base64enc veya tarayıcı gerektirmez: işçi gönderimi
#           taklit edilir ve task_fn hiç zorlanmaz; sonuç elle çözülür.
# ==============================================================================

testthat::local_edition(3)

suppressMessages({
  if (requireNamespace("shiny", quietly = TRUE)) library(shiny)
  if (requireNamespace("promises", quietly = TRUE)) library(promises)
})

# later kuyruğunu güvenli sınırla boşaltan yardımcı.
.fp_drain_later_queue <- function(max_iter = 100L) {
  for (i in seq_len(max_iter)) {
    if (later::loop_empty()) break
    later::run_now(timeout = 0)
  }
  invisible(NULL)
}

# Modülü izole bir ortama yükle ve heavy bağımlılıkları deterministik stub'la.
.fp_make_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Var olmayan fixture dosyalarını "erişilebilir" say (asenkron yola düşmek için
  # gerçek dosya gerekmez; file.info NA boyut döndürünce zaten async seçilir).
  env$path_exists_relaxed <- function(p) TRUE
  env$resolve_readable_path <- function(p) p
  env$resolve_uploaded_file <- function(name, user_id = NULL) name
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_file_preview.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Kontrol edilebilir promise üreten future taklidi: task_fn'i ZORLAMA, resolve/
# reject fonksiyonlarını kuyruğa koy ki testte elle çözelim.
.fp_make_future_stub <- function(resolvers) {
  function(expr, ...) {
    promises::promise(function(resolve, reject) {
      resolvers$queue[[length(resolvers$queue) + 1L]] <- list(
        resolve = resolve, reject = reject
      )
    })
  }
}

test_that("DOCX: BAYAT asenkron sonuç daha YENİ modalı EZMEZ; yalnızca güncel sonuç basılır", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  env <- .fp_make_env()
  resolvers <- new.env()
  resolvers$queue <- list()
  kayit <- new.env()
  kayit$msgs <- list()

  path_a <- file.path(tempdir(), "docA_buyuk.docx")  # kasıtlı olarak oluşturulmaz
  path_b <- file.path(tempdir(), "docB_buyuk.docx")

  env$mergen_dispatch_docx_preview <- .fp_make_future_stub(resolvers)
  testthat::local_mocked_bindings(
    showModal = function(...) invisible(NULL),
    removeModal = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(env$filePreviewServer, args = list(id = "fp"), {
    root <- .subset2(session, "parent")
    root$sendCustomMessage <- function(type, message) {
      kayit$msgs[[length(kayit$msgs) + 1L]] <- list(type = type, message = message)
      invisible(NULL)
    }
    open_fn <- session$returned$open
    expect_true(is.function(open_fn))

    # A'yı aç (belirteç 1), sonra B'yi aç (belirteç 2). Her ikisi de async yola
    # düşer (var olmayan dosya -> file.info NA boyut).
    isolate(open_fn(list(name = "docA_buyuk.docx", datapath = path_a, size = 12345)))
    isolate(open_fn(list(name = "docB_buyuk.docx", datapath = path_b, size = 12345)))

    # İki future çağrısı kuyruğa iki resolver koymalı.
    expect_length(resolvers$queue, 2L)
    # Henüz hiçbir asenkron sonuç gelmedi.
    expect_length(kayit$msgs, 0L)

    # A'nın (BAYAT) sonucunu çöz: belirteç 1 != güncel 2 -> EZMEMELİ.
    resolvers$queue[[1]]$resolve("BASE64_A")
    .fp_drain_later_queue()
    expect_length(kayit$msgs, 0L)

    # B'nin sonucunu çöz: belirteç 2 == güncel 2 -> basılmalı.
    resolvers$queue[[2]]$resolve("BASE64_B")
    .fp_drain_later_queue()
    expect_length(kayit$msgs, 1L)
    expect_identical(kayit$msgs[[1]]$type, "openDocxPreview")
    expect_identical(kayit$msgs[[1]]$message$base64, "BASE64_B")
    expect_true(grepl("docx_preview_container", kayit$msgs[[1]]$message$targetId, fixed = TRUE))
  })
})

test_that("DOCX: TEK açılışta asenkron başarı sonucu doğru base64 ile openDocxPreview gönderir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  env <- .fp_make_env()
  resolvers <- new.env()
  resolvers$queue <- list()
  kayit <- new.env()
  kayit$msgs <- list()

  path_a <- file.path(tempdir(), "tek_docA.docx")

  env$mergen_dispatch_docx_preview <- .fp_make_future_stub(resolvers)
  testthat::local_mocked_bindings(
    showModal = function(...) invisible(NULL),
    removeModal = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(env$filePreviewServer, args = list(id = "fp"), {
    root <- .subset2(session, "parent")
    root$sendCustomMessage <- function(type, message) {
      kayit$msgs[[length(kayit$msgs) + 1L]] <- list(type = type, message = message)
      invisible(NULL)
    }
    open_fn <- session$returned$open

    isolate(open_fn(list(name = "tek_docA.docx", datapath = path_a, size = 999)))
    expect_length(resolvers$queue, 1L)

    resolvers$queue[[1]]$resolve("BASE64_TEK")
    .fp_drain_later_queue()

    # Güncel istek: tam akış çalışır ve mesaj gönderilir.
    expect_length(kayit$msgs, 1L)
    expect_identical(kayit$msgs[[1]]$type, "openDocxPreview")
    expect_identical(kayit$msgs[[1]]$message$base64, "BASE64_TEK")
  })
})

test_that("DOCX: BAYAT asenkron HATA sonucu daha yeni modal için Türkçe hata toast'ı göstermez", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")

  env <- .fp_make_env()
  resolvers <- new.env()
  resolvers$queue <- list()
  # showToast'ı kaydeden stub (env içinde gölgelenir).
  toast_kaydi <- new.env()
  toast_kaydi$count <- 0L
  env$showToast <- function(session, message, type = "info", ...) {
    toast_kaydi$count <- toast_kaydi$count + 1L
    invisible(NULL)
  }

  path_a <- file.path(tempdir(), "hataA.docx")
  path_b <- file.path(tempdir(), "hataB.docx")

  env$mergen_dispatch_docx_preview <- .fp_make_future_stub(resolvers)
  testthat::local_mocked_bindings(
    showModal = function(...) invisible(NULL),
    removeModal = function(...) invisible(NULL),
    .package = "shiny"
  )

  shiny::testServer(env$filePreviewServer, args = list(id = "fp"), {
    open_fn <- session$returned$open

    isolate(open_fn(list(name = "hataA.docx", datapath = path_a, size = 12345)))
    isolate(open_fn(list(name = "hataB.docx", datapath = path_b, size = 12345)))
    expect_length(resolvers$queue, 2L)

    # A (bayat) hatayla sonuçlanır: belirteç eski -> hata toast'ı GÖSTERİLMEMELİ.
    resolvers$queue[[1]]$reject(simpleError("A kodlama hatası"))
    .fp_drain_later_queue()
    expect_identical(toast_kaydi$count, 0L)

    # B (güncel) hatayla sonuçlanırsa toast gösterilir (kontrol amaçlı).
    resolvers$queue[[2]]$reject(simpleError("B kodlama hatası"))
    .fp_drain_later_queue()
    expect_identical(toast_kaydi$count, 1L)
  })
})

test_that("oturum sahibi değişince açık önizlemenin indirmesi önceki dosyayı sunmaz", {
  skip_if_not_installed("shiny")
  env <- .fp_make_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
         encoding = "UTF-8", local = env)
  env$showToast <- function(...) invisible(NULL)
  kaynak <- withr::local_tempfile(fileext = ".txt")
  writeLines("A kullanicisinin gizli dosyasi", kaynak)
  kapanis <- 0L
  testthat::local_mocked_bindings(
    showModal = function(...) invisible(NULL),
    removeModal = function(...) kapanis <<- kapanis + 1L,
    .package = "shiny"
  )
  shiny::testServer(env$filePreviewServer, {
    session$userData$kimlik_sahibi <- 7L
    session$returned$open(list(name = "gizli.txt", datapath = kaynak))
    testthat::expect_identical(readLines(output$download_preview_file), "A kullanicisinin gizli dosyasi")
    env$mergen_session_owner_transition(session$userData, 7L, 8L)
    testthat::expect_gte(kapanis, 1L)
    testthat::expect_error(output$download_preview_file, "Dosya henüz hazır değil", fixed = TRUE)
  })
})

test_that("sahip değişince süren DOCX kodlaması yeni sahibe basılmaz ve önbelleğe yazılmaz", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("promises")
  env <- .fp_make_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
         encoding = "UTF-8", local = env)
  resolvers <- new.env()
  resolvers$queue <- list()
  kayit <- new.env()
  kayit$msgs <- list()
  path_a <- file.path(tempdir(), "sahipA_buyuk.docx")
  env$mergen_dispatch_docx_preview <- .fp_make_future_stub(resolvers)
  testthat::local_mocked_bindings(
    showModal = function(...) invisible(NULL),
    removeModal = function(...) invisible(NULL),
    .package = "shiny"
  )
  shiny::testServer(env$filePreviewServer, args = list(id = "fp"), {
    root <- .subset2(session, "parent")
    root$sendCustomMessage <- function(type, message) {
      kayit$msgs[[length(kayit$msgs) + 1L]] <- list(type = type, message = message)
      invisible(NULL)
    }
    session$userData$kimlik_sahibi <- 7L
    isolate(session$returned$open(list(name = "sahipA_buyuk.docx", datapath = path_a, size = 1)))
    expect_length(resolvers$queue, 1L)
    env$mergen_session_owner_transition(session$userData, 7L, 8L)
    resolvers$queue[[1]]$resolve("BASE64_A")
    .fp_drain_later_queue()
    expect_length(kayit$msgs, 0L)
    # Aynı yol yeniden açılınca önbellekten A'nın içeriği gelmez.
    isolate(session$returned$open(list(name = "sahipA_buyuk.docx", datapath = path_a, size = 1)))
    expect_length(kayit$msgs, 0L)
    expect_length(resolvers$queue, 2L)
  })
})

test_that("önizleme kayıtları sınırlıdır; eski URL ve eski sahip reddedilir", {
  env <- .fp_make_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_user_session_identity.R"),
         encoding = "UTF-8", local = env)
  env$showToast <- function(...) invisible(NULL)
  gorsel <- file.path(withr::local_tempdir(), "rapor.png")
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47)), gorsel)
  kayitlar <- list()
  testthat::local_mocked_bindings(showModal = function(...) invisible(NULL),
                                  removeModal = function(...) invisible(NULL), .package = "shiny")
  shiny::testServer(env$filePreviewServer, {
    root <- .subset2(session, "parent")
    root$registerDataObj <- function(name, data, filterFunc) {
      kayitlar[[name]] <<- list(data = data, filter = filterFunc)
      paste0("veri/", name, "?w=1")
    }
    session$userData$kimlik_sahibi <- 7L
    session$returned$open(list(name = "rapor.png", datapath = gorsel))
    ilk <- kayitlar[[1]]
    expect_match(ilk$data$jeton, "^[0-9a-f]{64}$")
    istek <- list(QUERY_STRING = paste0("w=1&preview_token=", ilk$data$jeton))
    expect_identical(ilk$filter(ilk$data, istek)$status, 200L)
    for (i in 1:40) session$returned$open(list(name = "rapor.png", datapath = gorsel))
    expect_length(kayitlar, 1L)
    simdiki <- kayitlar[[1]]
    expect_identical(simdiki$filter(simdiki$data, istek)$status, 403L)
    istek$QUERY_STRING <- paste0("preview_token=", simdiki$data$jeton)
    expect_identical(simdiki$filter(simdiki$data, istek)$status, 200L)
    env$mergen_session_owner_transition(session$userData, 7L, 8L)
    expect_identical(simdiki$filter(simdiki$data, istek)$status, 403L)
    session$returned$open(list(name = "rapor.png", datapath = gorsel))
    expect_length(kayitlar, 1L)
    expect_false(identical(kayitlar[[1]]$data$jeton, simdiki$data$jeton))
    expect_identical(kayitlar[[1]]$filter(kayitlar[[1]]$data, istek)$status, 403L)
  })
})

test_that("görsel kaydı daha önce açılmış PDF uç noktasını geçersiz kılmaz", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("openssl")
  env <- .fp_make_env()
  env$showToast <- function(...) invisible(NULL)
  dizin <- withr::local_tempdir()
  pdf <- file.path(dizin, "rapor.pdf")
  png <- file.path(dizin, "rapor.png")
  writeBin(raw(2 * 1024^2), pdf)
  writeBin(as.raw(1:4), png)
  kayitlar <- list()
  testthat::local_mocked_bindings(showModal = function(...) NULL, .package = "shiny")
  testthat::local_mocked_bindings(runjs = function(...) NULL, .package = "shinyjs")
  shiny::testServer(env$filePreviewServer, {
    root <- .subset2(session, "parent")
    root$registerDataObj <- function(name, data, filterFunc) {
      kayitlar[[name]] <<- list(data = data, filter = filterFunc)
      paste0("data/", name, "?w=1")
    }
    session$returned$open(list(name = "rapor.pdf", datapath = pdf))
    ilk <- kayitlar$pdf_preview
    istek <- list(QUERY_STRING = paste0("preview_token=", ilk$data$jeton))
    session$returned$open(list(name = "rapor.png", datapath = png))
    expect_length(kayitlar, 2L)
    expect_identical(ilk$filter(ilk$data, istek)$status, 200L)
  })
})

test_that("DOCX yolu ana süreçte yoklanmadan işçiye gönderilir", {
  env <- .fp_make_env()
  env$resolve_readable_path <- env$path_exists_relaxed <- env$file.info <- function(...) {
    stop("Ana süreç dosya yolunu yoklamamalı")
  }
  sent <- NULL
  env$mergen_dispatch_docx_preview <- function(path, ...) {
    sent <<- path
    promises::promise_resolve("kodlanmış")
  }
  testthat::local_mocked_bindings(showModal = function(...) NULL, .package = "shiny")
  shiny::testServer(env$filePreviewServer, {
    session$returned$open(list(name = "rapor.docx", datapath = "/sunucu/paylasim/rapor.docx", size = 1))
    .fp_drain_later_queue()
    expect_identical(sent, "/sunucu/paylasim/rapor.docx")
  })
})

test_that("DOCX senkron gönderim hatası yalnız güncel açık önizlemeye bildirilir", {
  for (change in c("current", "owner", "closed")) {
    env <- .fp_make_env()
    notifications <- 0L
    closed <- 0L
    env$showToast <- function(...) notifications <<- notifications + 1L
    testthat::local_mocked_bindings(
      showModal = function(...) NULL,
      removeModal = function(...) closed <<- closed + 1L,
      .package = "shiny")
    shiny::testServer(env$filePreviewServer, {
      env$mergen_dispatch_docx_preview <- function(...) {
        if (change == "owner") session$userData$kimlik_nesli <- 1L
        if (change == "closed") session$close()
        stop("işçi serileştirme hatası")
      }
      session$returned$open(list(name = "rapor.docx", datapath = "/sunucu/rapor.docx"))
      .fp_drain_later_queue()
      expect_identical(notifications, if (change == "current") 1L else 0L)
      expect_identical(closed, if (change == "current") 1L else 0L)
    })
  }
})

test_that("DOCX sonucu başka türdeki önizlemenin yolunu veya modalını değiştirmez", {
  env <- .fp_make_env()
  resolvers <- new.env()
  resolvers$queue <- list()
  env$mergen_dispatch_docx_preview <- .fp_make_future_stub(resolvers)
  removed <- 0L
  testthat::local_mocked_bindings(
    showModal = function(...) NULL,
    removeModal = function(...) removed <<- removed + 1L,
    .package = "shiny"
  )
  text_path <- withr::local_tempfile(fileext = ".txt")
  writeLines("yeni dosya", text_path)
  shiny::testServer(env$filePreviewServer, {
    session$returned$open(list(name = "eski.docx", datapath = "eski.docx"))
    session$returned$open(list(name = "yeni.txt", datapath = text_path))
    resolvers$queue[[1]]$resolve(structure("BASE64", resolved_path = "eski.docx"))
    .fp_drain_later_queue()
    expect_identical(normalizePath(isolate(file_storage$preview_file$datapath), winslash = "/"),
                     normalizePath(text_path, winslash = "/"))
    expect_identical(removed, 0L)
  })
})

test_that("adıyla açılan DOCX indirmesi işçinin yolunu bekler", {
  env <- .fp_make_env()
  resolvers <- new.env()
  resolvers$queue <- list()
  env$mergen_dispatch_docx_preview <- .fp_make_future_stub(resolvers)
  testthat::local_mocked_bindings(showModal = function(...) NULL, .package = "shiny")
  shiny::testServer(env$filePreviewServer, {
    session$returned$open(list(name = "rapor.docx"))
    expect_null(isolate(file_storage$preview_file$datapath))
    expect_match(output$docx_download_ui$html, '<span class="btn disabled">', fixed = TRUE)
    expect_false(grepl("shiny-download-link", output$docx_download_ui$html, fixed = TRUE))
    resolvers$queue[[1]]$resolve(structure("BASE64", resolved_path = "kalici.docx"))
    .fp_drain_later_queue()
    session$flushReact()
    expect_identical(isolate(file_storage$preview_file$datapath), "kalici.docx")
    expect_match(output$docx_download_ui$html, "download_preview_file", fixed = TRUE)
    expect_match(output$docx_download_ui$html, "shiny-download-link", fixed = TRUE)
    expect_false(grepl("<span[^>]*disabled", output$docx_download_ui$html))
  })
})

test_that("DOCX işçisi yolu çözer, önbelleği doğrular ve değişen dosyayı yeniden kodlar", {
  env <- new.env(parent = globalenv())
  for (file in c("helpers_async_result_guard.R", "helpers_files_path.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", file), encoding = "UTF-8", local = env)
  }
  path <- withr::local_tempfile(fileext = ".docx")
  writeBin(charToRaw("ilk içerik"), path)
  resolutions <- 0L
  env$resolve_readable_path <- function(raw_path) { resolutions <<- resolutions + 1L; path }
  env$tracked_future_promise <- function(task_fn, globals, ...) {
    expect_identical(resolutions, 0L)
    expect_identical(globals$docx_path, "/sunucu/rapor.docx")
    environment(task_fn) <- list2env(globals, parent = baseenv())
    task_fn()
  }
  first <- env$mergen_dispatch_docx_preview("/sunucu/rapor.docx", "test")
  expect_identical(resolutions, 1L)
  expect_identical(attr(first, "resolved_path"), path)
  cache <- list(key = attr(first, "cache_key"), base64 = "ÖNBELLEK")
  resolutions <- 0L
  second <- env$mergen_dispatch_docx_preview("/sunucu/rapor.docx", "test", cached = cache)
  expect_identical(as.character(second), "ÖNBELLEK")
  writeBin(charToRaw("dosya değişti ve büyüdü"), path)
  resolutions <- 0L
  third <- env$mergen_dispatch_docx_preview("/sunucu/rapor.docx", "test", cached = cache)
  expect_identical(as.character(third), base64enc::base64encode(path))
  expect_false(identical(attr(third, "cache_key"), cache$key))
})


test_that("büyük DOCX önbelleği worker yüküne taşınmaz", {
  env <- new.env(parent = globalenv())
  for (file in c("helpers_worker_monitor.R", "helpers_async_result_guard.R"))
    source(file.path(resolve_repo_root_for_tests(), "R", file), encoding = "UTF-8", local = env)
  path <- withr::local_tempfile(fileext = ".docx")
  writeBin(charToRaw("docx"), path)
  info <- file.info(path)
  cache <- list(key = paste(path, info$size[1], as.numeric(info$mtime[1]), sep = "||"),
                base64 = strrep("A", 12L * 1024L * 1024L))
  env$resolve_readable_path <- function(path) path
  environment(env$resolve_readable_path) <- baseenv()
  payloads <- list()
  env$tracked_future_promise <- function(task_fn, globals, packages, ...) {
    payload <- env$worker_monitor_serialize_explicit_task(task_fn, globals, packages)
    payloads[[length(payloads) + 1L]] <<- payload
    expect_lt(length(payload), 1024L * 1024L)
    promises::promise_resolve(unserialize(payload)())
  }
  env$mergen_dispatch_docx_preview(path, "cache-test", cached = list(key = cache$key, base64 = "küçük"))
  value <- NULL
  promises::then(env$mergen_dispatch_docx_preview(path, "cache-test", cached = cache),
                 function(result) value <<- result)
  .fp_drain_later_queue()
  expect_identical(as.character(value), cache$base64)
  expect_identical(attr(value, "resolved_path"), path)
  expect_identical(payloads[[1L]], payloads[[2L]])
})
