# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-rls-info-behavior.R
# Açıklama: R/helpers_pk_analysis_security_summary.R get_user_rls_info()
#           satır-düzeyi yetki çözümleme davranışını mock DB ile doğrular.
#           Kullanıcı bulunamama, departman parse, ADMIN, PY proje ve KY-P/DIR-P
#           EPS yetki yolları test edilir. Gerçek DB yok; cat çıktısı bastırılır.
# ==============================================================================

testthat::local_edition(3)

.rls_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_analysis_security_summary.R"),
  encoding = "UTF-8", local = .rls_env
)
# PY/EPS sorgu metinleri üretimde global tanımlıdır; mock'un ayırt edebilmesi için
# test ortamında ayırt edici sabitler atanır.
.rls_env$sql_permission_py <- "PY_PERMISSION_SQL"
.rls_env$sql_permission_eps <- "EPS_PERMISSION_SQL"

# cat tabanlı tanılama çıktısını bastırarak RLS sonucunu döndüren yardımcı.
.rls_call <- function(username = "ali", conn = "FAKECONN") {
  res <- NULL
  invisible(utils::capture.output(res <- .rls_env$get_user_rls_info(username, conn)))
  res
}

test_that("get_user_rls_info kullanıcı DC01 tablosunda yoksa authorized=FALSE döner", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(),
    .package = "DBI"
  )
  r <- .rls_call()
  expect_false(r$authorized)
  expect_true(nzchar(r$reason))
})

test_that("get_user_rls_info MasrafYeriKodu'nu virgülle bölerek allowed_depts üretir", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "USER", MasrafYeriKodu = "10,20",
                          stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_true(r$authorized)
  expect_identical(r$allowed_depts, c("10", "20"))
  # USER yetkisinde proje/EPS kısıtı yoktur.
  expect_null(r$allowed_projects)
  expect_null(r$allowed_eps)
})

test_that("get_user_rls_info ADMIN masraf yerinde departman kısıtı uygulamaz", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "USER", MasrafYeriKodu = "ADMIN",
                          stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_true(r$authorized)
  expect_null(r$allowed_depts)
})

test_that("get_user_rls_info PY yetkisinde izinli projeleri çözer", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "PY", MasrafYeriKodu = "10",
                          stringsAsFactors = FALSE))
      }
      if (identical(statement, "PY_PERMISSION_SQL")) {
        return(data.frame(KullaniciAdi = c("ali", "ali"), ProjeKodu = c("P1", "P2"),
                          stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_setequal(r$allowed_projects, c("P1", "P2"))
})

test_that("get_user_rls_info KY-P yetkisinde EPS kodlarını çözer", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "KY-P", MasrafYeriKodu = "10",
                          stringsAsFactors = FALSE))
      }
      if (identical(statement, "EPS_PERMISSION_SQL")) {
        return(data.frame(KullaniciAdi = "ali", EPSKodu = "E1,E2", stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_setequal(r$allowed_eps, c("E1", "E2"))
})
