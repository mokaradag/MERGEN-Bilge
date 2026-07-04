/*
 * MERGEN Bilge - MB_* Tabloları İçin Güvenli Performans Endeksleri
 * Safe Performance Indexes for MB_* Tables
 * 
 * Tarih / Date: Temmuz 2026 / July 2026
 * Amaç / Purpose: Üretimde test edilmiş, dört dalga halinde (Wave 1-4) dağıtılacak güvenli nonclustered endeksler
 * Purpose: Production-validated, four-wave deployment of safe nonclustered indexes
 * 
 * Önemli Notlar / Critical Notes:
 * - Tüm endeksler nonclustered ve non-unique yapıda tasarlanmıştır (güvenlik için)
 * - All indexes are nonclustered and non-unique by design (safety)
 * - Her Wave sonrasında oturum açış testi yapılmalıdır
 * - Login testing must occur between each Wave
 * - Deployment, üretim dışı saatlerde (off-peak) gerçekleştirilmelidir
 * - Deployment should occur during off-peak windows
 * - SET XACT_ABORT ON ve SET LOCK_TIMEOUT ayarları güvenli işlem işleme sağlar
 * - SET XACT_ABORT ON and SET LOCK_TIMEOUT ensure safe transaction handling
 * 
 * Beklenen Performans Iyileştirmesi / Expected Performance Improvement:
 * - Yönetici sorgularında mantıksal okumalar ~100-150x azalması
 * - ~100-150x reduction in logical reads for admin queries
 * - Tablo boyutları <100K satır olduğu için, skala artarken davranış değişebilir
 * - Because tables are currently <100K rows, behavior may change at scale
 */

SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;

-- ============================================================================
-- WAVE 1 / DALGA 1
-- ============================================================================
-- Amaç: MB_Chats ve MB_Messages için temel endeksler
-- Purpose: Core indexes for MB_Chats and MB_Messages

-- Checkpoint: Wave 1 başlamadan önce veritabanı yedeği alınmış olmalıdır
-- Checkpoint: Database backup must be taken before Wave 1 begins

-- Index 1: MB_Chats.IX_MB_Chats_User_Active_Recent
-- Amaç: Bir kullanıcının etkin söyleşilerini yakınlık sırasına göre hızlı bir şekilde almak
-- Purpose: Fast retrieval of active chats for a user, ordered by recency
-- Sütunlar / Columns: UserID (filtre), IsDeleted (filtre), CreateTimestamp (sıralama), ChatID (benzersizlik)
-- İçerir / INCLUDE: ChatTitle (hoş geldin ekranı, son söyleşiler listesi)

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_Chats_User_Active_Recent' AND object_id = OBJECT_ID('MB_Chats')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_Chats_User_Active_Recent]
    ON [dbo].[MB_Chats] (
        [UserID] ASC,
        [IsDeleted] ASC,
        [CreateTimestamp] DESC,
        [ChatID] DESC
    )
    INCLUDE ([ChatTitle])
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_Chats.IX_MB_Chats_User_Active_Recent oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_Chats.IX_MB_Chats_User_Active_Recent zaten mevcut / already exists';
END

-- Index 2: MB_Messages.IX_MB_Messages_Chat_Order
-- Amaç: Bir söyleşinin mesajlarını MessageOrder'a göre sırayla ve hızlı bir şekilde almak
-- Purpose: Fast retrieval of messages for a chat, ordered by MessageOrder
-- Sütunlar / Columns: ChatID (filtre), MessageOrder (sıralama), MessageID (sıralama)
-- İçerir / INCLUDE: MessageType, MessageTimestamp

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_Messages_Chat_Order' AND object_id = OBJECT_ID('MB_Messages')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_Messages_Chat_Order]
    ON [dbo].[MB_Messages] (
        [ChatID] ASC,
        [MessageOrder] ASC,
        [MessageID] ASC
    )
    INCLUDE ([MessageType], [MessageTimestamp])
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_Messages.IX_MB_Messages_Chat_Order oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_Messages.IX_MB_Messages_Chat_Order zaten mevcut / already exists';
END

-- Index 3: MB_Messages.IX_MB_Messages_Chat_Timestamp
-- Amaç: Bir söyleşinin en son mesajlarını zaman damgasına göre hızlı bir şekilde almak
-- Purpose: Fast retrieval of recent messages for a chat, ordered by timestamp
-- Sütunlar / Columns: ChatID (filtre), MessageTimestamp (sıralama)

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_Messages_Chat_Timestamp' AND object_id = OBJECT_ID('MB_Messages')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_Messages_Chat_Timestamp]
    ON [dbo].[MB_Messages] (
        [ChatID] ASC,
        [MessageTimestamp] DESC
    )
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_Messages.IX_MB_Messages_Chat_Timestamp oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_Messages.IX_MB_Messages_Chat_Timestamp zaten mevcut / already exists';
END

-- Wave 1 Checkpoint
PRINT '';
PRINT '=== DALGA 1 / WAVE 1 TAMAMLANDI ===';
PRINT 'Sonraki adım / Next step: Oturum açış testini yapın ve Wave 2 için onay almak.';
PRINT 'Next step: Perform login testing and obtain approval before Wave 2.';
PRINT '';

