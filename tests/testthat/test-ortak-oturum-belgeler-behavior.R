# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-belgeler-behavior.R
# Açıklama: Ortak Oturum PAYLAŞILAN belge girdilerinin davranış testleri.
#           GERÇEK bir DBI arka ucu (RSQLite, geçici dosya) üzerinde çalışır;
#           gerçek SQL Server/ODBC, LLM, tarayıcı veya ağ GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Yükleme yetkisi fail-closed: İzleyici ve katılımcı olmayan yükleyemez.
#   - Tekil oturumla AYNI doğrulama: uzantı beyaz listesi, boyut sınırı,
#     traversal dosya adı reddi; Türkçe dosya adı gidiş-dönüşü.
#   - Oturum başına deterministik yükleme klasörü (ortak_oturum_<id>) ve
#     oturumlar arası fiziksel izolasyon.
#   - Bağlam seçimi paylaşılan durumdur; yalnızca SEÇİLİ belgeler bağlam
#     metnine girer; seçim değişikliği yetki gerektirir.
#   - Kaldırma: soft delete + kök-içi güvenli fiziksel silme; liste dışı kalır.
#   - Yüklenen belge "Kendi Dosyalarıma Kaydet" ile kopyalanabilir (yükleme
#     kökü meşru kaynak köküdür).
#   - Sohbeti kalıcı temizleme: yalnızca katilimci_yonet yetkisi; üretim
#     sürerken reddedilir; mesajlar + kuyruk temizlenir, sistem notu kalır.
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

  for (dosya in c(
    "helpers_ortak_oturum_sunum.R",
    "helpers_ortak_oturum_db.R",
    "helpers_ortak_oturum_db_katilim.R",
    "helpers_ortak_oturum_db_davet.R",
    "helpers_ortak_oturum_db_mesajlar.R",
    "helpers_ortak_oturum_db_kuyruk.R",
    "helpers_ortak_oturum_files.R",
    "helpers_ortak_oturum_belgeler.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# SQLite lehçesinde test şeması (üretim T-SQL DDL'i DEĞİL; MetaJson dahil
# yalnızca bu testlerin dokunduğu tablolar).
.oo_belge_test_schema <- function(conn) {
  DBI::dbExecute(conn, "
    CREATE TABLE MB_Users (
      UserID INTEGER PRIMARY KEY AUTOINCREMENT,
      KullaniciAdi TEXT, KaynakAdi TEXT, Email TEXT, Departman TEXT, Sicil TEXT
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
    CREATE TABLE MB_OrtakOturum_YapayZekaKuyrugu (
      KuyrukID INTEGER PRIMARY KEY AUTOINCREMENT,
      OrtakOturumID INTEGER NOT NULL, OrtakMesajID INTEGER NOT NULL,
      SiraNo INTEGER NOT NULL, Durum TEXT NOT NULL,
      OlusturmaZamani TEXT, BaslamaZamani TEXT, BitisZamani TEXT
    )")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_OrtakOturum_AktifUretimler (
      OrtakOturumID INTEGER PRIMARY KEY,
      BaslatanKullaniciID INTEGER NOT NULL, OrtakMesajID INTEGER,
      IstekID TEXT NOT NULL, KilitDurumu TEXT NOT NULL,
      BaslamaZamani TEXT, GuncellemeZamani TEXT, KismiYanit TEXT
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

  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman)
                        VALUES ('ayse', 'Ayşe Yılmaz', 'ayse@example.com', 'Yazılım')")
  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman)
                        VALUES ('baris', 'Barış Demir', 'baris@example.com', 'Donanım')")
  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman)
                        VALUES ('cem', 'Cem Kaya', 'cem@example.com', 'Kalite')")

  invisible(conn)
}

# Test ortamı: bağlantı + oturum + deterministik geçici yükleme tabanı.
.oo_belge_test_ortam <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), tempfile(fileext = ".sqlite"))
  .oo_belge_test_schema(conn)

  taban <- file.path(tempdir(), sprintf("oo_belge_taban_%s", as.integer(runif(1, 1, 1e9))))
  dir.create(taban, showWarnings = FALSE, recursive = TRUE)

  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Belge Girdisi Testi", 1L, conn = conn)
  # Barış Katılımcı (yükleyebilir), Cem İzleyici (yükleyemez); 3. kullanıcı dışarıda değil.
  ortak_db_katilimci_ekle(oturum_id, 2L, "Katılımcı",
                          davet_eden_kullanici_id = 1L,
                          katilim_durumu = "Katıldı", conn = conn)
  ortak_db_katilimci_ekle(oturum_id, 3L, "İzleyici",
                          davet_eden_kullanici_id = 1L,
                          katilim_durumu = "Katıldı", conn = conn)

  list(conn = conn, taban = taban, oturum_id = oturum_id)
}

