-- =============================================================================
-- Dosya Yolu: docs/sql/2026-07-bilge-savunmasi-rollback.sql
-- Açıklama: Bilge Savunması tablolarının GERİ ALMA betiği.
--
-- UYARI — YIKICIDIR:
--   * Bu betik MB_Game_* ailesindeki TÜM oyun verisini kalıcı olarak siler.
--   * Yalnızca DBA / operatör tarafından, TAM DB YEDEĞİ alındıktan ve
--     uygulama tarafında MERGEN_BILGE_SAVUNMASI_ENABLED=FALSE yapılıp uygulama
--     yeniden başlatıldıktan SONRA, SSMS üzerinden manuel çalıştırılır.
--   * Uygulama açılışında OTOMATİK ÇALIŞTIRILMAZ.
--   * Sohbet/oturum tablolarına (MB_Chats, MB_Messages, MB_ClaudeCode_*,
--     MB_Ortak*) DOKUNMAZ.
--   * Sıra önemlidir: önce yabancı anahtar taşıyan çocuk tablolar silinir.
-- =============================================================================

IF OBJECT_ID(N'dbo.MB_Game_RunCheckpoints', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_RunCheckpoints;

IF OBJECT_ID(N'dbo.MB_Game_ChallengeEntries', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_ChallengeEntries;

IF OBJECT_ID(N'dbo.MB_Game_CommunityContributions', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_CommunityContributions;

IF OBJECT_ID(N'dbo.MB_Game_Blueprints', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_Blueprints;

IF OBJECT_ID(N'dbo.MB_Game_ChallengeSeasons', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_ChallengeSeasons;

IF OBJECT_ID(N'dbo.MB_Game_Achievements', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_Achievements;

IF OBJECT_ID(N'dbo.MB_Game_Runs', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_Runs;

IF OBJECT_ID(N'dbo.MB_Game_HeroProgress', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_HeroProgress;

IF OBJECT_ID(N'dbo.MB_Game_CampaignProgress', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_CampaignProgress;

IF OBJECT_ID(N'dbo.MB_Game_Profiles', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Game_Profiles;

-- Doğrulama: sonuç 0 satır olmalıdır.
SELECT t.name AS KalanTablo
FROM sys.tables t
WHERE t.name LIKE N'MB[_]Game[_]%'
ORDER BY t.name;
