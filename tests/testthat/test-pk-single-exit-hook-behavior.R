# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-single-exit-hook-behavior.R
# Açıklama: PK "tek çıkış" gözlemci sarmalayıcısının KURULUM sözleşmesi.
#
#           İki gerileme korunur:
#             1) `global.R` yeniden kaynaklandığında `pk_analiz_process_request`
#                sarmalanmamış hâline dönerse sarmalayıcı YENİDEN kurulmalıdır
#                (eski koruma yalnızca bir ortam bayrağına bakıyordu ve erken
#                dönüyordu: doğrudan çıkış yolları `MB_Analiz_Log` satırlarını
#                düşürüyordu).
#             2) Doğrudan çıkış sonucu ana süreçte ve işçide AYNI sınıflandırıcı
#                ile eşlenmelidir; aksi hâlde kaydedilen `Outcome` isteğin
#                yönlendirildiği yola göre değişirdi.
#
#           Tamamen çevrimdışı: DB, LLM, tarayıcı, SSO veya ağ YOKTUR.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  for (ad in c("log_warn", "log_info", "log_error")) {
    if (!exists(ad, mode = "function", inherits = TRUE)) {
      assign(ad, function(...) invisible(NULL), envir = globalenv())
    }
  }
  source(file.path(repo_root, "R", "helpers_pk_worker_observers.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_pk_worker_direct_exit.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "server_init_session_state.R"),
         encoding = "UTF-8", local = globalenv())
})

test_that("doğrudan çıkış sınıflandırıcısı ana süreçle İŞÇİDE aynıdır", {
  # İşçi tarafındaki tek eşleme kaynağı budur; ana süreç de onu çağırır.
  expect_identical(pk_direct_exit_outcome("sıradan yanıt"), "DogrudanYanit")
  expect_identical(pk_direct_exit_outcome("herhangi", stopped = TRUE), "Durduruldu")
  expect_identical(pk_direct_exit_outcome("herhangi", error = TRUE), "Hata")
})

# Telemetri lavabosunu taklit eden ortak koşum. `pk_analysis_observe()` her iki
# yolun da TEK yazma noktasıdır; yayılan `outcome` buradan yakalanır.
.pk_exit_with_sink <- function(env, code) {
  kayit <- new.env(parent = emptyenv())
  kayit$cagrilar <- list()

  onceki <- get0("pk_analysis_observe", envir = env, inherits = FALSE)
  assign("pk_analysis_observe", function(session, conn, info) {
    kayit$cagrilar[[length(kayit$cagrilar) + 1L]] <- info
    invisible(TRUE)
  }, envir = env)
  on.exit({
    if (is.null(onceki)) {
      suppressWarnings(try(rm("pk_analysis_observe", envir = env), silent = TRUE))
    } else {
      assign("pk_analysis_observe", onceki, envir = env)
    }
  }, add = TRUE)

  force(code)
  kayit
}

.pk_exit_session <- function() {
  list(userData = new.env(parent = emptyenv()))
}

