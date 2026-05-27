# ==============================================================================
# Dosya Yolu: R/helpers_db_connection.R
# Açıklama: Veritabanı bağlantısı, havuz sağlık kontrolü ve worker tarafı
#           güvenli DB bağlantı yardımcılarını içerir.
# ==============================================================================

# Bu dosya test bootstrap içinde cloud-quick modunda da source edilir.
# Bu nedenle odbc/pool gibi ağır runtime paketleri top-level library() ile
# zorunlu kılınmaz; gerçek bağlantı açan fonksiyonlar kendi içinde
# requireNamespace() ile net hata verir.
if (!requireNamespace("DBI", quietly = TRUE)) {
  stop("R/helpers_db_connection.R requires the 'DBI' package.", call. = FALSE)
}

if (!exists("resolve_db_client_encoding", mode = "function", inherits = TRUE) ||
    !exists("normalize_db_params", mode = "function", inherits = TRUE)) {
  stop(
    "R/helpers_db_encoding.R must be sourced before R/helpers_db_connection.R",
    call. = FALSE
  )
}

.DEFAULT_DSN <- Sys.getenv("DB_DSN", "TestConnection")

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