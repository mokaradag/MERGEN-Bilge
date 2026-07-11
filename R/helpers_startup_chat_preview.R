# ==============================================================================
# Dosya Yolu: R/helpers_startup_chat_preview.R
# Açıklama: Hızlı Başlangıç açılış yolundaki "Son Konuşmalar" (6 söyleşi)
#           ön izlemesi için DAR bağımlılık sözleşmeli worker katmanı.
#
#           Neden ayrı dosya: tracked_future_promise()'in otomatik bağımlılık
#           taraması (.GlobalEnv üzerinde getGlobalsAndPackages + özyinelemeli
#           findGlobals) uygulama büyüdükçe saniyeler sürer ve ana olay
#           döngüsünü SENKRON bloklar (Windows VM'de ölçülen ~9-14 sn açılış
#           duraklaması). Bu dosya, ön izleme sorgusunu yalnızca 2 fonksiyon +
#           skaler değerlerden oluşan AÇIK (explicit) worker-export
#           sözleşmesiyle gönderir; tarama ve oturum-ortamı serileştirmesi
#           tamamen atlanır (bkz. helpers_llm_true_streaming_worker.R deseni).
#
#           Katman ayrımı: db_chat_preview_fetch_raw() worker'da çalışır ve
#           yalnızca DBI/odbc + saf SQL üreticisine bağımlıdır; Türkçe metin
#           normalizasyonu (normalize_db_read_visible_frame zinciri) worker'a
#           taşınmaz, 6 satır için ANA süreçte db_chat_preview_format_frame()
#           ile yapılır. Böylece merkezi encoding sözleşmesi değişmeden kalır.
# ==============================================================================

# İşçi tarafı ham ön izleme sorgusu. Bağımlılık sözleşmesi bilinçli olarak
# dardır: DBI + odbc + db_chat_preview_query_sql. Bağlantı her yolda kapatılır.
# Kullanıcı kimliği geçersizse bağlantı hiç açılmaz.
db_chat_preview_fetch_raw <- function(user_id,
                                      limit,
                                      dsn,
                                      encoding,
                                      name_encoding) {
  safe_user_id <- suppressWarnings(as.integer(user_id[1]))
  if (is.na(safe_user_id) || safe_user_id <= 0L) {
    return(NULL)
  }

  safe_limit <- suppressWarnings(as.integer(limit[1]))
  if (is.na(safe_limit) || safe_limit <= 0L) {
    safe_limit <- 6L
  }

  if (is.null(dsn) || !nzchar(as.character(dsn)[1])) {
    stop("db_chat_preview_fetch_raw: DSN bulunamadı.", call. = FALSE)
  }

  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("odbc", quietly = TRUE)) {
    stop("db_chat_preview_fetch_raw: 'DBI' ve 'odbc' paketleri gereklidir.", call. = FALSE)
  }

  connect_started <- Sys.time()
  conn <- DBI::dbConnect(
    odbc::odbc(),
    dsn = as.character(dsn)[1],
    encoding = as.character(encoding)[1],
    name_encoding = as.character(name_encoding)[1]
  )
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  connect_ms <- as.numeric(difftime(Sys.time(), connect_started, units = "secs")) * 1000

  query_started <- Sys.time()
  preview_data <- DBI::dbGetQuery(
    conn,
    db_chat_preview_query_sql(safe_limit),
    params = list(safe_user_id)
  )
  query_ms <- as.numeric(difftime(Sys.time(), query_started, units = "secs")) * 1000

  attr(preview_data, "mergen_preview_perf") <- list(
    connect_ms = connect_ms,
    query_ms = query_ms
  )

  preview_data
}

