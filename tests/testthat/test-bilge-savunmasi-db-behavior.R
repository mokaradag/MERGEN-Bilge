# ==============================================================================
# Dosya Yolu: tests/testthat/test-bilge-savunmasi-db-behavior.R
# Açıklama: Bilge Savunması kalıcılık katmanının (MB_Game_* aile) davranış
#           testleri. GERÇEK bir DBI arka ucu (RSQLite, bellek içi) üzerinde
#           çalışır; gerçek SQL Server/ODBC, ağ, tarayıcı veya gizli değer
#           GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Tablo erişilebilirlik tespiti ve önbellek sıfırlama; tablolar yokken
#     tüm fonksiyonların güvenli NULL/FALSE/boş dönmesi.
#   - Profil oluşturma/okuma ve ayar kaydetme.
#   - Koşu yaşam döngüsü: jetonla idempotent başlatma, tekdüze kontrol
#     noktası, işlem-güvenli ve idempotent sonuçlandırma (ödül çoğaltılmaz).
#   - Geçersiz özetin Reddedildi olarak işaretlenmesi ve ilerlemeye
#     yazmaması (geri alma etkisi).
#   - Kampanya/kahraman/profil/başarım güncellemeleri ve kullanıcı izolasyonu.
#   - Haftalık sezon idempotentliği, giriş idempotentliği, liderlik paketi
#     (ad + rumuz + departman ile) ve topluluk katkısı idempotentliği.
#   - Plan yayınlama/okuma/yumuşak silme ve Türkçe başlık gidiş-dönüşü.
# ==============================================================================

