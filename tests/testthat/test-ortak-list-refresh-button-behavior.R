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
  # Üretimdeki önbellek yardımcısı; yalnızca DB liste okuması taklittir ve her
  # okuma ayırt edici bir satır döndürür (gösterilen verinin tazeliği görülür).
  env$ortak_db_sohbet_listesi_onbellekten <- local({
    yardimci_env <- new.env(parent = env)
    source(file.path(kok, "R", "helpers_ortak_oturum_db.R"), encoding = "UTF-8", local = yardimci_env)
    yardimci_env$ortak_db_sohbet_listesi_onbellekten
  })
  environment(env$ortak_db_sohbet_listesi_onbellekten)$ortak_db_oturum_listesi <- function(...) {
    kayit$okuma <- kayit$okuma + 1L
    data.frame(Baslik = paste("Ortak çğış okuma", kayit$okuma), stringsAsFactors = FALSE)
  }
  env$ortak_db_oturum_listesi <- function(...) data.frame()
  # Tablolar kurulu: okuma yolu sınanır; kalp atışı/bildirim DB çağrıları taklittir.
  env$ortak_db_tablolar_hazir_mi <- function(...) TRUE
  env$ortak_db_kalp_atisi <- function(...) invisible(NULL)
  env$ortak_db_bakim_temizlik <- function(...) invisible(NULL)
  env$ortak_db_bildirimlerim <- function(...) data.frame()
  env$ortakOturumRoomServer <- function(...) list()
  env$ortak_canli_durum_oturum_temizligi_bagla <- function(...) invisible(NULL)
  env$liste_olustur <- function(df, ...) shiny::tags$div(paste(df$Baslik, collapse = "|"))
  html <- function(x) paste(as.character(x$html), collapse = "")
  shiny::testServer(env$ortakCalismalarServer, args = list(current_user_id = function() 7L), {
    session$flushReact()
    testthat::expect_match(html(output$liste_sohbet), "okuma 1", fixed = TRUE)
    testthat::expect_identical(kayit$okuma, 1L)
    # Sekme ziyaretleri üretim önbelleğinden aynı veriyi gösterir.
    yenile("tab")
    session$flushReact()
    testthat::expect_match(html(output$liste_sohbet), "okuma 1", fixed = TRUE)
    testthat::expect_identical(kayit$okuma, 1L)
    # "Yenile" (sohbet sayfası) önbelleği düşürür ve TAZE veriyi gösterir.
    session$setInputs(yenile_sohbet = 1)
    testthat::expect_match(html(output$liste_sohbet), "okuma 2", fixed = TRUE)
    testthat::expect_identical(kayit$okuma, 2L)
    # Hub sayfasındaki düğme de aynı yenilemeyi yapar.
    session$setInputs(yenile_hub = 1)
    testthat::expect_match(html(output$liste_sohbet), "okuma 3", fixed = TRUE)
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
  # Tablolar kurulu: okuma yolu sınanır; kalp atışı/bildirim DB çağrıları taklittir.
  env$ortak_db_tablolar_hazir_mi <- function(...) TRUE
  env$ortak_db_kalp_atisi <- function(...) invisible(NULL)
  env$ortak_db_bakim_temizlik <- function(...) invisible(NULL)
  env$ortak_db_bildirimlerim <- function(...) data.frame()
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
    # Yenile'den ÖNCE: başarısız okuma önbellekte değildir.
    testthat::expect_null(sohbet_onbellek$df)
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

testthat::test_that("MB_Ortak* tabloları kurulmamışken listeler okuma hatası yerine kurulum yönlendirmesi gösterir", {
  testthat::skip_if_not_installed("shiny")
  paketler <- new.env(parent = globalenv())
  list2env(mget(getNamespaceExports("shiny"), envir = asNamespace("shiny"), inherits = TRUE), envir = paketler)
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "module_ortak_calismalar.R"), encoding = "UTF-8", local = env)
  kayit <- new.env()
  kayit$okuma <- 0L
  kayit$hazir <- FALSE
  # Tablo yokken sorgu başarısız olur ve işaretli hata çerçevesi dönerdi.
  okuma <- function(...) {
    kayit$okuma <- kayit$okuma + 1L
    if (isTRUE(kayit$hazir)) data.frame() else structure(data.frame(), mergen_okuma_hatasi = TRUE)
  }
  env$ortak_db_oturum_listesi <- okuma
  env$ortak_db_sohbet_listesi_onbellekten <- function(onbellek, kullanici_id, ...) okuma()
  env$ortak_db_tablolar_hazir_mi <- function(...) kayit$hazir
  env$ortak_db_kalp_atisi <- function(...) invisible(NULL)
  env$ortak_db_bakim_temizlik <- function(...) invisible(NULL)
  env$ortak_db_bildirimlerim <- function(...) data.frame()
  env$ortakOturumRoomServer <- function(...) list()
  env$ortak_canli_durum_oturum_temizligi_bagla <- function(...) invisible(NULL)
  html <- function(x) paste(as.character(x$html), collapse = "")
  shiny::testServer(env$ortakCalismalarServer, args = list(current_user_id = function() 7L), {
    session$flushReact()
    for (cikti in list(html(output$liste_sohbet), html(output$liste_bilge_yolac), html(output$liste_hub))) {
      testthat::expect_match(cikti, "henüz kurulmamış", fixed = TRUE)
      testthat::expect_false(grepl("okunamadı", cikti, fixed = TRUE))
    }
    testthat::expect_identical(kayit$okuma, 0L)
    # Tablolar kurulunca gerçek okuma yapılır ve doğrulanmış boş sonuç gösterilir.
    kayit$hazir <- TRUE
    session$setInputs(yenile_sohbet = 1)
    sonra <- html(output$liste_sohbet)
    testthat::expect_match(sonra, "Henüz ortak söyleşi yok", fixed = TRUE)
    testthat::expect_gt(kayit$okuma, 0L)
  })
})