.oo_belge_test_dosya <- function(ad, icerik = "Türkçe içerik: ğüşiöç İIıi") {
  yol <- file.path(tempdir(), ad)
  writeLines(icerik, yol, useBytes = FALSE)
  yol
}

test_that("belge yükleme: yetki fail-closed, doğrulama tekil oturumla aynı, Türkçe ad korunur", {
  ortam <- .oo_belge_test_ortam()
  conn <- ortam$conn
  on.exit({
    DBI::dbDisconnect(conn)
    options(mergen.ortak_yukleme_taban = NULL)
  }, add = TRUE)
  options(mergen.ortak_yukleme_taban = ortam$taban)

  kaynak <- .oo_belge_test_dosya("proje_notları_ğüşiöç.txt")

  # İzleyici (yapay_zeka_sor yetkisi yok) yükleyemez.
  izleyici <- ortak_db_belge_yukle(ortam$oturum_id, 3L, kaynak, "proje_notları_ğüşiöç.txt", conn = conn)
  expect_false(izleyici$basarili)
  expect_true(grepl("yetki", izleyici$mesaj, fixed = TRUE))

  # Katılımcı olmayan kullanıcı (id 99) yükleyemez.
  yabanci <- ortak_db_belge_yukle(ortam$oturum_id, 99L, kaynak, "x.txt", conn = conn)
  expect_false(yabanci$basarili)

  # Uzantı beyaz listesi tekil oturumla aynıdır: exe reddedilir.
  exe_kaynak <- .oo_belge_test_dosya("zararli.exe", "MZ")
  exe <- ortak_db_belge_yukle(ortam$oturum_id, 2L, exe_kaynak, "zararli.exe", conn = conn)
  expect_false(exe$basarili)

  # Traversal dosya adı reddedilir.
  traversal <- ortak_db_belge_yukle(ortam$oturum_id, 2L, kaynak, "../kacak.txt", conn = conn)
  expect_false(traversal$basarili)

  # Boyut sınırı merkezi opsiyon üzerinden uygulanır.
  eski_limit <- getOption("mergen.upload_max_mb", 25L)
  options(mergen.upload_max_mb = 0.000001)
  buyuk <- ortak_db_belge_yukle(ortam$oturum_id, 2L, kaynak, "buyuk.txt", conn = conn)
  options(mergen.upload_max_mb = eski_limit)
  expect_false(buyuk$basarili)

  # Yetkili katılımcı Türkçe adlı belgeyi yükler; varsayılan SEÇİLİDİR.
  sonuc <- ortak_db_belge_yukle(ortam$oturum_id, 2L, kaynak, "proje_notları_ğüşiöç.txt", conn = conn)
  expect_true(sonuc$basarili)
  expect_true(is.integer(sonuc$dosya_id) && sonuc$dosya_id > 0L)

  belgeler <- ortak_db_dosyalar(ortam$oturum_id, 1L, conn = conn)
  expect_equal(nrow(belgeler), 1L)
  expect_identical(as.character(belgeler$DosyaAdi[1]), "proje_notları_ğüşiöç.txt")

  meta <- ortak_belge_meta(belgeler$MetaJson[1])
  expect_identical(meta$kaynak, "KatilimciYuklemesi")
  expect_true(meta$secili)

  # Yükleme odaya görünür BelgeBildirimi bırakır (yükleyen adıyla).
  mesajlar <- ortak_db_mesajlari_getir(ortam$oturum_id, 1L, conn = conn)
  bildirimler <- mesajlar[mesajlar$MesajTuru == "BelgeBildirimi", , drop = FALSE]
  expect_equal(nrow(bildirimler), 1L)
  expect_true(grepl("Barış Demir", bildirimler$MesajMetni[1], fixed = TRUE))
})