testthat::skip_if_not_installed("DBI")
testthat::skip_if_not_installed("RSQLite")

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "utils_common.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_unicode_escape.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_db_params", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_character_id", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "config_characters.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("bilge_savunmasi_enabled", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "config_bilge_savunmasi.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("bs_kosu_ozeti_dogrula", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_bilge_savunmasi_validation.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("bs_db_tables_available", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_bilge_savunmasi_cekirdek.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("bs_db_finalize_run", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_bilge_savunmasi_kosu.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("bs_db_get_or_create_season", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_db_bilge_savunmasi_topluluk.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists(".bs_srv_bitirme_sonrasi", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "module_bilge_savunmasi.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

# SQLite şeması: docs/sql/2026-07-bilge-savunmasi.sql tablolarının test aynası.
.bs_test_db_kur <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")

  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_Profiles (",
    "GameProfileID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "UserID INTEGER NOT NULL UNIQUE, PlayerLevel INTEGER DEFAULT 1,",
    "TotalXP INTEGER DEFAULT 0, TotalScore INTEGER DEFAULT 0,",
    "SettingsJson TEXT, CreatedAt TEXT, UpdatedAt TEXT)"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_CampaignProgress (",
    "CampaignProgressID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "UserID INTEGER NOT NULL, MapID TEXT NOT NULL, Difficulty TEXT NOT NULL,",
    "Stars INTEGER DEFAULT 0, BestScore INTEGER DEFAULT 0,",
    "HighestWave INTEGER DEFAULT 0, CompletedCount INTEGER DEFAULT 0,",
    "LastPlayedAt TEXT, UNIQUE (UserID, MapID, Difficulty))"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_HeroProgress (",
    "HeroProgressID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "UserID INTEGER NOT NULL, HeroID TEXT NOT NULL,",
    "UsesCount INTEGER DEFAULT 0, MasteryXP INTEGER DEFAULT 0,",
    "UNIQUE (UserID, HeroID))"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_Runs (",
    "GameRunID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "UserID INTEGER NOT NULL, MapID TEXT NOT NULL, Difficulty TEXT NOT NULL,",
    "Seed INTEGER NOT NULL, Mode TEXT NOT NULL,",
    "ChallengeSeasonID INTEGER, BlueprintID INTEGER,",
    "GameVersion TEXT, BalanceVersion TEXT, SchemaVersion INTEGER,",
    "Status TEXT NOT NULL, ClientToken TEXT NOT NULL,",
    "StartedAt TEXT, FinalizedAt TEXT, DurationSeconds REAL,",
    "FinalWave INTEGER, CoreHealth REAL, Score INTEGER, Stars INTEGER,",
    "XPEarned INTEGER, RejectReason TEXT, ScoreDetailJson TEXT,",
    "EventSummaryJson TEXT, UNIQUE (UserID, ClientToken))"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_RunCheckpoints (",
    "CheckpointID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "GameRunID INTEGER NOT NULL, WaveNumber INTEGER NOT NULL,",
    "StateJson TEXT NOT NULL, CreatedAt TEXT,",
    "UNIQUE (GameRunID, WaveNumber))"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_Achievements (",
    "AchievementRowID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "UserID INTEGER NOT NULL, ItemID TEXT NOT NULL, ItemType TEXT NOT NULL,",
    "EarnedAt TEXT, UNIQUE (UserID, ItemID))"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_ChallengeSeasons (",
    "ChallengeSeasonID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "WeekCode TEXT NOT NULL UNIQUE, MapID TEXT NOT NULL,",
    "Difficulty TEXT NOT NULL, Seed INTEGER NOT NULL,",
    "ConfigJson TEXT, CreatedAt TEXT)"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_ChallengeEntries (",
    "ChallengeEntryID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "ChallengeSeasonID INTEGER NOT NULL, UserID INTEGER NOT NULL,",
    "GameRunID INTEGER NOT NULL, Score INTEGER DEFAULT 0,",
    "CoreHealth REAL DEFAULT 0, FinalWave INTEGER DEFAULT 0,",
    "DurationSeconds REAL DEFAULT 0, SubmittedAt TEXT,",
    "UNIQUE (ChallengeSeasonID, UserID))"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_Blueprints (",
    "BlueprintID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "UserID INTEGER NOT NULL, GameRunID INTEGER, MapID TEXT NOT NULL,",
    "Difficulty TEXT NOT NULL, Seed INTEGER NOT NULL, Title TEXT NOT NULL,",
    "PayloadJson TEXT NOT NULL, SchemaVersion INTEGER NOT NULL,",
    "CreatorResultJson TEXT, IsDeleted INTEGER DEFAULT 0, CreatedAt TEXT)"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Game_CommunityContributions (",
    "ContributionID INTEGER PRIMARY KEY AUTOINCREMENT,",
    "WeekCode TEXT NOT NULL, UserID INTEGER NOT NULL,",
    "GameRunID INTEGER NOT NULL UNIQUE, ThreatsNeutralized INTEGER DEFAULT 0,",
    "WavesDefended INTEGER DEFAULT 0, PointsContributed INTEGER DEFAULT 0,",
    "CreatedAt TEXT)"
  ))
  DBI::dbExecute(conn, paste(
    "CREATE TABLE MB_Users (",
    "UserID INTEGER PRIMARY KEY, KullaniciAdi TEXT, KaynakAdi TEXT,",
    "Departman TEXT)"
  ))
  DBI::dbExecute(conn, paste(
    "INSERT INTO MB_Users (UserID, KullaniciAdi, KaynakAdi, Departman) VALUES",
    "(101, 'gulsah.y', 'Gülşah Yıldız', 'Yazılım Müdürlüğü'),",
    "(102, 'omer.c', 'Ömer Çelik', 'Sistem Mühendisliği')"
  ))

  bs_db_reset_availability_cache()
  conn
}

# Geçerli koşu özeti: sunucu saatiyle uyumlu kısa ama makul süreli zafer.
.bs_test_db_ozet <- function(tohum, sure = 60) {
  dalgalar <- lapply(seq_len(8L), function(i) {
    list(dalga = i, olduruldu = 8L, sizinti = 0L, puan = 60,
         cekirdek = 20, kaynak = 150)
  })
  list(
    sema = BS_SEMA_SURUMU, oyun_surumu = BS_OYUN_SURUMU,
    harita = "baglam_kapisi", zorluk = "normal", tohum = tohum,
    mod = "kampanya", dalga_ozetleri = dalgalar, son_dalga = 8L,
    son_cekirdek = 20, zafer = TRUE, sure_saniye = sure,
    kullanilan_kahramanlar = list("emre", "selin", "deniz", "can", "ipek"),
    olay_ozeti = list(list(t = 1, tip = "yerlestir", k = "emre"))
  )
}

test_that("tablolar yokken tüm fonksiyonlar güvenli boş sonuç döner", {
  bos_conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit({ DBI::dbDisconnect(bos_conn); bs_db_reset_availability_cache() }, add = TRUE)
  bs_db_reset_availability_cache()

  expect_false(bs_db_tables_available(conn = bos_conn, force_refresh = TRUE))
  expect_null(bs_db_get_or_create_profile(101L, conn = bos_conn))
  expect_null(bs_db_load_profile_bundle(101L, conn = bos_conn))
  expect_null(bs_db_start_run(101L, "baglam_kapisi", "normal", 1L,
                              istemci_jetonu = "j-1", conn = bos_conn))
  expect_false(bs_db_save_checkpoint(101L, 1L, 3L, "{}", conn = bos_conn))
  sonuc <- bs_db_finalize_run(101L, 1L, "j-1", list(), conn = bos_conn)
  expect_false(isTRUE(sonuc$kabul))
  expect_null(bs_db_get_or_create_season(conn = bos_conn))
  expect_null(bs_db_challenge_leaderboard(1L, conn = bos_conn))
  expect_null(bs_db_list_blueprints(conn = bos_conn))
  expect_false(bs_db_add_community_contribution(101L, 1L, "2026-W29",
                                                conn = bos_conn))
})

test_that("profil oluşturma, tekrar okuma ve ayar kaydetme çalışır", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  expect_true(bs_db_tables_available(conn = conn, force_refresh = TRUE))

  eksik_conn <- .bs_test_db_kur()
  on.exit(DBI::dbDisconnect(eksik_conn), add = TRUE)
  DBI::dbRemoveTable(eksik_conn, "MB_Game_Blueprints")
  bs_db_reset_availability_cache()
  expect_false(bs_db_tables_available(conn = eksik_conn, force_refresh = TRUE))

  profil <- bs_db_get_or_create_profile(101L, conn = conn)
  expect_identical(profil$seviye, 1L)
  expect_identical(profil$xp, 0L)

  # İkinci çağrı yeni satır açmaz.
  profil2 <- bs_db_get_or_create_profile(101L, conn = conn)
  expect_identical(profil$profil_id, profil2$profil_id)

  expect_true(bs_db_update_settings(101L, list(sessiz = TRUE, kalite = "dengeli"),
                                    conn = conn))
  profil3 <- bs_db_get_or_create_profile(101L, conn = conn)
  expect_true(isTRUE(profil3$ayarlar$sessiz))
  expect_identical(profil3$ayarlar$kalite, "dengeli")

  # Geçersiz kullanıcı kimlikleri kalıcı iş yapmaz.
  expect_null(bs_db_get_or_create_profile(0L, conn = conn))
  expect_null(bs_db_get_or_create_profile(NA, conn = conn))
  expect_false(bs_db_update_settings(NULL, list(a = 1), conn = conn))
})

test_that("koşu başlatma jetonla idempotenttir ve eski aktif koşuyu kapatır", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu1 <- bs_db_start_run(101L, "baglam_kapisi", "normal", 111L,
                           istemci_jetonu = "jeton-a", conn = conn)
  expect_identical(kosu1$harita, "baglam_kapisi")
  expect_identical(kosu1$tohum, 111L)

  # Aynı jetonla tekrar: aynı koşu kimliği ve kalıcı satır alanları döner
  # (yeniden deneme/devam güvenliği). Çağrının yeni çözdüğü tohum/harita
  # istemciye sızarsa sonuç özeti kosu_eslesmesi ile reddedilir.
  tekrar <- bs_db_start_run(101L, "celiski_kavsagi", "zor", 999L,
                            istemci_jetonu = "jeton-a", conn = conn)
  expect_identical(tekrar$kosu_id, kosu1$kosu_id)
  expect_identical(tekrar$harita, kosu1$harita)
  expect_identical(tekrar$zorluk, kosu1$zorluk)
  expect_identical(tekrar$tohum, kosu1$tohum)

  # Yeni jeton yeni koşu açar; önceki Aktif koşu Bırakıldı olur.
  kosu2 <- bs_db_start_run(101L, "celiski_kavsagi", "normal", 222L,
                           istemci_jetonu = "jeton-b", conn = conn)
  expect_true(kosu2$kosu_id > kosu1$kosu_id)
  durumlar <- DBI::dbGetQuery(conn,
    "SELECT GameRunID, Status FROM MB_Game_Runs WHERE UserID = 101 ORDER BY GameRunID")
  expect_identical(durumlar$Status, c("Bırakıldı", "Aktif"))

  aktif <- bs_db_active_run(101L, conn = conn)
  expect_identical(aktif$kosu_id, kosu2$kosu_id)
})

test_that("kapalı koşu jetonu yeni başlatma yanıtı olarak döndürülmez", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 333L,
                          istemci_jetonu = "jeton-kapali", conn = conn)
  sonuc <- bs_db_finalize_run(101L, kosu$kosu_id, "jeton-kapali",
                              .bs_test_db_ozet(333L), conn = conn)
  expect_true(sonuc$kabul)

  # Regresyon: aynı ClientToken artık Aktif olmayan satıra aitse, benzersiz
  # jeton kısıtını atlayıp eski koşuyu "başladı" gibi döndürmemelidir.
  expect_null(bs_db_start_run(101L, "celiski_kavsagi", "normal", 444L,
                              istemci_jetonu = "jeton-kapali", conn = conn))
})

test_that("yeni koşu eklemesi başarısız olursa eski Aktif koşu Bırakıldı yapılmaz (transaction)", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu1 <- bs_db_start_run(101L, "baglam_kapisi", "normal", 111L,
                           istemci_jetonu = "jeton-once", conn = conn)
  expect_false(is.null(kosu1))

  # İkinci başlatma isteği, geçici bir DB hatasını simüle eder: Seed NOT NULL
  # kısıtını ihlal eden NA tohum, INSERT'i başarısızlığa uğratır. Düzeltme
  # öncesi kod, eski Aktif koşuyu Bırakıldı yapan UPDATE'i INSERT'ten ÖNCE
  # ayrı bir işlemde (transaction'sız) commit ederdi; bu durumda kullanıcı
  # ne eski devam edilebilir koşusunu ne de yeni bir koşu alırdı.
  basarisiz <- bs_db_start_run(101L, "baglam_kapisi", "normal", NA_integer_,
                               istemci_jetonu = "jeton-basarisiz", conn = conn)
  expect_null(basarisiz)

  # Eski koşu HÂLÂ Aktif olmalı: kapatma + ekleme tek transaction'da geri
  # alınmış olmalı.
  durumlar <- DBI::dbGetQuery(
    conn,
    "SELECT GameRunID, Status FROM MB_Game_Runs WHERE UserID = 101 ORDER BY GameRunID"
  )
  expect_identical(nrow(durumlar), 1L)
  expect_identical(durumlar$Status, "Aktif")
  expect_identical(as.integer(durumlar$GameRunID[1]), kosu1$kosu_id)

  # Başarısız istekten kaynaklı yarım kalmış ikinci bir satır YOKTUR.
  basarisiz_satir <- DBI::dbGetQuery(
    conn, "SELECT COUNT(*) AS n FROM MB_Game_Runs WHERE ClientToken = ?",
    params = list("jeton-basarisiz")
  )
  expect_identical(as.integer(basarisiz_satir$n[1]), 0L)

  # Kullanıcı devam edilebilir aktif koşusunu kaybetmemiş olmalı.
  aktif <- bs_db_active_run(101L, conn = conn)
  expect_identical(aktif$kosu_id, kosu1$kosu_id)
})

test_that("kontrol noktası tekdüze ilerler ve devam akışını besler", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 5L,
                          istemci_jetonu = "jeton-cp", conn = conn)

  expect_true(bs_db_save_checkpoint(101L, kosu$kosu_id, 3L,
                                    '{"dalgaNo":3}', conn = conn))
  expect_true(bs_db_save_checkpoint(101L, kosu$kosu_id, 4L,
                                    '{"dalgaNo":4}', conn = conn))
  # Geriye gidiş reddedilir; aynı dalga güncellenir (idempotent tekrar).
  expect_false(bs_db_save_checkpoint(101L, kosu$kosu_id, 2L, "{}", conn = conn))
  expect_true(bs_db_save_checkpoint(101L, kosu$kosu_id, 4L,
                                    '{"dalgaNo":4,"guncel":true}', conn = conn))

  # Başkasının koşusuna kontrol noktası yazılamaz (kullanıcı izolasyonu).
  expect_false(bs_db_save_checkpoint(102L, kosu$kosu_id, 5L, "{}", conn = conn))

  devam <- bs_db_active_run(101L, conn = conn)
  expect_identical(devam$kontrol_dalga, 4L)
  expect_true(grepl("guncel", devam$kontrol_durum, fixed = TRUE))
  # Sezon/plan atanmamış sıradan bir kampanya koşusunda NULL kalmalı.
  expect_null(devam$sezon_id)
  expect_null(devam$plan_id)
})

test_that("devam edilebilir aktif koşu, sezon ve plan kimliğini de taşır (devam düzleştirme sözleşmesi)", {
  # Regresyon: istemci "Devam Et" isteğini gönderirken harita/zorluk/plan_id
  # istek.devam altından düzleştirilir (bkz. www/js/bilge_savunmasi_uygulama.js
  # kosuIstegiGonder). Bu alanlar bs_db_active_run() tarafından hiç
  # döndürülmezse istemci onları düzleştiremez; bu sözleşme testi
  # bs_db_active_run()'ın sezon_id/plan_id alanlarını gerçekten taşıdığını
  # doğrular.
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  meydan <- bs_haftalik_meydan_okuma(
    as.POSIXct("2026-07-15 12:00:00", tz = "Europe/Istanbul")
  )
  sezon <- bs_db_get_or_create_season(meydan, conn = conn)

  kosu <- bs_db_start_run(101L, meydan$harita, meydan$zorluk, meydan$tohum,
                          mod = "haftalik", sezon_id = sezon$sezon_id,
                          istemci_jetonu = "jeton-haftalik-devam", conn = conn)
  expect_false(is.null(kosu))

  devam <- bs_db_active_run(101L, conn = conn)
  expect_identical(devam$kosu_id, kosu$kosu_id)
  expect_identical(devam$mod, "haftalik")
  expect_identical(devam$harita, meydan$harita)
  expect_identical(devam$zorluk, meydan$zorluk)
  expect_identical(devam$sezon_id, sezon$sezon_id)
  expect_null(devam$plan_id)

  # Plan (blueprint) modlu bir koşuda plan_id de taşınmalıdır.
  plan_kosu <- bs_db_start_run(102L, "baglam_kapisi", "normal", 55L,
                               mod = "plan", plan_id = 777L,
                               istemci_jetonu = "jeton-plan-devam", conn = conn)
  expect_false(is.null(plan_kosu))
  devam_plan <- bs_db_active_run(102L, conn = conn)
  expect_identical(devam_plan$plan_id, 777L)
  expect_null(devam_plan$sezon_id)
})

test_that("sonuçlandırma idempotenttir, ödülleri bir kez yazar ve izole eder", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 999L,
                          istemci_jetonu = "jeton-fin", conn = conn)
  ozet <- .bs_test_db_ozet(999L)

  # Yanlış jeton reddedilir.
  yanlis <- bs_db_finalize_run(101L, kosu$kosu_id, "jeton-sahte", ozet, conn = conn)
  expect_false(yanlis$kabul)
  expect_identical(yanlis$neden, "jeton")

  # Başka kullanıcı sonuçlandıramaz.
  baskasi <- bs_db_finalize_run(102L, kosu$kosu_id, "jeton-fin", ozet, conn = conn)
  expect_false(baskasi$kabul)
  expect_identical(baskasi$neden, "kosu_bulunamadi")

  sonuc <- bs_db_finalize_run(101L, kosu$kosu_id, "jeton-fin", ozet, conn = conn)
  expect_true(sonuc$kabul)
  expect_identical(sonuc$puan, 3224L)
  expect_identical(sonuc$yildiz, 3L)
  expect_identical(sonuc$xp, 322L)
  expect_false(sonuc$tekrar)
  expect_true(all(c("ilk_zafer", "uc_yildiz", "kusursuz_savunma", "tam_kadro")
                  %in% sonuc$yeni_basarimlar))

  # Idempotent tekrar: saklanan sonuç döner, ödül çoğaltılmaz.
  tekrar <- bs_db_finalize_run(101L, kosu$kosu_id, "jeton-fin", ozet, conn = conn)
  expect_true(tekrar$kabul)
  expect_true(tekrar$tekrar)
  expect_identical(tekrar$puan, 3224L)
  expect_length(tekrar$yeni_basarimlar, 0L)

  profil <- bs_db_get_or_create_profile(101L, conn = conn)
  expect_identical(profil$xp, 322L)          # iki kez yazılmadı
  expect_identical(profil$seviye, 2L)

  bundle <- bs_db_load_profile_bundle(101L, conn = conn)
  expect_identical(nrow(bundle$kampanya), 1L)
  expect_identical(as.integer(bundle$kampanya$Stars[1]), 3L)
  expect_identical(as.integer(bundle$kampanya$CompletedCount[1]), 1L)
  expect_identical(nrow(bundle$kahramanlar), 5L)
  expect_true(all(bundle$kahramanlar$UsesCount == 1L))

  # Kullanıcı izolasyonu: 102 hiçbir şey görmez.
  bundle_b <- bs_db_load_profile_bundle(102L, conn = conn)
  expect_identical(nrow(bundle_b$kampanya), 0L)
  expect_identical(nrow(bundle_b$basarimlar), 0L)
})

