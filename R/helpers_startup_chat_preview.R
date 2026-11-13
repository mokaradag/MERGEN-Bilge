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

# İşçi tarafı SINIRLI ham DB okuması (açık işçi sözleşmeleri ortak kullanır).
# Asılı kalan bir sorgu işçiyi süresiz tutmaz: query_timeout verildiğinde
# bağlantı + sorgu toplam süresi setTimeLimit ile sınırlanır, sürücü kesilebilir
# (interruptible) açılır ve kilit beklemesi LOCK_TIMEOUT ile aynı bütçeye
# bağlanır (helpers_ai_expert_greeting_topic.R deseni). Süre dolunca okuma hata
# verir; promise reddedilir ve işçi serbest kalır. Bağlantı her yolda kapanır.
mergen_bounded_db_fetch_raw <- function(sql, params, dsn, encoding, name_encoding,
                                        login_timeout = NA_integer_,
                                        query_timeout = NA_real_) {
  if (is.null(dsn) || !nzchar(as.character(dsn)[1])) {
    stop("mergen_bounded_db_fetch_raw: DSN bulunamadı.", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("odbc", quietly = TRUE)) {
    stop("mergen_bounded_db_fetch_raw: 'DBI' ve 'odbc' paketleri gereklidir.", call. = FALSE)
  }

  sure_sn <- suppressWarnings(as.numeric(query_timeout[1]))
  sinirli <- length(sure_sn) == 1L && is.finite(sure_sn) && sure_sn > 0
  if (sinirli) {
    # Önce kaydedilir, önce çalışır: bağlantı kapatma süre sınırına takılmaz.
    setTimeLimit(elapsed = sure_sn, transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
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
  if (sinirli) baglanti_args$interruptible <- TRUE
  conn <- do.call(DBI::dbConnect, baglanti_args)
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  connect_ms <- as.numeric(difftime(Sys.time(), connect_started, units = "secs")) * 1000
  if (sinirli) {
    # SQL Server üst sınırı (ms) aşılmaz; tam sayı taşması NA üretmez.
    kilit_ms <- as.integer(min(sure_sn, 2147483) * 1000)
    try(DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %d", kilit_ms)), silent = TRUE)
  }

  query_started <- Sys.time()
  veri <- DBI::dbGetQuery(conn, sql, params = params)
  query_ms <- as.numeric(difftime(Sys.time(), query_started, units = "secs")) * 1000

  attr(veri, "mergen_preview_perf") <- list(
    connect_ms = connect_ms,
    query_ms = query_ms
  )

  veri
}

# İşçi tarafı ham ön izleme sorgusu. Bağımlılık sözleşmesi bilinçli olarak
# dardır: DBI + odbc + SQL üreticileri + mergen_bounded_db_fetch_raw.
# Kullanıcı kimliği geçersizse bağlantı hiç açılmaz.
db_chat_preview_fetch_raw <- function(user_id,
                                      limit,
                                      dsn,
                                      encoding,
                                      name_encoding,
                                      login_timeout = NA_integer_,
                                      query_timeout = NA_real_) {
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

  mergen_bounded_db_fetch_raw(
    if (tam_liste) db_chat_list_summary_query_sql() else db_chat_preview_query_sql(safe_limit),
    params = list(safe_user_id),
    dsn = dsn, encoding = encoding, name_encoding = name_encoding,
    login_timeout = login_timeout, query_timeout = query_timeout
  )
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
# Gönderim anında var olup DB sonucunda olmayan söyleşi (başka oturumda
# silindi) yerel değişikliği olsa da geri getirilmez; yalnızca gönderimden
# SONRA yerelde açılan söyleşiler korunur. DB'de etkinliği (mesaj sayısı)
# yereldekinden ileride olan söyleşide etkinlik alanları DB'den kalır.
# (Silme/Tümünü Temizle sonrası sonuç çağıran tarafından hiç uygulanmaz.)
# silinenler: bu oturumda DB'de gerçekten silinen kimlikler (anlık görüntüde
# olmasalar da); DB sonucundan her durumda önce çıkarılır, kısayol dahil.
mergen_saved_chats_merge_newer <- function(db_chats, dispatch_snapshot, current, silinenler = character()) {
  db_chats <- db_chats %||% list()
  silinenler <- as.character(silinenler %||% character())
  if (length(silinenler) && length(names(db_chats))) db_chats <- db_chats[!(names(db_chats) %in% silinenler)]
  dispatch_snapshot <- dispatch_snapshot %||% list()
  current <- current %||% list()
  if (identical(current, dispatch_snapshot)) {
    return(db_chats)
  }
  silinen <- setdiff(names(dispatch_snapshot), names(current))
  birlesik <- db_chats[setdiff(names(db_chats), silinen)]
  degisen <- Filter(function(k) !identical(current[[k]], dispatch_snapshot[[k]]), names(current))
  etkinlik_alanlari <- c("last_message_timestamp", "message_count")
  sayi <- function(x) suppressWarnings(as.integer(x %||% NA_integer_)[1])
  etkin <- character()
  for (k in intersect(degisen, names(birlesik))) {
    once <- dispatch_snapshot[[k]]
    if (is.null(once)) {
      birlesik[[k]] <- current[[k]]
      next
    }
    # Başka oturum daha sonra mesaj eklediyse DB'nin sayı/zaman çifti daha yenidir.
    db_daha_yeni <- isTRUE(sayi(birlesik[[k]]$message_count) > sayi(current[[k]]$message_count))
    for (alan in names(current[[k]])) {
      if (db_daha_yeni && alan %in% etkinlik_alanlari) next
      if (!identical(current[[k]][[alan]], once[[alan]])) birlesik[[k]][alan] <- list(current[[k]][[alan]])
    }
    if (!db_daha_yeni &&
        (!identical(current[[k]]$last_message_timestamp, once$last_message_timestamp) ||
         !identical(current[[k]]$message_count, once$message_count))) {
      etkin <- c(etkin, k)
    }
  }
  yerel_yeni <- setdiff(setdiff(degisen, names(birlesik)), names(dispatch_snapshot))
  c(current[yerel_yeni], birlesik[etkin], birlesik[setdiff(names(birlesik), etkin)])
}

# Yapılandırılmış DB login sınırı (MERGEN_DB_LOGIN_TIMEOUT_SEC); plan yoksa NA.
mergen_startup_chat_preview_login_timeout <- function() {
  plan <- tryCatch(
    if (exists(".db_login_timeout_plan", mode = "function", inherits = TRUE)) .db_login_timeout_plan(Inf),
    error = function(e) NULL
  )
  if (is.list(plan) && identical(plan$mode, "bounded")) as.integer(plan$timeout) else NA_integer_
}

# Açılış DB işçilerinin ortak skaler yapılandırması (ana süreçte çözülür).
# Sorgu süre bütçesi işçinin asılı bir sorguda süresiz tutulmasını önler;
# mergen.startup_db_query_timeout_secs ile ayarlanabilir (varsayılan 60 sn).
mergen_startup_db_worker_config <- function() {
  default_dsn <- get0(".DEFAULT_DSN", ifnotfound = "TestConnection")
  sure <- suppressWarnings(as.numeric(getOption("mergen.startup_db_query_timeout_secs", 60))[1])
  if (length(sure) != 1L || !is.finite(sure) || sure <= 0) sure <- 60
  list(
    dsn = Sys.getenv("DB_DSN", default_dsn),
    encoding = get0(".DEFAULT_DB_CLIENT_ENCODING", ifnotfound = "UTF-8"),
    name_encoding = get0(
      ".DEFAULT_DB_NAME_ENCODING",
      ifnotfound = get0(".DEFAULT_DB_CLIENT_ENCODING", ifnotfound = "UTF-8")
    ),
    # get_connection() ile aynı login sınırı planı (NA = sürücü varsayılanı).
    login_timeout = mergen_startup_chat_preview_login_timeout(),
    query_timeout = sure
  )
}

# Açık worker-export sözleşmesi: yalnızca aşağıdaki adlar worker'a taşınır.
# Bu listeye oturum/reaktif nesne, bağlantı ya da geniş yardımcı zinciri
# EKLENMEZ; sözleşme test-startup-chat-preview-behavior.R ile kilitlidir.
mergen_startup_chat_preview_globals <- function(user_id, limit = 6L) {
  yapilandirma <- mergen_startup_db_worker_config()

  sozlesme <- list(
    startup_preview_user_id = suppressWarnings(as.integer(user_id[1])),
    startup_preview_limit = mergen_startup_chat_preview_limit(limit),
    startup_preview_dsn = yapilandirma$dsn,
    startup_preview_encoding = yapilandirma$encoding,
    startup_preview_login_timeout = yapilandirma$login_timeout,
    startup_preview_query_timeout = yapilandirma$query_timeout,
    startup_preview_name_encoding = yapilandirma$name_encoding,
    db_chat_preview_fetch_raw = db_chat_preview_fetch_raw,
    db_chat_preview_query_sql = db_chat_preview_query_sql,
    mergen_bounded_db_fetch_raw = mergen_bounded_db_fetch_raw
  )
  # Tam liste modu yalnızca özet SQL üreticisini ekler (oturum/bağlantı yok).
  if (is.na(sozlesme$startup_preview_limit)) {
    sozlesme$db_chat_list_summary_query_sql <- db_chat_list_summary_query_sql
  }
  sozlesme
}

# Büyük tam listede normalizasyon + biçimlendirme olay döngüsünü tek geri
# çağrıda tutmaz: dilim satırlık parçalar ayrı döngü turlarında işlenir (diğer
# oturumlar arada ilerler). Normalizasyon değer başınadır; dilimleme sonucu
# değiştirmez. Küçük listeler (ön izleme) doğrudan biçimlendirilir.
mergen_startup_chat_preview_format_staged <- function(raw_frame, dilim = 500L) {
  n <- if (is.data.frame(raw_frame)) nrow(raw_frame) else 0L
  if (n <= dilim) {
    return(db_chat_preview_format_frame(raw_frame))
  }
  promises::promise(function(resolve, reject) {
    parcalar <- list()
    bas <- 1L
    adim <- function() {
      tryCatch({
        son <- min(n, bas + dilim - 1L)
        parcalar[[length(parcalar) + 1L]] <<- db_chat_preview_format_frame(raw_frame[bas:son, , drop = FALSE])
        bas <<- son + 1L
        if (bas > n) resolve(do.call(c, parcalar)) else later::later(adim, 0)
      }, error = function(e) reject(e))
    }
    adim()
  })
}

# Hızlı Başlangıç ön izleme gönderimi: explicit modda tarama/serileştirme
# maliyeti olmadan worker'a gider; sonuç ana süreçte normalize edilip
# biçimlendirilir (tam listede dilimlerle). Dönen promise listeyi çözer.
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
  startup_preview_query_timeout <- preview_globals$startup_preview_query_timeout

  raw_promise <- tracked_future_promise(
    task_fn = function() {
      db_chat_preview_fetch_raw(
        user_id = startup_preview_user_id,
        limit = startup_preview_limit,
        dsn = startup_preview_dsn,
        encoding = startup_preview_encoding,
        name_encoding = startup_preview_name_encoding,
        login_timeout = startup_preview_login_timeout,
        query_timeout = startup_preview_query_timeout
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
    mergen_startup_chat_preview_format_staged(raw_frame)
  })
}