test_that("yükleme kökü oturuma özeldir ve oturumlar arası fiziksel izolasyon korunur", {
  ortam <- .oo_belge_test_ortam()
  conn <- ortam$conn
  on.exit({
    DBI::dbDisconnect(conn)
    options(mergen.ortak_yukleme_taban = NULL)
  }, add = TRUE)
  options(mergen.ortak_yukleme_taban = ortam$taban)

  ikinci_oturum <- ortak_db_oturum_olustur("NormalSohbet", "İkinci Oda", 1L, conn = conn)

  kaynak <- .oo_belge_test_dosya("ayrisim.txt")
  bir <- ortak_db_belge_yukle(ortam$oturum_id, 1L, kaynak, "ayrisim.txt", conn = conn)
  iki <- ortak_db_belge_yukle(ikinci_oturum, 1L, kaynak, "ayrisim.txt", conn = conn)
  expect_true(bir$basarili && iki$basarili)

  kok_bir <- ortak_oturum_yukleme_koku(ortam$oturum_id)
  kok_iki <- ortak_oturum_yukleme_koku(ikinci_oturum)

  expect_true(grepl(sprintf("ortak_oturum_%d", ortam$oturum_id), kok_bir, fixed = TRUE))
  expect_true(grepl(sprintf("ortak_oturum_%d", ikinci_oturum), kok_iki, fixed = TRUE))
  expect_false(identical(kok_bir, kok_iki))
  expect_length(list.files(kok_bir), 1L)
  expect_length(list.files(kok_iki), 1L)

  # Bir odanın belgesi diğer odanın listesinde GÖRÜNMEZ.
  expect_equal(nrow(ortak_db_dosyalar(ortam$oturum_id, 1L, conn = conn)), 1L)
  expect_equal(nrow(ortak_db_dosyalar(ikinci_oturum, 1L, conn = conn)), 1L)
})

test_that("bağlam seçimi paylaşılır ve yalnızca seçili belgeler bağlam metnine girer", {
  ortam <- .oo_belge_test_ortam()
  conn <- ortam$conn
  on.exit({
    DBI::dbDisconnect(conn)
    options(mergen.ortak_yukleme_taban = NULL)
  }, add = TRUE)
  options(mergen.ortak_yukleme_taban = ortam$taban)

  k1 <- .oo_belge_test_dosya("birinci.txt", "Birinci belgenin özgün içeriği ğüşiöç")
  k2 <- .oo_belge_test_dosya("ikinci.txt", "İkinci belgenin özgün içeriği")

  b1 <- ortak_db_belge_yukle(ortam$oturum_id, 1L, k1, "birinci.txt", conn = conn)
  b2 <- ortak_db_belge_yukle(ortam$oturum_id, 2L, k2, "ikinci.txt", conn = conn)
  expect_true(b1$basarili && b2$basarili)

  # Her iki yükleme de varsayılan seçilidir.
  secili <- ortak_db_secili_belgeler(ortam$oturum_id, 1L, conn = conn)
  expect_equal(nrow(secili), 2L)

  # İzleyici seçim durumunu DEĞİŞTİREMEZ (fail-closed).
  expect_false(ortak_db_belge_secim_guncelle(b2$dosya_id, 3L, secili = FALSE, conn = conn))

  # Yetkili katılımcı ikinci belgeyi bağlamdan çıkarır; durum paylaşılır.
  expect_true(ortak_db_belge_secim_guncelle(b2$dosya_id, 2L, secili = FALSE, conn = conn))
  secili2 <- ortak_db_secili_belgeler(ortam$oturum_id, 1L, conn = conn)
  expect_equal(nrow(secili2), 1L)
  expect_identical(as.character(secili2$DosyaAdi[1]), "birinci.txt")

  # Bağlam metni yalnızca seçili belgeyi içerir; Kaynakça talimatı taşır.
  baglam <- ortak_belge_baglam_metni(secili2)
  expect_true(grepl("birinci.txt", baglam$metin, fixed = TRUE))
  expect_true(grepl("Birinci belgenin özgün içeriği", baglam$metin, fixed = TRUE))
  expect_false(grepl("İkinci belgenin özgün içeriği", baglam$metin, fixed = TRUE))
  expect_true(grepl("Kaynakça", baglam$metin, fixed = TRUE))

  # Sistem mesajı üreticisi LLM protokol şeklini döndürür.
  sistem <- ortak_belge_baglam_sistem_mesaji(ortam$oturum_id, 1L, conn = conn)
  expect_identical(sistem$role, "system")
  expect_true(nzchar(sistem$content))

  # Kuyruk anlık görüntüsü belge kimliklerini MetaJson'dan ayırır: boş liste
  # NULL değildir ve sonradan seçilen belgeleri bağlama taşımamalıdır.
  bos_snapshot_json <- as.character(jsonlite::toJSON(
    list(belgeler = list(secili_ids = integer(0))),
    auto_unbox = TRUE,
    null = "null"
  ))
  expect_identical(ortak_belge_meta_secili_idleri(bos_snapshot_json), integer(0))
  expect_null(ortak_belge_baglam_sistem_mesaji(
    ortam$oturum_id,
    1L,
    conn = conn,
    belge_ids = integer(0)
  ))
  expect_true(grepl(
    "birinci.txt",
    ortak_belge_baglam_sistem_mesaji(
      ortam$oturum_id,
      1L,
      conn = conn,
      belge_ids = b1$dosya_id
    )$content,
    fixed = TRUE
  ))

  # Hiç seçili belge kalmazsa bağlam mesajı NULL olur.
  expect_true(ortak_db_belge_secim_guncelle(b1$dosya_id, 1L, secili = FALSE, conn = conn))
  expect_null(ortak_belge_baglam_sistem_mesaji(ortam$oturum_id, 1L, conn = conn))
})