test_that("geçersiz özet Reddedildi olur ve ilerleme yazmaz", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 7L,
                          istemci_jetonu = "jeton-red", conn = conn)
  ozet <- .bs_test_db_ozet(7L)
  ozet$tohum <- 12345L   # tohum oynanmış

  sonuc <- bs_db_finalize_run(101L, kosu$kosu_id, "jeton-red", ozet, conn = conn)
  expect_false(sonuc$kabul)
  expect_identical(sonuc$neden, "kosu_eslesmesi")

  satir <- DBI::dbGetQuery(conn,
    "SELECT Status, RejectReason, Score FROM MB_Game_Runs WHERE GameRunID = ?",
    params = list(kosu$kosu_id))
  expect_identical(satir$Status[1], "Reddedildi")
  expect_identical(satir$RejectReason[1], "kosu_eslesmesi")

  bundle <- bs_db_load_profile_bundle(101L, conn = conn)
  expect_identical(nrow(bundle$kampanya), 0L)
  expect_identical(nrow(bundle$kahramanlar), 0L)
  profil <- bs_db_get_or_create_profile(101L, conn = conn)
  expect_identical(profil$xp, 0L)

  # Reddedilen koşu tekrar sonuçlandırılamaz; saklanan durum döner.
  tekrar <- bs_db_finalize_run(101L, kosu$kosu_id, "jeton-red",
                               .bs_test_db_ozet(7L), conn = conn)
  expect_false(tekrar$kabul)
  expect_true(tekrar$tekrar)
  expect_identical(tekrar$neden, "kosu_eslesmesi")
})

