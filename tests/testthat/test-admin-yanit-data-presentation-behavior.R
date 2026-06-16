# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-yanit-data-presentation-behavior.R
# Açıklama: Yanıt Geri Bildirimi Analizi veri->sunum katmanının davranışsal
#           testleri (R/helpers_admin_yanit_analizi.R):
#             - admin_yanit_collect_data: 17 sorgu anahtarı + safe_query çağrı
#               sözleşmesi + kilit SQL çapaları (admin_gb_fetch_data ile simetri).
#             - admin_yanit_overview_ui: beğeni/yorum oranı hesaplaması, toplam=0
#               ve boş-çerçeve N/A korumaları, Türkçe metrik kartı etiketleri.
#           Saf veri/sunum mantığıdır; gerçek DB/LLM/tarayıcı GEREKMEZ.
#           admin_create_metric_card/admin_format_number/admin_create_info_button
#           izole env'de stub'lanır; safe_query mock'lanır. Çalışma zamanı R kodu
#           DEĞİŞMEZ (yalnızca mevcut doğru davranışı kilitler).
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

# helpers_admin_yanit_analizi.R'yi izole env'e yükler; admin helper bağımlılıkları
# stub'lanabilir ve %||% için utils_common da yüklenir (standalone güvenliği).
.ay_dp_env <- function() {
  env <- new.env(parent = globalenv())
  root <- resolve_repo_root_for_tests()
  source(file.path(root, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(file.path(root, "R", "helpers_admin_yanit_analizi.R"),
         encoding = "UTF-8", local = env)
  env
}

# ------------------------------------------------------------------------------
# admin_yanit_collect_data — sorgu sözleşmesi
# ------------------------------------------------------------------------------
.ay_expected_keys <- c(
  "toplam", "tip_dagilim", "gunluk_trend", "begeni_orani", "bugun", "bu_hafta",
  "yorumlu", "model_performans", "model_haftalik_trend", "uzunluk_analiz",
  "sure_analiz", "etiketler_ham", "son_yorumlar", "kullanici_ozet",
  "saatlik_dagilim", "gunluk_dagilim", "tumu"
)

testthat::test_that("admin_yanit_collect_data 17 anahtarı tek tek safe_query ile toplar", {
  env <- .ay_dp_env()

  sorgular <- new.env(); sorgular$liste <- character(0)
  mock_query <- function(sql) {
    sorgular$liste <- c(sorgular$liste, sql)
    data.frame()
  }

  res <- env$admin_yanit_collect_data(safe_query = mock_query)

  testthat::expect_type(res, "list")
  testthat::expect_setequal(names(res), .ay_expected_keys)
  # Her anahtar için tam olarak bir safe_query çağrısı yapılır.
  testthat::expect_length(sorgular$liste, length(.ay_expected_keys))
})

testthat::test_that("admin_yanit_collect_data kilit SQL semantiğini korur", {
  env <- .ay_dp_env()

  sorgular <- new.env(); sorgular$map <- list()
  mock_query <- function(sql) {
    sorgular$map[[length(sorgular$map) + 1L]] <- sql
    data.frame()
  }

  env$admin_yanit_collect_data(safe_query = mock_query)
  birlesik <- paste(unlist(sorgular$map), collapse = "\n---\n")

  # Tüm sorgular MB_Feedback üzerinden çalışır.
  testthat::expect_true(grepl("MB_Feedback", birlesik, fixed = TRUE))
  # Günlük trend son 30 günü filtreler ve MB_Messages ile JOIN'ler.
  testthat::expect_true(grepl("DATEADD(day, -30, GETDATE())", birlesik, fixed = TRUE))
  testthat::expect_true(grepl("MB_Messages", birlesik, fixed = TRUE))
  # Beğeni/beğenmeme ayrımı FeedbackType üzerinden yapılır.
  testthat::expect_true(grepl("FeedbackType = 'like'", birlesik, fixed = TRUE))
  testthat::expect_true(grepl("FeedbackType = 'dislike'", birlesik, fixed = TRUE))
  # Etiket ham verisi FeedbackTags sütunundan gelir.
  testthat::expect_true(grepl("FeedbackTags", birlesik, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# admin_yanit_overview_ui — hesaplanan metrikler
# ------------------------------------------------------------------------------

# overview_ui'yi stub'lı admin helper'larla çalıştırıp metrik kartı (başlık ->
# değer) çiftlerini kaydeder. Stub'lar test frame'inde tanımlanır (rec'i yakalar)
# ama izole env'e atanır, böylece overview_ui onları bulur.
.ay_run_overview <- function(env, data) {
  rec <- new.env(); rec$cards <- list()
  env$admin_create_metric_card <- function(title, value, ...) {
    rec$cards[[title]] <- as.character(value)
    NULL
  }
  env$admin_format_number <- function(x) as.character(x)
  env$admin_create_info_button <- function(...) NULL

  env$admin_yanit_overview_ui(data, ns = function(x) x)
  rec$cards
}

testthat::test_that("admin_yanit_overview_ui beğeni/yorum oranını ve sayıları doğru hesaplar", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")

  env <- .ay_dp_env()

  data <- list(
    toplam       = data.frame(cnt = 200),
    begeni_orani = data.frame(begeni = 150, begenmeme = 50),
    bugun        = data.frame(toplam = 12),
    bu_hafta     = data.frame(cnt = 40),
    yorumlu      = data.frame(cnt = 80)
  )

  kartlar <- .ay_run_overview(env, data)

  testthat::expect_identical(kartlar[["Toplam Geri Bildirim"]], "200")
  testthat::expect_identical(kartlar[["Beğeni Oranı"]], "75.0%")   # 150/200
  testthat::expect_identical(kartlar[["Beğeni"]], "150")
  testthat::expect_identical(kartlar[["Beğenmeme"]], "50")
  testthat::expect_identical(kartlar[["Bugün Gelen"]], "12")
  testthat::expect_identical(kartlar[["Yorum İçeren"]], "40.0%")   # 80/200
})

testthat::test_that("admin_yanit_overview_ui toplam=0 iken oranları N/A yapar", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")

  env <- .ay_dp_env()

  data <- list(
    toplam       = data.frame(cnt = 0),
    begeni_orani = data.frame(begeni = 0, begenmeme = 0),
    bugun        = data.frame(toplam = 0),
    bu_hafta     = data.frame(cnt = 0),
    yorumlu      = data.frame(cnt = 0)
  )

  kartlar <- .ay_run_overview(env, data)

  testthat::expect_identical(kartlar[["Toplam Geri Bildirim"]], "0")
  testthat::expect_identical(kartlar[["Beğeni Oranı"]], "N/A")
  testthat::expect_identical(kartlar[["Yorum İçeren"]], "N/A")
})

testthat::test_that("admin_yanit_overview_ui boş çerçevelerde güvenli varsayılanlar üretir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")

  env <- .ay_dp_env()

  bos <- data.frame()
  data <- list(
    toplam = bos, begeni_orani = bos, bugun = bos, bu_hafta = bos, yorumlu = bos
  )

  # Boş veri hata vermemeli ve sayılar 0 / oranlar N/A olmalı.
  kartlar <- NULL
  testthat::expect_error(kartlar <- .ay_run_overview(env, data), NA)

  testthat::expect_identical(kartlar[["Toplam Geri Bildirim"]], "0")
  testthat::expect_identical(kartlar[["Beğeni"]], "0")
  testthat::expect_identical(kartlar[["Beğenmeme"]], "0")
  testthat::expect_identical(kartlar[["Bugün Gelen"]], "0")
  testthat::expect_identical(kartlar[["Beğeni Oranı"]], "N/A")
})

testthat::test_that("admin_yanit_overview_ui altı Türkçe metrik kartını üretir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")

  env <- .ay_dp_env()

  data <- list(
    toplam       = data.frame(cnt = 10),
    begeni_orani = data.frame(begeni = 6, begenmeme = 4),
    bugun        = data.frame(toplam = 1),
    bu_hafta     = data.frame(cnt = 3),
    yorumlu      = data.frame(cnt = 2)
  )

  kartlar <- .ay_run_overview(env, data)

  testthat::expect_setequal(
    names(kartlar),
    c("Toplam Geri Bildirim", "Beğeni Oranı", "Beğeni", "Beğenmeme",
      "Bugün Gelen", "Yorum İçeren")
  )
})
