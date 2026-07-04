-- =============================================================================
-- Dosya Yolu: docs/sql/2026-07-safe-mb-performance-indexes.sql
-- Açıklama: MERGEN Bilge için üretim güvenli MB_* SQL Server performans indeksleri.
--
-- ÖNEMLİ OPERASYON NOTLARI:
--   * Bu betik yalnızca DBA/operatör tarafından manuel olarak çalıştırılmalıdır.
--   * Çalıştırmadan önce doğrulanmış bir yedek alınmalıdır.
--   * Yoğun kullanım saatleri dışında ve dalgalar hâlinde uygulanmalıdır.
--   * Her dalgadan sonra uygulama başlangıcı ve kullanıcı girişi test edilmelidir.
--   * Betik idempotenttir; mevcut indeksleri yeniden oluşturmamaya dikkat eder.
--   * Yalnızca üretimde doğrulanmış güvenli Wave 1-4 performans indekslerini içerir.
--   * PK/UQ kısıtları düşürülmemeli veya değiştirilmemelidir.
--   * MB_Users(KullaniciAdi) üzerindeki mevcut UQ__MB_Users__... benzersiz
--     kısıtı/indeksi korunmalıdır.
--   * Yeni UNIQUE IX_MB_Users_KullaniciAdi indeksi eklenmemelidir.
-- =============================================================================

/*
 * MERGEN Bilge - üretim güvenli MB_* SQL Server performans indeksleri
 * Tarih: Temmuz 2026
 *
 * Yalnızca manuel DBA/operatör betiğidir. Önce doğrulanmış bir yedek alın,
 * yoğun kullanım saatleri dışında uygulayın ve dalgalar hâlinde ilerleyin.
 * Her dalgadan sonra devam etmeden önce uygulama başlangıcını ve kullanıcı
 * girişini test edin. Bu betik idempotenttir ve yalnızca, daha önceki tümünü
 * tek seferde uygulama denemesinin kullanıcı giriş hatasına yol açmasının
 * ardından üretimde doğrulanan nihai güvenli Wave 1-4 performans indekslerini
 * içerir.
 *
 * Güvenlik sözleşmesi:
 * - Her dalgada SET XACT_ABORT ON ve SET LOCK_TIMEOUT 15000 kullanılır.
 * - Her CREATE INDEX işlemi IF NOT EXISTS ile korunur.
 * - Tüm indeksler nonclustered ve non-unique yapıdadır.
 * - PK/UQ kısıtlarını düşürmeyin veya değiştirmeyin; buna, mevcut
 *   MB_Users(KullaniciAdi) benzersiz kısıtı/indeksi de dahildir.
 *   Bu indeks/kısıt genellikle UQ__MB_Users__... biçiminde adlandırılmıştır.
 * - Yeni oluşturulmuş bir UNIQUE IX_MB_Users_KullaniciAdi indeksi eklemeyin.
 * - Önceki tümünü tek seferde uygulama dağıtımı geçersiz/güvensiz kabul
 *   edilmiştir. Muhtemel nedenler: güvenli olmayan toplu uygulama,
 *   şema kilitlenmesi veya kullanıcı giriş yolunda aşırı agresif benzersiz
 *   indeks denemesi. Kök neden kesin olarak kanıtlanmamıştır.
 */

-- ============================================================================
-- Wave 1: sohbet listesi ve mesaj yükleme/sıralama yolları
-- ============================================================================
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Chats_User_Active_Recent'
      AND object_id = OBJECT_ID(N'dbo.MB_Chats')
)
BEGIN
    CREATE INDEX IX_MB_Chats_User_Active_Recent
    ON dbo.MB_Chats (UserID, IsDeleted, CreateTimestamp DESC, ChatID DESC)
    INCLUDE (ChatTitle)
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Messages_Chat_Order'
      AND object_id = OBJECT_ID(N'dbo.MB_Messages')
)
BEGIN
    CREATE INDEX IX_MB_Messages_Chat_Order
    ON dbo.MB_Messages (ChatID, MessageOrder ASC, MessageID ASC)
    INCLUDE (MessageType, MessageTimestamp)
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Messages_Chat_Timestamp'
      AND object_id = OBJECT_ID(N'dbo.MB_Messages')
)
BEGIN
    CREATE INDEX IX_MB_Messages_Chat_Timestamp
    ON dbo.MB_Messages (ChatID, MessageTimestamp DESC)
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
END;
GO

