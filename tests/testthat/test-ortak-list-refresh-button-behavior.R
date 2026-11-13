# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-list-refresh-button-behavior.R
# Açıklama: Ortak Söyleşiler listesi oturum içinde 60 sn önbelleklenir; sayfadaki
#           "Yenile" düğmesi önbelleği düşürüp listeyi DB'den yeniden okutur
#           (önceden hiçbir gözlemci düğmeyi dinlemiyordu). Gerçek modül sunucusu
#           ve gerçek önbellek yardımcısı çalışır; yalnızca DB okuması taklittir.
# ==============================================================================

testthat::test_that("Ortak Söyleşiler 'Yenile' düğmesi önbelleği atlayıp listeyi yeniden okur", {
  testthat::skip_if_not_installed("shiny")
  paketler <- new.env(parent = globalenv())
  list2env(mget(getNamespaceExports("shiny"), envir = asNamespace("shiny"), inherits = TRUE), envir = paketler)
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "module_ortak_calismalar.R"), encoding = "UTF-8", local = env)
  kayit <- new.env()
  kayit$okuma <- 0L
  # Gerçek önbellek yardımcısı; DB okuması sayılır.
  env$ortak_db_sohbet_listesi_onbellekten <- function(onbellek, kullanici_id, ttl_sn = 60) {
    if (!is.null(onbellek$df) && identical(onbellek$uid, kullanici_id)) return(onbellek$df)
    kayit$okuma <- kayit$okuma + 1L
    onbellek$df <- data.frame(Baslik = "Ortak çğış")
    onbellek$uid <- kullanici_id
    onbellek$df
  }
  env$ortak_db_oturum_listesi <- function(...) data.frame()
  env$ortak_db_tablolar_hazir_mi <- function(...) FALSE
  env$ortakOturumRoomServer <- function(...) list()
  env$ortak_canli_durum_oturum_temizligi_bagla <- function(...) invisible(NULL)
  env$liste_olustur <- function(df, ...) shiny::tags$div(paste(nrow(df), "satır"))
  shiny::testServer(env$ortakCalismalarServer, args = list(current_user_id = function() 7L), {
    session$flushReact()
    output$liste_sohbet
    testthat::expect_identical(kayit$okuma, 1L)
    # Sekme ziyaretleri önbelleği korur.
    yenile("tab")
    session$flushReact()
    output$liste_sohbet
    testthat::expect_identical(kayit$okuma, 1L)
    # "Yenile" (sohbet sayfası) önbelleği düşürür ve yeniden okutur.
    session$setInputs(yenile_sohbet = 1)
    output$liste_sohbet
    testthat::expect_identical(kayit$okuma, 2L)
    # Hub sayfasındaki düğme de aynı yenilemeyi yapar.
    session$setInputs(yenile_hub = 1)
    output$liste_sohbet
    testthat::expect_identical(kayit$okuma, 3L)
  })
})

testthat::test_that("Ortak Söyleşiler okuma hatası boş liste gibi gösterilmez, önbelleğe alınmaz ve Yenile ile toparlanır", {
  testthat::skip_if_not_installed("shiny")
  paketler <- new.env(parent = globalenv())
  list2env(mget(getNamespaceExports("shiny"), envir = asNamespace("shiny"), inherits = TRUE), envir = paketler)
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  # Gerçek modül ve gerçek önbellek yardımcısı; yalnızca DB liste okuması taklittir.
  source(file.path(kok, "R", "module_ortak_calismalar.R"), encoding = "UTF-8", local = env)
  env$ortak_db_sohbet_listesi_onbellekten <- local({
    yardimci_env <- new.env(parent = env)
    source(file.path(kok, "R", "helpers_ortak_oturum_db.R"), encoding = "UTF-8", local = yardimci_env)
    yardimci_env$ortak_db_sohbet_listesi_onbellekten
  })
  kayit <- new.env()
  kayit$okuma <- 0L
  kayit$hata <- TRUE
  environment(env$ortak_db_sohbet_listesi_onbellekten)$ortak_db_oturum_listesi <- function(...) {
    kayit$okuma <- kayit$okuma + 1L
    # Sürücü ayrıntısı arayüze sızmamalı (örnek değer, gerçek değil).
    if (isTRUE(kayit$hata)) return(structure(data.frame(), mergen_okuma_hatasi = TRUE, ayrinti = "DSN=ornek_dsn"))
    data.frame()
  }
  env$ortak_db_oturum_listesi <- function(...) data.frame()
  env$ortak_db_tablolar_hazir_mi <- function(...) FALSE
  env$ortakOturumRoomServer <- function(...) list()
  env$ortak_canli_durum_oturum_temizligi_bagla <- function(...) invisible(NULL)
  html <- function(x) paste(as.character(x$html), collapse = "")
  shiny::testServer(env$ortakCalismalarServer, args = list(current_user_id = function() 7L), {
    session$flushReact()
    ilk <- html(output$liste_sohbet)
    testthat::expect_identical(kayit$okuma, 1L)
    testthat::expect_match(ilk, "okunamadı", fixed = TRUE)
    testthat::expect_match(ilk, "Yenile", fixed = TRUE)
    testthat::expect_false(grepl("Henüz ortak söyleşi yok", ilk, fixed = TRUE),
                           info = "okuma hatası 'boş liste' mesajıyla gösterilmemeli")
    testthat::expect_false(grepl("ornek_dsn", ilk, fixed = TRUE))
    # Başarısız okuma önbelleğe alınmadığı için Yenile DB'yi yeniden okur ve
    # doğrulanmış boş sonuç bu kez boş liste mesajıyla gösterilir.
    kayit$hata <- FALSE
    session$setInputs(yenile_sohbet = 1)
    sonra <- html(output$liste_sohbet)
    testthat::expect_identical(kayit$okuma, 2L)
    testthat::expect_match(sonra, "Henüz ortak söyleşi yok", fixed = TRUE)
    testthat::expect_false(grepl("okunamadı", sonra, fixed = TRUE))
  })
})
