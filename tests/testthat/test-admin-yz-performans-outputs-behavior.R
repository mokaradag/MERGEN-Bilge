# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-yz-performans-outputs-behavior.R
# Açıklama: R/module_admin_yz_performans.R admin_ai_perf_outputs() render
#           fonksiyonlarının davranışsal testleri. Model performansı/hata oranı
#           çubuk grafikleri ile yavaş/hızlı sorgu DT tablolarının seri adı,
#           sıralama, x ekseni kategorileri ve boş-veri koruması doğrulanır.
#           Gerçek DB/tarayıcı yoktur; analytics_data reaktifi stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.aip_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_yz_performans.R"),
  encoding = "UTF-8",
  local = .aip_env
)
.aip_env[["%>%"]] <- magrittr::`%>%`
.aip_env$JS <- htmlwidgets::JS
.aip_env$admin_dt_header_callback <- htmlwidgets::JS("function(thead) {}")

.aip_full <- function() {
  list(
    model_performance = data.frame(
      ModelUsed = c("yavas-model", "hizli-model"),
      avg_duration = c(9.4, 1.2),
      total_count = c(40, 120),
      stringsAsFactors = FALSE
    ),
    model_errors = data.frame(
      ModelUsed = c("kotu-model", "iyi-model"),
      error_rate = c(15.0, 2.0),
      error_count = c(6, 1),
      total_count = c(40, 50),
      stringsAsFactors = FALSE
    ),
    slowest_queries = data.frame(
      ModelUsed = c("m1"), ResponseDuration = c(12.345),
      query_preview = c("yavaş sorgu önizleme"), query_time = c("2026-01-01 10:00:00"),
      stringsAsFactors = FALSE
    ),
    fastest_queries = data.frame(
      ModelUsed = c("m2"), ResponseDuration = c(0.5),
      query_preview = c("hızlı sorgu önizleme"), query_time = c("2026-01-02 11:00:00"),
      stringsAsFactors = FALSE
    )
  )
}

.aip_empty <- function() {
  bos <- data.frame()
  list(model_performance = bos, model_errors = bos, slowest_queries = bos, fastest_queries = bos)
}

.aip_server <- function(data_fn) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      .aip_env$admin_ai_perf_outputs(output, data_fn, list(emptyTable = "Yok"))
    })
  }
}

.aip_series <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts$series
}
.aip_categories <- function(output_value) {
  unlist(jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts$xAxis$categories)
}

test_that("model performansı grafiği süreye göre artan sıralar ve 'Süre' serisini üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.aip_server(.aip_full), args = list(id = "ai"), {
    seri <- .aip_series(output$model_performance_chart)
    expect_identical(seri[[1]]$name, "Süre")
    # avg_duration artan sıralandığı için hızlı-model önce gelir.
    expect_identical(.aip_categories(output$model_performance_chart), c("hizli-model", "yavas-model"))
    # Yuvarlanmış süre değerleri y olarak taşınır.
    expect_equal(vapply(seri[[1]]$data, function(p) as.numeric(p$y), numeric(1)), c(1.2, 9.4))
  })
})

test_that("model hata oranı grafiği hata oranına göre artan sıralar ve 'Hata Oranı' serisini üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.aip_server(.aip_full), args = list(id = "ai"), {
    seri <- .aip_series(output$model_errors_chart)
    expect_identical(seri[[1]]$name, "Hata Oranı")
    expect_identical(.aip_categories(output$model_errors_chart), c("iyi-model", "kotu-model"))
    expect_equal(vapply(seri[[1]]$data, function(p) as.numeric(p$y), numeric(1)), c(2.0, 15.0))
  })
})

test_that("yavaş/hızlı sorgu tabloları Türkçe sütun başlıklarını üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.aip_server(.aip_full), args = list(id = "ai"), {
    yavas <- as.character(output$slowest_queries_table)
    hizli <- as.character(output$fastest_queries_table)
    # DT container HTML'i Türkçe sütun başlıklarını taşır.
    for (baslik in c("Model", "Süre (sn)", "Sorgu Önizleme", "Tarih")) {
      expect_true(grepl(baslik, yavas, fixed = TRUE))
      expect_true(grepl(baslik, hizli, fixed = TRUE))
    }
    # Boş tablo dili iki tabloya da uygulanır.
    expect_true(grepl("Yok", yavas, fixed = TRUE))
  })
})

test_that("boş veri tüm AI performans çıktılarında korumayı tetikler ve hata vermez", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.aip_server(.aip_empty), args = list(id = "ai"), {
    expect_error(force(output$model_performance_chart), NA)
    expect_error(force(output$model_errors_chart), NA)
    expect_error(force(output$slowest_queries_table), NA)
    expect_error(force(output$fastest_queries_table), NA)
  })
})
