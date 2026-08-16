# ==============================================================================
# Dosya Yolu: tests/scripts/run_vm_encoding_preflight_real.R
# Açıklama: Windows VM / SSO / SQL Server Türkçe kodlama sınırını gerçek
#           ortam değişkenleri ve gerçek DB bağlantısı ile ön kontrolden geçirir.
#           Varsayılan olarak veri yazmaz; opsiyonel transactional write probe
#           MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE ile açılır.
# ==============================================================================

vm_encoding_preflight_stop <- function(message) {
  stop(message, call. = FALSE)
}

vm_encoding_preflight_bool <- function(value, default = FALSE, env_name = "value") {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(default)
  }

  norm <- tolower(trimws(as.character(value[1])))

  if (!nzchar(norm)) {
    return(default)
  }

  if (norm %in% c("true", "t")) {
    return(TRUE)
  }

  if (norm %in% c("false", "f")) {
    return(FALSE)
  }

  vm_encoding_preflight_stop(sprintf(
    "%s geçersiz: %s. TRUE/FALSE kullanın.",
    env_name,
    as.character(value[1])
  ))
}

vm_encoding_preflight_norm_encoding <- function(value) {
  value <- trimws(as.character(value[1] %||% ""))
  toupper(gsub("_", "-", value, fixed = TRUE))
}

vm_encoding_preflight_has_mojibake <- function(value) {
  text <- paste(enc2utf8(as.character(value %||% "")), collapse = "\n")

  mojibake_tokens <- c(
    "Ã§",
    "Ä±",
    "Ã¶",
    "ÅŸ",
    "ÄŸ",
    "Ã¼",
    "Ã‡",
    "Ä°",
    "Ã–",
    "\u00c5\u017e",
    "Ãœ",
    "TÃ¼rkiye",
    "NasÄ±l",
    "yardÄ±mcÄ±",
    "baÅŸkent"
  )

  any(vapply(
    mojibake_tokens,
    function(token) grepl(token, text, fixed = TRUE),
    logical(1)
  ))
}

