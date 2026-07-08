-- =============================================================================
-- Dosya Yolu: docs/sql/2026-07-ortak-oturumlar.sql
-- Açıklama: MERGEN Bilge "Ortak Oturumlar" (işbirlikçi çalışma odaları)
--           tabloları: ortak oturumlar, katılımcılar, davetler, canlı durum,
--           bildirimler, oda içi yazışma, yapay zekâ kuyruğu/aktif üretim
--           kilidi, ortak Bilge Yolaç oturum/çalıştırmaları, ortak belgeler,
--           kullanıcı belge kopyaları ve oturum olay günlüğü.
--
-- ÖNEMLİ OPERASYON NOTLARI:
--   * Bu betik UYGULAMA AÇILIŞINDA OTOMATİK ÇALIŞTIRILMAZ. Yalnızca DBA /
--     operatör tarafından SSMS üzerinden, DOĞRULANMIŞ DB yedeği alındıktan
--     sonra manuel uygulanır (bkz. RUNBOOK.md "Ortak Oturumlar tabloları").
--   * Betik idempotenttir: tablolar/indeksler zaten varsa hiçbir şey yapmaz,
--     mevcut veriyi DEĞİŞTİRMEZ ve SİLMEZ (yıkıcı ifade içermez).
--   * Mevcut PK/constraint'lere DOKUNMAZ; MB_Chats / MB_Messages /
--     MB_Users / MB_ClaudeCode_* tablolarında hiçbir değişiklik yapmaz.
--   * Mevcut üretim şemasıyla uyum için MB_Users(UserID) ile ilişki kuran
--     bütün kullanıcı FK kolonları INT olarak tanımlanmıştır. SQL Server FK
--     kolonunda INT -> BIGINT tür eşleşmesine izin vermez.
--   * İş kuralı değerleri (rol, durum, mesaj türü, hedef, dosya durumu vb.)
--     TÜRKÇE NVARCHAR sabitleridir ve N'...' önekiyle yazılır. İngilizce
--     durum değeri (owner/pending/completed vb.) SAKLANMAZ.
--   * Kişisel geçmiş ile ortak geçmiş kasıtlı olarak AYRIDIR: bu tablolar
--     MB_Chats/MB_Messages ve MB_ClaudeCode_* ailesine yazmaz.
--   * Bu tablolara gizli değer (API anahtarı, token, ortam değişkeni, ham
--     kimlik bilgisi) veya ikili dosya içeriği YAZILMAZ; ortak belgeler için
--     yalnızca metadata (ad, yol, boyut, hash) saklanır; içerik disktedir.
--   * Türkçe metin bütünlüğü uygulama tarafındaki merkezi DB encoding
--     yardımcıları (normalize_db_visible_value / normalize_db_technical_value
--     / normalize_db_params) ile korunur. DB_CLIENT_ENCODING=WINDOWS-1254
--     üretim sözleşmesi değişmez.
--   * Geri alma betiği: docs/sql/2026-07-ortak-oturumlar-rollback.sql
-- =============================================================================

SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;
GO

-- 0) Ön koşul: mevcut kullanıcı anahtarı tipi ---------------------------------
-- Üretim DB'de MB_Users.UserID INT olduğu için tüm kullanıcı FK kolonları INT
-- olmalıdır. SQL Server FK kolonunda INT -> BIGINT eşleşmesine izin vermez.
IF OBJECT_ID(N'dbo.MB_Users', N'U') IS NULL
BEGIN
    THROW 51000, 'Ön koşul başarısız: dbo.MB_Users tablosu bulunamadı. Ortak Oturumlar kurulumu durduruldu.', 1;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.columns c
    JOIN sys.types ty ON ty.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'dbo.MB_Users')
      AND c.name = N'UserID'
      AND ty.name = N'int'
)
BEGIN
    THROW 51001, 'Ön koşul başarısız: dbo.MB_Users.UserID tipi INT değil. Kullanıcı FK kolonları mevcut UserID tipiyle birebir eşleşmelidir.', 1;
END;
GO

