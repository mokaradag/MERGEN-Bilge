# ==============================================================================
# Dosya Yolu: R/helpers_db_claude_code_sessions.R
# Açıklama: Bilge Yolaç (Claude Code) kalıcı oturum saklama DB yardımcıları.
#           MB_ClaudeCode_Sessions (oturum başlığı) ve MB_ClaudeCode_Runs
#           (prompt/sonuç/araç çalıştırma birimleri) tablolarını yönetir.
#
# Sözleşmeler:
#   * Bu katman MB_Chats / MB_Messages ailesinden kasıtlı olarak AYRIDIR;
#     Bilge Yolaç ajan oturumları normal sohbet şemasına yazılmaz.
#   * Tablolar henüz oluşturulmamışsa (aşamalı devreye alma) tüm fonksiyonlar
#     çökmek yerine güvenli boş/NULL sonuç döner ve uyarı loglar; Bilge Yolaç
#     bellek-içi modda çalışmaya devam eder.
#   * Yalnızca parametreli SQL kullanılır; kullanıcıya görünen metinler
#     normalize_db_visible_value(), teknik alanlar normalize_db_technical_value()
#     üzerinden geçer ve tüm parametreler normalize_db_params() ile bağlanır.
#   * Bu tablolara gizli değer (API anahtarı, token, ortam değişkeni) veya
#     ikili dosya içeriği yazılmaz; üretilen dosyalar için yalnızca metadata
#     saklanır. RawStreamJsonl boyutu cc_db_truncate_raw_stream() ile sınırlanır.
#   * Testler gerçek SQLite bağlantısı enjekte edebilsin diye tüm fonksiyonlar
#     opsiyonel `conn` parametresi alır. SQLite yolu YALNIZCA çevrimdışı
#     davranış testleri içindir; üretim T-SQL yolu (OUTPUT INSERTED +
#     UPDLOCK/HOLDLOCK) değişmez.
#   * Tablo kurulum betiği: docs/sql/2026-07-bilge-yolac-sessions.sql
#     (uygulama açılışında OTOMATİK ÇALIŞTIRILMAZ; bkz. RUNBOOK.md).
# ==============================================================================

# Tablo erişilebilirlik önbelleği (her çalıştırmada tekrar tekrar tablo
# varlık sorgusu atmamak için).
.cc_db_sessions_state <- new.env(parent = emptyenv())

.cc_db_sessions_log_warn <- function(...) {
  msg <- paste(..., collapse = " ")
  if (exists("log_warn", mode = "function", inherits = TRUE)) {
    # logger glue çözümlemesine takılmaması için süslü parantezler temizlenir.
    log_warn(gsub("[{}]", "", msg))
  } else {
    warning(msg, call. = FALSE)
  }
  invisible(NULL)
}

# Tek merkezi güvenli değerlendirme: hata durumunda fallback döner ve uyarı
# metni verilmişse loglar. Bu yardımcı, dosyadaki anonim tryCatch handler
# sayısını maintainability ratchet altında tutmak için de kullanılır.
.cc_db_try <- function(expr, fallback = NULL, uyari = NULL) {
  tryCatch(expr, error = function(e) {
    if (!is.null(uyari)) {
      .cc_db_sessions_log_warn(uyari, conditionMessage(e))
    }
    fallback
  })
}

cc_db_sessions_reset_availability_cache <- function() {
  .cc_db_sessions_state$available <- NULL
  .cc_db_sessions_state$checked_at <- NULL
  invisible(NULL)
}

# Bağlantı edinme sınırı: conn enjekte edilmişse sahiplik çağırandadır
# (release no-op). Aksi halde işlem gerektiren yollarda havuz-güvenli
# db_acquire_tx_connection(), diğerlerinde get_connection() kullanılır.
.cc_db_sessions_acquire <- function(conn = NULL, tx = FALSE) {
  if (!is.null(conn)) {
    return(list(conn = conn, mode = "injected", info = NULL))
  }

  if (isTRUE(tx) &&
      exists("db_acquire_tx_connection", mode = "function", inherits = TRUE)) {
    conn_info <- db_acquire_tx_connection("primary")
    return(list(conn = conn_info$conn, mode = "tx", info = conn_info))
  }

  conn_info <- get_connection()
  list(conn = conn_info$conn, mode = "plain", info = conn_info)
}