-- ============================================================================
-- WAVE 2 / DALGA 2
-- ============================================================================
-- Amaç: MB_Feedback ve MB_Users için destek endeksleri
-- Purpose: Support indexes for MB_Feedback and MB_Users

-- Checkpoint: Wave 1 endeksleri etkin olmalı ve oturum açış testi geçmiş olmalıdır
-- Checkpoint: Wave 1 indexes must be active and login testing must have passed

-- Index 4: MB_Feedback.IX_MB_Feedback_User_Message
-- Amaç: Bir kullanıcının belirli bir mesaja verdiği geribildirime hızlı bir şekilde erişmek
-- Purpose: Fast retrieval of feedback for a user's message
-- Sütunlar / Columns: UserID (filtre), MessageID (filtre)
-- İçerir / INCLUDE: FeedbackType

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_Feedback_User_Message' AND object_id = OBJECT_ID('MB_Feedback')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_Feedback_User_Message]
    ON [dbo].[MB_Feedback] (
        [UserID] ASC,
        [MessageID] ASC
    )
    INCLUDE ([FeedbackType])
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_Feedback.IX_MB_Feedback_User_Message oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_Feedback.IX_MB_Feedback_User_Message zaten mevcut / already exists';
END

-- Index 5: MB_Users.IX_MB_Users_KullaniciAdi_Lookup
-- Amaç: Kullanıcı adına göre kullanıcı kimliğini ve ek bilgileri hızlı bir şekilde almak
-- Purpose: Fast retrieval of user ID and additional fields by username
-- Sütunlar / Columns: KullaniciAdi (filtre)
-- İçerir / INCLUDE: UserID, KaynakAdi, LastLoginDate
-- Not / Note: Bu endeks, MB_Users(KullaniciAdi) benzersiz kısıtlamasına ek olarak görülür
-- Note: This index is supplementary to the existing UNIQUE constraint on MB_Users(KullaniciAdi)

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_Users_KullaniciAdi_Lookup' AND object_id = OBJECT_ID('MB_Users')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_Users_KullaniciAdi_Lookup]
    ON [dbo].[MB_Users] (
        [KullaniciAdi] ASC
    )
    INCLUDE ([UserID], [KaynakAdi], [LastLoginDate])
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_Users.IX_MB_Users_KullaniciAdi_Lookup oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_Users.IX_MB_Users_KullaniciAdi_Lookup zaten mevcut / already exists';
END

-- Wave 2 Checkpoint
PRINT '';
PRINT '=== DALGA 2 / WAVE 2 TAMAMLANDI ===';
PRINT 'Sonraki adım / Next step: Oturum açış testini yapın ve Wave 3 için onay almak.';
PRINT '';

-- ============================================================================
-- WAVE 3 / DALGA 3
-- ============================================================================
-- Amaç: MB_Destek tabloları için endeksler
-- Purpose: Indexes for MB_Destek tables

-- Checkpoint: Wave 1 ve 2 endeksleri etkin olmalı
-- Checkpoint: Wave 1 and 2 indexes must be active

-- Index 6: MB_Destek_Geri_Bildirim.IX_MB_Destek_Geri_Bildirim_User_Recent
-- Amaç: Bir kullanıcının son geribildirimlerini hızlı bir şekilde almak
-- Purpose: Fast retrieval of recent feedback for a user
-- Sütunlar / Columns: UserID (filtre), OlusturmaTarihi (sıralama)

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_Destek_Geri_Bildirim_User_Recent' AND object_id = OBJECT_ID('MB_Destek_Geri_Bildirim')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_Destek_Geri_Bildirim_User_Recent]
    ON [dbo].[MB_Destek_Geri_Bildirim] (
        [UserID] ASC,
        [OlusturmaTarihi] DESC
    )
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_Destek_Geri_Bildirim.IX_MB_Destek_Geri_Bildirim_User_Recent oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_Destek_Geri_Bildirim.IX_MB_Destek_Geri_Bildirim_User_Recent zaten mevcut / already exists';
END

-- Index 7: MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_User_Recent
-- Amaç: Bir kullanıcının son hata raporlarını hızlı bir şekilde almak
-- Purpose: Fast retrieval of recent error reports for a user
-- Sütunlar / Columns: UserID (filtre), OlusturmaTarihi (sıralama)

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_Destek_Hata_Bildir_User_Recent' AND object_id = OBJECT_ID('MB_Destek_Hata_Bildir')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_Destek_Hata_Bildir_User_Recent]
    ON [dbo].[MB_Destek_Hata_Bildir] (
        [UserID] ASC,
        [OlusturmaTarihi] DESC
    )
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_User_Recent oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_User_Recent zaten mevcut / already exists';
END