-- 1) Ortak oturum başlık tablosu ----------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturumlar', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturumlar (
        OrtakOturumID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        KaynakTuru NVARCHAR(50) NOT NULL,
        KaynakID BIGINT NULL,
        Baslik NVARCHAR(500) NULL,
        OlusturanKullaniciID INT NOT NULL,
        OturumDurumu NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_OrtakOturumlar_OturumDurumu DEFAULT N'Aktif',
        PaylasimBaslangicTipi NVARCHAR(100) NULL,
        SonEtkinlikZamani DATETIME2(0) NULL,
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakOturumlar_OlusturmaZamani DEFAULT SYSUTCDATETIME(),
        GuncellemeZamani DATETIME2(0) NULL,
        MetaJson NVARCHAR(MAX) NULL,
        CONSTRAINT CK_MB_OrtakOturumlar_KaynakTuru CHECK (KaynakTuru IN (N'NormalSohbet', N'BilgeYolaç')),
        CONSTRAINT CK_MB_OrtakOturumlar_OturumDurumu CHECK (OturumDurumu IN (N'Aktif', N'Arşivlendi', N'Kapandı')),
        CONSTRAINT FK_MB_OrtakOturumlar_Olusturan FOREIGN KEY (OlusturanKullaniciID) REFERENCES dbo.MB_Users(UserID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_OrtakOturumlar_Kaynak_Recent'
      AND object_id = OBJECT_ID(N'dbo.MB_OrtakOturumlar')
)
BEGIN
    CREATE INDEX IX_MB_OrtakOturumlar_Kaynak_Recent
    ON dbo.MB_OrtakOturumlar (KaynakTuru, OturumDurumu, SonEtkinlikZamani DESC, OlusturmaZamani DESC);
END;
GO

-- 1b) SecilenPersona kolonu (aşamalı devreye alma): odanın etkin yapay zekâ
-- personasını tutar (emre/selin/deniz/can/ipek). Kurulu olmayan şemada
-- uygulama sessizce güvenli düşer ve oturum kimliğinden deterministik varsayılan
-- persona kullanır (bkz. ortak_oturum_persona_kimligi). Idempotent ALTER.
IF OBJECT_ID(N'dbo.MB_OrtakOturumlar', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.MB_OrtakOturumlar', N'SecilenPersona') IS NULL
BEGIN
    ALTER TABLE dbo.MB_OrtakOturumlar
        ADD SecilenPersona NVARCHAR(50) NULL;
END;
GO

-- 2) Katılımcılar ---------------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Katilimcilar', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturum_Katilimcilar (
        KatilimciID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakOturumID BIGINT NOT NULL,
        KullaniciID INT NOT NULL,
        Rol NVARCHAR(50) NOT NULL,
        KatilimDurumu NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_OrtakKatilim_KatilimDurumu DEFAULT N'DavetEdildi',
        KullaniciGorunumDurumu NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_OrtakKatilim_Gorunum DEFAULT N'Görünüyor',
        DavetEdenKullaniciID INT NULL,
        DavetZamani DATETIME2(0) NULL,
        KatilmaZamani DATETIME2(0) NULL,
        SonGorulmeZamani DATETIME2(0) NULL,
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakKatilim_Olusturma DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_MB_OrtakKatilim_Oturum_Kullanici UNIQUE (OrtakOturumID, KullaniciID),
        CONSTRAINT CK_MB_OrtakKatilim_Rol CHECK (Rol IN (N'Sahip', N'OturumYöneticisi', N'Katılımcı', N'İzleyici')),
        CONSTRAINT CK_MB_OrtakKatilim_Durum CHECK (KatilimDurumu IN (N'DavetEdildi', N'Katıldı', N'Reddetti', N'Çıkarıldı', N'Ayrıldı')),
        CONSTRAINT CK_MB_OrtakKatilim_Gorunum CHECK (KullaniciGorunumDurumu IN (N'Görünüyor', N'KullanıcıArşivledi', N'Ayrıldı')),
        CONSTRAINT FK_MB_OrtakKatilim_Oturum FOREIGN KEY (OrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID),
        CONSTRAINT FK_MB_OrtakKatilim_Kullanici FOREIGN KEY (KullaniciID) REFERENCES dbo.MB_Users(UserID),
        CONSTRAINT FK_MB_OrtakKatilim_DavetEden FOREIGN KEY (DavetEdenKullaniciID) REFERENCES dbo.MB_Users(UserID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_OrtakKatilim_Kullanici_Liste'
      AND object_id = OBJECT_ID(N'dbo.MB_OrtakOturum_Katilimcilar')
)
BEGIN
    CREATE INDEX IX_MB_OrtakKatilim_Kullanici_Liste
    ON dbo.MB_OrtakOturum_Katilimcilar (KullaniciID, KatilimDurumu, KullaniciGorunumDurumu, OrtakOturumID);