test_that("belge kaldırma yetki ister, soft delete + kök-içi fiziksel silme yapar", {
  ortam <- .oo_belge_test_ortam()
  conn <- ortam$conn
  on.exit({
    DBI::dbDisconnect(conn)
    options(mergen.ortak_yukleme_taban = NULL)
  }, add = TRUE)
  options(mergen.ortak_yukleme_taban = ortam$taban)

  kaynak <- .oo_belge_test_dosya("silinecek.txt")
  b <- ortak_db_belge_yukle(ortam$oturum_id, 2L, kaynak, "silinecek.txt", conn = conn)
  expect_true(b$basarili)

  kok <- ortak_oturum_yukleme_koku(ortam$oturum_id)
  expect_length(list.files(kok), 1L)

  # İzleyici kaldıramaz (fail-closed).
  izleyici <- ortak_db_belge_sil(b$dosya_id, 3L, conn = conn)
  expect_false(izleyici$basarili)
  expect_length(list.files(kok), 1L)

  # Yetkili katılımcı kaldırır: liste dışı + fiziksel dosya silinir.
  sonuc <- ortak_db_belge_sil(b$dosya_id, 1L, conn = conn)
  expect_true(sonuc$basarili)
  expect_equal(nrow(ortak_db_dosyalar(ortam$oturum_id, 1L, conn = conn)), 0L)
  expect_length(list.files(kok), 0L)

  durum <- DBI::dbGetQuery(conn,
    "SELECT DosyaDurumu FROM MB_OrtakOturum_Dosyalar WHERE OrtakDosyaID = ?",
    params = list(b$dosya_id))
  expect_identical(as.character(durum$DosyaDurumu[1]), "Silindi")

  # Kaldırılmış belge yeniden kaldırılamaz / seçilemez.
  expect_false(ortak_db_belge_sil(b$dosya_id, 1L, conn = conn)$basarili)
  expect_false(ortak_db_belge_secim_guncelle(b$dosya_id, 1L, secili = TRUE, conn = conn))
})

