# Dosya Yolu: tests/testthat/test-admin-bilge-yolac-outputs-behavior.R
# Açıklama: Bilge Yolaç yönetici grafiklerinin görünüm sözleşmeleri.

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.by_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_bilge_yolac.R"),
  encoding = "UTF-8",
  local = .by_env
)
.by_env[["%>%"]] <- magrittr::`%>%`
.by_env$JS <- htmlwidgets::JS

.by_data <- function() {
  list(
    daily_trend = data.frame(
      session_date = c("2026-07-29", "2026-07-28"),
      cnt = c(7, 3), stringsAsFactors = FALSE
    ),
    status_dist = data.frame(
      Status = c("completed", "failed", "stopped", "active", "other"),
      cnt = c(8, 2, 1, 3, 1), stringsAsFactors = FALSE
    ),
    top_users = data.frame(),
    recent_sessions = data.frame()
  )
}

.by_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    .by_env$admin_bilge_yolac_outputs(output, .by_data, list(emptyTable = "Yok"))
  })
}

.by_opts <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts
}

testthat::test_that("Bilge Yolaç günlük eğilimi haftalık eğilim görsel dilini kullanır", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")
  testthat::skip_if_not_installed("DT")

  shiny::testServer(.by_server, args = list(id = "by"), {
    opts <- .by_opts(output$by_daily_trend_chart)
    seri <- opts$series[[1]]

    testthat::expect_identical(opts$chart$type, "areaspline")
    testthat::expect_identical(seri$color, "#22c55e")
    testthat::expect_equal(opts$plotOptions$areaspline$lineWidth, 2.5)
    testthat::expect_equal(opts$plotOptions$areaspline$marker$radius, 3)
    testthat::expect_equal(
      vapply(seri$data, function(p) as.numeric(p$y), numeric(1)),
      c(3, 7)
    )
  })
})

testthat::test_that("Bilge Yolaç durum dağılımı halka ve anlamlı durum renkleri üretir", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("highcharter")
  testthat::skip_if_not_installed("DT")

  shiny::testServer(.by_server, args = list(id = "by"), {
    opts <- .by_opts(output$by_status_chart)
    noktalar <- opts$series[[1]]$data
    renkler <- stats::setNames(
      vapply(noktalar, function(p) p$color, character(1)),
      vapply(noktalar, function(p) p$name, character(1))
    )

    testthat::expect_identical(opts$chart$type, "pie")
    testthat::expect_identical(opts$plotOptions$pie$innerSize, "60%")
    testthat::expect_identical(renkler[["Tamamlandı"]], "#10b981")
    testthat::expect_identical(renkler[["Başarısız"]], "#ef4444")
    testthat::expect_identical(renkler[["Durduruldu"]], "#f59e0b")
    testthat::expect_identical(renkler[["Aktif"]], "#3b82f6")
    testthat::expect_identical(renkler[["other"]], "#94a3b8")
  })
})
