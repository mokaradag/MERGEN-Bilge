/*
 * MERGEN Bilge - emergency rollback for safe MB_* performance indexes
 * Date: July 2026
 *
 * Drops ONLY the final safe performance indexes from
 * docs/sql/2026-07-safe-mb-performance-indexes.sql. Do not drop PKs and do not
 * drop or alter pre-existing UQ constraints, including MB_Users(KullaniciAdi).
 * Use only if a wave introduces production symptoms and after capturing evidence.
 */

SET XACT_ABORT ON;
SET LOCK_TIMEOUT 15000;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MB_Chats_User_Active_Recent' AND object_id = OBJECT_ID(N'dbo.MB_Chats'))
    DROP INDEX IX_MB_Chats_User_Active_Recent ON dbo.MB_Chats;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MB_Messages_Chat_Order' AND object_id = OBJECT_ID(N'dbo.MB_Messages'))
    DROP INDEX IX_MB_Messages_Chat_Order ON dbo.MB_Messages;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MB_Messages_Chat_Timestamp' AND object_id = OBJECT_ID(N'dbo.MB_Messages'))
    DROP INDEX IX_MB_Messages_Chat_Timestamp ON dbo.MB_Messages;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MB_Feedback_User_Message' AND object_id = OBJECT_ID(N'dbo.MB_Feedback'))
    DROP INDEX IX_MB_Feedback_User_Message ON dbo.MB_Feedback;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MB_Users_KullaniciAdi_Lookup' AND object_id = OBJECT_ID(N'dbo.MB_Users'))
    DROP INDEX IX_MB_Users_KullaniciAdi_Lookup ON dbo.MB_Users;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MB_Destek_Geri_Bildirim_User_Recent' AND object_id = OBJECT_ID(N'dbo.MB_Destek_Geri_Bildirim'))
    DROP INDEX IX_MB_Destek_Geri_Bildirim_User_Recent ON dbo.MB_Destek_Geri_Bildirim;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MB_Destek_Hata_Bildir_User_Recent' AND object_id = OBJECT_ID(N'dbo.MB_Destek_Hata_Bildir'))
    DROP INDEX IX_MB_Destek_Hata_Bildir_User_Recent ON dbo.MB_Destek_Hata_Bildir;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MB_Destek_Hata_Bildir_Status_Recent' AND object_id = OBJECT_ID(N'dbo.MB_Destek_Hata_Bildir'))
    DROP INDEX IX_MB_Destek_Hata_Bildir_Status_Recent ON dbo.MB_Destek_Hata_Bildir;
GO