test_that("haftalık sezon idempotenttir ve liderlik zengin profil taşır", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  meydan <- bs_haftalik_meydan_okuma(
    as.POSIXct("2026-07-15 12:00:00", tz = "Europe/Istanbul")
  )
  sezon1 <- bs_db_get_or_create_season(meydan, conn = conn)
  sezon2 <- bs_db_get_or_create_season(meydan, conn = conn)
  expect_identical(sezon1$sezon_id, sezon2$sezon_id)
  expect_identical(sezon1$hafta_kodu, meydan$hafta_kodu)

  # İki kullanıcı haftalık koşu bitirir.
  girisEkle <- function(uid, jeton, sure) {
    kosu <- bs_db_start_run(uid, meydan$harita, meydan$zorluk, meydan$tohum,
                            mod = "haftalik", sezon_id = sezon1$sezon_id,
                            istemci_jetonu = jeton, conn = conn)
    harita_kaydi <- bs_harita_katalogu()[[meydan$harita]]
    dalgalar <- lapply(seq_len(harita_kaydi$dalga_sayisi), function(i) {
      list(dalga = i, olduruldu = 8L, sizinti = 0L, puan = 60,
           cekirdek = 20, kaynak = 150)
    })
    ozet <- list(
      sema = BS_SEMA_SURUMU, oyun_surumu = BS_OYUN_SURUMU,
      harita = meydan$harita, zorluk = meydan$zorluk, tohum = meydan$tohum,
      mod = "haftalik", dalga_ozetleri = dalgalar,
      son_dalga = harita_kaydi$dalga_sayisi, son_cekirdek = 20, zafer = TRUE,
      sure_saniye = sure, kullanilan_kahramanlar = list("emre"),
      olay_ozeti = list()
    )
    sonuc <- bs_db_finalize_run(uid, kosu$kosu_id, jeton, ozet, conn = conn)
    expect_true(sonuc$kabul)
    expect_true(bs_db_submit_challenge_entry(uid, sezon1$sezon_id,
                                             kosu$kosu_id, conn = conn))
    kosu$kosu_id
  }

  kosu_a <- girisEkle(101L, "hafta-a", 80)
  girisEkle(102L, "hafta-b", 75)

  # Aynı koşunun tekrar gönderimi hiçbir şeyi değiştirmez.
  expect_true(bs_db_submit_challenge_entry(101L, sezon1$sezon_id, kosu_a,
                                           conn = conn))
  giris_sayisi <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) AS n FROM MB_Game_ChallengeEntries")
  expect_identical(as.integer(giris_sayisi$n[1]), 2L)

  tablo <- bs_db_challenge_leaderboard(sezon1$sezon_id, user_id = 101L,
                                       conn = conn)
  expect_identical(tablo$toplam_katilimci, 2L)
  expect_length(tablo$ilkler, 2L)

  # Eşit puan/çekirdek/dalgada kısa süre üstte: 102 birinci olmalı.
  expect_identical(tablo$ilkler[[1]]$oyuncu, "Ömer Çelik")
  expect_identical(tablo$ilkler[[1]]$rumuz, "omer.c")
  expect_identical(tablo$ilkler[[1]]$departman, "Sistem Mühendisliği")
  expect_false(tablo$ilkler[[1]]$benim)
  expect_identical(tablo$ilkler[[2]]$oyuncu, "Gülşah Yıldız")
  expect_true(tablo$ilkler[[2]]$benim)
  expect_identical(tablo$benim_sira, 2L)
})

