-- =============================================================================
-- Dosya Yolu: docs/sql/2026-07-bilge-yolac-sessions.sql
-- Açıklama: Bilge Yolaç (Claude Code) kalıcı oturum saklama tabloları.
--
-- ÖNEMLİ OPERASYON NOTLARI:
--   * Bu betik UYGULAMA AÇILIŞINDA OTOMATİK ÇALIŞTIRILMAZ. Yalnızca DBA /
--     operatör tarafından SSMS üzerinden, DB yedeği alındıktan sonra manuel
--     uygulanır (bkz. RUNBOOK.md "Bilge Yolaç oturum tabloları" bölümü).
--   * Betik idempotenttir: tablolar/indeksler zaten varsa hiçbir şey yapmaz,
--     mevcut veriyi DEĞİŞTİRMEZ ve SİLMEZ (yıkıcı ifade içermez).
--   * Tablolar kasıtlı olarak MB_Chats / MB_Messages ailesinden AYRIDIR.
--     Bilge Yolaç bir ajan/çalışma alanı ortamıdır; oturum yapısı (CLI resume
--     kimliği, workdir, runtime workdir, araç çağrıları, üretilen dosyalar)
--     normal sohbet şemasına sığmaz.
--   * Kolon tipleri NVARCHAR'dır; Türkçe metin bütünlüğü uygulama tarafındaki
--     merkezi DB encoding yardımcıları (normalize_db_visible_value /
--     normalize_db_technical_value / normalize_db_params) ile korunur.
--     DB_CLIENT_ENCODING=WINDOWS-1254 üretim sözleşmesi değişmez.
--   * RawStreamJsonl uygulama tarafında boyut sınırına tabidir (varsayılan
--     ~400.000 karakter); taşan içerik açık bir kesme işaretiyle kısaltılır.
--   * Bu tablolara gizli bilgi (API anahtarı, token, ortam değişkeni, ikili
--     dosya içeriği) YAZILMAZ; üretilen dosyalar için yalnızca metadata
--     (ad, boyut, indirme yolu) saklanır.
-- =============================================================================

-- 1) Oturum başlık tablosu -----------------------------------------------------
IF OBJECT_ID(N'dbo.MB_ClaudeCode_Sessions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_ClaudeCode_Sessions (
        ClaudeSessionRecordID BIGINT IDENTITY(1,1) PRIMARY KEY,
        UserID BIGINT NOT NULL,
        ClaudeCliSessionID NVARCHAR(200) NULL,
        SessionTitle NVARCHAR(500) NULL,
        Workdir NVARCHAR(MAX) NULL,
        SourceWorkdir NVARCHAR(MAX) NULL,
        RuntimeWorkdir NVARCHAR(MAX) NULL,
        ModelUsed NVARCHAR(100) NULL,
        RuntimeModel NVARCHAR(100) NULL,
        CharacterID NVARCHAR(50) NULL,
        Status NVARCHAR(50) NULL,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        LastRunAt DATETIME2(0) NULL,
        IsDeleted BIT NOT NULL DEFAULT 0,
        SessionMetaJson NVARCHAR(MAX) NULL
    );
END;

-- Kullanıcı bazlı "en son etkinlik" listelemesi için kapsayıcı indeks.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_ClaudeCode_Sessions_User_Recent'
      AND object_id = OBJECT_ID(N'dbo.MB_ClaudeCode_Sessions')
)
BEGIN
    CREATE INDEX IX_MB_ClaudeCode_Sessions_User_Recent
    ON dbo.MB_ClaudeCode_Sessions (UserID, IsDeleted, LastRunAt DESC, CreatedAt DESC);
END;

-- 2) Çalıştırma (run) tablosu --------------------------------------------------
IF OBJECT_ID(N'dbo.MB_ClaudeCode_Runs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_ClaudeCode_Runs (
        ClaudeRunID BIGINT IDENTITY(1,1) PRIMARY KEY,
        ClaudeSessionRecordID BIGINT NOT NULL,
        RunOrder INT NOT NULL,
        Prompt NVARCHAR(MAX) NOT NULL,
        FinalOutput NVARCHAR(MAX) NULL,
        Status NVARCHAR(50) NOT NULL,
        ExitCode INT NULL,
        DurationSeconds DECIMAL(10,2) NULL,
        ToolUsesJson NVARCHAR(MAX) NULL,
        GeneratedDownloadsJson NVARCHAR(MAX) NULL,
        RawStreamJsonl NVARCHAR(MAX) NULL,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_MB_ClaudeCode_Runs_Sessions
            FOREIGN KEY (ClaudeSessionRecordID)
            REFERENCES dbo.MB_ClaudeCode_Sessions(ClaudeSessionRecordID)
    );
END;

-- Oturum zaman çizelgesi okuma yolu için indeks.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_ClaudeCode_Runs_Session_Order'
      AND object_id = OBJECT_ID(N'dbo.MB_ClaudeCode_Runs')
)
BEGIN
    CREATE INDEX IX_MB_ClaudeCode_Runs_Session_Order
    ON dbo.MB_ClaudeCode_Runs (ClaudeSessionRecordID, RunOrder ASC);
END;

-- 3) Doğrulama (bilgi amaçlı; hiçbir şey değiştirmez) --------------------------
SELECT
    t.name AS TableName,
    (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS ColumnCount
FROM sys.tables t
WHERE t.name IN (N'MB_ClaudeCode_Sessions', N'MB_ClaudeCode_Runs');
