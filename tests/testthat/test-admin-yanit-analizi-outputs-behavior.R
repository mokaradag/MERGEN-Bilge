# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-yanit-analizi-outputs-behavior.R
# Açıklama: R/module_admin_yanit_analizi_outputs.R içindeki admin_yanit_outputs()
#           highcharter/DT render fonksiyonlarının davranışsal "golden"
#           testleri. Günlük beğeni/beğenmeme areaspline'ı, tip pastası, model
#           bar'ı, etiket treemap'i ve refresh-bağımlı saat-gün ısı haritasının
#           seri adı, verisi ve renk eşlemesi doğrulanır. Renderer'lar modülden
#           BİREBİR çıkarıldığı için bu sözleşme grafik davranışının korunduğunu
#           kanıtlar. Gerçek DB/tarayıcı yoktur; veri reaktifleri stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.yao_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_yanit_analizi_outputs.R"),
  encoding = "UTF-8",
  local = .yao_env
)
.yao_env[["%>%"]] <- magrittr::`%>%`
.yao_env$JS <- htmlwidgets::JS
.yao_env$admin_dt_header_callback <- htmlwidgets::JS("function(thead) {}")
.yao_env$admin_turkish_dt_language <- list(emptyTable = "Veri yok")
.yao_env$admin_turkish_days <- c("Pazartesi", "Salı", "Çarşamba", "Perşembe",
                                 "Cuma", "Cumartesi", "Pazar")
.yao_env$admin_format_turkish_date <- function(d) format(as.Date(d), "%d.%m")

# Refresh stub: trigger() çağrısı sayılır (saat/saatlik grafikler bağımlı).
.yao_refresh <- function() {
  n <- 0L
  list(trigger = function() { n <<- n + 1L; invisible(NULL) }, count = function() n)
}

.yao_full <- function() {
  list(
    gunluk_trend = data.frame(
      tarih = as.character(c(Sys.Date() - 2, Sys.Date() - 1)),
      begeni = c(5, 8), begenmeme = c(1, 2), stringsAsFactors = FALSE
    ),
    tip_dagilim = data.frame(
      FeedbackType = c("like", "dislike"), cnt = c(30, 6), stringsAsFactors = FALSE
    ),
    model_performans = data.frame(
      ModelUsed = c("model-a", "model-b"),
      toplam_yanit = c(20, 10), begeni = c(18, 4), begenmeme = c(2, 6),
      ort_sure = c(3.2, 5.1), stringsAsFactors = FALSE
    ),
    saatlik_dagilim = data.frame(
      saat = c(9, 14), begeni = c(4, 7), begenmeme = c(1, 2), toplam = c(5, 9),
      stringsAsFactors = FALSE
    ),
    gunluk_dagilim = data.frame()
  )
}

.yao_etiket <- function() {
  data.frame(
    etiket = c("dogru", "eksik"), cnt = c(11, 5),
    begeni_cnt = c(9, 1), begenmeme_cnt = c(2, 4), stringsAsFactors = FALSE
  )
}

.yao_empty <- function() {
  bos <- data.frame()
  list(gunluk_trend = bos, tip_dagilim = bos, model_performans = bos,
       saatlik_dagilim = bos, gunluk_dagilim = bos)
}
.yao_etiket_empty <- function() data.frame()

.yao_server <- function(data_fn, etiket_fn, refresh = .yao_refresh()) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      .yao_env$admin_yanit_outputs(output, data_fn, etiket_fn, refresh)
    })
  }
}

.yao_series <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts$series
}

test_that("günlük trend iki areaspline serisi (Beğeni yeşil / Beğenmeme kırmızı) üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.yao_server(.yao_full, .yao_etiket), args = list(id = "ya"), {
    seri <- .yao_series(output$ya_gunluk_trend_chart)
    expect_identical(seri[[1]]$name, "Beğeni")
    expect_identical(seri[[1]]$type, "areaspline")
    expect_identical(seri[[1]]$color, "#10b981")
    expect_identical(seri[[2]]$name, "Beğenmeme")
    expect_identical(seri[[2]]$color, "#ef4444")
    # 30 günlük pencere doldurulur (tarih ekseni 30 nokta).
    expect_equal(length(seri[[1]]$data), 30)
  })
})

test_that("tip pastası like/dislike kodlarını Türkçe etikete ve renge çevirir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.yao_server(.yao_full, .yao_etiket), args = list(id = "ya"), {
    pts <- .yao_series(output$ya_tip_pie_chart)[[1]]$data
    isimler <- vapply(pts, function(p) p$name, character(1))
    renkler <- vapply(pts, function(p) p$color, character(1))
    yvals <- vapply(pts, function(p) as.numeric(p$y), numeric(1))
    expect_identical(isimler, c("Beğeni", "Beğenmeme"))
    expect_identical(renkler, c("#10b981", "#ef4444"))
    expect_equal(yvals, c(30, 6))
  })
})

test_that("model bar grafiği Beğeni/Beğenmeme serilerini oran sırasına göre üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.yao_server(.yao_full, .yao_etiket), args = list(id = "ya"), {
    seri <- .yao_series(output$ya_model_bar_chart)
    expect_identical(seri[[1]]$name, "Beğeni")
    expect_identical(seri[[1]]$color, "#10b981")
    expect_identical(seri[[2]]$name, "Beğenmeme")
    expect_identical(seri[[2]]$color, "#ef4444")
    # model-a oranı (18/20=90%) > model-b (4/10=40%) -> önce model-a beğenisi 18.
    expect_equal(as.numeric(seri[[1]]$data[[1]]), 18)
  })
})

test_that("etiket treemap adlarını etiket'ten ve değerleri cnt'den üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.yao_server(.yao_full, .yao_etiket), args = list(id = "ya"), {
    pts <- .yao_series(output$ya_etiket_treemap_chart)[[1]]$data
    isimler <- vapply(pts, function(p) p$name, character(1))
    degerler <- vapply(pts, function(p) as.numeric(p$value), numeric(1))
    expect_identical(isimler, c("dogru", "eksik"))
    expect_equal(degerler, c(11, 5))
  })
})

test_that("saat-gün ısı haritası refresh$trigger() bağımlılığını çağırır ve render olur", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  refresh <- .yao_refresh()
  shiny::testServer(.yao_server(.yao_full, .yao_etiket, refresh), args = list(id = "ya"), {
    expect_error(force(output$ya_saat_gun_heatmap), NA)
    seri <- .yao_series(output$ya_saat_gun_heatmap)
    expect_identical(seri[[1]]$name, "Geri Bildirim")
  })
  # Renderer refresh$trigger() çağırdığı için sayaç artmış olmalıdır.
  expect_gt(refresh$count(), 0L)
})

test_that("boş veri grafikleri hatasız boş highchart döndürür", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.yao_server(.yao_empty, .yao_etiket_empty), args = list(id = "ya"), {
    for (out in list(output$ya_tip_pie_chart, output$ya_model_bar_chart,
                     output$ya_etiket_treemap_chart, output$ya_saatlik_chart)) {
      expect_error(force(out), NA)
      j <- jsonlite::fromJSON(as.character(out), simplifyVector = FALSE)
      expect_true(is.null(j$x$hc_opts$series) || length(j$x$hc_opts$series) == 0)
    }
  })
})

