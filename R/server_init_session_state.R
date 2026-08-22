# ==============================================================================
# Dosya Yolu: R/server_init_session_state.R
# Açıklama: server.R için oturum-yerel reaktif durumları ve başlangıç geri
#           bildirim yükleme akışını kurar.
# ==============================================================================

serverInitSessionState <- function(session, identity, sso_state = NULL) {

  if (is.null(identity) ||
      !is.function(identity$resolve_current_user_id) ||
      !is.function(identity$is_sso_active) ||
      !is.function(identity$is_auth_ready)) {
    stop(
      "serverInitSessionState: identity sözleşmesi eksik veya geçersiz.",
      call. = FALSE
    )
  }

  # ---------------------------------------------------------------------------
  # Başlangıç geri bildirim durumu
  # ---------------------------------------------------------------------------
  initial_feedback <- list(
    liked = character(0),
    disliked = character(0)
  )

  # ---------------------------------------------------------------------------
  # Ana reaktif durum nesnesi
  # ---------------------------------------------------------------------------
  values <- shiny::reactiveValues(
    messages = list(),
    saved_chats = list(),
    show_welcome = TRUE,
    current_chat_id = NULL,
    last_request_time = NULL,
    is_sending = FALSE,
    typing = FALSE,
    liked_messages = initial_feedback$liked,
    disliked_messages = initial_feedback$disliked,
    current_font_size = "medium",
    temp_files = list()
  )

  # Karşılama ekranının oturum içi bağlanma durumu
  session$userData$welcome_screen_attached <- FALSE

  # Oturum-yerel ortak depolar tek sözleşmeden hazırlanır.
  session_runtime_store_reset(session)

  # ---------------------------------------------------------------------------
  # Yardımcı reaktif bayraklar
  # ---------------------------------------------------------------------------
  stop_generation <- shiny::reactiveVal(FALSE)
  file_to_add <- shiny::reactiveVal(NULL)
  session_files <- shiny::reactiveVal(list())
  active_request_id <- shiny::reactiveVal(NULL)
  quick_action_skip_mcp <- shiny::reactiveVal(FALSE)

  # ---------------------------------------------------------------------------
  # Veritabanından geri bildirimleri yükle
  # ---------------------------------------------------------------------------
  sync_feedback_from_db <- function() {
    effective_user_id <- identity$resolve_current_user_id()

    if (effective_user_id <= 0) {
      return(invisible(NULL))
    }

    all_feedback <- load_feedback_from_db(effective_user_id)
    values$liked_messages <- all_feedback$liked
    values$disliked_messages <- all_feedback$disliked

    invisible(NULL)
  }

  # ---------------------------------------------------------------------------
  # SSO veya yerel mod için geri bildirim yükleme akışı
  # ---------------------------------------------------------------------------
  if (isTRUE(identity$is_sso_active())) {
    if (is.null(sso_state)) {
      stop(
        "serverInitSessionState: SSO modunda sso_state gereklidir.",
        call. = FALSE
      )
    }

    shiny::observeEvent(sso_state$authenticated, {
      shiny::req(isTRUE(sso_state$authenticated), isTRUE(identity$is_auth_ready()))
      sync_feedback_from_db()
    }, ignoreInit = TRUE, once = TRUE)
  } else {
    sync_feedback_from_db()
  }

  list(
    values = values,
    stop_generation = stop_generation,
    file_to_add = file_to_add,
    session_files = session_files,
    active_request_id = active_request_id,
    quick_action_skip_mcp = quick_action_skip_mcp,
    sync_feedback_from_db = sync_feedback_from_db
  )
}

# ==============================================================================
# PR #695 — Proje/Kaynak Analizi Codex çalışma zamanı düzeltmeleri
# ==============================================================================
# Bu katman server init bölümünde, analiz ve Ortak Oturum modüllerinden sonra
# yüklenir. Büyük orkestratörleri büyütmeden dört sınırı sertleştirir:
#   * ortak oda SQL yanıtlarında köken alt bilgisi,
#   * DB hatası sonrasında bağlantı tekrarının önlenmesi,
#   * derin analiz kimlik bağlantısının erken bırakılması,
#   * yarım kalan filtre gözlemlerinin istek sonunda temizlenmesi.

.pk_hook_runtime_env <- environment()

.pk_hook_scalar_text <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  out <- as.character(x)[1]
  if (is.na(out)) "" else out
}