UPDATE STATISTICS dbo.MB_Chats;
UPDATE STATISTICS dbo.MB_Messages;
GO

-- Wave 1 sonrasında: Gerekirse uygulamayı başlatın, kullanıcıların giriş
-- yapabildiğini doğrulayın, sohbet listesi ve geçmiş ekranlarını duman testinden geçirin.

-- ============================================================================
-- Wave 2: geri bildirim sorgulama yolu; özellikle non-unique tasarlanmıştır
-- ============================================================================
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Feedback_User_Message'
      AND object_id = OBJECT_ID(N'dbo.MB_Feedback')
)
BEGIN
    CREATE INDEX IX_MB_Feedback_User_Message
    ON dbo.MB_Feedback (UserID, MessageID)
    INCLUDE (FeedbackType)
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
END;
GO

UPDATE STATISTICS dbo.MB_Feedback;
GO

-- Wave 2 sonrasında: Kullanıcıların giriş yapabildiğini ve geri bildirim
-- yükleme/kaydetme/silme işlemlerinin çalıştığını doğrulayın.

-- ============================================================================
-- Wave 3: kullanıcı girişi/kullanıcı profili sorgulama yolu;
-- açık performans indeksi non-unique yapıdadır
-- ============================================================================
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Users_KullaniciAdi_Lookup'
      AND object_id = OBJECT_ID(N'dbo.MB_Users')
)
BEGIN
    CREATE INDEX IX_MB_Users_KullaniciAdi_Lookup
    ON dbo.MB_Users (KullaniciAdi)
    INCLUDE (UserID, KaynakAdi, LastLoginDate)
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
END;
GO

UPDATE STATISTICS dbo.MB_Users;
GO

-- Wave 3 sonrasında: Destek/yönetim indekslerini uygulamadan önce kullanıcıların
-- giriş yapabildiğini doğrulayın.

-- ============================================================================
-- Wave 4: destek/yönetim güncel listeleme yolları
-- ============================================================================
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Destek_Geri_Bildirim_User_Recent'
      AND object_id = OBJECT_ID(N'dbo.MB_Destek_Geri_Bildirim')
)
BEGIN
    CREATE INDEX IX_MB_Destek_Geri_Bildirim_User_Recent
    ON dbo.MB_Destek_Geri_Bildirim (UserID, OlusturmaTarihi DESC)
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Destek_Hata_Bildir_User_Recent'
      AND object_id = OBJECT_ID(N'dbo.MB_Destek_Hata_Bildir')
)
BEGIN
    CREATE INDEX IX_MB_Destek_Hata_Bildir_User_Recent
    ON dbo.MB_Destek_Hata_Bildir (UserID, OlusturmaTarihi DESC)
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MB_Destek_Hata_Bildir_Status_Recent'
      AND object_id = OBJECT_ID(N'dbo.MB_Destek_Hata_Bildir')
)
BEGIN
    CREATE INDEX IX_MB_Destek_Hata_Bildir_Status_Recent
    ON dbo.MB_Destek_Hata_Bildir (Durum, OlusturmaTarihi DESC)
    INCLUDE (Oncelik, UserID)
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
END;
GO

UPDATE STATISTICS dbo.MB_Destek_Geri_Bildirim;
UPDATE STATISTICS dbo.MB_Destek_Hata_Bildir;
GO

-- Nihai doğrulama: Uygulama start_mergen_prod.bat ile başlatılmalı,
-- kullanıcıların giriş yapabildiği doğrulanmalı, yönetim ekranında ilk tıklama
-- ve içerik yükleme duman testinden geçirilmeli, metadata üzerinden indekslerin
-- etkin olduğu teyit edilmeli ve temsili SET STATISTICS IO/TIME kontrolleri
-- gözden geçirilmelidir.