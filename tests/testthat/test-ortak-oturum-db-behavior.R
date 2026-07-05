# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-db-behavior.R
# Açıklama: Ortak Oturumlar DB katmanının davranış testleri. GERÇEK bir DBI
#           arka ucu (RSQLite, geçici dosya) üzerinde çalışır; gerçek SQL
#           Server/ODBC, LLM, tarayıcı veya ağ GEREKMEZ ve gizli değer
#           kullanılmaz.
#
# Kapsanan sözleşmeler:
#   - Tablo erişilebilirlik tespiti ve tablo yokken güvenli boş/NULL dönüş.
#   - Oturum oluşturma: Sahip otomatik Katıldı; Türkçe başlık gidiş-dönüşü.
#   - Mesaj yönlendirme: OdaMesajı LLM tetiklemez; İzleyici yazamaz/soramaz;
#     katılımcı olmayan kullanıcı okuyamaz (fail-closed).
#   - Davet akışı: metadata görünümü, kabul sonrası içerik erişimi, red durumu.
#   - Üretim kilidi: oda başına tek aktif üretim; yalnızca kilit sahibi bırakır.
#   - Kullanıcı bazlı arşiv kişiseldir; oda arşivi herkes içindir (Sahip).
#   - Sahiplik devri ve Sahip'in tek olduğu odada kural koruması.
#   - Ortak belge kaydı + kişisel kopya yetkisi + kopya durumu izleme.
#   - Bakım temizliği ve istatistik/tutanak yardımcıları.
# ==============================================================================

