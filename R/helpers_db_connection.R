# ==============================================================================
# Dosya Yolu: R/helpers_db_connection.R
# Açıklama: Veritabanı bağlantısı, havuz sağlık kontrolü ve worker tarafı
#           güvenli DB bağlantı yardımcılarını içerir.
# ==============================================================================

library(DBI)
library(odbc)
library(pool)

.DEFAULT_DSN <- Sys.getenv("DB_DSN", "TestConnection")

resolve_db_client_encoding <- function() {
  # DB istemci kodlaması üretim VM üzerinde .Renviron ile yönetilir.
  # Ortam değişkeni yoksa test/local varsayılanı korunur.
  env_encoding <- Sys.getenv("DB_CLIENT_ENCODING", unset = NA_character_)

  if (!is.na(env_encoding) && nzchar(trimws(env_encoding))) {
    return(trimws(as.character(env_encoding)[1]))
  }

  option_encoding <- getOption("mergen.db.client_encoding", "UTF-8")
  option_encoding <- as.character(option_encoding)[1]

  if (is.na(option_encoding) || !nzchar(trimws(option_encoding))) {
    return("UTF-8")
  }

  trimws(option_encoding)
}

resolve_db_name_encoding <- function(client_encoding = resolve_db_client_encoding()) {
  # Sütun/tablo adı kodlaması ayrı verilmemişse istemci kodlamasıyla aynı tutulur.
  env_encoding <- Sys.getenv("DB_NAME_ENCODING", unset = NA_character_)

  if (!is.na(env_encoding) && nzchar(trimws(env_encoding))) {
    return(trimws(as.character(env_encoding)[1]))
  }

  option_encoding <- getOption("mergen.db.name_encoding", client_encoding)
  option_encoding <- as.character(option_encoding)[1]

  if (is.na(option_encoding) || !nzchar(trimws(option_encoding))) {
    return(client_encoding)
  }

  trimws(option_encoding)
}

db_client_encoding_is_utf8 <- function(encoding_name) {
  encoding_name <- toupper(gsub("[_-]", "", as.character(encoding_name %||% "")[1]))
  identical(encoding_name, "UTF8")
}

.DEFAULT_DB_CLIENT_ENCODING <- resolve_db_client_encoding()
.DEFAULT_DB_NAME_ENCODING <- resolve_db_name_encoding(.DEFAULT_DB_CLIENT_ENCODING)

normalize_db_value <- function(x, repair_mojibake = FALSE) {
  # DBI parametreleri çoğunlukla skaler gelir; yine de bu yardımcı vektör,
  # NA ve boş karakter girdilerinde uyarı üretmemelidir. Strict test runner
  # stop_on_warning = TRUE kullandığı için burada warning-free davranış kritiktir.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (length(x) == 0L) {
    return(x)
  }

  repair_mojibake <- isTRUE(repair_mojibake)

  out_utf8 <- if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    normalize_text_utf8(x, repair_mojibake = repair_mojibake)
  } else {
    tryCatch(
      enc2utf8(x),
      error = function(e) x
    )
  }

  out_utf8[is.na(x)] <- NA_character_

  client_encoding <- resolve_db_client_encoding()
  client_is_utf8 <- db_client_encoding_is_utf8(client_encoding)

  if (isTRUE(client_is_utf8) && isTRUE(l10n_info()[["UTF-8"]])) {
    return(out_utf8)
  }

  if (!isTRUE(client_is_utf8)) {
    out_client <- tryCatch(
      iconv(out_utf8, from = "UTF-8", to = client_encoding, sub = NA_character_),
      error = function(e) rep(NA_character_, length(out_utf8))
    )

    failed <- is.na(out_client) & !is.na(out_utf8)

    # WINDOWS-1254 Türkçe karakterleri temsil eder; ancak bazı Unicode sembolleri
    # temsil edemez. Böyle bir karakter tüm string için iconv sonucunu NA yaparsa,
    # ham UTF-8'e düşmek yerine temsil edilemeyen karakterleri DB sınırında çıkarırız.
    # Bu, MB_Messages yazımında Türkçe metnin mojibake olmasını engeller.
    if (any(failed)) {
      stripped_values <- tryCatch(
        iconv(out_utf8[failed], from = "UTF-8", to = client_encoding, sub = ""),
        error = function(e) rep("", sum(failed))
      )

      stripped_values[is.na(stripped_values)] <- ""
      out_client[failed] <- stripped_values
    }

    if (any(!is.na(out_client))) {
      Encoding(out_client[!is.na(out_client)]) <- "unknown"
    }

    out_client[is.na(x)] <- NA_character_
    return(out_client)
  }

  out_native <- tryCatch(
    enc2native(out_utf8),
    error = function(e) out_utf8
  )

  out_native[is.na(x)] <- NA_character_

  roundtrip_utf8 <- tryCatch(
    enc2utf8(out_native),
    error = function(e) out_utf8
  )
  roundtrip_utf8[is.na(x)] <- NA_character_

  if (!identical(unname(roundtrip_utf8), unname(out_utf8))) {
    return(out_utf8)
  }

  out_native
}

