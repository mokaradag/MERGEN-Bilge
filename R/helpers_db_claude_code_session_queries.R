# ==============================================================================
# Dosya Yolu: R/helpers_db_claude_code_session_queries.R
# Açıklama: Bilge Yolaç kalıcı oturum katmanının SAF yardımcıları: oturum
#           başlığı üretimi, ham stream metni boyut sınırı, güvenli JSON
#           serileştirme ve kullanıcı-izole liste sorgusu üretici.
#
#           Bu dosya DB bağlantısı AÇMAZ; yalnızca metin/SQL üretir. DB
#           orkestrasyonu R/helpers_db_claude_code_sessions.R içindedir ve
#           bu dosyadan SONRA yüklenir (source manifest sözleşmesi).
# ==============================================================================

#' İlk prompttan okunabilir bir oturum başlığı üretir (saf fonksiyon).
cc_db_generate_session_title <- function(prompt,
                                         fallback_time = Sys.time(),
                                         max_chars = 80L) {
  text <- tryCatch(as.character(prompt %||% "")[1], error = function(e) "")
  if (is.na(text)) text <- ""

  # Tek satıra indir, ardışık boşlukları sadeleştir.
  text <- gsub("[\r\n\t]+", " ", text)
  text <- trimws(gsub("\\s+", " ", text))

  if (!nzchar(text)) {
    return(paste("Bilge Yolaç Oturumu", format(fallback_time, "%d.%m.%Y %H:%M")))
  }

  max_chars <- max(as.integer(max_chars %||% 80L), 20L)

  if (nchar(text) > max_chars) {
    text <- paste0(substr(text, 1L, max_chars - 3L), "...")
  }

  text
}

#' Ham stream-json metnini boyut sınırına indirir (saf fonksiyon).
#'
#' Taşan içerik açık bir kesme işaretiyle sonlandırılır; böylece kalıcı
#' kayıtta kesme durumu her zaman görünür kalır.
#'
#' @return list(text = <sınırlı metin veya NULL>, truncated = TRUE/FALSE)
cc_db_truncate_raw_stream <- function(raw_text, max_chars = NULL) {
  if (is.null(raw_text) || !length(raw_text)) {
    return(list(text = NULL, truncated = FALSE))
  }

  text <- paste(as.character(raw_text), collapse = "\n")
  if (!nzchar(text)) {
    return(list(text = NULL, truncated = FALSE))
  }

  if (is.null(max_chars)) {
    max_chars <- getOption("mergen.claude_code.raw_stream_max_chars", 400000L)
  }
  max_chars <- max(as.integer(max_chars), 1000L)

  if (nchar(text) <= max_chars) {
    return(list(text = text, truncated = FALSE))
  }

  marker <- "\n[[MERGEN-RAW-STREAM-TRUNCATED]]"
  list(
    text = paste0(substr(text, 1L, max_chars - nchar(marker)), marker),
    truncated = TRUE
  )
}

# Liste/metadata değerlerini güvenli JSON metnine çevirir. Başarısızlıkta
# boş JSON döner; persist yolu asla bu yüzden kırılmaz.
.cc_db_sessions_json <- function(x, empty = "[]") {
  if (is.null(x) || length(x) == 0L) {
    return(empty)
  }

  tryCatch(
    as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")),
    error = function(e) empty
  )
}

