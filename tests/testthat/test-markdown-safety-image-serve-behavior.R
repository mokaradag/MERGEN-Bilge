# ==============================================================================
# Dosya Yolu: tests/testthat/test-markdown-safety-image-serve-behavior.R
# Açıklama: mergen_serve_image_data_url ve .mergen_register_image_data_obj
#           için davranış testleri. Oturum varken session-scoped URL üretimi,
#           oturum başına memoizasyon, oturumsuz/hatalı kayıtta base64
#           data-URI'ye güvenli düşüş ve içerik türü eşlemesi doğrulanır.
#           Çevrimdışı ve deterministik; gerçek Shiny oturumu gerekmez.
# ==============================================================================

.imageServeEnv <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_markdown_safety.R"),
         encoding = "UTF-8", local = env)
  env
}

# 1x1 şeffaf PNG'yi deterministik olarak diske yazar (fixture)
.writeTinyPng <- function(path) {
  png_b64 <- "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  writeBin(base64enc::base64decode(png_b64), path)
  invisible(path)
}

# registerDataObj çağrılarını kaydeden sahte oturum üretir
.makeFakeImageSession <- function(register_fn = NULL) {
  session <- new.env(parent = emptyenv())
  session$userData <- new.env(parent = emptyenv())
  session$register_calls <- list()

  if (is.null(register_fn)) {
    register_fn <- function(name, data, filterFunc) {
      session$register_calls[[length(session$register_calls) + 1L]] <-
        list(name = name, data = data)
      paste0("session/test/dataobj/", name)
    }
  }

  session$registerDataObj <- register_fn
  session
}

testthat::test_that("mergen_serve_image_data_url geçersiz/eksik yolda NULL döner", {
  env <- .imageServeEnv()

  testthat::expect_null(env$mergen_serve_image_data_url(NULL, session = NULL))
  testthat::expect_null(env$mergen_serve_image_data_url("", session = NULL))
  testthat::expect_null(env$mergen_serve_image_data_url(
    file.path(withr::local_tempdir(), "yok.png"), session = NULL
  ))
  testthat::expect_null(env$mergen_serve_image_data_url(c("a.png", "b.png"), session = NULL))
})

testthat::test_that("mergen_serve_image_data_url oturumsuz bağlamda base64 data-URI'ye düşer", {
  env <- .imageServeEnv()
  png_path <- file.path(withr::local_tempdir(), "kucuk.png")
  .writeTinyPng(png_path)

  out <- env$mergen_serve_image_data_url(png_path, session = NULL)

  testthat::expect_true(is.character(out) && length(out) == 1L)
  testthat::expect_true(startsWith(out, "data:image/png;base64,"))

  # Base64 gövdesi gerçekten dosya içeriğine karşılık gelir
  govde <- sub("^data:image/png;base64,", "", out)
  testthat::expect_identical(
    base64enc::base64decode(govde),
    readBin(png_path, "raw", file.info(png_path)$size)
  )
})

testthat::test_that("mergen_serve_image_data_url aktif oturumda session-scoped URL üretir ve memoize eder", {
  env <- .imageServeEnv()
  png_path <- file.path(withr::local_tempdir(), "oturumlu.png")
  .writeTinyPng(png_path)

  session <- .makeFakeImageSession()

  url1 <- env$mergen_serve_image_data_url(png_path, session = session)
  testthat::expect_true(startsWith(url1, "session/test/dataobj/"))
  testthat::expect_length(session$register_calls, 1L)

  # İkinci çağrı oturum cache'inden gelir; registerDataObj tekrar çağrılmaz
  url2 <- env$mergen_serve_image_data_url(png_path, session = session)
  testthat::expect_identical(url2, url1)
  testthat::expect_length(session$register_calls, 1L)

  # Cache, kullanıcı oturum verisinde normalize yol anahtarıyla durur
  cache <- session$userData$mergen_image_url_cache
  testthat::expect_true(is.list(cache))
  norm_key <- normalizePath(png_path, winslash = "/", mustWork = FALSE)
  testthat::expect_identical(cache[[norm_key]], url1)
})

testthat::test_that("mergen_serve_image_data_url kayıt hatasında base64 yedeğine düşer", {
  env <- .imageServeEnv()
  png_path <- file.path(withr::local_tempdir(), "hata.png")
  .writeTinyPng(png_path)

  patlayan_session <- .makeFakeImageSession(
    register_fn = function(name, data, filterFunc) stop("kayıt başarısız")
  )

  out <- env$mergen_serve_image_data_url(png_path, session = patlayan_session)
  testthat::expect_true(startsWith(out, "data:image/png;base64,"))
})

testthat::test_that(".mergen_register_image_data_obj içerik türünü uzantıya göre eşler", {
  env <- .imageServeEnv()
  tmp <- withr::local_tempdir()

  beklenenler <- list(
    "a.jpg"  = "image/jpeg",
    "b.jpeg" = "image/jpeg",
    "c.png"  = "image/png",
    "d.gif"  = "image/gif",
    "e.webp" = "image/webp",
    "f.svg"  = "image/svg+xml",
    # Bilinmeyen uzantı güvenli varsayılana düşer
    "g.bilinmeyen" = "image/png"
  )

  for (ad in names(beklenenler)) {
    yol <- file.path(tmp, ad)
    .writeTinyPng(yol)
    session <- .makeFakeImageSession()
    env$.mergen_register_image_data_obj(session, yol)
    kayit <- session$register_calls[[1L]]
    testthat::expect_identical(kayit$data$ctype, beklenenler[[ad]],
                               info = sprintf("uzantı eşlemesi: %s", ad))
  }
})
