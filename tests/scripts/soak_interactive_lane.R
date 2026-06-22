# ==============================================================================
# Dosya Yolu: tests/scripts/soak_interactive_lane.R
# Aciklama:
#   INTERACTIVE (etkilesimli oturum) soak seridi. GET-only HTTP seritinden farkli
#   olarak, GERCEK uygulama yardimcilarini ve ISLEM-GUVENLI DB HAVUZUNU gercek bir
#   DBI arka ucuna (RSQLite, gecici dosya) karsi calistirir. Her "oturum" sohbet
#   benzeri bir eylem dizisi yurutur:
#     - oturum ac (kullanici kimligi + kisisel anahtar; anahtar izolasyonu)
#     - sohbet olustur (with_db_transaction INSERT)
#     - kullanici mesaji kaydet (with_db_transaction; Turkce metin)
#     - streaming delta isle (gercek mergen_stream_classify_poll_lines)
#     - asistan mesaji kaydet (with_db_transaction)
#     - stop/iptal karari (gercek mergen_stream_abort_cleanup_plan) + ISLEM ROLLBACK
#     - kucuk dosya yukle (gercek validate_uploaded_file)
#     - kayitli/gecmis oku (with_db_connection SELECT; kullanici-kapsamli)
#     - oturum kapat
#
#   Olculenler: basari orani, p50/p95/p99 gecikme, throughput, DB havuz sayaclari
#   (checkout/return/leak/tx), mojibake, oturumlar-arasi izolasyon, sir sizinti.
#
#   DURUSTLUK SINIRI: Bu serit GERCEK DBI havuz/islem/encoding/streaming-karar
#   yollarini eszamanli-benzeri tekrar yuk altinda dogrular; ANCAK tek-surecte
#   ardisik oturumlardir (gercek tarayici/websocket DEGIL) ve uretim T-SQL/SQL
#   Server'i DEGIL lane-yerel SQLite SQL'ini kullanir. Bu sinirlar evidence'ta
#   does_not_prove altinda acikca yazilir.
#
#   Bu dosya BILEREK ASCII-guvenlidir (Turkce ozel karakter yok); Turkce fikstur
#   metinleri \u kacislariyla uretilir (parser-guvenli, Windows VM uyumlu).
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

# Repo kokunu calisma-dizininden bagimsiz bul (soak_client.R ile ayni desen).
soak_interactive_repo_root <- function() {
  env_root <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
  for (cand in c(env_root, ".", "..", "../..", "../../..")) {
    if (!nzchar(cand)) next
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = FALSE))
    }
  }
  normalizePath(".", winslash = "/", mustWork = FALSE)
}