# Kullanıcı bazlı oturum listeleme sorgusunu ve parametrelerini üretir.
# Güvenlik filtresi (UserID + IsDeleted) burada tek noktadan uygulanır.
# sqlite_yolu YALNIZCA çevrimdışı testlerde TRUE olur; üretim T-SQL kalır.
.cc_db_sessions_list_query <- function(user_id,
                                       limit,
                                       include_deleted,
                                       query,
                                       status,
                                       model,
                                       workdir,
                                       date_from,
                                       date_to,
                                       sort,
                                       sqlite_yolu) {
  where <- c("s.UserID = ?")
  params <- list(user_id)

  if (!isTRUE(include_deleted)) {
    where <- c(where, "s.IsDeleted = 0")
  }

  if (!is.null(query) && nzchar(trimws(as.character(query)[1]))) {
    aranan <- paste0("%", trimws(as.character(query)[1]), "%")
    where <- c(where, "(s.SessionTitle LIKE ? OR s.Workdir LIKE ? OR s.SourceWorkdir LIKE ?)")
    params <- c(params, list(aranan, aranan, aranan))
  }

  if (!is.null(status) && nzchar(as.character(status)[1])) {
    if (identical(as.character(status)[1], "resumable")) {
      where <- c(where, "s.ClaudeCliSessionID IS NOT NULL AND s.ClaudeCliSessionID <> ''")
    } else {
      where <- c(where, "s.Status = ?")
      params <- c(params, list(as.character(status)[1]))
    }
  }

  if (!is.null(model) && nzchar(as.character(model)[1])) {
    where <- c(where, "(s.ModelUsed = ? OR s.RuntimeModel = ?)")
    params <- c(params, list(as.character(model)[1], as.character(model)[1]))
  }

  if (!is.null(workdir) && nzchar(as.character(workdir)[1])) {
    hedef <- paste0("%", as.character(workdir)[1], "%")
    where <- c(where, "(s.Workdir LIKE ? OR s.SourceWorkdir LIKE ?)")
    params <- c(params, list(hedef, hedef))
  }

  if (!is.null(date_from) && nzchar(as.character(date_from)[1])) {
    where <- c(where, "COALESCE(s.LastRunAt, s.CreatedAt) >= ?")
    params <- c(params, list(as.character(date_from)[1]))
  }

  if (!is.null(date_to) && nzchar(as.character(date_to)[1])) {
    where <- c(where, "COALESCE(s.LastRunAt, s.CreatedAt) <= ?")
    params <- c(params, list(paste0(as.character(date_to)[1], " 23:59:59")))
  }

  order_by <- switch(
    as.character(sort %||% "last_activity")[1],
    "created" = "s.CreatedAt DESC",
    "run_count" = "RunCount DESC, COALESCE(s.LastRunAt, s.CreatedAt) DESC",
    "COALESCE(s.LastRunAt, s.CreatedAt) DESC"
  )

  limit_sql <- if (isTRUE(sqlite_yolu)) {
    "LIMIT ?"
  } else {
    "OFFSET 0 ROWS FETCH NEXT ? ROWS ONLY"
  }
  params <- c(params, list(as.integer(limit)))

  sql <- paste(
    "SELECT",
    "  s.ClaudeSessionRecordID, s.UserID, s.ClaudeCliSessionID, s.SessionTitle,",
    "  s.Workdir, s.SourceWorkdir, s.RuntimeWorkdir, s.ModelUsed, s.RuntimeModel,",
    "  s.CharacterID, s.Status, s.CreatedAt, s.LastRunAt, s.IsDeleted,",
    "  (SELECT COUNT(*) FROM MB_ClaudeCode_Runs r",
    "    WHERE r.ClaudeSessionRecordID = s.ClaudeSessionRecordID) AS RunCount,",
    "  (SELECT COUNT(*) FROM MB_ClaudeCode_Runs r",
    "    WHERE r.ClaudeSessionRecordID = s.ClaudeSessionRecordID",
    "      AND r.Status = 'failed') AS FailedRunCount,",
    "  (SELECT COUNT(*) FROM MB_ClaudeCode_Runs r",
    "    WHERE r.ClaudeSessionRecordID = s.ClaudeSessionRecordID",
    "      AND r.GeneratedDownloadsJson IS NOT NULL",
    "      AND r.GeneratedDownloadsJson <> ''",
    "      AND r.GeneratedDownloadsJson <> '[]') AS RunsWithFiles,",
    "  (SELECT r.Prompt FROM MB_ClaudeCode_Runs r",
    "    WHERE r.ClaudeSessionRecordID = s.ClaudeSessionRecordID",
    "      AND r.RunOrder = (SELECT MAX(r2.RunOrder) FROM MB_ClaudeCode_Runs r2",
    "                         WHERE r2.ClaudeSessionRecordID = s.ClaudeSessionRecordID)",
    "  ) AS LastPrompt",
    "FROM MB_ClaudeCode_Sessions s",
    "WHERE", paste(where, collapse = " AND "),
    "ORDER BY", order_by,
    limit_sql
  )

  list(sql = sql, params = params)
}