test_that("hafta dönümünde bitirilen haftalık koşu, BAŞLADIĞI sezona gönderilir", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  # Koşu, PAZAR gecesi (eski ISO hafta, W28) başlar.
  eski_meydan <- bs_haftalik_meydan_okuma(
    as.POSIXct("2026-07-12 23:50:00", tz = "Europe/Istanbul")
  )
  eski_sezon <- bs_db_get_or_create_season(eski_meydan, conn = conn)

  kosu <- bs_db_start_run(101L, eski_meydan$harita, eski_meydan$zorluk,
                          eski_meydan$tohum, mod = "haftalik",
                          sezon_id = eski_sezon$sezon_id,
                          istemci_jetonu = "hafta-donumu", conn = conn)

  harita_kaydi <- bs_harita_katalogu()[[eski_meydan$harita]]
  dalgalar <- lapply(seq_len(harita_kaydi$dalga_sayisi), function(i) {
    list(dalga = i, olduruldu = 8L, sizinti = 0L, puan = 60,
         cekirdek = 20, kaynak = 150)
  })
  ozet <- list(
    sema = BS_SEMA_SURUMU, oyun_surumu = BS_OYUN_SURUMU,
    harita = eski_meydan$harita, zorluk = eski_meydan$zorluk,
    tohum = eski_meydan$tohum, mod = "haftalik", dalga_ozetleri = dalgalar,
    son_dalga = harita_kaydi$dalga_sayisi, son_cekirdek = 20, zafer = TRUE,
    # Süre, sunucu saatine göre geçen (gerçek, ~0 saniye) süreye göre makul
    # kalmalı: >= dalga_sayisi*6 ve <= sunucu_gecen_saniye + 90.
    sure_saniye = 65, kullanilan_kahramanlar = list("emre"), olay_ozeti = list()
  )

  # Koşu PAZARTESİ sabahı (yeni ISO hafta, W29) sonuçlandırılır; "şimdiki"
  # hafta artık koşunun başladığı haftadan FARKLIDIR.
  yeni_meydan <- bs_haftalik_meydan_okuma(
    as.POSIXct("2026-07-13 00:10:00", tz = "Europe/Istanbul")
  )
  expect_false(identical(eski_meydan$hafta_kodu, yeni_meydan$hafta_kodu))
  yeni_sezon <- bs_db_get_or_create_season(yeni_meydan, conn = conn)
  expect_false(identical(eski_sezon$sezon_id, yeni_sezon$sezon_id))

  sonuc <- bs_db_finalize_run(101L, kosu$kosu_id, "hafta-donumu", ozet, conn = conn)
  expect_true(sonuc$kabul)
  # Sonuç, koşunun BAŞLADIĞI (eski) sezonu taşımalı; "şimdiki" sezonu değil.
  expect_identical(sonuc$sezon_id, eski_sezon$sezon_id)

  istek <- list(mod = "haftalik")
  paket <- .bs_srv_bitirme_sonrasi(101L, kosu$kosu_id, istek, sonuc, conn = conn)
  expect_true(paket$kabul)
  # Regresyon: liderlik paketi "şimdiki" sezonu DEĞİL, koşunun gerçek
  # sezonunu yansıtmalı; aksi halde skor liderlik tablosuna hiç ulaşmaz.
  expect_identical(paket$sezon$sezon_id, eski_sezon$sezon_id)

  giris <- DBI::dbGetQuery(
    conn,
    "SELECT ChallengeSeasonID FROM MB_Game_ChallengeEntries WHERE GameRunID = ?",
    params = list(kosu$kosu_id)
  )
  expect_identical(nrow(giris), 1L)
  expect_identical(as.integer(giris$ChallengeSeasonID[1]), eski_sezon$sezon_id)

  # "Şimdiki" (yeni) sezonun liderlik tablosunda bu koşu YOKTUR.
  yeni_liderlik <- bs_db_challenge_leaderboard(yeni_sezon$sezon_id, conn = conn)
  expect_identical(yeni_liderlik$toplam_katilimci, 0L)

  # Koşunun gerçek (eski) sezonunun liderlik tablosunda bu koşu VARDIR.
  eski_liderlik <- bs_db_challenge_leaderboard(eski_sezon$sezon_id, conn = conn)
  expect_identical(eski_liderlik$toplam_katilimci, 1L)
})

test_that("liderlik tablosu 500 kaydı kırpmadan ÖNCE sıralar (en yüksek puan kaybolmaz)", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  meydan <- bs_haftalik_meydan_okuma(
    as.POSIXct("2026-07-15 12:00:00", tz = "Europe/Istanbul")
  )
  sezon <- bs_db_get_or_create_season(meydan, conn = conn)

  # 600 giriş doğrudan eklenir (gerçek koşu akışını atlayarak hızlı kurulum).
  # Sorgunun ORDER BY içermemesi nedeniyle satırlar ekleme (rowid) sırasıyla
  # döner; en yüksek puanlı giriş BİLEREK en sona eklenir. Düzeltme öncesi
  # kod sıralamadan önce ilk 500 satırı aldığından bu girişi tamamen
  # kaybederdi ve hem "ilkler" hem de "benim_sira" yanlış çıkardı.
  n <- 600L
  girisler_df <- data.frame(
    ChallengeSeasonID = rep(as.integer(sezon$sezon_id), n),
    UserID = seq.int(1000L, 1000L + n - 1L),
    GameRunID = seq_len(n),
    Score = c(seq.int(1L, n - 1L), 999999L),
    CoreHealth = rep(15, n),
    FinalWave = rep(8L, n),
    DurationSeconds = rep(300, n),
    SubmittedAt = rep("2026-07-15 12:00:00", n),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(conn, "MB_Game_ChallengeEntries", girisler_df)

  en_yuksek_uid <- 1000L + n - 1L
  tablo <- bs_db_challenge_leaderboard(sezon$sezon_id, user_id = en_yuksek_uid,
                                       conn = conn)

  expect_identical(tablo$toplam_katilimci, 600L)
  expect_identical(tablo$benim_sira, 1L)
  expect_length(tablo$ilkler, 20L)  # varsayılan sayfa boyutu (limit)
  expect_identical(tablo$ilkler[[1]]$puan, 999999)
  expect_true(tablo$ilkler[[1]]$benim)

  orta_uid <- 1000L + 520L
  orta_tablo <- bs_db_challenge_leaderboard(sezon$sezon_id, user_id = orta_uid,
                                            conn = conn)
  # Regresyon: kullanıcı ilk gösterim penceresinin dışında kalsa bile tam
  # sıralamadaki yeri ve yakın çevresi kaybolmamalıdır.
  expect_identical(orta_tablo$toplam_katilimci, 600L)
  expect_false(is.null(orta_tablo$benim_sira))
  expect_true(any(vapply(orta_tablo$yakinlar, function(x) isTRUE(x$benim), logical(1))))

})

