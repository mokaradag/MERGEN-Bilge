# ==============================================================================
# R/module_performance.R
# Dosya Yolu: R/module_performance.R
# Açıklama: Shiny uygulaması için performans takip modülü.
# Gerçek aktif oturum/kullanıcı sayısını izler; toplam istek, başarılı istek,
# ortalama yanıt süresi ve hata sayılarını takip eder.
# ==============================================================================

performanceStatsServer <- function(id, current_user_id_provider) {
  moduleServer(id, function(input, output, session) {

    # Geçerli kullanıcı kimliğini güvenli şekilde çöz
    get_current_user_id <- function() {
      raw_id <- if (is.function(current_user_id_provider)) {
        current_user_id_provider()
      } else {
        current_user_id_provider
      }

      uid <- suppressWarnings(as.integer(raw_id %||% 0L))
      if (is.na(uid)) uid <- 0L
      uid
    }

    # --- PERFORMANS İSTATİSTİKLERİ ---
    stats <- reactiveValues(
      active_users = 0,
      total_requests = 0,
      successful_requests = 0,
      avg_response_time = 0,
      error_count = 0,
      last_request_time = NULL,
      uptime_start = Sys.time()
    )

    # İstatistiklerin kaydedileceği dosya yolu
    stats_file <- "logs/performance_stats.txt"

    # --- AKTİF OTURUM DEFTERİ ---
    if (!exists(".mergen_active_sessions", envir = .GlobalEnv, inherits = FALSE)) {
      assign(".mergen_active_sessions", new.env(parent = emptyenv()), envir = .GlobalEnv)
    }
    active_sessions_env <- get(".mergen_active_sessions", envir = .GlobalEnv)

    # Bağlantısı kopmuş ama temizlenmemiş oturumlar için zaman aşımı
    session_timeout_secs <- 1800

    cleanup_active_sessions <- function() {
      current_time <- Sys.time()
      tokens <- ls(envir = active_sessions_env)

      if (!length(tokens)) {
        return(invisible(NULL))
      }

      for (tok in tokens) {
        entry <- tryCatch(active_sessions_env[[tok]], error = function(e) NULL)

        if (is.null(entry) || is.null(entry$last_seen)) {
          try(rm(list = tok, envir = active_sessions_env), silent = TRUE)
          next
        }

        age_secs <- as.numeric(difftime(current_time, entry$last_seen, units = "secs"))
        if (is.na(age_secs) || age_secs > session_timeout_secs) {
          try(rm(list = tok, envir = active_sessions_env), silent = TRUE)
        }
      }

      invisible(NULL)
    }

    count_active_sessions <- function() {
      cleanup_active_sessions()
      length(ls(envir = active_sessions_env))
    }

    count_active_users <- function() {
      cleanup_active_sessions()
      tokens <- ls(envir = active_sessions_env)

      if (!length(tokens)) {
        return(0L)
      }

      user_ids <- vapply(tokens, function(tok) {
        entry <- tryCatch(active_sessions_env[[tok]], error = function(e) NULL)
        uid <- suppressWarnings(as.integer(entry$user_id %||% 0L))
        if (is.na(uid)) uid <- 0L
        uid
      }, integer(1))

      as.integer(length(unique(user_ids[user_ids > 0])))
    }

    touch_session <- function(user_id = NULL) {
      uid <- suppressWarnings(as.integer(user_id %||% get_current_user_id()))
      if (is.na(uid)) uid <- 0L

      active_sessions_env[[session$token]] <- list(
        user_id = uid,
        last_seen = Sys.time()
      )

      stats$active_users <- count_active_users()
      invisible(NULL)
    }

    persist_stats <- function() {
      tryCatch({
        if (!dir.exists("logs")) dir.create("logs", recursive = TRUE)

        stats_df <- data.frame(
          total_requests = stats$total_requests,
          successful_requests = stats$successful_requests,
          avg_response_time = stats$avg_response_time,
          error_count = stats$error_count,
          stringsAsFactors = FALSE
        )

        write.table(
          stats_df,
          stats_file,
          row.names = FALSE,
          sep = "\t",
          quote = FALSE
        )
      }, error = function(e) {
        cat("[ERROR] Failed to save stats:", e$message, "\n")
      })
    }

    # --- MEVCUT İSTATİSTİKLERİ YÜKLEME ---
    isolate({
      if (file.exists(stats_file)) {
        saved <- tryCatch({
          read.table(stats_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        }, error = function(e) NULL)

        if (!is.null(saved) && nrow(saved) > 0) {
          stats$total_requests <- as.numeric(saved$total_requests[1] %||% 0)
          stats$error_count <- as.numeric(saved$error_count[1] %||% 0)

          stats$successful_requests <- if ("successful_requests" %in% names(saved)) {
            as.numeric(saved$successful_requests[1] %||% 0)
          } else {
            max(0, stats$total_requests - stats$error_count)
          }

          stats$avg_response_time <- as.numeric(saved$avg_response_time[1] %||% 0)

          cat(sprintf(
            "[STATS LOADED] Total: %d, Success: %d, Avg: %.2f, Errors: %d\n",
            stats$total_requests,
            stats$successful_requests,
            stats$avg_response_time,
            stats$error_count
          ))
        }
      }
    })

    # Bu oturumu kaydet
    touch_session(get_current_user_id())

    # Oturum yaşadığı sürece heartbeat gönder
    observe({
      invalidateLater(60000, session)
      touch_session(get_current_user_id())
    })

    # Oturum kapanınca defterden çıkar
    session$onSessionEnded(function() {
      try(rm(list = session$token, envir = active_sessions_env), silent = TRUE)
    })

    # --- BAŞARILI İSTEK TAKİBİ ---
    track_request <- function(duration_seconds = NULL) {
      isolate({
        stats$total_requests <- stats$total_requests + 1
        stats$successful_requests <- stats$successful_requests + 1
        stats$last_request_time <- Sys.time()

        if (!is.null(duration_seconds) && is.finite(duration_seconds)) {
          success_total <- stats$successful_requests
          current_avg <- stats$avg_response_time

          stats$avg_response_time <- if (success_total <= 1) {
            duration_seconds
          } else {
            ((current_avg * (success_total - 1)) + duration_seconds) / success_total
          }
        }

        cat(sprintf(
          "[STATS] Total: %d, Success: %d, Avg: %.2f, Errors: %d\n",
          stats$total_requests,
          stats$successful_requests,
          stats$avg_response_time,
          stats$error_count
        ))

        if (stats$total_requests %% 10 == 0) {
          persist_stats()
        }
      })
    }

    # --- HATA TAKİBİ ---
    track_error <- function() {
      isolate({
        stats$total_requests <- stats$total_requests + 1
        stats$error_count <- stats$error_count + 1
        stats$last_request_time <- Sys.time()

        cat(sprintf(
          "[STATS] Total: %d, Success: %d, Errors: %d\n",
          stats$total_requests,
          stats$successful_requests,
          stats$error_count
        ))

        if (stats$total_requests %% 10 == 0) {
          persist_stats()
        }
      })
    }

    return(list(
      track_request = track_request,
      track_error = track_error,
      touch_session = touch_session,
      get_active_session_count = count_active_sessions,
      stats = stats
    ))
  })
}