# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-kisisel-kopya-behavior.R
# Açıklama: "Kendi Dosyalarıma Kaydet" akışının GERÇEK dosya deposu zinciriyle
#           (global_register_file / mergen_register_uploaded_file — stub YOK)
#           davranış testleri. Kök neden regresyonu: MCP tabanı altındaki
#           ortak yüklemeler için kopyasız takma ad (alias) üretilmesi ve kopya
#           durumu yazımındaki hatanın tüm işlemi "başarısız" göstermesi.
#           Gerçek RSQLite + geçici dosya kökleri; SQL Server/LLM/ağ GEREKMEZ.
# ==============================================================================

testthat::skip_if_not_installed("DBI")
testthat::skip_if_not_installed("RSQLite")
testthat::skip_if_not_installed("fs")

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn <<- function(...) invisible(NULL)
  }
  if (!exists("normalize_db_params", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_unicode_escape.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("validate_uploaded_file", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "utils_upload_validator.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("ortak_rol_yetkileri", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_permissions.R"),
           encoding = "UTF-8", local = globalenv())
  }

  # GERÇEK dosya deposu zinciri: helper_load_file_store.R test köklerini tempdir
  # altına zorlar ve global_register_file / mergen_user_upload_dir'i yükler.
  # (testthat helper dosyaları otomatik yüklenir; burada garanti altına alınır.)
  if (!exists("global_register_file", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "tests", "testthat", "helper_load_file_store.R"),
           encoding = "UTF-8", local = globalenv())
  }

  for (dosya in c(
    "helpers_ortak_oturum_db.R",
    "helpers_ortak_oturum_db_katilim.R",
    "helpers_ortak_oturum_db_mesajlar.R",
    "helpers_ortak_oturum_files.R",
    "helpers_ortak_oturum_belgeler.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# Bu testlerin dokunduğu tablolarla sınırlı SQLite şeması.
.oo_kk_schema <- function(conn, kopya_tablosu = TRUE) {
  DBI::dbExecute(conn, "
    CREATE TABLE MB_Users (
      UserID INTEGER PRIMARY KEY, KullaniciAdi TEXT, KaynakAdi TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturumlar (
      OrtakOturumID INTEGER PRIMARY KEY, KaynakTuru TEXT, Baslik TEXT,
      OlusturanKullaniciID INTEGER, OturumDurumu TEXT, SonEtkinlikZamani TEXT,
      GuncellemeZamani TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Katilimcilar (
      KatilimciID INTEGER PRIMARY KEY, OrtakOturumID INTEGER, KullaniciID INTEGER,
      Rol TEXT, KatilimDurumu TEXT, KullaniciGorunumDurumu TEXT,
      DavetEdenKullaniciID INTEGER, DavetZamani TEXT, KatilmaZamani TEXT,
      SonGorulmeZamani TEXT, OlusturmaZamani TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Mesajlar (
      OrtakMesajID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER,
      GonderenKullaniciID INTEGER, MesajTuru TEXT, Hedef TEXT, MesajMetni TEXT,
      BagliMesajID INTEGER, MesajSirasi INTEGER, LLMGonderildiMi INTEGER DEFAULT 0,
      OlusturmaZamani TEXT, MetaJson TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Olaylar (
      OlayID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER,
      OlayTuru TEXT, TetikleyenKullaniciID INTEGER, OlusturmaZamani TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Dosyalar (
      OrtakDosyaID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER,
      OrtakCalistirmaID INTEGER, UretenKullaniciID INTEGER, DosyaAdi TEXT,
      DosyaYolu TEXT, DosyaTuru TEXT, DosyaBoyutu REAL, DosyaDurumu TEXT,
      DosyaSahipligi TEXT, OlusturmaZamani TEXT, MetaJson TEXT
    )")
  if (isTRUE(kopya_tablosu)) {
    DBI::dbExecute(conn, "
      CREATE TABLE MB_OrtakOturum_DosyaKopyalari (
        KopyaID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakDosyaID INTEGER,
        KullaniciID INTEGER, KullaniciDosyaYolu TEXT, KopyalamaDurumu TEXT,
        KopyalamaZamani TEXT, HataMesaji TEXT
      )")
  }
  invisible(conn)
}

.oo_kk_fixture <- function(kopya_tablosu = TRUE) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), tempfile(fileext = ".sqlite"))
  .oo_kk_schema(conn, kopya_tablosu = kopya_tablosu)
  DBI::dbExecute(conn, "INSERT INTO MB_Users VALUES (2, 'kul2', 'Kullanıcı İki')")
  DBI::dbExecute(conn, "INSERT INTO MB_OrtakOturumlar (OrtakOturumID, KaynakTuru, Baslik, OlusturanKullaniciID, OturumDurumu) VALUES (1, 'NormalSohbet', 'Oda', 2, 'Aktif')")
  DBI::dbExecute(conn, "INSERT INTO MB_OrtakOturum_Katilimcilar (KatilimciID, OrtakOturumID, KullaniciID, Rol, KatilimDurumu, KullaniciGorunumDurumu) VALUES (1, 1, 2, 'Sahip', 'Katıldı', 'Aktif')")
  conn
}

test_that("katılımcı yüklemesi kişisel klasöre GERÇEK kopya üretir (takma ad değil)", {
  conn <- .oo_kk_fixture()
  withr::defer(DBI::dbDisconnect(conn))

  kaynak <- tempfile(fileext = ".txt")
  writeLines(enc2utf8("Türkçe içerik: ğüşiöç"), kaynak, useBytes = TRUE)

  y <- ortak_db_belge_yukle(1L, 2L, kaynak, dosya_adi = "rapor_özet.txt", conn = conn)
  expect_true(y$basarili)

  sonuc <- ortak_dosya_kisisel_kopyala(y$dosya_id, 2L, conn = conn)
  expect_true(sonuc$basarili)
  expect_identical(sonuc$durum, "Kopyalandı")
  expect_true(file.exists(sonuc$hedef_yol))

  # Kök neden regresyonu: hedef, ortak belgeden FARKLI fiziksel bir dosyadır
  # ve kullanıcının kendi kovasındadır (user_2). Ortak belge silinse bile
  # kişisel kopya yaşamaya devam eder.
  ortak_yol <- DBI::dbGetQuery(conn, "SELECT DosyaYolu FROM MB_OrtakOturum_Dosyalar WHERE OrtakDosyaID = ?",
                               params = list(y$dosya_id))$DosyaYolu[1]
  expect_false(identical(
    normalizePath(sonuc$hedef_yol, winslash = "/"),
    normalizePath(ortak_yol, winslash = "/")
  ))
  expect_true(grepl("/user_2/", gsub("\\\\", "/", sonuc$hedef_yol), fixed = TRUE))

  # Görünen ad korunur; içerik bayt-eş kopyadır.
  expect_identical(basename(sonuc$hedef_yol), "rapor_özet.txt")
  expect_identical(readLines(sonuc$hedef_yol, encoding = "UTF-8")[1], "Türkçe içerik: ğüşiöç")

  sil <- ortak_db_belge_sil(y$dosya_id, 2L, conn = conn)
  expect_true(sil$basarili)
  expect_true(file.exists(sonuc$hedef_yol))

  # Kopya durumu yazıldı: ikinci istek yeniden kopyalamaz.
  y2 <- ortak_db_belge_yukle(1L, 2L, kaynak, dosya_adi = "ikinci.txt", conn = conn)
  ilk <- ortak_dosya_kisisel_kopyala(y2$dosya_id, 2L, conn = conn)
  tekrar <- ortak_dosya_kisisel_kopyala(y2$dosya_id, 2L, conn = conn)
  expect_true(tekrar$basarili)
  expect_true(grepl("zaten", tekrar$mesaj, fixed = TRUE))
})

test_that("üretilen (dosya kökü) belge de kişisel klasöre kopyalanır", {
  conn <- .oo_kk_fixture()
  withr::defer(DBI::dbDisconnect(conn))

  kaynak <- tempfile(fileext = ".md")
  writeLines("# Özet raporu", kaynak)

  dosya_id <- ortak_db_dosya_kaydet(
    1L, kaynak, dosya_adi = "claude_raporu.md",
    ureten_kullanici_id = 2L, conn = conn
  )
  expect_false(is.null(dosya_id))

  sonuc <- ortak_dosya_kisisel_kopyala(dosya_id, 2L, conn = conn)
  expect_true(sonuc$basarili)
  expect_true(file.exists(sonuc$hedef_yol))
  expect_true(grepl("/user_2/", gsub("\\\\", "/", sonuc$hedef_yol), fixed = TRUE))
})

test_that("kopya durumu tablosu yoksa kopya yine BAŞARILI raporlanır (eski şema toleransı)", {
  conn <- .oo_kk_fixture(kopya_tablosu = FALSE)
  withr::defer(DBI::dbDisconnect(conn))

  kaynak <- tempfile(fileext = ".txt")
  writeLines("içerik", kaynak)

  y <- ortak_db_belge_yukle(1L, 2L, kaynak, dosya_adi = "tolerans.txt", conn = conn)
  expect_true(y$basarili)

  # Kök neden regresyonu: durum satırı yazılamasa da fiziksel kopya + indeks
  # başarılıysa kullanıcıya "Belge kopyalanırken hata oluştu" DENMEZ.
  sonuc <- ortak_dosya_kisisel_kopyala(y$dosya_id, 2L, conn = conn)
  expect_true(sonuc$basarili)
  expect_true(file.exists(sonuc$hedef_yol))
  expect_true(grepl("kopyalandı", sonuc$mesaj, fixed = TRUE))
})

test_that("aynı ada sahip ikinci belge kişisel klasörde deterministik ad alır", {
  conn <- .oo_kk_fixture()
  withr::defer(DBI::dbDisconnect(conn))

  k1 <- tempfile(fileext = ".txt"); writeLines("bir", k1)
  k2 <- tempfile(fileext = ".txt"); writeLines("iki", k2)

  y1 <- ortak_db_belge_yukle(1L, 2L, k1, dosya_adi = "ayni_ad.txt", conn = conn)
  y2 <- ortak_db_belge_yukle(1L, 2L, k2, dosya_adi = "ayni_ad.txt", conn = conn)

  s1 <- ortak_dosya_kisisel_kopyala(y1$dosya_id, 2L, conn = conn)
  s2 <- ortak_dosya_kisisel_kopyala(y2$dosya_id, 2L, conn = conn)

  expect_true(s1$basarili)
  expect_true(s2$basarili)
  expect_false(identical(s1$hedef_yol, s2$hedef_yol))
  expect_true(file.exists(s1$hedef_yol))
  expect_true(file.exists(s2$hedef_yol))
  expect_identical(readLines(s1$hedef_yol)[1], "bir")
  expect_identical(readLines(s2$hedef_yol)[1], "iki")
})

test_that("yetkisiz katılımcı ve içerik erişimsiz kullanıcı kopyalayamaz", {
  conn <- .oo_kk_fixture()
  withr::defer(DBI::dbDisconnect(conn))

  DBI::dbExecute(conn, "INSERT INTO MB_Users VALUES (3, 'kul3', 'Kullanıcı Üç')")

  kaynak <- tempfile(fileext = ".txt"); writeLines("gizli", kaynak)
  y <- ortak_db_belge_yukle(1L, 2L, kaynak, dosya_adi = "gizli.txt", conn = conn)

  # Katılımcı olmayan kullanıcı: fail-closed.
  yabanci <- ortak_dosya_kisisel_kopyala(y$dosya_id, 3L, conn = conn)
  expect_false(yabanci$basarili)
  expect_identical(yabanci$durum, "Reddetti")
})