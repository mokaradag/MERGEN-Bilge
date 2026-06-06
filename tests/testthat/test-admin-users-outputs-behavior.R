# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-users-outputs-behavior.R
# Açıklama: module_admin_kullanici_analizi.R içindeki admin_users_outputs render
#           fonksiyonunun davranışsal testleri. En aktif kullanıcılar grafiği
#           seri verisini (mesaj sayısına göre azalan), boş-veri korumalarını ve
#           güçlü kullanıcılar tablosunun Türkçe başlıklarını doğrular.
#           highcharter çıktısı JSON olarak okunur; gerçek DB/LLM/ağ GEREKMEZ.
# ==============================================================================

testthat::skip_if_not_installed("highcharter")
testthat::skip_if_not_installed("DT")

suppressMessages({
  library(shiny)
  library(highcharter)
  library(DT)
})

.admin_users_env <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_admin_analytics.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "module_admin_kullanici_analizi.R"),
         encoding = "UTF-8", local = env)
  env
}

.admin_users_data <- function(empty = FALSE) {
  if (isTRUE(empty)) {
    return(list(
      top_users = data.frame(user_name = character(0), full_name = character(0), message_count = integer(0)),
      power_users = data.frame(user_name = character(0), full_name = character(0), chat_count = integer(0),
                               total_messages = integer(0), avg_chat_length = numeric(0)),
      usage_by_day = data.frame(day_num = integer(0), message_count = integer(0)),
      usage_by_hour = data.frame(hour = integer(0), message_count = integer(0)),
      file_uploaders = data.frame()
    ))
  }
  list(
    top_users = data.frame(
      user_name = c("ali", "veli", "ayse"),
      full_name = c("Ali Ak", "Veli Vural", "Ayşe Yıldız"),
      message_count = c(7L, 12L, 3L),
      stringsAsFactors = FALSE
    ),
    power_users = data.frame(
      user_name = c("ali"), full_name = c("Ali Ak"),
      chat_count = 4L, total_messages = 20L, avg_chat_length = 5.0,
      stringsAsFactors = FALSE
    ),
    usage_by_day = data.frame(day_num = integer(0), message_count = integer(0)),
    usage_by_hour = data.frame(hour = integer(0), message_count = integer(0)),
    file_uploaders = data.frame()
  )
}

testthat::test_that("admin_users_outputs en aktif kullanıcılar grafiğini mesaj sayısına göre azalan sıralar", {
  env <- .admin_users_env()
  data_fn <- function() .admin_users_data(empty = FALSE)

  shiny::testServer(
    function(input, output, session) {
      env$admin_users_outputs(output, data_fn, list(), c("Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"))
    },
    {
      j <- jsonlite::fromJSON(as.character(output$top_users_chart), simplifyVector = FALSE)
      y_vals <- vapply(j$x$hc_opts$series[[1]]$data, function(p) p$y, numeric(1))
      # En çok mesaj (12) ilk sırada, azalan: 12, 7, 3
      testthat::expect_identical(y_vals, c(12, 7, 3))
    }
  )
})

testthat::test_that("admin_users_outputs boş veri grafiklerde hata vermez", {
  env <- .admin_users_env()
  data_fn <- function() .admin_users_data(empty = TRUE)

  shiny::testServer(
    function(input, output, session) {
      env$admin_users_outputs(output, data_fn, list(), c("Pzt"))
    },
    {
      # Boş veride highchart() döner; seri olmamalı, hata fırlatmamalı.
      j_top <- jsonlite::fromJSON(as.character(output$top_users_chart), simplifyVector = FALSE)
      testthat::expect_true(length(j_top$x$hc_opts$series) == 0)
      j_day <- jsonlite::fromJSON(as.character(output$usage_by_day_chart), simplifyVector = FALSE)
      testthat::expect_true(length(j_day$x$hc_opts$series) == 0)
    }
  )
})

testthat::test_that("admin_users_outputs güçlü kullanıcılar tablosunu Türkçe başlıklarla üretir", {
  env <- .admin_users_env()
  data_fn <- function() .admin_users_data(empty = FALSE)

  shiny::testServer(
    function(input, output, session) {
      env$admin_users_outputs(output, data_fn, list(), c("Pzt"))
    },
    {
      tbl_json <- as.character(output$power_users_table)
      # ASCII başlık doğrudan görünür; Türkçe başlıklar \u-escape olabilir, ASCII'yi kontrol ederiz.
      testthat::expect_true(grepl("Mesaj", tbl_json, fixed = TRUE))
      testthat::expect_true(grepl("admin-datatable", tbl_json, fixed = TRUE))
    }
  )
})