test_that("yüklenen belge Kendi Dosyalarıma Kaydet ile kopyalanabilir (yükleme kökü meşru)", {
  ortam <- .oo_belge_test_ortam()
  conn <- ortam$conn

  test_root <- file.path(tempdir(), sprintf("oo_kopya_root_%s", as.integer(runif(1, 1, 1e9))))
  dir.create(test_root, showWarnings = FALSE, recursive = TRUE)
  eski_root <- getOption("mergen.files_root", NULL)

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
    DBI::dbDisconnect(conn)
    options(mergen.ortak_yukleme_taban = NULL)
    options(mergen.files_root = eski_root)
    if (is.null(onceki_kayit_fn)) {
      rm("global_register_file", envir = globalenv())
    } else {
      assign("global_register_file", onceki_kayit_fn, envir = globalenv())
    }
  }, add = TRUE)

  options(mergen.ortak_yukleme_taban = ortam$taban)
  options(mergen.files_root = test_root)

  kaynak <- .oo_belge_test_dosya("kopyalanacak.txt")
  b <- ortak_db_belge_yukle(ortam$oturum_id, 1L, kaynak, "kopyalanacak.txt", conn = conn)
  expect_true(b$basarili)

  sonuc <- ortak_dosya_kisisel_kopyala(b$dosya_id, 2L, conn = conn)
  expect_true(sonuc$basarili)
  expect_identical(sonuc$durum, "Kopyalandı")
})

test_that("sohbeti kalıcı temizleme: yetki, üretim kilidi ve kuyruk sözleşmeleri", {
  ortam <- .oo_belge_test_ortam()
  conn <- ortam$conn
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- ortam$oturum_id

  ortak_db_mesaj_ekle(oturum_id, 1L, "OdaMesajı", "Merhaba ekip", conn = conn)
  soru_id <- ortak_db_mesaj_ekle(oturum_id, 2L, "YapayZekaSorusu", "Risk yönetimi nedir?",
                                 llm_gonderildi = TRUE, conn = conn)
  ortak_db_mesaj_ekle(oturum_id, NULL, "YapayZekaYanıtı", "Risk yönetimi ...",
                      bagli_mesaj_id = soru_id, conn = conn)
  ortak_db_kuyruk_ekle(oturum_id, soru_id, conn = conn)

  # Katılımcı (katilimci_yonet yetkisi yok) temizleyemez.
  katilimci <- ortak_db_sohbet_temizle(oturum_id, 2L, conn = conn)
  expect_false(katilimci$basarili)
  expect_gte(nrow(ortak_db_mesajlari_getir(oturum_id, 1L, conn = conn)), 3L)

  # Üretim sürerken Sahip bile temizleyemez.
  expect_true(ortak_db_uretim_kilidi_al(oturum_id, 1L, "istek_1", mesaj_id = soru_id, conn = conn))
  kilitli <- ortak_db_sohbet_temizle(oturum_id, 1L, conn = conn)
  expect_false(kilitli$basarili)
  expect_true(grepl("üretimi", kilitli$mesaj, fixed = TRUE))
  ortak_db_uretim_kilidi_birak(oturum_id, "istek_1", conn = conn)

  # Sahip temizler: tüm mesajlar silinir, kuyruk boşalır, sistem notu kalır.
  sonuc <- ortak_db_sohbet_temizle(oturum_id, 1L, conn = conn)
  expect_true(sonuc$basarili)

  kalanlar <- ortak_db_mesajlari_getir(oturum_id, 1L, conn = conn)
  expect_equal(nrow(kalanlar), 1L)
  expect_identical(as.character(kalanlar$MesajTuru[1]), "SistemMesajı")
  expect_true(grepl("kalıcı olarak temizlendi", kalanlar$MesajMetni[1], fixed = TRUE))
  expect_true(grepl("Ayşe Yılmaz", kalanlar$MesajMetni[1], fixed = TRUE))

  kuyruk <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) AS n FROM MB_OrtakOturum_YapayZekaKuyrugu WHERE OrtakOturumID = ?",
    params = list(oturum_id))
  expect_identical(as.integer(kuyruk$n[1]), 0L)

  # Temizlik yalnızca bu odayı etkiler (izolasyon).
  ikinci <- ortak_db_oturum_olustur("NormalSohbet", "Dokunulmayan Oda", 1L, conn = conn)
  ortak_db_mesaj_ekle(ikinci, 1L, "OdaMesajı", "Bu kalmalı", conn = conn)
  expect_true(ortak_db_sohbet_temizle(oturum_id, 1L, conn = conn)$basarili)
  expect_equal(nrow(ortak_db_mesajlari_getir(ikinci, 1L, conn = conn)), 1L)
})
