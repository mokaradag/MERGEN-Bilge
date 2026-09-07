-- =============================================================================
-- Dosya Yolu: docs/sql/2026-07-bilge-savunmasi.sql
-- Açıklama: Bilge Savunması (kule savunma oyunu) kalıcılık tabloları.
--
-- ÖNEMLİ OPERASYON NOTLARI:
--   * Bu betik UYGULAMA AÇILIŞINDA OTOMATİK ÇALIŞTIRILMAZ. Yalnızca DBA /
--     operatör tarafından SSMS üzerinden, DB yedeği alındıktan sonra manuel
--     uygulanır (bkz. RUNBOOK.md "Bilge Savunması tabloları" bölümü).
--   * Betik idempotenttir: tablolar/indeksler zaten varsa hiçbir şey yapmaz,
--     mevcut veriyi DEĞİŞTİRMEZ ve SİLMEZ (yıkıcı ifade içermez).
--   * MB_Game_* ailesi MB_Chats / MB_Messages / MB_ClaudeCode_* tablolarından
--     kasıtlı olarak AYRIDIR; oyun ilerlemesi sohbet şemasına yazılmaz.
--   * Kolon tipleri NVARCHAR'dır; Türkçe metin bütünlüğü uygulamanın merkezi
--     DB encoding yardımcılarıyla korunur. DB_CLIENT_ENCODING=WINDOWS-1254
--     üretim sözleşmesi değişmez.
--   * Bu tablolara gizli bilgi (API anahtarı, token, ortam değişkeni, dosya
--     içeriği) ve görsel ikili veri YAZILMAZ. JSON kolonları uygulama
--     tarafında boyut sınırına tabidir (koşu özeti ~60.000, kontrol noktası
--     ~40.000, plan ~20.000 karakter).
--   * Durum/mod değerleri Türkçedir: Status = Aktif / Tamamlandı / Yenilgi /
--     Bırakıldı / Reddedildi; Mode = kampanya / haftalik / plan.
--   * Geri alma betiği: docs/sql/2026-07-bilge-savunmasi-rollback.sql
-- =============================================================================

-- 1) Oyuncu profili ------------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_Profiles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_Profiles (
        GameProfileID BIGINT IDENTITY(1,1) PRIMARY KEY,
        UserID BIGINT NOT NULL,
        PlayerLevel INT NOT NULL DEFAULT 1,
        TotalXP INT NOT NULL DEFAULT 0,
        TotalScore BIGINT NOT NULL DEFAULT 0,
        SettingsJson NVARCHAR(4000) NULL,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedAt DATETIME2(0) NULL,
        CONSTRAINT UQ_MB_Game_Profiles_User UNIQUE (UserID)
    );
END;

-- 2) Kampanya ilerlemesi -------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_CampaignProgress', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_CampaignProgress (
        CampaignProgressID BIGINT IDENTITY(1,1) PRIMARY KEY,
        UserID BIGINT NOT NULL,
        MapID NVARCHAR(50) NOT NULL,
        Difficulty NVARCHAR(30) NOT NULL,
        Stars INT NOT NULL DEFAULT 0,
        BestScore BIGINT NOT NULL DEFAULT 0,
        HighestWave INT NOT NULL DEFAULT 0,
        CompletedCount INT NOT NULL DEFAULT 0,
        LastPlayedAt DATETIME2(0) NULL,
        CONSTRAINT UQ_MB_Game_CampaignProgress
            UNIQUE (UserID, MapID, Difficulty)
    );
END;

-- 3) Kahraman (persona) ilerlemesi ---------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_HeroProgress', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_HeroProgress (
        HeroProgressID BIGINT IDENTITY(1,1) PRIMARY KEY,
        UserID BIGINT NOT NULL,
        HeroID NVARCHAR(30) NOT NULL,
        UsesCount INT NOT NULL DEFAULT 0,
        MasteryXP INT NOT NULL DEFAULT 0,
        CONSTRAINT UQ_MB_Game_HeroProgress UNIQUE (UserID, HeroID)
    );
END;