.cc_db_sessions_release <- function(handle) {
  if (is.null(handle) || identical(handle$mode, "injected")) {
    return(invisible(NULL))
  }

  if (identical(handle$mode, "tx")) {
    db_release_tx_connection(handle$info)
  } else {
    release_connection(handle$info)
  }

  invisible(NULL)
}

# SQLite lehçe tespiti: yalnızca çevrimdışı testlerde TRUE olur. Üretim
# SQL Server/ODBC yolu T-SQL kalır (OUTPUT INSERTED + kilit ipuçları).
.cc_db_sessions_is_sqlite <- function(conn) {
  isTRUE(inherits(conn, "SQLiteConnection")) ||
    any(grepl("sqlite", class(conn), ignore.case = TRUE))
}

.cc_db_sessions_now_stamp <- function() {
  format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "Europe/Istanbul")
}

# Okuma sınırı: yalnızca kullanıcıya görünen metin kolonlarını DB-safe
# Unicode escape belirteçlerinden geri açar (teknik kolonlara dokunmaz).
.cc_db_sessions_restore_visible_columns <- function(df, columns) {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    return(df)
  }

  if (!exists("normalize_db_read_visible_value", mode = "function", inherits = TRUE)) {
    return(df)
  }

  for (kolon in intersect(columns, names(df))) {
    if (is.character(df[[kolon]])) {
      df[[kolon]] <- normalize_db_read_visible_value(df[[kolon]])
    }
  }

  df
}

#' MB_ClaudeCode_Sessions / MB_ClaudeCode_Runs tabloları erişilebilir mi?
#'
#' Sonuç önbelleğe alınır: TRUE kalıcıdır; FALSE 60 saniye boyunca tekrar
#' sorgulanmaz (eksik tabloyla her çalıştırmada DB yoklamamak için).
cc_db_claude_tables_available <- function(conn = NULL, force_refresh = FALSE) {
  cached <- .cc_db_sessions_state$available

  if (!isTRUE(force_refresh) && !is.null(cached)) {
    if (isTRUE(cached)) {
      return(TRUE)
    }

    checked_at <- .cc_db_sessions_state$checked_at
    if (!is.null(checked_at) &&
        as.numeric(difftime(Sys.time(), checked_at, units = "secs")) < 60) {
      return(FALSE)
    }
  }

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn),
    fallback = NULL,
    uyari = "Bilge Yolaç oturum tabloları için DB bağlantısı alınamadı:"
  )

  ok <- FALSE

  if (!is.null(handle)) {
    on.exit(.cc_db_sessions_release(handle), add = TRUE)

    ok <- .cc_db_try(
      isTRUE(DBI::dbExistsTable(handle$conn, "MB_ClaudeCode_Sessions")) &&
        isTRUE(DBI::dbExistsTable(handle$conn, "MB_ClaudeCode_Runs")),
      fallback = FALSE,
      uyari = "Bilge Yolaç oturum tabloları kontrol edilemedi:"
    )
  }

  .cc_db_sessions_state$available <- isTRUE(ok)
  .cc_db_sessions_state$checked_at <- Sys.time()

  isTRUE(ok)
}

# INSERT sonrası üretilen kimliği lehçeye göre okur. Üretim yolu T-SQL
# OUTPUT INSERTED; SQLite yolu yalnızca çevrimdışı testler içindir.
.cc_db_sessions_insert_returning_id <- function(conn, insert_sql_tsql,
                                                insert_sql_plain, id_column,
                                                params) {
  if (.cc_db_sessions_is_sqlite(conn)) {
    DBI::dbExecute(conn, insert_sql_plain, params = params)
    res <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() AS id")
    return(as.integer(res$id[1]))
  }

  res <- DBI::dbGetQuery(conn, insert_sql_tsql, params = params)
  if (nrow(res) == 0L) {
    stop(sprintf("INSERT %s kimlik dondurmedi.", id_column), call. = FALSE)
  }
  as.integer(res[[1]][1])
}

