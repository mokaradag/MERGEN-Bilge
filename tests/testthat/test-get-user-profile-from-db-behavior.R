# ==============================================================================
# Dosya Yolu: tests/testthat/test-get-user-profile-from-db-behavior.R
# Açıklama: R/helpers_database.R get_user_profile_from_db() davranış testleri.
#           Geçersiz kimlikte erken NULL, UserID vs KullaniciAdi WHERE
#           yönlendirmesi, satır bulunamayınca NULL, dönen satırın liste'ye
#           çevrilip user_id eklenmesi ve görünür/teknik alan normalizasyonu
#           doğrulanır. DBI sınırı (get_connection / dbGetQuery) taklit edilir;
#           GERÇEK SQL Server/DB GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)

# Yakalanan sorgu/parametreleri kayıt eden DBI taklidi ile izole ortam.
.gup_env <- function(query_rows) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  cap <- new.env()
  cap$called <- 0L
  cap$query <- NULL
  cap$params <- NULL
  env$.cap <- cap

  env$get_connection <- function() list(conn = "SAHTE_BAGLANTI")
  env$release_connection <- function(info) invisible(NULL)
  env$normalize_db_params <- function(p) p
  env$normalize_db_technical_value <- function(x) as.character(x)
  # Görünür alan normalizasyonunu locale-bağımsız bir önekle gözlemle.
  env$normalize_db_visible_value <- function(x) paste0("VIS:", as.character(x))
  env$normalize_text_frame_utf8 <- function(df, ...) df
  env$dbGetQuery <- function(conn, query, params = NULL) {
    cap$called <- cap$called + 1L
    cap$query <- query
    cap$params <- params
    query_rows
  }

  suppressMessages(source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_database.R"),
    encoding = "UTF-8", local = env
  ))
  # Kaynak sonrası DBI stub'larının üretim tanımlarını gölgelediğinden emin ol.
  env$get_connection <- function() list(conn = "SAHTE_BAGLANTI")
  env$release_connection <- function(info) invisible(NULL)
  env$dbGetQuery <- function(conn, query, params = NULL) {
    cap$called <- cap$called + 1L
    cap$query <- query
    cap$params <- params
    query_rows
  }
  env$normalize_db_params <- function(p) p
  env$normalize_db_technical_value <- function(x) as.character(x)
  env$normalize_db_visible_value <- function(x) paste0("VIS:", as.character(x))
  env$normalize_text_frame_utf8 <- function(df, ...) df
  env
}

.gup_one_row <- function() {
  data.frame(
    UserID = 1234L, KullaniciAdi = "mkaradag", KaynakAdi = "Mustafa Karadağ",
    LastLoginDate = "2026-01-01", Sicil = "5678", Email = "m@x.tr",
    Sektor = "yazılım", Departman = "bilgi işlem", Mudurluk = "merkez",
    MasrafYeriKodu = "MY01", SonGirisKaynagi = "sso",
    stringsAsFactors = FALSE
  )
}

test_that("geçersiz uid ve boş username için DB'ye gitmeden NULL döner", {
  env <- .gup_env(.gup_one_row())
  expect_null(env$get_user_profile_from_db(user_id = 0L, username = ""))
  expect_null(env$get_user_profile_from_db(user_id = NA_integer_, username = NULL))
  # Erken çıkış: dbGetQuery hiç çağrılmamalı.
  expect_identical(env$.cap$called, 0L)
})

test_that("geçerli uid UserID WHERE'ine yönlenir ve uid parametresini taşır", {
  env <- .gup_env(.gup_one_row())
  out <- env$get_user_profile_from_db(user_id = 1234L)
  expect_true(grepl("WHERE UserID = ?", env$.cap$query, fixed = TRUE))
  expect_identical(env$.cap$params[[1]], 1234L)
  expect_true(is.list(out))
  expect_identical(out$user_id, 1234L)
})

test_that("yalnızca username verilince KullaniciAdi WHERE'ine yönlenir", {
  env <- .gup_env(.gup_one_row())
  env$get_user_profile_from_db(user_id = NULL, username = "mkaradag")
  expect_true(grepl("LOWER(KullaniciAdi)", env$.cap$query, fixed = TRUE))
  expect_identical(env$.cap$params[[1]], "mkaradag")
})

test_that("satır bulunamazsa NULL döner", {
  bos <- .gup_one_row()[0, , drop = FALSE]
  env <- .gup_env(bos)
  expect_null(env$get_user_profile_from_db(user_id = 999L))
})

test_that("görünür alanlar normalize_db_visible_value ile dönüştürülür", {
  env <- .gup_env(.gup_one_row())
  out <- env$get_user_profile_from_db(user_id = 1234L)
  # Görünür alan "VIS:" önekiyle işaretlenmeli (locale-bağımsız); teknik alan
  # (KullaniciAdi) ise dokunulmadan kalmalı.
  expect_identical(out$Departman, "VIS:bilgi işlem")
  expect_identical(out$KullaniciAdi, "mkaradag")
})