test_that("İŞÇİ doğrudan çıkış yolu sınıflandırılmış sonucu YAYAR", {
  # `withr` `required_packages` UYESI DEGILDIR; `with_envvar()` icin gerekli.
  testthat::skip_if_not_installed("withr")
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  # Sarmalayıcı YALNIZCA işçi bootstrap kipinde kurulur.
  withr::with_envvar(list(MERGEN_PK_WORKER_BOOTSTRAP = "1"), {
    env$pk_analiz_process_request <- function(user_prompt, chat_history, session,
                                              stop_check = NULL) {
      "Sentetik doğrudan yanıt"
    }
    source(file.path(repo_root, "R", "helpers_pk_worker_observers.R"),
           encoding = "UTF-8", local = env)
    source(file.path(repo_root, "R", "helpers_pk_worker_direct_exit.R"),
           encoding = "UTF-8", local = env)
  })

  expect_true(isTRUE(attr(env$pk_analiz_process_request,
                          "pk_worker_direct_exit_wrapper")),
              info = "İşçi sarmalayıcısı kurulmalıdır.")

  # DB bağlantısı AÇILMAZ: `.pk_worker_observer_connection()` `get_connection`
  # yokken NULL döner; lavabo yine de çağrılır.
  kayit <- .pk_exit_with_sink(env, {
    env$pk_analiz_process_request("soru", NULL, .pk_exit_session(), NULL)
  })

  expect_length(kayit$cagrilar, 1L)
  expect_identical(kayit$cagrilar[[1]]$outcome, "DogrudanYanit")
  expect_identical(kayit$cagrilar[[1]]$filter_status, "not_reached")

  # Durdurulmuş istek TELEMETRİYE HİÇ ULAŞMAZ (yeni DB işi başlatılmaz).
  kayit2 <- .pk_exit_with_sink(env, {
    env$pk_analiz_process_request("soru", NULL, .pk_exit_session(),
                                  function() TRUE)
  })
  expect_length(kayit2$cagrilar, 0L)
})

test_that("ANA SÜREÇ doğrudan çıkış yolu AYNI sınıflandırmayı yayar", {
  # KARDEŞ TESTLE AYNI MUHAFIZ: `.pk_hook_runtime_env` korumasız okunduğunda
  # yükleme başarısız olan bir koşucuda test ATLANMAK yerine "object not found"
  # ile düşüyor ve rapor gerçek nedeni gizliyordu.
  skip_if_not(exists("pk_hook_single_exit_fix_install", mode = "function") &&
                exists(".pk_hook_runtime_env"),
              "Kurulum yardımcısı yüklenemedi.")

  hedef <- .pk_hook_runtime_env

  eski_cekirdek <- get0(".pk_analiz_process_request_without_exit_observer",
                        envir = hedef, inherits = FALSE)
  eski_fn <- get0("pk_analiz_process_request", envir = hedef, inherits = FALSE)
  eski_bayrak <- get0(".pk_hook_single_exit_installed", envir = hedef, inherits = FALSE)
  on.exit({
    for (ad in c(".pk_analiz_process_request_without_exit_observer",
                 "pk_analiz_process_request", ".pk_hook_single_exit_installed")) {
      suppressWarnings(try(rm(list = ad, envir = hedef), silent = TRUE))
    }
    if (!is.null(eski_cekirdek)) {
      assign(".pk_analiz_process_request_without_exit_observer", eski_cekirdek, envir = hedef)
    }
    if (!is.null(eski_fn)) assign("pk_analiz_process_request", eski_fn, envir = hedef)
    if (!is.null(eski_bayrak)) {
      assign(".pk_hook_single_exit_installed", eski_bayrak, envir = hedef)
    }
  }, add = TRUE)

  assign(".pk_analiz_process_request_without_exit_observer",
         function(user_prompt, chat_history, session, stop_check = NULL) {
           "Yetki Hatası: bu veriye erişim yetkiniz yok."
         }, envir = hedef)
  suppressWarnings(try(rm(".pk_hook_single_exit_installed", envir = hedef), silent = TRUE))
  suppressWarnings(try(rm("pk_analiz_process_request", envir = hedef), silent = TRUE))

  expect_true(isTRUE(pk_hook_single_exit_fix_install()))

  kayit <- .pk_exit_with_sink(hedef, {
    get("pk_analiz_process_request", envir = hedef)(
      "soru", NULL, .pk_exit_session(), NULL
    )
  })

  expect_length(kayit$cagrilar, 1L)
  # AYNI SINIFLANDIRICI: iki yol da `pk_direct_exit_outcome()` kullanır; bu
  # metin ana süreçte eskiden `Yetkisiz`, işçide `DogrudanYanit` olabiliyordu.
  # LİTERAL DE SABİTLENİR (PR #705 incelemesi, P3): yalnızca sınıflandırıcıyla
  # karşılaştırmak, sınıflandırma BOZULDUĞUNDA iki tarafı BİRLİKTE kaydırır ve
  # test yeşil kalırdı -- dosya başlığının adlandırdığı gerilemenin ta kendisi.
  # Yetki hatası metni `Yetkisiz` sınıfına düşer; `DogrudanYanit` DEĞİLDİR.
  expect_identical(kayit$cagrilar[[1]]$outcome, "Yetkisiz")
  expect_identical(kayit$cagrilar[[1]]$outcome,
                   pk_direct_exit_outcome("Yetki Hatası: bu veriye erişim yetkiniz yok."))
})