#' Yeni kalıcı Bilge Yolaç oturum kaydı oluşturur.
#'
#' @return Oturum kayıt kimliği (integer) veya başarısızlıkta NULL.
cc_db_create_session <- function(user_id,
                                 title = NULL,
                                 workdir = NULL,
                                 source_workdir = NULL,
                                 runtime_workdir = NULL,
                                 model = NULL,
                                 runtime_model = NULL,
                                 character_id = NULL,
                                 metadata = list(),
                                 conn = NULL) {
  user_id <- suppressWarnings(as.integer(user_id %||% 0L)[1])
  if (is.na(user_id) || user_id <= 0L) {
    return(NULL)
  }

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn),
    fallback = NULL,
    uyari = "Bilge Yolaç oturum kaydı için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.cc_db_sessions_release(handle), add = TRUE)

  .cc_db_try({
    params <- normalize_db_params(list(
      user_id,
      normalize_db_visible_value(as.character(title %||% NA_character_)[1]),
      normalize_db_technical_value(as.character(workdir %||% NA_character_)[1]),
      normalize_db_technical_value(as.character(source_workdir %||% NA_character_)[1]),
      normalize_db_technical_value(as.character(runtime_workdir %||% NA_character_)[1]),
      normalize_db_technical_value(as.character(model %||% NA_character_)[1]),
      normalize_db_technical_value(as.character(runtime_model %||% NA_character_)[1]),
      normalize_db_technical_value(as.character(character_id %||% NA_character_)[1]),
      normalize_db_technical_value("active"),
      .cc_db_sessions_now_stamp(),
      normalize_db_technical_value(.cc_db_sessions_json(metadata, empty = "{}"))
    ))

    kolonlar <- paste(
      "(UserID, SessionTitle, Workdir, SourceWorkdir, RuntimeWorkdir,",
      "ModelUsed, RuntimeModel, CharacterID, Status, CreatedAt, SessionMetaJson)"
    )
    degerler <- "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    .cc_db_sessions_insert_returning_id(
      conn = handle$conn,
      insert_sql_tsql = paste(
        "INSERT INTO MB_ClaudeCode_Sessions", kolonlar,
        "OUTPUT INSERTED.ClaudeSessionRecordID AS id", degerler
      ),
      insert_sql_plain = paste(
        "INSERT INTO MB_ClaudeCode_Sessions", kolonlar, degerler
      ),
      id_column = "ClaudeSessionRecordID",
      params = params
    )
  },
  fallback = NULL,
  uyari = "Bilge Yolaç oturum kaydı oluşturulamadı:")
}

#' Oturumun devam/durum alanlarını günceller (yalnızca verilen alanlar).
cc_db_update_session_resume_state <- function(session_record_id,
                                              cli_session_id = NULL,
                                              workdir = NULL,
                                              source_workdir = NULL,
                                              runtime_workdir = NULL,
                                              model = NULL,
                                              runtime_model = NULL,
                                              status = NULL,
                                              title = NULL,
                                              touch_last_run = TRUE,
                                              conn = NULL,
                                              user_id = NULL) {
  session_record_id <- suppressWarnings(as.integer(session_record_id %||% 0L)[1])
  if (is.na(session_record_id) || session_record_id <= 0L) {
    return(invisible(FALSE))
  }

  # Kullanıcı kapsamı ZORUNLUDUR: `user_id` yokken UPDATE yalnızca
  # `ClaudeSessionRecordID` ile çalışıyor ve bayat/yanlış bir kayıt kimliği
  # BAŞKA bir kullanıcının Workdir/RuntimeWorkdir/RuntimeModel/Status alanlarını
  # ezebiliyordu ("tüm işlemler kullanıcı-izoledir" sözleşmesi bozuluyordu).
  kapsam_uid <- mergen_canonical_user_id(user_id %||% NA_integer_)
  if (kapsam_uid <= 0L) {
    .cc_db_sessions_log_warn("Bilge Yolaç oturum güncellemesi kullanıcı kapsamı olmadan reddedildi.")
    return(invisible(FALSE))
  }

  # Teknik alanlar: mojibake onarımı uygulanmaz (CLAUDE.md DB sözleşmesi).
  teknik_alanlar <- list(
    ClaudeCliSessionID = cli_session_id,
    Workdir = workdir,
    SourceWorkdir = source_workdir,
    RuntimeWorkdir = runtime_workdir,
    ModelUsed = model,
    RuntimeModel = runtime_model,
    Status = status
  )
  teknik_alanlar <- teknik_alanlar[!vapply(teknik_alanlar, is.null, logical(1))]

  set_parts <- character(0)
  params <- list()

  for (kolon in names(teknik_alanlar)) {
    set_parts <- c(set_parts, paste0(kolon, " = ?"))
    params[[length(params) + 1L]] <-
      normalize_db_technical_value(as.character(teknik_alanlar[[kolon]])[1])
  }

  if (!is.null(title)) {
    # Oturum başlığı kullanıcıya görünen metindir.
    set_parts <- c(set_parts, "SessionTitle = ?")
    params[[length(params) + 1L]] <-
      normalize_db_visible_value(as.character(title)[1])
  }

  if (isTRUE(touch_last_run)) {
    set_parts <- c(set_parts, "LastRunAt = ?")
    params[[length(params) + 1L]] <- .cc_db_sessions_now_stamp()
  }

  if (!length(set_parts)) {
    return(invisible(FALSE))
  }

  params[[length(params) + 1L]] <- session_record_id
  params[[length(params) + 1L]] <- kapsam_uid

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn),
    fallback = NULL,
    uyari = "Bilge Yolaç oturum güncellemesi için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.cc_db_sessions_release(handle), add = TRUE)

  sonuc <- .cc_db_try({
    etkilenen <- DBI::dbExecute(
      handle$conn,
      paste(
        "UPDATE MB_ClaudeCode_Sessions SET",
        paste(set_parts, collapse = ", "),
        "WHERE ClaudeSessionRecordID = ? AND UserID = ?"
      ),
      params = normalize_db_params(params)
    )

    isTRUE(etkilenen > 0)
  },
  fallback = FALSE,
  uyari = "Bilge Yolaç oturum durumu güncellenemedi:")

  invisible(isTRUE(sonuc))
}