normalize_db_visible_value <- function(x) {
  # Kullanıcıya görünen metinler DB parametre sınırına gelmeden onarılır.
  # Teknik kimlik, enum, bayrak ve yol alanları bu yardımcıdan geçirilmemelidir.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(x, repair_mojibake = TRUE))
  }

  enc2utf8(x)
}

normalize_db_technical_value <- function(x) {
  # Teknik karakter alanları UTF-8 olarak işaretlenir; mojibake onarımı yapılmaz.
  if (is.null(x) || !is.character(x)) {
    return(x)
  }

  if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    return(normalize_text_utf8(x, repair_mojibake = FALSE))
  }

  enc2utf8(x)
}

db_visible_text_has_mojibake <- function(value) {
  if (is.null(value) || length(value) == 0L) {
    return(FALSE)
  }

  text <- paste(enc2utf8(as.character(value)), collapse = "\n")

  if (!nzchar(text)) {
    return(FALSE)
  }

  mojibake_tokens <- c(
    "\u00C3\u00A7", # c cedilla corrupted
    "\u00C3\u00B6", # o umlaut corrupted
    "\u00C3\u00BC", # u umlaut corrupted
    "\u00C4\u00B1", # dotless i corrupted
    "\u00C4\u00B0", # dotted capital I corrupted
    "\u00C4\u0178", # g breve corrupted
    "\u00C5\u0178", # s cedilla corrupted
    "\u00C3\u2021", # capital C cedilla corrupted
    "\u00C3\u2013", # capital O umlaut corrupted
    "\u00C3\u0153", # capital U umlaut corrupted
    "\u00C4\u017E", # capital G breve corrupted
    "\u00C5\u017E", # capital S cedilla corrupted
    "T\u00C3\u00BCrkiye",
    "Nas\u00C4\u00B1l",
    "yard\u00C4\u00B1mc\u00C4\u00B1",
    "ba\u00C5\u0178kent",
    "te\u00C5\u0178ekk\u00C3\u00BCr"
  )

  any(vapply(
    mojibake_tokens,
    function(token) grepl(token, text, fixed = TRUE),
    logical(1)
  ))
}

