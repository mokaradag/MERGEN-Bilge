-- =============================================================================
-- Dosya Yolu: docs/sql/2026-07-ortak-oturumlar-rollback.sql
-- Açıklama: docs/sql/2026-07-ortak-oturumlar.sql betiğinin GERİ ALMA betiği.
--           YALNIZCA Ortak Oturumlar özelliğiyle eklenen yeni tabloları ve
--           indeksleri kaldırır.
--
-- ÖNEMLİ OPERASYON NOTLARI:
--   * Bu betik UYGULAMA AÇILIŞINDA OTOMATİK ÇALIŞTIRILMAZ. Yalnızca DBA /
--     operatör tarafından SSMS üzerinden, DOĞRULANMIŞ DB yedeği alındıktan
--     sonra manuel uygulanır.
--   * SADECE MB_Ortak* / MB_Kullanici_CanliDurum / MB_Bildirimler tablolarına
--     dokunur. MEVCUT MB_Chats, MB_Messages, MB_Users, MB_Feedback,
--     MB_ClaudeCode_Sessions ve MB_ClaudeCode_Runs tablolarına ASLA dokunmaz.
--   * Tablolar FK bağımlılık sırasının TERSİNE göre kaldırılır (önce çocuk,
--     sonra ebeveyn); her DROP, OBJECT_ID koruması ile idempotenttir.
--   * DİKKAT: DROP TABLE, ortak oturum verisini kalıcı olarak siler. Ortak
--     belge dosyaları (disk üzerindeki ortak_oturumlar/ klasörü) bu betikle
--     SİLİNMEZ; gerekiyorsa dosya sistemi temizliği ayrı ve bilinçli bir
--     operasyon adımıdır.
--   * Uygulama tarafı tablolar yokken güvenli boş/NULL sonuçla çalışmaya
--     devam eder (aşamalı devreye alma sözleşmesi); rollback uygulamayı
--     kırmaz, yalnızca Ortak Oturumlar sayfaları "tablolar hazır değil"
--     durumuna döner.
-- =============================================================================

SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;
GO

-- 1) Olay günlüğü (yalnızca ortak oturum tablolarına FK verir)
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Olaylar', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturum_Olaylar;
GO

-- 2) Belge kullanıcı kopyaları (MB_OrtakOturum_Dosyalar'a FK verir)
IF OBJECT_ID(N'dbo.MB_OrtakOturum_DosyaKopyalari', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturum_DosyaKopyalari;
GO

-- 3) Ortak belgeler (MB_OrtakBilgeYolac_Calistirmalar'a FK verir)
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Dosyalar', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturum_Dosyalar;
GO

-- 4) Ortak Bilge Yolaç çalıştırmaları
IF OBJECT_ID(N'dbo.MB_OrtakBilgeYolac_Calistirmalar', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakBilgeYolac_Calistirmalar;
GO

-- 5) Ortak Bilge Yolaç oturumları
IF OBJECT_ID(N'dbo.MB_OrtakBilgeYolac_Oturumlar', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakBilgeYolac_Oturumlar;
GO

-- 6) Aktif üretim kilidi (MB_OrtakOturum_Mesajlar'a FK verir)
IF OBJECT_ID(N'dbo.MB_OrtakOturum_AktifUretimler', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturum_AktifUretimler;
GO

-- 7) Yapay zekâ kuyruğu (MB_OrtakOturum_Mesajlar'a FK verir)
IF OBJECT_ID(N'dbo.MB_OrtakOturum_YapayZekaKuyrugu', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturum_YapayZekaKuyrugu;
GO

-- 8) Ortak oturum mesajları
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Mesajlar', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturum_Mesajlar;
GO

-- 9) Bildirimler (MB_OrtakOturumlar'a FK verir)
IF OBJECT_ID(N'dbo.MB_Bildirimler', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Bildirimler;
GO

-- 10) Canlı durum (MB_OrtakOturumlar'a FK verir)
IF OBJECT_ID(N'dbo.MB_Kullanici_CanliDurum', N'U') IS NOT NULL
    DROP TABLE dbo.MB_Kullanici_CanliDurum;
GO

-- 11) Davetler
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Davetler', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturum_Davetler;
GO

-- 12) Katılımcılar
IF OBJECT_ID(N'dbo.MB_OrtakOturum_Katilimcilar', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturum_Katilimcilar;
GO

-- 13) Ortak oturum başlık tablosu (en son; diğerleri buna FK verir)
IF OBJECT_ID(N'dbo.MB_OrtakOturumlar', N'U') IS NOT NULL
    DROP TABLE dbo.MB_OrtakOturumlar;
GO

-- 14) Doğrulama: kalan Ortak Oturum tablosu olmamalıdır (bilgi amaçlı)
SELECT t.name AS KalanTablo
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
);
GO