END;
GO

-- 3) Davetler -------------------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Davetler', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturum_Davetler (
        DavetID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakOturumID BIGINT NOT NULL,
        DavetEdilenKullaniciID INT NULL,
        DavetEdilenEposta NVARCHAR(320) NULL,
        DavetEdenKullaniciID INT NOT NULL,
        Rol NVARCHAR(50) NOT NULL,
        DavetYontemi NVARCHAR(50) NOT NULL,
        DavetDurumu NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_OrtakDavet_Durum DEFAULT N'Bekliyor',
        DavetMesaji NVARCHAR(MAX) NULL,
        DavetTokenHash NVARCHAR(256) NULL,
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakDavet_Olusturma DEFAULT SYSUTCDATETIME(),
        SonGonderimZamani DATETIME2(0) NULL,
        KabulZamani DATETIME2(0) NULL,
        SonCevapZamani DATETIME2(0) NULL,
        GecerlilikBitisZamani DATETIME2(0) NULL,
        CONSTRAINT CK_MB_OrtakDavet_Rol CHECK (Rol IN (N'Sahip', N'OturumYöneticisi', N'Katılımcı', N'İzleyici')),
        CONSTRAINT CK_MB_OrtakDavet_Yontem CHECK (DavetYontemi IN (N'Mergenİçi', N'Eposta', N'MergenİçiVeEposta')),
        CONSTRAINT CK_MB_OrtakDavet_Durum CHECK (DavetDurumu IN (N'Bekliyor', N'Katıldı', N'Reddetti', N'SüresiDoldu', N'İptalEdildi')),
        CONSTRAINT FK_MB_OrtakDavet_Oturum FOREIGN KEY (OrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID),
        CONSTRAINT FK_MB_OrtakDavet_DavetEdilen FOREIGN KEY (DavetEdilenKullaniciID) REFERENCES dbo.MB_Users(UserID),
        CONSTRAINT FK_MB_OrtakDavet_DavetEden FOREIGN KEY (DavetEdenKullaniciID) REFERENCES dbo.MB_Users(UserID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_OrtakDavet_Alici_Durum'
      AND object_id = OBJECT_ID(N'dbo.MB_OrtakOturum_Davetler')
)
BEGIN
    CREATE INDEX IX_MB_OrtakDavet_Alici_Durum
    ON dbo.MB_OrtakOturum_Davetler (DavetEdilenKullaniciID, DavetDurumu, OlusturmaZamani DESC);
END;
GO