testthat::test_that("olumsuz tablo sonucu önbellekteyken Yenile tabloları yeniden yoklar; geçici yoklama hatası kurulum mesajı göstermez", {
  testthat::skip_if_not_installed("shiny")
  paketler <- new.env(parent = globalenv())
  list2env(mget(getNamespaceExports("shiny"), envir = asNamespace("shiny"), inherits = TRUE), envir = paketler)
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "module_ortak_calismalar.R"), encoding = "UTF-8", local = env)
  # Üretimdeki tablo yoklaması ve olumsuz önbelleği; yalnızca bağlantı ve tablo varlığı taklittir.
  yardimci <- new.env(parent = env)
  source(file.path(kok, "R", "helpers_ortak_oturum_db.R"), encoding = "UTF-8", local = yardimci)
  kayit <- new.env()
  kayit$hazir <- FALSE
  kayit$baglanti_hatasi <- FALSE
  kayit$yoklama <- 0L
  yardimci$.oo_db_acquire <- function(conn = NULL) {
    if (isTRUE(kayit$baglanti_hatasi)) stop("veritabanına ulaşılamadı (test)")
    list(conn = "sahte")
  }
  yardimci$.oo_db_release <- function(...) invisible(NULL)
  yardimci$.oo_db_log_warn <- function(...) invisible(NULL)
  testthat::local_mocked_bindings(dbExistsTable = function(conn, name, ...) {
    kayit$yoklama <- kayit$yoklama + 1L
    isTRUE(kayit$hazir)
  }, .package = "DBI")
  for (ad in c("ortak_db_tablolar_hazir_mi", "ortak_db_tablo_prob_hatasi_mi",
               "ortak_db_tablo_olumsuz_onbellegini_temizle")) {
    env[[ad]] <- yardimci[[ad]]
  }
  env$ortak_db_oturum_listesi <- function(...) data.frame()
  env$ortak_db_sohbet_listesi_onbellekten <- function(...) data.frame()
  env$ortak_db_kalp_atisi <- function(...) invisible(NULL)
  env$ortak_db_bakim_temizlik <- function(...) invisible(NULL)
  env$ortak_db_bildirimlerim <- function(...) data.frame()
  env$ortakOturumRoomServer <- function(...) list()
  env$ortak_canli_durum_oturum_temizligi_bagla <- function(...) invisible(NULL)
  html <- function(x) paste(as.character(x$html), collapse = "")
  shiny::testServer(env$ortakCalismalarServer, args = list(current_user_id = function() 7L), {
    session$flushReact()
    testthat::expect_match(html(output$liste_sohbet), "henüz kurulmamış", fixed = TRUE)
    # Tablolar kuruldu; sekme ziyareti 60 sn'lik olumsuz sonucu korur (yoklama yok).
    kayit$hazir <- TRUE
    yoklama_once <- kayit$yoklama
    yenile("tab")
    session$flushReact()
    testthat::expect_match(html(output$liste_sohbet), "henüz kurulmamış", fixed = TRUE)
    testthat::expect_identical(kayit$yoklama, yoklama_once)
    # "Yenile" olumsuz sonucu düşürür: tablolar hemen görülür ve liste okunur.
    session$setInputs(yenile_sohbet = 1)
    testthat::expect_match(html(output$liste_sohbet), "Henüz ortak söyleşi yok", fixed = TRUE)
  })

  # Geçici bağlantı hatası: kurulum yönlendirmesi değil yeniden deneme durumu;
  # hata önbelleğe alınmaz, DB toparlanınca ilk yenilemede liste gelir.
  yardimci$ortak_db_reset_availability_cache()
  kayit$baglanti_hatasi <- TRUE
  shiny::testServer(env$ortakCalismalarServer, args = list(current_user_id = function() 7L), {
    session$flushReact()
    ilk <- html(output$liste_sohbet)
    testthat::expect_match(ilk, "okunamadı", fixed = TRUE)
    testthat::expect_false(grepl("henüz kurulmamış", ilk, fixed = TRUE))
    kayit$baglanti_hatasi <- FALSE
    yenile("tab")
    session$flushReact()
    testthat::expect_match(html(output$liste_sohbet), "Henüz ortak söyleşi yok", fixed = TRUE)
  })
})

