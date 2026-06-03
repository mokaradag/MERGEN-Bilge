# ==============================================================================
# Dosya Yolu: tests/testthat/test-app-loading-behavior.R
# Açıklama: R/module_app_loading.R açılış yükleme katmanı yardımcılarının
#           DAVRANIŞSAL testleri. Bu dosya daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           Kapsananlar:
#           - app_loading_heptagon_points(): saf geometri; düzgün yedigen köşe
#             noktalarını "x,y x,y ..." biçiminde döndürür.
#           - app_loading_asset(): www altındaki bir varlığı UTF-8 metin olarak
#             okur, UTF-8 BOM'unu ayıklar, eksik dosyada uyarıp "" döndürür.
#           - app_loading_mark_svg(): saf SVG amblem işaretlemesi.
#           - appLoadingUI(): açılış katmanı UI yapısı (id/sınıf/erişilebilirlik).
#
#           Ağ/DB/LLM/tarayıcı GEREKMEZ. Varlık okuma testleri geçici dizinlerde
#           ya da repo kökünde withr::with_dir ile deterministik tutulur.
# ==============================================================================

# Modül dosyasını izole bir ortama yükler. Kaynak yüklenirken yan etki yoktur
# (yalnızca fonksiyon tanımları). UI testleri için shiny aranır.
.source_app_loading_for_test <- function() {
  env <- new.env(parent = globalenv())
  if (!exists("%||%", envir = env, inherits = TRUE)) {
    env$`%||%` <- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "module_app_loading.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# ------------------------------------------------------------------------------
# app_loading_heptagon_points
# ------------------------------------------------------------------------------
testthat::test_that("app_loading_heptagon_points tam 7 köşe noktası döndürür", {
  env <- .source_app_loading_for_test()
  noktalar <- env$app_loading_heptagon_points(80)
  parcalar <- strsplit(noktalar, " ", fixed = TRUE)[[1]]
  testthat::expect_length(parcalar, 7L)
  # Her parça "x,y" biçiminde iki ondalık sayı içermeli.
  testthat::expect_true(all(grepl("^-?[0-9]+\\.[0-9]{2},-?[0-9]+\\.[0-9]{2}$", parcalar)))
})

testthat::test_that("app_loading_heptagon_points r=0 için tüm noktaları merkeze toplar", {
  env <- .source_app_loading_for_test()
  noktalar <- env$app_loading_heptagon_points(0, cx = 120, cy = 120)
  parcalar <- strsplit(noktalar, " ", fixed = TRUE)[[1]]
  # Yarıçap sıfırsa yedi köşe de merkez (120.00,120.00) olur.
  testthat::expect_true(all(parcalar == "120.00,120.00"))
})

testthat::test_that("app_loading_heptagon_points ilk köşeyi tepe-yukarı (cy - r) konumlandırır", {
  env <- .source_app_loading_for_test()
  # vx[1]=0, vy[1]=-1 => ilk köşe (cx, cy - r).
  noktalar <- env$app_loading_heptagon_points(100, cx = 120, cy = 120)
  ilk <- strsplit(noktalar, " ", fixed = TRUE)[[1]][1]
  testthat::expect_identical(ilk, "120.00,20.00")
})

testthat::test_that("app_loading_heptagon_points özel merkez koordinatlarını uygular", {
  env <- .source_app_loading_for_test()
  noktalar <- env$app_loading_heptagon_points(0, cx = 50, cy = 75)
  parcalar <- strsplit(noktalar, " ", fixed = TRUE)[[1]]
  testthat::expect_true(all(parcalar == "50.00,75.00"))
})

# ------------------------------------------------------------------------------
# app_loading_asset
# ------------------------------------------------------------------------------
testthat::test_that("app_loading_asset eksik dosyada uyarır ve boş dize döndürür", {
  env <- .source_app_loading_for_test()
  sonuc <- NULL
  # Eksik dosya uyarısı strict runner'da yutulmalı; expect_warning ile tüketilir.
  testthat::expect_warning(
    sonuc <- env$app_loading_asset("css/kesinlikle_olmayan_dosya_xyz.css"),
    regexp = "bulunamad"
  )
  testthat::expect_identical(sonuc, "")
})

testthat::test_that("app_loading_asset UTF-8 BOM'unu ayıklar ve Türkçe metni korur", {
  env <- .source_app_loading_for_test()
  tmp <- withr::local_tempdir()
  # app_loading_asset göreli yolun başına "www/" ekler; dosya www altında olmalı.
  dir.create(file.path(tmp, "www", "css"), recursive = TRUE, showWarnings = FALSE)
  hedef <- file.path(tmp, "www", "css", "ornek.css")

  # BOM (EF BB BF) + Türkçe içerik yaz.
  icerik <- "/* Çağrı Ömer Şıkır */"
  con <- file(hedef, open = "wb")
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  writeBin(charToRaw(enc2utf8(icerik)), con)
  close(con)

  okunan <- withr::with_dir(tmp, env$app_loading_asset("css/ornek.css"))
  # BOM ayıklanmalı: çıktı BOM karakteriyle başlamaz, "/*" ile başlar.
  testthat::expect_true(startsWith(okunan, "/*"))
  testthat::expect_identical(enc2utf8(okunan), enc2utf8(icerik))
  testthat::expect_identical(Encoding(okunan), "UTF-8")
})

testthat::test_that("app_loading_asset boş dosya için boş dize döndürür", {
  env <- .source_app_loading_for_test()
  tmp <- withr::local_tempdir()
  # Boş dosya www altına yerleştirilir; size <= 0 dalında uyarısız "" dönmeli.
  dir.create(file.path(tmp, "www", "js"), recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(tmp, "www", "js", "bos.js"))
  okunan <- withr::with_dir(tmp, env$app_loading_asset("js/bos.js"))
  testthat::expect_identical(okunan, "")
})

testthat::test_that("app_loading_asset repo kökündeki gerçek CSS varlığını okur", {
  env <- .source_app_loading_for_test()
  repo_root <- resolve_repo_root_for_tests()
  # Gerçek varlık mevcutsa içerik dolu gelir; aksi halde test atlanır.
  if (!file.exists(file.path(repo_root, "www", "css", "app_loading.css"))) {
    testthat::skip("www/css/app_loading.css bulunamadı")
  }
  okunan <- withr::with_dir(repo_root, env$app_loading_asset("css/app_loading.css"))
  testthat::expect_true(is.character(okunan))
  testthat::expect_true(nzchar(okunan))
})

# ------------------------------------------------------------------------------
# app_loading_mark_svg
# ------------------------------------------------------------------------------
testthat::test_that("app_loading_mark_svg ilerleme halkalı SVG amblemini üretir", {
  env <- .source_app_loading_for_test()
  svg <- env$app_loading_mark_svg()
  testthat::expect_true(grepl("<svg", svg, fixed = TRUE))
  testthat::expect_true(grepl("viewBox=\"0 0 240 240\"", svg, fixed = TRUE))
  # İlerleme poligonu 0-100 birime ölçeklenir (pathLength=100, başlangıç boş).
  testthat::expect_true(grepl("pathLength=\"100\"", svg, fixed = TRUE))
  testthat::expect_true(grepl("stroke-dashoffset=\"100\"", svg, fixed = TRUE))
  testthat::expect_true(grepl("aloProgressGrad", svg, fixed = TRUE))
  # Erişilebilirlik: dekoratif amblem aria-hidden olmalı.
  testthat::expect_true(grepl("aria-hidden=\"true\"", svg, fixed = TRUE))
})

testthat::test_that("app_loading_mark_svg iç içe dört yedigen poligonu içerir", {
  env <- .source_app_loading_for_test()
  svg <- env$app_loading_mark_svg()
  # outer/track/progress/inner = 4 poligon.
  poligon_sayisi <- length(gregexpr("<polygon", svg, fixed = TRUE)[[1]])
  testthat::expect_identical(poligon_sayisi, 4L)
  # İlerleme poligonunun noktaları gerçek yedigen üreticisinden gelmeli (r=80).
  beklenen <- env$app_loading_heptagon_points(80)
  testthat::expect_true(grepl(beklenen, svg, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# appLoadingUI
# ------------------------------------------------------------------------------
testthat::test_that("appLoadingUI açılış katmanı yapısını ve marka metnini üretir", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))
  env <- .source_app_loading_for_test()

  repo_root <- resolve_repo_root_for_tests()
  # Repo kökünde çalışarak gerçek www varlıkları satır içine gömülür ve
  # eksik-dosya uyarısı oluşmaz (strict runner uyumu).
  ui <- withr::with_dir(repo_root, env$appLoadingUI())
  html <- paste(as.character(ui), collapse = "\n")

  testthat::expect_true(grepl("id=\"app-loading-overlay\"", html, fixed = TRUE))
  testthat::expect_true(grepl("MERGEN", html, fixed = TRUE))
  testthat::expect_true(grepl("Bilge", html, fixed = TRUE))
  # Başlangıç durum metni Türkçe korunmalı.
  testthat::expect_true(grepl("Başlatılıyor", html, fixed = TRUE))
  # Yükleme amblemi (alo-mark) ve okunabilir yüzde göstergesi yer almalı.
  testthat::expect_true(grepl("alo-mark", html, fixed = TRUE))
  testthat::expect_true(grepl("alo-readout-num", html, fixed = TRUE))
})
