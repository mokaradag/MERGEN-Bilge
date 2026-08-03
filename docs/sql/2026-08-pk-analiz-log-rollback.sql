-- =============================================================================
-- Dosya Yolu: docs/sql/2026-08-pk-analiz-log-rollback.sql
-- Açıklama: MB_Analiz_Log telemetri tablosunun GERİ ALMA betiği.
--
-- YIKICI BETİK - DİKKAT:
--   * Bu betik TABLOYU VE İÇİNDEKİ TÜM TELEMETRİ VERİSİNİ SİLER.
--   * ASLA otomatik çalıştırılmaz; yalnızca DBA / operatör tarafından, DB
--     YEDEĞİ ALINDIKTAN SONRA ve açık onayla elle uygulanır.
--   * Kurulum betiğinden (2026-08-pk-analiz-log.sql) BİLEREK ayrı tutulmuştur;
--     kurulum betiği hiçbir yıkıcı ifade içermez.
--
-- ÖNCE BUNU DÜŞÜNÜN:
--   Telemetriyi kapatmak için tabloyu silmeye GEREK YOKTUR. Uygulamada
--   .Renviron içine MERGEN_PK_TELEMETRY=false yazıp R sürecini yeniden
--   başlatmak yeterlidir (tarayıcı yenilemesi yetmez). Tablo yalnızca kalıcı
--   olarak kaldırılacaksa bu betik kullanılır.
--
-- VERİYİ KORUYARAK ARŞİVLEME (önerilen ara adım):
--   SELECT * INTO dbo.MB_Analiz_Log_Arsiv_20260801 FROM dbo.MB_Analiz_Log;
-- =============================================================================

-- 1) İndeksleri kaldır ---------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NOT NULL
   AND EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = N'IX_MB_Analiz_Log_FiltreDurumu'
          AND object_id = OBJECT_ID(N'dbo.MB_Analiz_Log')
   )
BEGIN
    DROP INDEX IX_MB_Analiz_Log_FiltreDurumu ON dbo.MB_Analiz_Log;
END;
GO

IF OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NOT NULL
   AND EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = N'IX_MB_Analiz_Log_SecilenSorguID'
          AND object_id = OBJECT_ID(N'dbo.MB_Analiz_Log')
   )
BEGIN
    DROP INDEX IX_MB_Analiz_Log_SecilenSorguID ON dbo.MB_Analiz_Log;
END;
GO

IF OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NOT NULL
   AND EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = N'IX_MB_Analiz_Log_OlusturmaZamani'
          AND object_id = OBJECT_ID(N'dbo.MB_Analiz_Log')
   )
BEGIN
    DROP INDEX IX_MB_Analiz_Log_OlusturmaZamani ON dbo.MB_Analiz_Log;
END;
GO

-- 2) Tabloyu kaldır ------------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NOT NULL
BEGIN
    DROP TABLE dbo.MB_Analiz_Log;
END;
GO

-- 3) Doğrulama -----------------------------------------------------------------
SELECT
    N'MB_Analiz_Log' AS Tablo,
    CASE WHEN OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NULL
         THEN N'KALDIRILDI' ELSE N'HALA VAR' END AS Durum;
GO
