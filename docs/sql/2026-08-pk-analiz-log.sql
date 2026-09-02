-- =============================================================================
-- Dosya Yolu: docs/sql/2026-08-pk-analiz-log.sql
-- Açıklama: Proje ve Kaynak Analizi telemetri tablosu (MB_Analiz_Log).
--
-- ÖNEMLİ OPERASYON NOTLARI:
--   * Bu betik UYGULAMA AÇILIŞINDA OTOMATİK ÇALIŞTIRILMAZ. Yalnızca DBA /
--     operatör tarafından SSMS üzerinden, DB yedeği alındıktan sonra manuel
--     uygulanır. Uygulama tarafı hiçbir koşulda DDL çalıştırmaz.
--   * Betik idempotenttir: tablo/indeksler zaten varsa hiçbir şey yapmaz,
--     mevcut veriyi DEĞİŞTİRMEZ ve SİLMEZ (yıkıcı ifade içermez).
--   * Bu tablo YOKKEN de Proje ve Kaynak Analizi TAM ÇALIŞIR. Uygulama tablo
--     hazırlığını süreç başına bir kez tespit eder, bulunamazsa telemetriyi
--     tek bir log satırıyla devre dışı bırakır (fail-soft). Yani uygulama
--     güncellemesi bu betikten ÖNCE sahaya inebilir.
--   * Kolon tipleri NVARCHAR'dır; Türkçe metin bütünlüğü uygulama tarafındaki
--     merkezî DB encoding yardımcıları (normalize_db_visible_value /
--     normalize_db_technical_value / normalize_db_params) ile korunur.
--     DB_CLIENT_ENCODING=WINDOWS-1254 üretim sözleşmesi DEĞİŞMEZ.
--   * OlusturmaZamani uygulama tarafından Türkiye yerel saatiyle (sabit +3)
--     yazılır; MB_Ortak* ailesiyle aynı sözleşme.
--
-- GİZLİLİK VE ERİŞİM:
--   * SoruMetni yalnızca MERGEN_PK_LOG_QUESTION_TEXT=true iken doldurulur.
--     Varsayılan (false) durumda NULL kalır ve yerine sunucu anahtarlı
--     HMAC-SHA256 parmak izi (SoruParmakIzi) saklanır. Anahtar
--     (MERGEN_PK_TELEMETRY_HMAC_KEY) tanımlı değilse parmak izi de yazılmaz.
--     ParmakIziAnahtarID anahtar rotasyonundan sonra eski satırların hangi
--     anahtarla üretildiğini belirtir.
--   * SatirRlsOncesi KISITLI bir alandır: RLS (yetki) filtresinden ÖNCEKİ satır
--     sayısıdır ve kullanıcının yetkisi dışındaki veri hacmini ele verir.
--     Bu değer yalnızca burada tutulur; kullanıcıya görünen alt bilgiye, Excel
--     'Bilgi' sayfasına veya modele giden pakete ASLA yazılmaz. Tabloya erişim
--     buna göre kısıtlanmalıdır.
--   * Bu tabloya gizli bilgi (API anahtarı, token, parola, DSN, bağlantı
--     dizesi, ham ODBC tanılaması) YAZILMAZ.
-- =============================================================================

-- 1) Telemetri tablosu ---------------------------------------------------------
IF OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MB_Analiz_Log (
        AnalizLogID        BIGINT IDENTITY(1,1) PRIMARY KEY,

        -- İstek kimliği ve kullanıcı bağlamı
        IstekID            NVARCHAR(64)   NULL,
        KullaniciID        BIGINT         NULL,
        KullaniciAdi       NVARCHAR(200)  NULL,

        -- Hangi motor ve mod çalıştı
        Motor              NVARCHAR(10)   NULL,
        DerinDusunme       BIT            NULL,

        -- Soru: ham metin (opsiyonel) VEYA anahtarlı parmak izi
        SoruMetni          NVARCHAR(MAX)  NULL,
        SoruParmakIzi      NVARCHAR(64)   NULL,
        ParmakIziAnahtarID NVARCHAR(32)   NULL,

        -- Sorgu seçimi
        SecilenSorguID     NVARCHAR(64)   NULL,
        SecilenSorguAdi    NVARCHAR(400)  NULL,

        -- Filtre adımının tipli sonucu:
        -- ok_no_filter / ok_filtered / timeout / error / malformed /
        -- stopped / disabled / not_reached
        FiltreDurumu       NVARCHAR(32)   NULL,
        FiltreSayisi       INT            NULL,

        -- Satır sayıları.
        -- DİKKAT: SatirRlsOncesi kısıtlıdır, kullanıcıya gösterilmez.
        SatirRlsOncesi     INT            NULL,
        SatirYetkiSonrasi  INT            NULL,
        SatirFiltreSonrasi INT            NULL,

        -- Kullanıcıya da bildirilen bozulma kodları (virgülle ayrılmış)
        BozulmaKodlari     NVARCHAR(400)  NULL,

        -- Basarili / BosSonuc / Hata / Durduruldu
        Sonuc              NVARCHAR(32)   NULL,
        ToplamSureMs       INT            NULL,

        OlusturmaZamani    DATETIME2(3)   NOT NULL
            CONSTRAINT DF_MB_Analiz_Log_OlusturmaZamani
            DEFAULT (DATEADD(HOUR, 3, SYSUTCDATETIME()))
    );
END;
GO

-- 2) İndeksler -----------------------------------------------------------------
-- Zaman bazlı raporlama (günlük/haftalık kullanım, bozulma oranı).
IF OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = N'IX_MB_Analiz_Log_OlusturmaZamani'
          AND object_id = OBJECT_ID(N'dbo.MB_Analiz_Log')
   )
BEGIN
    CREATE INDEX IX_MB_Analiz_Log_OlusturmaZamani
        ON dbo.MB_Analiz_Log (OlusturmaZamani DESC);
END;
GO

-- Hangi sorgunun ne sıklıkta kullanıldığı: metadata zenginleştirme önceliği
-- (master plan §5.1 "telemetriye göre önceliklendir") bu indeksten okunur.
IF OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = N'IX_MB_Analiz_Log_SecilenSorguID'
          AND object_id = OBJECT_ID(N'dbo.MB_Analiz_Log')
   )
BEGIN
    CREATE INDEX IX_MB_Analiz_Log_SecilenSorguID
        ON dbo.MB_Analiz_Log (SecilenSorguID, OlusturmaZamani DESC);
END;
GO

-- Bozulma (zaman aşımı / hata / bozuk yanıt) oranını ölçmek için.
IF OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE name = N'IX_MB_Analiz_Log_FiltreDurumu'
          AND object_id = OBJECT_ID(N'dbo.MB_Analiz_Log')
   )
BEGIN
    CREATE INDEX IX_MB_Analiz_Log_FiltreDurumu
        ON dbo.MB_Analiz_Log (FiltreDurumu, OlusturmaZamani DESC);
END;
GO

-- 3) Doğrulama (bilgilendirme amaçlı; veri değiştirmez) -------------------------
SELECT
    N'MB_Analiz_Log'                                   AS Tablo,
    CASE WHEN OBJECT_ID(N'dbo.MB_Analiz_Log', N'U') IS NULL
         THEN N'YOK' ELSE N'HAZIR' END                 AS Durum;
GO
