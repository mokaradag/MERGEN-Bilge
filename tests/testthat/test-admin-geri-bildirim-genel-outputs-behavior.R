# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-geri-bildirim-genel-outputs-behavior.R
# Açıklama: R/module_admin_geri_bildirim_genel.R admin_feedback_outputs()
#           render fonksiyonlarının davranışsal testleri. Gruplu sütun
#           grafiklerinin Beğeni/Beğenmeme seri adı + renk eşlemesi, bucket
#           sıralaması, eğilim grafiği ve model tablosu başlıkları doğrulanır.
#           Gerçek DB/tarayıcı yoktur; analytics_data reaktifi stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.fb_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_geri_bildirim_genel.R"),
  encoding = "UTF-8",
  local = .fb_env
)
.fb_env[["%>%"]] <- magrittr::`%>%`
.fb_env$admin_dt_header_callback <- htmlwidgets::JS("function(thead) {}")
# Sayı formatlayıcı stub'u (bar hücreleri için).
.fb_env$admin_format_number <- function(x) as.character(x)

.fb_full <- function() {
  list(
    model_feedback = data.frame(
      ModelUsed = c("model-x", "model-y"),
      likes = c(8, 4), dislikes = c(2, 6), total_responses = c(10, 10),
      stringsAsFactors = FALSE
    ),
    # Kasten karışık sırada verilir; grafik bucket seviyesine göre sıralamalı.
    response_time_feedback = data.frame(
      duration_bucket = c("20+ sn", "0-5 sn", "5-10 sn"),
      likes = c(1, 9, 5), dislikes = c(4, 1, 2),
      stringsAsFactors = FALSE
    ),
    response_length_feedback = data.frame(
      length_bucket = c("Kısa (< 500)", "Uzun (1500-3000)"),
      likes = c(7, 3), dislikes = c(1, 2),
      stringsAsFactors = FALSE
    ),
    feedback_trend = data.frame(
      feedback_date = c("2026-01-02", "2026-01-01"),
      likes = c(5, 3), dislikes = c(1, 2),
      stringsAsFactors = FALSE
    )
  )
}

.fb_empty <- function() {
  bos <- data.frame()
  list(model_feedback = bos, response_time_feedback = bos,
       response_length_feedback = bos, feedback_trend = bos)
}

.fb_server <- function(data_fn, fmt = function(x) as.character(x)) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      .fb_env$admin_feedback_outputs(output, data_fn, list(emptyTable = "Yok"), fmt)
    })
  }
}

.fb_series <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts$series
}
.fb_categories <- function(output_value) {
  unlist(jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts$xAxis$categories)
}

test_that("yanıt süresi gruplu grafiği bucket seviyesine göre sıralar ve iki seriyi renklendirir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.fb_server(.fb_full), args = list(id = "fb"), {
    seri <- .fb_series(output$response_time_feedback_chart)
    isimler <- vapply(seri, function(s) s$name, character(1))
    renkler <- vapply(seri, function(s) s$color, character(1))

    expect_identical(isimler, c("Beğeni", "Beğenmeme"))
    expect_identical(renkler, c("#10b981", "#ef4444"))

    # x ekseni bucket sırasına göre: 0-5 sn, 5-10 sn, 20+ sn (10-20 sn veride yok).
    expect_identical(.fb_categories(output$response_time_feedback_chart), c("0-5 sn", "5-10 sn", "20+ sn"))
    # Beğeni serisi sıralı bucket'lara karşılık gelir: 0-5 sn=9, 5-10 sn=5, 20+ sn=1.
    expect_equal(as.numeric(unlist(seri[[1]]$data)), c(9, 5, 1))
  })
})

test_that("yanıt uzunluğu gruplu grafiği Beğeni/Beğenmeme serilerini üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.fb_server(.fb_full), args = list(id = "fb"), {
    seri <- .fb_series(output$response_length_feedback_chart)
    isimler <- vapply(seri, function(s) s$name, character(1))
    expect_identical(isimler, c("Beğeni", "Beğenmeme"))
    # Bucket sırası: Kısa önce, Uzun sonra.
    expect_identical(.fb_categories(output$response_length_feedback_chart), c("Kısa (< 500)", "Uzun (1500-3000)"))
  })
})

test_that("geri bildirim eğilimi grafiği tarihe göre artan sıralar ve format_turkish_date kullanır", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.fb_server(.fb_full, fmt = function(x) paste0("D:", x)), args = list(id = "fb"), {
    kategoriler <- .fb_categories(output$feedback_trend_chart)
    # feedback_date artan sıralandığı için 01 önce gelir; etiketler fmt'den üretilir.
    expect_identical(kategoriler, c("D:2026-01-01", "D:2026-01-02"))
  })
})

test_that("model geri bildirim tablosu Türkçe başlıkları üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.fb_server(.fb_full), args = list(id = "fb"), {
    tablo <- as.character(output$model_feedback_table)
    expect_true(grepl("Model", tablo, fixed = TRUE))
    expect_true(grepl("Toplam Yanıt", tablo, fixed = TRUE))
    expect_true(grepl("Beğeni Oranı (%)", tablo, fixed = TRUE))
  })
})

test_that("boş veri tüm geri bildirim çıktılarında korumayı tetikler ve hata vermez", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.fb_server(.fb_empty), args = list(id = "fb"), {
    expect_error(force(output$response_time_feedback_chart), NA)
    expect_error(force(output$response_length_feedback_chart), NA)
    expect_error(force(output$feedback_trend_chart), NA)
    expect_error(force(output$model_feedback_table), NA)
  })
})