test_that("topluluk katkısı koşu bazında idempotenttir ve toplamlar doğru", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 42L,
                          istemci_jetonu = "top-a", conn = conn)
  sonuc <- bs_db_finalize_run(101L, kosu$kosu_id, "top-a",
                              .bs_test_db_ozet(42L), conn = conn)
  expect_true(sonuc$kabul)

  hafta <- "2026-W29"
  expect_true(bs_db_add_community_contribution(101L, kosu$kosu_id, hafta,
                                               etkisizlestirilen = 64L,
                                               conn = conn))
  # Aynı koşu ikinci kez katkı yazamaz.
  expect_true(bs_db_add_community_contribution(101L, kosu$kosu_id, hafta,
                                               etkisizlestirilen = 64L,
                                               conn = conn))
  n <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) AS n FROM MB_Game_CommunityContributions")
  expect_identical(as.integer(n$n[1]), 1L)

  # Sonuçlanmamış koşu katkı yazamaz.
  acik <- bs_db_start_run(101L, "baglam_kapisi", "normal", 43L,
                          istemci_jetonu = "top-b", conn = conn)
  expect_false(bs_db_add_community_contribution(101L, acik$kosu_id, hafta,
                                                conn = conn))

  toplam <- bs_db_community_totals(hafta, user_id = 101L, conn = conn)
  expect_identical(toplam$katilimci, 1)
  expect_identical(toplam$etkisizlestirilen, 64)
  expect_identical(toplam$savunulan_dalga, 8)
  expect_identical(toplam$benim$etkisizlestirilen, 64)
})

test_that("plan yayınlama doğrulanır, Türkçe başlık korunur ve sahibi siler", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 55L,
                          istemci_jetonu = "plan-a", conn = conn)
  sonuc <- bs_db_finalize_run(101L, kosu$kosu_id, "plan-a",
                              .bs_test_db_ozet(55L), conn = conn)
  expect_true(sonuc$kabul)

  plan <- list(
    sema = BS_SEMA_SURUMU, harita = "baglam_kapisi", zorluk = "normal",
    tohum = 55L, baslik = "Güneydoğu Köşe Hattı",
    yerlesimler = list(
      list(kahraman = "emre", x = 4L, y = 3L, seviye = 2L, dalga = 1L)
    )
  )

  # Koşunun gerçek üçlüsüyle uyuşmayan plan reddedilir.
  bozuk <- plan; bozuk$tohum <- 999L
  expect_null(bs_db_publish_blueprint(101L, kosu$kosu_id,
                                      "Deneme", bozuk, conn = conn))

  plan_id <- bs_db_publish_blueprint(101L, kosu$kosu_id,
                                     "Güneydoğu Köşe Hattı", plan, conn = conn)
  expect_true(is.integer(plan_id) && plan_id > 0L)

  liste <- bs_db_list_blueprints(user_id = 102L, conn = conn)
  expect_length(liste, 1L)
  expect_identical(liste[[1]]$baslik, "Güneydoğu Köşe Hattı")
  expect_identical(liste[[1]]$yaratici, "Gülşah Yıldız")
  expect_identical(liste[[1]]$yaratici_departman, "Yazılım Müdürlüğü")
  expect_false(liste[[1]]$benim)

  yuk <- bs_db_get_blueprint(plan_id, conn = conn)
  expect_identical(yuk$harita, "baglam_kapisi")
  expect_identical(yuk$tohum, 55L)
  expect_identical(yuk$plan$yerlesimler[[1]]$kahraman, "emre")

  # Yalnızca sahibi silebilir; silinen plan listeden ve okumadan düşer.
  expect_false(bs_db_soft_delete_blueprint(102L, plan_id, conn = conn))
  expect_true(bs_db_soft_delete_blueprint(101L, plan_id, conn = conn))
  expect_length(bs_db_list_blueprints(user_id = 101L, conn = conn), 0L)
  expect_null(bs_db_get_blueprint(plan_id, conn = conn))
})

test_that("koşu bırakma yalnızca sahibinin aktif koşusunu kapatır", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 66L,
                          istemci_jetonu = "birak-a", conn = conn)
  expect_false(bs_db_abandon_run(102L, kosu$kosu_id, conn = conn))
  expect_true(bs_db_abandon_run(101L, kosu$kosu_id, conn = conn))
  expect_false(bs_db_abandon_run(101L, kosu$kosu_id, conn = conn))
  expect_null(bs_db_active_run(101L, conn = conn))
})

