# ==============================================================================
# File: tests/scripts/repair_mb_messages_mojibake.R
# Purpose: One-time repair for mojibake in MB_Messages user-visible fields.
#
# Default is DRY RUN.
#
# Dry run:
#   Sys.setenv(MERGEN_REPAIR_MOJIBAKE_APPLY = "FALSE")
#   source("tests/scripts/repair_mb_messages_mojibake.R", encoding = "UTF-8")
#
# Apply:
#   Sys.setenv(MERGEN_REPAIR_MOJIBAKE_APPLY = "TRUE")
#   source("tests/scripts/repair_mb_messages_mojibake.R", encoding = "UTF-8")
#
# By default this scans ALL rows.
# Optional:
#   MERGEN_REPAIR_MOJIBAKE_BATCH_SIZE = "1000"
#   MERGEN_REPAIR_MOJIBAKE_MAX_ROWS   = "0"     # 0 means all rows
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

repair_mb_messages_int <- function(value, default = 0L) {
  out <- suppressWarnings(as.integer(value[1]))

  if (is.na(out)) {
    return(as.integer(default))
  }

  as.integer(out)
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
    "\u00C3",       # Ã marker
    "\u00C4",       # Ä marker
    "\u00C5",       # Å marker
    "\u00C2",       # Â marker
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

repair_mb_messages_preview <- function(x, n = 160L) {
  x <- repair_mb_messages_coalesce_text(x)
  x <- gsub("[\r\n]+", " ", x)
  substr(x, 1L, n)
}

repair_mb_messages_replace_common_turkish_mojibake <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(value)
  }

  out <- enc2utf8(as.character(value[1]))

  replacements <- c(
    "\u00C4\u00B0" = "\u0130", # Ä° -> İ
    "\u00C4\u00B1" = "\u0131", # Ä± -> ı
    "\u00C3\u00BC" = "\u00FC", # Ã¼ -> ü
    "\u00C3\u0153" = "\u00DC", # Ãœ -> Ü
    "\u00C3\u00B6" = "\u00F6", # Ã¶ -> ö
    "\u00C3\u2013" = "\u00D6", # Ã– -> Ö
    "\u00C3\u00A7" = "\u00E7", # Ã§ -> ç
    "\u00C3\u2021" = "\u00C7", # Ã‡ -> Ç
    "\u00C4\u0178" = "\u011F", # ÄŸ -> ğ
    "\u00C4\u017E" = "\u011E", # Äž -> Ğ
    "\u00C5\u0178" = "\u015F", # ÅŸ -> ş
    "\u00C5\u017E" = "\u015E", # Åž -> Ş

    # Some VM/console/ODBC paths surface the second byte marker through Â.
    "\u00C2\u00B0" = "\u0130", # Â° -> İ
    "\u00C2\u00B1" = "\u0131"  # Â± -> ı
  )

  for (bad in names(replacements)) {
    out <- gsub(bad, replacements[[bad]], out, fixed = TRUE)
  }

  out
}

repair_mb_messages_strip_or_repair_symbol_mojibake <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(value)
  }

  out <- enc2utf8(as.character(value[1]))

  # Common UTF-8 emoji/symbol bytes misread through Windows-1254/1252.
  # When the byte sequence is incomplete after DB roundtrip, reliable recovery
  # is not always possible; remove only the corrupt prefix fragments.
  replacements <- c(
    "\u011F\u0178\u201D\u008D" = "\U0001F50D",
    "\u011F\u0178\u201D\u017D" = "\U0001F50E",
    "\u011F\u0178\u201C\u008C" = "\U0001F4CC",
    "\u011F\u0178\u201C\u009D" = "\U0001F4DD",
    "\u011F\u0178\u2019\u00A1" = "\U0001F4A1",
    "\u011F\u0178\u0161\u20AC" = "\U0001F680",
    "\u011F\u0178\u017D\u00AF" = "\U0001F3AF",
    "\u011F\u0178\u2018\u008D" = "\U0001F44D",
    "\u00E2\u0153\u2026" = "\u2705",
    "\u00E2\u009D\u0152" = "\u274C",
    "\u00E2\u0161\u00A0" = "\u26A0",
    "\u00E2\u20AC\u201D" = "\u2014",
    "\u00E2\u20AC\u201C" = "\u2013",
    "\u00E2\u20AC\u2122" = "\u2019",
    "\u00E2\u20AC\u0153" = "\u201C",
    "\u00E2\u20AC\u009D" = "\u201D"
  )

  for (bad in names(replacements)) {
    out <- gsub(bad, replacements[[bad]], out, fixed = TRUE)
  }

  # If incomplete emoji fragments remain, remove only the broken prefix cluster.
  # This prevents DB verification from failing forever on unrecoverable partials.
  out <- gsub("\u011F\u0178[\u0080-\uFFFF]{0,4}", "", out, perl = TRUE)
  out <- gsub("\u00F0\u0178[\u0080-\uFFFF]{0,4}", "", out, perl = TRUE)
  out <- gsub("\u00E2[\u0080-\uFFFF]{1,3}", "", out, perl = TRUE)

  # Clean spacing caused by removed corrupt emoji prefixes.
  out <- gsub("[[:space:]]{2,}", " ", out, perl = TRUE)
  trimws(out)
}

