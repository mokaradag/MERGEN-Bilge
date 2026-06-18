# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-geri-bildirim-outputs-behavior.R
# Açıklama: R/module_admin_geri_bildirim_outputs.R içindeki admin_gb_outputs()
#           highcharter/DT render fonksiyonlarının davranışsal "golden"
#           testleri. Günlük çift-eksenli trend, memnuniyet pastası, NPS solid
#           gauge hesabı ve etiket treemap'inin seri adı, verisi, renk eşlemesi
#           ve boş-veri koruması doğrulanır. Renderer'lar modülden BİREBİR
#           çıkarıldığı için bu sözleşme grafik davranışının korunduğunu kanıtlar.
#           Gerçek DB/tarayıcı yoktur; veri reaktifleri stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.gbo_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_geri_bildirim_output_tables.R"),
  encoding = "UTF-8",
  local = .gbo_env
)
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_geri_bildirim_outputs.R"),
  encoding = "UTF-8",
  local = .gbo_env
)
# Renderer'ların çağrı anında çözdüğü global yardımcıları enjekte et.
.gbo_env[["%>%"]] <- magrittr::`%>%`
.gbo_env$JS <- htmlwidgets::JS
.gbo_env$admin_dt_header_callback <- htmlwidgets::JS("function(thead) {}")
.gbo_env$admin_turkish_dt_language <- list(emptyTable = "Veri yok")
.gbo_env$admin_format_turkish_date <- function(d) format(as.Date(d), "%d.%m")

# Dolu veri: testte kullanılan tüm reaktif alanları içerir.
.gbo_full <- function() {
  list(
    gunluk_trend = data.frame(
      tarih = c("2026-01-01", "2026-01-02", "2026-01-03"),
      cnt = c(4, 7, 5),
      ort_memnuniyet = c(3.5, 4.2, 4.0),
      stringsAsFactors = FALSE
    ),
    memnuniyet_dagilim = data.frame(
      Memnuniyet = c(1, 3, 5),
      cnt = c(2, 6, 12),
      stringsAsFactors = FALSE
    ),
    nps_dagilim = data.frame(
      toplam = 20, promoter = 12, passive = 5, detractor = 3,
      stringsAsFactors = FALSE
    ),
    kullanici_memnuniyet = data.frame(
      KullaniciAdi = c("Ayşe"), bildirim_sayisi = c(3),
      ort_memnuniyet = c(4.33), ort_nps = c(8.5),
      son_bildirim = c("2026-01-03 10:00:00"),
      stringsAsFactors = FALSE
    )
  )
}

.gbo_etiket <- function() {
  data.frame(
    etiket = c("tasarim", "performans"),
    cnt = c(9, 4),
    etiket_tr = c("Tasarım Önerisi", "Performans"),
    stringsAsFactors = FALSE
  )
}

.gbo_empty <- function() {
  bos <- data.frame()
  list(gunluk_trend = bos, memnuniyet_dagilim = bos, nps_dagilim = bos,
       kullanici_memnuniyet = bos)
}
.gbo_etiket_empty <- function() data.frame()

# admin_gb_outputs'u bir moduleServer içinde saran yardımcı.
.gbo_server <- function(data_fn, etiket_fn) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      .gbo_env$admin_gb_outputs(output, data_fn, etiket_fn)
    })
  }
}

.gbo_opts <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts
}
.gbo_series <- function(output_value) .gbo_opts(output_value)$series

test_that("günlük trend çift eksenli: 'Bildirim Sayısı' sütun + 'Ort. Memnuniyet' spline", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.gbo_server(.gbo_full, .gbo_etiket), args = list(id = "gb"), {
    seri <- .gbo_series(output$gb_gunluk_trend_chart)
    expect_identical(seri[[1]]$name, "Bildirim Sayısı")
    expect_identical(seri[[1]]$type, "column")
    expect_identical(seri[[1]]$color, "#06b6d4")
    expect_equal(as.numeric(unlist(seri[[1]]$data)), c(4, 7, 5))

    expect_identical(seri[[2]]$name, "Ort. Memnuniyet")
    expect_identical(seri[[2]]$type, "spline")
    expect_identical(seri[[2]]$color, "#f59e0b")
    expect_equal(as.numeric(unlist(seri[[2]]$data)), c(3.5, 4.2, 4.0))
  })
})

test_that("memnuniyet pastası 5 seviye için Türkçe etiket, renk ve cnt eşlemesini korur", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.gbo_server(.gbo_full, .gbo_etiket), args = list(id = "gb"), {
    pts <- .gbo_series(output$gb_memnuniyet_polar_chart)[[1]]$data
    isimler <- vapply(pts, function(p) p$name, character(1))
    renkler <- vapply(pts, function(p) p$color, character(1))
    yvals <- vapply(pts, function(p) as.numeric(p$y), numeric(1))

    expect_identical(isimler, c("Çok Kötü", "Kötü", "Orta", "İyi", "Çok İyi"))
    expect_identical(renkler, c("#ef4444", "#f97316", "#f59e0b", "#22c55e", "#10b981"))
    # Memnuniyet 1->2, 3->6, 5->12; 2 ve 4 boş (0).
    expect_equal(yvals, c(2, 0, 6, 0, 12))
  })
})

test_that("NPS solid gauge değeri (promoter-detractor)/toplam*100 olarak hesaplanır", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.gbo_server(.gbo_full, .gbo_etiket), args = list(id = "gb"), {
    seri <- .gbo_series(output$gb_nps_gauge_chart)
    # (12 - 3) / 20 * 100 = 45 -> sarı eşik (>=0, <50) -> #f59e0b
    nps_pt <- seri[[1]]$data[[1]]
    expect_equal(as.numeric(nps_pt$y), 45)
    expect_identical(nps_pt$color, "#f59e0b")
  })
})

test_that("etiket treemap adlarını etiket_tr'den ve değerleri cnt'den üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.gbo_server(.gbo_full, .gbo_etiket), args = list(id = "gb"), {
    pts <- .gbo_series(output$gb_etiket_treemap_chart)[[1]]$data
    isimler <- vapply(pts, function(p) p$name, character(1))
    degerler <- vapply(pts, function(p) as.numeric(p$value), numeric(1))
    expect_identical(isimler, c("Tasarım Önerisi", "Performans"))
    expect_equal(degerler, c(9, 4))
  })
})

test_that("boş veri grafikleri hatasız boş highchart döndürür", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.gbo_server(.gbo_empty, .gbo_etiket_empty), args = list(id = "gb"), {
    for (out in list(output$gb_gunluk_trend_chart, output$gb_memnuniyet_polar_chart,
                     output$gb_nps_gauge_chart, output$gb_etiket_treemap_chart)) {
      expect_error(force(out), NA)
      j <- jsonlite::fromJSON(as.character(out), simplifyVector = FALSE)
      expect_true(is.null(j$x$hc_opts$series) || length(j$x$hc_opts$series) == 0)
    }
  })
})

test_that("kullanıcı memnuniyet tablosu dolu ve boş veride hatasız render olur", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("DT")

  shiny::testServer(.gbo_server(.gbo_full, .gbo_etiket), args = list(id = "gb"), {
    expect_error(force(output$gb_kullanici_tablo), NA)
  })
  shiny::testServer(.gbo_server(.gbo_empty, .gbo_etiket_empty), args = list(id = "gb"), {
    expect_error(force(output$gb_kullanici_tablo), NA)
  })
})
