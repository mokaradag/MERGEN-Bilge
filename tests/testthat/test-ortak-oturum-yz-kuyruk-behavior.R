# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-yz-kuyruk-behavior.R
# Açıklama: Ortak Oturumlar tamamlama seti davranış testleri:
#   - SAF yardımcılar: canlı durum sunum rozeti, rol görünen ad/seçenekler,
#     kuyruk/aktif katılım durumları, Bilge Yolaç yetki kararları.
#   - DB katmanı (gerçek RSQLite): yapay zekâ kuyruğu yaşam döngüsü, kısmi
#     yanıt yayını, aktif üretim detayı, bayat kilit devralma, kişisel geçmiş
#     kopyalama, katılımcı listesi aktif filtresi (çıkarma görünür etkisi),
#     canlı durum oda kimliği.
#   Gerçek SQL Server/ODBC, LLM, tarayıcı, SSO veya ağ GEREKMEZ; gizli değer yok.
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
  if (!exists("ortak_rol_yetkileri", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_permissions.R"), encoding = "UTF-8", local = globalenv())
  }
  if (!exists("ortak_sunum_rozeti", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ortak_oturum_sunum.R"), encoding = "UTF-8", local = globalenv())
  }
  for (dosya in c(
    "helpers_ortak_oturum_db.R",
    "helpers_ortak_oturum_db_katilim.R",
    "helpers_ortak_oturum_db_davet.R",
    "helpers_ortak_oturum_db_mesajlar.R",
    "helpers_ortak_oturum_db_kuyruk.R",
    "helpers_ortak_oturum_files.R",
    "helpers_ortak_oturum_bakim.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# -----------------------------------------------------------------------------
# SAF yardımcılar
# -----------------------------------------------------------------------------

test_that("canlı durum sunum rozeti renk + Türkçe etiketi (yalnızca renk değil) üretir", {
  odada <- ortak_sunum_rozeti("Çevrimİçi", ayni_odada = TRUE)
  expect_identical(odada$sinif, "oo-canli-odada")
  expect_identical(odada$etiket, "Bu odada çevrim içi")

  cevrimici <- ortak_sunum_rozeti("Çevrimİçi", ayni_odada = FALSE)
  expect_identical(cevrimici$sinif, "oo-canli-cevrimici")
  expect_identical(cevrimici$etiket, "Uygulamada çevrim içi")

  bosta <- ortak_sunum_rozeti("Boşta")
  expect_identical(bosta$sinif, "oo-canli-bosta")

  davetli <- ortak_sunum_rozeti("ÇevrimDışı", davet_bekliyor = TRUE)
  expect_identical(davetli$sinif, "oo-canli-davetli")
  expect_identical(davetli$etiket, "Davet bekliyor")

  cevrimdisi <- ortak_sunum_rozeti("ÇevrimDışı")
  expect_identical(cevrimdisi$sinif, "oo-canli-cevrimdisi")
})

test_that("rol görünen ad ve seçenekler insan-okunur (Oturum Yöneticisi boşluklu)", {
  expect_identical(ortak_rol_gorunen_ad("OturumYöneticisi"), "Oturum Yöneticisi")
  expect_identical(ortak_rol_gorunen_ad("Sahip"), "Sahip")
  expect_identical(ortak_rol_gorunen_ad("Katılımcı"), "Katılımcı")
  expect_identical(ortak_rol_gorunen_ad("İzleyici"), "İzleyici")
  expect_identical(ortak_rol_gorunen_ad("Bilinmeyen"), "Bilinmeyen")

  secenekler <- ortak_rol_secenekleri()
  # Sahip atanamaz; teknik değerler korunur, görünen etiketler boşluklu.
  expect_false("Sahip" %in% unname(secenekler))
  expect_true("OturumYöneticisi" %in% unname(secenekler))
  expect_true("Oturum Yöneticisi" %in% names(secenekler))
})

test_that("kuyruk/aktif katılım durumları ve Bilge Yolaç yetki kararları doğru", {
  expect_identical(ortak_kuyruk_durumlari()[1:2], c("Bekliyor", "Çalışıyor"))
  expect_identical(ortak_aktif_katilim_durumlari(), c("Katıldı", "DavetEdildi"))

  # Çalıştırma yapay_zeka_sor ile aynı satır; çalışma alanı yazma yalnızca yönetici+.
  expect_true(ortak_by_calistirabilir_mi("Katılımcı"))
  expect_false(ortak_by_calistirabilir_mi("İzleyici"))
  expect_true(ortak_by_calisma_alani_yazabilir_mi("OturumYöneticisi"))
  expect_true(ortak_by_calisma_alani_yazabilir_mi("Sahip"))
  expect_false(ortak_by_calisma_alani_yazabilir_mi("Katılımcı"))
})

# -----------------------------------------------------------------------------
# DB katmanı (RSQLite)
# -----------------------------------------------------------------------------

.oo_yz_schema <- function(conn) {
  DBI::dbExecute(conn, "CREATE TABLE MB_Users (UserID INTEGER PRIMARY KEY AUTOINCREMENT, KullaniciAdi TEXT, KaynakAdi TEXT, Email TEXT, Departman TEXT, Sicil TEXT)")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturumlar (OrtakOturumID INTEGER PRIMARY KEY AUTOINCREMENT, KaynakTuru TEXT NOT NULL, KaynakID INTEGER, Baslik TEXT, OlusturanKullaniciID INTEGER NOT NULL, OturumDurumu TEXT NOT NULL, PaylasimBaslangicTipi TEXT, SonEtkinlikZamani TEXT, OlusturmaZamani TEXT, GuncellemeZamani TEXT, MetaJson TEXT)")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_Katilimcilar (KatilimciID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER NOT NULL, KullaniciID INTEGER NOT NULL, Rol TEXT NOT NULL, KatilimDurumu TEXT NOT NULL, KullaniciGorunumDurumu TEXT NOT NULL, DavetEdenKullaniciID INTEGER, DavetZamani TEXT, KatilmaZamani TEXT, SonGorulmeZamani TEXT, OlusturmaZamani TEXT, UNIQUE (OrtakOturumID, KullaniciID))")
  DBI::dbExecute(conn, "CREATE TABLE MB_Kullanici_CanliDurum (CanliDurumID INTEGER PRIMARY KEY AUTOINCREMENT, KullaniciID INTEGER NOT NULL, OturumAnahtari TEXT NOT NULL, Sayfa TEXT, SonKalpAtisiZamani TEXT NOT NULL, Durum TEXT NOT NULL, SonGorulenOrtakOturumID INTEGER, OlusturmaZamani TEXT, UNIQUE (KullaniciID, OturumAnahtari))")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_Mesajlar (OrtakMesajID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER NOT NULL, GonderenKullaniciID INTEGER, MesajTuru TEXT NOT NULL, Hedef TEXT NOT NULL, MesajMetni TEXT, BagliMesajID INTEGER, MesajSirasi INTEGER NOT NULL, LLMGonderildiMi INTEGER NOT NULL DEFAULT 0, OlusturmaZamani TEXT, MetaJson TEXT, UNIQUE (OrtakOturumID, MesajSirasi))")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_YapayZekaKuyrugu (KuyrukID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER NOT NULL, OrtakMesajID INTEGER NOT NULL, SiraNo INTEGER NOT NULL, Durum TEXT NOT NULL, OlusturmaZamani TEXT, BaslamaZamani TEXT, BitisZamani TEXT)")
  # AktifUretimler: KismiYanit kolonu DAHİL (üretim şeması 8b ile hizalı).
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_AktifUretimler (OrtakOturumID INTEGER PRIMARY KEY, BaslatanKullaniciID INTEGER NOT NULL, OrtakMesajID INTEGER, IstekID TEXT NOT NULL, KilitDurumu TEXT NOT NULL, BaslamaZamani TEXT, GuncellemeZamani TEXT, KismiYanit TEXT)")
  DBI::dbExecute(conn, "CREATE TABLE MB_OrtakOturum_Olaylar (OlayID INTEGER PRIMARY KEY AUTOINCREMENT, OrtakOturumID INTEGER NOT NULL, OlayTuru TEXT NOT NULL, TetikleyenKullaniciID INTEGER, PayloadJson TEXT, OlusturmaZamani TEXT)")
  # Kişisel geçmiş kopyalama için kişisel tablolar (yalnızca OKUNUR).
  DBI::dbExecute(conn, "CREATE TABLE MB_Chats (ChatID INTEGER PRIMARY KEY AUTOINCREMENT, UserID INTEGER NOT NULL, ChatTitle TEXT, IsDeleted INTEGER DEFAULT 0, CreateTimestamp TEXT)")
  DBI::dbExecute(conn, "CREATE TABLE MB_Messages (MessageID INTEGER PRIMARY KEY AUTOINCREMENT, ChatID INTEGER NOT NULL, MessageType TEXT, MessageContent TEXT, MessageOrder INTEGER, MessageTimestamp TEXT)")

  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman) VALUES ('ayse','Ayşe Yılmaz','ayse@x.com','Yazılım')")
  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman) VALUES ('baris','Barış Demir','baris@x.com','Donanım')")
  DBI::dbExecute(conn, "INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, Email, Departman) VALUES ('cem','Cem Kaya','cem@x.com','Kalite')")
  invisible(conn)
}