# Ana süreç tarafı: ham ön izleme çerçevesini görünür-metin normalizasyonundan
# geçirip load_chats_preview_from_db() ile AYNI liste şekline biçimlendirir.
# Bu hizalama tests/testthat/test-startup-chat-preview-behavior.R ile kilitlidir;
# helpers_db_chat_readers.R'daki biçim değişirse burası da bilinçli güncellenmelidir.
db_chat_preview_format_frame <- function(preview_data) {
  if (is.null(preview_data) || !is.data.frame(preview_data) || nrow(preview_data) == 0) {
    return(list())
  }

  if (exists("normalize_db_read_visible_frame", mode = "function", inherits = TRUE)) {
    preview_data <- normalize_db_read_visible_frame(preview_data, repair_mojibake = TRUE)
  } else if (exists("normalize_text_frame_utf8", mode = "function", inherits = TRUE)) {
    preview_data <- normalize_text_frame_utf8(preview_data, repair_mojibake = TRUE)
  }

  timestamp_missing <- function(value) {
    is.null(value) || length(value) == 0L || is.na(value[1])
  }

  chat_ids <- as.character(preview_data$ChatID)
  formatted <- lapply(seq_len(nrow(preview_data)), function(i) {
    row <- preview_data[i, ]

    last_ts <- row$LastMessageTimestamp
    if (timestamp_missing(last_ts)) {
      last_ts <- row$CreateTimestamp
    }

    msg_count <- row$MessageCount %||% 0L
    msg_count <- suppressWarnings(as.integer(msg_count[1]))
    if (is.na(msg_count)) {
      msg_count <- 0L
    }

    list(
      title = row$ChatTitle,
      messages = NULL,
      timestamp = row$CreateTimestamp,
      last_message_timestamp = last_ts,
      message_count = msg_count
    )
  })

  names(formatted) <- chat_ids
  formatted[chat_ids]
}

# Açık worker-export sözleşmesi: yalnızca aşağıdaki adlar worker'a taşınır.
# Bu listeye oturum/reaktif nesne, bağlantı ya da geniş yardımcı zinciri
# EKLENMEZ; sözleşme test-startup-chat-preview-behavior.R ile kilitlidir.
mergen_startup_chat_preview_globals <- function(user_id, limit = 6L) {
  default_dsn <- get0(".DEFAULT_DSN", ifnotfound = "TestConnection")

  list(
    startup_preview_user_id = suppressWarnings(as.integer(user_id[1])),
    startup_preview_limit = suppressWarnings(as.integer(limit[1])),
    startup_preview_dsn = Sys.getenv("DB_DSN", default_dsn),
    startup_preview_encoding = get0(".DEFAULT_DB_CLIENT_ENCODING", ifnotfound = "UTF-8"),
    startup_preview_name_encoding = get0(
      ".DEFAULT_DB_NAME_ENCODING",
      ifnotfound = get0(".DEFAULT_DB_CLIENT_ENCODING", ifnotfound = "UTF-8")
    ),
    db_chat_preview_fetch_raw = db_chat_preview_fetch_raw,
    db_chat_preview_query_sql = db_chat_preview_query_sql
  )
}

# Hızlı Başlangıç ön izleme gönderimi: explicit modda tarama/serileştirme
# maliyeti olmadan worker'a gider; 6 satırlık sonuç ana süreçte normalize
# edilip biçimlendirilir. Dönen promise biçimlendirilmiş listeyi çözer.
mergen_startup_chat_preview_promise <- function(user_id,
                                                limit = 6L,
                                                session_token = NULL) {
  preview_globals <- mergen_startup_chat_preview_globals(user_id, limit = limit)

  # Yerel kopyalar test stub'larının (env yeniden bağlamayan senkron sarmalayıcı)
  # task_fn'i doğrudan çalıştırabilmesi için kapanışta da görünür tutulur.
  startup_preview_user_id <- preview_globals$startup_preview_user_id
  startup_preview_limit <- preview_globals$startup_preview_limit
  startup_preview_dsn <- preview_globals$startup_preview_dsn
  startup_preview_encoding <- preview_globals$startup_preview_encoding
  startup_preview_name_encoding <- preview_globals$startup_preview_name_encoding

  raw_promise <- tracked_future_promise(
    task_fn = function() {
      db_chat_preview_fetch_raw(
        user_id = startup_preview_user_id,
        limit = startup_preview_limit,
        dsn = startup_preview_dsn,
        encoding = startup_preview_encoding,
        name_encoding = startup_preview_name_encoding
      )
    },
    task_type = "startup_saved_chats_preview",
    session_token = session_token,
    dependency_mode = "explicit",
    globals = preview_globals,
    packages = c("DBI")
  )

  promises::then(raw_promise, onFulfilled = function(raw_frame) {
    perf <- attr(raw_frame, "mergen_preview_perf")
    if (is.list(perf) && .worker_monitor_trace_enabled()) {
      cat(sprintf(
        "[STARTUP PERF] preview_db connect_ms=%.0f query_ms=%.0f rows=%d\n",
        perf$connect_ms %||% -1,
        perf$query_ms %||% -1,
        if (is.data.frame(raw_frame)) nrow(raw_frame) else 0L
      ))
    }
    db_chat_preview_format_frame(raw_frame)
  })
}
