# ==============================================================================
# Dosya Yolu: tests/testthat/helper_e2e_file_context_harness.R
# Açıklama: Dosya Yönetimi, model bağlamı ve yenileme yarış durumları için
#           gerçek servis gerektirmeyen deterministik E2E benzeri test harness'i.
# ==============================================================================

.e2e_file_value <- function(x, name, default = NULL) {
  if (!is.list(x) || is.null(x[[name]])) {
    return(default)
  }

  x[[name]]
}

e2e_file_context_empty_table <- function() {
  columns <- c(
    "Dosya_Adi",
    "Boyut",
    "Tur",
    "Yukleme_Tarihi",
    "Islemler",
    "Model_Baglami"
  )

  stats::setNames(
    as.data.frame(
      replicate(length(columns), character(0), simplify = FALSE),
      stringsAsFactors = FALSE
    ),
    columns
  )
}

e2e_file_context_new_state <- function() {
  list(
    table = e2e_file_context_empty_table(),
    file_contents = list(),
    files_in_context = list(),
    parent_context = list(),
    messages = list(),
    toasts = character(0),
    events = character(0),
    last_error = NULL,
    last_upload = NULL,
    last_refresh_id = NULL,
    last_cleanup_plan = NULL,
    last_restore_stale_ids = character(0),
    ui_unchecked_ids = character(0),
    refresh_guard = fm_create_refresh_request_guard()
  )
}

e2e_file_context_make_file_info <- function(name,
                                            datapath = NULL,
                                            size = 128,
                                            type = "") {
  if (is.null(datapath) || !nzchar(datapath)) {
    ext <- tolower(tools::file_ext(name))
    if (!nzchar(ext)) {
      ext <- "txt"
    }

    datapath <- tempfile("e2e_file_context_", fileext = paste0(".", ext))
  }

  if (!file.exists(datapath)) {
    dir.create(dirname(datapath), recursive = TRUE, showWarnings = FALSE)
    writeBin(charToRaw("MERGEN test içeriği"), datapath)
  }

  list(
    name = enc2utf8(as.character(name)[1]),
    datapath = normalizePath(datapath, winslash = "/", mustWork = FALSE),
    size = as.numeric(size)[1],
    type = as.character(type)[1]
  )
}

