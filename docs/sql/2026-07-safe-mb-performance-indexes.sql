/*
 * MERGEN Bilge - production-safe MB_* SQL Server performance indexes
 * Date: July 2026
 *
 * Manual DBA/operator script only. Take a verified backup first, apply outside
 * peak usage, and apply in waves. Test application startup and login after each
 * wave before continuing. This script is idempotent and contains only the final
 * safe Wave 1-4 performance indexes that were validated in production after the
 * superseded all-at-once attempt caused login failure.
 *
 * Safety contract:
 * - SET XACT_ABORT ON and SET LOCK_TIMEOUT 15000 are used in every wave.
 * - Every CREATE INDEX is protected by IF NOT EXISTS.
 * - All indexes are nonclustered and non-unique.
 * - Do not drop or alter PK/UQ constraints, including the pre-existing unique
 *   MB_Users(KullaniciAdi) constraint/index named like UQ__MB_Users__...
 * - Do not add a newly-created UNIQUE IX_MB_Users_KullaniciAdi index.
 * - The earlier all-at-once deployment is superseded/unsafe; likely caused by
 *   unsafe all-at-once deployment / schema-locking / overly aggressive unique
 *   login-path index attempt; root cause not conclusively proven.
 */

-- ============================================================================
-- Wave 1: chat list and message hydration/order paths
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

-- After Wave 1: start app if needed, verify users can log in, smoke chat list/history.

-- ============================================================================
-- Wave 2: feedback lookup path (intentionally non-unique)
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

-- After Wave 2: verify users can log in and feedback load/save/delete still works.

-- ============================================================================
-- Wave 3: login/user-profile lookup (explicit performance index is non-unique)
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

-- After Wave 3: verify users can log in before applying support/admin indexes.

-- ============================================================================
-- Wave 4: support/admin recent-list paths
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

-- Final validation: app starts with start_mergen_prod.bat, users can log in,
-- admin first-click/content-load is smoked, metadata confirms indexes are enabled,
-- and representative SET STATISTICS IO/TIME checks are reviewed.