-- 4) Koşu (run) kayıtları ------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_Runs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_Runs (
        GameRunID BIGINT IDENTITY(1,1) PRIMARY KEY,
        UserID BIGINT NOT NULL,
        MapID NVARCHAR(50) NOT NULL,
        Difficulty NVARCHAR(30) NOT NULL,
        Seed INT NOT NULL,
        Mode NVARCHAR(30) NOT NULL,
        ChallengeSeasonID BIGINT NULL,
        BlueprintID BIGINT NULL,
        GameVersion NVARCHAR(20) NULL,
        BalanceVersion NVARCHAR(20) NULL,
        SchemaVersion INT NULL,
        Status NVARCHAR(30) NOT NULL,
        ClientToken NVARCHAR(64) NOT NULL,
        StartedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        FinalizedAt DATETIME2(0) NULL,
        DurationSeconds DECIMAL(10,2) NULL,
        FinalWave INT NULL,
        CoreHealth DECIMAL(10,2) NULL,
        Score BIGINT NULL,
        Stars INT NULL,
        XPEarned INT NULL,
        RejectReason NVARCHAR(100) NULL,
        ScoreDetailJson NVARCHAR(MAX) NULL,
        EventSummaryJson NVARCHAR(MAX) NULL,
        CONSTRAINT UQ_MB_Game_Runs_ClientToken UNIQUE (UserID, ClientToken)
    );
END;

-- Kullanıcının son koşuları ve aktif koşu araması için indeks.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Game_Runs_User_Status'
      AND object_id = OBJECT_ID(N'dbo.MB_Game_Runs')
)
BEGIN
    CREATE INDEX IX_MB_Game_Runs_User_Status
    ON dbo.MB_Game_Runs (UserID, Status, GameRunID DESC);
END;

-- 5) Koşu kontrol noktaları ----------------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_RunCheckpoints', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_RunCheckpoints (
        CheckpointID BIGINT IDENTITY(1,1) PRIMARY KEY,
        GameRunID BIGINT NOT NULL,
        WaveNumber INT NOT NULL,
        StateJson NVARCHAR(MAX) NOT NULL,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_MB_Game_RunCheckpoints UNIQUE (GameRunID, WaveNumber),
        CONSTRAINT FK_MB_Game_RunCheckpoints_Runs
            FOREIGN KEY (GameRunID) REFERENCES dbo.MB_Game_Runs(GameRunID)
    );
END;

-- 6) Başarımlar ve kalıcı açılımlar --------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_Achievements', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_Achievements (
        AchievementRowID BIGINT IDENTITY(1,1) PRIMARY KEY,
        UserID BIGINT NOT NULL,
        ItemID NVARCHAR(60) NOT NULL,
        ItemType NVARCHAR(20) NOT NULL,
        EarnedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_MB_Game_Achievements UNIQUE (UserID, ItemID)
    );
END;

-- 7) Haftalık meydan okuma sezonları -------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_ChallengeSeasons', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_ChallengeSeasons (
        ChallengeSeasonID BIGINT IDENTITY(1,1) PRIMARY KEY,
        WeekCode NVARCHAR(20) NOT NULL,
        MapID NVARCHAR(50) NOT NULL,
        Difficulty NVARCHAR(30) NOT NULL,
        Seed INT NOT NULL,
        ConfigJson NVARCHAR(2000) NULL,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_MB_Game_ChallengeSeasons_Week UNIQUE (WeekCode)
    );
END;

-- 8) Haftalık meydan okuma girişleri -------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_ChallengeEntries', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_ChallengeEntries (
        ChallengeEntryID BIGINT IDENTITY(1,1) PRIMARY KEY,
        ChallengeSeasonID BIGINT NOT NULL,
        UserID BIGINT NOT NULL,
        GameRunID BIGINT NOT NULL,
        Score BIGINT NOT NULL DEFAULT 0,
        CoreHealth DECIMAL(10,2) NOT NULL DEFAULT 0,
        FinalWave INT NOT NULL DEFAULT 0,
        DurationSeconds DECIMAL(10,2) NOT NULL DEFAULT 0,
        SubmittedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_MB_Game_ChallengeEntries UNIQUE (ChallengeSeasonID, UserID),
        CONSTRAINT FK_MB_Game_ChallengeEntries_Seasons
            FOREIGN KEY (ChallengeSeasonID)
            REFERENCES dbo.MB_Game_ChallengeSeasons(ChallengeSeasonID)
    );
END;

