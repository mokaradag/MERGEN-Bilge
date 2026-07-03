# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_workbench_session_api.R
# Açıklama: Bilge Yolaç çalışma alanı modülünün Oturumlar sayfasına açtığı
#           oturum API'sini üretir: kayıtlı oturumu çalışma alanına yükleme
#           (hidrasyon) ve yeni oturum başlatma. module_claude_code.R bu
#           fabrikayı çağırır ve dönen fonksiyonları claudeCodeServer()'ın
#           dönüş değeri olarak dışa açar.
#
# Sözleşmeler:
#   * Geçmiş her zaman görünür yüklenir; Claude CLI --resume yalnızca
#     hidrasyon planı güvenli bulursa (çalışma dizini erişilebilir) kurulur.
#   * Workdir geri yüklemesi input$workdir observer'ının oturum bağlarını
#     sıfırlamaması için rv$suppress_workdir_reset_once bayrağını kullanır.
#   * "Yeni Oturum" görünümü temizler; KALICI GEÇMİŞİ SİLMEZ (detach).
# ==============================================================================

cc_create_workbench_session_api <- function(session,
                                            input,
                                            ns,
                                            rv,
                                            ensure_ready_user_id,
                                            get_active_character,
                                            kullanici_adi) {

  # --- Kayıtlı oturumu çalışma alanına yükle (Oturumlar sayfası çağırır) ---
  load_persisted_session <- function(record_id) {
    if (isTRUE(rv$is_running)) {
      showNotification(
        "Aktif bir çalıştırma sürerken kayıtlı oturum yüklenemez.",
        type = "warning", duration = 5
      )
      return(invisible(FALSE))
    }

    user_check <- ensure_ready_user_id("kayıtlı oturum yükleme")
    if (!isTRUE(user_check$ok)) {
      showNotification(user_check$message, type = "warning", duration = 5)
      return(invisible(FALSE))
    }

    kayit <- cc_db_load_session(user_check$user_id, record_id)
    if (is.null(kayit)) {
      showNotification(
        "Oturum bulunamadı veya bu oturuma erişim yetkiniz yok.",
        type = "error", duration = 5
      )
      return(invisible(FALSE))
    }

    plan <- cc_session_hydration_plan(
      kayit,
      format_output_fn = format_claude_code_output
    )

    # Runtime durumunu geri yükle: geçmiş her zaman görünür; CLI resume
    # yalnızca çalışma dizini hala erişilebilirse denenir.
    rv$claude_session_record_id <- suppressWarnings(as.integer(record_id)[1])
    rv$claude_session_title <- plan$title
    rv$claude_session_loaded <- TRUE
    rv$conversation_context <- plan$conversation_context
    rv$has_messages <- length(plan$messages) > 0L
    rv$cli_session_id <- plan$resume$cli_session_id
    rv$active_runtime_workdir <- plan$resume$runtime_workdir
    rv$active_runtime_source <- plan$resume$source_workdir

    runtime_model <- as.character(kayit$session$RuntimeModel %||% "")[1]
    if (!is.na(runtime_model) && nzchar(runtime_model)) {
      rv$current_runtime_model <- runtime_model
      rv$current_model <- runtime_model
      session$sendCustomMessage(
        type = "cc-set-model-selection",
        message = list(
          inputId = ns("model"),
          value = runtime_model
        )
      )
    }

    # Proje dizinini geri yükle; workdir observer'ının oturum bağlarını
    # sıfırlamaması için bir defalık bastırma bayrağı kullan.
    mevcut_workdir <- isolate(input$workdir)
    if (!is.null(plan$workdir_restore) &&
        !identical(plan$workdir_restore, mevcut_workdir)) {
      rv$suppress_workdir_reset_once <- TRUE
      updateTextInput(session, "workdir", value = plan$workdir_restore)
    }

    karakter <- get_active_character()

    session$sendCustomMessage(
      type = "cc-hydrate-session",
      message = list(
        target = ns("output_area"),
        welcomeId = ns("welcome_screen"),
        statusId = ns("status_text"),
        durationId = ns("duration_text"),
        sessionTitle = plan$title,
        resumeOk = isTRUE(plan$resume$ok),
        accentColor = karakter$accent,
        characterName = karakter$display_name,
        senderName = kullanici_adi(),
        messages = plan$messages
      )
    )

    for (uyari in plan$warnings) {
      showNotification(uyari, type = "warning", duration = 8)
    }

    invisible(TRUE)
  }

  # --- Aktif kayıt arşivlenirken çalışma alanı bağını güvenli kopar ---
  detach_archived_session <- function(record_id, detach = TRUE) {
    aktif_id <- suppressWarnings(as.integer(rv$claude_session_record_id %||% NA_integer_)[1])
    arsiv_id <- suppressWarnings(as.integer(record_id %||% NA_integer_)[1])

    if (is.na(aktif_id) || is.na(arsiv_id) || !identical(aktif_id, arsiv_id)) {
      return(invisible(TRUE))
    }

    if (isTRUE(rv$is_running)) {
      showNotification(
        "Aktif çalışan oturum arşivlenmeden önce durdurulmalıdır.",
        type = "warning", duration = 5
      )
      return(invisible(FALSE))
    }

    if (!isTRUE(detach)) {
      return(invisible(TRUE))
    }

    if (exists("cc_persist_detach_session", mode = "function", inherits = TRUE)) {
      cc_persist_detach_session(rv)
    }
    rv$cli_session_id <- NULL
    rv$conversation_context <- list()
    rv$active_runtime_workdir <- NULL
    rv$active_runtime_source <- NULL
    invisible(TRUE)
  }

  # --- Yeni oturum: görünümü temizler; KALICI GEÇMİŞİ SİLMEZ ---
  start_new_session <- function() {
    if (isTRUE(rv$is_running)) {
      return(invisible(FALSE))
    }

    rv$output_history <- list()
    rv$has_messages <- FALSE
    rv$conversation_context <- list()
    rv$cli_session_id <- NULL
    rv$active_runtime_workdir <- NULL
    rv$active_runtime_source <- NULL

    if (exists("cc_persist_detach_session", mode = "function", inherits = TRUE)) {
      cc_persist_detach_session(rv)
    }

    session$sendCustomMessage(
      type = "cc-clear-output",
      message = list(
        target = ns("output_area"),
        welcomeId = ns("welcome_screen"),
        statusId = ns("status_text"),
        durationId = ns("duration_text")
      )
    )

    invisible(TRUE)
  }

  list(
    load_persisted_session = load_persisted_session,
    start_new_session = start_new_session,
    detach_archived_session = detach_archived_session
  )
}