test_that("sonuçlandırma durum geçişini Aktif koşuluyla iddia eder; eşzamanlı ele geçirmede ödül tekrar uygulanmaz", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 321L,
                          istemci_jetonu = "jeton-yaris", conn = conn)
  ozet <- .bs_test_db_ozet(321L)

  gercek_dogrula <- bs_kosu_ozeti_dogrula
  on.exit(assign("bs_kosu_ozeti_dogrula", gercek_dogrula, envir = globalenv()),
          add = TRUE)
  # bs_kosu_ozeti_dogrula() normal biçimde geçerli bir sonuç üretir, ancak
  # yan etki olarak AYNI bağlantı/transaction üzerinde satırı eşzamanlı bir
  # "kazanan" sonuçlandırma isteği gibi ÖNCEDEN Tamamlandı yapar (tek
  # bağlantı üzerinden yarış durumunu deterministik biçimde simüle eder;
  # bkz. "yeni koşu eklemesi başarısız olursa..." testindeki NOT NULL
  # kısıt tekniği ile aynı yaklaşım). Gerçek kod bu durumu
  # WHERE ... AND Status = 'Aktif' koşuluyla yakalamalı ve ödülleri
  # (kampanya/kahraman/profil/başarım) TEKRAR uygulamak yerine artık
  # sonuçlanmış satırı idempotent olarak döndürmelidir.
  assign("bs_kosu_ozeti_dogrula", function(...) {
    DBI::dbExecute(
      conn,
      paste(
        "UPDATE MB_Game_Runs SET Status = 'Tamamlandı', Score = 7,",
        "Stars = 1, XPEarned = 2, FinalWave = 1, CoreHealth = 5,",
        "DurationSeconds = 10 WHERE GameRunID = ?"
      ),
      params = list(kosu$kosu_id)
    )
    gercek_dogrula(...)
  }, envir = globalenv())

  sonuc <- bs_db_finalize_run(101L, kosu$kosu_id, "jeton-yaris", ozet, conn = conn)

  expect_true(sonuc$kabul)
  expect_true(sonuc$tekrar)
  # Sunucunun asıl doğrulama/ödül hesabı (1480 puan) değil, "kazanan"
  # eşzamanlı isteğin satıra yazdığı sentinel değerler dönmelidir.
  expect_identical(sonuc$puan, 7L)
  expect_identical(sonuc$yildiz, 1L)
  expect_identical(sonuc$xp, 2L)

  # Kampanya/kahraman/profil ilerlemesi İKİNCİ KEZ yazılmamış olmalı.
  profil <- bs_db_get_or_create_profile(101L, conn = conn)
  expect_identical(profil$xp, 0L)
  bundle <- bs_db_load_profile_bundle(101L, conn = conn)
  expect_identical(nrow(bundle$kampanya), 0L)
  expect_identical(nrow(bundle$kahramanlar), 0L)
})

test_that("haftalık koşudan savunma planı yayınlanamaz (değiştirici planla taşınmaz)", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  meydan <- bs_haftalik_meydan_okuma(
    as.POSIXct("2026-07-15 12:00:00", tz = "Europe/Istanbul")
  )
  sezon <- bs_db_get_or_create_season(meydan, conn = conn)

  kosu <- bs_db_start_run(101L, meydan$harita, meydan$zorluk, meydan$tohum,
                          mod = "haftalik", sezon_id = sezon$sezon_id,
                          istemci_jetonu = "haftalik-plan", conn = conn)
  harita_kaydi <- bs_harita_katalogu()[[meydan$harita]]
  dalgalar <- lapply(seq_len(harita_kaydi$dalga_sayisi), function(i) {
    list(dalga = i, olduruldu = 8L, sizinti = 0L, puan = 60,
         cekirdek = 20, kaynak = 150)
  })
  ozet <- list(
    sema = BS_SEMA_SURUMU, oyun_surumu = BS_OYUN_SURUMU,
    harita = meydan$harita, zorluk = meydan$zorluk, tohum = meydan$tohum,
    mod = "haftalik", dalga_ozetleri = dalgalar,
    son_dalga = harita_kaydi$dalga_sayisi, son_cekirdek = 20, zafer = TRUE,
    sure_saniye = 90, kullanilan_kahramanlar = list("emre"), olay_ozeti = list()
  )
  sonuc <- bs_db_finalize_run(101L, kosu$kosu_id, "haftalik-plan", ozet, conn = conn)
  expect_true(sonuc$kabul)

  plan <- list(
    sema = BS_SEMA_SURUMU, harita = meydan$harita, zorluk = meydan$zorluk,
    tohum = meydan$tohum, baslik = "Haftalık Plan",
    yerlesimler = list(list(kahraman = "emre", x = 2L, y = 2L, seviye = 1L, dalga = 1L))
  )
  # Regresyon: haftalık koşunun değiştiricisi plana taşınmaz (plan/deneme
  # modu hiç değiştirici uygulamaz); yaratıcının değiştiriciyle elde ettiği
  # sonuçla haksız kıyaslamayı önlemek için yayın tamamen reddedilir.
  expect_null(bs_db_publish_blueprint(101L, kosu$kosu_id, "Haftalık Plan",
                                      plan, conn = conn))
  expect_length(bs_db_list_blueprints(conn = conn), 0L)

  # Normal (kampanya) koşulu yayın hâlâ çalışır (regresyon değil).
  kampanya_kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 707L,
                                   istemci_jetonu = "kampanya-plan", conn = conn)
  kampanya_sonuc <- bs_db_finalize_run(101L, kampanya_kosu$kosu_id,
                                       "kampanya-plan", .bs_test_db_ozet(707L),
                                       conn = conn)
  expect_true(kampanya_sonuc$kabul)
  kampanya_plan <- list(
    sema = BS_SEMA_SURUMU, harita = "baglam_kapisi", zorluk = "normal",
    tohum = 707L, baslik = "Kampanya Planı",
    yerlesimler = list(list(kahraman = "emre", x = 2L, y = 2L, seviye = 1L, dalga = 1L))
  )
  kampanya_plan_id <- bs_db_publish_blueprint(101L, kampanya_kosu$kosu_id,
                                              "Kampanya Planı", kampanya_plan,
                                              conn = conn)
  expect_true(is.integer(kampanya_plan_id) && kampanya_plan_id > 0L)
})

test_that("sezon kaydı ConfigJson'dan değiştiriciyi de döndürür (devam eden koşunun KENDİ sezonu)", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  meydan <- bs_haftalik_meydan_okuma(
    as.POSIXct("2026-07-15 12:00:00", tz = "Europe/Istanbul")
  )
  sezon <- bs_db_get_or_create_season(meydan, conn = conn)

  yeniden_okunan <- bs_db_get_season_by_id(sezon$sezon_id, conn = conn)
  expect_false(is.null(yeniden_okunan$degistirici))
  expect_identical(yeniden_okunan$degistirici$id, meydan$degistirici$id)
  expect_identical(yeniden_okunan$degistirici$ad, meydan$degistirici$ad)

  # Var olmayan sezon kimliği için hâlâ NULL döner (regresyon değil).
  expect_null(bs_db_get_season_by_id(999999L, conn = conn))
})