# Etkilesimli serit icin gerekli GERCEK uygulama yardimcilarini yukler.
# (caller UTF-8 locale ayarlamali). Calisma-dizininden bagimsizdir.
soak_interactive_bootstrap <- function() {
  root <- soak_interactive_repo_root()
  files <- c(
    "R/utils_common.R", "R/utils_text_encoding.R",
    "R/helpers_db_unicode_escape.R", "R/helpers_db_encoding.R",
    "R/helpers_db_connection.R", "R/helpers_db_pool.R",
    "R/utils_safe_path.R", "R/utils_atomic_write.R", "R/utils_upload_validator.R",
    "R/helpers_api_key_crypto.R", "R/helpers_api_key_identity.R",
    "R/helpers_streaming_poll_lifecycle.R", "R/helpers_streaming_abort_lifecycle.R"
  )
  ok <- TRUE
  for (f in files) {
    res <- tryCatch({
      suppressWarnings(suppressMessages(source(file.path(root, f), encoding = "UTF-8")))
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(res)) ok <- FALSE
  }
  required_fns <- c("init_db_pool_once", "close_db_pool_once", "with_db_transaction",
                    "with_db_connection", "db_pool_status_snapshot",
                    "normalize_db_visible_value", "normalize_db_read_visible_value",
                    "db_visible_text_has_mojibake", "validate_uploaded_file",
                    "mergen_stream_classify_poll_lines", "mergen_stream_abort_cleanup_plan",
                    "mb_api_key_get_effective_key")
  present <- vapply(required_fns, function(fn) exists(fn, mode = "function"), logical(1))
  available <- ok && all(present) &&
    requireNamespace("pool", quietly = TRUE) &&
    requireNamespace("RSQLite", quietly = TRUE) &&
    requireNamespace("DBI", quietly = TRUE)
  list(available = available, missing_fns = required_fns[!present])
}

# Lane-yerel SQLite havuz factory'si (tum bagantilar ayni dosya-DB'yi paylasir).
soak_interactive_sqlite_factory <- function(dbfile) {
  function() {
    pool::dbPool(
      drv = RSQLite::SQLite(),
      dbname = dbfile,
      minSize = 1L,
      maxSize = 6L
    )
  }
}

# Lane-yerel sema (uretim T-SQL DEGIL; SQLite uyumlu).
soak_interactive_setup_schema <- function() {
  with_db_connection(function(conn) {
    DBI::dbExecute(conn, "CREATE TABLE IF NOT EXISTS mb_chats (
      chat_id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER,
      title TEXT, created_at TEXT)")
    DBI::dbExecute(conn, "CREATE TABLE IF NOT EXISTS mb_messages (
      message_id INTEGER PRIMARY KEY AUTOINCREMENT, chat_id INTEGER, user_id INTEGER,
      content TEXT, msg_type TEXT, msg_order INTEGER, created_at TEXT)")
  })
  invisible(NULL)
}

# Sahte oturum nesnesi (anahtar yonlendirme icin). userData bir ortamdir.
.soak_interactive_session_obj <- function(username, personal_key) {
  ud <- new.env(parent = emptyenv())
  ud$auth_initialized <- TRUE
  ud$system_username <- username
  ud$user_id <- 100L
  ud$auth_source <- "soak-interactive"
  ud$ai_api_key <- personal_key
  ud$ai_api_key_owner <- username
  list(userData = ud)
}

# Bir eylemi zamanlar, metrige kaydeder ve sonucu doner. Hata yutmaz; status
# "ok"/"error" olarak isaretlenir.
.soak_interactive_timed <- function(metrics, action, fn) {
  start <- Sys.time()
  res <- tryCatch(list(ok = TRUE, value = fn()),
                  error = function(e) list(ok = FALSE, value = NULL, err = conditionMessage(e)))
  lat <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000
  status <- if (isTRUE(res$ok)) "ok" else "error"
  soak_metrics_record(metrics, "interactive", paste0("interactive_", action),
                      lat, status, NA_integer_, 0, "n/a")
  res
}

# Sentetik streaming JSONL delta satirlari (Turkce + markdown + kod). Gercek
# mergen_stream_classify_poll_lines bunlari ayristirir.
.soak_interactive_stream_lines <- function() {
  parcalar <- c(
    "Merhaba, ", "bu bir ", "\u00f6rnek ", "yan\u0131tt\u0131r. ",
    "**Kal\u0131n** ", "ve `kod` ", "i\u00e7erir. ", "\u00c7\u011f\u0131\u0130\u00f6\u015f\u00fc."
  )
  vapply(parcalar, function(p) {
    as.character(jsonlite::toJSON(list(type = "delta", text = p), auto_unbox = TRUE))
  }, character(1))
}

# Tek bir etkilesimli oturumu calistirir. Geriye oturum-ozeti doner.
soak_interactive_run_session <- function(cfg, metrics, session_idx, do_stop) {
  username <- sprintf("isess_user%04d", session_idx)
  personal_key <- sprintf("sk-isess-%s", username)
  user_id <- 200000L + session_idx

  # 1) Oturum ac + anahtar izolasyonu (kisisel anahtar bu kullaniciya ait).
  iso_pass <- FALSE
  .soak_interactive_timed(metrics, "session_open", function() {
    sess <- .soak_interactive_session_obj(username, personal_key)
    old_req <- Sys.getenv("MERGEN_REQUIRE_PERSONAL_API_KEY", unset = NA_character_)
    old_def <- Sys.getenv("MERGEN_ALLOW_DEFAULT_API_KEY", unset = NA_character_)
    Sys.setenv(MERGEN_REQUIRE_PERSONAL_API_KEY = "FALSE", MERGEN_ALLOW_DEFAULT_API_KEY = "FALSE")
    on.exit({
      if (is.na(old_req)) Sys.unsetenv("MERGEN_REQUIRE_PERSONAL_API_KEY") else Sys.setenv(MERGEN_REQUIRE_PERSONAL_API_KEY = old_req)
      if (is.na(old_def)) Sys.unsetenv("MERGEN_ALLOW_DEFAULT_API_KEY") else Sys.setenv(MERGEN_ALLOW_DEFAULT_API_KEY = old_def)
    }, add = TRUE)
    plan <- mb_api_key_get_effective_key(sess)
    iso_pass <<- identical(plan$source %||% "", "personal")
    TRUE
  })

  # 2) Sohbet olustur (ISLEM).
  chat_title <- sprintf("S\u00f6yle\u015fi %d \u00c7\u011f\u0131\u0130\u00f6\u015f\u00fc", session_idx)
  chat_res <- .soak_interactive_timed(metrics, "chat_create", function() {
    with_db_transaction(function(conn) {
      DBI::dbExecute(conn, "INSERT INTO mb_chats (user_id, title, created_at) VALUES (?, ?, ?)",
                     params = list(user_id, normalize_db_visible_value(chat_title),
                                   format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
      DBI::dbGetQuery(conn, "SELECT last_insert_rowid() AS id")$id[1]
    })
  })
  chat_id <- if (isTRUE(chat_res$ok)) chat_res$value else NA_integer_

  # 3) Kullanici mesaji kaydet (ISLEM; Turkce).
  user_text <- sprintf("T\u00fcrkiye'nin ba\u015fkenti neresidir? (oturum %d)", session_idx)
  .soak_interactive_timed(metrics, "user_msg_save", function() {
    with_db_transaction(function(conn) {
      DBI::dbExecute(conn, "INSERT INTO mb_messages (chat_id, user_id, content, msg_type, msg_order, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                     params = list(chat_id, user_id, normalize_db_visible_value(user_text),
                                   "user", 1L, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
    })
  })

  # 4) Streaming delta isle (GERCEK siniflandirici).
  stream_res <- .soak_interactive_timed(metrics, "stream_process", function() {
    classified <- mergen_stream_classify_poll_lines(.soak_interactive_stream_lines())
    classified$delta_text
  })
  assistant_text <- if (isTRUE(stream_res$ok)) stream_res$value else ""

  # 5) Asistan mesaji kaydet (ISLEM) -- veya stop/iptal karari.
  if (isTRUE(do_stop)) {
    .soak_interactive_timed(metrics, "stop_cancel", function() {
      plan <- mergen_stream_abort_cleanup_plan(assistant_text, list(aborted = TRUE))
      if (identical(plan$action, "finalize_partial")) {
        with_db_transaction(function(conn) {
          DBI::dbExecute(conn, "INSERT INTO mb_messages (chat_id, user_id, content, msg_type, msg_order, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                         params = list(chat_id, user_id, normalize_db_visible_value(plan$final_text),
                                       "assistant", 2L, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
        })
      }
      plan$action
    })
  } else {
    .soak_interactive_timed(metrics, "assistant_msg_save", function() {
      with_db_transaction(function(conn) {
        DBI::dbExecute(conn, "INSERT INTO mb_messages (chat_id, user_id, content, msg_type, msg_order, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                       params = list(chat_id, user_id, normalize_db_visible_value(assistant_text),
                                     "assistant", 2L, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
      })
    })
  }

  # 6) Niyetli ISLEM ROLLBACK dogrulamasi: ekle + hata firlat -> satir kalmamali.
  rollback_pass <- FALSE
  .soak_interactive_timed(metrics, "tx_rollback_probe", function() {
    before <- with_db_connection(function(conn) {
      DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM mb_messages WHERE user_id = ?",
                      params = list(user_id))$n[1]
    })
    try(with_db_transaction(function(conn) {
      DBI::dbExecute(conn, "INSERT INTO mb_messages (chat_id, user_id, content, msg_type, msg_order, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                     params = list(chat_id, user_id, "rollback-probe", "assistant", 99L,
                                   format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
      stop("kasitli rollback")
    }), silent = TRUE)
    after <- with_db_connection(function(conn) {
      DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM mb_messages WHERE user_id = ?",
                      params = list(user_id))$n[1]
    })
    rollback_pass <<- identical(as.integer(before), as.integer(after))
    rollback_pass
  })

  # 7) Kucuk dosya yukle (GERCEK dogrulayici; Turkce dosya adi).
  upload_pass <- FALSE
  .soak_interactive_timed(metrics, "file_upload", function() {
    tmp <- tempfile(fileext = ".pdf"); writeLines("soak interactive", tmp)
    on.exit(unlink(tmp), add = TRUE)
    fn <- "T\u00fcrk\u00e7e_\u00e7al\u0131\u015fma_\u00f6zeti_\u0130stanbul.pdf"
    r <- validate_uploaded_file(tmp, filename = fn,
                                allowed_ext = c("pdf", "docx", "txt", "csv", "xlsx"))
    upload_pass <<- isTRUE(r$ok)
    upload_pass
  })

  # 8) Kayitli/gecmis oku (kullanici-kapsamli) + Turkce round-trip + izolasyon.
  read_pass <- FALSE; mojibake_hit <- FALSE
  .soak_interactive_timed(metrics, "history_read", function() {
    rows <- with_db_connection(function(conn) {
      DBI::dbGetQuery(conn, "SELECT content FROM mb_messages WHERE user_id = ? ORDER BY msg_order",
                      params = list(user_id))
    })
    # Bu oturum yalniz KENDI mesajlarini gormeli (cross-session izolasyon).
    chat_rows <- with_db_connection(function(conn) {
      DBI::dbGetQuery(conn, "SELECT title FROM mb_chats WHERE user_id = ?",
                      params = list(user_id))
    })
    restored <- if (nrow(chat_rows) > 0L) normalize_db_read_visible_value(chat_rows$title[1]) else ""
    read_pass <<- nrow(chat_rows) == 1L &&
      identical(enc2utf8(restored), enc2utf8(chat_title))
    mojibake_hit <<- db_visible_text_has_mojibake(restored) ||
      (nrow(rows) > 0L && db_visible_text_has_mojibake(rows$content[1]))
    read_pass
  })

  list(
    isolation_pass = isTRUE(iso_pass) && isTRUE(read_pass),
    rollback_pass = isTRUE(rollback_pass),
    upload_pass = isTRUE(upload_pass),
    mojibake_hit = isTRUE(mojibake_hit),
    user_id = user_id
  )
}

# ------------------------------------------------------------------------------
# Etkilesimli seridi calistirir. Kendi SQLite havuzunu kurar, N oturumu calistirir,
# metrikleri toplar ve yapisal bir ozet doner. Global durumu (.GlobalEnv$pool)
# eski haline getirir.
# ------------------------------------------------------------------------------
soak_interactive_lane <- function(cfg, sessions = NULL, stop_fraction = 0.25) {
  boot <- soak_interactive_bootstrap()
  if (!isTRUE(boot$available)) {
    return(list(
      available = FALSE,
      reason = sprintf("Etkilesimli serit yardimcilari/paketleri yuklenemedi; eksik: %s",
                       paste(boot$missing_fns, collapse = ", ")),
      missing_fns = boot$missing_fns
    ))
  }

  if (is.null(sessions)) {
    sessions <- max(1L, as.integer(cfg$interactive_users %||% 12L))
  }
  iterations <- max(1L, as.integer(cfg$interactive_iterations %||% 1L))

  metrics <- soak_metrics_new()
  dbfile <- tempfile(fileext = ".sqlite")

  pool_existed <- exists("pool", envir = .GlobalEnv, inherits = FALSE)
  old_pool <- if (pool_existed) get("pool", envir = .GlobalEnv, inherits = FALSE) else NULL

  db_pool_reset_stats()
  on.exit({
    suppressWarnings(try(close_db_pool_once(), silent = TRUE))
    if (pool_existed) assign("pool", old_pool, envir = .GlobalEnv)
    else if (exists("pool", envir = .GlobalEnv, inherits = FALSE)) rm("pool", envir = .GlobalEnv)
    suppressWarnings(unlink(dbfile))
  }, add = TRUE)

  setup_ok <- tryCatch({
    init_db_pool_once("primary", factory = soak_interactive_sqlite_factory(dbfile), force = TRUE)
    soak_interactive_setup_schema()
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(setup_ok)) {
    return(list(available = FALSE, reason = "SQLite havuzu/sema kurulamadi."))
  }

  loop_start <- Sys.time()
  iso_fail <- 0L; rollback_fail <- 0L; upload_fail <- 0L; mojibake_hits <- 0L
  total_sessions <- 0L

  for (it in seq_len(iterations)) {
    for (s in seq_len(sessions)) {
      total_sessions <- total_sessions + 1L
      do_stop <- (total_sessions %% max(1L, round(1 / stop_fraction))) == 0L
      res <- soak_interactive_run_session(cfg, metrics, total_sessions, do_stop)
      if (!isTRUE(res$isolation_pass)) iso_fail <- iso_fail + 1L
      if (!isTRUE(res$rollback_pass)) rollback_fail <- rollback_fail + 1L
      if (!isTRUE(res$upload_pass)) upload_fail <- upload_fail + 1L
      if (isTRUE(res$mojibake_hit)) mojibake_hits <- mojibake_hits + 1L
    }
  }
  soak_metrics_add_load_seconds(metrics, as.numeric(difftime(Sys.time(), loop_start, units = "secs")))

  summary <- soak_metrics_summary(metrics)
  pool_snap <- db_pool_status_snapshot()
  metrics_df <- soak_metrics_as_df(metrics)

  list(
    available = TRUE,
    sessions = total_sessions,
    actions = summary$requests,
    summary = summary,
    db_pool = list(
      checkout = pool_snap$counters$checkout,
      returned = pool_snap$counters$returned,
      outstanding_checkouts = pool_snap$counters$outstanding_checkouts,
      tx_begin = pool_snap$counters$tx_begin,
      tx_commit = pool_snap$counters$tx_commit,
      tx_rollback = pool_snap$counters$tx_rollback,
      no_leak = identical(as.integer(pool_snap$counters$outstanding_checkouts), 0L)
    ),
    isolation_pass = (iso_fail == 0L),
    isolation_failures = iso_fail,
    rollback_pass = (rollback_fail == 0L),
    rollback_failures = rollback_fail,
    upload_pass = (upload_fail == 0L),
    upload_failures = upload_fail,
    mojibake_hits = as.integer(mojibake_hits),
    metrics_df = metrics_df,
    note = paste(
      "In-process etkilesimli oturumlar: GERCEK DB havuzu/islem/encoding/streaming",
      "karar yollari + dosya dogrulama + anahtar izolasyonu. Tek-surecte ardisik;",
      "gercek tarayici/websocket DEGIL, uretim T-SQL DEGIL (lane-yerel SQLite)."
    )
  )
}
