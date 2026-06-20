# ==============================================================================
# Dosya Yolu: R/helpers_db_chat_read_queries.R
# Açıklama: MERGEN Bilge sohbet okuma SQL sorgu üreticileri (saf string).
#           R/helpers_db_chat_readers.R orkestrasyonundan ayrılan, bağlantısız
#           ve encoding'siz SQL şema bilgisidir. Üreticiler parametreli ('?')
#           ASCII SQL döndürür; kullanıcı izolasyonu (c.UserID = ?) ve soft-delete
#           (c.IsDeleted = 0) filtreleri bu modülde korunur.
#
# Not:
# - Bu dosya hiçbir DB bağlantısı açmaz, normalize/encode etmez ve reaktif
#   durum tutmaz. Yalnızca byte-birebir aynı SQL string'lerini üretir.
# - Okuyucular (load_chats_*, load_chat_messages_*, load_history_rows_batch)
#   bu üreticileri çağırır; davranış golden testiyle korunur.
# ==============================================================================

# Sohbet önizleme listesi (TOP N, en yeni etkinliğe göre sıralı).
db_chat_preview_query_sql <- function(limit) {
  sprintf("
      SELECT TOP %d
             c.ChatID,
             c.ChatTitle,
             c.CreateTimestamp,
             COUNT(m.MessageID) AS MessageCount,
             MAX(m.MessageTimestamp) AS LastMessageTimestamp
      FROM MB_Chats c
      LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID
      WHERE c.UserID = ? AND c.IsDeleted = 0
      GROUP BY c.ChatID, c.ChatTitle, c.CreateTimestamp
      ORDER BY COALESCE(MAX(m.MessageTimestamp), c.CreateTimestamp) DESC,
               c.CreateTimestamp DESC
    ", limit)
}

# Sohbet listesi özeti (mesajsız; sayım + son mesaj zamanı).
db_chat_list_summary_query_sql <- function() {
  "
      SELECT c.ChatID, c.ChatTitle, c.CreateTimestamp,
             COUNT(m.MessageID) AS MessageCount,
             MAX(m.MessageTimestamp) AS LastMessageTimestamp
      FROM MB_Chats c
      LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID
      WHERE c.UserID = ? AND c.IsDeleted = 0
      GROUP BY c.ChatID, c.ChatTitle, c.CreateTimestamp
      ORDER BY COALESCE(MAX(m.MessageTimestamp), c.CreateTimestamp) DESC,
               c.CreateTimestamp DESC
    "
}

# Sohbet listesi + mesajlar (with_reasoning, ReasoningContent sütununu içerir).
db_chat_list_full_query_sql <- function(with_reasoning) {
  paste0(
    "
    SELECT c.ChatID, c.ChatTitle, c.CreateTimestamp,
           m.MessageID, m.MessageContent, m.MessageType, m.MessageTimestamp, m.MessageOrder,",
    if (isTRUE(with_reasoning)) "
           m.ReasoningContent," else "",
    "
           COALESCE(MAX(m.MessageTimestamp) OVER (PARTITION BY c.ChatID), c.CreateTimestamp) AS SortTimestamp
    FROM MB_Chats c
    JOIN MB_Messages m ON c.ChatID = m.ChatID
    WHERE c.UserID = ? AND c.IsDeleted = 0
    ORDER BY SortTimestamp DESC, c.CreateTimestamp DESC, m.MessageOrder ASC
  "
  )
}

# Tek sohbetin mesajları (with_reasoning: ReasoningContent; scoped: c.UserID = ?).
db_chat_messages_query_sql <- function(with_reasoning, scoped) {
  paste0(
    "
      SELECT c.ChatTitle, c.CreateTimestamp, m.MessageID, m.MessageContent,
             m.MessageType, m.MessageTimestamp, m.MessageOrder",
    if (isTRUE(with_reasoning)) ", m.ReasoningContent" else "",
    "
      FROM MB_Chats c
      LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID
      WHERE c.ChatID = ?",
    if (isTRUE(scoped)) " AND c.UserID = ?" else "",
    "
      ORDER BY m.MessageOrder ASC
    "
  )
}

# Toplu sohbet mesajları (IN (...) placeholder ile; with_reasoning + scoped).
db_chat_messages_batch_query_sql <- function(placeholder, with_reasoning, scoped) {
  paste0(
    "SELECT c.ChatID, c.ChatTitle, c.CreateTimestamp,",
    "       m.MessageID, m.MessageContent, m.MessageType,",
    "       m.MessageTimestamp, m.MessageOrder",
    if (isTRUE(with_reasoning)) ", m.ReasoningContent" else "",
    "  FROM MB_Chats c",
    "  LEFT JOIN MB_Messages m ON c.ChatID = m.ChatID",
    " WHERE c.ChatID IN (", placeholder, ")",
    if (isTRUE(scoped)) " AND c.UserID = ?" else "",
    " ORDER BY c.ChatID ASC, m.MessageOrder ASC"
  )
}

# Hafif geçmiş satırları: sohbet başına eşleşmiş kullanıcı/asistan satır çiftleri.
db_history_rows_query_sql <- function(placeholder, scoped) {
  paste0(
    "WITH filtered AS (",
    "  SELECT c.ChatID, c.ChatTitle, m.MessageID, m.MessageContent, m.MessageType, ",
    "         m.MessageTimestamp, m.MessageOrder ",
    "    FROM MB_Chats c ",
    "    INNER JOIN MB_Messages m ON c.ChatID = m.ChatID ",
    "   WHERE c.ChatID IN (", placeholder, ")",
    if (isTRUE(scoped)) " AND c.UserID = ?" else "",
    "), ",
    "user_msgs AS (",
    "  SELECT ChatID, ChatTitle, MessageContent, MessageTimestamp, ",
    "         ROW_NUMBER() OVER (PARTITION BY ChatID ORDER BY MessageOrder ASC, MessageID ASC) AS rn ",
    "    FROM filtered ",
    "   WHERE MessageType = 'user'",
    "), ",
    "assistant_msgs AS (",
    "  SELECT ChatID, MessageContent, ",
    "         ROW_NUMBER() OVER (PARTITION BY ChatID ORDER BY MessageOrder ASC, MessageID ASC) AS rn ",
    "    FROM filtered ",
    "   WHERE MessageType IN ('ai', 'assistant')",
    ") ",
    "SELECT u.ChatID, u.ChatTitle, u.MessageTimestamp, ",
    "       LEFT(u.MessageContent, 100) AS Soru, ",
    "       LEFT(a.MessageContent, 100) AS Cevap, ",
    "       u.rn AS PairOrder ",
    "  FROM user_msgs u ",
    "  INNER JOIN assistant_msgs a ",
    "          ON a.ChatID = u.ChatID ",
    "         AND a.rn = u.rn ",
    " ORDER BY u.ChatID ASC, u.rn ASC"
  )
}