test_that("plan modunda devam isteği, plan silinmiş olsa bile aktif koşudan çözülür", {
  conn <- .bs_test_db_kur()
  on.exit({ DBI::dbDisconnect(conn); bs_db_reset_availability_cache() }, add = TRUE)

  # Bir plan yayınlanır; başka bir kullanıcı bu planı dener (mod=plan).
  kaynak_kosu <- bs_db_start_run(101L, "baglam_kapisi", "normal", 606L,
                                 istemci_jetonu = "plan-kaynak", conn = conn)
  kaynak_sonuc <- bs_db_finalize_run(101L, kaynak_kosu$kosu_id, "plan-kaynak",
                                     .bs_test_db_ozet(606L), conn = conn)
  expect_true(kaynak_sonuc$kabul)
  plan <- list(
    sema = BS_SEMA_SURUMU, harita = "baglam_kapisi", zorluk = "normal",
    tohum = 606L, baslik = "Deneme Planı",
    yerlesimler = list(list(kahraman = "emre", x = 1L, y = 1L, seviye = 1L, dalga = 1L))
  )
  plan_id <- bs_db_publish_blueprint(101L, kaynak_kosu$kosu_id, "Deneme Planı",
                                     plan, conn = conn)
  expect_true(is.integer(plan_id) && plan_id > 0L)

  # 102 numaralı kullanıcı planı dener; aktif (plan modlu) bir koşusu olur.
  deneme_kosu <- bs_db_start_run(102L, "baglam_kapisi", "normal", 606L,
                                 mod = "plan", plan_id = plan_id,
                                 istemci_jetonu = "plan-deneme", conn = conn)
  expect_false(is.null(deneme_kosu))

  # Deneme sürerken plan sahibi planı SİLER.
  expect_true(bs_db_soft_delete_blueprint(101L, plan_id, conn = conn))
  expect_null(bs_db_get_blueprint(plan_id, conn = conn))

  # .bs_srv_kosu_istegi_cozumle() içindeki bs_db_active_run()/
  # bs_db_get_blueprint() çağrıları conn parametresi almaz (üretimde
  # get_connection() kullanılır); bu testte enjekte edilen SQLite'a
  # yönlendirmek için geçici olarak forward edilirler. Enjekte edilen
  # bağlantı, çakışmayı önlemek için ayrı bir isimle (test_conn) kapatılır;
  # sarıcıların kendi `conn` parametresi bilerek gölgede bırakılmaz.
  test_conn <- conn
  eski_aktif <- bs_db_active_run
  eski_plan <- bs_db_get_blueprint
  on.exit({
    assign("bs_db_active_run", eski_aktif, envir = globalenv())
    assign("bs_db_get_blueprint", eski_plan, envir = globalenv())
  }, add = TRUE)
  assign("bs_db_active_run", function(user_id, conn = NULL) {
    eski_aktif(user_id, conn = test_conn)
  }, envir = globalenv())
  assign("bs_db_get_blueprint", function(plan_id, conn = NULL) {
    eski_plan(plan_id, conn = test_conn)
  }, envir = globalenv())

  # Regresyon: "Devam Et" isteği (kosu_id/istemci_jetonu düzleştirilmiş)
  # plan_bulunamadi ile reddedilmemeli; aktif koşudan (harita/zorluk/tohum/
  # plan_id) doğrudan çözülmelidir.
  istek_devam <- list(
    mod = "plan", plan_id = plan_id,
    kosu_id = deneme_kosu$kosu_id, istemci_jetonu = "plan-deneme"
  )
  cozum <- .bs_srv_kosu_istegi_cozumle(102L, istek_devam)
  expect_null(cozum$hata)
  expect_identical(cozum$harita, "baglam_kapisi")
  expect_identical(cozum$zorluk, "normal")
  expect_identical(cozum$tohum, 606L)
  expect_identical(cozum$plan_id, plan_id)

  # Karşılaştırma: plan_id/kosu_id OLMADAN (yeni bir plan denemesi gibi)
  # aynı silinmiş plana başvurmak hâlâ reddedilmelidir (normal davranış
  # korunur; yalnızca gerçek devam istekleri bu korumadan yararlanır).
  yeni_istek <- list(mod = "plan", plan_id = plan_id)
  cozum_yeni <- .bs_srv_kosu_istegi_cozumle(102L, yeni_istek)
  expect_identical(cozum_yeni$hata, "plan_bulunamadi")
})

test_that(".bs_srv_profil_yuku() ile .bs_srv_init_yuku() aynı ilerleme alanlarını üretir (bölünme sözleşmesi)", {
  eski_tablolar <- bs_db_tables_available
  eski_bundle <- bs_db_load_profile_bundle
  eski_devam <- bs_db_active_run
  on.exit({
    assign("bs_db_tables_available", eski_tablolar, envir = globalenv())
    assign("bs_db_load_profile_bundle", eski_bundle, envir = globalenv())
    assign("bs_db_active_run", eski_devam, envir = globalenv())
  }, add = TRUE)

  sahte_bundle <- list(
    profil = list(profil_id = 1L, seviye = 3L, xp = 500L,
                  toplam_puan = 4000L, ayarlar = list()),
    kampanya = data.frame(MapID = "baglam_kapisi", Difficulty = "normal",
                          Stars = 3L, BestScore = 1200L, HighestWave = 8L,
                          CompletedCount = 1L, LastPlayedAt = "2026-07-15",
                          stringsAsFactors = FALSE),
    kahramanlar = data.frame(HeroID = "emre", UsesCount = 2L, MasteryXP = 30L,
                             stringsAsFactors = FALSE),
    basarimlar = data.frame(ItemID = "ilk_zafer", ItemType = "basarim",
                            EarnedAt = "2026-07-15", stringsAsFactors = FALSE)
  )
  sahte_devam <- list(kosu_id = 7L, harita = "baglam_kapisi", zorluk = "normal",
                      mod = "kampanya", kontrol_dalga = 3L)

  assign("bs_db_tables_available", function(...) TRUE, envir = globalenv())
  assign("bs_db_load_profile_bundle", function(...) sahte_bundle, envir = globalenv())
  assign("bs_db_active_run", function(...) sahte_devam, envir = globalenv())

  profil_yuku <- .bs_srv_profil_yuku(101L)
  init_yuku <- .bs_srv_init_yuku(101L)

  for (alan in c("kalicilik", "profil", "kampanya", "kahraman_ilerlemesi",
                "basarimlar", "devam")) {
    expect_identical(init_yuku[[alan]], profil_yuku[[alan]], info = paste("alan:", alan))
  }
  expect_identical(profil_yuku$devam, sahte_devam)
  expect_identical(profil_yuku$profil$seviye, 3L)
  expect_length(profil_yuku$kampanya, 1L)
  expect_identical(profil_yuku$kampanya[[1]]$Stars, 3L)

  # init yükü ayrıca statik manifest alanlarını da taşımalı.
  expect_identical(init_yuku$etkin, TRUE)
  expect_false(is.null(init_yuku$surumler))
  expect_false(is.null(init_yuku$personalar))
  expect_false(is.null(init_yuku$haritalar))
  expect_false(is.null(init_yuku$haftalik))
})