-- 4) Kullanıcı canlı durum (kalp atışı) ------------------------------------------
IF OBJECT_ID(N'dbo.MB_Kullanici_CanliDurum', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Kullanici_CanliDurum (
        CanliDurumID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        KullaniciID INT NOT NULL,
        OturumAnahtari NVARCHAR(128) NOT NULL,
        Sayfa NVARCHAR(200) NULL,
        SonKalpAtisiZamani DATETIME2(0) NOT NULL,
        Durum NVARCHAR(50) NOT NULL,
        SonGorulenOrtakOturumID BIGINT NULL,
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_CanliDurum_Olusturma DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_MB_CanliDurum_Kullanici_Oturum UNIQUE (KullaniciID, OturumAnahtari),
        CONSTRAINT CK_MB_CanliDurum_Durum CHECK (Durum IN (N'Çevrimİçi', N'Boşta', N'ÇevrimDışı')),
        CONSTRAINT FK_MB_CanliDurum_Kullanici FOREIGN KEY (KullaniciID) REFERENCES dbo.MB_Users(UserID),
        CONSTRAINT FK_MB_CanliDurum_OrtakOturum FOREIGN KEY (SonGorulenOrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_CanliDurum_SonKalpAtisi'
      AND object_id = OBJECT_ID(N'dbo.MB_Kullanici_CanliDurum')
)
BEGIN
    CREATE INDEX IX_MB_CanliDurum_SonKalpAtisi
    ON dbo.MB_Kullanici_CanliDurum (SonKalpAtisiZamani DESC, Durum, KullaniciID);
END;
GO

-- 5) Uygulama içi bildirimler -----------------------------------------------------
IF OBJECT_ID(N'dbo.MB_Bildirimler', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Bildirimler (
        BildirimID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        AliciKullaniciID INT NOT NULL,
        GonderenKullaniciID INT NULL,
        BildirimTuru NVARCHAR(80) NOT NULL,
        Baslik NVARCHAR(300) NOT NULL,
        Mesaj NVARCHAR(MAX) NULL,
        IlgiliOturumID BIGINT NULL,
        OkunduMu BIT NOT NULL CONSTRAINT DF_MB_Bildirimler_Okundu DEFAULT 0,
        Durum NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_Bildirimler_Durum DEFAULT N'Bekliyor',
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_Bildirimler_Olusturma DEFAULT SYSUTCDATETIME(),
        OkunmaZamani DATETIME2(0) NULL,
        CONSTRAINT CK_MB_Bildirimler_Tur CHECK (BildirimTuru IN (N'OrtakOturumDavet', N'OrtakOturumÇağrı', N'BelgeKaydetmeİsteği')),
        CONSTRAINT CK_MB_Bildirimler_Durum CHECK (Durum IN (N'Bekliyor', N'KabulEdildi', N'Reddedildi', N'SüresiDoldu')),
        CONSTRAINT FK_MB_Bildirimler_Alici FOREIGN KEY (AliciKullaniciID) REFERENCES dbo.MB_Users(UserID),
        CONSTRAINT FK_MB_Bildirimler_Gonderen FOREIGN KEY (GonderenKullaniciID) REFERENCES dbo.MB_Users(UserID),
        CONSTRAINT FK_MB_Bildirimler_Oturum FOREIGN KEY (IlgiliOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Bildirimler_Alici_Bekleyen'
      AND object_id = OBJECT_ID(N'dbo.MB_Bildirimler')
)
BEGIN
    CREATE INDEX IX_MB_Bildirimler_Alici_Bekleyen
    ON dbo.MB_Bildirimler (AliciKullaniciID, OkunduMu, Durum, OlusturmaZamani DESC);
END;
GO

-- 6) Ortak oturum mesajları --------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Mesajlar', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturum_Mesajlar (
        OrtakMesajID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakOturumID BIGINT NOT NULL,
        GonderenKullaniciID INT NULL,
        MesajTuru NVARCHAR(80) NOT NULL,
        Hedef NVARCHAR(80) NOT NULL,
        MesajMetni NVARCHAR(MAX) NULL,
        BagliMesajID BIGINT NULL,
        MesajSirasi BIGINT NOT NULL,
        LLMGonderildiMi BIT NOT NULL CONSTRAINT DF_MB_OrtakMesaj_LLM DEFAULT 0,
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakMesaj_Olusturma DEFAULT SYSUTCDATETIME(),
        MetaJson NVARCHAR(MAX) NULL,
        CONSTRAINT UQ_MB_OrtakMesaj_Sira UNIQUE (OrtakOturumID, MesajSirasi),
        CONSTRAINT CK_MB_OrtakMesaj_Tur CHECK (MesajTuru IN (N'OdaMesajı', N'YapayZekaSorusu', N'YapayZekaYanıtı', N'SistemMesajı', N'BelgeBildirimi')),
        CONSTRAINT CK_MB_OrtakMesaj_Hedef CHECK (Hedef IN (N'Katılımcılar', N'YapayZeka')),
        CONSTRAINT FK_MB_OrtakMesaj_Oturum FOREIGN KEY (OrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID),
        CONSTRAINT FK_MB_OrtakMesaj_Gonderen FOREIGN KEY (GonderenKullaniciID) REFERENCES dbo.MB_Users(UserID),
        CONSTRAINT FK_MB_OrtakMesaj_Bagli FOREIGN KEY (BagliMesajID) REFERENCES dbo.MB_OrtakOturum_Mesajlar(OrtakMesajID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_OrtakMesaj_Oturum_Sira'
      AND object_id = OBJECT_ID(N'dbo.MB_OrtakOturum_Mesajlar')
)
BEGIN
    CREATE INDEX IX_MB_OrtakMesaj_Oturum_Sira
    ON dbo.MB_OrtakOturum_Mesajlar (OrtakOturumID, MesajSirasi ASC, OlusturmaZamani ASC);
END;
GO

-- 7) Yapay zekâ istek kuyruğu -------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturum_YapayZekaKuyrugu', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturum_YapayZekaKuyrugu (
        KuyrukID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakOturumID BIGINT NOT NULL,
        OrtakMesajID BIGINT NOT NULL,
        SiraNo BIGINT NOT NULL,
        Durum NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_OrtakAIKuyruk_Durum DEFAULT N'Bekliyor',
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakAIKuyruk_Olusturma DEFAULT SYSUTCDATETIME(),
        BaslamaZamani DATETIME2(0) NULL,
        BitisZamani DATETIME2(0) NULL,
        CONSTRAINT CK_MB_OrtakAIKuyruk_Durum CHECK (Durum IN (N'Bekliyor', N'Çalışıyor', N'Tamamlandı', N'İptalEdildi', N'Hata')),
        CONSTRAINT FK_MB_OrtakAIKuyruk_Oturum FOREIGN KEY (OrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID),
        CONSTRAINT FK_MB_OrtakAIKuyruk_Mesaj FOREIGN KEY (OrtakMesajID) REFERENCES dbo.MB_OrtakOturum_Mesajlar(OrtakMesajID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_OrtakAIKuyruk_Oturum_Durum'
      AND object_id = OBJECT_ID(N'dbo.MB_OrtakOturum_YapayZekaKuyrugu')
)
BEGIN
    CREATE INDEX IX_MB_OrtakAIKuyruk_Oturum_Durum
    ON dbo.MB_OrtakOturum_YapayZekaKuyrugu (OrtakOturumID, Durum, SiraNo ASC);
END;
GO

-- 8) Aktif üretim kilidi (oda başına tek yanıt üretimi) -----------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturum_AktifUretimler', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturum_AktifUretimler (
        OrtakOturumID BIGINT NOT NULL PRIMARY KEY,
        BaslatanKullaniciID INT NOT NULL,
        OrtakMesajID BIGINT NULL,
        IstekID NVARCHAR(128) NOT NULL,
        KilitDurumu NVARCHAR(50) NOT NULL,
        BaslamaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakAktifUretim_Baslama DEFAULT SYSUTCDATETIME(),
        GuncellemeZamani DATETIME2(0) NULL,
        CONSTRAINT CK_MB_OrtakAktifUretim_Durum CHECK (KilitDurumu IN (N'Çalışıyor', N'İptalEdildi', N'Tamamlandı', N'Hata')),
        CONSTRAINT FK_MB_OrtakAktifUretim_Oturum FOREIGN KEY (OrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID),
        CONSTRAINT FK_MB_OrtakAktifUretim_Kullanici FOREIGN KEY (BaslatanKullaniciID) REFERENCES dbo.MB_Users(UserID),
        CONSTRAINT FK_MB_OrtakAktifUretim_Mesaj FOREIGN KEY (OrtakMesajID) REFERENCES dbo.MB_OrtakOturum_Mesajlar(OrtakMesajID)
    );