testthat::skip_if_not_installed("DBI")
testthat::skip_if_not_installed("RSQLite")

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  # Sessiz log stub'ı: strict suite stop_on_warning=TRUE olduğundan hata
  # yollarında warning() yerine sessiz log kullanılır.
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

  if (!exists("ortak_rol_yetkileri", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_permissions.R"),
           encoding = "UTF-8", local = globalenv())
  }

  for (dosya in c(
    "helpers_ortak_oturum_db.R",
    "helpers_ortak_oturum_db_katilim.R",
    "helpers_ortak_oturum_db_davet.R",
    "helpers_ortak_oturum_db_mesajlar.R",
    "helpers_ortak_oturum_files.R",
    "helpers_ortak_oturum_bakim.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# SQLite lehçesinde test şeması (üretim T-SQL DDL'i DEĞİL; bkz.
# docs/sql/2026-07-ortak-oturumlar.sql).
.oo_test_create_schema <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE MB_Users (
      UserID INTEGER PRIMARY KEY AUTOINCREMENT,
      KullaniciAdi TEXT, KaynakAdi TEXT, Email TEXT, Departman TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturumlar (
      OrtakOturumID INTEGER PRIMARY KEY AUTOINCREMENT,
      KaynakTuru TEXT NOT NULL, KaynakID INTEGER, Baslik TEXT,
      OlusturanKullaniciID INTEGER NOT NULL, OturumDurumu TEXT NOT NULL,
      PaylasimBaslangicTipi TEXT, SonEtkinlikZamani TEXT,
      OlusturmaZamani TEXT, GuncellemeZamani TEXT, MetaJson TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Katilimcilar (
      KatilimciID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakOturumID INTEGER NOT NULL, KullaniciID INTEGER NOT NULL,
      Rol TEXT NOT NULL, KatilimDurumu TEXT NOT NULL,
      KullaniciGorunumDurumu TEXT NOT NULL,
      DavetEdenKullaniciID INTEGER, DavetZamani TEXT, KatilmaZamani TEXT,
      SonGorulmeZamani TEXT, OlusturmaZamani TEXT,
      UNIQUE (OrtakOturumID, KullaniciID)
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Davetler (
      DavetID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakOturumID INTEGER NOT NULL, DavetEdilenKullaniciID INTEGER,
      DavetEdilenEposta TEXT, DavetEdenKullaniciID INTEGER NOT NULL,
      Rol TEXT NOT NULL, DavetYontemi TEXT NOT NULL, DavetDurumu TEXT NOT NULL,
      DavetMesaji TEXT, DavetTokenHash TEXT, OlusturmaZamani TEXT,
      SonGonderimZamani TEXT, KabulZamani TEXT, SonCevapZamani TEXT,
      GecerlilikBitisZamani TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_Kullanici_CanliDurum (
      CanliDurumID INTEGER PRIMARY KEY AUTOINCREMENT,
      KullaniciID INTEGER NOT NULL, OturumAnahtari TEXT NOT NULL,
      Sayfa TEXT, SonKalpAtisiZamani TEXT NOT NULL, Durum TEXT NOT NULL,
      SonGorulenOrtakOturumID INTEGER, OlusturmaZamani TEXT,
      UNIQUE (KullaniciID, OturumAnahtari)
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_Bildirimler (
      BildirimID INTEGER PRIMARY KEY AUTOINCREMENT,
      AliciKullaniciID INTEGER NOT NULL, GonderenKullaniciID INTEGER,
      BildirimTuru TEXT NOT NULL, Baslik TEXT NOT NULL, Mesaj TEXT,
      IlgiliOturumID INTEGER, OkunduMu INTEGER NOT NULL DEFAULT 0,
      Durum TEXT NOT NULL, OlusturmaZamani TEXT, OkunmaZamani TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Mesajlar (
      OrtakMesajID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakOturumID INTEGER NOT NULL, GonderenKullaniciID INTEGER,
      MesajTuru TEXT NOT NULL, Hedef TEXT NOT NULL, MesajMetni TEXT,
      BagliMesajID INTEGER, MesajSirasi INTEGER NOT NULL,
      LLMGonderildiMi INTEGER NOT NULL DEFAULT 0,
      OlusturmaZamani TEXT, MetaJson TEXT,
      UNIQUE (OrtakOturumID, MesajSirasi)
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_AktifUretimler (
      OrtakOturumID INTEGER PRIMARY KEY,
      BaslatanKullaniciID INTEGER NOT NULL, OrtakMesajID INTEGER,
      IstekID TEXT NOT NULL, KilitDurumu TEXT NOT NULL,
      BaslamaZamani TEXT, GuncellemeZamani TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakBilgeYolac_Oturumlar (
      OrtakBilgeYolacOturumID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakOturumID INTEGER NOT NULL UNIQUE, OrtakCalismaDizini TEXT,
      RuntimeDizini TEXT, Model TEXT, Karakter TEXT, ClaudeCliSessionID TEXT,
      OturumDurumu TEXT NOT NULL, OlusturmaZamani TEXT,
      SonCalistirmaZamani TEXT, MetaJson TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakBilgeYolac_Calistirmalar (
      OrtakCalistirmaID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakBilgeYolacOturumID INTEGER NOT NULL,
      KomutuVerenKullaniciID INTEGER NOT NULL, Komut TEXT NOT NULL,
      NihaiYanit TEXT, Durum TEXT NOT NULL, UretilenDosyalarJson TEXT,
      HamAkisJsonl TEXT, AracKullanimlariJson TEXT,
      CalistirmaSirasi INTEGER NOT NULL, ExitCode INTEGER, SureSaniye REAL,
      OlusturmaZamani TEXT,
      UNIQUE (OrtakBilgeYolacOturumID, CalistirmaSirasi)
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Dosyalar (
      OrtakDosyaID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakOturumID INTEGER NOT NULL, OrtakCalistirmaID INTEGER,
      UretenKullaniciID INTEGER, DosyaAdi TEXT NOT NULL,
      DosyaYolu TEXT NOT NULL, DosyaTuru TEXT, DosyaBoyutu REAL,
      DosyaHash TEXT, DosyaDurumu TEXT NOT NULL,
      DosyaSahipligi TEXT NOT NULL, OlusturmaZamani TEXT, MetaJson TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_DosyaKopyalari (
      DosyaKopyaID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakDosyaID INTEGER NOT NULL, KullaniciID INTEGER NOT NULL,
      KullaniciDosyaYolu TEXT, KopyalamaDurumu TEXT NOT NULL,
      KopyalamaZamani TEXT, HataMesaji TEXT,
      UNIQUE (OrtakDosyaID, KullaniciID)
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_Olaylar (
      OlayID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakOturumID INTEGER NOT NULL, OlayTuru TEXT NOT NULL,
      TetikleyenKullaniciID INTEGER, PayloadJson TEXT, OlusturmaZamani TEXT
    )")

  # Test kullanıcıları: Ayşe (Sahip), Barış (Katılımcı), Cem (dışarıdaki).
  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman)
                        VALUES ('ayse', 'Ayşe Yılmaz', 'ayse@example.com', 'Yazılım')")
  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman)
                        VALUES ('baris', 'Barış Demir', 'baris@example.com', 'Donanım')")
  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman)
                        VALUES ('cem', 'Cem Kaya', 'cem@example.com', 'Kalite')")

  invisible(conn)
}

.oo_test_conn <- function() {
  db_path <- tempfile(fileext = ".sqlite")
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  .oo_test_create_schema(conn)
  conn
}

test_that("tablolar yokken tüm okuma/yazma yolları güvenli boş/NULL/FALSE döner", {
  bos_conn <- DBI::dbConnect(RSQLite::SQLite(), tempfile(fileext = ".sqlite"))
  on.exit(DBI::dbDisconnect(bos_conn), add = TRUE)

  ortak_db_reset_availability_cache()
  expect_false(ortak_db_tablolar_hazir_mi(conn = bos_conn, force_refresh = TRUE))

  expect_null(ortak_db_oturum_olustur("NormalSohbet", "Deneme", 1L, conn = bos_conn))
  expect_null(ortak_db_oturum_getir(1L, conn = bos_conn))
  expect_equal(nrow(ortak_db_oturum_listesi(1L, conn = bos_conn)), 0L)
  expect_null(ortak_db_mesaj_ekle(1L, 1L, "OdaMesajı", "selam", conn = bos_conn))
  expect_equal(nrow(ortak_db_mesajlari_getir(1L, 1L, conn = bos_conn)), 0L)
  expect_false(ortak_db_uretim_kilidi_al(1L, 1L, "istek", conn = bos_conn))

  ortak_db_reset_availability_cache()
})

test_that("oturum oluşturma: Sahip otomatik Katıldı olur ve Türkçe başlık korunur", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  ortak_db_reset_availability_cache()
  expect_true(ortak_db_tablolar_hazir_mi(conn = conn, force_refresh = TRUE))

  baslik <- "Güvenlik İyileştirme Çalışması ğüşiöç"
  oturum_id <- ortak_db_oturum_olustur(
    "NormalSohbet", baslik, 1L,
    paylasim_tipi = "SadeceBundanSonrası", conn = conn
  )

  expect_true(is.integer(oturum_id) && oturum_id > 0L)

  bilgi <- ortak_db_oturum_getir(oturum_id, conn = conn)
  expect_identical(as.character(bilgi$Baslik[1]), baslik)
  expect_identical(as.character(bilgi$OturumDurumu[1]), "Aktif")

  sahip <- ortak_db_katilimci_getir(oturum_id, 1L, conn = conn)
  expect_identical(as.character(sahip$Rol[1]), "Sahip")
  expect_identical(as.character(sahip$KatilimDurumu[1]), "Katıldı")

  # Geçersiz kaynak türü ve geçersiz kullanıcı reddedilir.
  expect_null(ortak_db_oturum_olustur("shared_chat", "X", 1L, conn = conn))
  expect_null(ortak_db_oturum_olustur("NormalSohbet", "X", 0L, conn = conn))

  ortak_db_reset_availability_cache()
})

test_that("mesaj yönlendirme ve yetki: OdaMesajı LLM'siz kalır, İzleyici ve yabancı yazamaz", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Mesaj Testi", 1L, conn = conn)

  # Barış İzleyici olarak katılır; Cem hiç katılımcı değildir.
  ortak_db_katilimci_ekle(oturum_id, 2L, "İzleyici",
                          davet_eden_kullanici_id = 1L,
                          katilim_durumu = "Katıldı", conn = conn)

  # Sahip oda mesajı yazar: hedef Katılımcılar, LLM işareti 0.
  oda_id <- ortak_db_mesaj_ekle(oturum_id, 1L, "OdaMesajı", "Merhaba ekip", conn = conn)
  expect_true(is.integer(oda_id) && oda_id > 0L)

  satir <- DBI::dbGetQuery(conn,
    "SELECT MesajTuru, Hedef, LLMGonderildiMi FROM MB_OrtakOturum_Mesajlar WHERE OrtakMesajID = ?",
    params = list(oda_id))
  expect_identical(satir$Hedef[1], "Katılımcılar")
  expect_identical(as.integer(satir$LLMGonderildiMi[1]), 0L)

  # Yapay zekâ sorusu hedefi YapayZeka'dır.
  soru_id <- ortak_db_mesaj_ekle(oturum_id, 1L, "YapayZekaSorusu", "Özet çıkar", llm_gonderildi = TRUE, conn = conn)
  hedef <- DBI::dbGetQuery(conn,
    "SELECT Hedef FROM MB_OrtakOturum_Mesajlar WHERE OrtakMesajID = ?", params = list(soru_id))
  expect_identical(hedef$Hedef[1], "YapayZeka")

  # İzleyici yazamaz ve soramaz (fail-closed).
  expect_null(ortak_db_mesaj_ekle(oturum_id, 2L, "OdaMesajı", "yazamam", conn = conn))
  expect_null(ortak_db_mesaj_ekle(oturum_id, 2L, "YapayZekaSorusu", "soramam", conn = conn))

  # Katılımcı olmayan Cem yazamaz ve OKUYAMAZ.
  expect_null(ortak_db_mesaj_ekle(oturum_id, 3L, "OdaMesajı", "dışarıdan", conn = conn))
  expect_equal(nrow(ortak_db_mesajlari_getir(oturum_id, 3L, conn = conn)), 0L)

  # İzleyici okuyabilir; sıra numaraları artandır.
  okunan <- ortak_db_mesajlari_getir(oturum_id, 2L, conn = conn)
  expect_equal(nrow(okunan), 2L)
  expect_identical(as.integer(okunan$MesajSirasi), c(1L, 2L))

  # Geçersiz tür reddedilir.
  expect_null(ortak_db_mesaj_ekle(oturum_id, 1L, "chat_message", "x", conn = conn))

  # LLM bağlam üreticisi yalnızca YZ soru/yanıtını içerir; oda mesajı girmez.
  ortak_db_mesaj_ekle(oturum_id, NULL, "YapayZekaYanıtı", "Özet: tamam", bagli_mesaj_id = soru_id, conn = conn)
  gecmis <- ortak_yz_sohbet_gecmisi(ortak_db_mesajlari_getir(oturum_id, 1L, conn = conn))
  expect_length(gecmis, 2L)
  expect_identical(gecmis[[1]]$role, "user")
  expect_identical(gecmis[[2]]$role, "assistant")
})

test_that("davet akışı: kabul öncesi içerik kapalı, kabul sonrası açık, red kalıcı", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Davet Testi", 1L, conn = conn)
  ortak_db_mesaj_ekle(oturum_id, 1L, "OdaMesajı", "gizli içerik", conn = conn)

  davet_id <- ortak_db_davet_olustur(
    oturum_id = oturum_id,
    davet_eden_kullanici_id = 1L,
    davet_edilen_kullanici_id = 2L,
    rol = "Katılımcı",
    davet_yontemi = "Mergenİçi",
    conn = conn
  )
  expect_true(is.integer(davet_id) && davet_id > 0L)

  # Davet edilen kullanıcı davet metadata'sını görür ama İÇERİĞİ göremez.
  davetler <- ortak_db_davetlerim(2L, conn = conn)
  expect_equal(nrow(davetler), 1L)
  expect_identical(as.character(davetler$DavetDurumu[1]), "Bekliyor")
  expect_equal(nrow(ortak_db_mesajlari_getir(oturum_id, 2L, conn = conn)), 0L)

  # Davet yalnızca sahibi tarafından yanıtlanabilir.
  expect_false(ortak_db_davet_yanitla(davet_id, 3L, kabul = TRUE, conn = conn))

  # Kabul: katılım Katıldı olur ve içerik erişimi açılır.
  expect_true(ortak_db_davet_yanitla(davet_id, 2L, kabul = TRUE, conn = conn))
  expect_identical(
    as.character(ortak_db_katilimci_getir(oturum_id, 2L, conn = conn)$KatilimDurumu[1]),
    "Katıldı"
  )
  expect_equal(nrow(ortak_db_mesajlari_getir(oturum_id, 2L, conn = conn)), 1L)

  # Aynı davet ikinci kez yanıtlanamaz (Bekliyor değil).
  expect_false(ortak_db_davet_yanitla(davet_id, 2L, kabul = FALSE, conn = conn))

  # Yetkisiz davet: Katılımcı rolündeki Barış davet edemez (davet_et yetkisi yok).
  expect_null(ortak_db_davet_olustur(oturum_id, 2L, 3L, conn = conn))

  # Red akışı: Cem'i davet et, reddetsin; içerik erişimi kapalı kalır.
  davet_cem <- ortak_db_davet_olustur(oturum_id, 1L, 3L, conn = conn)
  expect_true(ortak_db_davet_yanitla(davet_cem, 3L, kabul = FALSE, conn = conn))
  expect_identical(
    as.character(ortak_db_katilimci_getir(oturum_id, 3L, conn = conn)$KatilimDurumu[1]),
    "Reddetti"
  )
  expect_equal(nrow(ortak_db_mesajlari_getir(oturum_id, 3L, conn = conn)), 0L)
})

test_that("üretim kilidi oda başına tektir ve yalnızca sahibi bırakır", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Kilit Testi", 1L, conn = conn)

  expect_false(ortak_db_aktif_uretim_var_mi(oturum_id, conn = conn))
  expect_true(ortak_db_uretim_kilidi_al(oturum_id, 1L, "istek_a", conn = conn))
  expect_true(ortak_db_aktif_uretim_var_mi(oturum_id, conn = conn))

  # İkinci istek kilidi ALAMAZ (tek aktif üretim kuralı).
  expect_false(ortak_db_uretim_kilidi_al(oturum_id, 2L, "istek_b", conn = conn))

  # Yanlış istek kimliği kilidi bırakamaz.
  expect_false(ortak_db_uretim_kilidi_birak(oturum_id, "istek_b", conn = conn))
  expect_true(ortak_db_aktif_uretim_var_mi(oturum_id, conn = conn))

  # Kilit sahibi bırakır; ardından yeni istek kilit alabilir.
  expect_true(ortak_db_uretim_kilidi_birak(oturum_id, "istek_a", "Tamamlandı", conn = conn))
  expect_false(ortak_db_aktif_uretim_var_mi(oturum_id, conn = conn))
  expect_true(ortak_db_uretim_kilidi_al(oturum_id, 2L, "istek_c", conn = conn))
})

test_that("kullanıcı arşivi kişiseldir; oda arşivi yalnızca Sahip ile herkese uygulanır", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Arşiv Testi", 1L, conn = conn)
  ortak_db_katilimci_ekle(oturum_id, 2L, "Katılımcı",
                          davet_eden_kullanici_id = 1L,
                          katilim_durumu = "Katıldı", conn = conn)

  # Barış kendi görünümünde arşivler: kendi listesinden düşer, Ayşe'ninkinden düşmez.
  expect_true(ortak_db_kullanici_gorunum_guncelle(oturum_id, 2L, "KullanıcıArşivledi", conn = conn))
  expect_equal(nrow(ortak_db_oturum_listesi(2L, conn = conn)), 0L)
  expect_equal(nrow(ortak_db_oturum_listesi(1L, conn = conn)), 1L)
  expect_equal(nrow(ortak_db_oturum_listesi(2L, arsiv_gorunumu = TRUE, conn = conn)), 1L)

  # Geri yükleme.
  expect_true(ortak_db_kullanici_gorunum_guncelle(oturum_id, 2L, "Görünüyor", conn = conn))
  expect_equal(nrow(ortak_db_oturum_listesi(2L, conn = conn)), 1L)

  # Oda düzeyi arşiv: Katılımcı Barış YAPAMAZ (fail-closed), Sahip yapar.
  expect_false(ortak_db_oturum_durum_guncelle(oturum_id, 2L, "Arşivlendi", conn = conn))
  expect_true(ortak_db_oturum_durum_guncelle(oturum_id, 1L, "Arşivlendi", conn = conn))

  # Oda arşivi HERKESİN normal listesinden düşürür.
  expect_equal(nrow(ortak_db_oturum_listesi(1L, conn = conn)), 0L)
  expect_equal(nrow(ortak_db_oturum_listesi(2L, conn = conn)), 0L)
  expect_equal(nrow(ortak_db_oturum_listesi(2L, arsiv_gorunumu = TRUE, conn = conn)), 1L)
})

test_that("sahiplik devri: yalnızca Sahip devreder ve roller tutarlı değişir", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Sahiplik Testi", 1L, conn = conn)
  ortak_db_katilimci_ekle(oturum_id, 2L, "Katılımcı",
                          davet_eden_kullanici_id = 1L,
                          katilim_durumu = "Katıldı", conn = conn)

  # Sahip olmayan devredemez; davet aşamasındaki kullanıcıya devredilemez.
  expect_false(ortak_db_sahiplik_devret(oturum_id, 2L, 1L, conn = conn))
  ortak_db_katilimci_ekle(oturum_id, 3L, "Katılımcı",
                          davet_eden_kullanici_id = 1L,
                          katilim_durumu = "DavetEdildi", conn = conn)
  expect_false(ortak_db_sahiplik_devret(oturum_id, 1L, 3L, conn = conn))

  # Geçerli devir: Barış Sahip olur, Ayşe OturumYöneticisi'ne düşer.
  expect_true(ortak_db_sahiplik_devret(oturum_id, 1L, 2L, conn = conn))
  expect_identical(as.character(ortak_db_katilimci_getir(oturum_id, 2L, conn = conn)$Rol[1]), "Sahip")
  expect_identical(
    as.character(ortak_db_katilimci_getir(oturum_id, 1L, conn = conn)$Rol[1]),
    "OturumYöneticisi"
  )

  # Rol güncelleme yolu Sahip'i hedefleyemez ve Sahip rolü atayamaz.
  expect_false(ortak_db_katilimci_rol_guncelle(oturum_id, 2L, 1L, "Sahip", conn = conn))
  expect_false(ortak_db_katilimci_rol_guncelle(oturum_id, 1L, 2L, "Katılımcı", conn = conn))
})

test_that("ortak belge yaşam döngüsü: oda belgesi önce, kişisel kopya açık eylemle", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # Dosya kökleri geçici dizine sandbox'lanır.
  eski_root <- getOption("mergen.files_root")
  test_root <- file.path(tempdir(), sprintf("oo_files_%d", sample.int(99999L, 1L)))
  dir.create(test_root, recursive = TRUE, showWarnings = FALSE)
  options(mergen.files_root = test_root)
  on.exit(options(mergen.files_root = eski_root), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("BilgeYolaç", "Belge Testi", 1L, conn = conn)
  ortak_db_katilimci_ekle(oturum_id, 2L, "Katılımcı",
                          davet_eden_kullanici_id = 1L,
                          katilim_durumu = "Katıldı", conn = conn)

  # Üretilen dosya ortak belge olarak kaydedilir (fiziksel kopya + metadata).
  kaynak <- file.path(tempdir(), "rapor_özeti_ğüşiöç.txt")
  writeLines("Türkçe içerik: ğüşiöç İIıi", kaynak, useBytes = FALSE)

  dosya_id <- ortak_db_dosya_kaydet(
    oturum_id, kaynak,
    dosya_adi = "rapor_özeti_ğüşiöç.txt",
    ureten_kullanici_id = 1L, conn = conn
  )
  expect_true(is.integer(dosya_id) && dosya_id > 0L)

  kok <- ortak_oturum_dosya_koku(oturum_id)
  expect_true(dir.exists(kok))
  expect_length(list.files(kok), 1L)

  # Belge listesi: içerik erişimli katılımcı görür, yabancı görmez.
  belgeler <- ortak_db_dosyalar(oturum_id, 2L, conn = conn)
  expect_equal(nrow(belgeler), 1L)
  expect_true(is.na(belgeler$KopyalamaDurumu[1]) || !nzchar(belgeler$KopyalamaDurumu[1]))
  expect_equal(nrow(ortak_db_dosyalar(oturum_id, 3L, conn = conn)), 0L)

  # Yabancı kullanıcı kopyalayamaz (fail-closed).
  yabanci <- ortak_dosya_kisisel_kopyala(dosya_id, 3L, conn = conn)
  expect_false(yabanci$basarili)

  # Katılımcı açık eylemle kopyalar; durum Kopyalandı olur. Dosya Yönetimi
  # kayıt yolu test için stub'lanır (global env; test sonunda geri alınır).
  onceki_kayit_fn <- if (exists("global_register_file", inherits = TRUE)) {
    get("global_register_file", inherits = TRUE)
  } else {
    NULL
  }
  assign("global_register_file", function(src_path, filename, user_id = NULL, ...) {
    hedef <- file.path(test_root, sprintf("user_%s_%s", user_id, filename))
    file.copy(src_path, hedef)
    list(stored_path = hedef)
  }, envir = globalenv())
  on.exit({
    if (is.null(onceki_kayit_fn)) {
      rm("global_register_file", envir = globalenv())
    } else {
      assign("global_register_file", onceki_kayit_fn, envir = globalenv())
    }
  }, add = TRUE)

  sonuc <- ortak_dosya_kisisel_kopyala(dosya_id, 2L, conn = conn)
  expect_true(sonuc$basarili)
  expect_identical(sonuc$durum, "Kopyalandı")

  belgeler2 <- ortak_db_dosyalar(oturum_id, 2L, conn = conn)
  expect_identical(as.character(belgeler2$KopyalamaDurumu[1]), "Kopyalandı")

  # İkinci kopyalama yeni fiziksel kopya üretmez (idempotent).
  tekrar <- ortak_dosya_kisisel_kopyala(dosya_id, 2L, conn = conn)
  expect_true(tekrar$basarili)
  expect_true(grepl("zaten", tekrar$mesaj, fixed = TRUE))
})

test_that("liste ayrımı: kaynak türü filtreleri kişisel/ortak karışmasını önler", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  sohbet_id <- ortak_db_oturum_olustur("NormalSohbet", "Sohbet Odası", 1L, conn = conn)
  by_id <- ortak_db_oturum_olustur("BilgeYolaç", "Ajan Odası", 1L, conn = conn)

  hepsi <- ortak_db_oturum_listesi(1L, conn = conn)
  expect_equal(nrow(hepsi), 2L)

  sadece_sohbet <- ortak_db_oturum_listesi(1L, kaynak_turu = "NormalSohbet", conn = conn)
  expect_equal(nrow(sadece_sohbet), 1L)
  expect_identical(as.integer(sadece_sohbet$OrtakOturumID[1]), sohbet_id)

  sadece_by <- ortak_db_oturum_listesi(1L, kaynak_turu = "BilgeYolaç", conn = conn)
  expect_equal(nrow(sadece_by), 1L)
  expect_identical(as.integer(sadece_by$OrtakOturumID[1]), by_id)

  # Katılımcı olmayan kullanıcı hiçbir ortak oturum görmez.
  expect_equal(nrow(ortak_db_oturum_listesi(3L, conn = conn)), 0L)
})

test_that("canlı durum: kalp atışı upsert eder ve sınıflandırma Türkçe döner", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  expect_true(ortak_db_kalp_atisi(1L, "oturum_a", sayfa = "ortak_calismalar", conn = conn))
  expect_true(ortak_db_kalp_atisi(1L, "oturum_a", sayfa = "chat", conn = conn))

  satirlar <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM MB_Kullanici_CanliDurum")
  expect_equal(as.integer(satirlar$n[1]), 1L)

  durumlar <- ortak_db_canli_durumlar(conn = conn)
  expect_equal(nrow(durumlar), 1L)
  expect_identical(as.character(durumlar$CanliDurum[1]), "Çevrimİçi")

  # Geçersiz kimlik yazmaz (SSO placeholder 0 koruması).
  expect_false(ortak_db_kalp_atisi(0L, "oturum_b", conn = conn))
})

test_that("bakım temizliği: eski davet/bildirim/kalp atışı ve kayıp dosya işaretlenir", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Bakım Testi", 1L, conn = conn)
  davet_id <- ortak_db_davet_olustur(oturum_id, 1L, 2L, conn = conn)

  eski_zaman <- format(Sys.time() - 90 * 86400, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  DBI::dbExecute(conn, "UPDATE MB_OrtakOturum_Davetler SET OlusturmaZamani = ?",
                 params = list(eski_zaman))
  DBI::dbExecute(conn,
    "INSERT INTO MB_Bildirimler (AliciKullaniciID, BildirimTuru, Baslik, Durum, OlusturmaZamani, OkunduMu)
     VALUES (2, 'OrtakOturumDavet', 'Eski çağrı', 'Bekliyor', ?, 0)",
    params = list(eski_zaman))
  DBI::dbExecute(conn,
    "INSERT INTO MB_Kullanici_CanliDurum (KullaniciID, OturumAnahtari, SonKalpAtisiZamani, Durum)
     VALUES (1, 'eski', ?, 'Çevrimİçi')",
    params = list(eski_zaman))
  DBI::dbExecute(conn,
    "INSERT INTO MB_OrtakOturum_Dosyalar
     (OrtakOturumID, DosyaAdi, DosyaYolu, DosyaDurumu, DosyaSahipligi, OlusturmaZamani)
     VALUES (?, 'kayip.txt', '/olmayan/yol/kayip.txt', 'Üretildi', 'OrtakOturumDosyası', ?)",
    params = list(oturum_id, eski_zaman))

  sonuc <- ortak_db_bakim_temizlik(conn = conn)

  expect_gte(sonuc$davet, 1L)
  expect_gte(sonuc$bildirim, 1L)
  expect_gte(sonuc$kalp_atisi, 1L)
  expect_gte(sonuc$dosya, 1L)

  davet_durum <- DBI::dbGetQuery(conn,
    "SELECT DavetDurumu FROM MB_OrtakOturum_Davetler WHERE DavetID = ?",
    params = list(davet_id))
  expect_identical(davet_durum$DavetDurumu[1], "SüresiDoldu")
})

test_that("istatistik ve tutanak yardımcıları güvenli özet üretir", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "İstatistik Testi", 1L, conn = conn)
  ortak_db_mesaj_ekle(oturum_id, 1L, "YapayZekaSorusu", "Soru?", conn = conn)
  ortak_db_mesaj_ekle(oturum_id, NULL, "YapayZekaYanıtı", "Yanıt.", conn = conn)

  davet_id <- ortak_db_davet_olustur(oturum_id, 1L, 2L, conn = conn)
  ortak_db_davet_yanitla(davet_id, 2L, kabul = TRUE, conn = conn)

  ist <- ortak_db_istatistikler(conn = conn)
  expect_identical(ist$toplam_oda, 1L)
  expect_identical(ist$aktif_oda, 1L)
  expect_identical(ist$yz_soru, 1L)
  expect_identical(ist$davet_kabul, 1L)
  expect_identical(ist$davet_kabul_orani, 1)

  # Tutanak: mesajlar ve etiketler metne girer; dosyaya BOM'lu yazılır.
  metin <- ortak_tutanak_metni(
    ortak_db_oturum_getir(oturum_id, conn = conn),
    ortak_db_mesajlari_getir(oturum_id, 1L, conn = conn),
    ortak_db_dosyalar(oturum_id, 1L, conn = conn)
  )
  expect_true(grepl("İstatistik Testi", metin, fixed = TRUE))
  expect_true(grepl("Yapay Zekâ Yanıtı", metin, fixed = TRUE))
  expect_true(grepl("Soru?", metin, fixed = TRUE))

  hedef <- tempfile(fileext = ".txt")
  ortak_tutanak_dosyaya_yaz(metin, hedef)
  baytlar <- readBin(hedef, what = "raw", n = 3L)
  expect_identical(baytlar, as.raw(c(0xEF, 0xBB, 0xBF)))
})

