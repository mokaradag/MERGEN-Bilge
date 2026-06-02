# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-analytics-formatters-behavior.R
# Açıklama: R/helpers_admin_analytics.R içindeki saf (pure) biçimlendirme
#           yardımcılarının ve Türkçe sabitlerinin DAVRANIŞSAL testleri.
#           Bu helper dosyası daha önce hiçbir test tarafından çağrılmıyordu.
#
#           Gerçek davranış: admin_format_turkish_date() tek bir tarihi
#           "GG Ay" (ör. "05 Mar") biçiminde döndürür ve NA/NULL için ""
#           verir. admin_format_number() tamsayıya yuvarlanmış metin döndürür,
#           NA/NULL için "0" verir. Bu fonksiyonlar üretimde her zaman skaler
#           olarak (vapply ile) çağrılır. Ağ/DB/Shiny sunucusu GEREKMEZ.
# ==============================================================================

# helpers_admin_analytics.R'yi izole bir ortama yükler. Kaynak yüklenirken
# çalışan tek yan etki admin_dt_header_callback <- JS(...) çağrısıdır; bu yüzden
# JS için küçük bir stub sağlanır. UI yardımcıları (div/span/icon) için shiny
# aranır.
.source_admin_analytics_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  if (!exists("%||%", envir = globalenv(), inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }

  # DT::JS yerine kaynak-zamanı güvenli stub (yalnızca metni döndürür).
  env$JS <- function(...) paste0(...)
  env$showToast <- function(...) invisible(NULL)

  source(
    file.path(repo_root, "R", "helpers_admin_analytics.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

# ------------------------------------------------------------------------------
# Türkçe sabitler
# ------------------------------------------------------------------------------
testthat::test_that("admin_turkish_months 12 Türkçe ay kısaltması içerir ve ay indeksiyle eşleşir", {
  env <- .source_admin_analytics_for_test()

  testthat::expect_length(env$admin_turkish_months, 12L)
  testthat::expect_identical(env$admin_turkish_months[[1]], "Oca")
  testthat::expect_identical(env$admin_turkish_months[[3]], "Mar")
  testthat::expect_identical(env$admin_turkish_months[[12]], "Ara")
  # Türkçe karakter bütünlüğü korunmalı (Şub / Ağu).
  testthat::expect_identical(env$admin_turkish_months[[2]], "Şub")
  testthat::expect_identical(env$admin_turkish_months[[8]], "Ağu")
})

testthat::test_that("admin_turkish_days Pazartesi'den başlar ve 7 gün içerir", {
  env <- .source_admin_analytics_for_test()

  testthat::expect_length(env$admin_turkish_days, 7L)
  testthat::expect_identical(env$admin_turkish_days[[1]], "Pazartesi")
  testthat::expect_identical(env$admin_turkish_days[[7]], "Pazar")
  # Çarşamba Türkçe karakterlerini korumalı.
  testthat::expect_identical(env$admin_turkish_days[[3]], "Çarşamba")
})

# ------------------------------------------------------------------------------
# admin_format_turkish_date
# ------------------------------------------------------------------------------
testthat::test_that("admin_format_turkish_date tek tarihi 'GG Ay' biçiminde verir", {
  env <- .source_admin_analytics_for_test()

  testthat::expect_identical(env$admin_format_turkish_date(as.Date("2026-03-05")), "05 Mar")
  testthat::expect_identical(env$admin_format_turkish_date(as.Date("2026-01-01")), "01 Oca")
  testthat::expect_identical(env$admin_format_turkish_date(as.Date("2026-12-31")), "31 Ara")
  # Karakter tarih dizesi de kabul edilmeli.
  testthat::expect_identical(env$admin_format_turkish_date("2026-08-09"), "09 Ağu")
})

testthat::test_that("admin_format_turkish_date NA ve NULL için boş dize döndürür", {
  env <- .source_admin_analytics_for_test()

  testthat::expect_identical(env$admin_format_turkish_date(NA), "")
  testthat::expect_identical(env$admin_format_turkish_date(NULL), "")
})

testthat::test_that("admin_format_turkish_date üretimdeki skaler (vapply) çağrı desenini destekler", {
  env <- .source_admin_analytics_for_test()

  tarihler <- as.Date(c("2026-02-10", "2026-05-20", "2026-11-03"))
  etiketler <- vapply(tarihler, env$admin_format_turkish_date, character(1))

  testthat::expect_identical(etiketler, c("10 Şub", "20 May", "03 Kas"))
})

# ------------------------------------------------------------------------------
# admin_format_number
# ------------------------------------------------------------------------------
testthat::test_that("admin_format_number sayıyı tamsayı metnine çevirir", {
  env <- .source_admin_analytics_for_test()

  testthat::expect_identical(env$admin_format_number(1234L), "1234")
  testthat::expect_identical(env$admin_format_number(0L), "0")
  # Ondalık değer tamsayıya indirgenir (as.integer kesme davranışı).
  testthat::expect_identical(env$admin_format_number(7.9), "7")
})

testthat::test_that("admin_format_number NA ve NULL için '0' döndürür", {
  env <- .source_admin_analytics_for_test()

  testthat::expect_identical(env$admin_format_number(NA), "0")
  testthat::expect_identical(env$admin_format_number(NULL), "0")
})

# ------------------------------------------------------------------------------
# Renk paleti ve tooltip teması (saf listeler)
# ------------------------------------------------------------------------------
testthat::test_that("admin_modern_colors beklenen renk gruplarını hex değerleriyle içerir", {
  env <- .source_admin_analytics_for_test()

  testthat::expect_true(is.list(env$admin_modern_colors))
  testthat::expect_true(all(
    c("primary", "success", "warning", "danger", "info", "neutral") %in%
      names(env$admin_modern_colors)
  ))
  # Tüm değerler '#rrggbb' biçiminde olmalı.
  tum_renkler <- unlist(env$admin_modern_colors, use.names = FALSE)
  testthat::expect_true(all(grepl("^#[0-9a-fA-F]{6}$", tum_renkler)))
})

testthat::test_that("admin_hc_tooltip_theme koyu tema tooltip listesi döndürür", {
  env <- .source_admin_analytics_for_test()

  tema <- env$admin_hc_tooltip_theme()
  testthat::expect_true(is.list(tema))
  testthat::expect_true(all(c("backgroundColor", "borderColor", "style") %in% names(tema)))
  testthat::expect_identical(tema$style$color, "#fff")
})

testthat::test_that("admin_turkish_dt_language Türkçe DataTable etiketlerini içerir", {
  env <- .source_admin_analytics_for_test()

  dil <- env$admin_turkish_dt_language
  testthat::expect_true(is.list(dil))
  testthat::expect_identical(dil$search, "Ara:")
  testthat::expect_identical(dil$zeroRecords, "Eşleşen kayıt bulunamadı")
  testthat::expect_identical(dil$paginate$first, "İlk")
  testthat::expect_true(is.list(dil$aria))
})

# ------------------------------------------------------------------------------
# HTML üreten yardımcılar (shiny etiket fonksiyonları gerekir)
# ------------------------------------------------------------------------------
testthat::test_that("admin_create_metric_card değer, başlık, renk ve ipucunu HTML'e işler", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))

  env <- .source_admin_analytics_for_test()

  kart <- env$admin_create_metric_card(
    title = "Toplam Hata",
    value = "42",
    icon_name = "bug",
    color_class = "danger",
    subtitle = "son 7 gün",
    tooltip = "Toplam hata sayısı"
  )
  html <- as.character(kart)

  testthat::expect_true(grepl("metric-card", html, fixed = TRUE))
  testthat::expect_true(grepl("danger", html, fixed = TRUE))
  testthat::expect_true(grepl("42", html, fixed = TRUE))
  testthat::expect_true(grepl("Toplam Hata", html, fixed = TRUE))
  testthat::expect_true(grepl("son 7", html, fixed = TRUE))
  testthat::expect_true(grepl("data-toggle", html, fixed = TRUE))
})

testthat::test_that("admin_create_info_button ipucu metnini ve tooltip tetiğini taşır", {
  testthat::skip_if_not_installed("shiny")
  suppressMessages(library(shiny))

  env <- .source_admin_analytics_for_test()

  btn <- env$admin_create_info_button("Bu metrik neyi gösterir")
  html <- as.character(btn)

  testthat::expect_true(grepl("info-btn", html, fixed = TRUE))
  testthat::expect_true(grepl("data-toggle", html, fixed = TRUE))
  testthat::expect_true(grepl("Bu metrik neyi", html, fixed = TRUE))
})
