# ==============================================================================
# Dosya Yolu: R/helpers_db_connection.R
# Açıklama: Veritabanı bağlantısı, havuz sağlık kontrolü ve worker tarafı
#           güvenli DB bağlantı yardımcılarını içerir.
# ==============================================================================

library(DBI)
library(odbc)
library(pool)

.DEFAULT_DSN <- Sys.getenv("DB_DSN", "TestConnection")
.DEFAULT_DB_CLIENT_ENCODING <- getOption("mergen.db.client_encoding", "UTF-8")
.DEFAULT_DB_NAME_ENCODING <- getOption("mergen.db.name_encoding", .DEFAULT_DB_CLIENT_ENCODING)

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

  if (isTRUE(l10n_info()[["UTF-8"]])) {
    return(out_utf8)
  }

  out_native <- tryCatch(
    enc2native(out_utf8),
    error = function(e) out_utf8
  )

  out_native[is.na(x)] <- NA_character_

  # Windows/native code pages cannot represent all Unicode characters
  # such as emoji. If native conversion is lossy, keep UTF-8 because the
  # ODBC connection is already opened with encoding = "UTF-8".
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