assert_mb_message_visible_encoding_clean <- function(conn, message_id) {
  if (is.null(conn) || is.null(message_id) || is.na(message_id)) {
    return(invisible(TRUE))
  }

  has_reasoning_content <- tryCatch({
    cols <- DBI::dbGetQuery(
      conn,
      "
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'MB_Messages'
          AND COLUMN_NAME = 'ReasoningContent'
      "
    )
    nrow(cols) > 0L
  }, error = function(e) {
    FALSE
  })

  query <- if (isTRUE(has_reasoning_content)) {
    "
      SELECT MessageContent, ReasoningContent
      FROM MB_Messages
      WHERE MessageID = ?
    "
  } else {
    "
      SELECT
        MessageContent,
        CAST(NULL AS NVARCHAR(MAX)) AS ReasoningContent
      FROM MB_Messages
      WHERE MessageID = ?
    "
  }

  row <- DBI::dbGetQuery(
    conn,
    query,
    params = normalize_db_params(list(as.integer(message_id)))
  )

  if (nrow(row) == 0L) {
    return(invisible(TRUE))
  }

  if (db_visible_text_has_mojibake(row$MessageContent) ||
      db_visible_text_has_mojibake(row$ReasoningContent)) {
    stop(
      sprintf(
        "MB_Messages encoding guard failed after insert. MessageID=%s. Transaction will be rolled back.",
        as.character(message_id)
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

normalize_db_params <- function(params, repair_mojibake = FALSE) {
  lapply(params, normalize_db_value, repair_mojibake = repair_mojibake)
}

get_pool_info <- function() {
  start_time <- Sys.time()
  conn_info <- NULL

  tryCatch({
    conn_info <- get_connection()
    DBI::dbGetQuery(conn_info$conn, "SELECT 1 AS ok")

    elapsed_ms <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000)
    mode_text <- if (isTRUE(conn_info$pooled)) "Bağlantı Havuzu" else "Doğrudan Bağlantı"

    list(
      valid = TRUE,
      mode = mode_text,
      note = sprintf("Veritabanı erişim testi başarılı (%d ms)", elapsed_ms),
      response_ms = elapsed_ms
    )
  }, error = function(e) {
    list(
      valid = FALSE,
      mode = "Doğrudan Bağlantı",
      note = "Veritabanı erişim testi başarısız",
      error = conditionMessage(e)
    )
  }, finally = {
    release_connection(conn_info)
  })
}

db_pool_healthy <- function(timeout_sec = 5) {
  basla <- Sys.time()

  info <- tryCatch({
    setTimeLimit(elapsed = as.numeric(timeout_sec), transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf, transient = TRUE), add = TRUE)
    get_pool_info()
  }, error = function(e) {
    list(valid = FALSE, error = conditionMessage(e))
  })

  sure <- as.numeric(difftime(Sys.time(), basla, units = "secs"))
  if (sure > as.numeric(timeout_sec)) {
    return(FALSE)
  }

  isTRUE(info$valid)
}

get_connection <- function(target = "primary") {
  dsn_var <- switch(target,
    "primary"   = "DB_DSN",
    "secondary" = "DB_DSN_2",
    "tertiary"  = "DB_DSN_3",
    "DB_DSN"
  )

  if (target == "primary" && exists("pool", envir = .GlobalEnv, inherits = FALSE)) {
    pool_obj <- tryCatch(
      get("pool", envir = .GlobalEnv, inherits = FALSE),
      error = function(e) NULL
    )

    if (!is.null(pool_obj) && inherits(pool_obj, "Pool")) {
      return(list(conn = pool_obj, pooled = TRUE, pool = pool_obj))
    }
  }

  if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
    stop("Worker/process requires 'odbc' and 'DBI' packages installed.", call. = FALSE)
  }

  dsn_name <- Sys.getenv(dsn_var, .DEFAULT_DSN)

  if (identical(dsn_name, "")) {
    stop(
      sprintf(
        "HATA: '%s' için .Renviron içinde DSN tanımı bulunamadı (Target: %s)",
        dsn_var,
        target
      ),
      call. = FALSE
    )
  }

  conn <- DBI::dbConnect(
    odbc::odbc(),
    dsn = dsn_name,
    encoding = .DEFAULT_DB_CLIENT_ENCODING,
    name_encoding = .DEFAULT_DB_NAME_ENCODING
  )

  list(conn = conn, pooled = FALSE, pool = NULL)
}

release_connection <- function(conn_info) {
  if (is.null(conn_info)) return(invisible(NULL))

  if (isTRUE(conn_info$pooled)) {
    return(invisible(NULL))
  }

  tryCatch({
    DBI::dbDisconnect(conn_info$conn)
  }, error = function(e) {
    invisible(NULL)
  })

  invisible(NULL)
}

worker_db_connect <- function(max_retries = 3, retry_delay = 1) {
  for (i in seq_len(max_retries)) {
    tryCatch({
      if (!requireNamespace("odbc", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
        stop("Worker needs 'odbc' and 'DBI' packages installed.", call. = FALSE)
      }

      conn <- DBI::dbConnect(
        odbc::odbc(),
        dsn = Sys.getenv("DB_DSN", .DEFAULT_DSN),
        encoding = .DEFAULT_DB_CLIENT_ENCODING,
        name_encoding = .DEFAULT_DB_NAME_ENCODING
      )

      return(conn)
    }, error = function(e) {
      if (i == max_retries) {
        stop(
          paste("Failed to connect to database after", max_retries, "attempts:", e$message),
          call. = FALSE
        )
      }

      Sys.sleep(retry_delay * i)
    })
  }
}