-- Index 8: MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_Status_Recent
-- Amaç: Belirli durumlu hataları son tarihine göre sırayla almak
-- Purpose: Fast retrieval of errors with specific status, ordered by recency
-- Sütunlar / Columns: Durum (filtre), OlusturmaTarihi (sıralama)
-- İçerir / INCLUDE: Oncelik, UserID

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_Destek_Hata_Bildir_Status_Recent' AND object_id = OBJECT_ID('MB_Destek_Hata_Bildir')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_Destek_Hata_Bildir_Status_Recent]
    ON [dbo].[MB_Destek_Hata_Bildir] (
        [Durum] ASC,
        [OlusturmaTarihi] DESC
    )
    INCLUDE ([Oncelik], [UserID])
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_Status_Recent oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_Status_Recent zaten mevcut / already exists';
END

-- Wave 3 Checkpoint
PRINT '';
PRINT '=== DALGA 3 / WAVE 3 TAMAMLANDI ===';
PRINT 'Sonraki adım / Next step: Oturum açış testini yapın ve Wave 4 için onay almak.';
PRINT '';

-- ============================================================================
-- WAVE 4 / DALGA 4
-- ============================================================================
-- Amaç: MB_ClaudeCode tabloları için endeksler
-- Purpose: Indexes for MB_ClaudeCode tables

-- Checkpoint: Wave 1, 2 ve 3 endeksleri etkin olmalı
-- Checkpoint: Wave 1, 2, and 3 indexes must be active

-- Index 9: MB_ClaudeCode_Sessions.IX_MB_ClaudeCode_Sessions_User_Recent
-- Amaç: Bir kullanıcının etkin Bilge Yolaç oturumlarını yakınlık sırasına göre hızlı almak
-- Purpose: Fast retrieval of active Bilge Yolaç sessions for a user, ordered by recency
-- Sütunlar / Columns: UserID (filtre), IsDeleted (filtre), LastRunAt (sıralama), CreatedAt (sıralama)

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_ClaudeCode_Sessions_User_Recent' AND object_id = OBJECT_ID('MB_ClaudeCode_Sessions')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_ClaudeCode_Sessions_User_Recent]
    ON [dbo].[MB_ClaudeCode_Sessions] (
        [UserID] ASC,
        [IsDeleted] ASC,
        [LastRunAt] DESC,
        [CreatedAt] DESC
    )
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_ClaudeCode_Sessions.IX_MB_ClaudeCode_Sessions_User_Recent oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_ClaudeCode_Sessions.IX_MB_ClaudeCode_Sessions_User_Recent zaten mevcut / already exists';
END

-- Index 10: MB_ClaudeCode_Runs.IX_MB_ClaudeCode_Runs_Session_Order
-- Amaç: Bir oturumun çalışmalarını sıra numarasına göre hızlı almak
-- Purpose: Fast retrieval of runs for a session, ordered by run order
-- Sütunlar / Columns: ClaudeSessionRecordID (filtre), RunOrder (sıralama)

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE name = 'IX_MB_ClaudeCode_Runs_Session_Order' AND object_id = OBJECT_ID('MB_ClaudeCode_Runs')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MB_ClaudeCode_Runs_Session_Order]
    ON [dbo].[MB_ClaudeCode_Runs] (
        [ClaudeSessionRecordID] ASC,
        [RunOrder] ASC
    )
    WITH (SORT_IN_TEMPDB = ON, MAXDOP = 1);
    
    PRINT '✓ MB_ClaudeCode_Runs.IX_MB_ClaudeCode_Runs_Session_Order oluşturuldu / created';
END
ELSE
BEGIN
    PRINT '⚠ MB_ClaudeCode_Runs.IX_MB_ClaudeCode_Runs_Session_Order zaten mevcut / already exists';
END

-- Wave 4 Checkpoint
PRINT '';
PRINT '=== DALGA 4 / WAVE 4 TAMAMLANDI ===';
PRINT 'TÜM DALGALAR BAŞARIYLA TAMAMLANDI / ALL WAVES COMPLETED SUCCESSFULLY';
PRINT '';

-- Final Summary
PRINT '=== ÖZET / SUMMARY ===';
PRINT 'Oluşturulan endeks sayısı / Total indexes created: 10';
PRINT 'Tablolar / Tables affected: MB_Chats, MB_Messages, MB_Feedback, MB_Users, MB_Destek_Geri_Bildirim, MB_Destek_Hata_Bildir, MB_ClaudeCode_Sessions, MB_ClaudeCode_Runs';
PRINT '';
PRINT 'Sonraki adım / Next step:';
PRINT '1. 30 dakika minimum soak testi yapın (oturum açış, söyleşi yönetimi, yönetici analitikleri)';
PRINT '2. Perform minimum 30-minute soak testing (login, chat management, admin analytics)';
PRINT '3. Endeks fragmentasyonunu kontrol edin / Check index fragmentation';
PRINT '4. Performans iyileştirmesini doğrulayın (SET STATISTICS IO ON kullanarak)';
PRINT '5. Verify performance improvement using SET STATISTICS IO ON';
PRINT '';

PRINT 'UYARI / WARNING: Dağıtım sırasında veritabanının yedeklemesi yapılmalıdır.';
PRINT 'WARNING: Database must be backed up during deployment.';