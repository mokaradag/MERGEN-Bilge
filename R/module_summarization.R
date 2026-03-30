# R/module_summarization.R
# Dosya özetleme modülü - Tek veya çoklu belgeleri kapsamlı şekilde özetler

safe_source("R/helpers_summarization_prompts.R", encoding = "UTF-8")

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
    
    # Birden fazla yol kaynağını dene
    fpath <- NULL
    
    # 1) Doğrudan dosya bilgisindeki yolları dene (path_exists_relaxed ile UNC desteği)
    possible_paths <- c(
      fobj$persisted_path,
      fobj$datapath,
      fobj$path,
      fobj$source_path
    )
    
    for (path_candidate in possible_paths) {
      if (!is.null(path_candidate) && nzchar(path_candidate)) {
        # Önce path_exists_relaxed, sonra file.exists (UNC yolları için gerekli)
        exists_ok <- tryCatch(path_exists_relaxed(path_candidate), error = function(e) FALSE)
        if (!isTRUE(exists_ok)) exists_ok <- file.exists(path_candidate)
        if (isTRUE(exists_ok)) {
          fpath <- path_candidate
          break
        }
      }
    }
    
    # 2) session$userData$current_session_files'dan dene (register_session_file yolları)
    if (is.null(fpath)) {
      csf <- session$userData$current_session_files
      if (!is.null(csf) && !is.null(csf[[fname]])) {
        csf_obj <- csf[[fname]]
        csf_paths <- c(csf_obj$persisted_path, csf_obj$datapath, csf_obj$path)
        for (cp in csf_paths) {
          if (!is.null(cp) && nzchar(cp)) {
            exists_ok <- tryCatch(path_exists_relaxed(cp), error = function(e) FALSE)
            if (!isTRUE(exists_ok)) exists_ok <- file.exists(cp)
            if (isTRUE(exists_ok)) {
              fpath <- cp
              log_info("[SUMMARIZATION] session registry'den yol bulundu: {cp}")
              break
            }
          }
        }
      }
    }
    
    # 3) Dosya yöneticisi modülünden dene (dosya ID'si ile anahtarlanmış - isim eşleme gerekli)
    if (is.null(fpath)) {
      file_manager_data <- session$userData$file_manager_data
      if (!is.null(file_manager_data)) {
        fm_files <- tryCatch({
          if (is.function(file_manager_data$file_contents)) {
            file_manager_data$file_contents()
          } else {
            NULL
          }
        }, error = function(e) NULL)
        
        # fm_files dosya ID ile anahtarlanmış; isim ile eşleştir
        if (!is.null(fm_files) && length(fm_files) > 0) {
          for (fid in names(fm_files)) {
            fm_obj <- fm_files[[fid]]
            if (identical(fm_obj$name, fname)) {
              fm_paths <- c(fm_obj$persisted_path, fm_obj$datapath, fm_obj$path)
              for (fp in fm_paths) {
                if (!is.null(fp) && nzchar(fp)) {
                  exists_ok <- tryCatch(path_exists_relaxed(fp), error = function(e) FALSE)
                  if (!isTRUE(exists_ok)) exists_ok <- file.exists(fp)
                  if (isTRUE(exists_ok)) {
                    fpath <- fp
                    log_info("[SUMMARIZATION] file_manager'dan yol bulundu: {fp}")
                    break
                  }
                }
              }
              if (!is.null(fpath)) break
            }
          }
        }
      }
    }
    
    # 4) Son çare: resolve_uploaded_file ile dene
    if (is.null(fpath)) {
      user_id <- session$userData$user_id %||% session$userData$system_username %||% NULL
      if (!is.null(user_id)) {
        resolved <- tryCatch(resolve_uploaded_file(fname, user_id), silent = TRUE)
        if (!inherits(resolved, "try-error") && !is.null(resolved) && nzchar(resolved)) {
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

    # Normalize path - yalnızca normalizePath çalışırsa güncelle, aksi hâlde mevcut yolu koru
    fpath_norm <- tryCatch(normalizePath(fpath, winslash = "/", mustWork = TRUE), error = function(e) NULL)
    if (!is.null(fpath_norm)) fpath <- fpath_norm
    
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