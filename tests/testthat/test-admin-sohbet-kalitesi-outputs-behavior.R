# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-sohbet-kalitesi-outputs-behavior.R
# Açıklama: R/module_admin_sohbet_kalitesi.R admin_chat_quality_outputs()
#           render fonksiyonlarının davranışsal testleri. Kodlu/kodsuz halka
#           grafiğinin renk eşlemesi, en uzun söyleşi / yeniden oluşturma
#           tablolarının başlıkları ve boş-veri koruması doğrulanır.
#           Gerçek DB/tarayıcı yoktur; analytics_data reaktifi stub'lanır.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.cq_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "module_admin_sohbet_kalitesi.R"),
  encoding = "UTF-8",
  local = .cq_env
)
.cq_env[["%>%"]] <- magrittr::`%>%`
.cq_env$admin_dt_header_callback <- htmlwidgets::JS("function(thead) {}")

.cq_full <- function() {
  list(
    code_ratio = data.frame(
      has_code = c("Kodlu", "Kodsuz"), cnt = c(30, 70), stringsAsFactors = FALSE
    ),
    longest_chats = data.frame(
      ChatTitle = c("Uzun söyleşi"), msg_count = c(42),
      full_name = c("Ali Veli"), user_name = c("aliveli"), stringsAsFactors = FALSE
    ),
    regenerated_responses = data.frame(
      ChatTitle = c("Yeniden söyleşi"), user_name = c("ayse"),
      ai_count = c(5), user_count = c(2), stringsAsFactors = FALSE
    )
  )
}

.cq_empty <- function() {
  bos <- data.frame()
  list(code_ratio = bos, longest_chats = bos, regenerated_responses = bos)
}

.cq_server <- function(data_fn) {
  function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      .cq_env$admin_chat_quality_outputs(output, data_fn, list(emptyTable = "Yok"))
    })
  }
}

.cq_series <- function(output_value) {
  jsonlite::fromJSON(as.character(output_value), simplifyVector = FALSE)$x$hc_opts$series
}

test_that("kodlu/kodsuz halka grafiği etiketlere göre mor ve gri renkleri eşler", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")

  shiny::testServer(.cq_server(.cq_full), args = list(id = "cq"), {
    pts <- .cq_series(output$code_ratio_chart)[[1]]$data
    isimler <- vapply(pts, function(p) p$name, character(1))
    renkler <- vapply(pts, function(p) p$color, character(1))

    expect_identical(isimler, c("Kodlu", "Kodsuz"))
    # Kodlu -> mor (#8b5cf6), diğeri -> gri (#64748b).
    expect_identical(renkler, c("#8b5cf6", "#64748b"))
    expect_equal(vapply(pts, function(p) as.numeric(p$y), numeric(1)), c(30, 70))
  })
})

test_that("en uzun söyleşiler tablosu tam adı görünen ad olarak kullanır ve Türkçe başlık üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.cq_server(.cq_full), args = list(id = "cq"), {
    tablo <- as.character(output$longest_chats_table)
    expect_true(grepl("Söyleşi Başlığı", tablo, fixed = TRUE))
    expect_true(grepl("Mesaj", tablo, fixed = TRUE))
    expect_true(grepl("Kullanıcı", tablo, fixed = TRUE))
  })
})

test_that("yeniden oluşturma tablosu Türkçe sütun başlıklarını üretir", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.cq_server(.cq_full), args = list(id = "cq"), {
    tablo <- as.character(output$regenerated_table)
    expect_true(grepl("YZ Yanıt", tablo, fixed = TRUE))
    expect_true(grepl("Kullanıcı Mesaj", tablo, fixed = TRUE))
    expect_true(grepl("Yeniden Oluşturma", tablo, fixed = TRUE))
  })
})

test_that("boş veri tüm söyleşi kalitesi çıktılarında korumayı tetikler ve hata vermez", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("highcharter")
  skip_if_not_installed("DT")

  shiny::testServer(.cq_server(.cq_empty), args = list(id = "cq"), {
    expect_error(force(output$code_ratio_chart), NA)
    expect_error(force(output$longest_chats_table), NA)
    expect_error(force(output$regenerated_table), NA)
  })
})
