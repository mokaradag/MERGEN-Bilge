# ==============================================================================
# File: tests/scripts/repair_mb_messages_mojibake.R
# Purpose: One-time repair for mojibake in MB_Messages user-visible fields.
#
# Default is DRY RUN.
# Apply with:
#   Sys.setenv(MERGEN_REPAIR_MOJIBAKE_APPLY = "TRUE")
# ==============================================================================

local({

repair_mb_messages_bool <- function(value, default = FALSE) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) return(default)

  norm <- tolower(trimws(as.character(value[1])))

  if (!nzchar(norm)) return(default)
  if (norm %in% c("true", "t", "1", "yes", "y")) return(TRUE)
  if (norm %in% c("false", "f", "0", "no", "n")) return(FALSE)

  default
}

repair_mb_messages_coalesce_text <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return("")
  }

  as.character(value[1])
}

repair_mb_messages_has_mojibake <- function(value) {
  text <- paste(enc2utf8(as.character(value)), collapse = "\n")

  if (!nzchar(text)) {
    return(FALSE)
  }

  mojibake_tokens <- c(
    "\u00C3",       # A-tilde marker
    "\u00C4",       # A-diaeresis marker
    "\u00C5",       # A-ring marker
    "\u00C2",       # stray A-circumflex marker
    "\uFFFD",       # replacement character
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

repair_mb_messages_preview <- function(x, n = 140L) {
  x <- repair_mb_messages_coalesce_text(x)
  x <- gsub("[\r\n]+", " ", x)
  substr(x, 1L, n)
}

Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false",
  MERGEN_SQL_LOADER_STRICT = "true"
)

source("app.R", encoding = "UTF-8")

required <- c(
  "get_connection",
  "release_connection",
  "normalize_db_visible_value",
  "normalize_db_params"
)

missing <- required[!vapply(
  required,
  function(nm) exists(nm, envir = globalenv(), mode = "function", inherits = TRUE),
  logical(1)
)]

if (length(missing) > 0L) {
  stop(
    sprintf("Missing function(s): %s", paste(missing, collapse = ", ")),
    call. = FALSE
  )
}

apply_changes <- repair_mb_messages_bool(
  Sys.getenv("MERGEN_REPAIR_MOJIBAKE_APPLY", "FALSE"),
  default = FALSE
)

limit <- suppressWarnings(as.integer(Sys.getenv("MERGEN_REPAIR_MOJIBAKE_TOP", "5000")))

if (is.na(limit) || limit <= 0L) {
  limit <- 5000L
}

cat(sprintf(
  "INFO: MB_Messages mojibake repair starting. Mode=%s, TOP=%d\n",
  if (isTRUE(apply_changes)) "APPLY" else "DRY_RUN",
  limit
))

conn_info <- NULL

tryCatch({
  conn_info <- get_connection()
  conn <- conn_info$conn

  # ASCII-safe: fetch recent rows, detect mojibake in R.
  # This avoids fragile SQL strings containing literal mojibake characters.
  query <- sprintf("
    SELECT TOP (%d)
      MessageID,
      ChatID,
      MessageContent,
      ReasoningContent,
      MessageTimestamp
    FROM MB_Messages
    ORDER BY MessageID DESC
  ", limit)

  rows <- DBI::dbGetQuery(conn, query)

  if (nrow(rows) == 0L) {
    cat("OK: MB_Messages has no rows to inspect.\n")
    return(invisible(TRUE))
  }

  candidate_idx <- vapply(seq_len(nrow(rows)), function(i) {
    repair_mb_messages_has_mojibake(rows$MessageContent[i]) ||
      repair_mb_messages_has_mojibake(rows$ReasoningContent[i])
  }, logical(1))

  rows <- rows[candidate_idx, , drop = FALSE]

  if (nrow(rows) == 0L) {
    cat("OK: No mojibake candidates found in inspected MB_Messages rows.\n")
    return(invisible(TRUE))
  }

  cat(sprintf("INFO: %d mojibake candidate row(s) found.\n", nrow(rows)))

  updates <- list()

  for (i in seq_len(nrow(rows))) {
    message_id <- rows$MessageID[i]

    old_content <- rows$MessageContent[i]
    old_reasoning <- rows$ReasoningContent[i]

    new_content <- old_content
    new_reasoning <- old_reasoning

    if (!is.na(old_content) && repair_mb_messages_has_mojibake(old_content)) {
      new_content <- normalize_db_visible_value(old_content)
    }

    if (!is.na(old_reasoning) && repair_mb_messages_has_mojibake(old_reasoning)) {
      new_reasoning <- normalize_db_visible_value(old_reasoning)
    }

    changed_content <- !identical(as.character(old_content), as.character(new_content))
    changed_reasoning <- !identical(as.character(old_reasoning), as.character(new_reasoning))

    if (isTRUE(changed_content) || isTRUE(changed_reasoning)) {
      updates[[length(updates) + 1L]] <- list(
        MessageID = message_id,
        ChatID = rows$ChatID[i],
        old_content = old_content,
        new_content = new_content,
        old_reasoning = old_reasoning,
        new_reasoning = new_reasoning,
        changed_content = changed_content,
        changed_reasoning = changed_reasoning
      )
    }
  }

  if (length(updates) == 0L) {
    cat("WARN: Mojibake candidates were found, but normalize_db_visible_value() produced no changes.\n")
    return(invisible(FALSE))
  }

  cat(sprintf("INFO: %d row(s) look repairable.\n", length(updates)))

  for (item in utils::head(updates, 10L)) {
    cat(sprintf(
      "PREVIEW MessageID=%s ChatID=%s\n  OLD: %s\n  NEW: %s\n",
      item$MessageID,
      item$ChatID,
      repair_mb_messages_preview(item$old_content),
      repair_mb_messages_preview(item$new_content)
    ))
  }

  if (!isTRUE(apply_changes)) {
    cat("DRY_RUN: No updates were written. Set MERGEN_REPAIR_MOJIBAKE_APPLY=TRUE to apply.\n")
    return(invisible(TRUE))
  }

  DBI::dbBegin(conn)
  committed <- FALSE

  tryCatch({
    for (item in updates) {
      DBI::dbExecute(
        conn,
        "
          UPDATE MB_Messages
          SET
            MessageContent = ?,
            ReasoningContent = ?
          WHERE MessageID = ?
        ",
        params = normalize_db_params(list(
          item$new_content,
          item$new_reasoning,
          as.integer(item$MessageID)
        ))
      )
    }

    DBI::dbCommit(conn)
    committed <- TRUE

    cat(sprintf("OK: %d MB_Messages row(s) repaired.\n", length(updates)))
    invisible(TRUE)
  }, error = function(e) {
    if (!isTRUE(committed)) {
      try(DBI::dbRollback(conn), silent = TRUE)
    }

    stop(e)
  })
}, finally = {
  release_connection(conn_info)
})

})