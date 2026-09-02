# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-export-serve-behavior.R
# Açıklama: PK dışa aktarım ekinin GERÇEKTEN dosyadan akıtıldığını kilitler.
#
# NEDEN: `pk_export_serve()` gövdeyi `shiny::httpResponse(content = list(file =
# ..., owned = FALSE))` olarak döndürür. Bu, ancak alt katman adlandırılmış
# listedeki `file` alanını dosya akışına ÇEVİRİRSE çalışır. Çeviri kalkarsa her
# indirme, dosya yerine BOZUK bir gövde döndürür.
#
# YAKLAŞIM (PR incelemesi): testler artık `pk_export_serve()` DAVRANIŞINI
# çalıştırır — kayıtlı `filterFunc` gerçek bir istekle çağrılır ve dönen yanıt
# denetlenir. Bağımlılıkların ÖZEL iç sembolleri (`httpuv:::rookCall`,
# Shiny `.httpServer`) yalnızca ek bir bütünleşme kontrolünde kullanılır; bu
# kontrol semboller yoksa ATLANIR, çünkü yukarı akış yeniden adlandırması
# dosya akışı çalışırken testi kırmamalıdır.
# Tamamen çevrimdışıdır: ağ, DB, LLM veya tarayıcı GEREKMEZ.
# ==============================================================================

# Kayıt çağrısını yakalayan asgari sahte oturum. Gerçek Shiny oturumu
# GEREKMEZ: `pk_export_serve()` yalnızca `registerDataObj`, `userData` ve
# `onSessionEnded` alanlarını kullanır.
.pk_serve_fake_session <- function(url_uret = TRUE) {
  kayitlar <- list()
  temizleyiciler <- list()
  ud <- new.env(parent = emptyenv())
  list(
    userData = ud,
    kayitlar = function() kayitlar,
    # TEMİZLEYİCİLER SAKLANIR VE ÇALIŞTIRILABİLİR: eski sahte oturum geri
    # çağrıyı yutuyordu, bu yüzden "kayıt başarısızsa dosya oturum sonunda
    # silinir" sözleşmesi HİÇ sınanmıyordu.
    oturumu_bitir = function() {
      for (fn in temizleyiciler) try(fn(), silent = TRUE)
      temizleyiciler <<- list()
      invisible(TRUE)
    },
    onSessionEnded = function(fn) {
      temizleyiciler[[length(temizleyiciler) + 1L]] <<- fn
      invisible(fn)
    },
    # KAYIT SAYISI OKUNABILIR: yalnizca "dosya yok" iddiasi, `pk_export_serve()`
    # basarisiz kayit yolunda dosyayi ZATEN sildigi icin temizleyicinin
    # kaydedilip kaydedilmedigini KANITLAMAZ.
    temizleyici_sayisi = function() length(temizleyiciler),
    registerDataObj = function(name, data, filterFunc) {
      kayitlar[[length(kayitlar) + 1L]] <<- list(
        name = name, data = data, filterFunc = filterFunc
      )
      if (isTRUE(url_uret)) paste0("session/abc/dataobj/", name) else NULL
    }
  )
}

.pk_serve_load_helper <- function() {
  kok <- resolve_repo_root_for_tests()
  ortam <- new.env(parent = globalenv())
  # KOŞULSUZ ATANIR: `exists(..., inherits = TRUE)` bu çağrı çerçevesinden
  # bakar ve testthat YARDIMCI ortamındaki bir tanımı görebilir. O ortam
  # `ortam`ın (parent = `globalenv()`) zincirinde DEĞİLDİR; koşul sağlanınca
  # atama atlanır ve sourced üretim yardımcısı "could not find function %||%"
  # ile düşer. Üretim semantiği: yalnız `NULL` yedeğe düşer.
  assign("%||%", function(a, b) if (is.null(a)) b else a, envir = ortam)
  source(file.path(kok, "R", "helpers_pk_export_serve.R"),
         encoding = "UTF-8", local = ortam)
  ortam
}