END;
GO

-- 8b) Kısmi yanıt yayını (artımlı üretim ön izlemesi) --------------------------------
-- KismiYanit kolonu, süren üretimin token-token ön izlemesini tutar; tüm
-- katılımcılar yoklamayla görür. Idempotent: kolon yoksa eklenir. Uygulama
-- katmanı kolon yoksa güvenli düşer (tryCatch); bu ALTER opsiyonel iyileştirmedir.
IF OBJECT_ID(N'dbo.MB_OrtakOturum_AktifUretimler', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.MB_OrtakOturum_AktifUretimler', N'KismiYanit') IS NULL
BEGIN
    ALTER TABLE dbo.MB_OrtakOturum_AktifUretimler
        ADD KismiYanit NVARCHAR(MAX) NULL;
END;
GO

-- 9) Ortak Bilge Yolaç oturumları ----------------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakBilgeYolac_Oturumlar', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakBilgeYolac_Oturumlar (
        OrtakBilgeYolacOturumID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakOturumID BIGINT NOT NULL UNIQUE,
        OrtakCalismaDizini NVARCHAR(MAX) NULL,
        RuntimeDizini NVARCHAR(MAX) NULL,
        Model NVARCHAR(100) NULL,
        Karakter NVARCHAR(50) NULL,
        ClaudeCliSessionID NVARCHAR(200) NULL,
        OturumDurumu NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_OrtakBY_OturumDurumu DEFAULT N'Aktif',
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakBY_Olusturma DEFAULT SYSUTCDATETIME(),
        SonCalistirmaZamani DATETIME2(0) NULL,
        MetaJson NVARCHAR(MAX) NULL,
        CONSTRAINT CK_MB_OrtakBY_OturumDurumu CHECK (OturumDurumu IN (N'Aktif', N'Arşivlendi', N'Kapandı')),
        CONSTRAINT FK_MB_OrtakBY_Oturum FOREIGN KEY (OrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID)
    );