repair_mb_messages_repair_visible_text <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return(value)
  }

  original <- enc2utf8(as.character(value[1]))

  candidate_1 <- tryCatch(
    normalize_db_visible_value(original),
    error = function(e) original
  )

  candidate_2 <- tryCatch(
    repair_text_mojibake(original, max_passes = 4L),
    error = function(e) original
  )

  candidate_3 <- tryCatch(
    repair_mb_messages_replace_common_turkish_mojibake(original),
    error = function(e) original
  )

  candidate_4 <- tryCatch(
    repair_mb_messages_replace_common_turkish_mojibake(candidate_1),
    error = function(e) candidate_1
  )

  candidate_5 <- tryCatch(
    repair_mb_messages_strip_or_repair_symbol_mojibake(candidate_4),
    error = function(e) candidate_4
  )

  candidate_6 <- tryCatch(
    repair_mb_messages_strip_or_repair_symbol_mojibake(candidate_3),
    error = function(e) candidate_3
  )

  candidates <- unique(c(
    original,
    candidate_1,
    candidate_2,
    candidate_3,
    candidate_4,
    candidate_5,
    candidate_6
  ))

  bad <- vapply(candidates, repair_mb_messages_has_mojibake, logical(1))

  # Prefer the first candidate that no longer has mojibake markers.
  if (any(!bad)) {
    return(candidates[which(!bad)[1]])
  }

  # Otherwise prefer the last changed candidate, because it likely repaired
  # Turkish letters even if some unrecoverable emoji marker remains.
  changed <- candidates[candidates != original]

  if (length(changed) > 0L) {
    return(changed[length(changed)])
  }

  original
}

repair_mb_messages_sql_unicode_expr <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) {
    return("NULL")
  }

  value <- enc2utf8(as.character(value[1]))

  if (!nzchar(value)) {
    return("N''")
  }

  codepoints <- utf8ToInt(value)

  if (length(codepoints) == 0L) {
    return("N''")
  }

  flush_ascii <- function(buffer) {
    if (!length(buffer)) return(character(0))
    txt <- intToUtf8(buffer)
    txt <- gsub("'", "''", txt, fixed = TRUE)
    paste0("N'", txt, "'")
  }

  parts <- character(0)
  ascii_buffer <- integer(0)

  append_nchar <- function(cp) {
    if (cp <= 0xFFFFL) {
      return(sprintf("NCHAR(%d)", cp))
    }

    # UTF-16 surrogate pair for supplementary-plane code points.
    cp2 <- cp - 0x10000L
    high <- 0xD800L + (cp2 %/% 0x400L)
    low <- 0xDC00L + (cp2 %% 0x400L)

    sprintf("NCHAR(%d)+NCHAR(%d)", high, low)
  }

  for (cp in codepoints) {
    # Keep printable ASCII as compact N'...' chunks.
    # Use NCHAR for apostrophe and all non-ASCII/control characters.
    if (cp >= 32L && cp <= 126L && cp != 39L) {
      ascii_buffer <- c(ascii_buffer, cp)
    } else {
      if (length(ascii_buffer)) {
        parts <- c(parts, flush_ascii(ascii_buffer))
        ascii_buffer <- integer(0)
      }

      parts <- c(parts, append_nchar(cp))
    }
  }

  if (length(ascii_buffer)) {
    parts <- c(parts, flush_ascii(ascii_buffer))
  }

  if (!length(parts)) {
    return("N''")
  }

  paste(parts, collapse = "+")
}

repair_mb_messages_safe_disconnect <- function(conn) {
  if (is.null(conn)) return(invisible(NULL))

  tryCatch({
    if (DBI::dbIsValid(conn)) {
      DBI::dbDisconnect(conn)
    }
  }, error = function(e) {
    invisible(NULL)
  })

  invisible(NULL)
}

