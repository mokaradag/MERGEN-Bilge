# ==============================================================================
# Dosya Yolu: tests/testthat/test-chartlab-module-behavior.R
# Açıklama: R/module_chartlab.R ChartLab modülünün davranışsal testleri.
#           mergen_dark_theme() saf tema yardımcısı ve push_spec() üzerinden
#           auto_guess_chart_spec otomatik tür/eksen tahmini ile renderUI
#           yer tutucu (placeholder) yapısı doğrulanır. Gerçek çizim yapılmaz.
# ==============================================================================

testthat::local_edition(3)

.cl_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_chartlab.R"),
  encoding = "UTF-8",
  local = .cl_env
)

# charts_container renderUI çıktısını tek karakter dizisine indirger.
.cl_html <- function(output_value) {
  paste(as.character(output_value), collapse = "")
}

test_that("mergen_dark_theme kategorik renkleri ve kapalı credits ile tema döndürür", {
  skip_if_not_installed("highcharter")

  thm <- .cl_env$mergen_dark_theme()

  expect_true(is.list(thm))
  # Kategorik palet ilk rengi içermeli.
  expect_true("#60a5fa" %in% thm$colors)
  expect_length(thm$colors, 10)
  # Highcharts credits kapalı olmalı.
  expect_false(isTRUE(thm$credits$enabled))
  # Saydam arka plan korunmalı.
  expect_equal(thm$chart$backgroundColor, "transparent")
})

test_that("chartLabServer push_spec içeren API döndürür ve id üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.cl_env$chartLabServer, args = list(id = "cl"), {
    api <- session$returned
    expect_true(is.function(api$push_spec))

    yeni_id <- api$push_spec(list(
      type = "bar",
      data = data.frame(kategori = c("A", "B"), deger = c(3, 5), stringsAsFactors = FALSE),
      file = "ornek.csv"
    ))
    expect_true(is.character(yeni_id))
    expect_true(nzchar(yeni_id))
  })
})

test_that("charts_container: grafik yokken Türkçe boş durum mesajı gösterir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.cl_env$chartLabServer, args = list(id = "cl"), {
    html <- .cl_html(output$charts_container)
    expect_true(grepl("Henüz grafik yok", html, fixed = TRUE))
  })
})

test_that("auto_guess_chart_spec: tarih + sayısal veride çizgi grafiğe ve doğru eksenlere düşer", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.cl_env$chartLabServer, args = list(id = "cl"), {
    session$returned$push_spec(list(
      data = data.frame(
        tarih = as.Date("2026-01-01") + 0:2,
        deger = c(10, 20, 15)
      ),
      file = "zaman.csv"
    ))

    html <- .cl_html(output$charts_container)
    # Tür otomatik LINE olmalı (tarih + sayısal -> zaman serisi).
    expect_true(grepl("LINE", html, fixed = TRUE))
    # Meta satırı tahmin edilen eksenleri yansıtmalı.
    expect_true(grepl("x=tarih", html, fixed = TRUE))
    expect_true(grepl("y=deger", html, fixed = TRUE))
    expect_true(grepl("group=-", html, fixed = TRUE))
    expect_true(grepl("zaman.csv", html, fixed = TRUE))
  })
})

test_that("auto_guess_chart_spec: kategori + sayısal veride bar grafiğe düşer", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.cl_env$chartLabServer, args = list(id = "cl"), {
    session$returned$push_spec(list(
      data = data.frame(
        kategori = c("Ankara", "İzmir", "Ankara"),
        deger = c(5, 9, 2),
        stringsAsFactors = FALSE
      ),
      file = "iller.csv"
    ))

    html <- .cl_html(output$charts_container)
    expect_true(grepl("BAR", html, fixed = TRUE))
    expect_true(grepl("x=kategori", html, fixed = TRUE))
    expect_true(grepl("y=deger", html, fixed = TRUE))
  })
})

test_that("auto_guess_chart_spec: iki sayısal sütun scatter grafiğe düşer", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.cl_env$chartLabServer, args = list(id = "cl"), {
    session$returned$push_spec(list(
      data = data.frame(a = c(1, 2, 3), b = c(4, 5, 6)),
      file = "sayisal.csv"
    ))

    html <- .cl_html(output$charts_container)
    expect_true(grepl("SCATTER", html, fixed = TRUE))
    expect_true(grepl("x=a", html, fixed = TRUE))
    expect_true(grepl("y=b", html, fixed = TRUE))
  })
})

test_that("push_spec: id zaman damgalı üretilir ve tamsayı taşma uyarısı vermez (regresyon)", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.cl_env$chartLabServer, args = list(id = "cl"), {
    yeni_id <- NULL
    # Eskiden as.integer(ms_zaman) taşıp NA + uyarı üretiyordu; artık uyarı olmamalı.
    expect_warning(
      yeni_id <- session$returned$push_spec(list(
        type = "bar",
        data = data.frame(k = c("A", "B"), d = c(1, 2), stringsAsFactors = FALSE),
        file = "t.csv"
      )),
      regexp = NA
    )
    # id "cl_<ms>_<rastgele>" biçiminde olmalı; "NA" parçası içermemeli.
    expect_match(yeni_id, "^cl_[0-9]+_[0-9]+$")
    expect_false(grepl("NA", yeni_id, fixed = TRUE))
  })
})

test_that("auto_guess_chart_spec: desteklenmeyen box türü histograma çevrilir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.cl_env$chartLabServer, args = list(id = "cl"), {
    session$returned$push_spec(list(
      type = "box",
      data = data.frame(olcum = c(1, 2, 3, 4, 5)),
      file = "kutu.csv"
    ))

    html <- .cl_html(output$charts_container)
    # box/boxplot artık desteklenmiyor; histograma sabit geri dönüş.
    expect_true(grepl("HIST", html, fixed = TRUE))
    expect_false(grepl("BOX", html, fixed = TRUE))
    expect_true(grepl("x=olcum", html, fixed = TRUE))
  })
})
