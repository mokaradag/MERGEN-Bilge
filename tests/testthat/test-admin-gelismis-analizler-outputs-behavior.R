# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-gelismis-analizler-outputs-behavior.R
# Açıklama: R/module_admin_gelismis_analizler.R admin_advanced_analytics_outputs()
#           render fonksiyonlarının davranışsal testleri. Çoklu seri model
#           kullanım trendi, saatlik ortalama yanıt süresi, söyleşi uzunluğu ve
#           model dağılımı halka grafikleri doğrulanır.
#           Gerçek DB/tarayıcı yoktur; analytics_data reaktifi stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.aa_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_gelismis_analizler.R"),
  encoding = "UTF-8",
  local = .aa_env
)
.aa_env[["%>%"]] <- magrittr::`%>%`

.aa_full <- function() {
  list(
    model_usage_trend = data.frame(
      ModelUsed = c("m1", "m1", "m2", "m2"),
      usage_date = c("2026-01-01", "2026-01-02", "2026-01-01", "2026-01-02"),
      cnt = c(3, 5, 2, 7), stringsAsFactors = FALSE
    ),
    avg_response_by_hour = data.frame(
      hour_num = c(9, 10, 8), avg_duration = c(2.345, 3.0, 1.5), stringsAsFactors = FALSE
    ),
    chat_length_distribution = data.frame(
      length_bucket = c("3-5 mesaj", "1-2 mesaj"), chat_count = c(12, 30), stringsAsFactors = FALSE
    ),
    model_performance = data.frame(
      ModelUsed = c("m1", "m2"), total_count = c(40, 60), stringsAsFactors = FALSE
    )
  )
}

.aa_empty <- function() {
  bos <- data.frame()
  list(model_usage_trend = bos, avg_response_by_hour = bos,
       chat_length_distribution = bos, model_performance = bos)
}

.aa_server <- function(data_fn, fmt = function(x) as.character(x)) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      .aa_env$admin_advanced_analytics_outputs(output, data_fn, fmt)
    })
  }
}

.aa_opts <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts
}

test_that("model kullanım trendi her model için ayrı seri üretir ve tarih eksenini formatlar", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.aa_server(.aa_full, fmt = function(x) paste0("T:", x)), args = list(id = "aa"), {
    opts <- .aa_opts(output$model_usage_trend_chart)
    isimler <- vapply(opts$series, function(s) s$name, character(1))
    expect_setequal(isimler, c("m1", "m2"))

    # sapply tarih etiketlerini adlandırılmış üretir; karşılaştırma için ad kaldırılır.
    kategoriler <- unname(unlist(opts$xAxis$categories))
    expect_identical(kategoriler, c("T:2026-01-01", "T:2026-01-02"))

    # m1 serisi tarih sırasına göre 3,5 değerlerini taşır.
    m1 <- Filter(function(s) s$name == "m1", opts$series)[[1]]
    expect_equal(as.numeric(unlist(m1$data)), c(3, 5))
  })
})

test_that("saatlik ortalama yanıt süresi saate göre artan sıralar ve 'Ort. Süre' serisini üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.aa_server(.aa_full), args = list(id = "aa"), {
    opts <- .aa_opts(output$avg_response_by_hour_chart)
    expect_identical(opts$series[[1]]$name, "Ort. Süre")
    expect_identical(opts$series[[1]]$color, "#f59e0b")
    # Saat etiketleri 08:00, 09:00, 10:00 sırasıyla.
    expect_identical(unlist(opts$xAxis$categories), c("08:00", "09:00", "10:00"))
  })
})

test_that("söyleşi uzunluğu halka grafiği bucket seviyesine göre sıralar", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.aa_server(.aa_full), args = list(id = "aa"), {
    pts <- .aa_opts(output$chat_length_dist_chart)$series[[1]]$data
    isimler <- vapply(pts, function(p) p$name, character(1))
    # "1-2 mesaj" "3-5 mesaj"den önce gelmeli (factor seviyesi).
    expect_identical(isimler, c("1-2 mesaj", "3-5 mesaj"))
  })
})

test_that("model dağılımı halka grafiği 'Kullanım' serisini model adlarıyla üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.aa_server(.aa_full), args = list(id = "aa"), {
    seri <- .aa_opts(output$model_distribution_chart)$series[[1]]
    expect_identical(seri$name, "Kullanım")
    isimler <- vapply(seri$data, function(p) p$name, character(1))
    expect_setequal(isimler, c("m1", "m2"))
  })
})

test_that("boş veri tüm gelişmiş analiz grafiklerinde korumayı tetikler ve hata vermez", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.aa_server(.aa_empty), args = list(id = "aa"), {
    expect_error(force(output$model_usage_trend_chart), NA)
    expect_error(force(output$avg_response_by_hour_chart), NA)
    expect_error(force(output$chat_length_dist_chart), NA)
    expect_error(force(output$model_distribution_chart), NA)
  })
})
