# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-genel-bakis-outputs-behavior.R
# Açıklama: R/module_admin_genel_bakis.R içindeki admin_overview_outputs()
#           highcharter render fonksiyonlarının davranışsal testleri.
#           Günlük trend areaspline ve geri bildirim halka grafiğinin seri adı,
#           verisi, renk eşlemesi ve boş-veri koruması doğrulanır.
#           Gerçek DB/tarayıcı yoktur; analytics_data reaktifi stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.gb_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_genel_bakis.R"),
  encoding = "UTF-8",
  local = .gb_env
)
.gb_env[["%>%"]] <- magrittr::`%>%`

# Dolu veri: günlük trend + geri bildirim özeti.
.gb_full <- function() {
  list(
    daily_trend = data.frame(
      chat_date = c("2026-01-01", "2026-01-02", "2026-01-03"),
      chat_count = c(3, 5, 8),
      stringsAsFactors = FALSE
    ),
    feedback_summary = data.frame(
      FeedbackType = c("like", "dislike"),
      cnt = c(7, 2),
      stringsAsFactors = FALSE
    )
  )
}

# Boş veri: her iki grafikte de nrow==0 koruma dalını tetikler.
.gb_empty <- function() {
  list(daily_trend = data.frame(), feedback_summary = data.frame())
}

# admin_overview_outputs'u bir moduleServer içinde saran yardımcı.
.gb_server <- function(data_fn, fmt) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      .gb_env$admin_overview_outputs(output, data_fn, fmt)
    })
  }
}

.gb_series <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts$series
}

test_that("günlük trend grafiği seri adını ve gerçek söyleşi sayılarını taşır", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.gb_server(.gb_full, function(x) as.character(x)), args = list(id = "gb"), {
    seri <- .gb_series(output$daily_trend_chart)
    expect_identical(seri[[1]]$name, "Söyleşi")
    expect_equal(as.numeric(unlist(seri[[1]]$data)), c(3, 5, 8))
    # Marka turuncu çizgi rengi korunur.
    expect_identical(seri[[1]]$color, "#ff6b35")
  })
})

test_that("günlük trend tarih etiketleri format_turkish_date fonksiyonundan üretilir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  # Tarih formatlayıcı çağrıldığını kanıtlamak için ayırt edici bir önek ekler.
  fmt <- function(x) paste0("TR-", x)

  shiny::testServer(.gb_server(.gb_full, fmt), args = list(id = "gb"), {
    j <- jsonlite::fromJSON(as.character(output$daily_trend_chart), simplifyVector = FALSE)
    kategoriler <- unlist(j$x$hc_opts$xAxis$categories)
    expect_true(all(grepl("^TR-", kategoriler)))
    expect_true("TR-2026-01-01" %in% kategoriler)
  })
})

test_that("geri bildirim halka grafiği like/dislike kodlarını Türkçe etikete ve renge çevirir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.gb_server(.gb_full, function(x) as.character(x)), args = list(id = "gb"), {
    pts <- .gb_series(output$feedback_donut_chart)[[1]]$data
    isimler <- vapply(pts, function(p) p$name, character(1))
    renkler <- vapply(pts, function(p) p$color, character(1))

    expect_identical(isimler, c("Beğeni", "Beğenmeme"))
    # like -> yeşil (#10b981), dislike -> kırmızı (#ef4444).
    expect_identical(renkler, c("#10b981", "#ef4444"))
    # y değerleri kaynaktaki cnt ile eşleşir.
    expect_equal(vapply(pts, function(p) as.numeric(p$y), numeric(1)), c(7, 2))
  })
})

test_that("boş veri her iki grafikte de hatasız boş highchart döndürür", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.gb_server(.gb_empty, function(x) as.character(x)), args = list(id = "gb"), {
    expect_error(force(output$daily_trend_chart), NA)
    expect_error(force(output$feedback_donut_chart), NA)
    # Boş highchart'ta seri bulunmaz.
    j <- jsonlite::fromJSON(as.character(output$daily_trend_chart), simplifyVector = FALSE)
    expect_true(is.null(j$x$hc_opts$series) || length(j$x$hc_opts$series) == 0)
  })
})
