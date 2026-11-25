# ==============================================================================
# Dosya Yolu: R/helpers_startup_chat_preview.R
# Açıklama: Hızlı Başlangıç açılış yolundaki "Son Konuşmalar" (6 söyleşi)
#           ön izlemesi için DAR bağımlılık sözleşmeli worker katmanı.
#
#           Neden ayrı dosya: tracked_future_promise()'in otomatik bağımlılık
#           taraması (.GlobalEnv üzerinde getGlobalsAndPackages + özyinelemeli
#           findGlobals) uygulama büyüdükçe saniyeler sürer ve ana olay
#           döngüsünü SENKRON bloklar (Windows VM'de ölçülen ~9-14 sn açılış
#           duraklaması). Bu dosya, ön izleme sorgusunu yalnızca 1 fonksiyon +
#           skaler değerlerden oluşan AÇIK (explicit) worker-export
#           sözleşmesiyle gönderir; tarama ve oturum-ortamı serileştirmesi
#           tamamen atlanır (bkz. helpers_llm_true_streaming_worker.R deseni).
#
#           Katman ayrımı: worker yalnızca mergen_bounded_db_fetch_raw()
#           çalıştırır (DBI/odbc); SQL ana süreçte seçilir; Türkçe metin
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
# saat: bütçe muhasebesinin saati (geçen sn); varsayılan proc.time. Testler
# zamanlayıcı duraklamasından bağımsız denetim için sanal saat verebilir.
# varsayilan_login: bütçeli okumada login sınırı yapılandırılmamışsa kullanılan
# tavan (helpers_db_connection.R .DB_DEFAULT_LOGIN_TIMEOUT_SEC ile aynı; işçi
# yükü kendine yeterli kalsın diye değer olarak taşınır, testle eşitliği kilitli).
mergen_bounded_db_fetch_raw <- function(sql, params, dsn, encoding, name_encoding,
                                        login_timeout = NA_integer_,
                                        query_timeout = NA_real_,
                                        saat = function() proc.time()[["elapsed"]],
                                        varsayilan_login = 30L) {
  if (is.null(dsn) || !nzchar(as.character(dsn)[1])) {
    stop("mergen_bounded_db_fetch_raw: DSN bulunamadı.", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("odbc", quietly = TRUE)) {
    stop("mergen_bounded_db_fetch_raw: 'DBI' ve 'odbc' paketleri gereklidir.", call. = FALSE)
  }

  sure_sn <- suppressWarnings(as.numeric(query_timeout[1]))
  sinirli <- length(sure_sn) == 1L && is.finite(sure_sn) && sure_sn > 0
  if (sinirli && length(params)) {
    # odbc 1.7: parametreli (bind) yürütme ana iş parçacığında eşzamanlıdır ve
    # süre sınırıyla kesilemez; bütçe yalnızca doğrudan (immediate) kesilebilir
    # yürütmede SQLCancel ile uygulanır. Bu yüzden yalnızca doğrulanmış tam sayı
    # parametreler güvenli SQL sabitine çevrilir; başka tür bütçesiz
    # yürütülmez (kapalı-başarısız).
    tam_sayi <- vapply(params, function(x) {
      length(x) == 1L && is.numeric(x) && is.finite(x) && x == trunc(x) &&
        abs(x) <= .Machine$integer.max
    }, logical(1))
    if (!all(tam_sayi)) {
      stop("mergen_bounded_db_fetch_raw: bütçeli okuma yalnızca tam sayı parametre kabul eder.", call. = FALSE)
    }
    sql <- as.character(DBI::sqlInterpolate(DBI::ANSI(), sql, .dots = lapply(params, as.integer)))
    params <- NULL
  }
  if (sinirli) {
    # Önce kaydedilir, önce çalışır: bağlantı kapatma süre sınırına takılmaz.
    setTimeLimit(elapsed = sure_sn, transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
    butce_baslangici <- saat()
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
  # Bütçeli okumada bağlantı denemesi de bütçeye dahildir: setTimeLimit yerel
  # (native) bağlanma çağrısını kesemez; login sınırı bütçeyi aşamaz. Tavan
  # yapılandırılmış sınır, yoksa varsayılan login sınırıdır (tüm sorgu bütçesi
  # değil). Saniye aşağı yuvarlanır (4.2 sn -> 4 sn; bütçe aşılmaz). Sürücü
  # saniye çözünürlüğündedir ve 0 "sınırsız" demektir: 1 sn altı bütçede login
  # sınırı BİLİNÇLİ olarak 1 sn'dir (bağlanma bütçeyi en çok 1 sn'den az aşabilir;
  # bağlantı sonrası kalan bütçe ayrıca denetlenir ve sorgu süre sınırıyla koşar).
  if (sinirli) {
    butce_login <- max(1L, as.integer(min(floor(sure_sn), 2147483L)))
    # İşçi yükü kendine yeterlidir: `%||%` gibi dış yardımcılara dayanılmaz.
    tavan <- if (is.null(baglanti_args$timeout)) suppressWarnings(as.integer(varsayilan_login[1])) else baglanti_args$timeout
    if (length(tavan) != 1L || is.na(tavan) || tavan < 1L) tavan <- butce_login
    baglanti_args$timeout <- min(tavan, butce_login)
  }
  if (sinirli) baglanti_args$interruptible <- TRUE
  conn <- do.call(DBI::dbConnect, baglanti_args)
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  connect_ms <- as.numeric(difftime(Sys.time(), connect_started, units = "secs")) * 1000
  # Bağlantı kurulumu bütçeyi tükettiyse oturum kurulumu (SET LOCK_TIMEOUT) dahil
  # hiçbir deyim gönderilmez; bağlantı on.exit ile kapanır.
  if (sinirli && (saat() - butce_baslangici) >= sure_sn) {
    stop("mergen_bounded_db_fetch_raw: sorgu süre bütçesi bağlantı kurulumunda tükendi.", call. = FALSE)
  }
  if (sinirli) {
    # SQL Server üst sınırı (ms) aşılmaz; tam sayı taşması NA üretmez.
    kilit_ms <- as.integer(min(sure_sn, 2147483) * 1000)
    kurulum <- try(DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %d", kilit_ms)), silent = TRUE)
    # R süre sınırı dolunca sınırı silip hata verir; yakalanan kurulum hatası ana
    # sorguyu sınırsız bırakmasın diye kalan bütçe (ileti metnine bakmadan)
    # yeniden uygulanır. Bütçe bittiyse sorgu hiç başlamaz; diğer kurulum
    # hataları ölümcül değildir.
    kalan_sn <- sure_sn - (saat() - butce_baslangici)
    if (!is.finite(kalan_sn) || kalan_sn <= 0) {
      if (inherits(kurulum, "try-error") && inherits(attr(kurulum, "condition"), "condition")) {
        stop(attr(kurulum, "condition"))
      }
      stop("mergen_bounded_db_fetch_raw: sorgu süre bütçesi kurulumda tükendi.", call. = FALSE)
    }
    setTimeLimit(elapsed = kalan_sn, transient = TRUE)
  }

  query_started <- Sys.time()
  veri <- if (sinirli) {
    # SINIR: SQLCancel yalnızca doğrudan YÜRÜTMEYİ kesilebilir kılar; odbc 1.7
    # satırları ayrı (yerel) getirme çağrılarıyla alır ve sürücüde bekleyen tek
    # bir getirme çağrısı R süre sınırını o çağrı dönene dek denetleyemez. Bu
    # nedenle satırlar sınırlı parçalarla getirilir: süre sınırı parçalar
    # arasında denetlenir, aşım en çok tek parçanın süresiyle sınırlıdır. Bu
    # uçtan uca katı bir son tarih DEĞİLDİR (bkz. docs/performance-improvement-plan.md).
    # Bütçe her parçadan ÖNCE ve döndükten hemen SONRA (son parça dahil)
    # denetlenir: süresi dolmuş okuma yeni bir yerel getirme başlatmaz ve
    # olağan temizlik yolundan (on.exit) hatayla çıkar.
    butce_denetle <- function() {
      if ((saat() - butce_baslangici) >= sure_sn) {
        stop("mergen_bounded_db_fetch_raw: sorgu süre bütçesi satır getirme sırasında tükendi.", call. = FALSE)
      }
    }
    parcali_getir <- function() {
      sonuc_kumesi <- DBI::dbSendQuery(conn, sql)
      on.exit(try(DBI::dbClearResult(sonuc_kumesi), silent = TRUE))
      parcalar <- list()
      repeat {
        butce_denetle()
        parca <- DBI::dbFetch(sonuc_kumesi, n = 1000L)
        butce_denetle()
        parcalar[[length(parcalar) + 1L]] <- parca
        if (isTRUE(DBI::dbHasCompleted(sonuc_kumesi)) || !NROW(parca)) break
      }
      if (length(parcalar) == 1L) parcalar[[1L]] else do.call(rbind, parcalar)
    }
    parcali_getir()
  } else {
    DBI::dbGetQuery(conn, sql, params = params)
  }
  query_ms <- as.numeric(difftime(Sys.time(), query_started, units = "secs")) * 1000

  # sorgu_baslangici: okumanın başladığı an (epoch sn); tam liste birleştirmesi
  # hidrasyonla gelen alanların bu okumadan taze olup olmadığını buna göre seçer.
  attr(veri, "mergen_preview_perf") <- list(
    connect_ms = connect_ms,
    query_ms = query_ms,
    sorgu_baslangici = as.numeric(query_started)
  )

  veri
}

# Ana süreç tarafı SQL seçimi: tam liste YALNIZCA açık NA sentineliyle (özet
# SQL, TOP yok); diğer tüm limitler mergen_startup_chat_preview_limit() kuralıyla
# ön izleme SQL'ine düşer. İşçiye yalnızca hazır SQL metni gider.
mergen_startup_chat_preview_sql <- function(limit) {
  safe_limit <- mergen_startup_chat_preview_limit(limit)
  if (is.na(safe_limit)) db_chat_list_summary_query_sql() else db_chat_preview_query_sql(safe_limit)
}

# Ham ön izleme okuması (ana süreçte ya da tam uygulama yüklü bağlamda).
# Kullanıcı kimliği geçersizse bağlantı hiç açılmaz. Açılış işçi görevi bunu
# KULLANMAZ: iç içe arama işçide future/callr'ın globals'ı globalenv'e örtük
# kopyalamasına dayanırdı; görev SQL'i ana süreçte seçip
# mergen_bounded_db_fetch_raw'ı doğrudan çağırır (sözleşme kendine yeterlidir).
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

  if (is.null(dsn) || !nzchar(as.character(dsn)[1])) {
    stop("db_chat_preview_fetch_raw: DSN bulunamadı.", call. = FALSE)
  }

  mergen_bounded_db_fetch_raw(
    mergen_startup_chat_preview_sql(limit),
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

# Aktif future planının eşzamansız işçi destekleyip desteklemediğini bildirir.
# MERGEN_DISABLE_FUTURES veya PSOCK başlatma hatasında plan sequential olur;
# otomatik arka plan tam liste okuması ana olay döngüsünü bloklamasın diye
# yalnızca işçi planı etkinken çalışır (kullanıcı sekme ziyareti etkilenmez).
# Plan sorgusu hata verirse işçi DOĞRULANAMAMIŞ sayılır (FALSE): yalnızca
# doğrulanmış eşzamansız plan TRUE döner.
mergen_startup_async_worker_ready <- function() {
  if (!requireNamespace("future", quietly = TRUE)) return(FALSE)
  plan <- tryCatch(future::plan("next"), error = function(e) NULL)
  !is.null(plan) && !inherits(plan, c("sequential", "uniprocess"))
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
# EKLENMEZ. Tek fonksiyon global'i (mergen_bounded_db_fetch_raw) yalnızca
# base/DBI/odbc'ye bağlıdır; SQL ana süreçte seçilip metin olarak gider.
# Sözleşme test-startup-chat-preview-behavior.R ile kilitlidir.
mergen_startup_chat_preview_globals <- function(user_id, limit = 6L) {
  yapilandirma <- mergen_startup_db_worker_config()
  safe_limit <- mergen_startup_chat_preview_limit(limit)

  list(
    startup_preview_user_id = suppressWarnings(as.integer(user_id[1])),
    startup_preview_limit = safe_limit,
    startup_preview_sql = mergen_startup_chat_preview_sql(safe_limit),
    startup_preview_dsn = yapilandirma$dsn,
    startup_preview_encoding = yapilandirma$encoding,
    startup_preview_login_timeout = yapilandirma$login_timeout,
    startup_preview_query_timeout = yapilandirma$query_timeout,
    startup_preview_name_encoding = yapilandirma$name_encoding,
    mergen_bounded_db_fetch_raw = mergen_bounded_db_fetch_raw
  )
}

# Büyük tam listede normalizasyon + biçimlendirme olay döngüsünü tek geri
# çağrıda tutmaz: dilim satırlık parçalar ayrı döngü turlarında işlenir (diğer
# oturumlar arada ilerler). Normalizasyon değer başınadır; dilimleme sonucu
# değiştirmez. Küçük listeler (ön izleme) doğrudan biçimlendirilir.
# gecerli_mi: oturum kapandığında veya nesil eskidiğinde kalan dilimler
# işlenmeden durdurulur.
mergen_startup_chat_preview_format_staged <- function(raw_frame, dilim = 500L, gecerli_mi = NULL) {
  if (is.function(gecerli_mi) && !isTRUE(gecerli_mi())) {
    return(NULL)
  }
  n <- if (is.data.frame(raw_frame)) nrow(raw_frame) else 0L
  if (n <= dilim) {
    return(db_chat_preview_format_frame(raw_frame))
  }
  promises::promise(function(resolve, reject) {
    parcalar <- list()
    bas <- 1L
    adim <- function() {
      tryCatch({
        if (is.function(gecerli_mi) && !isTRUE(gecerli_mi())) {
          return(resolve(NULL))
        }
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
                                                session_token = NULL,
                                                gecerli_mi = NULL) {
  preview_globals <- mergen_startup_chat_preview_globals(user_id, limit = limit)

  # Yerel kopyalar test stub'larının (env yeniden bağlamayan senkron sarmalayıcı)
  # task_fn'i doğrudan çalıştırabilmesi için kapanışta da görünür tutulur.
  startup_preview_user_id <- preview_globals$startup_preview_user_id
  startup_preview_limit <- preview_globals$startup_preview_limit
  startup_preview_sql <- preview_globals$startup_preview_sql
  startup_preview_dsn <- preview_globals$startup_preview_dsn
  startup_preview_encoding <- preview_globals$startup_preview_encoding
  startup_preview_name_encoding <- preview_globals$startup_preview_name_encoding
  startup_preview_login_timeout <- preview_globals$startup_preview_login_timeout
  startup_preview_query_timeout <- preview_globals$startup_preview_query_timeout

  raw_promise <- tracked_future_promise(
    task_fn = function() {
      # Geçersiz kimlikte bağlantı hiç açılmaz.
      if (length(startup_preview_user_id) != 1L || is.na(startup_preview_user_id) ||
          startup_preview_user_id <= 0L) {
        return(NULL)
      }
      mergen_bounded_db_fetch_raw(
        startup_preview_sql,
        params = list(startup_preview_user_id),
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
    packages = c("DBI"),
    # Kuyrukta eskiyen (sahip/nesil değişmiş) okuma işçi yuvası almadan düşer.
    start_check = if (is.function(gecerli_mi)) gecerli_mi else NULL
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
    # DB okumasının anı biçimlendirilmiş listeye taşınır (birleştirme tazelik
    # karşılaştırması için); kademeli biçimlendirmede promise sonucuna eklenir.
    okuma_zamani <- if (is.list(perf)) perf$sorgu_baslangici else NULL
    zaman_ekle <- function(liste) {
      if (is.list(liste) && length(okuma_zamani)) attr(liste, "mergen_okuma_zamani") <- okuma_zamani
      liste
    }
    bicimli <- mergen_startup_chat_preview_format_staged(raw_frame, gecerli_mi = gecerli_mi)
    if (promises::is.promise(bicimli)) promises::then(bicimli, zaman_ekle) else zaman_ekle(bicimli)
  })
}
