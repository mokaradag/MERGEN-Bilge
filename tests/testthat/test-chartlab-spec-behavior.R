# ==============================================================================
# Dosya Yolu: tests/testthat/test-chartlab-spec-behavior.R
# Açıklama: ChartLab saf grafik-spec yardımcılarının davranışsal testleri.
#           Grafik türü normalizasyonu, mapping değeri seçimi, tip/eksen/sütun
#           kontrolleri, otomatik spec tahmini ve agregasyon davranışı
#           doğrulanır. Alias testlerinde ASCII değerler kullanılarak Windows/
#           Türkçe yerel ayar kırılganlığı önlenir. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.chartlab_spec_source_once <- function() {
  if (exists("chartlab_normalize_chart_type", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("chartlab_auto_guess_spec", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }

  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_chartlab_spec.R"),
    encoding = "UTF-8",
    local = globalenv()
  )

  invisible(TRUE)
}

testthat::test_that("chartlab_normalize_chart_type alias ve özel durumları çözer", {
  .chartlab_spec_source_once()

  testthat::expect_identical(chartlab_normalize_chart_type("Line Chart"), "line")
  testthat::expect_identical(chartlab_normalize_chart_type("trend"), "line")
  testthat::expect_identical(chartlab_normalize_chart_type("column"), "bar")
  testthat::expect_identical(chartlab_normalize_chart_type("BAR"), "bar")
  testthat::expect_identical(chartlab_normalize_chart_type("scatter plot"), "scatter")
  testthat::expect_identical(chartlab_normalize_chart_type("doughnut"), "donut")
  testthat::expect_identical(chartlab_normalize_chart_type("histogram"), "hist")
  # Box/boxplot özel olarak hist'e eşlenir.
  testthat::expect_identical(chartlab_normalize_chart_type("boxplot"), "hist")
  testthat::expect_identical(chartlab_normalize_chart_type("pie chart"), "pie")

  # Bilinmeyen tür olduğu gibi (küçük harfe indirilmiş) geri döner.
  testthat::expect_identical(chartlab_normalize_chart_type("garip_tur"), "garip_tur")
  # NULL/boş -> boş string.
  testthat::expect_identical(chartlab_normalize_chart_type(NULL), "")
})

testthat::test_that("chartlab_normalize_mapping_value ilk anlamlı değeri seçer", {
  .chartlab_spec_source_once()

  testthat::expect_null(chartlab_normalize_mapping_value(NULL))
  testthat::expect_null(chartlab_normalize_mapping_value(character(0)))
  testthat::expect_null(chartlab_normalize_mapping_value(c("", "   ")))

  testthat::expect_identical(chartlab_normalize_mapping_value("  kolon  "), "kolon")
  testthat::expect_identical(chartlab_normalize_mapping_value(c("", "  ", "asil")), "asil")
  testthat::expect_identical(chartlab_normalize_mapping_value(c("a", "b")), "a")
})

testthat::test_that("chartlab tip kontrol yardımcıları doğru sınıfları tanır", {
  .chartlab_spec_source_once()

  testthat::expect_true(chartlab_is_numeric(1:5))
  testthat::expect_false(chartlab_is_numeric("metin"))

  testthat::expect_true(chartlab_is_date(Sys.Date()))
  testthat::expect_false(chartlab_is_date(42))

  testthat::expect_true(chartlab_is_numeric_or_date(1.5))
  testthat::expect_true(chartlab_is_numeric_or_date(Sys.Date()))
  testthat::expect_false(chartlab_is_numeric_or_date("metin"))
})

testthat::test_that("chartlab_first_or_null ilk öğeyi veya NULL döner", {
  .chartlab_spec_source_once()

  testthat::expect_identical(chartlab_first_or_null(c("a", "b")), "a")
  testthat::expect_null(chartlab_first_or_null(character(0)))
  testthat::expect_identical(chartlab_first_or_null(list(10, 20)), 10)
})

testthat::test_that("chartlab_aggregate_values agregasyon fonksiyonunu doğru seçer", {
  .chartlab_spec_source_once()

  z <- c(1, 2, 3, NA)
  testthat::expect_identical(chartlab_aggregate_values(c(1, 2, 3), "sum"), 6)
  testthat::expect_identical(chartlab_aggregate_values(c(1, 2, 3), "mean"), 2)
  testthat::expect_identical(chartlab_aggregate_values(c(1, 2, 3), "median"), 2)
  testthat::expect_identical(chartlab_aggregate_values(c(4, 1, 9), "min"), 1)
  testthat::expect_identical(chartlab_aggregate_values(c(4, 1, 9), "max"), 9)
  # count: NA olmayan eleman sayısı.
  testthat::expect_identical(chartlab_aggregate_values(z, "count"), 3L)
  # Bilinmeyen/NULL -> varsayılan sum.
  testthat::expect_identical(chartlab_aggregate_values(c(1, 2, 3), "bilinmeyen"), 6)
  testthat::expect_identical(chartlab_aggregate_values(c(1, 2, 3), NULL), 6)
})

testthat::test_that("chartlab_aggregate_line_data kategorik tekrarlı X için agrege eder", {
  .chartlab_spec_source_once()

  df <- data.frame(
    kategori = c("a", "a", "b"),
    deger = c(1, 3, 5),
    stringsAsFactors = FALSE
  )

  out <- chartlab_aggregate_line_data(df, x = "kategori", y = "deger", agg = "mean")
  testthat::expect_identical(nrow(out), 2L)
  a_val <- out$deger[as.character(out$kategori) == "a"]
  testthat::expect_identical(as.numeric(a_val), 2)

  # Benzersiz kategorik X -> agrege edilmeden döner.
  df_uniq <- data.frame(kategori = c("a", "b"), deger = c(1, 2), stringsAsFactors = FALSE)
  testthat::expect_identical(nrow(chartlab_aggregate_line_data(df_uniq, "kategori", "deger")), 2L)

  # Sayısal X kategorik değildir -> ham veri döner.
  df_num <- data.frame(x = c(1, 1, 2), y = c(1, 2, 3))
  testthat::expect_identical(nrow(chartlab_aggregate_line_data(df_num, "x", "y")), 3L)
})

testthat::test_that("chartlab_auto_guess_spec eksik tip/eksenleri veri tipine göre tahmin eder", {
  .chartlab_spec_source_once()

  # Kategorik + sayısal -> bar, x=kategori, y=deger.
  sp_bar <- chartlab_auto_guess_spec(list(
    type = "",
    mapping = list(),
    data = data.frame(kategori = c("a", "b"), deger = c(10, 20), stringsAsFactors = FALSE)
  ))
  testthat::expect_identical(sp_bar$type, "bar")
  testthat::expect_identical(sp_bar$mapping$x, "kategori")
  testthat::expect_identical(sp_bar$mapping$y, "deger")

  # İki sayısal sütun, kategorik yok -> çizgi (scatter regresyonunu önler).
  sp_line <- chartlab_auto_guess_spec(list(
    type = "",
    mapping = list(),
    data = data.frame(a = c(1, 2, 3), b = c(4, 5, 6))
  ))
  testthat::expect_identical(sp_line$type, "line")
  testthat::expect_identical(sp_line$mapping$x, "a")
  testthat::expect_identical(sp_line$mapping$y, "b")

  # Veri olmadan spec olduğu gibi (tip normalize edilerek) döner.
  sp_nodata <- chartlab_auto_guess_spec(list(type = "Line Chart", mapping = list()))
  testthat::expect_identical(sp_nodata$type, "line")
})