#' Bir çalıştırma (prompt + sonuç + araç kullanımı) kaydını ekler.
#'
#' @return Çalıştırma kaydı kimliği (integer) veya başarısızlıkta NULL.
cc_db_save_run <- function(session_record_id,
                           prompt,
                           final_output = "",
                           status = "completed",
                           exit_code = NULL,
                           duration_seconds = NULL,
                           tool_uses = list(),
                           generated_downloads = list(),
                           raw_stream_jsonl = NULL,
                           conn = NULL) {
  session_record_id <- suppressWarnings(as.integer(session_record_id %||% 0L)[1])
  if (is.na(session_record_id) || session_record_id <= 0L) {
    return(NULL)
  }

  prompt_text <- normalize_db_visible_value(as.character(prompt %||% "")[1])
  if (is.na(prompt_text) || !nzchar(prompt_text)) {
    return(NULL)
  }

  raw_stream <- cc_db_truncate_raw_stream(raw_stream_jsonl)

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn, tx = TRUE),
    fallback = NULL,
    uyari = "Bilge Yolaç çalıştırma kaydı için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(NULL)
  }

  tx_conn <- handle$conn
  tx_begun <- FALSE
  tx_committed <- FALSE

  # after = FALSE ile rollback, bağlantı iadesinden ÖNCE çalışır; havuzlu
  # bağlantı açık işlemle iade edilmez (helpers_db_pool sözleşmesi).
  on.exit(.cc_db_sessions_release(handle), add = TRUE)
  on.exit({
    if (isTRUE(tx_begun) && !isTRUE(tx_committed)) {
      try(DBI::dbRollback(tx_conn), silent = TRUE)
    }
  }, add = TRUE, after = FALSE)

  .cc_db_try({
    sqlite_yolu <- .cc_db_sessions_is_sqlite(tx_conn)

    # SQLite lehçesi kilit ipuçlarını desteklemez; üretim T-SQL yolunda
    # RunOrder üretimi MB_Messages ile aynı UPDLOCK/HOLDLOCK sözleşmesini izler.
    next_order_sql <- if (sqlite_yolu) {
      "SELECT COALESCE(MAX(RunOrder), 0) + 1 AS next_order
       FROM MB_ClaudeCode_Runs
       WHERE ClaudeSessionRecordID = ?"
    } else {
      "SELECT COALESCE(MAX(RunOrder), 0) + 1 AS next_order
       FROM MB_ClaudeCode_Runs WITH (UPDLOCK, HOLDLOCK)
       WHERE ClaudeSessionRecordID = ?"
    }

    DBI::dbBegin(tx_conn)
    tx_begun <- TRUE

    next_order <- DBI::dbGetQuery(
      tx_conn,
      next_order_sql,
      params = list(session_record_id)
    )$next_order[1]
    next_order <- as.integer(next_order %||% 1L)

    params <- normalize_db_params(list(
      session_record_id,
      next_order,
      prompt_text,
      normalize_db_visible_value(as.character(final_output %||% "")[1]),
      normalize_db_technical_value(as.character(status %||% "completed")[1]),
      if (is.null(exit_code)) NA_integer_ else suppressWarnings(as.integer(exit_code)[1]),
      if (is.null(duration_seconds)) NA_real_ else round(suppressWarnings(as.numeric(duration_seconds)[1]), 2),
      normalize_db_technical_value(.cc_db_sessions_json(tool_uses)),
      normalize_db_technical_value(.cc_db_sessions_json(generated_downloads)),
      if (is.null(raw_stream$text)) NA_character_ else normalize_db_technical_value(raw_stream$text),
      .cc_db_sessions_now_stamp()
    ))

    kolonlar <- paste(
      "(ClaudeSessionRecordID, RunOrder, Prompt, FinalOutput, Status,",
      "ExitCode, DurationSeconds, ToolUsesJson, GeneratedDownloadsJson,",
      "RawStreamJsonl, CreatedAt)"
    )
    degerler <- "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    run_id <- .cc_db_sessions_insert_returning_id(
      conn = tx_conn,
      insert_sql_tsql = paste(
        "INSERT INTO MB_ClaudeCode_Runs", kolonlar,
        "OUTPUT INSERTED.ClaudeRunID AS id", degerler
      ),
      insert_sql_plain = paste(
        "INSERT INTO MB_ClaudeCode_Runs", kolonlar, degerler
      ),
      id_column = "ClaudeRunID",
      params = params
    )

    DBI::dbCommit(tx_conn)
    tx_committed <- TRUE

    run_id
  },
  fallback = NULL,
  uyari = "Bilge Yolaç çalıştırma kaydı yazılamadı:")
}