repair_mb_messages_sql_id_list <- function(ids) {
  ids <- suppressWarnings(as.integer(ids))
  ids <- ids[!is.na(ids)]

  if (length(ids) == 0L) {
    return("NULL")
  }

  paste(ids, collapse = ",")
}

repair_mb_messages_verify_rows <- function(conn, ids, has_reasoning_content) {
  id_sql <- repair_mb_messages_sql_id_list(ids)

  reason_select <- if (isTRUE(has_reasoning_content)) {
    "ReasoningContent"
  } else {
    "CAST(NULL AS NVARCHAR(MAX)) AS ReasoningContent"
  }

  verify_sql <- paste0(
    "
      SELECT
        MessageID,
        ChatID,
        MessageContent,
        ",
    reason_select,
    "
      FROM MB_Messages
      WHERE MessageID IN (",
    id_sql,
    ")
      ORDER BY MessageID ASC
    "
  )

  verify_rows <- DBI::dbGetQuery(conn, verify_sql)

  if (nrow(verify_rows) == 0L) {
    return(data.frame())
  }

  still_bad <- vapply(seq_len(nrow(verify_rows)), function(i) {
    repair_mb_messages_has_mojibake(verify_rows$MessageContent[i]) ||
      repair_mb_messages_has_mojibake(verify_rows$ReasoningContent[i])
  }, logical(1))

  verify_rows[still_bad, , drop = FALSE]
}

Sys.setenv(
  MERGEN_DISABLE_FUTURES = "true",
  MERGEN_RUN_APP = "false",
  MERGEN_SQL_LOADER_STRICT = "true"
)

legacy_top <- Sys.getenv("MERGEN_REPAIR_MOJIBAKE_TOP", unset = "")

if (nzchar(legacy_top)) {
  cat(sprintf(
    "INFO: MERGEN_REPAIR_MOJIBAKE_TOP=%s detected but ignored as a total limit. This script scans all rows by default.\n",
    legacy_top
  ))
}

source("app.R", encoding = "UTF-8")

required <- c(
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

batch_size <- repair_mb_messages_int(
  Sys.getenv("MERGEN_REPAIR_MOJIBAKE_BATCH_SIZE", "1000"),
  default = 1000L
)

if (batch_size <= 0L) {
  batch_size <- 1000L
}

max_rows <- repair_mb_messages_int(
  Sys.getenv("MERGEN_REPAIR_MOJIBAKE_MAX_ROWS", "0"),
  default = 0L
)

if (max_rows < 0L) {
  max_rows <- 0L
}

cat(sprintf(
  "INFO: MB_Messages mojibake repair starting. Mode=%s, BATCH_SIZE=%d, MAX_ROWS=%s\n",
  if (isTRUE(apply_changes)) "APPLY" else "DRY_RUN",
  batch_size,
  if (max_rows == 0L) "ALL" else as.character(max_rows)
))

conn <- NULL

tryCatch({
  if (exists("worker_db_connect", envir = globalenv(), mode = "function", inherits = TRUE)) {
    conn <- worker_db_connect()
    cat("INFO: Direct worker_db_connect() connection opened.\n")
  } else if (exists("get_connection", envir = globalenv(), mode = "function", inherits = TRUE)) {
    conn_info <- get_connection()
    conn <- conn_info$conn
    cat("WARN: worker_db_connect() not found; using get_connection().\n")
  } else {
    stop("No DB connection helper found.", call. = FALSE)
  }

  db_identity <- tryCatch({
    DBI::dbGetQuery(
      conn,
      "SELECT DB_NAME() AS database_name, @@SERVERNAME AS server_name"
    )
  }, error = function(e) {
    data.frame(database_name = NA_character_, server_name = NA_character_)
  })

  cat(sprintf(
    "INFO: Connected database=%s, server=%s\n",
    as.character(db_identity$database_name[1]),
    as.character(db_identity$server_name[1])
  ))

  columns <- DBI::dbGetQuery(
    conn,
    "
      SELECT COLUMN_NAME
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_NAME = 'MB_Messages'
    "
  )

  has_reasoning_content <- "ReasoningContent" %in% as.character(columns$COLUMN_NAME)

  if (!isTRUE(has_reasoning_content)) {
    cat("WARN: MB_Messages.ReasoningContent not found; only MessageContent will be repaired.\n")
  }

  total_rows <- tryCatch({
    DBI::dbGetQuery(conn, "SELECT COUNT_BIG(*) AS n FROM MB_Messages")$n[1]
  }, error = function(e) NA)

  cat(sprintf("INFO: MB_Messages total rows reported by DB: %s\n", as.character(total_rows)))

  last_id <- 0L
  scanned_rows <- 0L
  candidate_rows <- 0L
  repairable_rows <- 0L
  updated_rows <- 0L
  changed_content_count <- 0L
  changed_reasoning_count <- 0L
  preview_printed <- 0L
  preview_limit <- 25L
  batch_no <- 0L
  verification_failures <- list()

  repeat {
    remaining_limit <- if (max_rows > 0L) {
      max_rows - scanned_rows
    } else {
      batch_size
    }

    if (max_rows > 0L && remaining_limit <= 0L) {
      break
    }

    current_batch_size <- if (max_rows > 0L) {
      min(batch_size, remaining_limit)
    } else {
      batch_size
    }

    reason_select <- if (isTRUE(has_reasoning_content)) {
      "ReasoningContent"
    } else {
      "CAST(NULL AS NVARCHAR(MAX)) AS ReasoningContent"
    }

    query <- sprintf(
      "
        SELECT TOP (%d)
          MessageID,
          ChatID,
          MessageContent,
          %s,
          MessageTimestamp
        FROM MB_Messages
        WHERE MessageID > ?
        ORDER BY MessageID ASC
      ",
      current_batch_size,
      reason_select
    )

    rows <- DBI::dbGetQuery(conn, query, params = list(as.integer(last_id)))

    if (nrow(rows) == 0L) {
      break
    }

    batch_no <- batch_no + 1L
    scanned_rows <- scanned_rows + nrow(rows)
    last_id <- max(as.integer(rows$MessageID), na.rm = TRUE)

    candidate_idx <- vapply(seq_len(nrow(rows)), function(i) {
      repair_mb_messages_has_mojibake(rows$MessageContent[i]) ||
        repair_mb_messages_has_mojibake(rows$ReasoningContent[i])
    }, logical(1))

    candidates <- rows[candidate_idx, , drop = FALSE]
    candidate_rows <- candidate_rows + nrow(candidates)

    if (nrow(candidates) == 0L) {
      if (batch_no %% 10L == 0L) {
        cat(sprintf(
          "INFO: scanned=%d, candidates=%d, repairable=%d, updated=%d, last_id=%d\n",
          scanned_rows,
          candidate_rows,
          repairable_rows,
          updated_rows,
          last_id
        ))
      }
      next
    }

    updates <- list()

    for (i in seq_len(nrow(candidates))) {
      old_content <- candidates$MessageContent[i]
      old_reasoning <- candidates$ReasoningContent[i]

      new_content <- old_content
      new_reasoning <- old_reasoning

      if (!is.na(old_content) && repair_mb_messages_has_mojibake(old_content)) {
        new_content <- repair_mb_messages_repair_visible_text(old_content)
      }

      if (!is.na(old_reasoning) && repair_mb_messages_has_mojibake(old_reasoning)) {
        new_reasoning <- repair_mb_messages_repair_visible_text(old_reasoning)
      }

      changed_content <- !identical(as.character(old_content), as.character(new_content))
      changed_reasoning <- !identical(as.character(old_reasoning), as.character(new_reasoning))

      if (isTRUE(changed_content) || isTRUE(changed_reasoning)) {
        updates[[length(updates) + 1L]] <- list(
          MessageID = as.integer(candidates$MessageID[i]),
          ChatID = candidates$ChatID[i],
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
	  cat(sprintf(
		"WARN: batch=%d has %d mojibake candidate(s), but repair produced no changed values. First candidate MessageID=%s Preview=%s\n",
		batch_no,
		nrow(candidates),
		as.character(candidates$MessageID[1]),
		repair_mb_messages_preview(candidates$MessageContent[1])
	  ))
	  next
	}

    repairable_rows <- repairable_rows + length(updates)

    for (item in updates) {
      if (preview_printed < preview_limit) {
        cat(sprintf(
          "PREVIEW MessageID=%s ChatID=%s\n  OLD: %s\n  NEW: %s\n",
          item$MessageID,
          item$ChatID,
          repair_mb_messages_preview(item$old_content),
          repair_mb_messages_preview(item$new_content)
        ))
        preview_printed <- preview_printed + 1L
      }
    }

    if (!isTRUE(apply_changes)) {
      next
    }

    DBI::dbBegin(conn)
    committed <- FALSE

    tryCatch({
		for (item in updates) {
		  message_id_sql <- as.integer(item$MessageID)
		  content_expr <- repair_mb_messages_sql_unicode_expr(item$new_content)

		  if (isTRUE(has_reasoning_content)) {
			reasoning_expr <- repair_mb_messages_sql_unicode_expr(item$new_reasoning)

			update_sql <- sprintf(
			  "
				UPDATE MB_Messages
				SET
				  MessageContent = %s,
				  ReasoningContent = %s
				WHERE MessageID = %d
			  ",
			  content_expr,
			  reasoning_expr,
			  message_id_sql
			)
		  } else {
			update_sql <- sprintf(
			  "
				UPDATE MB_Messages
				SET MessageContent = %s
				WHERE MessageID = %d
			  ",
			  content_expr,
			  message_id_sql
			)
		  }

		  affected <- DBI::dbExecute(conn, update_sql)

        if (!identical(as.integer(affected), 1L)) {
          warning(sprintf(
            "MessageID=%s update affected %s rows.",
            item$MessageID,
            as.character(affected)
          ), call. = FALSE)
        }

        updated_rows <- updated_rows + as.integer(affected)

        if (isTRUE(item$changed_content)) {
          changed_content_count <- changed_content_count + 1L
        }

        if (isTRUE(item$changed_reasoning)) {
          changed_reasoning_count <- changed_reasoning_count + 1L
        }
      }

      DBI::dbCommit(conn)
      committed <- TRUE
    }, error = function(e) {
      if (!isTRUE(committed)) {
        try(DBI::dbRollback(conn), silent = TRUE)
      }

      stop(e)
    })

    verify_bad <- repair_mb_messages_verify_rows(
      conn,
      vapply(updates, function(item) item$MessageID, integer(1)),
      has_reasoning_content = has_reasoning_content
    )

    if (nrow(verify_bad) > 0L) {
      verification_failures[[length(verification_failures) + 1L]] <- verify_bad

      cat(sprintf(
        "ERROR: Verification still sees mojibake after update. First bad MessageID=%s\n",
        as.character(verify_bad$MessageID[1])
      ))
    }

    cat(sprintf(
      "INFO: batch=%d scanned=%d candidates=%d repairable=%d updated=%d last_id=%d\n",
      batch_no,
      scanned_rows,
      candidate_rows,
      repairable_rows,
      updated_rows,
      last_id
    ))
  }

  cat("INFO: MB_Messages mojibake repair summary:\n")
  cat(sprintf("  scanned_rows=%d\n", scanned_rows))
  cat(sprintf("  candidate_rows=%d\n", candidate_rows))
  cat(sprintf("  repairable_rows=%d\n", repairable_rows))
  cat(sprintf("  updated_rows=%d\n", updated_rows))
  cat(sprintf("  changed_content_count=%d\n", changed_content_count))
  cat(sprintf("  changed_reasoning_count=%d\n", changed_reasoning_count))

  if (!isTRUE(apply_changes)) {
    cat("DRY_RUN: No updates were written. Set MERGEN_REPAIR_MOJIBAKE_APPLY=TRUE to apply.\n")
    return(invisible(TRUE))
  }

	if (length(verification_failures) > 0L) {
	  all_bad <- do.call(rbind, verification_failures)

	  preview <- paste(
		utils::head(
		  paste0(
			"MessageID=", all_bad$MessageID,
			", Preview=", substr(all_bad$MessageContent, 1, 120)
		  ),
		  10L
		),
		collapse = " | "
	  )

	  stop(sprintf(
		"Repair wrote updates, but verification still found mojibake in %d row(s). First bad rows: %s",
		nrow(all_bad),
		preview
	  ), call. = FALSE)
	}

  final_check_query <- "
    SELECT TOP (25)
      MessageID,
      ChatID,
      MessageContent,
      ReasoningContent
    FROM MB_Messages
    ORDER BY MessageID DESC
  "

  final_rows <- DBI::dbGetQuery(conn, final_check_query)

  final_bad <- vapply(seq_len(nrow(final_rows)), function(i) {
    repair_mb_messages_has_mojibake(final_rows$MessageContent[i]) ||
      repair_mb_messages_has_mojibake(final_rows$ReasoningContent[i])
  }, logical(1))

  if (any(final_bad)) {
    bad <- final_rows[final_bad, , drop = FALSE]

    stop(sprintf(
      "Recent-row verification failed after repair. First bad MessageID(s): %s",
      paste(utils::head(bad$MessageID, 20L), collapse = ", ")
    ), call. = FALSE)
  }

  cat("OK: MB_Messages mojibake repair completed and verified for updated rows.\n")
  invisible(TRUE)
}, finally = {
  repair_mb_messages_safe_disconnect(conn)
})

})