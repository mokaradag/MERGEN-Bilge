/*
 * MERGEN Bilge - MB_* Tabloları Performans Endekslerinin Geri Alınması
 * Emergency Rollback for MB_* Performance Indexes
 * 
 * Tarih / Date: Temmuz 2026 / July 2026
 * Amaç / Purpose: İstenen durumda güvenli performans endekslerini geri almak
 * Purpose: Emergency removal of safe performance indexes if needed
 * 
 * Önemli Notlar / Critical Notes:
 * - Bu betik YALNIZCA performans endekslerini düşürür (10 adet)
 * - This script drops ONLY the performance indexes (10 indexes)
 * - Birincil Anahtar (Primary Key) kısıtlamaları korunur / Primary Key constraints preserved
 * - Benzersiz (Unique) kısıtlamaları korunur / Unique constraints preserved
 * - Beklenen çalışma süresi / Expected execution time: < 1 dakika / 1 minute
 * 
 * Uyarı / WARNING:
 * - Geri alınan endeksler olmadan sorgu performansı önemli ölçüde azalabilir
 * - Query performance may significantly degrade without these indexes
 * - Geri alma işleminden sonra anında etkili olur (yeni bağlantılar gerekli değildir)
 * - Rollback takes effect immediately (new connections not required)
 */

SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;

PRINT '=== PERFORMANS ENDEKSLERI GERİ ALMA / PERFORMANCE INDEXES ROLLBACK ===';
PRINT '';

-- Index 1: MB_Chats.IX_MB_Chats_User_Active_Recent
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_Chats_User_Active_Recent' AND object_id = OBJECT_ID('MB_Chats'))
BEGIN
    DROP INDEX [IX_MB_Chats_User_Active_Recent] ON [dbo].[MB_Chats];
    PRINT '✓ MB_Chats.IX_MB_Chats_User_Active_Recent düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_Chats.IX_MB_Chats_User_Active_Recent mevcut değil / not found';
END

-- Index 2: MB_Messages.IX_MB_Messages_Chat_Order
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_Messages_Chat_Order' AND object_id = OBJECT_ID('MB_Messages'))
BEGIN
    DROP INDEX [IX_MB_Messages_Chat_Order] ON [dbo].[MB_Messages];
    PRINT '✓ MB_Messages.IX_MB_Messages_Chat_Order düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_Messages.IX_MB_Messages_Chat_Order mevcut değil / not found';
END

-- Index 3: MB_Messages.IX_MB_Messages_Chat_Timestamp
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_Messages_Chat_Timestamp' AND object_id = OBJECT_ID('MB_Messages'))
BEGIN
    DROP INDEX [IX_MB_Messages_Chat_Timestamp] ON [dbo].[MB_Messages];
    PRINT '✓ MB_Messages.IX_MB_Messages_Chat_Timestamp düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_Messages.IX_MB_Messages_Chat_Timestamp mevcut değil / not found';
END

-- Index 4: MB_Feedback.IX_MB_Feedback_User_Message
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_Feedback_User_Message' AND object_id = OBJECT_ID('MB_Feedback'))
BEGIN
    DROP INDEX [IX_MB_Feedback_User_Message] ON [dbo].[MB_Feedback];
    PRINT '✓ MB_Feedback.IX_MB_Feedback_User_Message düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_Feedback.IX_MB_Feedback_User_Message mevcut değil / not found';
END

-- Index 5: MB_Users.IX_MB_Users_KullaniciAdi_Lookup
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_Users_KullaniciAdi_Lookup' AND object_id = OBJECT_ID('MB_Users'))
BEGIN
    DROP INDEX [IX_MB_Users_KullaniciAdi_Lookup] ON [dbo].[MB_Users];
    PRINT '✓ MB_Users.IX_MB_Users_KullaniciAdi_Lookup düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_Users.IX_MB_Users_KullaniciAdi_Lookup mevcut değil / not found';
END

-- Index 6: MB_Destek_Geri_Bildirim.IX_MB_Destek_Geri_Bildirim_User_Recent
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_Destek_Geri_Bildirim_User_Recent' AND object_id = OBJECT_ID('MB_Destek_Geri_Bildirim'))
BEGIN
    DROP INDEX [IX_MB_Destek_Geri_Bildirim_User_Recent] ON [dbo].[MB_Destek_Geri_Bildirim];
    PRINT '✓ MB_Destek_Geri_Bildirim.IX_MB_Destek_Geri_Bildirim_User_Recent düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_Destek_Geri_Bildirim.IX_MB_Destek_Geri_Bildirim_User_Recent mevcut değil / not found';
END

-- Index 7: MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_User_Recent
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_Destek_Hata_Bildir_User_Recent' AND object_id = OBJECT_ID('MB_Destek_Hata_Bildir'))
BEGIN
    DROP INDEX [IX_MB_Destek_Hata_Bildir_User_Recent] ON [dbo].[MB_Destek_Hata_Bildir];
    PRINT '✓ MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_User_Recent düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_User_Recent mevcut değil / not found';
END

-- Index 8: MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_Status_Recent
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_Destek_Hata_Bildir_Status_Recent' AND object_id = OBJECT_ID('MB_Destek_Hata_Bildir'))
BEGIN
    DROP INDEX [IX_MB_Destek_Hata_Bildir_Status_Recent] ON [dbo].[MB_Destek_Hata_Bildir];
    PRINT '✓ MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_Status_Recent düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_Destek_Hata_Bildir.IX_MB_Destek_Hata_Bildir_Status_Recent mevcut değil / not found';
END

-- Index 9: MB_ClaudeCode_Sessions.IX_MB_ClaudeCode_Sessions_User_Recent
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_ClaudeCode_Sessions_User_Recent' AND object_id = OBJECT_ID('MB_ClaudeCode_Sessions'))
BEGIN
    DROP INDEX [IX_MB_ClaudeCode_Sessions_User_Recent] ON [dbo].[MB_ClaudeCode_Sessions];
    PRINT '✓ MB_ClaudeCode_Sessions.IX_MB_ClaudeCode_Sessions_User_Recent düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_ClaudeCode_Sessions.IX_MB_ClaudeCode_Sessions_User_Recent mevcut değil / not found';
END

-- Index 10: MB_ClaudeCode_Runs.IX_MB_ClaudeCode_Runs_Session_Order
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MB_ClaudeCode_Runs_Session_Order' AND object_id = OBJECT_ID('MB_ClaudeCode_Runs'))
BEGIN
    DROP INDEX [IX_MB_ClaudeCode_Runs_Session_Order] ON [dbo].[MB_ClaudeCode_Runs];
    PRINT '✓ MB_ClaudeCode_Runs.IX_MB_ClaudeCode_Runs_Session_Order düşürüldü / dropped';
END
ELSE
BEGIN
    PRINT '⚠ MB_ClaudeCode_Runs.IX_MB_ClaudeCode_Runs_Session_Order mevcut değil / not found';
END

-- Summary
PRINT '';
PRINT '=== GERİ ALMA TAMAMLANDI / ROLLBACK COMPLETE ===';
PRINT 'Düşürülen endeksler / Indexes dropped: 10 (veya daha az mevcut değilse / or fewer if not all present)';
PRINT '';
PRINT 'UYARI / WARNING: Endeksler geri alındıktan sonra sorgu performansı azalabilir.';
PRINT 'WARNING: Query performance may be significantly reduced after rollback.';
PRINT 'İstenirse, performans endekslerini yeniden dağıtmanız gerekebilir.';
PRINT 'If needed, you may need to redeploy the performance indexes.';