.oo_yz_conn <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), tempfile(fileext = ".sqlite"))
  .oo_yz_schema(conn)
  conn
}

# Sahip (1) + katılan Katılımcı (2) olan bir sohbet odası kurar.
.oo_yz_oda <- function(conn) {
  oturum_id <- ortak_db_oturum_olustur("NormalSohbet", "Kuyruk Testi", 1L, conn = conn)
  ortak_db_katilimci_ekle(oturum_id, 2L, "Katılımcı", katilim_durumu = "Katıldı", conn = conn)
  oturum_id
}

test_that("yapay zekâ kuyruğu: ekleme, bekleyen listesi, sıralı devralma ve tamamlama", {
  conn <- .oo_yz_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- .oo_yz_oda(conn)

  # İki soru gönderilir (kilit sahibi başkasıdır varsayımıyla doğrudan kuyruğa).
  s1 <- ortak_db_mesaj_ekle(oturum_id, 1L, "YapayZekaSorusu", "Birinci soru", conn = conn)
  s2 <- ortak_db_mesaj_ekle(oturum_id, 2L, "YapayZekaSorusu", "İkinci soru", conn = conn)

  k1 <- ortak_db_kuyruk_ekle(oturum_id, s1, conn = conn)
  k2 <- ortak_db_kuyruk_ekle(oturum_id, s2, conn = conn)
  expect_true(!is.null(k1) && !is.null(k2))

  bekleyenler <- ortak_db_kuyruk_bekleyenler(oturum_id, conn = conn)
  expect_equal(nrow(bekleyenler), 2L)
  expect_identical(as.character(bekleyenler$MesajMetni[1]), "Birinci soru")
  expect_identical(as.character(bekleyenler$SoranAdi[1]), "Ayşe Yılmaz")

  # Sıradaki devralınır: ilk giren ilk çıkar (SiraNo).
  sonraki <- ortak_db_kuyruk_sonraki_al(oturum_id, conn = conn)
  expect_identical(sonraki$mesaj_metni, "Birinci soru")
  expect_identical(as.integer(sonraki$soran_id), 1L)

  # Devralınan kayıt artık Bekliyor değildir; kalan tek bekleyen ikinci sorudur.
  kalan <- ortak_db_kuyruk_bekleyenler(oturum_id, conn = conn)
  expect_equal(nrow(kalan), 1L)
  expect_identical(as.character(kalan$MesajMetni[1]), "İkinci soru")

  expect_true(ortak_db_kuyruk_tamamla(sonraki$kuyruk_id, "Tamamlandı", conn = conn))

  # Bekletme: devralınan bir kayıt yeniden Bekliyor'a döner (kaybolmaz).
  sonraki2 <- ortak_db_kuyruk_sonraki_al(oturum_id, conn = conn)
  expect_identical(sonraki2$mesaj_metni, "İkinci soru")
  expect_true(ortak_db_kuyruk_beklet(sonraki2$kuyruk_id, conn = conn))
  geri <- ortak_db_kuyruk_bekleyenler(oturum_id, conn = conn)
  expect_equal(nrow(geri), 1L)
})