vm_encoding_preflight_require_functions <- function(function_names) {
  missing <- function_names[!vapply(
    function_names,
    function(nm) exists(nm, envir = globalenv(), mode = "function", inherits = TRUE),
    logical(1)
  )]

  if (length(missing) > 0L) {
    vm_encoding_preflight_stop(sprintf(
      "VM encoding preflight başarısız: eksik fonksiyon(lar): %s",
      paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

vm_encoding_preflight_visible_text <- function(value) {
  # Transactional probe, çalışma zamanı sözleşmesini taklit eder:
  # önce sadece kullanıcıya görünen metin onarılır, sonra karma DB parametre
  # listesi repair_mojibake=FALSE varsayılanıyla bağlanır.
  if (is.null(value) || !is.character(value)) {
    return(value)
  }

  if (exists("normalize_db_visible_value", envir = globalenv(), mode = "function", inherits = TRUE)) {
    return(normalize_db_visible_value(value))
  }

  if (exists("normalize_text_utf8", envir = globalenv(), mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(value, repair_mojibake = TRUE))
  }

  enc2utf8(value)
}

vm_encoding_preflight_technical_text <- function(value) {
  # Teknik alanlarda mojibake onarımı yapılmaz.
  if (is.null(value) || !is.character(value)) {
    return(value)
  }

  if (exists("normalize_db_technical_value", envir = globalenv(), mode = "function", inherits = TRUE)) {
    return(normalize_db_technical_value(value))
  }

  if (exists("normalize_text_utf8", envir = globalenv(), mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(value, repair_mojibake = FALSE))
  }

  enc2utf8(value)
}

vm_encoding_preflight_query_scalar <- function(conn, query, params = list()) {
  result <- DBI::dbGetQuery(conn, query, params = params)

  if (nrow(result) == 0L || ncol(result) == 0L) {
    return(NA_character_)
  }

  as.character(result[[1]][1])
}

.vm_encoding_preflight_env_to_restore <- c(
  "MERGEN_DISABLE_FUTURES",
  "MERGEN_RUN_APP",
  "MERGEN_SQL_LOADER_STRICT"
)

.vm_encoding_preflight_env_snapshot <- Sys.getenv(
  .vm_encoding_preflight_env_to_restore,
  unset = NA_character_
)

on.exit({
  for (nm in names(.vm_encoding_preflight_env_snapshot)) {
    old_value <- .vm_encoding_preflight_env_snapshot[[nm]]

    if (is.na(old_value)) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, stats::setNames(list(old_value), nm))
    }
  }
}, add = TRUE)

Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false",
  MERGEN_SQL_LOADER_STRICT = "true"
)

source("app.R", encoding = "UTF-8")

if (exists("validate_boot_state", envir = globalenv(), mode = "function", inherits = FALSE)) {
  validate_boot_state()
}

vm_encoding_preflight_require_functions(c(
  "resolve_db_client_encoding",
  "resolve_db_name_encoding",
  "db_client_encoding_is_utf8",
  "normalize_db_value",
  "normalize_db_params",
  "get_connection",
  "release_connection"
))

client_env <- Sys.getenv("DB_CLIENT_ENCODING", unset = "")
name_env <- Sys.getenv("DB_NAME_ENCODING", unset = "")

if (!identical(vm_encoding_preflight_norm_encoding(client_env), "WINDOWS-1254")) {
  vm_encoding_preflight_stop(sprintf(
    paste(
      "VM encoding preflight başarısız:",
      ".Renviron içinde DB_CLIENT_ENCODING=WINDOWS-1254 bekleniyor.",
      "Gelen değer: '%s'",
      "R sürecini tamamen yeniden başlatmadan devam etmeyin."
    ),
    client_env
  ))
}

if (!identical(vm_encoding_preflight_norm_encoding(name_env), "WINDOWS-1254")) {
  vm_encoding_preflight_stop(sprintf(
    paste(
      "VM encoding preflight başarısız:",
      ".Renviron içinde DB_NAME_ENCODING=WINDOWS-1254 bekleniyor.",
      "Gelen değer: '%s'",
      "R sürecini tamamen yeniden başlatmadan devam etmeyin."
    ),
    name_env
  ))
}

resolved_client <- resolve_db_client_encoding()
resolved_name <- resolve_db_name_encoding()

if (!identical(vm_encoding_preflight_norm_encoding(resolved_client), "WINDOWS-1254")) {
  vm_encoding_preflight_stop(sprintf(
    "resolve_db_client_encoding() WINDOWS-1254 döndürmedi. Gelen: %s",
    resolved_client
  ))
}

if (!identical(vm_encoding_preflight_norm_encoding(resolved_name), "WINDOWS-1254")) {
  vm_encoding_preflight_stop(sprintf(
    "resolve_db_name_encoding() WINDOWS-1254 döndürmedi. Gelen: %s",
    resolved_name
  ))
}

if (isTRUE(db_client_encoding_is_utf8(resolved_client))) {
  vm_encoding_preflight_stop(
    "DB client encoding UTF-8 görünüyor; VM üretim Türkçe yazım sınırı için WINDOWS-1254 bekleniyor."
  )
}

probe_text <- "Türkçe test: ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü"
probe_param <- normalize_db_value(probe_text, repair_mojibake = TRUE)

if (identical(charToRaw(probe_param), charToRaw(enc2utf8(probe_text)))) {
  vm_encoding_preflight_stop(
    "normalize_db_value() WINDOWS-1254 ortamında ham UTF-8 parametre döndürdü. Bu VM için risklidir."
  )
}

probe_roundtrip <- iconv(probe_param, from = resolved_client, to = "UTF-8", sub = NA_character_)

if (!identical(probe_roundtrip, probe_text)) {
  vm_encoding_preflight_stop(sprintf(
    "WINDOWS-1254 parametre roundtrip başarısız. Beklenen='%s', Gelen='%s'",
    probe_text,
    probe_roundtrip
  ))
}

cat("OK: DB_CLIENT_ENCODING/DB_NAME_ENCODING ve WINDOWS-1254 parametre sınırı doğrulandı.\n")

conn_info <- NULL

tryCatch({
  conn_info <- get_connection()
  conn <- conn_info$conn

  column_query <- "
    SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, COLLATION_NAME
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME IN (
      'MB_Users',
      'MB_Chats',
      'MB_Messages',
      'MB_Feedback',
      'MB_Destek_Geri_Bildirim',
      'MB_Destek_Hata_Bildir'
    )
      AND COLUMN_NAME IN (
        'KullaniciAdi',
        'KaynakAdi',
        'Sicil',
        'Email',
        'Sektor',
        'Departman',
        'Mudurluk',
        'MasrafYeriKodu',
        'SonGirisKaynagi',
        'ChatTitle',
        'MessageContent',
        'MessageType',
        'ReasoningContent',
        'FeedbackType',
        'FeedbackTags',
        'FeedbackComment',
        'Etiketler',
        'EnCokSevilen',
        'Gelistirme',
        'Konular',
        'Kategoriler',
        'Oncelik',
        'Aciklama',
        'EkDosyaYollari',
        'Durum'
      )
    ORDER BY TABLE_NAME, COLUMN_NAME
  "

  columns <- DBI::dbGetQuery(conn, column_query)

  required_columns <- data.frame(
    TABLE_NAME = c(
      "MB_Users",
      "MB_Chats",
      "MB_Messages",
      "MB_Messages",
      "MB_Feedback",
      "MB_Feedback"
    ),
    COLUMN_NAME = c(
      "KaynakAdi",
      "ChatTitle",
      "MessageContent",
      "ReasoningContent",
      "FeedbackTags",
      "FeedbackComment"
    ),
    stringsAsFactors = FALSE
  )

  missing_required <- required_columns[!vapply(seq_len(nrow(required_columns)), function(i) {
    any(
      columns$TABLE_NAME == required_columns$TABLE_NAME[i] &
        columns$COLUMN_NAME == required_columns$COLUMN_NAME[i]
    )
  }, logical(1)), , drop = FALSE]

  if (nrow(missing_required) > 0L) {
    vm_encoding_preflight_stop(sprintf(
      "Kritik metin sütunları eksik: %s",
      paste(
        paste(missing_required$TABLE_NAME, missing_required$COLUMN_NAME, sep = "."),
        collapse = ", "
      )
    ))
  }

  cat("OK: Kritik SQL Server metin sütunları bulundu.\n")
  print(columns)
  
  scan_recent_messages <- vm_encoding_preflight_bool(
    Sys.getenv("MERGEN_PREFLIGHT_SCAN_RECENT_MESSAGES", "TRUE"),
    default = TRUE,
    env_name = "MERGEN_PREFLIGHT_SCAN_RECENT_MESSAGES"
  )

  if (isTRUE(scan_recent_messages)) {
    recent_messages <- DBI::dbGetQuery(
      conn,
      "
        SELECT TOP (200)
          MessageID,
          ChatID,
          MessageContent,
          ReasoningContent,
          MessageTimestamp
        FROM MB_Messages
        ORDER BY MessageID DESC
      "
    )

    visible_values <- character(0)

    if ("MessageContent" %in% names(recent_messages)) {
      visible_values <- c(visible_values, recent_messages$MessageContent)
    }

    if ("ReasoningContent" %in% names(recent_messages)) {
      visible_values <- c(visible_values, recent_messages$ReasoningContent)
    }

    visible_values <- visible_values[!is.na(visible_values)]

    legacy_mojibake_found <- length(visible_values) > 0L &&
      vm_encoding_preflight_has_mojibake(visible_values)

	if (isTRUE(legacy_mojibake_found)) {
	  bad_rows <- recent_messages[
		vapply(seq_len(nrow(recent_messages)), function(i) {
		  row_text <- paste(
			recent_messages$MessageContent[i] %||% "",
			recent_messages$ReasoningContent[i] %||% "",
			collapse = "\n"
		  )
		  vm_encoding_preflight_has_mojibake(row_text)
		}, logical(1)),
		,
		drop = FALSE
	  ]

	  legacy_message <- sprintf(
		paste(
		  "WARN: Son MB_Messages kayıtlarında eski mojibake kalıntısı bulundu.",
		  "Bu kontrol tarihsel veri için uyarıdır; tek başına yeni yazma regresyonu sayılmaz.",
		  "Yeni yazma yolu MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE ile ayrıca doğrulanmalıdır.",
		  "İlk bozuk kayıtlar: %s"
		),
		paste(
		  utils::head(
			paste0(
			  "MessageID=", bad_rows$MessageID,
			  ", ChatID=", bad_rows$ChatID,
			  ", MessageContentBytes=",
			  nchar(bad_rows$MessageContent %||% "", type = "bytes", allowNA = FALSE)
			),
			5
		  ),
		  collapse = " | "
		)
	  )

	  fail_on_legacy <- vm_encoding_preflight_bool(
		Sys.getenv("MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE", "FALSE"),
		default = FALSE,
		env_name = "MERGEN_PREFLIGHT_FAIL_ON_LEGACY_MOJIBAKE"
	  )

	  if (isTRUE(fail_on_legacy)) {
		vm_encoding_preflight_stop(legacy_message)
	  } else {
		cat(legacy_message, "\n")
	  }
	} else {
      cat("OK: Son MB_Messages kayıtlarında mojibake bulunmadı.\n")
    }
  }

  require_nvarchar <- vm_encoding_preflight_bool(
    Sys.getenv("MERGEN_PREFLIGHT_REQUIRE_NVARCHAR", "FALSE"),
    default = FALSE,
    env_name = "MERGEN_PREFLIGHT_REQUIRE_NVARCHAR"
  )

  non_unicode <- columns[
    tolower(columns$DATA_TYPE) %in% c("varchar", "char", "text"),
    ,
    drop = FALSE
  ]

  if (nrow(non_unicode) > 0L) {
    msg <- sprintf(
      "UYARI: Unicode olmayan metin sütunları var: %s",
      paste(
        paste(non_unicode$TABLE_NAME, non_unicode$COLUMN_NAME, non_unicode$DATA_TYPE, sep = "."),
        collapse = ", "
      )
    )

    if (isTRUE(require_nvarchar)) {
      vm_encoding_preflight_stop(msg)
    } else {
      warning(msg, call. = FALSE)
    }
  }

  write_probe <- vm_encoding_preflight_bool(
    Sys.getenv("MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST", "FALSE"),
    default = FALSE,
    env_name = "MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST"
  )

  if (!isTRUE(write_probe)) {
    cat("INFO: Transactional DB encoding write probe atlandı. Açmak için MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE ayarlayın.\n")
  } else {
    DBI::dbBegin(conn)
    rollback_needed <- TRUE

    tryCatch({
      probe_suffix <- format(Sys.time(), "%Y%m%d%H%M%S")

      probe_username <- vm_encoding_preflight_technical_text(
        paste0("vm_preflight_encoding_", probe_suffix)
      )
      probe_name <- vm_encoding_preflight_visible_text(
        "VM Ön Kontrol Kullanıcısı"
      )
      probe_title <- vm_encoding_preflight_visible_text(
        "Türkçe test: ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü"
      )
      probe_message <- vm_encoding_preflight_visible_text(
        "Türkiye'nin başkenti neresidir? Nasıl yardımcı olabilirim?"
      )
      probe_reasoning <- vm_encoding_preflight_visible_text(
        "Düşünce ön kontrolü: ölçü, açıklama, şablon."
      )
      probe_feedback_type <- vm_encoding_preflight_technical_text("dislike")
      probe_feedback_tags <- vm_encoding_preflight_visible_text(
        "açıklama,öneri,şikayet-değil"
      )
      probe_feedback_comment <- vm_encoding_preflight_visible_text(
        "Görüş: Türkçe karakterler SSMS tarafında mojibake olmamalı."
      )

      user_res <- DBI::dbGetQuery(
        conn,
        "
          INSERT INTO MB_Users (KullaniciAdi, KaynakAdi, LastLoginDate)
          OUTPUT INSERTED.UserID AS UserID
          VALUES (?, ?, GETDATE())
        ",
        params = normalize_db_params(
          list(probe_username, probe_name)
        )
      )

      probe_user_id <- as.integer(user_res$UserID[1])

      chat_res <- DBI::dbGetQuery(
        conn,
        "
          INSERT INTO MB_Chats (UserID, ChatTitle)
          OUTPUT INSERTED.ChatID AS ChatID
          VALUES (?, ?)
        ",
        params = normalize_db_params(
          list(probe_user_id, probe_title)
        )
      )

      probe_chat_id <- as.integer(chat_res$ChatID[1])

      message_res <- tryCatch(
        DBI::dbGetQuery(
          conn,
          "
            INSERT INTO MB_Messages
              (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder, ReasoningContent)
            OUTPUT INSERTED.MessageID AS MessageID
            VALUES (?, ?, 'user', GETDATE(), 1, ?)
          ",
          params = normalize_db_params(
            list(probe_chat_id, probe_message, probe_reasoning)
          )
        ),
        error = function(e) {
          DBI::dbGetQuery(
            conn,
            "
              INSERT INTO MB_Messages
                (ChatID, MessageContent, MessageType, MessageTimestamp, MessageOrder)
              OUTPUT INSERTED.MessageID AS MessageID
              VALUES (?, ?, 'user', GETDATE(), 1)
            ",
            params = normalize_db_params(
              list(probe_chat_id, probe_message)
            )
          )
        }
      )

      probe_message_id <- as.integer(message_res$MessageID[1])

      DBI::dbExecute(
        conn,
        "
          INSERT INTO MB_Feedback
            (UserID, MessageID, FeedbackType, FeedbackTags, FeedbackComment, FeedbackTimestamp)
          VALUES (?, ?, ?, ?, ?, CAST(GETDATE() AS datetime2(0)))
        ",
        params = normalize_db_params(
          list(
            probe_user_id,
            probe_message_id,
            probe_feedback_type,
            probe_feedback_tags,
            probe_feedback_comment
          )
        )
      )

      read_back <- DBI::dbGetQuery(
        conn,
        "
          SELECT
            u.KullaniciAdi,
            u.KaynakAdi,
            c.ChatTitle,
            m.MessageContent,
            m.ReasoningContent,
            f.FeedbackType,
            f.FeedbackTags,
            f.FeedbackComment
          FROM MB_Users u
          INNER JOIN MB_Chats c ON c.UserID = u.UserID
          INNER JOIN MB_Messages m ON m.ChatID = c.ChatID
          LEFT JOIN MB_Feedback f ON f.MessageID = m.MessageID AND f.UserID = u.UserID
          WHERE u.UserID = ?
        ",
        params = normalize_db_params(list(probe_user_id))
      )

      raw_values <- unlist(read_back, use.names = FALSE)
      raw_values <- raw_values[!is.na(raw_values)]

      if (vm_encoding_preflight_has_mojibake(raw_values)) {
        vm_encoding_preflight_stop(sprintf(
          "Transactional DB encoding write probe mojibake tespit etti: %s",
          paste(raw_values, collapse = " | ")
        ))
      }

      expected_values <- c(
        "VM Ön Kontrol Kullanıcısı",
        "Türkçe test: ç ğ ı İ ö ş ü Ç Ğ I Ö Ş Ü",
        "Türkiye'nin başkenti neresidir? Nasıl yardımcı olabilirim?",
        "açıklama,öneri,şikayet-değil",
        "Görüş: Türkçe karakterler SSMS tarafında mojibake olmamalı."
      )

      read_back_text <- paste(enc2utf8(as.character(raw_values)), collapse = "\n")

      missing_expected <- expected_values[!vapply(
        expected_values,
        function(expected) grepl(expected, read_back_text, fixed = TRUE, useBytes = FALSE),
        logical(1)
      )]

      if (length(missing_expected) > 0L) {
        vm_encoding_preflight_stop(sprintf(
          "Transactional DB encoding write probe beklenen Türkçe metinleri geri okuyamadı: %s",
          paste(missing_expected, collapse = " | ")
        ))
      }

      DBI::dbRollback(conn)
      rollback_needed <- FALSE

      cat("OK: Transactional DB encoding write/read probe başarılı; test kayıtları rollback edildi.\n")
      cat("INFO: Bu kontrol SSMS ile manuel app-flow doğrulamasının yerine geçmez.\n")
    }, error = function(e) {
      if (isTRUE(rollback_needed)) {
        try(DBI::dbRollback(conn), silent = TRUE)
      }
      stop(e)
    })
  }
}, finally = {
  release_connection(conn_info)
})

cat("OK: Windows VM SQL Server encoding preflight tamamlandı. WARN çıktıysa yalnızca tarihsel veri / opsiyonel şema uyarısı olarak değerlendirin; yeni yazma regresyonu transactional probe ile ayrıca doğrulanmalıdır.\n")