#' Kullanıcının Bilge Yolaç oturumlarını listeler (kullanıcı-izole).
#'
#' @return data.frame (0 satır olabilir); tablo yoksa/hata olursa boş df.
cc_db_list_sessions <- function(user_id,
                                limit = 50,
                                include_deleted = FALSE,
                                query = NULL,
                                status = NULL,
                                model = NULL,
                                workdir = NULL,
                                date_from = NULL,
                                date_to = NULL,
                                sort = "last_activity",
                                conn = NULL,
                                only_deleted = FALSE) {
  bos <- data.frame()

  user_id <- suppressWarnings(as.integer(user_id %||% 0L)[1])
  if (is.na(user_id) || user_id <= 0L) {
    return(bos)
  }

  limit <- suppressWarnings(as.integer(limit %||% 50L)[1])
  if (is.na(limit) || limit <= 0L) limit <- 50L
  limit <- min(limit, 500L)

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn),
    fallback = NULL,
    uyari = "Bilge Yolaç oturum listesi için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(bos)
  }
  on.exit(.cc_db_sessions_release(handle), add = TRUE)

  .cc_db_try({
    plan <- .cc_db_sessions_list_query(
      user_id = user_id,
      limit = limit,
      include_deleted = include_deleted,
      query = query,
      status = status,
      model = model,
      workdir = workdir,
      date_from = date_from,
      date_to = date_to,
      sort = sort,
      sqlite_yolu = .cc_db_sessions_is_sqlite(handle$conn),
      only_deleted = only_deleted
    )

    sonuc <- DBI::dbGetQuery(
      handle$conn,
      plan$sql,
      params = normalize_db_params(plan$params)
    )

    # Yalnızca kullanıcıya görünen metin kolonları okuma sınırında onarılır;
    # teknik kolonlar (Workdir, ModelUsed, Status vb.) olduğu gibi kalır.
    .cc_db_sessions_restore_visible_columns(
      sonuc,
      c("SessionTitle", "LastPrompt")
    )
  },
  fallback = bos,
  uyari = "Bilge Yolaç oturum listesi okunamadı:")
}