END;
GO

-- 10) Ortak Bilge Yolaç çalıştırmaları -----------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakBilgeYolac_Calistirmalar', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakBilgeYolac_Calistirmalar (
        OrtakCalistirmaID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakBilgeYolacOturumID BIGINT NOT NULL,
        KomutuVerenKullaniciID INT NOT NULL,
        Komut NVARCHAR(MAX) NOT NULL,
        NihaiYanit NVARCHAR(MAX) NULL,
        Durum NVARCHAR(50) NOT NULL,
        UretilenDosyalarJson NVARCHAR(MAX) NULL,
        HamAkisJsonl NVARCHAR(MAX) NULL,
        AracKullanimlariJson NVARCHAR(MAX) NULL,
        CalistirmaSirasi INT NOT NULL,
        ExitCode INT NULL,
        SureSaniye DECIMAL(10,2) NULL,
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakBYCalisma_Olusturma DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_MB_OrtakBYCalisma_Sira UNIQUE (OrtakBilgeYolacOturumID, CalistirmaSirasi),
        CONSTRAINT CK_MB_OrtakBYCalisma_Durum CHECK (Durum IN (N'Çalışıyor', N'Tamamlandı', N'Başarısız', N'Durduruldu')),
        CONSTRAINT FK_MB_OrtakBYCalisma_Oturum FOREIGN KEY (OrtakBilgeYolacOturumID) REFERENCES dbo.MB_OrtakBilgeYolac_Oturumlar(OrtakBilgeYolacOturumID),
        CONSTRAINT FK_MB_OrtakBYCalisma_Kullanici FOREIGN KEY (KomutuVerenKullaniciID) REFERENCES dbo.MB_Users(UserID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_OrtakBYCalisma_Oturum_Sira'
      AND object_id = OBJECT_ID(N'dbo.MB_OrtakBilgeYolac_Calistirmalar')
)
BEGIN
    CREATE INDEX IX_MB_OrtakBYCalisma_Oturum_Sira
    ON dbo.MB_OrtakBilgeYolac_Calistirmalar (OrtakBilgeYolacOturumID, CalistirmaSirasi ASC);
END;
GO

-- 11) Ortak oturum belgeleri ----------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Dosyalar', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturum_Dosyalar (
        OrtakDosyaID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakOturumID BIGINT NOT NULL,
        OrtakCalistirmaID BIGINT NULL,
        UretenKullaniciID INT NULL,
        DosyaAdi NVARCHAR(500) NOT NULL,
        DosyaYolu NVARCHAR(MAX) NOT NULL,
        DosyaTuru NVARCHAR(100) NULL,
        DosyaBoyutu BIGINT NULL,
        DosyaHash NVARCHAR(128) NULL,
        DosyaDurumu NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_OrtakDosya_Durum DEFAULT N'Üretildi',
        DosyaSahipligi NVARCHAR(80) NOT NULL CONSTRAINT DF_MB_OrtakDosya_Sahiplik DEFAULT N'OrtakOturumDosyası',
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakDosya_Olusturma DEFAULT SYSUTCDATETIME(),
        MetaJson NVARCHAR(MAX) NULL,
        CONSTRAINT CK_MB_OrtakDosya_Durum CHECK (DosyaDurumu IN (N'Üretildi', N'Silindi', N'ErişimKapatıldı')),
        CONSTRAINT CK_MB_OrtakDosya_Sahiplik CHECK (DosyaSahipligi IN (N'OrtakOturumDosyası', N'KullanıcıKopyası')),
        CONSTRAINT FK_MB_OrtakDosya_Oturum FOREIGN KEY (OrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID),
        CONSTRAINT FK_MB_OrtakDosya_Calistirma FOREIGN KEY (OrtakCalistirmaID) REFERENCES dbo.MB_OrtakBilgeYolac_Calistirmalar(OrtakCalistirmaID),
        CONSTRAINT FK_MB_OrtakDosya_Ureten FOREIGN KEY (UretenKullaniciID) REFERENCES dbo.MB_Users(UserID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_OrtakDosya_Oturum'
      AND object_id = OBJECT_ID(N'dbo.MB_OrtakOturum_Dosyalar')
)
BEGIN
    CREATE INDEX IX_MB_OrtakDosya_Oturum
    ON dbo.MB_OrtakOturum_Dosyalar (OrtakOturumID, DosyaDurumu, OlusturmaZamani DESC);