test_that("ek gerçekten DOSYADAN akıtılır ve indirme başlığı taşır", {
  skip_if_not_installed("shiny")
  # `withr` `required_packages` UYESI DEGILDIR; `local_tempdir()` icin gerekli.
  skip_if_not_installed("withr")

  ortam <- .pk_serve_load_helper()
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "analiz.xlsx")
  writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04)), yol)

  oturum <- .pk_serve_fake_session()
  artefakt <- ortam$pk_export_serve(oturum, list(
    status = "ok",
    files = list(list(path = yol, name = "analiz.xlsx", format = "xlsx"))
  ))

  expect_identical(artefakt$status, "ok")
  expect_true(nzchar(artefakt$files[[1]]$url))

  kayit <- oturum$kayitlar()[[1]]
  yanit <- kayit$filterFunc(kayit$data, list())

  # DAVRANIŞ: gövde belleğe okunmaz, dosya yolu taşıyan adlandırılmış listedir.
  expect_equal(yanit$status, 200L)
  expect_true(is.list(yanit$content))
  expect_true("file" %in% names(yanit$content))
  expect_false(is.raw(yanit$content))
  expect_true(file.exists(yanit$content$file))
  expect_identical(
    normalizePath(yanit$content$file, winslash = "/", mustWork = TRUE),
    normalizePath(yol, winslash = "/", mustWork = TRUE)
  )
  # `owned = FALSE`: dosyayı oturum-sonu temizliği siler, httpuv DEĞİL.
  expect_false(isTRUE(yanit$content$owned))

  expect_true(grepl("spreadsheetml", yanit$content_type, fixed = TRUE))
  expect_true(grepl(
    "attachment; filename=\"analiz.xlsx\"",
    paste(unlist(yanit$headers), collapse = " "), fixed = TRUE
  ))

  # Temizlik defteri dosyayı üstlenmiştir (sahipsiz dosya kalmaz).
  expect_true(any(grepl("analiz.xlsx", oturum$userData$pk_export_cleanup_paths,
                        fixed = TRUE)))
})

test_that("CSV biçimi UTF-8 içerik türüyle sunulur", {
  skip_if_not_installed("shiny")
  # `withr` `required_packages` UYESI DEGILDIR; `local_tempdir()` icin gerekli.
  skip_if_not_installed("withr")

  ortam <- .pk_serve_load_helper()
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "analiz.csv")
  writeLines("a,b", yol)

  oturum <- .pk_serve_fake_session()
  ortam$pk_export_serve(oturum, list(
    status = "ok",
    files = list(list(path = yol, name = "analiz.csv", format = "csv"))
  ))

  kayit <- oturum$kayitlar()[[1]]
  yanit <- kayit$filterFunc(kayit$data, list())
  expect_true(grepl("text/csv", yanit$content_type, fixed = TRUE))
  expect_true(grepl("charset=UTF-8", yanit$content_type, fixed = TRUE))
})

test_that("dosya kaybolduysa 404 döner, bozuk gövde DÖNMEZ", {
  skip_if_not_installed("shiny")
  # `withr` `required_packages` UYESI DEGILDIR; `local_tempdir()` icin gerekli.
  skip_if_not_installed("withr")

  ortam <- .pk_serve_load_helper()
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "analiz.xlsx")
  writeLines("x", yol)

  oturum <- .pk_serve_fake_session()
  ortam$pk_export_serve(oturum, list(
    status = "ok",
    files = list(list(path = yol, name = "analiz.xlsx", format = "xlsx"))
  ))

  unlink(yol, force = TRUE)
  kayit <- oturum$kayitlar()[[1]]
  yanit <- kayit$filterFunc(kayit$data, list())

  expect_equal(yanit$status, 404L)
  expect_false(is.list(yanit$content))
})

test_that("kayıt URL üretemezse ek BAŞARISIZ sayılır ve dosya diskte kalmaz", {
  skip_if_not_installed("shiny")
  # `withr` `required_packages` UYESI DEGILDIR; `local_tempdir()` icin gerekli.
  skip_if_not_installed("withr")

  ortam <- .pk_serve_load_helper()
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "analiz.xlsx")
  writeLines("x", yol)

  oturum <- .pk_serve_fake_session(url_uret = FALSE)
  artefakt <- ortam$pk_export_serve(oturum, list(
    status = "ok",
    files = list(list(path = yol, name = "analiz.xlsx", format = "xlsx"))
  ))

  expect_identical(artefakt$status, "failed")
  expect_true(nzchar(artefakt$message))

  # KAYIT BAŞARISIZ OLSA DA DOSYA OTURUM SONUNDA GİDER: temizleyici gerçekten
  # kaydedilmiş olmalı ve çalıştırıldığında dosyayı silmelidir.
  #
  # AYIRT EDİCİ İDDİA KAYIT SAYISIDIR: başarısız kayıt dalında
  # `pk_export_serve()` `.pk_export_discard_files()` çağırıp dosyayı DÖNMEDEN
  # ÖNCE siler; dolayısıyla `.pk_export_register_cleanup()` `onSessionEnded`
  # kancasını kurmayı bıraksa bile aşağıdaki `expect_false()` geçerdi.
  expect_false(file.exists(yol))
  expect_gt(oturum$temizleyici_sayisi(), 0L)
  oturum$oturumu_bitir()
  expect_false(file.exists(yol))

  # Oturum yoksa dosya SİLİNİR (temizlik kaydı olmadan diskte bırakılmaz).
  yol2 <- file.path(gecici, "analiz2.xlsx")
  writeLines("x", yol2)
  artefakt2 <- ortam$pk_export_serve(NULL, list(
    status = "ok",
    files = list(list(path = yol2, name = "analiz2.xlsx", format = "xlsx"))
  ))
  expect_identical(artefakt2$status, "failed")
  expect_length(artefakt2$files, 0L)
  expect_false(file.exists(yol2))
})

