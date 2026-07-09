# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-canli-durum-behavior.R
# Açıklama: ortak_db_canli_durumlar() canlı durum (çevrim içi kullanıcı) DB
#           katmanı regresyon testleri. Kritik hata: davet panelinin "Çevrim İçi
#           Kullanıcılar" sekmesi, aktif kullanıcılar olmasına rağmen boş
#           kalıyordu. Tazelik artık VERİTABANININ KENDİ SAATİYLE (yaş) hesaplanır
#           (DATEDIFF / SQLite julianday); istemci tarafı ODBC saat dilimi/an
#           yorumu denklemden çıkarılmıştır. Bu dosya taze/boşta/çevrim dışı
#           sınıflandırmasını ve kullanıcı başına en güncel satır seçimini gerçek
#           RSQLite üzerinde doğrular. SQL Server/ODBC, LLM, ağ GEREKMEZ.
# ==============================================================================

testthat::skip_if_not_installed("DBI")
testthat::skip_if_not_installed("RSQLite")

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn <<- function(...) invisible(NULL)
  }
  if (!exists("normalize_db_params", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_encoding.R"), encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_unicode_escape.R"), encoding = "UTF-8", local = globalenv())
  }
  if (!exists("ortak_sunum_durumu", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_permissions.R"), encoding = "UTF-8", local = globalenv())
  }
  if (!exists("ortak_db_canli_durumlar", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_db.R"), encoding = "UTF-8", local = globalenv())
    source(file.path(repo_root, "R", "helpers_ortak_oturum_db_davet.R"), encoding = "UTF-8", local = globalenv())
  }
})

# UTC duvar-saati metni üretir (heartbeat yazımıyla aynı biçim: .oo_db_now).
.ocd_utc <- function(offset_sn = 0) {
  format(Sys.time() + offset_sn, "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

.ocd_conn <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(conn, "CREATE TABLE MB_Kullanici_CanliDurum (CanliDurumID INTEGER PRIMARY KEY AUTOINCREMENT, KullaniciID INTEGER NOT NULL, OturumAnahtari TEXT NOT NULL, Sayfa TEXT, SonKalpAtisiZamani TEXT NOT NULL, Durum TEXT NOT NULL, SonGorulenOrtakOturumID INTEGER, OlusturmaZamani TEXT, UNIQUE (KullaniciID, OturumAnahtari))")
  conn
}

.ocd_ekle <- function(conn, uid, offset_sn, oturum_anahtari = NULL, gorulen = NA) {
  DBI::dbExecute(
    conn,
    "INSERT INTO MB_Kullanici_CanliDurum (KullaniciID, OturumAnahtari, Sayfa, SonKalpAtisiZamani, Durum, SonGorulenOrtakOturumID, OlusturmaZamani) VALUES (?,?,?,?,?,?,?)",
    params = list(uid, oturum_anahtari %||% paste0("tok_", uid, "_", offset_sn), "ortak_calismalar",
                  .ocd_utc(offset_sn), "Çevrimİçi", if (is.na(gorulen)) NA_integer_ else as.integer(gorulen), .ocd_utc(offset_sn))
  )
}

test_that("DB-saat yaşıyla taze kalp atışı Çevrimİçi, eski kalp atışı ÇevrimDışı sınıflanır", {
  conn <- .ocd_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  .ocd_ekle(conn, 1L, offset_sn = -10)     # 10 sn önce -> Çevrimİçi (<=120)
  .ocd_ekle(conn, 2L, offset_sn = -180)    # 3 dk önce -> Boşta (120<..<=300)
  .ocd_ekle(conn, 3L, offset_sn = -600)    # 10 dk önce -> ÇevrimDışı (>300)

  d <- ortak_db_canli_durumlar(conn = conn)
  expect_equal(nrow(d), 3L)
  al <- function(uid) as.character(d$CanliDurum[d$KullaniciID == uid][1])
  expect_identical(al(1L), "Çevrimİçi")
  expect_identical(al(2L), "Boşta")
  expect_identical(al(3L), "ÇevrimDışı")
})

test_that("kullanıcı başına EN GÜNCEL (en küçük yaş) satır seçilir", {
  conn <- .ocd_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # Aynı kullanıcı iki sekmeden: biri eski (çevrim dışı), biri taze (çevrim içi).
  .ocd_ekle(conn, 5L, offset_sn = -900, oturum_anahtari = "tok_eski", gorulen = NA)
  .ocd_ekle(conn, 5L, offset_sn = -5,   oturum_anahtari = "tok_taze", gorulen = 42L)

  d <- ortak_db_canli_durumlar(conn = conn)
  expect_equal(nrow(d), 1L)
  expect_identical(as.character(d$CanliDurum[1]), "Çevrimİçi")
  expect_equal(as.integer(d$SonGorulenOrtakOturumID[1]), 42L)
})

test_that("çıktı sözleşmesi korunur: KullaniciID, CanliDurum, SonGorulenOrtakOturumID", {
  conn <- .ocd_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  .ocd_ekle(conn, 7L, offset_sn = -3, gorulen = 9L)
  d <- ortak_db_canli_durumlar(conn = conn)
  expect_true(all(c("KullaniciID", "CanliDurum", "SonGorulenOrtakOturumID") %in% names(d)))
  # Dahili yaş sütunu tüketiciye sızdırılmamalı.
  expect_false("YasSaniye" %in% names(d))
})

test_that("gelecekte damgalı (saat kayması) kalp atışı TAZE sayılır, çevrim dışı DEĞİL", {
  conn <- .ocd_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # R yazımı ile DB "şimdi"si arasında küçük kayma: kalp atışı hafif gelecekte
  # (negatif yaş). Bu taze demektir; negatifi "en eski" sayan hata çevrim içi
  # kullanıcıyı sessizce çevrim dışı gösteriyordu.
  .ocd_ekle(conn, 11L, offset_sn = 30)  # 30 sn gelecekte -> negatif yaş
  d <- ortak_db_canli_durumlar(conn = conn)
  expect_equal(nrow(d), 1L)
  expect_identical(as.character(d$CanliDurum[1]), "Çevrimİçi")
})

test_that("boş tabloda güvenli boş çerçeve döner", {
  conn <- .ocd_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  d <- ortak_db_canli_durumlar(conn = conn)
  expect_true(is.data.frame(d))
  expect_equal(nrow(d), 0L)
})
