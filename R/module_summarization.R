# R/module_summarization.R
# Dosya özetleme modülü - Tek veya çoklu belgeleri kapsamlı şekilde özetler

safe_source("R/helpers_summarization_prompts.R", encoding = "UTF-8")

prepare_summarization_request <- function(
  file_list,
  session,
  settings,
  max_chars_per_file = 120000,
  detail_level = "standard",
  focus_mode = "general"
) {
  prep_start_time <- Sys.time()

  log_info("[SUMMARIZATION PERF] Hazırlık başladı - giriş sayısı: {length(file_list)}")

  user_query <- NULL
  if (!is.null(file_list$user_query)) {
    user_query <- file_list$user_query
    file_list$user_query <- NULL
    log_info("[SUMMARIZATION] Kullanıcı sorgusu alındı: {user_query}")
  }

  if (length(file_list) == 0) {
    return(list(
      success = FALSE,
      message = "Özetlenecek dosya bulunamadı. Lütfen Dosya Yönetimi sayfasından 'Model Bağlamı' seçeneği işaretli dosyaları ekleyin."
    ))
  }

  file_contents <- list()
  total_chars <- 0
  read_errors <- character(0)

  session_registry <- session$userData$current_session_files %||% list()

  file_manager_data <- session$userData$file_manager_data
  fm_files <- tryCatch({
    if (!is.null(file_manager_data) && is.function(file_manager_data$file_contents)) {
      file_manager_data$file_contents()
    } else {
      NULL
    }
  }, error = function(e) NULL)

  fm_by_name <- list()
  if (!is.null(fm_files) && length(fm_files) > 0) {
    for (fid in names(fm_files)) {
      fm_obj <- fm_files[[fid]]
      nm <- fm_obj$name %||% NULL
      if (!is.null(nm) && nzchar(nm) && is.null(fm_by_name[[nm]])) {
        fm_by_name[[nm]] <- fm_obj
      }
    }
  }

  pick_existing_path <- function(candidates) {
    candidates <- candidates[!vapply(candidates, function(x) {
      is.null(x) || !nzchar(as.character(x)[1])
    }, logical(1))]

    if (!length(candidates)) {
      return(NULL)
    }

    for (cand in candidates) {
      path_value <- as.character(cand)[1]
      exists_ok <- tryCatch(path_exists_relaxed(path_value), error = function(e) FALSE)
      if (!isTRUE(exists_ok)) {
        exists_ok <- file.exists(path_value)
      }
      if (isTRUE(exists_ok)) {
        return(path_value)
      }
    }

    NULL
  }

  for (fname in names(file_list)) {
    fobj <- file_list[[fname]]
    if (!is.list(fobj)) next

    fpath <- pick_existing_path(list(
      fobj$persisted_path,
      fobj$datapath,
      fobj$path,
      fobj$source_path
    ))

    if (is.null(fpath) && !is.null(session_registry[[fname]])) {
      reg_obj <- session_registry[[fname]]
      fpath <- pick_existing_path(list(
        reg_obj$persisted_path,
        reg_obj$datapath,
        reg_obj$path
      ))
      if (!is.null(fpath)) {
        log_info("[SUMMARIZATION] session registry'den yol bulundu: {fpath}")
      }
    }

    if (is.null(fpath) && !is.null(fm_by_name[[fname]])) {
      fm_obj <- fm_by_name[[fname]]
      fpath <- pick_existing_path(list(
        fm_obj$persisted_path,
        fm_obj$datapath,
        fm_obj$path
      ))
      if (!is.null(fpath)) {
        log_info("[SUMMARIZATION] file_manager'dan yol bulundu: {fpath}")
      }
    }

    if (is.null(fpath)) {
      user_id <- session$userData$user_id %||% session$userData$system_username %||% NULL
      if (!is.null(user_id)) {
		resolved <- tryCatch(
		  resolve_uploaded_file(
			fname,
			user_id = user_id
		  ),
		  error = function(e) NULL
		)

		if (!is.null(resolved) && nzchar(resolved)) {
		  exists_ok <- tryCatch(path_exists_relaxed(resolved), error = function(e) FALSE)
		  if (!isTRUE(exists_ok)) exists_ok <- file.exists(resolved)

		  if (isTRUE(exists_ok)) {
			fpath <- resolved
			log_info("[SUMMARIZATION] resolve_uploaded_file ile yol bulundu: {resolved}")
		  }
		}
      }
    }

    fpath_exists <- if (!is.null(fpath) && nzchar(fpath)) {
      tryCatch(path_exists_relaxed(fpath), error = function(e) file.exists(fpath))
    } else FALSE

    if (!isTRUE(fpath_exists)) {
      err_msg <- paste("Dosya yolu bulunamadı:", fname)
      log_error("[SUMMARIZATION] {err_msg}")
      read_errors <- c(read_errors, err_msg)
      next
    }

    fpath_norm <- tryCatch(
      normalizePath(fpath, winslash = "/", mustWork = TRUE),
      error = function(e) NULL
    )
    if (!is.null(fpath_norm)) fpath <- fpath_norm

    log_info("[SUMMARIZATION] Dosya okunuyor: {fname} | Yol: {fpath}")

    raw_text <- tryCatch(
      {
        content <- readFileContentToString(list(
          name = fname,
          datapath = fpath,
          size = file.info(fpath)$size
        ))

        if (is.null(content) || !is.character(content) || length(content) == 0 || !nzchar(content[1])) {
          stop("Dosya içeriği boş veya okunamadı")
        }

        content
      },
      error = function(e) {
        err_msg <- paste("Dosya okuma hatası (", fname, "):", conditionMessage(e))
        log_error("[SUMMARIZATION] {err_msg}")
        read_errors <<- c(read_errors, err_msg)
        NULL
      }
    )

    if (is.null(raw_text)) next

    raw_text <- as.character(raw_text)[1]
    raw_text <- gsub("\\s+", " ", raw_text)
    raw_text <- gsub("\\n\\s*\\n", "\n\n", raw_text)

    truncated <- if (nchar(raw_text) > max_chars_per_file) {
      log_info("[SUMMARIZATION] Dosya kırpıldı: {fname} | {nchar(raw_text)} -> {max_chars_per_file}")
      substr(raw_text, 1, max_chars_per_file)
    } else {
      raw_text
    }

    total_chars <- total_chars + nchar(truncated)

    file_contents[[fname]] <- list(
      name = fname,
      content = truncated,
      original_size = nchar(raw_text),
      truncated = nchar(raw_text) > max_chars_per_file,
      path = fpath
    )

    log_info("[SUMMARIZATION] Dosya hazırlandı: {fname} ({nchar(truncated)} karakter)")
  }

  if (length(file_contents) == 0) {
    error_msg <- "Dosya içerikleri okunamadı."
    if (length(read_errors) > 0) {
      error_msg <- paste0(error_msg, "\n\nHatalar:\n", paste("- ", read_errors, collapse = "\n"))
    }

    log_error("[SUMMARIZATION] {error_msg}")

    return(list(
      success = FALSE,
      message = error_msg
    ))
  }

  log_info("[SUMMARIZATION] Başarıyla okunan dosya sayısı: {length(file_contents)} | Toplam karakter: {total_chars}")

  sys_prompt <- build_summarization_system_prompt(
    file_count = length(file_contents),
    total_chars = total_chars,
    detail_level = detail_level,
    focus_mode = focus_mode
  )

  if (!is.null(user_query) && nchar(user_query) > 0) {
    user_prompt <- paste0(
      "Kullanıcı Sorgusu: ", user_query, "\n\n",
      build_summarization_user_prompt(file_contents, detail_level, focus_mode)
    )
  } else {
    user_prompt <- build_summarization_user_prompt(file_contents, detail_level, focus_mode)
  }

  messages <- list(
    list(type = "system", content = sys_prompt),
    list(type = "user", content = user_prompt)
  )

  current_settings <- reactiveValuesToList(settings)
  current_settings$temperature <- 0.3
  current_settings$enable_mcp_tools <- FALSE
  current_settings$tool_family <- "summarization"
  current_settings$shiny_session <- session

  summary_max_output_tokens <- switch(
    detail_level,
    "brief" = 2048L,
    "detailed" = if (length(file_contents) > 1) 16384L else 12288L,
    8192L
  )

  if (identical(focus_mode, "comparison") && length(file_contents) > 1) {
    summary_max_output_tokens <- max(summary_max_output_tokens, 16384L)
  }

  current_settings$max_output_tokens <- summary_max_output_tokens

  log_info(sprintf(
    "[SUMMARIZATION PERF] Çıkış üst sınırı ayarlandı - detay=%s, odak=%s, dosya=%d, max_tokens=%d",
    detail_level,
    focus_mode,
    length(file_contents),
    summary_max_output_tokens
  ))

  selected_model <- current_settings$model_selection
  if (is.null(selected_model) || !nzchar(selected_model)) {
    selected_model <- as.character(api_config$local_models[1])
  }

  metadata_block <- ""
  if (any(vapply(file_contents, `[[`, logical(1), "truncated"))) {
    metadata_block <- paste0(
      "\n\n---\n",
      "_Not: Bazı dosyalar çok uzun olduğu için ilk ",
      format(max_chars_per_file, big.mark = ".", decimal.mark = ","),
      " karakter özetlendi._"
    )
  }

  prep_duration <- as.numeric(difftime(Sys.time(), prep_start_time, units = "secs"))

  log_info(sprintf(
    "[SUMMARIZATION PERF] Hazırlık tamamlandı - dosya=%d, toplam_karakter=%d, süre=%.3f sn",
    length(file_contents),
    total_chars,
    prep_duration
  ))

  list(
    success = TRUE,
    messages = messages,
    current_settings = current_settings,
    selected_model = selected_model,
    file_count = length(file_contents),
    metadata_block = metadata_block,
    prep_duration = prep_duration
  )
}