END;
GO

-- 12) Belge kullanıcı kopyaları --------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturum_DosyaKopyalari', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturum_DosyaKopyalari (
        DosyaKopyaID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakDosyaID BIGINT NOT NULL,
        KullaniciID INT NOT NULL,
        KullaniciDosyaYolu NVARCHAR(MAX) NULL,
        KopyalamaDurumu NVARCHAR(50) NOT NULL CONSTRAINT DF_MB_OrtakDosyaKopya_Durum DEFAULT N'Bekliyor',
        KopyalamaZamani DATETIME2(0) NULL,
        HataMesaji NVARCHAR(MAX) NULL,
        CONSTRAINT UQ_MB_OrtakDosyaKopya_Dosya_Kullanici UNIQUE (OrtakDosyaID, KullaniciID),
        CONSTRAINT CK_MB_OrtakDosyaKopya_Durum CHECK (KopyalamaDurumu IN (N'Bekliyor', N'Kopyalandı', N'Reddetti', N'Hata')),
        CONSTRAINT FK_MB_OrtakDosyaKopya_Dosya FOREIGN KEY (OrtakDosyaID) REFERENCES dbo.MB_OrtakOturum_Dosyalar(OrtakDosyaID),
        CONSTRAINT FK_MB_OrtakDosyaKopya_Kullanici FOREIGN KEY (KullaniciID) REFERENCES dbo.MB_Users(UserID)
    );
END;
GO

-- 13) Oturum olay günlüğü ----------------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Olaylar', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_OrtakOturum_Olaylar (
        OlayID BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrtakOturumID BIGINT NOT NULL,
        OlayTuru NVARCHAR(100) NOT NULL,
        TetikleyenKullaniciID INT NULL,
        PayloadJson NVARCHAR(MAX) NULL,
        OlusturmaZamani DATETIME2(0) NOT NULL CONSTRAINT DF_MB_OrtakOlay_Olusturma DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_MB_OrtakOlay_Tur CHECK (OlayTuru IN (
            N'KullanıcıKatıldı',
            N'KullanıcıAyrıldı',
            N'MesajEklendi',
            N'YanıtBaşladı',
            N'YanıtTamamlandı',
            N'BelgeÜretildi',
            N'BelgeKopyalandı',
            N'DavetGönderildi',
            N'DavetReddedildi',
            N'RolDeğişti',
            N'SahiplikDevredildi',
            N'OturumArşivlendi',
            N'OturumGeriYüklendi',
            N'GeçmişKopyalandı',
            N'OturumKapatıldı'
        )),
        CONSTRAINT FK_MB_OrtakOlay_Oturum FOREIGN KEY (OrtakOturumID) REFERENCES dbo.MB_OrtakOturumlar(OrtakOturumID),
        CONSTRAINT FK_MB_OrtakOlay_Kullanici FOREIGN KEY (TetikleyenKullaniciID) REFERENCES dbo.MB_Users(UserID)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_OrtakOlay_Oturum_Zaman'
      AND object_id = OBJECT_ID(N'dbo.MB_OrtakOturum_Olaylar')
)
BEGIN
    CREATE INDEX IX_MB_OrtakOlay_Oturum_Zaman
    ON dbo.MB_OrtakOturum_Olaylar (OrtakOturumID, OlusturmaZamani DESC);
END;
GO

-- 14) Doğrulama (bilgi amaçlı; hiçbir şey değiştirmez) ---------------------------------
SELECT
    t.name AS TableName,
    (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS ColumnCount
FROM sys.tables t
WHERE t.name IN (
    N'MB_OrtakOturumlar',
    N'MB_OrtakOturum_Katilimcilar',
    N'MB_OrtakOturum_Davetler',
    N'MB_Kullanici_CanliDurum',
    N'MB_Bildirimler',
    N'MB_OrtakOturum_Mesajlar',
    N'MB_OrtakOturum_YapayZekaKuyrugu',
    N'MB_OrtakOturum_AktifUretimler',
    N'MB_OrtakBilgeYolac_Oturumlar',
    N'MB_OrtakBilgeYolac_Calistirmalar',
    N'MB_OrtakOturum_Dosyalar',
    N'MB_OrtakOturum_DosyaKopyalari',
    N'MB_OrtakOturum_Olaylar'
)
ORDER BY t.name;
GO
