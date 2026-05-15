# ==============================================================================
# Dosya Yolu: tests/scripts/repair_mb_messages_mojibake.R
# Açıklama: MB_Messages içindeki kullanıcıya görünen mojibake kayıtlarını
#           normalize_db_visible_value() ile onaran tek-seferlik bakım script'i.
#
# Varsayılan DRY RUN'dır. Gerçek güncelleme için:
#   Sys.setenv(MERGEN_REPAIR_MOJIBAKE_APPLY = "TRUE")
# ==============================================================================

repair_mb_messages_bool <- function(value, default = FALSE) {
  if (is.null(value) || length(value) == 0L || is.na(value[1])) return(default)
  norm <- tolower(trimws(as.character(value[1])))
  if (!nzchar(norm)) return(default)
  if (norm %in% c("true", "t", "1", "yes", "y")) return(TRUE)
  if (norm %in% c("false", "f", "0", "no", "n")) return(FALSE)
  default
}

repair_mb_messages_has_mojibake <- function(value) {
  text <- paste(enc2utf8(as.character(value %||% "")), collapse = "\n")

  mojibake_tokens <- c(
    "Ã§", "Ä±", "Ã¶", "ÅŸ", "ÄŸ", "Ã¼",
    "Ã‡", "Ä°", "Ã–", "Åž", "Ãœ",
    "TÃ¼rkiye", "NasÄ±l", "yardÄ±mcÄ±", "baÅŸkent",
    "teÅŸekkÃ¼r", "AÃ§", "Ã‡", "Å"
  )

  any(vapply(
    mojibake_tokens,
    function(token) grepl(token, text, fixed = TRUE),
    logical(1)
  ))
}

repair_mb_messages_preview <- function(x, n = 140L) {
  x <- as.character(x %||% "")[1]
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
    sprintf("Eksik fonksiyon(lar): %s", paste(missing, collapse = ", ")),
    call. = FALSE
  )
}

apply_changes <- repair_mb_messages_bool(
  Sys.getenv("MERGEN_REPAIR_MOJIBAKE_APPLY", "FALSE"),
  default = FALSE
)

limit <- suppressWarnings(as.integer(Sys.getenv("MERGEN_REPAIR_MOJIBAKE_TOP", "5000")))
if (is.na(limit) || limit <= 0L) limit <- 5000L

cat(sprintf(
  "INFO: MB_Messages mojibake repair başlıyor. Mode=%s, TOP=%d\n",
  if (isTRUE(apply_changes)) "APPLY" else "DRY_RUN",
  limit
))

conn_info <- NULL

tryCatch({
  conn_info <- get_connection()
  conn <- conn_info$conn

  query <- sprintf("
    SELECT TOP (%d)
      MessageID,
      ChatID,
      MessageContent,
      ReasoningContent,
      MessageTimestamp
    FROM MB_Messages
    WHERE
      MessageContent LIKE N'%%Ã%%'
      OR MessageContent LIKE N'%%Ä%%'
      OR MessageContent LIKE N'%%Å%%'
      OR MessageContent LIKE N'%%Â%%'
      OR MessageContent LIKE N'%%�%%'
      OR ReasoningContent LIKE N'%%Ã%%'
      OR ReasoningContent LIKE N'%%Ä%%'
      OR ReasoningContent LIKE N'%%Å%%'
      OR ReasoningContent LIKE N'%%Â%%'
      OR ReasoningContent LIKE N'%%�%%'
    ORDER BY MessageID DESC
  ", limit)

  rows <- DBI::dbGetQuery(conn, query)

  if (nrow(rows) == 0L) {
    cat("OK: MB_Messages içinde mojibake adayı bulunmadı.\n")
    quit(save = "no", status = 0)
  }

  cat(sprintf("INFO: %d mojibake adayı bulundu.\n", nrow(rows)))

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
    cat("WARN: Mojibake adayı bulundu ama normalize_db_visible_value() değişiklik üretmedi.\n")
    quit(save = "no", status = 1)
  }

  cat(sprintf("INFO: %d kayıt onarılabilir görünüyor.\n", length(updates)))

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
    cat("DRY_RUN: Güncelleme yapılmadı. Gerçek uygulama için MERGEN_REPAIR_MOJIBAKE_APPLY=TRUE ayarlayın.\n")
    quit(save = "no", status = 0)
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

    cat(sprintf("OK: %d MB_Messages kaydı onarıldı.\n", length(updates)))
  }, error = function(e) {
    if (!isTRUE(committed)) {
      try(DBI::dbRollback(conn), silent = TRUE)
    }
    stop(e)
  })
}, finally = {
  release_connection(conn_info)
})