test_that("kısmi yanıt yayını ve aktif üretim detayı çalışır (KismiYanit kolonu varken)", {
  conn <- .oo_yz_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- .oo_yz_oda(conn)
  istek_id <- "istek_1"
  expect_true(ortak_db_uretim_kilidi_al(oturum_id, 1L, istek_id, conn = conn))

  # Kısmi yanıt yazılır ve detayda görünür.
  expect_true(ortak_db_uretim_kismi_yanit_guncelle(oturum_id, istek_id, "Yanıt üretiliyor...", conn = conn))
  detay <- ortak_db_aktif_uretim_detay(oturum_id, conn = conn)
  expect_false(is.null(detay))
  expect_identical(as.character(detay$KilitDurumu[1]), "Çalışıyor")
  expect_identical(as.character(detay$BaslatanAdi[1]), "Ayşe Yılmaz")
  expect_identical(as.character(detay$KismiYanit[1]), "Yanıt üretiliyor...")
})

test_that("bayat üretim kilidi eşik aşınca devralınır (oda süresiz kilitlenmez)", {
  conn <- .oo_yz_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- .oo_yz_oda(conn)
  expect_true(ortak_db_uretim_kilidi_al(oturum_id, 1L, "eski_istek", conn = conn))

  # Kilidi eski göster: normal ikinci deneme reddedilir...
  expect_false(ortak_db_uretim_kilidi_al(oturum_id, 2L, "yeni_istek", conn = conn))

  # ...ancak başlama zamanı 20 dk geriye alınırsa bayat sayılır ve devralınır.
  eski <- format(Sys.time() - 20 * 60, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  DBI::dbExecute(conn, "UPDATE MB_OrtakOturum_AktifUretimler SET BaslamaZamani = ? WHERE OrtakOturumID = ?",
                 params = list(eski, oturum_id))
  expect_true(ortak_db_uretim_kilidi_al(oturum_id, 2L, "yeni_istek2", bayat_dakika = 15L, conn = conn))
})

test_that("kişisel geçmiş kopyalama: soru/yanıt ortak odaya kopyalanır, kaynak değişmez", {
  conn <- .oo_yz_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- .oo_yz_oda(conn)

  # Sahip (1) kişisel sohbeti.
  DBI::dbExecute(conn, "INSERT INTO MB_Chats (UserID, ChatTitle, IsDeleted, CreateTimestamp) VALUES (1, 'Kişisel Söyleşi', 0, '2026-01-01 09:00:00')")
  chat_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() AS id")$id[1]
  DBI::dbExecute(conn, "INSERT INTO MB_Messages (ChatID, MessageType, MessageContent, MessageOrder, MessageTimestamp) VALUES (?, 'user', 'Merhaba yapay zekâ', 1, '2026-01-01 09:00:01')", params = list(chat_id))
  DBI::dbExecute(conn, "INSERT INTO MB_Messages (ChatID, MessageType, MessageContent, MessageOrder, MessageTimestamp) VALUES (?, 'ai', 'Merhaba, nasıl yardımcı olabilirim?', 2, '2026-01-01 09:00:02')", params = list(chat_id))

  sonuc <- ortak_db_gecmis_kopyala(oturum_id, 1L, chat_id, conn = conn)
  expect_true(sonuc$basarili)
  expect_equal(sonuc$kopyalanan, 2L)

  # Ortak odaya soru + yanıt + sistem bilgi mesajı yazıldı.
  mesajlar <- ortak_db_mesajlari_getir(oturum_id, 1L, conn = conn)
  turler <- as.character(mesajlar$MesajTuru)
  expect_true("YapayZekaSorusu" %in% turler)
  expect_true("YapayZekaYanıtı" %in% turler)

  # Kaynak kişisel kayıt DEĞİŞMEDİ.
  kaynak_adet <- DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM MB_Messages WHERE ChatID = ?", params = list(chat_id))
  expect_equal(as.integer(kaynak_adet$n[1]), 2L)

  # Başka kullanıcının sohbetine yetkisiz kopyalama denemesi başarısızdır.
  yabanci <- ortak_db_gecmis_kopyala(oturum_id, 2L, chat_id, conn = conn)
  expect_false(yabanci$basarili)
})

test_that("katılımcı listesi aktif filtresi: çıkarılan kullanıcı listeden düşer", {
  conn <- .oo_yz_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  oturum_id <- .oo_yz_oda(conn)

  # İki aktif katılımcı (Sahip 1 + Katılımcı 2).
  aktif <- ortak_db_katilimci_listesi(oturum_id, conn = conn)
  expect_equal(nrow(aktif), 2L)

  # Katılımcı 2 çıkarılır -> aktif listeden düşer (görünür etki).
  ortak_db_katilim_durumu_guncelle(oturum_id, 2L, "Çıkarıldı", conn = conn)
  aktif2 <- ortak_db_katilimci_listesi(oturum_id, conn = conn)
  expect_equal(nrow(aktif2), 1L)
  expect_equal(as.integer(aktif2$KullaniciID[1]), 1L)

  # sadece_aktif = FALSE tüm satırları (çıkarılan dahil) döndürür.
  tumu <- ortak_db_katilimci_listesi(oturum_id, conn = conn, sadece_aktif = FALSE)
  expect_equal(nrow(tumu), 2L)
})

test_that("canlı durumlar en güncel satırı ve görülen oda kimliğini döndürür", {
  conn <- .oo_yz_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  simdi <- format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")
  ortak_db_kalp_atisi(1L, "oturum_a", sayfa = "ortak_calismalar",
                      gorulen_ortak_oturum_id = 42L, conn = conn)

  durumlar <- ortak_db_canli_durumlar(conn = conn)
  expect_equal(nrow(durumlar), 1L)
  expect_identical(as.character(durumlar$CanliDurum[1]), "Çevrimİçi")
  expect_equal(as.integer(durumlar$SonGorulenOrtakOturumID[1]), 42L)
})

# -----------------------------------------------------------------------------
# Yeni bağlam (bağlam sıfırlama) — item 10
# -----------------------------------------------------------------------------

test_that("bağlam sıfırlama işareti sonrası yalnızca sonraki soru/yanıt bağlama girer", {
  df <- data.frame(
    MesajTuru = c(
      "YapayZekaSorusu", "YapayZekaYanıtı",
      "SistemMesajı",
      "YapayZekaSorusu", "YapayZekaYanıtı"
    ),
    MesajMetni = c(
      "Eski soru", "Eski yanıt",
      ortak_baglam_sifirlama_notu(),
      "Yeni soru", "Yeni yanıt"
    ),
    stringsAsFactors = FALSE
  )

  gecmis <- ortak_yz_sohbet_gecmisi(df)
  icerikler <- vapply(gecmis, function(m) as.character(m$content), character(1))

  # Sıfırlama işaretinden ÖNCEKİ soru/yanıt bağlama girmez.
  expect_false("Eski soru" %in% icerikler)
  expect_false("Eski yanıt" %in% icerikler)
  # İşaretten SONRAKİ soru/yanıt bağlamdadır.
  expect_true("Yeni soru" %in% icerikler)
  expect_true("Yeni yanıt" %in% icerikler)
})

test_that("sıfırlama sonrası tamamlanan eski yanıt yeni bağlama alınmaz", {
  df <- data.frame(
    OrtakMesajID = c("2147483648", "2147483649", "2147483650", "2147483651"),
    MesajTuru = c(
      "YapayZekaSorusu",
      "SistemMesajı",
      "YapayZekaYanıtı",
      "YapayZekaSorusu"
    ),
    MesajMetni = c(
      "Eski soru",
      ortak_baglam_sifirlama_notu(),
      "Geç biten eski yanıt",
      "Yeni soru"
    ),
    BagliMesajID = c(NA_character_, NA_character_, "2147483648", NA_character_),
    stringsAsFactors = FALSE
  )

  gecmis <- ortak_yz_sohbet_gecmisi(df)
  icerikler <- vapply(gecmis, function(m) as.character(m$content), character(1))

  expect_false("Eski soru" %in% icerikler)
  expect_false("Geç biten eski yanıt" %in% icerikler)
  expect_true("Yeni soru" %in% icerikler)
})

test_that("işaret yoksa tüm soru/yanıt geçmişi korunur (davranış değişmez)", {
  df <- data.frame(
    MesajTuru = c("YapayZekaSorusu", "YapayZekaYanıtı"),
    MesajMetni = c("Soru bir", "Yanıt bir"),
    stringsAsFactors = FALSE
  )
  gecmis <- ortak_yz_sohbet_gecmisi(df)
  icerikler <- vapply(gecmis, function(m) as.character(m$content), character(1))
  expect_true(all(c("Soru bir", "Yanıt bir") %in% icerikler))
})

test_that("yalnızca EN SON sıfırlama işareti dikkate alınır", {
  df <- data.frame(
    MesajTuru = c(
      "SistemMesajı", "YapayZekaSorusu",
      "SistemMesajı", "YapayZekaSorusu"
    ),
    MesajMetni = c(
      ortak_baglam_sifirlama_notu(), "Ara soru",
      ortak_baglam_sifirlama_notu(), "Son soru"
    ),
    stringsAsFactors = FALSE
  )
  gecmis <- ortak_yz_sohbet_gecmisi(df)
  icerikler <- vapply(gecmis, function(m) as.character(m$content), character(1))
  expect_false("Ara soru" %in% icerikler)
  expect_true("Son soru" %in% icerikler)
})

test_that("bağlam sıfırlama notu kararlı ve boş olmayan bir metindir", {
  not <- ortak_baglam_sifirlama_notu()
  expect_true(is.character(not) && length(not) == 1L && nzchar(not))
})
