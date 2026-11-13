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