testthat::test_that("Ortak Söyleşiler önbelleği oturum sahibi değişince (kimlik kaybı) düşer", {
  testthat::skip_if_not_installed("shiny")
  paketler <- new.env(parent = globalenv())
  list2env(mget(getNamespaceExports("shiny"), envir = asNamespace("shiny"), inherits = TRUE), envir = paketler)
  env <- new.env(parent = paketler)
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_user_session_identity.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "module_ortak_calismalar.R"), encoding = "UTF-8", local = env)
  kayit <- new.env(); kayit$okuma <- 0L
  env$ortak_db_sohbet_listesi_onbellekten <- function(onbellek, kullanici_id, ttl_sn = 60) {
    if (!is.null(onbellek$df) && identical(onbellek$uid, kullanici_id)) return(onbellek$df)
    kayit$okuma <- kayit$okuma + 1L
    onbellek$df <- data.frame(Baslik = paste("oda", kayit$okuma)); onbellek$uid <- kullanici_id
    onbellek$df
  }
  env$ortak_db_oturum_listesi <- function(...) data.frame()
  env$ortak_db_tablolar_hazir_mi <- function(...) TRUE
  env$ortak_db_kalp_atisi <- function(...) invisible(NULL)
  env$ortak_db_bakim_temizlik <- function(...) invisible(NULL)
  env$ortak_db_bildirimlerim <- function(...) data.frame()
  env$ortakOturumRoomServer <- function(...) list()
  env$ortak_canli_durum_oturum_temizligi_bagla <- function(...) invisible(NULL)
  env$liste_olustur <- function(df, ...) shiny::tags$div(paste(df$Baslik, collapse = "|"))
  shiny::testServer(env$ortakCalismalarServer, args = list(current_user_id = function() 7L), {
    session$flushReact()
    output$liste_sohbet
    testthat::expect_identical(kayit$okuma, 1L)
    # Kimlik düştü ve aynı kullanıcı geri geldi: çıkış öncesi liste yeniden kullanılmaz
    # ve liste_yenile anında artarak açık sekmedeki eski sahibin listesini temizler.
    onceki_yenile <- shiny::isolate(liste_yenile())
    env$mergen_session_owner_transition(session$userData, 7L, 0L)
    testthat::expect_gt(shiny::isolate(liste_yenile()), onceki_yenile)
    env$mergen_session_owner_transition(session$userData, 0L, 7L)
    testthat::expect_null(sohbet_onbellek$df)
    session$flushReact()
    output$liste_sohbet
    testthat::expect_identical(kayit$okuma, 2L)
  })
})

testthat::test_that("başarısız tablo probu eski olumsuz önbelleği temizler ve otomatik yoklamada geri çekilir", {
  kok <- resolve_repo_root_for_tests()
  yardimci <- new.env(parent = globalenv())
  yardimci$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(kok, "R", "helpers_ortak_oturum_db.R"), encoding = "UTF-8", local = yardimci)
  sayac <- 0L
  yardimci$.oo_db_acquire <- function(conn = NULL, tx = FALSE) {
    sayac <<- sayac + 1L
    stop("DB geçici olarak erişilemez (test)")
  }
  # Eski doğrulanmış olumsuz önbellek kurulu olsun.
  yardimci$.oo_db_state$available <- FALSE
  yardimci$.oo_db_state$checked_at <- Sys.time()
  # Zorunlu prob başarısız olunca eski FALSE önbelleği düşer ve geri çekilme başlar.
  testthat::expect_false(yardimci$ortak_db_tablolar_hazir_mi(force_refresh = TRUE))
  testthat::expect_identical(sayac, 1L)
  testthat::expect_null(yardimci$.oo_db_state$available)
  testthat::expect_true(yardimci$ortak_db_tablo_prob_hatasi_mi())
  # Otomatik yoklama geri çekilme penceresinde DB'ye tekrar gitmez.
  testthat::expect_false(yardimci$ortak_db_tablolar_hazir_mi(force_refresh = FALSE, otomatik_yoklama = TRUE))
  testthat::expect_identical(sayac, 1L)
  # Etkileşimli/zorunlu yenileme geri çekilmeyi aşarak yeniden yoklar.
  testthat::expect_false(yardimci$ortak_db_tablolar_hazir_mi(force_refresh = TRUE))
  testthat::expect_identical(sayac, 2L)
})
