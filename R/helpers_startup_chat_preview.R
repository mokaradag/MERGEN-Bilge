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
    butce_baslangici <- proc.time()[["elapsed"]]
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
  # (native) bağlanma çağrısını kesemez; login sınırı bütçeyi aşamaz,
  # yapılandırılmamışsa bütçe login sınırı olarak iletilir (en az 1 sn).
  if (sinirli) {
    butce_login <- max(1L, as.integer(min(ceiling(sure_sn), 2147483L)))
    baglanti_args$timeout <- if (is.null(baglanti_args$timeout)) butce_login else min(baglanti_args$timeout, butce_login)
  }
  if (sinirli) baglanti_args$interruptible <- TRUE
  conn <- do.call(DBI::dbConnect, baglanti_args)
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  connect_ms <- as.numeric(difftime(Sys.time(), connect_started, units = "secs")) * 1000
  if (sinirli) {
    # SQL Server üst sınırı (ms) aşılmaz; tam sayı taşması NA üretmez.
    kilit_ms <- as.integer(min(sure_sn, 2147483) * 1000)
    kurulum <- try(DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %d", kilit_ms)), silent = TRUE)
    # R süre sınırı dolunca sınırı silip hata verir; yakalanan kurulum hatası ana
    # sorguyu sınırsız bırakmasın diye kalan bütçe (ileti metnine bakmadan)
    # yeniden uygulanır. Bütçe bittiyse sorgu hiç başlamaz; diğer kurulum
    # hataları ölümcül değildir.
    kalan_sn <- sure_sn - (proc.time()[["elapsed"]] - butce_baslangici)
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
    parcali_getir <- function() {
      sonuc_kumesi <- DBI::dbSendQuery(conn, sql)
      on.exit(try(DBI::dbClearResult(sonuc_kumesi), silent = TRUE))
      parcalar <- list()
      repeat {
        parca <- DBI::dbFetch(sonuc_kumesi, n = 1000L)
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

  attr(veri, "mergen_preview_perf") <- list(
    connect_ms = connect_ms,
    query_ms = query_ms
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
  eksik <- function(x) is.null(x) || length(x) == 0L || is.na(x[1])
  for (k in intersect(degisen, names(birlesik))) {
    once <- dispatch_snapshot[[k]]
    db_sayi <- sayi(birlesik[[k]]$message_count)
    yerel_sayi <- sayi(current[[k]]$message_count)
    yerel_hidrate <- isTRUE(current[[k]]$hidrate_edildi) && !isTRUE(current[[k]]$baslik_yerel_degisti)
    # Başka oturum daha sonra mesaj eklediyse DB'nin sayı/zaman çifti daha yenidir.
    db_daha_yeni <- isTRUE(db_sayi > yerel_sayi)
    yerel_zaman <- current[[k]]$last_message_timestamp
    db_zaman <- birlesik[[k]]$last_message_timestamp
    yerel_zaman_daha_yeni <- !eksik(yerel_zaman) && !eksik(db_zaman) &&
      isTRUE(suppressWarnings(as.numeric(yerel_zaman)[1] > as.numeric(db_zaman)[1]))
    yerel_ileride <- isTRUE(yerel_sayi > db_sayi) ||
      (isTRUE(yerel_sayi == db_sayi) && yerel_zaman_daha_yeni)
    if (is.null(once)) {
      # Gönderimden sonra yerelde açılan/hidrate edilen söyleşi: DB girdisi
      # TABAN kalır (detay okuyucu etkinlik zamanı taşımayabilir; eksik alan
      # DB'nin zamanını silmez). Yalnızca hidrasyon sonucu önbelleklenen başlık
      # DB'nin daha yeni başlığını ezmez; yerel etkinlik DB'yi geçtiyse başa taşınır.
      taban <- birlesik[[k]]
      for (alan in names(current[[k]])) {
        deger <- current[[k]][[alan]]
        if (eksik(deger) || (alan %in% etkinlik_alanlari && !yerel_ileride)) next
        if (identical(alan, "title") && yerel_hidrate) next
        taban[alan] <- list(deger)
      }
      if (yerel_ileride) etkin <- c(etkin, k)
      # Yerelde mesaj yazıldı ve DB de ayrıca okundu: eşit sayı içerik eşitliği
      # değildir (başka sekmenin mesajı eksik olabilir). Önbellek korunur, yeniden
      # açılışta kapsamlı bir yeniden okuma istenir.
      if (!eksik(yerel_zaman) && !identical(yerel_zaman, db_zaman)) {
        taban$transkript_yenile <- TRUE
      }
      birlesik[[k]] <- taban
      next
    }
    for (alan in names(current[[k]])) {
      if (db_daha_yeni && alan %in% etkinlik_alanlari) next
      if (identical(alan, "title") && yerel_hidrate) next
      if (!identical(current[[k]][[alan]], once[[alan]])) birlesik[[k]][alan] <- list(current[[k]][[alan]])
    }
    # Gönderimden sonra hem DB hem yerel etkinlik ilerlediyse transkript iki
    # kaynağın birleşimidir; sayı eşitliği tam olduğunu kanıtlamaz.
    once_sayi <- sayi(once$message_count)
    if (isTRUE(db_sayi > once_sayi) && isTRUE(yerel_sayi > once_sayi)) {
      birlesik[[k]]$transkript_yenile <- TRUE
    }
    # DB bu oturumun güncellemesini zaten içeriyorsa DB sırası korunur; yalnızca
    # yerel etkinlik DB'nin önündeyse söyleşi başa taşınır.
    if (yerel_ileride) {
      etkin <- c(etkin, k)
    }
  }
  # Yalnızca gönderimden SONRA yerelde oluşturulan söyleşiler korunur; başka
  # oturumda silinmiş ama bu oturumda yalnızca hidrate edilmiş kayıt geri gelmez.
  yerel_yeni <- Filter(
    function(k) !isTRUE(current[[k]]$hidrate_edildi),
    setdiff(setdiff(degisen, names(birlesik)), names(dispatch_snapshot))
  )
  c(current[yerel_yeni], birlesik[etkin], birlesik[setdiff(names(birlesik), etkin)])
}

# Aktif future planının eşzamansız işçi destekleyip desteklemediğini bildirir.
# MERGEN_DISABLE_FUTURES veya PSOCK başlatma hatasında plan sequential olur;
# otomatik arka plan tam liste okuması ana olay döngüsünü bloklamasın diye
# yalnızca işçi planı etkinken çalışır (kullanıcı sekme ziyareti etkilenmez).
mergen_startup_async_worker_ready <- function() {
  if (!requireNamespace("future", quietly = TRUE)) return(FALSE)
  !inherits(tryCatch(future::plan("next"), error = function(e) NULL), "sequential")
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
    mergen_startup_chat_preview_format_staged(raw_frame, gecerli_mi = gecerli_mi)
  })
}
