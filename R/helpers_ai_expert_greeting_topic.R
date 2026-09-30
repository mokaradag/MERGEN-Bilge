# ==============================================================================
# Dosya Yolu: R/helpers_ai_expert_greeting_topic.R
# Açıklama: Keşfet karşılama önekinin "son konu" bilgisi. Sorgu ana olay
#           döngüsünde değil, dar ve açık bağımlılıklı işçide çalışır; sonuç
#           oturumda kullanıcı kimliğiyle önbelleklenir.
#           Çağıran: R/server_speech_assets_runtime.R (prewarm_welcome).
# ==============================================================================

# --- Karşılama öneki için son kullanıcı istemi (işçide) ---
# Ana olay döngüsü DB'de beklemez: sorgu dar, açık bağımlılıklı işçide çalışır
# (bkz. R/helpers_startup_chat_preview.R deseni). Metin normalizasyonu ana
# süreçte yapılır.
# İsteğe bağlı kişiselleştirme işçiyi süresiz tutmaz: bağlantı ve sorgu
# `sure_sn` ile sınırlıdır (sürücü login zaman aşımı + kesilebilir yürütme).
ai_expert_recent_prompt_fetch_raw <- function(user_id, dsn, encoding, name_encoding, sure_sn = 8) {
  uid <- if (is.integer(user_id) && length(user_id) == 1L && !is.na(user_id)) user_id else NA_integer_
  if (is.na(uid) || uid <= 0L || is.null(dsn) || !nzchar(as.character(dsn)[1])) return(NULL)
  setTimeLimit(elapsed = sure_sn, transient = TRUE)
  on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
  conn <- DBI::dbConnect(odbc::odbc(), dsn = as.character(dsn)[1],
                         encoding = as.character(encoding)[1],
                         name_encoding = as.character(name_encoding)[1],
                         timeout = max(1L, as.integer(sure_sn)), interruptible = TRUE)
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  try(DBI::dbExecute(conn, sprintf("SET LOCK_TIMEOUT %d", as.integer(sure_sn * 1000))), silent = TRUE)
  sonuc <- DBI::dbGetQuery(conn, paste(
    "SELECT TOP 1 m.MessageContent FROM MB_Messages m JOIN MB_Chats c ON m.ChatID = c.ChatID",
    "WHERE c.UserID = ? AND m.MessageType = 'user' AND c.IsDeleted = 0",
    "ORDER BY m.MessageTimestamp DESC"
  ), params = list(uid))
  if (nrow(sonuc)) as.character(sonuc$MessageContent) else NULL
}

# Son istem promise'i oturumda kullanıcı kimliğiyle önbelleklenir (onay/iptal
# tekrarı sorguyu yinelemez). İşçi gönderilemezse konu atlanır (NULL).
ai_expert_recent_prompt_promise <- function(session, user_id) {
  # Kayıplı kimlik (ör. 7.9) başka kullanıcıya kısaltılmaz; reddedilir.
  uid <- if (exists("mergen_canonical_user_id", mode = "function")) {
    mergen_canonical_user_id(user_id)
  } else if (is.numeric(user_id) && length(user_id) == 1L && isTRUE(user_id == trunc(user_id))) {
    suppressWarnings(as.integer(user_id))
  } else {
    0L
  }
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (length(uid) != 1L || is.na(uid) || uid <= 0L || !exists("tracked_future_promise", mode = "function")) {
    return(promises::promise_resolve(NULL))
  }
  onbellek <- if (is.environment(ud)) ud$ai_expert_recent_prompt else NULL
  if (is.list(onbellek) && identical(onbellek$uid, uid) &&
      (isTRUE(onbellek$pending) || isTRUE(as.numeric(Sys.time()) - onbellek$t < 30))) {
    return(onbellek$promise)
  }
  dsn <- Sys.getenv("DB_DSN", get0(".DEFAULT_DSN", ifnotfound = ""))
  kodlama <- get0(".DEFAULT_DB_CLIENT_ENCODING", ifnotfound = "UTF-8")
  ad_kodlama <- get0(".DEFAULT_DB_NAME_ENCODING", ifnotfound = kodlama)
  sure_sn <- 8
  gorev <- tryCatch(tracked_future_promise(
    task_fn = function() ai_expert_recent_prompt_fetch_raw(uid, dsn, kodlama, ad_kodlama, sure_sn),
    task_type = "ai_expert_greeting_topic",
    session_token = tryCatch(session$token, error = function(e) NULL),
    dependency_mode = "explicit",
    globals = list(ai_expert_recent_prompt_fetch_raw = ai_expert_recent_prompt_fetch_raw,
                   uid = uid, dsn = dsn, kodlama = kodlama, ad_kodlama = ad_kodlama, sure_sn = sure_sn),
    packages = c("DBI", "odbc")
  ), error = function(e) NULL)
  if (is.null(gorev)) return(promises::promise_resolve(NULL))
  sonuc <- promises::catch(promises::then(gorev, function(ham) {
    if (is.environment(ud) && is.list(ud$ai_expert_recent_prompt) &&
        identical(ud$ai_expert_recent_prompt$promise, sonuc)) {
      ud$ai_expert_recent_prompt$pending <- FALSE
      ud$ai_expert_recent_prompt$t <- as.numeric(Sys.time())
    }
    if (is.null(ham)) return(NULL)
    if (exists("normalize_utf8_text", mode = "function")) normalize_utf8_text(ham) else enc2utf8(ham)
  }), function(e) {
    # Hata önbelleklenmez: sonraki karşılama yeniden dener.
    if (is.environment(ud) && is.list(ud$ai_expert_recent_prompt) &&
        identical(ud$ai_expert_recent_prompt$promise, sonuc)) {
      ud$ai_expert_recent_prompt <- NULL
    }
    NULL
  })
  if (is.environment(ud)) ud$ai_expert_recent_prompt <- list(uid = uid, promise = sonuc, pending = TRUE, t = as.numeric(Sys.time()))
  sonuc
}
