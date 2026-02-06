# R/module_summarization.R
# Dosya özetleme modülü - Tek veya çoklu belgeleri kapsamlı şekilde özetler

source("R/helpers_summarization_prompts.R", encoding = "UTF-8")

process_summarization_request <- function(
  file_list,
  session,
  settings,
  ai_processor,
  max_chars_per_file = 120000,
  detail_level = "standard",
  focus_mode = "general"
) {
  
  # DEBUG: Log what files we received
  log_info("[SUMMARIZATION] process_summarization_request called with {length(file_list)} files")
  log_info("[SUMMARIZATION] File names: {paste(names(file_list), collapse=', ')}")
  
  # Kullanıcı sorgusunu çıkar (eğer varsa)
  user_query <- NULL
  if (!is.null(file_list$user_query)) {
    user_query <- file_list$user_query
    file_list$user_query <- NULL  # Gerçek dosya listesinden çıkar
    log_info("[SUMMARIZATION] Kullanıcı sorgusu alındı: {user_query}")
  }
  
  if (length(file_list) == 0) {
    return(promises::promise_resolve(list(
      success = FALSE,
      message = "Özetlenecek dosya bulunamadı. Lütfen Dosya Yönetimi sayfasından 'Model Bağlamı' seçeneği işaretli dosyaları ekleyin."
    )))
  }
  
  file_contents <- list()
  total_chars <- 0
  read_errors <- character(0)
  
  for (fname in names(file_list)) {
    fobj <- file_list[[fname]]
    
    # Try multiple path locations
    fpath <- NULL
    
    # Try different possible path locations in order
    possible_paths <- c(
      fobj$datapath,
      fobj$path,
      fobj$source_path,
      fobj$persisted_path
    )
    
    for (path_candidate in possible_paths) {
      if (!is.null(path_candidate) && nzchar(path_candidate) && file.exists(path_candidate)) {
        fpath <- path_candidate
        break
      }
    }
    
    # If still no path, try to resolve from file manager
    if (is.null(fpath)) {
      # Get file manager data from session
      file_manager_data <- session$userData$file_manager_data
      if (!is.null(file_manager_data)) {
        # Try to get file from file manager
        fm_files <- tryCatch({
          if (is.function(file_manager_data$file_contents)) {
            file_manager_data$file_contents()
          } else {
            NULL
          }
        }, error = function(e) NULL)
        
        if (!is.null(fm_files) && fname %in% names(fm_files)) {
          fm_obj <- fm_files[[fname]]
          fpath <- fm_obj$datapath %||% fm_obj$path %||% fm_obj$persisted_path
        }
      }
    }
    
    # If still no path, try to resolve using global resolve function
    if (is.null(fpath)) {
      resolved_path <- tryCatch({
        resolve_uploaded_file(fname, session$userData$user_id %||% NULL)
      }, error = function(e) NULL)
      
      if (!is.null(resolved_path) && file.exists(resolved_path)) {
        fpath <- resolved_path
      }
    }
    
    if (is.null(fpath) || !nzchar(fpath) || !file.exists(fpath)) {
      err_msg <- paste("Dosya yolu bulunamadı:", fname)
      log_error("[SUMMARIZATION] {err_msg}")
      read_errors <- c(read_errors, err_msg)
      next
    }
    
    # Normalize path
    fpath <- normalizePath(fpath, winslash = "/", mustWork = FALSE)
    
    log_info("[SUMMARIZATION] Reading file: {fname} from path: {fpath}")
    
    raw_text <- tryCatch(
      {
        # Use the helper function to read file content
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
        read_errors <- c(read_errors, err_msg)
        NULL
      }
    )
    
    if (is.null(raw_text)) next
    
    # Clean and prepare text
    raw_text <- as.character(raw_text)[1]
    
    # Remove excessive whitespace but preserve structure
    raw_text <- gsub("\\s+", " ", raw_text)
    raw_text <- gsub("\\n\\s*\\n", "\n\n", raw_text)
    
    # Truncate if necessary (but with 256k models, we can handle more)
    truncated <- if (nchar(raw_text) > max_chars_per_file) {
      log_info("[SUMMARIZATION] File {fname} truncated from {nchar(raw_text)} to {max_chars_per_file} chars")
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
    
    log_info("[SUMMARIZATION] Successfully read file: {fname} ({nchar(truncated)} chars)")
  }
  
  if (length(file_contents) == 0) {
    error_msg <- "Dosya içerikleri okunamadı."
    if (length(read_errors) > 0) {
      error_msg <- paste0(error_msg, "\n\nHatalar:\n", paste("- ", read_errors, collapse = "\n"))
    }
    
    log_error("[SUMMARIZATION] {error_msg}")
    
    return(promises::promise_resolve(list(
      success = FALSE,
      message = error_msg
    )))
  }
  
  log_info("[SUMMARIZATION] Successfully read {length(file_contents)} files, total {total_chars} chars")
  
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
  current_settings$tool_family <- "none"
  current_settings$shiny_session <- session
  
  selected_model <- current_settings$model_selection
  if (is.null(selected_model) || !nzchar(selected_model)) {
    selected_model <- as.character(api_config$local_models[1])
  }
  
  p <- ai_processor$call_llm_non_streaming(
    messages,
    current_settings,
    selected_model
  )
  
  promises::then(
    p,
    onFulfilled = function(result) {
      if (!result$success) {
        return(list(
          success = FALSE,
          message = paste("Özetleme başarısız:", result$error)
        ))
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
      
      list(
        success = TRUE,
        summary = paste0(result$content, metadata_block),
        file_count = length(file_contents)
      )
    },
    onRejected = function(err) {
      list(
        success = FALSE,
        message = paste("Özetleme hatası:", conditionMessage(err))
      )
    }
  )
}