pk_filter_observation_clear <- function(request_id = NULL, question = NULL) {
  state <- if (exists(".pk_filter_observation_state", inherits = TRUE)) {
    get(".pk_filter_observation_state", inherits = TRUE)
  } else {
    NULL
  }
  if (!is.environment(state)) return(invisible(FALSE))

  keys <- ls(state, all.names = TRUE)
  if (length(keys) == 0L) return(invisible(FALSE))

  request_id <- .pk_hook_scalar_text(request_id)
  question <- .pk_hook_scalar_text(question)
  if (!nzchar(request_id) && !nzchar(question)) return(invisible(FALSE))

  remove_key <- vapply(keys, function(key) {
    parts <- strsplit(key, "\u001f", fixed = TRUE)[[1]]
    request_match <- nzchar(request_id) && length(parts) >= 1L &&
      identical(parts[[1]], request_id)
    question_match <- !nzchar(request_id) && nzchar(question) &&
      length(parts) >= 4L && identical(parts[[4]], question)
    request_match || question_match
  }, logical(1))

  doomed <- keys[remove_key]
  if (length(doomed) == 0L) return(invisible(FALSE))

  rm(list = doomed, envir = state)
  invisible(TRUE)
}

.pk_hook_current_request_id <- function(session) {
  if (!exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
    return(NULL)
  }
  tryCatch(pk_provenance_current_request_id(session), error = function(e) NULL)
}

.pk_hook_session_username <- function(session) {
  tryCatch(
    session$userData$system_username %||%
      session$userData$username %||%
      session$userData$user_name %||%
      "Unknown",
    error = function(e) "Unknown"
  )
}

# Çıkışın DB/SQL kaynaklı olup olmadığını METİNDEN sınıflandırır. İstisnalar da
# koşulsuz DB hatası sayılmaz: aksi halde ayrıştırma, sorgu seçimi veya başka
# uygulama hataları conn = NULL ile gözlemlenir ve MB_Analiz_Log'a hiç yazılmaz.
# Yeniden bağlanmama yolu yalnızca gerçekten DB kaynaklı çıkışlara ayrılmıştır.
.pk_hook_database_failure_text <- function(text, is_exception = FALSE) {
  text <- .pk_hook_scalar_text(text)
  if (!nzchar(text)) return(FALSE)

  patterns <- c(
    "Veritabanı Hatası", "SQLSTATE", "ODBC", "nanodbc",
    "Login timeout", "Login failed", "could not connect",
    "Connection refused", "DSN=", "Driver="
  )

  # İstisna mesajlarında bağlantı katmanı hataları DBI/ODBC biçiminde görünür.
  if (isTRUE(is_exception)) {
    patterns <- c(
      patterns,
      "dbConnect", "dbGetQuery", "dbSendQuery", "dbExecute",
      "Data source name not found",
      "08001", "08S01", "HYT00", "IM002"
    )
  }

  any(vapply(patterns, function(pattern) {
    grepl(pattern, text, fixed = TRUE, useBytes = TRUE)
  }, logical(1)))
}

