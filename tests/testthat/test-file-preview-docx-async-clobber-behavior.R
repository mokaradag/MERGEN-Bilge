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
#           Gerçek dosya, base64enc veya tarayıcı gerektirmez: future::future
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
  skip_if_not_installed("future")

  env <- .fp_make_env()
  resolvers <- new.env()
  resolvers$queue <- list()
  kayit <- new.env()
  kayit$msgs <- list()

  path_a <- file.path(tempdir(), "docA_buyuk.docx")  # kasıtlı olarak oluşturulmaz
  path_b <- file.path(tempdir(), "docB_buyuk.docx")

  testthat::local_mocked_bindings(
    future = .fp_make_future_stub(resolvers), .package = "future"
  )
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
  skip_if_not_installed("future")

  env <- .fp_make_env()
  resolvers <- new.env()
  resolvers$queue <- list()
  kayit <- new.env()
  kayit$msgs <- list()

  path_a <- file.path(tempdir(), "tek_docA.docx")

  testthat::local_mocked_bindings(
    future = .fp_make_future_stub(resolvers), .package = "future"
  )
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
  skip_if_not_installed("future")

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

  testthat::local_mocked_bindings(
    future = .fp_make_future_stub(resolvers), .package = "future"
  )
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