-- Liderlik tablosu okuma yolu için indeks (puan + eşitlik bozucular).
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Game_ChallengeEntries_Leaderboard'
      AND object_id = OBJECT_ID(N'dbo.MB_Game_ChallengeEntries')
)
BEGIN
    CREATE INDEX IX_MB_Game_ChallengeEntries_Leaderboard
    ON dbo.MB_Game_ChallengeEntries
        (ChallengeSeasonID, Score DESC, CoreHealth DESC, FinalWave DESC,
         DurationSeconds ASC);
END;

-- 9) Savunma planları (blueprint) ----------------------------------------------
IF OBJECT_ID(N'dbo.MB_Game_Blueprints', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_Blueprints (
        BlueprintID BIGINT IDENTITY(1,1) PRIMARY KEY,
        UserID BIGINT NOT NULL,
        GameRunID BIGINT NULL,
        MapID NVARCHAR(50) NOT NULL,
        Difficulty NVARCHAR(30) NOT NULL,
        Seed INT NOT NULL,
        Title NVARCHAR(200) NOT NULL,
        PayloadJson NVARCHAR(MAX) NOT NULL,
        SchemaVersion INT NOT NULL,
        CreatorResultJson NVARCHAR(1000) NULL,
        IsDeleted BIT NOT NULL DEFAULT 0,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;

-- Yayın listesi okuma yolu için indeks.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Game_Blueprints_Recent'
      AND object_id = OBJECT_ID(N'dbo.MB_Game_Blueprints')
)
BEGIN
    CREATE INDEX IX_MB_Game_Blueprints_Recent
    ON dbo.MB_Game_Blueprints (IsDeleted, BlueprintID DESC);
END;

-- Aynı koşudan yalnızca TEK aktif plan yayınlanabilir. Uygulama katmanındaki
-- oku-sonra-yaz denetimi atomik değildir: iki eşzamanlı yayın isteği "plan yok"
-- görüp iki satır ekleyebiliyordu. Yumuşak silme semantiği korunur (yalnızca
-- IsDeleted = 0 satırlar benzersizdir), GameRunID NULL olan planlar kapsam dışıdır.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_MB_Game_Blueprints_ActiveRun'
      AND object_id = OBJECT_ID(N'dbo.MB_Game_Blueprints')
)
BEGIN
    CREATE UNIQUE INDEX UX_MB_Game_Blueprints_ActiveRun
    ON dbo.MB_Game_Blueprints (UserID, GameRunID)
    WHERE IsDeleted = 0 AND GameRunID IS NOT NULL;
END;

-- 10) Haftalık topluluk operasyonu katkıları -----------------------------------
IF OBJECT_ID(N'dbo.MB_Game_CommunityContributions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Game_CommunityContributions (
        ContributionID BIGINT IDENTITY(1,1) PRIMARY KEY,
        WeekCode NVARCHAR(20) NOT NULL,
        UserID BIGINT NOT NULL,
        GameRunID BIGINT NOT NULL,
        ThreatsNeutralized INT NOT NULL DEFAULT 0,
        WavesDefended INT NOT NULL DEFAULT 0,
        PointsContributed BIGINT NOT NULL DEFAULT 0,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_MB_Game_CommunityContributions_Run UNIQUE (GameRunID)
    );
END;

-- Haftalık toplam okuma yolu için indeks.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Game_CommunityContributions_Week'
      AND object_id = OBJECT_ID(N'dbo.MB_Game_CommunityContributions')
)
BEGIN
    CREATE INDEX IX_MB_Game_CommunityContributions_Week
    ON dbo.MB_Game_CommunityContributions (WeekCode, UserID);
END;

-- 11) Doğrulama (bilgi amaçlı; hiçbir şey değiştirmez) -------------------------
SELECT
    t.name AS TableName,
    (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS ColumnCount
FROM sys.tables t
WHERE t.name IN (
    N'MB_Game_Profiles',
    N'MB_Game_CampaignProgress',
    N'MB_Game_HeroProgress',
    N'MB_Game_Runs',
    N'MB_Game_RunCheckpoints',
    N'MB_Game_Achievements',
    N'MB_Game_ChallengeSeasons',
    N'MB_Game_ChallengeEntries',
    N'MB_Game_Blueprints',
    N'MB_Game_CommunityContributions'
)
ORDER BY t.name;

-- Beklenen sonuç: 10 satır. Eksik satır varsa betik tekrar çalıştırılabilir
-- (idempotent). Uygulama tarafı tablo yokluğunda çökmez; oyun kalıcılıksız
-- modda çalışır ve kullanıcıya açıklayıcı bir uyarı gösterir.
