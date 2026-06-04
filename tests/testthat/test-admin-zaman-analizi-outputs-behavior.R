# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-zaman-analizi-outputs-behavior.R
# Açıklama: R/module_admin_zaman_analizi.R admin_time_analysis_outputs()
#           render fonksiyonlarının davranışsal testleri. Haftalık trend
#           areaspline, çift eksenli aylık büyüme (turkish_months) ve yeni
#           kullanıcı aktivasyon tablosu doğrulanır.
#           Gerçek DB/tarayıcı yoktur; analytics_data reaktifi stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.za_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_zaman_analizi.R"),
  encoding = "UTF-8",
  local = .za_env
)
.za_env[["%>%"]] <- magrittr::`%>%`
.za_env$JS <- htmlwidgets::JS
.za_env$admin_dt_header_callback <- htmlwidgets::JS("function(thead) {}")

.tr_months <- c("Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık")

.za_full <- function() {
  list(
    weekly_trend = data.frame(
      year_num = c(2026, 2026), week_num = c(1, 2),
      week_start = c("2026-01-01", "2026-01-08"), week_end = c("2026-01-07", "2026-01-14"),
      cnt = c(4, 9), stringsAsFactors = FALSE
    ),
    new_user_activation = data.frame(
      full_name = c("Ali Veli"), user_name = c("aliveli"),
      first_chat = c("2026-01-01 09:00:00"), chat_count = c(3), active_days = c(2),
      stringsAsFactors = FALSE
    ),
    monthly_growth = data.frame(
      year_num = c(2026, 2026), month_num = c(1, 2),
      chat_count = c(10, 20), unique_users = c(5, 8), stringsAsFactors = FALSE
    )
  )
}

.za_empty <- function() {
  bos <- data.frame()
  list(weekly_trend = bos, new_user_activation = bos, monthly_growth = bos)
}

.za_server <- function(data_fn) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      .za_env$admin_time_analysis_outputs(output, data_fn, list(emptyTable = "Yok"), .tr_months)
    })
  }
}

.za_opts <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts
}

test_that("haftalık trend grafiği 'Söyleşi' serisini yeşil renkle ve doğru sayılarla üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.za_server(.za_full), args = list(id = "za"), {
    seri <- .za_opts(output$weekly_trend_chart)$series
    expect_identical(seri[[1]]$name, "Söyleşi")
    expect_identical(seri[[1]]$color, "#22c55e")
    expect_equal(vapply(seri[[1]]$data, function(p) as.numeric(p$y), numeric(1)), c(4, 9))
  })
})

test_that("aylık büyüme grafiği iki seri (Söyleşi + Benzersiz Kullanıcı) ve Türkçe ay etiketleri üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.za_server(.za_full), args = list(id = "za"), {
    opts <- .za_opts(output$monthly_growth_chart)
    seri <- opts$series
    isimler <- vapply(seri, function(s) s$name, character(1))
    renkler <- vapply(seri, function(s) s$color, character(1))

    expect_identical(isimler, c("Söyleşi", "Benzersiz Kullanıcı"))
    expect_identical(renkler, c("#3b82f6", "#f59e0b"))

    # Ay etiketleri turkish_months ile üretilir: "Ocak 2026", "Şubat 2026".
    kategoriler <- unlist(opts$xAxis$categories)
    expect_true("Ocak 2026" %in% kategoriler)
    expect_true("Şubat 2026" %in% kategoriler)
  })
})

test_that("yeni kullanıcı aktivasyon tablosu Türkçe başlıkları üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.za_server(.za_full), args = list(id = "za"), {
    tablo <- as.character(output$new_user_activation_table)
    expect_true(grepl("İlk Söyleşi", tablo, fixed = TRUE))
    expect_true(grepl("Aktif Gün", tablo, fixed = TRUE))
  })
})

test_that("boş veri tüm zaman analizi çıktılarında korumayı tetikler ve hata vermez", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.za_server(.za_empty), args = list(id = "za"), {
    expect_error(force(output$weekly_trend_chart), NA)
    expect_error(force(output$monthly_growth_chart), NA)
    expect_error(force(output$new_user_activation_table), NA)
  })
})