test_that("üretim kaynağı belleğe okunan gövdeye geri DÖNMEZ", {
  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, "R", "helpers_pk_export_serve.R")
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  # Bellek içi gövdeye geri dönüş (`content = readBin(...)`) YASAKTIR: izin
  # verilen tavanda tek bir indirme yüzlerce MB'ı paylaşılan süreçte tutardı.
  expect_false(
    grepl("content = readBin(", metin, fixed = TRUE),
    info = "Ek, belleğe okunarak sunulmamalıdır."
  )
})

# --- Bütünleşme kontrolü (ATLANABİLİR) ---------------------------------------
# Aşağıdaki iki kontrol bağımlılıkların ÖZEL sembollerine bakar. Yukarı akış
# yeniden adlandırması dosya akışını bozmadan bu sembolleri kaldırabileceği
# için kontroller sembol yoksa ATLANIR; asıl sözleşme yukarıdaki davranış
# testleridir.

.pk_serve_private <- function(paket, ad, envir = NULL) {
  tryCatch({
    # `%||%` BU DOSYADA BAĞLI DEĞİLDİR (yalnızca özel yardımcı ortamına atanır):
    # operatör oturumda yoksa "could not find function" `tryCatch()` içinde
    # `NULL`a dönüyor, iki bütünleşme testi ATLANIYOR ve atlama mesajı gerçek
    # nedeni (eksik operatör) gizleyip yukarı akış yeniden adlandırmasını
    # SUÇLUYORDU.
    ortam <- if (is.null(envir)) asNamespace(paket) else envir
    if (!exists(ad, envir = ortam, inherits = FALSE)) return(NULL)
    get(ad, envir = ortam, inherits = FALSE)
  }, error = function(e) NULL)
}

test_that("httpuv adlandırılmış `file` gövdesini dosya akışına çevirir", {
  skip_if_not_installed("httpuv")

  rook <- .pk_serve_private("httpuv", "rookCall")
  skip_if(is.null(rook), "httpuv:::rookCall bu sürümde yok; davranış testleri geçerli.")

  govde <- tryCatch(paste(deparse(rook), collapse = "\n"), error = function(e) "")
  skip_if(!nzchar(govde), "httpuv iç fonksiyonu incelenemedi.")

  expect_true(
    grepl("bodyFile", govde, fixed = TRUE),
    info = "httpuv gövdeyi `bodyFile` alanına çevirmelidir."
  )
  expect_true(
    grepl("bodyFileOwned", govde, fixed = TRUE),
    info = "`owned` bayrağı httpuv tarafına taşınmalıdır."
  )
  # Alan adı ARANIR; tam ifade biçimi DEĞİL (yukarı akış yeniden yazımına
  # dayanıklı olsun diye).
  # İDDİA GERÇEKTEN SINAR: ikinci koşul (`grepl("body", ...)`) `bodyFile`
  # dizesiyle de eşleştiği için ayrık ifade HER ZAMAN TRUE oluyordu; sözleşme
  # ("çeviri yanıt GÖVDESİNE bakar") hiç denetlenmiyordu.
  expect_true(
    grepl("resp$body", govde, fixed = TRUE),
    info = "Çeviri, yanıt gövdesine bakmalıdır."
  )
})

test_that("Shiny GET yanıtında `content` DOĞRUDAN httpuv gövdesi olur", {
  skip_if_not_installed("shiny")

  hm <- .pk_serve_private("shiny", "handlerManager")
  skip_if(is.null(hm), "shiny:::handlerManager bu sürümde yok.")

  olustur <- .pk_serve_private("shiny", "createHttpuvApp", envir = hm)
  skip_if(is.null(olustur) || !is.function(olustur), "createHttpuvApp bulunamadı.")

  http_server <- .pk_serve_private("shiny", ".httpServer", envir = environment(olustur))
  skip_if(is.null(http_server) || !is.function(http_server), ".httpServer bulunamadı.")

  govde <- tryCatch(paste(deparse(body(http_server)), collapse = "\n"),
                    error = function(e) "")
  skip_if(!nzchar(govde), "Shiny iç fonksiyonu incelenemedi.")

  expect_true(
    grepl("response$content", govde, fixed = TRUE),
    info = "Shiny `content` alanını httpuv gövdesine DEĞİŞTİRMEDEN geçirmelidir."
  )
})
