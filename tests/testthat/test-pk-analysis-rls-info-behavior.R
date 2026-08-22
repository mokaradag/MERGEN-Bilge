# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-rls-info-behavior.R
# Açıklama: R/helpers_pk_analysis_security_summary.R get_user_rls_info()
#           satır-düzeyi yetki çözümleme davranışını mock DB ile doğrular.
#           Kullanıcı bulunamama, departman parse, ADMIN, PY proje ve KY-P/DIR-P
#           EPS yetki yolları test edilir. Gerçek DB yok; cat çıktısı bastırılır.
# ==============================================================================

testthat::local_edition(3)

.rls_env <- new.env(parent = globalenv())
# Kaynak sırası ÇALIŞMA ZAMANI manifestini yansıtır: kimlik/izin yardımcıları
# `helpers_pk_rls_identity.R` içindedir, redaktör ise temel katmandadır
# (tanı metinleri KAPALI BAŞARISIZ biçimde redakte edilir).
for (.f in c("utils_log_redact.R", "helpers_pk_rls_identity.R",
             "helpers_pk_analysis_security_summary.R")) {
  source(file.path(resolve_repo_root_for_tests(), "R", .f),
         encoding = "UTF-8", local = .rls_env)
}
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
      # İzin okuması artık SQL TARAFINDA kullanıcıya daraltılır: operatör
      # sorgusu türetilmiş tablo olarak sarılır ve `KullaniciAdi = ?` yüklemi
      # eklenir. Sahte sürücü bu sözleşmeyi doğrular.
      if (grepl("PY_PERMISSION_SQL", statement, fixed = TRUE)) {
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

test_that("izin okumasi SQL tarafinda kullaniciya daraltilir", {
  gorulen <- new.env(parent = emptyenv())
  gorulen$ifade <- NA_character_
  gorulen$params <- NULL

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "PY", MasrafYeriKodu = "10",
                          stringsAsFactors = FALSE))
      }
      if (grepl("PY_PERMISSION_SQL", statement, fixed = TRUE)) {
        gorulen$ifade <- statement
        gorulen$params <- list(...)$params
        return(data.frame(KullaniciAdi = "ali", ProjeKodu = "P1", stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )

  r <- .rls_call()
  expect_setequal(r$allowed_projects, "P1")
  expect_true(grepl("KullaniciAdi = ?", gorulen$ifade, fixed = TRUE))
  expect_equal(gorulen$params, list("ali"))
})

test_that("DB tarafi daraltma calismazsa R tarafinda filtrelenir", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "PY", MasrafYeriKodu = "10",
                          stringsAsFactors = FALSE))
      }
      # Sarmalanmış biçim reddedilir (ör. sondaki ORDER BY): eski davranışa
      # dönülür ve KULLANICI FİLTRESİ R tarafında uygulanır.
      if (grepl("mb_izin", statement, fixed = TRUE)) stop("Incorrect syntax near ORDER.")
      if (identical(statement, "PY_PERMISSION_SQL")) {
        return(data.frame(KullaniciAdi = c("ali", "veli"), ProjeKodu = c("P1", "P9"),
                          stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_setequal(r$allowed_projects, "P1")
})

test_that("izin tablosundaki farkli buyuk/kucuk harf yazimi kapsami dusurmez", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "Ali", Yetki = "PY", MasrafYeriKodu = "10",
                          stringsAsFactors = FALSE))
      }
      if (grepl("PY_PERMISSION_SQL", statement, fixed = TRUE)) {
        # SQL Server collation'ı büyük/küçük harf duyarsızdır; R'nin `==`
        # karşılaştırması DEĞİLDİR. Yazım farkı kapsamı boşaltmamalıdır.
        return(data.frame(KullaniciAdi = "ALI", ProjeKodu = "P1", stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call(username = "Ali")
  expect_setequal(r$allowed_projects, "P1")
  expect_equal(r$scope_state_projects, "available")
})

test_that("mukerrer DC01 yetki kaydi KAPALI BASARISIZ olur", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = c("ali", "ali"),
                          Yetki = c("USER", "ADMIN"),
                          MasrafYeriKodu = c("10", "ADMIN"),
                          stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_false(isTRUE(r$authorized))
  expect_true(isTRUE(r$ambiguous))
})

test_that("MasrafYeriKodu NA iken departman kapsami COZULEMEDI sayilir", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "USER",
                          MasrafYeriKodu = NA_character_, stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_true(isTRUE(r$authorized))
  expect_null(r$allowed_depts)
  # ADMIN işareti DEĞİL: kapsam çözülemedi. `pk_rls_plan()` bunu durdurma
  # nedeni sayar; `not_applicable` deseydi kullanıcı TÜM satırları görürdü.
  expect_equal(r$scope_state_depts, "unavailable")
})

test_that("MasrafYeriKodu ADMIN ise departman kisiti BILEREK yoktur", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "USER",
                          MasrafYeriKodu = "ADMIN", stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_null(r$allowed_depts)
  expect_equal(r$scope_state_depts, "not_applicable")
})

test_that("get_user_rls_info KY-P yetkisinde EPS kodlarını çözer", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("DC01_user_base", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", Yetki = "KY-P", MasrafYeriKodu = "10",
                          stringsAsFactors = FALSE))
      }
      if (grepl("EPS_PERMISSION_SQL", statement, fixed = TRUE)) {
        return(data.frame(KullaniciAdi = "ali", EPSKodu = "E1,E2", stringsAsFactors = FALSE))
      }
      data.frame()
    },
    .package = "DBI"
  )
  r <- .rls_call()
  expect_setequal(r$allowed_eps, c("E1", "E2"))
})
