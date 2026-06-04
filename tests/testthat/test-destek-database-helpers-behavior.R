# ==============================================================================
# Dosya Yolu: tests/testthat/test-destek-database-helpers-behavior.R
# Açıklama: R/helpers_destek_database.R destek listeleme/güncelleme yardımcılarının
#           davranışsal testleri. Durum doğrulaması (DB'siz), TOP/UserID sorgu
#           biçimi ve UPDATE yürütmesi mock DB ile doğrulanır. Gerçek DB yok.
# ==============================================================================

testthat::local_edition(3)

.dsd_make_env <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_destek_database.R"),
    encoding = "UTF-8", local = env
  )
  env$get_connection <- function(...) list(conn = "FAKE")
  env$release_connection <- function(...) invisible(NULL)
  env
}

# -----------------------------------------------------------------------------
# destek_hata_durum_guncelle (durum doğrulaması DB'den önce çalışır)
# -----------------------------------------------------------------------------

test_that("destek_hata_durum_guncelle geçersiz durumda DB'ye gitmeden hata verir", {
  env <- .dsd_make_env()
  expect_error(env$destek_hata_durum_guncelle(5, "gecersiz_durum"), "Geçersiz durum")
})

test_that("destek_hata_durum_guncelle geçerli durumda UPDATE yürütür", {
  env <- .dsd_make_env()
  yakalanan <- new.env()
  testthat::local_mocked_bindings(
    dbExecute = function(conn, statement, params = NULL, ...) {
      yakalanan$q <- statement
      yakalanan$p <- params
      1L
    },
    .package = "DBI"
  )
  n <- env$destek_hata_durum_guncelle(5, "cozuldu")
  expect_equal(n, 1L)
  expect_true(grepl("UPDATE MB_Destek_Hata_Bildir", yakalanan$q, fixed = TRUE))
  # İki parametre: yeni durum + bildirim id.
  expect_equal(length(yakalanan$p), 2L)
  expect_identical(yakalanan$p[[1]], "cozuldu")
})

# -----------------------------------------------------------------------------
# destek_geri_bildirim_listele / destek_hata_bildirim_listele
# -----------------------------------------------------------------------------

test_that("destek_geri_bildirim_listele limiti TOP olarak uygular ve sonucu döndürür", {
  env <- .dsd_make_env()
  yakalanan <- new.env()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      yakalanan$q <- statement
      data.frame(GeriBildirimID = 1, KullaniciAdi = "ali", Memnuniyet = "iyi",
                 stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  r <- env$destek_geri_bildirim_listele(50)
  expect_true(grepl("TOP 50", yakalanan$q, fixed = TRUE))
  expect_true(grepl("MB_Destek_Geri_Bildirim", yakalanan$q, fixed = TRUE))
  expect_equal(nrow(r), 1L)
})

test_that("destek_hata_bildirim_listele hata bildirim tablosundan TOP ile okur", {
  env <- .dsd_make_env()
  yakalanan <- new.env()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      yakalanan$q <- statement
      data.frame(HataBildirimID = 1, Konular = "k", Durum = "acik", stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  r <- env$destek_hata_bildirim_listele(25)
  expect_true(grepl("TOP 25", yakalanan$q, fixed = TRUE))
  expect_true(grepl("MB_Destek_Hata_Bildir", yakalanan$q, fixed = TRUE))
  expect_equal(nrow(r), 1L)
})

# -----------------------------------------------------------------------------
# destek_kullanici_geri_bildirim / destek_kullanici_hata_bildirim
# -----------------------------------------------------------------------------

test_that("destek_kullanici_geri_bildirim UserID parametreli sorgu çalıştırır", {
  env <- .dsd_make_env()
  yakalanan <- new.env()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, params = NULL, ...) {
      yakalanan$q <- statement
      yakalanan$p <- params
      data.frame(GeriBildirimID = 9, Memnuniyet = "iyi", stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  r <- env$destek_kullanici_geri_bildirim(7)
  expect_true(grepl("WHERE UserID = ?", yakalanan$q, fixed = TRUE))
  expect_equal(yakalanan$p[[1]], 7L)
  expect_equal(nrow(r), 1L)
})

test_that("destek_kullanici_hata_bildirim kullanıcının hata geçmişini UserID ile okur", {
  env <- .dsd_make_env()
  yakalanan <- new.env()
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, params = NULL, ...) {
      yakalanan$q <- statement
      yakalanan$p <- params
      data.frame(HataBildirimID = 3, Konular = "k", Durum = "acik", stringsAsFactors = FALSE)
    },
    .package = "DBI"
  )
  r <- env$destek_kullanici_hata_bildirim(7)
  expect_true(grepl("MB_Destek_Hata_Bildir", yakalanan$q, fixed = TRUE))
  expect_true(grepl("WHERE UserID = ?", yakalanan$q, fixed = TRUE))
  expect_equal(yakalanan$p[[1]], 7L)
})