e2e_file_context_upload <- function(state,
                                    file_info,
                                    generate_message = TRUE,
                                    summarization_mode = FALSE,
                                    file_id = NULL) {
  file_name <- enc2utf8(as.character(.e2e_file_value(file_info, "name", ""))[1])
  file_ext <- tolower(tools::file_ext(file_name))

  allowed_extensions <- fm_resolve_allowed_extensions(
    generate_message = generate_message,
    summarization_mode = summarization_mode
  )

  if (!nzchar(file_name) || !nzchar(file_ext) || !file_ext %in% allowed_extensions) {
    state$last_error <- "unsupported_extension"
    state$toasts <- c(
      state$toasts,
      sprintf("unsupported_extension:%s", file_name)
    )
    return(state)
  }

  if (is.null(file_id) || !nzchar(file_id)) {
    file_id <- sprintf("file_%03d", length(state$file_contents) + 1L)
  }

  file_entry <- list(
    id = file_id,
    name = file_name,
    datapath = as.character(.e2e_file_value(file_info, "datapath", ""))[1],
    persisted_path = as.character(.e2e_file_value(file_info, "datapath", ""))[1],
    size = as.numeric(.e2e_file_value(file_info, "size", 0))[1],
    type = as.character(.e2e_file_value(file_info, "type", ""))[1]
  )

  state$file_contents[[file_id]] <- file_entry
  state$last_upload <- file_entry
  state$last_error <- NULL

  new_row <- data.frame(
    Dosya_Adi = file_name,
    Boyut = as.character(file_entry$size),
    Tur = toupper(file_ext),
    Yukleme_Tarihi = "2026-01-01 00:00",
    Islemler = sprintf("actions:%s", file_id),
    Model_Baglami = sprintf("attach:%s", file_id),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  state$table <- rbind(state$table, new_row)

  if (isTRUE(generate_message)) {
    state$messages <- append(
      state$messages,
      list(list(
        type = "system",
        content = sprintf("%s yüklendi.", file_name),
        file_id = file_id
      ))
    )
  }

  state
}

e2e_file_context_attach <- function(state,
                                    file_id,
                                    checked = TRUE,
                                    mcp_enabled = FALSE,
                                    summarization_mode = FALSE) {
  info <- state$file_contents[[file_id]]

  if (is.null(info)) {
    state$last_error <- "missing_file"
    state$toasts <- c(state$toasts, sprintf("missing_file:%s", file_id))
    return(state)
  }

  file_name <- enc2utf8(info$name)
  file_ext <- tolower(tools::file_ext(file_name))

  if (!isTRUE(checked)) {
    state$files_in_context[[file_id]] <- NULL
    state$parent_context[[file_name]] <- NULL
    state$events <- c(state$events, sprintf("detached:%s", file_name))
    state$last_error <- NULL
    return(state)
  }

  if (isTRUE(summarization_mode) &&
      !file_ext %in% fm_summarization_allowed_extensions()) {
    state$last_error <- "summarization_extension"
    state$toasts <- c(
      state$toasts,
      sprintf("summarization_reject:%s", file_name)
    )
    return(state)
  }

  if (isTRUE(mcp_enabled) && !file_ext %in% c("xls", "xlsx")) {
    state$last_error <- "mcp_non_excel"
    state$toasts <- c(state$toasts, sprintf("mcp_reject:%s", file_name))
    return(state)
  }

  if (isTRUE(mcp_enabled)) {
    other_ids <- setdiff(names(state$files_in_context), file_id)

    if (length(other_ids) > 0L) {
      for (other_id in other_ids) {
        other_file <- state$file_contents[[other_id]]
        if (!is.null(other_file$name)) {
          state$parent_context[[other_file$name]] <- NULL
        }
      }

      state$files_in_context[other_ids] <- NULL
      state$ui_unchecked_ids <- unique(c(state$ui_unchecked_ids, other_ids))
      state$toasts <- c(state$toasts, "mcp_single_file_cleanup")
    }
  }

  state$files_in_context[[file_id]] <- TRUE
  state$parent_context[[file_name]] <- info
  state$events <- c(state$events, sprintf("attached:%s", file_name))
  state$last_error <- NULL

  state
}

e2e_file_context_enable_mcp <- function(state) {
  cleanup_plan <- fm_plan_mcp_context_cleanup(
    file_contents = state$file_contents,
    files_in_context = state$files_in_context
  )

  if (length(cleanup_plan$remove_ids) > 0L) {
    for (file_id in cleanup_plan$remove_ids) {
      info <- state$file_contents[[file_id]]
      if (!is.null(info$name)) {
        state$parent_context[[info$name]] <- NULL
      }

      state$files_in_context[[file_id]] <- NULL
    }

    state$ui_unchecked_ids <- unique(c(
      state$ui_unchecked_ids,
      cleanup_plan$remove_ids
    ))
  }

  state$last_cleanup_plan <- cleanup_plan
  state$events <- c(state$events, "mcp_enabled")

  state
}

e2e_file_context_refresh_start <- function(state,
                                           user_id,
                                           trigger = "manual",
                                           sso_enabled = FALSE,
                                           auth_ready = TRUE) {
  state$last_refresh_id <- NULL

  if (isTRUE(sso_enabled) && !isTRUE(auth_ready)) {
    state$events <- c(
      state$events,
      sprintf("refresh_skip:auth_not_ready:%s", trigger)
    )
    return(state)
  }

  if (!fm_valid_user_id(user_id)) {
    state$events <- c(
      state$events,
      sprintf("refresh_skip:invalid_user:%s", trigger)
    )
    return(state)
  }

  request_id <- state$refresh_guard$next_id()
  state$last_refresh_id <- request_id
  state$events <- c(
    state$events,
    sprintf("refresh_start:%s:%s", request_id, trigger)
  )

  state
}

e2e_file_context_refresh_apply <- function(state, request_id, rows) {
  if (!state$refresh_guard$is_latest(request_id)) {
    state$events <- c(
      state$events,
      sprintf("refresh_skip:stale:%s", request_id)
    )
    return(state)
  }

  if (is.null(rows) || !is.data.frame(rows) || nrow(rows) == 0L) {
    state$events <- c(
      state$events,
      sprintf("refresh_skip:empty:%s", request_id)
    )
    return(state)
  }

  previously_attached_names <- unique(vapply(
    names(state$files_in_context),
    function(file_id) {
      info <- state$file_contents[[file_id]]
      if (is.null(info$name)) "" else enc2utf8(info$name)
    },
    character(1)
  ))
  previously_attached_names <- previously_attached_names[nzchar(previously_attached_names)]

  state$table <- e2e_file_context_empty_table()
  state$file_contents <- list()
  state$files_in_context <- list()
  state$parent_context <- list()
  state$last_upload <- NULL

  for (i in seq_len(nrow(rows))) {
    file_info <- list(
      name = enc2utf8(as.character(rows$name[i])),
      datapath = as.character(rows$path[i]),
      size = as.numeric(rows$size[i]),
      type = as.character(rows$type[i])
    )

    state <- e2e_file_context_upload(
      state = state,
      file_info = file_info,
      generate_message = FALSE,
      summarization_mode = FALSE
    )
  }

  if (length(previously_attached_names) > 0L) {
    for (file_id in names(state$file_contents)) {
      info <- state$file_contents[[file_id]]
      if (info$name %in% previously_attached_names) {
        state <- e2e_file_context_attach(
          state = state,
          file_id = file_id,
          checked = TRUE
        )
      }
    }
  }

  state$events <- c(
    state$events,
    sprintf("refresh_apply:%s:%s", request_id, nrow(rows))
  )

  state
}

e2e_file_context_restore_client_state <- function(state, attached_ids) {
  attached_ids <- unique(as.character(attached_ids))
  attached_ids <- attached_ids[nzchar(attached_ids)]

  valid_ids <- intersect(attached_ids, names(state$file_contents))
  stale_ids <- setdiff(attached_ids, names(state$file_contents))

  state$files_in_context <- list()
  state$parent_context <- list()
  state$last_restore_stale_ids <- stale_ids

  for (file_id in valid_ids) {
    state <- e2e_file_context_attach(
      state = state,
      file_id = file_id,
      checked = TRUE
    )
  }

  state$events <- c(
    state$events,
    sprintf("client_restore:valid=%s:stale=%s", length(valid_ids), length(stale_ids))
  )

  state
}