# R/module_chat_actions.R
# Moves like/dislike/regenerate/edit handlers out of server.R with zero behavior change.

chatActionsInit <- function(input, session, values,
                            current_user_id,
                            send_message_fn,
                            stop_generation,
                            reset_chat_state,
                            feedback_modal = NULL) {
  message_to_edit_id <- shiny::reactiveVal(NULL)

  # Etkin kullanıcı kimliğini her kullanım anında oturumdan çöz.
  resolve_current_user_id <- function() {
    session_uid <- session$userData$user_id %||% NULL
    uid <- suppressWarnings(as.integer(session_uid %||% current_user_id %||% 0L))
    if (is.na(uid)) uid <- 0L
    uid
  }

  # Optional: prevent accidental double-handling of the same click within 250ms
  .last_feedback <- shiny::reactiveVal(list(kind = NULL, id = NULL, at = 0))
  .is_recent_duplicate <- function(kind, id, window = 0.25) {
    last <- .last_feedback()
    recent <- is.list(last) && identical(last$kind, kind) && identical(last$id, id) &&
              (as.numeric(Sys.time()) - as.numeric(last$at)) < window
    if (!recent) .last_feedback(list(kind = kind, id = id, at = Sys.time()))
    recent
  }

  # Like
  shiny::observeEvent(input$like_message, {
    req(input$like_message)
    msg_id <- input$like_message
    if (.is_recent_duplicate("like", msg_id)) return()
    idx <- which(vapply(values$messages, function(m) identical(m$id, msg_id), logical(1)))
    if (!length(idx)) return()

    actual <- values$messages[[idx]]
    if (isTRUE(!is.null(actual$db_id)) && isTRUE(!is.na(actual$db_id))) {
      db_id <- as.integer(actual$db_id)
      if (db_id %in% as.integer(values$liked_messages)) {
        effective_user_id <- resolve_current_user_id()
        values$liked_messages <- setdiff(values$liked_messages, as.character(db_id))
        remove_feedback_from_db(effective_user_id, db_id)
        session$sendCustomMessage("updateFeedback", list(messageId = msg_id, action = "remove_like"))
        showToast(session, "Beğeni kaldırıldı.", "info")
      } else {
        values$liked_messages    <- union(values$liked_messages,    as.character(db_id))
        values$disliked_messages <- setdiff(values$disliked_messages, as.character(db_id))
        session$sendCustomMessage("updateFeedback", list(messageId = msg_id, action = "like"))
		if (!is.null(feedback_modal) && is.function(feedback_modal$open)) {
          feedback_modal$open(db_id, "like", on_cancel = function() {
            values$liked_messages <- setdiff(values$liked_messages, as.character(db_id))
            session$sendCustomMessage("updateFeedback", list(messageId = msg_id, action = "remove_like"))
          })
        }
      }
    } else {
      showToast(session, "Lütfen yanıt tamamlandıktan sonra beğenin.", "warning")
    }
  }, ignoreInit = TRUE)

  # Dislike
  shiny::observeEvent(input$dislike_message, {
    req(input$dislike_message)
    msg_id <- input$dislike_message
    if (.is_recent_duplicate("dislike", msg_id)) return()
    idx <- which(vapply(values$messages, function(m) identical(m$id, msg_id), logical(1)))
    if (!length(idx)) return()

    actual <- values$messages[[idx]]
    if (isTRUE(!is.null(actual$db_id)) && isTRUE(!is.na(actual$db_id))) {
      db_id <- as.integer(actual$db_id)
      if (db_id %in% as.integer(values$disliked_messages)) {
        effective_user_id <- resolve_current_user_id()
        values$disliked_messages <- setdiff(values$disliked_messages, as.character(db_id))
        remove_feedback_from_db(effective_user_id, db_id)
        session$sendCustomMessage("updateFeedback", list(messageId = msg_id, action = "remove_dislike"))
        showToast(session, "Geri bildirim kaldırıldı.", "info")
      } else {
        values$disliked_messages <- union(values$disliked_messages, as.character(db_id))
        values$liked_messages    <- setdiff(values$liked_messages,    as.character(db_id))
        session$sendCustomMessage("updateFeedback", list(messageId = msg_id, action = "dislike"))
		if (!is.null(feedback_modal) && is.function(feedback_modal$open)) {
          feedback_modal$open(db_id, "dislike", on_cancel = function() {
            values$disliked_messages <- setdiff(values$disliked_messages, as.character(db_id))
            session$sendCustomMessage("updateFeedback", list(messageId = msg_id, action = "remove_dislike"))
          })
        }
      }
    } else {
      showToast(session, "Lütfen yanıt tamamlandıktan sonra beğenmeyin.", "warning")
    }
  }, ignoreInit = TRUE)

  # Regenerate
  shiny::observeEvent(input$regenerate_message, {
    req(input$regenerate_message)
    msg_id <- input$regenerate_message
    idx <- which(vapply(values$messages, function(m) identical(m$id, msg_id), logical(1)))
    if (!length(idx) || idx <= 1) return()
    # Find the last user prompt before this message
    user_idx <- -1L
    for (i in seq(idx - 1L, 1L)) {
      if (identical(values$messages[[i]]$type, "user")) { user_idx <- i; break }
    }
    if (user_idx == -1L) return()
    user_prompt <- values$messages[[user_idx]]$content
    values$messages <- values$messages[-idx]
    send_message_fn(user_prompt)
    showToast(session, "Yanıt yeniden oluşturuldu.", "success")
  }, ignoreInit = TRUE)

  # Edit -> open modal
  shiny::observeEvent(input$edit_message_request, {
    req(input$edit_message_request)
    msg_id <- input$edit_message_request
    msg <- NULL
    for (m in values$messages) { if (identical(m$id, msg_id)) { msg <- m; break } }
    if (is.null(msg)) return()

    message_to_edit_id(msg_id)
    showModal(modalDialog(
      title = "Mesajı Düzenle",
      textAreaInput("edited_message_text", label = NULL, value = msg$content, width = "100%", rows = 6),
      footer = tagList(
        actionButton("save_edited_message", "Değişiklikleri Kaydet", class = "btn-modern btn-primary"),
        tags$button("İptal", class = "btn-modern btn-secondary", `data-dismiss` = "modal")
      ),
      easyClose = TRUE
    ))
  }, ignoreInit = TRUE)

  # Save edited
  shiny::observeEvent(input$save_edited_message, {
    req(message_to_edit_id(), input$edited_message_text)
    msg_id  <- message_to_edit_id()
    new_txt <- trimws(input$edited_message_text %||% "")
    removeModal()
    message_to_edit_id(NULL)

    if (!nzchar(new_txt)) return()

    # Stop any ongoing streaming before processing
    if (isTRUE(values$is_sending)) {
      stop_generation(TRUE)
      Sys.sleep(0.2)
    }
    reset_chat_state()

    shinyjs::delay(200, {
      idx <- which(vapply(values$messages, function(m) identical(m$id, msg_id), logical(1)))
      if (!length(idx)) return()
      # Remove from the edited one onwards (also remove UI for those)
      if (idx < length(values$messages)) {
        for (i in seq(length(values$messages), idx)) {
          removeUI(selector = paste0("#message_wrapper_", values$messages[[i]]$id), immediate = TRUE)
        }
      }
      values$messages <- values$messages[seq_len(idx - 1L)]
      send_message_fn(new_txt)
      showToast(session, "Mesaj düzenlendi ve yeniden gönderildi.", "success")
    })
  }, ignoreInit = TRUE)
}