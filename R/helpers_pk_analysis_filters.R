# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_filters.R
# Açıklama: AI filtre motoru için uyumluluk yüzeyi ve Faz 0 gözlem bağdaştırıcısı.
#           Karar veren v1 motoru helpers_pk_analysis_filters_base.R içinde
#           aynen korunur; bu dosya yalnızca gerçekten uygulanan/düşürülen
#           filtreleri ve toplulaştırma öncesi eşleşen satır sayısını kaydeder.
# ==============================================================================

.pk_filter_engine_path <- file.path("R", "helpers_pk_analysis_filters_base.R")
if (!file.exists(.pk_filter_engine_path)) {
  stop(sprintf("%s bulunamadı.", .pk_filter_engine_path), call. = FALSE)
}
source(.pk_filter_engine_path, encoding = "UTF-8", local = environment())
rm(.pk_filter_engine_path)

.pk_apply_smart_filters_engine <- apply_smart_filters

if (!exists(".pk_filter_observation_state", inherits = FALSE) ||
    !is.environment(.pk_filter_observation_state)) {
  .pk_filter_observation_state <- new.env(parent = emptyenv())
}

.pk_filter_observation_scalar <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  out <- as.character(x)[1]
  if (is.na(out)) "" else out
}

.pk_filter_observation_key <- function(request_id, query_id, query_name, question) {
  paste(
    .pk_filter_observation_scalar(request_id),
    .pk_filter_observation_scalar(query_id),
    .pk_filter_observation_scalar(query_name),
    .pk_filter_observation_scalar(question),
    sep = "\u001f"
  )
}

.pk_filter_observation_context <- function(user_prompt) {
  request_id <- NULL
  query_meta <- NULL
  session_obj <- NULL

  for (fr in rev(sys.frames())) {
    if (is.null(request_id) && exists("pk_request_id", envir = fr, inherits = FALSE)) {
      request_id <- get("pk_request_id", envir = fr, inherits = FALSE)
    }

    if (is.null(query_meta)) {
      for (nm in c("selected_query", "query")) {
        if (exists(nm, envir = fr, inherits = FALSE)) {
          candidate <- get(nm, envir = fr, inherits = FALSE)
          if (is.list(candidate)) {
            query_meta <- candidate
            break
          }
        }
      }
    }

    if (is.null(session_obj) && exists("session", envir = fr, inherits = FALSE)) {
      candidate_session <- get("session", envir = fr, inherits = FALSE)
      if (!is.null(candidate_session)) session_obj <- candidate_session
    }
  }

  if ((is.null(request_id) || !nzchar(.pk_filter_observation_scalar(request_id))) &&
      !is.null(session_obj) &&
      exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
    request_id <- tryCatch(
      pk_provenance_current_request_id(session_obj),
      error = function(e) NULL
    )
  }

  list(
    request_id = request_id,
    query_id = query_meta$id %||% NULL,
    query_name = query_meta$name %||% NULL,
    question = user_prompt
  )
}

.pk_filter_dropped <- function(filter, reason) {
  list(filter = filter %||% list(), reason = as.character(reason)[1])
}

.pk_filter_observation_probe <- function(data, filter_instructions) {
  dt <- data.table::as.data.table(data)
  filters <- filter_instructions$filters %||% list()
  applied <- list()
  dropped <- list()

  expression <- filter_instructions$filter_expression
  expression_applied <- FALSE

  if (!is.null(expression) && nzchar(as.character(expression)[1])) {
    expression <- as.character(expression)[1]
    expression_applied <- tryCatch({
      dt <- subset(dt, eval(parse(text = expression)))
      TRUE
    }, error = function(e) {
      dropped[[length(dropped) + 1L]] <<- .pk_filter_dropped(
        list(column = "filter_expression", value = expression, operation = "expression"),
        paste0("ifade uygulanamadı: ", conditionMessage(e))
      )
      FALSE
    })

    if (isTRUE(expression_applied)) {
      applied <- list(list(
        column = "filter_expression",
        value = expression,
        operation = "expression"
      ))
    }
  }

  if (!isTRUE(expression_applied) && length(filters) > 0L) {
    for (f in filters) {
      col <- .pk_filter_observation_scalar(f$column)
      val <- f$value
      op <- .pk_filter_observation_scalar(f$operation %||% "exact_match")
      if (!nzchar(op)) op <- "exact_match"

      if (!nzchar(col) || !(col %in% names(dt))) {
        dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(f, "sütun veri kümesinde bulunamadı")
        next
      }

      col_vals <- dt[[col]]
      val_str <- .pk_filter_observation_scalar(val)

      if (is.character(col_vals) || is.factor(col_vals)) {
        val_regex <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", val_str)
        col_vals_char <- as.character(col_vals)

        if (identical(op, "contains")) {
          dt <- dt[grepl(val_regex, col_vals_char, ignore.case = TRUE), ]
        } else {
          dt <- dt[grepl(paste0("^", val_regex, "$"), col_vals_char, ignore.case = TRUE), ]
        }
        applied[[length(applied) + 1L]] <- f
        next
      }

      if (is.numeric(col_vals)) {
        val_num <- suppressWarnings(as.numeric(val_str))
        if (is.na(val_num)) {
          dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(f, "değer sayısal biçime dönüştürülemedi")
          next
        }

        if (identical(op, "greater_than")) {
          dt <- dt[col_vals > val_num, ]
        } else if (identical(op, "less_than")) {
          dt <- dt[col_vals < val_num, ]
        } else {
          dt <- dt[col_vals == val_num, ]
        }
        applied[[length(applied) + 1L]] <- f
        next
      }

      dropped[[length(dropped) + 1L]] <- .pk_filter_dropped(f, "sütun türü filtreleme için desteklenmiyor")
    }
  }

  list(
    matched_rows = nrow(dt),
    applied_filters = applied,
    dropped_filters = dropped
  )
}

.pk_filter_observation_store <- function(context, observation) {
  key <- .pk_filter_observation_key(
    context$request_id,
    context$query_id,
    context$query_name,
    context$question
  )
  assign(key, observation, envir = .pk_filter_observation_state)
  invisible(observation)
}

pk_filter_observation_take <- function(info) {
  info <- if (is.list(info)) info else list()
  key <- .pk_filter_observation_key(
    info$request_id,
    info$query_id,
    info$query_name,
    info$question
  )

  if (!exists(key, envir = .pk_filter_observation_state, inherits = FALSE)) return(NULL)

  observation <- get(key, envir = .pk_filter_observation_state, inherits = FALSE)
  rm(list = key, envir = .pk_filter_observation_state)
  observation
}

apply_smart_filters <- function(data, filter_instructions, user_prompt) {
  result <- .pk_apply_smart_filters_engine(data, filter_instructions, user_prompt)

  observation <- tryCatch(
    .pk_filter_observation_probe(data, filter_instructions),
    error = function(e) NULL
  )

  if (!is.null(observation)) {
    context <- .pk_filter_observation_context(user_prompt)
    .pk_filter_observation_store(context, observation)
  }

  result
}