# server_init_chat_runtime.R kendi doğrudan-çıkış sarmalayıcısını kurduktan
# sonra çağrılır. DB/SQL hata çıkışı biliniyorsa telemetri için ikinci bağlantı
# açılmaz; pk_analysis_observe(conn = NULL) köken alt bilgisini yine hazırlar.
pk_hook_single_exit_fix_install <- function() {
  target_env <- .pk_hook_runtime_env
  if (!exists(
    ".pk_analiz_process_request_without_exit_observer",
    mode = "function",
    envir = target_env,
    inherits = TRUE
  ) || exists(
    ".pk_hook_single_exit_installed",
    envir = target_env,
    inherits = FALSE
  )) {
    return(invisible(FALSE))
  }

  core <- get(
    ".pk_analiz_process_request_without_exit_observer",
    mode = "function",
    envir = target_env,
    inherits = TRUE
  )

  replacement <- function(user_prompt, chat_history, session,
                           stop_check = NULL) {
    started_at <- Sys.time()
    request_id <- NULL
    on.exit({
      cleanup_request_id <- request_id %||% .pk_hook_current_request_id(session)
      try(
        pk_filter_observation_clear(cleanup_request_id, user_prompt),
        silent = TRUE
      )
    }, add = TRUE)

    caught_error <- NULL
    result <- tryCatch(
      core(
        user_prompt = user_prompt,
        chat_history = chat_history,
        session = session,
        stop_check = stop_check
      ),
      error = function(e) {
        caught_error <<- e
        e
      }
    )

    request_id <- .pk_hook_current_request_id(session)
    is_exception <- inherits(result, "condition")
    is_direct_exit <- is_exception || is.character(result) ||
      (is.list(result) && identical(result$type, "error_message"))
    if (!isTRUE(is_direct_exit)) return(result)

    has_pending_footer <- tryCatch(
      !is.null(session$userData$pk_provenance_pending),
      error = function(e) FALSE
    )
    if (isTRUE(has_pending_footer)) {
      if (is_exception) stop(caught_error)
      return(result)
    }

    auth_pending <- tryCatch(
      identical(session$userData$auth_initialized, FALSE),
      error = function(e) FALSE
    )
    if (isTRUE(auth_pending) ||
        !exists("pk_analysis_observe", mode = "function", inherits = TRUE)) {
      if (is_exception) stop(caught_error)
      return(result)
    }

    response_text <- if (is_exception) {
      conditionMessage(result)
    } else if (is.character(result)) {
      .pk_hook_scalar_text(result)
    } else {
      .pk_hook_scalar_text(result$content)
    }

    stopped <- grepl("İşlem Durduruldu", response_text, fixed = TRUE)
    unauthorized <- grepl("Yetki Hatası", response_text, fixed = TRUE)
    no_match <- grepl(
      "mevcut analiz kütüphanesinde bulunamadı",
      response_text,
      fixed = TRUE
    )

    outcome <- if (stopped) {
      "Durduruldu"
    } else if (unauthorized) {
      "Yetkisiz"
    } else if (no_match) {
      "EslesmeYok"
    } else {
      "Hata"
    }

    user_id <- tryCatch(session$userData$user_id %||% NULL, error = function(e) NULL)
    database_failure <- .pk_hook_database_failure_text(response_text, is_exception)

    conn_list <- NULL
    conn <- NULL
    # DURDURULMUŞ İSTEK YENİ BİR BAĞLANTI AÇMAZ.
    #
    # `stopped` bir DB arızası DEĞİLDİR, bu yüzden eski koşul bu dala giriyordu:
    # havuz kapalıyken `get_connection()` ANA Shiny olay döngüsünde bloklayan bir
    # ODBC login başlatabiliyor ve iptal ZATEN onaylanmışken yanıtı geciktirip
    # diğer oturumları donduruyordu. İşçi doğrudan-çıkış sarmalayıcısı bu
    # atlamayı zaten yapar; ana süreç de aynı sözleşmeye uyar.
    if (!isTRUE(database_failure) && !isTRUE(stopped)) {
      conn_list <- tryCatch(get_connection(), error = function(e) NULL)
      conn <- if (is.list(conn_list)) conn_list$conn %||% NULL else NULL
      if (!is.null(conn_list)) {
        on.exit(try(release_connection(conn_list), silent = TRUE), add = TRUE)
      }
    }

    try(
      pk_analysis_observe(session, conn, list(
        request_id = request_id,
        question = user_prompt,
        username = .pk_hook_session_username(session),
        user_id = user_id,
        deep_thinking = FALSE,
        # ETKİN MOTOR DOĞRUDAN ÇIKIŞTA DA YAZILIR: alan boş kalınca
        # `pk_telemetry_build_record()` `Motor`u v1 varsayıyor ve v2 istekleri
        # (yetkisiz / eşleşme yok / hata) yanlış motora atfediliyordu.
        engine = if (exists("pk_engine_mode", mode = "function", inherits = TRUE)) {
          tryCatch(pk_engine_mode(), error = function(e) NULL)
        } else {
          NULL
        },
        query_name = "Tekil analiz",
        filter_status = if (stopped) "stopped" else "not_reached",
        filters = list(),
        outcome = outcome,
        duration_ms = as.numeric(difftime(Sys.time(), started_at, units = "secs")) * 1000
      )),
      silent = TRUE
    )

    if (is_exception) stop(caught_error)
    result
  }

  assign("pk_analiz_process_request", replacement, envir = target_env)
  assign(".pk_hook_single_exit_installed", TRUE, envir = target_env)
  invisible(TRUE)
}

