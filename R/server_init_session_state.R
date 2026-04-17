# ==============================================================================
# Dosya Yolu: R/server_init_session_state.R
# Açıklama: server.R için oturum-yerel reaktif durumları ve başlangıç geri
#           bildirim yükleme akışını kurar.
# ==============================================================================

serverInitSessionState <- function(session, resolve_current_user_id, sso_state = NULL) {

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
  values <- reactiveValues(
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

  # ---------------------------------------------------------------------------
  # Yardımcı reaktif bayraklar
  # ---------------------------------------------------------------------------
  stop_generation <- reactiveVal(FALSE)
  file_to_add <- reactiveVal(NULL)
  session_files <- reactiveVal(list())
  active_request_id <- reactiveVal(NULL)
  quick_action_skip_mcp <- reactiveVal(FALSE)

  # ---------------------------------------------------------------------------
  # Veritabanından geri bildirimleri yükle
  # ---------------------------------------------------------------------------
  sync_feedback_from_db <- function() {
    effective_user_id <- resolve_current_user_id()

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
  if (isTRUE(session$userData$sso_active)) {
    observeEvent(sso_state$authenticated, {
      req(isTRUE(sso_state$authenticated), isTRUE(session$userData$auth_initialized))
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