test_that("sarmalayıcı SEMBOL YENİDEN KAYNAKLANDIĞINDA yeniden kurulur", {
  # KARDEŞ TESTLE AYNI MUHAFIZ: aşağıda `.pk_hook_runtime_env` KORUMASIZ
  # okunuyordu; yardımcı dosya yüklenip bağlama eksik/yeniden adlandırılmış
  # olduğunda test ATLANMAK yerine "object not found" ile düşüyor ve
  # `stop_on_failure = TRUE` altında rapor GERÇEK nedeni gizliyordu.
  skip_if_not(exists("pk_hook_single_exit_fix_install", mode = "function") &&
                exists(".pk_hook_runtime_env"),
              "Kurulum yardımcısı yüklenemedi.")

  hedef <- .pk_hook_runtime_env
  cekirdek <- function(user_prompt, chat_history, session, stop_check = NULL) "yanit"

  eski_cekirdek <- get0(".pk_analiz_process_request_without_exit_observer",
                        envir = hedef, inherits = FALSE)
  eski_fn <- get0("pk_analiz_process_request", envir = hedef, inherits = FALSE)
  eski_bayrak <- get0(".pk_hook_single_exit_installed", envir = hedef, inherits = FALSE)
  on.exit({
    if (is.null(eski_cekirdek)) {
      suppressWarnings(try(rm(".pk_analiz_process_request_without_exit_observer",
                              envir = hedef), silent = TRUE))
    } else {
      assign(".pk_analiz_process_request_without_exit_observer", eski_cekirdek, envir = hedef)
    }
    if (is.null(eski_fn)) {
      suppressWarnings(try(rm("pk_analiz_process_request", envir = hedef), silent = TRUE))
    } else {
      assign("pk_analiz_process_request", eski_fn, envir = hedef)
    }
    if (is.null(eski_bayrak)) {
      suppressWarnings(try(rm(".pk_hook_single_exit_installed", envir = hedef), silent = TRUE))
    } else {
      assign(".pk_hook_single_exit_installed", eski_bayrak, envir = hedef)
    }
  }, add = TRUE)

  assign(".pk_analiz_process_request_without_exit_observer", cekirdek, envir = hedef)
  assign("pk_analiz_process_request", cekirdek, envir = hedef)
  suppressWarnings(try(rm(".pk_hook_single_exit_installed", envir = hedef), silent = TRUE))

  expect_true(isTRUE(pk_hook_single_exit_fix_install()))
  kurulu <- get("pk_analiz_process_request", envir = hedef, inherits = FALSE)
  expect_true(.pk_hook_single_exit_is_wrapped(kurulu))

  # Aynı sarmalayıcı yerindeyken kurulum TEKRARLANMAZ.
  expect_false(isTRUE(pk_hook_single_exit_fix_install()))

  # SEMBOL YENİDEN KAYNAKLANDI: bayrak ortamda kalsa da sarmalayıcı geri gelir.
  assign("pk_analiz_process_request", cekirdek, envir = hedef)
  expect_false(.pk_hook_single_exit_is_wrapped(
    get("pk_analiz_process_request", envir = hedef, inherits = FALSE)
  ))
  expect_true(isTRUE(pk_hook_single_exit_fix_install()))
  expect_true(.pk_hook_single_exit_is_wrapped(
    get("pk_analiz_process_request", envir = hedef, inherits = FALSE)
  ))
})
