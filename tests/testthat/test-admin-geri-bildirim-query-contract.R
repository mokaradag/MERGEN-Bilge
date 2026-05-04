# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-geri-bildirim-query-contract.R
# Açıklama: Geri Bildirim Analizi SQL sorgu paketi extraction sözleşmesini doğrular.
# ==============================================================================

test_that("admin geri bildirim SQL sorgu paketi beklenen anahtarları korur", {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R/helpers_admin_geri_bildirim_queries.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  queries <- helper_env$admin_gb_feedback_queries()

  expected_names <- c(
    "tumu",
    "toplam",
    "ort_memnuniyet",
    "memnuniyet_dagilim",
    "nps_dagilim",
    "iletisim_izni",
    "gunluk_trend",
    "memnuniyet_trend",
    "nps_trend",
    "etiketler_ham",
    "bugun",
    "bu_hafta",
    "kullanici_memnuniyet",
    "nps_puan_dagilim",
    "memnuniyet_nps_korelasyon"
  )

  expect_equal(names(queries), expected_names)
  expect_true(all(vapply(queries, is.character, logical(1))))
  expect_true(all(nzchar(trimws(unlist(queries, use.names = FALSE)))))
  expect_true(grepl("MB_Destek_Geri_Bildirim", queries$tumu, fixed = TRUE))
  expect_true(grepl("DC01_userr", queries$tumu, fixed = TRUE))
  expect_true(grepl("ORDER BY gb.OlusturmaTarihi DESC", queries$tumu, fixed = TRUE))
})

test_that("admin_gb_fetch_data query_fn enjeksiyonu ile DB'ye dokunmadan çalışır", {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R/helpers_admin_geri_bildirim_queries.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  called_sql <- character(0)

  fake_query <- function(sql) {
    called_sql <<- c(called_sql, sql)
    data.frame(ok = TRUE)
  }

  result <- helper_env$admin_gb_fetch_data(query_fn = fake_query)
  expected_names <- names(helper_env$admin_gb_feedback_queries())

  expect_equal(names(result), expected_names)
  expect_equal(length(called_sql), length(expected_names))
  expect_true(all(vapply(result, is.data.frame, logical(1))))
})

test_that("admin_gb_fetch_data geçersiz query_fn değerini açık hata ile reddeder", {
  repo_root <- resolve_repo_root_for_tests()
  helper_env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R/helpers_admin_geri_bildirim_queries.R"),
    encoding = "UTF-8",
    local = helper_env
  )

  expect_error(
    helper_env$admin_gb_fetch_data(query_fn = "not-a-function"),
    "query_fn bir fonksiyon olmalıdır"
  )
})