test_that("ortak Bilge Yolaç oturum/çalıştırma kaydı sıra ve Türkçe metni korur", {
  conn <- .oo_test_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortak_db_oturum_olustur("BilgeYolaç", "Ajan Odası", 1L, conn = conn)
  by_id <- ortak_db_by_oturum_olustur(oturum_id, calisma_dizini = "/tmp/ortak", conn = conn)
  expect_true(is.integer(by_id) && by_id > 0L)

  c1 <- ortak_db_by_calistirma_kaydet(by_id, 1L, "Dosyaları özetle", "Özet hazır ğüşiöç", conn = conn)
  c2 <- ortak_db_by_calistirma_kaydet(by_id, 1L, "Rapor üret", "Rapor tamam", conn = conn)
  expect_true(c1 > 0L && c2 > 0L)

  calistirmalar <- ortak_db_by_calistirmalar(by_id, conn = conn)
  expect_equal(nrow(calistirmalar), 2L)
  expect_identical(as.integer(calistirmalar$CalistirmaSirasi), c(1L, 2L))
  expect_identical(as.character(calistirmalar$NihaiYanit[1]), "Özet hazır ğüşiöç")

  kayit <- ortak_db_by_oturum_getir(oturum_id, conn = conn)
  expect_false(is.na(kayit$SonCalistirmaZamani[1]))
})
