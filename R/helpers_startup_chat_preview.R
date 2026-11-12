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
                                      name_encoding,
                                      login_timeout = NA_integer_) {
  safe_user_id <- suppressWarnings(as.integer(user_id[1]))
  if (is.na(safe_user_id) || safe_user_id <= 0L) {
    return(NULL)
  }

  # Yalnızca AÇIK NA sentineli (tek elemanlı sayısal/mantıksal NA, NaN değil)
  # mesajsız tam söyleşi listesini seçer (aynı biçim, TOP yok). "abc", Inf,
  # NULL gibi bozuk limitler sessizce sınırsız sorguya dönüşmez; 6'ya düşer.
  # mergen_startup_chat_preview_limit() ile aynı kuraldır; işçi sözleşmesini
  # genişletmemek için burada satır içi tutulur.
  tam_liste <- length(limit) == 1L && (is.logical(limit) || is.numeric(limit)) &&
    is.na(limit) && !is.nan(limit)
  safe_limit <- suppressWarnings(as.integer(limit[1]))
  if (!tam_liste && (length(safe_limit) != 1L || is.na(safe_limit) || safe_limit <= 0L)) {
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
  baglanti_args <- list(
    odbc::odbc(),
    dsn = as.character(dsn)[1],
    encoding = as.character(encoding)[1],
    name_encoding = as.character(name_encoding)[1]
  )
  # get_connection() ile aynı login sınırı: yapılandırılmış süre varsa sürücüye
  # iletilir; yoksa sürücü varsayılanı korunur (timeout HİÇ geçilmez).
  login_timeout <- suppressWarnings(as.integer(login_timeout[1]))
  if (length(login_timeout) == 1L && !is.na(login_timeout) && login_timeout >= 1L) {
    baglanti_args$timeout <- login_timeout
  }
  conn <- do.call(DBI::dbConnect, baglanti_args)
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  connect_ms <- as.numeric(difftime(Sys.time(), connect_started, units = "secs")) * 1000

  query_started <- Sys.time()
  preview_data <- DBI::dbGetQuery(
    conn,
    if (tam_liste) db_chat_list_summary_query_sql() else db_chat_preview_query_sql(safe_limit),
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

  # Tam listede (binlerce satır) ana süreçte satır satır data.frame alt
  # kümesi alınmaz; sütun vektörleri bir kez okunur, öğe erişimi O(1)'dir.
  chat_ids <- as.character(preview_data$ChatID)
  n <- nrow(preview_data)
  baslik_sutunu <- preview_data$ChatTitle
  olusturma_sutunu <- preview_data$CreateTimestamp
  son_sutunu <- preview_data$LastMessageTimestamp
  sayi_sutunu <- suppressWarnings(as.integer(preview_data$MessageCount %||% rep(0L, n)))
  formatted <- lapply(seq_len(n), function(i) {
    last_ts <- son_sutunu[i]
    if (timestamp_missing(last_ts)) {
      last_ts <- olusturma_sutunu[i]
    }

    msg_count <- sayi_sutunu[i]
    if (length(msg_count) != 1L || is.na(msg_count)) {
      msg_count <- 0L
    }

    list(
      title = baslik_sutunu[i],
      messages = NULL,
      timestamp = olusturma_sutunu[i],
      last_message_timestamp = last_ts,
      message_count = msg_count
    )
  })

  names(formatted) <- chat_ids
  formatted[chat_ids]
}

# Ön izleme limiti normalleştirici: tam liste YALNIZCA açık NA sentineliyle
# seçilir; diğer tüm geçersiz değerler (NULL, "abc", Inf, NaN, <= 0) 6'ya döner.
mergen_startup_chat_preview_limit <- function(limit) {
  if (length(limit) == 1L && (is.logical(limit) || is.numeric(limit)) &&
      is.na(limit) && !is.nan(limit)) {
    return(NA_integer_)
  }
  sayi <- suppressWarnings(as.integer(limit[1]))
  if (length(sayi) != 1L || is.na(sayi) || sayi <= 0L) 6L else sayi
}

# Arka plan tam listesi gönderimden SONRA yerelde yapılan değişiklikleri ezmez:
# yerelde eklenen söyleşiler başa eklenir, yerelde silinenler geri gelmez.
# DB'de de bulunan söyleşide yalnızca yerelde DEĞİŞEN alanlar uygulanır (ör. ad
# değişimi DB'nin daha yeni sayı/zamanını ezmez); etkinliği yerelde ilerleyen
# söyleşi başa taşınır. Yerel durum değişmediyse DB sonucu aynen uygulanır.
# (Silme/Tümünü Temizle sonrası sonuç çağıran tarafından hiç uygulanmaz.)
mergen_saved_chats_merge_newer <- function(db_chats, dispatch_snapshot, current) {
  db_chats <- db_chats %||% list()
  dispatch_snapshot <- dispatch_snapshot %||% list()
  current <- current %||% list()
  if (identical(current, dispatch_snapshot)) {
    return(db_chats)
  }
  silinen <- setdiff(names(dispatch_snapshot), names(current))
  birlesik <- db_chats[setdiff(names(db_chats), silinen)]
  degisen <- Filter(function(k) !identical(current[[k]], dispatch_snapshot[[k]]), names(current))
  etkin <- character()
  for (k in intersect(degisen, names(birlesik))) {
    once <- dispatch_snapshot[[k]]
    if (is.null(once)) {
      birlesik[[k]] <- current[[k]]
      next
    }
    for (alan in names(current[[k]])) {
      if (!identical(current[[k]][[alan]], once[[alan]])) birlesik[[k]][alan] <- list(current[[k]][[alan]])
    }
    if (!identical(current[[k]]$last_message_timestamp, once$last_message_timestamp) ||
        !identical(current[[k]]$message_count, once$message_count)) {
      etkin <- c(etkin, k)
    }
  }
  c(current[setdiff(degisen, names(birlesik))], birlesik[etkin], birlesik[setdiff(names(birlesik), etkin)])
}

# Yapılandırılmış DB login sınırı (MERGEN_DB_LOGIN_TIMEOUT_SEC); plan yoksa NA.
mergen_startup_chat_preview_login_timeout <- function() {
  plan <- tryCatch(
    if (exists(".db_login_timeout_plan", mode = "function", inherits = TRUE)) .db_login_timeout_plan(Inf),
    error = function(e) NULL
  )
  if (is.list(plan) && identical(plan$mode, "bounded")) as.integer(plan$timeout) else NA_integer_
}

# Açık worker-export sözleşmesi: yalnızca aşağıdaki adlar worker'a taşınır.
# Bu listeye oturum/reaktif nesne, bağlantı ya da geniş yardımcı zinciri
# EKLENMEZ; sözleşme test-startup-chat-preview-behavior.R ile kilitlidir.
mergen_startup_chat_preview_globals <- function(user_id, limit = 6L) {
  default_dsn <- get0(".DEFAULT_DSN", ifnotfound = "TestConnection")

  sozlesme <- list(
    startup_preview_user_id = suppressWarnings(as.integer(user_id[1])),
    startup_preview_limit = mergen_startup_chat_preview_limit(limit),
    startup_preview_dsn = Sys.getenv("DB_DSN", default_dsn),
    startup_preview_encoding = get0(".DEFAULT_DB_CLIENT_ENCODING", ifnotfound = "UTF-8"),
    # get_connection() ile aynı login sınırı planı (ana süreçte çözülür; NA =
    # sürücü varsayılanı).
    startup_preview_login_timeout = mergen_startup_chat_preview_login_timeout(),
    startup_preview_name_encoding = get0(
      ".DEFAULT_DB_NAME_ENCODING",
      ifnotfound = get0(".DEFAULT_DB_CLIENT_ENCODING", ifnotfound = "UTF-8")
    ),
    db_chat_preview_fetch_raw = db_chat_preview_fetch_raw,
    db_chat_preview_query_sql = db_chat_preview_query_sql
  )
  # Tam liste modu yalnızca özet SQL üreticisini ekler (oturum/bağlantı yok).
  if (is.na(sozlesme$startup_preview_limit)) {
    sozlesme$db_chat_list_summary_query_sql <- db_chat_list_summary_query_sql
  }
  sozlesme
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
  startup_preview_login_timeout <- preview_globals$startup_preview_login_timeout

  raw_promise <- tracked_future_promise(
    task_fn = function() {
      db_chat_preview_fetch_raw(
        user_id = startup_preview_user_id,
        limit = startup_preview_limit,
        dsn = startup_preview_dsn,
        encoding = startup_preview_encoding,
        name_encoding = startup_preview_name_encoding,
        login_timeout = startup_preview_login_timeout
      )
    },
    task_type = if (is.na(startup_preview_limit)) "startup_saved_chats" else "startup_saved_chats_preview",
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