#' Tek bir oturumu ve çalıştırmalarını yükler (kullanıcı-izole).
#'
#' @return list(session = <tek satırlık liste>, runs = data.frame) veya NULL.
cc_db_load_session <- function(user_id,
                               session_record_id,
                               include_runs = TRUE,
                               max_runs = 200L,
                               conn = NULL) {
  user_id <- suppressWarnings(as.integer(user_id %||% 0L)[1])
  session_record_id <- suppressWarnings(as.integer(session_record_id %||% 0L)[1])

  if (is.na(user_id) || user_id <= 0L ||
      is.na(session_record_id) || session_record_id <= 0L) {
    return(NULL)
  }

  max_runs <- suppressWarnings(as.integer(max_runs %||% 200L)[1])
  if (is.na(max_runs) || max_runs <= 0L) max_runs <- 200L
  max_runs <- min(max_runs, 1000L)

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn),
    fallback = NULL,
    uyari = "Bilge Yolaç oturum yüklemesi için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(NULL)
  }
  on.exit(.cc_db_sessions_release(handle), add = TRUE)

  .cc_db_try({
    baslik <- DBI::dbGetQuery(
      handle$conn,
      "SELECT ClaudeSessionRecordID, UserID, ClaudeCliSessionID, SessionTitle,
              Workdir, SourceWorkdir, RuntimeWorkdir, ModelUsed, RuntimeModel,
              CharacterID, Status, CreatedAt, LastRunAt, IsDeleted, SessionMetaJson
       FROM MB_ClaudeCode_Sessions
       WHERE ClaudeSessionRecordID = ? AND UserID = ?",
      params = normalize_db_params(list(session_record_id, user_id))
    )

    # Kullanıcı izolasyonu: kayıt bu kullanıcıya ait değilse NULL döner.
    kayit_bulundu <- nrow(baslik) > 0L

    baslik <- .cc_db_sessions_restore_visible_columns(baslik, "SessionTitle")

    runs <- data.frame()

    if (isTRUE(kayit_bulundu) && isTRUE(include_runs)) {
      sqlite_yolu <- .cc_db_sessions_is_sqlite(handle$conn)

      run_sql <- if (sqlite_yolu) {
        "SELECT ClaudeRunID, RunOrder, Prompt, FinalOutput, Status, ExitCode,
                DurationSeconds, ToolUsesJson, GeneratedDownloadsJson, CreatedAt
         FROM MB_ClaudeCode_Runs
         WHERE ClaudeSessionRecordID = ?
         ORDER BY RunOrder ASC
         LIMIT ?"
      } else {
        "SELECT ClaudeRunID, RunOrder, Prompt, FinalOutput, Status, ExitCode,
                DurationSeconds, ToolUsesJson, GeneratedDownloadsJson, CreatedAt
         FROM MB_ClaudeCode_Runs
         WHERE ClaudeSessionRecordID = ?
         ORDER BY RunOrder ASC
         OFFSET 0 ROWS FETCH NEXT ? ROWS ONLY"
      }

      runs <- DBI::dbGetQuery(
        handle$conn,
        run_sql,
        params = normalize_db_params(list(session_record_id, max_runs))
      )

      runs <- .cc_db_sessions_restore_visible_columns(
        runs,
        c("Prompt", "FinalOutput")
      )
    }

    if (!isTRUE(kayit_bulundu)) {
      NULL
    } else {
      list(session = as.list(baslik[1, , drop = FALSE]), runs = runs)
    }
  },
  fallback = NULL,
  uyari = "Bilge Yolaç oturumu yüklenemedi:")
}

#' Oturumu yumuşak siler / arşivler (kullanıcı-izole; fiziksel silme yapmaz).
cc_db_soft_delete_session <- function(user_id, session_record_id, conn = NULL) {
  user_id <- suppressWarnings(as.integer(user_id %||% 0L)[1])
  session_record_id <- suppressWarnings(as.integer(session_record_id %||% 0L)[1])

  if (is.na(user_id) || user_id <= 0L ||
      is.na(session_record_id) || session_record_id <= 0L) {
    return(invisible(FALSE))
  }

  handle <- .cc_db_try(
    .cc_db_sessions_acquire(conn),
    fallback = NULL,
    uyari = "Bilge Yolaç oturum arşivleme için DB bağlantısı alınamadı:"
  )
  if (is.null(handle)) {
    return(invisible(FALSE))
  }
  on.exit(.cc_db_sessions_release(handle), add = TRUE)

  sonuc <- .cc_db_try({
    etkilenen <- DBI::dbExecute(
      handle$conn,
      "UPDATE MB_ClaudeCode_Sessions
       SET IsDeleted = 1
       WHERE ClaudeSessionRecordID = ? AND UserID = ?",
      params = normalize_db_params(list(session_record_id, user_id))
    )

    isTRUE(etkilenen > 0L)
  },
  fallback = FALSE,
  uyari = "Bilge Yolaç oturumu arşivlenemedi:")

  invisible(isTRUE(sonuc))
}

# NOT: Arşivden geri yükleme (cc_db_restore_session) ve KALICI silme
# (cc_db_hard_delete_session) bu dosyanın maintainability ratchet bütçesi
# altında kalması için R/helpers_db_claude_code_session_lifecycle.R dosyasına
# ayrılmıştır; o dosya bu dosyadan SONRA yüklenir.
