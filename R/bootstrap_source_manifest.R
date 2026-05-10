# ==============================================================================
# Dosya Yolu: R/bootstrap_source_manifest.R
# Açıklama: global.R kaynak manifesti doğrulama yardımcıları ve kritik sıra
#           sözleşmeleri. Uygulama kaynaklarını yüklemez; yalnızca manifesti
#           erken, UTF-8 güvenli ve yan etkisiz biçimde doğrular.
# ==============================================================================

source_manifest_stop <- function(message) {
  stop(
    sprintf("Kaynak manifesti doğrulaması başarısız: %s", message),
    call. = FALSE
  )
}

source_manifest_read_file_with_encoding <- function(path, encoding_name) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0L) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  if (!length(raw_data)) {
    return("")
  }

  txt <- tryCatch(
    suppressWarnings(
      iconv(list(raw_data), from = encoding_name, to = "UTF-8", sub = NA)[[1]]
    ),
    error = function(e) NA_character_
  )

  if (is.na(txt)) {
    return(NA_character_)
  }

  txt <- gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
  enc2utf8(txt)
}

source_manifest_read_self <- function(path = "global.R") {
  if (!file.exists(path)) {
    source_manifest_stop(sprintf("manifest dosyası okunamadı: %s", path))
  }

  txt <- source_manifest_read_file_with_encoding(path, "UTF-8")

  if (is.na(txt) || !nzchar(txt)) {
    source_manifest_stop(sprintf("manifest metni UTF-8 olarak okunamadı: %s", path))
  }

  txt
}

source_manifest_extract_safe_source_paths <- function(text) {
  matches <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, matches)[[1]]
  if (length(hits) == 0L || identical(hits, character(0))) {
    source_manifest_stop("safe_source kayıtları bulunamadı.")
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

source_manifest_validate_files <- function(paths, repo_root = getwd()) {
  if (!is.character(paths) || length(paths) == 0L) {
    source_manifest_stop("manifest boş veya karakter vektörü değil.")
  }

  invalid_paths <- paths[is.na(paths) | !nzchar(paths)]
  if (length(invalid_paths) > 0L) {
    source_manifest_stop("manifest içinde boş dosya yolu var.")
  }

  allowed_duplicate_paths <- c("welcome_screen.R")
  duplicate_paths <- setdiff(
    unique(paths[duplicated(paths)]),
    allowed_duplicate_paths
  )

  if (length(duplicate_paths) > 0L) {
    source_manifest_stop(sprintf(
      "tekrar eden kaynak dosya(lar): %s",
      paste(duplicate_paths, collapse = ", ")
    ))
  }

  missing_paths <- paths[!file.exists(file.path(repo_root, paths))]
  if (length(missing_paths) > 0L) {
    source_manifest_stop(sprintf(
      "eksik kaynak dosya(lar): %s",
      paste(missing_paths, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

source_manifest_try_parse_file <- function(path) {
  encodings <- c("UTF-8", "WINDOWS-1254", "latin1")
  last_error <- NULL

  for (encoding_name in encodings) {
    txt <- source_manifest_read_file_with_encoding(path, encoding_name)

    if (is.na(txt)) {
      last_error <- sprintf("dosya %s kodlamasıyla UTF-8'e çevrilemedi", encoding_name)
      next
    }

    parse_result <- tryCatch(
      withCallingHandlers(
        {
          parse(text = txt, keep.source = FALSE, encoding = "UTF-8")
          TRUE
        },
        warning = function(w) {
          stop(conditionMessage(w), call. = FALSE)
        }
      ),
      error = function(e) {
        last_error <<- conditionMessage(e)
        FALSE
      }
    )

    if (isTRUE(parse_result)) {
      return(invisible(TRUE))
    }
  }

  if (is.null(last_error) || !nzchar(last_error)) {
    last_error <- "bilinmeyen parse hatası"
  }

  source_manifest_stop(sprintf(
    "kaynak dosya parse edilemedi: %s -> %s",
    path,
    last_error
  ))
}

source_manifest_validate_parse <- function(paths, repo_root = getwd()) {
  for (path in paths) {
    source_manifest_try_parse_file(file.path(repo_root, path))
  }

  invisible(TRUE)
}

source_manifest_validate_order <- function(paths, order_rules) {
  if (!is.list(order_rules) || length(order_rules) == 0L) {
    return(invisible(TRUE))
  }

  positions <- seq_along(paths)
  names(positions) <- paths

  for (rule in order_rules) {
    if (!is.character(rule) || length(rule) != 2L) {
      source_manifest_stop("geçersiz sıra kuralı tanımı var.")
    }

    before_path <- rule[[1]]
    after_path <- rule[[2]]

    if (is.na(positions[[before_path]]) || is.na(positions[[after_path]])) {
      source_manifest_stop(sprintf(
        "sıra kuralında dosya eksik: %s önce %s",
        before_path,
        after_path
      ))
    }

    if (positions[[before_path]] >= positions[[after_path]]) {
      source_manifest_stop(sprintf(
        "yanlış kaynak sırası: %s, %s dosyasından önce yüklenmelidir.",
        before_path,
        after_path
      ))
    }
  }

  invisible(TRUE)
}

source_manifest_validate <- function(order_rules,
                                     repo_root = getwd(),
                                     source_file = "global.R",
                                     validate_parse = TRUE) {
  manifest_text <- source_manifest_read_self(source_file)
  paths <- source_manifest_extract_safe_source_paths(manifest_text)

  source_manifest_validate_files(paths, repo_root = repo_root)

  if (isTRUE(validate_parse)) {
    source_manifest_validate_parse(paths, repo_root = repo_root)
  }

  source_manifest_validate_order(paths, order_rules)

  invisible(paths)
}

source_manifest_required_order <- list(
  c("R/bootstrap_source_manifest.R", "R/config_packages.R"),

  c("R/config_file_store.R", "R/config_file_store_index_mutation.R"),
  c("R/config_file_store_index_mutation.R", "R/config_file_store_registry.R"),
  c("R/config_file_store_registry.R", "R/config_characters.R"),

  c("R/config_api.R", "R/helpers_api_model_config.R"),
  c("R/helpers_api_model_config.R", "R/config_claude_code.R"),
  c("R/helpers_api_model_config.R", "R/helpers_llm_api.R"),
  c("R/helpers_api_model_config.R", "R/helpers_llm_sse.R"),
  c("R/helpers_api_model_config.R", "R/helpers_llm_worker.R"),

  c("R/helpers_database.R", "R/module_chat_history.R"),

  c("R/helpers_mcp_context.R", "R/helpers_mcp_bootstrap.R"),
  c("R/helpers_mcp_bootstrap.R", "R/helpers_mcp_tools.R"),
  c("R/helpers_mcp_tools.R", "R/helpers_mcp_table_readers.R"),
  c("R/helpers_mcp_table_readers.R", "R/helpers_mcp_file_resolver.R"),
  c("R/helpers_mcp_file_resolver.R", "R/helpers_mcp_schema_helpers.R"),
  c("R/helpers_mcp_schema_helpers.R", "R/helpers_mcp_basic_tools.R"),
  c("R/helpers_mcp_basic_tools.R", "R/helpers_mcp_chart_tools.R"),
  c("R/helpers_mcp_chart_tools.R", "R/helpers_chartlab_spec.R"),
  c("R/helpers_chartlab_spec.R", "R/helpers_chartlab.R"),
  c("R/helpers_mcp_file_resolver.R", "R/module_summarization.R"),

  c("R/helpers_files_path.R", "R/helpers_files.R"),
  c("R/helpers_files.R", "R/helpers_file_manager_policy.R"),
  c("R/helpers_file_manager_policy.R", "R/helpers_file_manager_context_policy.R"),
  c("R/helpers_file_manager_context_policy.R", "R/helpers_file_manager_table.R"),
  c("R/helpers_file_manager_table.R", "R/helpers_file_manager_refresh_guard.R"),
  c("R/helpers_file_manager_refresh_guard.R", "R/helpers_file_manager_session_registry.R"),
  c("R/helpers_file_manager_session_registry.R", "R/helpers_file_manager_runtime.R"),
  c("R/helpers_file_manager_runtime.R", "R/helpers_file_manager_storage.R"),
  c("R/helpers_file_manager_storage.R", "R/helpers_file_manager_state_runtime.R"),
  c("R/helpers_file_manager_state_runtime.R", "R/module_file_manager_ui.R"),
  c("R/module_file_manager_ui.R", "R/module_file_manager.R"),

  c("R/helpers_send_message_request_lifecycle.R", "R/helpers_send_message_core.R"),
  c("R/helpers_send_message_core.R", "R/helpers_send_message_prompting.R"),
  c("R/helpers_send_message_prompting.R", "R/server_send_message.R"),
  c("R/helpers_send_message_request_lifecycle.R", "R/server_handler_true_streaming.R"),
  c("R/helpers_send_message_core.R", "R/server_send_message.R"),

  c("R/helpers_health_formatters.R", "R/helpers_health_runtime_checks.R"),
  c("R/helpers_health_runtime_checks.R", "R/helpers_health_checks.R"),
  c("R/helpers_health_checks.R", "R/module_health.R"),

  c("R/helpers_claude_code_user_guard.R", "R/helpers_claude_code_server_setup.R"),
  c("R/helpers_claude_code_upload_folder.R", "R/helpers_claude_code_server_setup.R"),
  c("R/helpers_claude_code_process.R", "R/helpers_claude_code_runtime_workdir.R"),
  c("R/helpers_claude_code_runtime_workdir.R", "R/helpers_claude_code_directory_listing.R"),
  c("R/helpers_claude_code_directory_listing.R", "R/helpers_claude_code.R"),
  c("R/helpers_claude_code.R", "R/helpers_claude_code_server_setup.R"),
  c("R/helpers_claude_code_downloads.R", "R/helpers_claude_code_workdir_scan.R"),
  c("R/helpers_claude_code_workdir_scan.R", "R/helpers_claude_code_workdir_snapshot.R"),
  c("R/helpers_claude_code_workdir_snapshot.R", "R/helpers_claude_code_documents.R"),
  c("R/helpers_claude_code_documents.R", "R/helpers_claude_code_run_lifecycle.R"),
  c("R/helpers_claude_code_run_lifecycle.R", "R/module_claude_code_akis.R"),
  c("R/helpers_claude_code_run_lifecycle.R", "R/module_claude_code.R"),
  c("R/helpers_claude_code_server_setup.R", "R/module_claude_code.R"),

  c("R/helpers_llm_response_postprocess.R", "R/helpers_llm_api.R"),
  c("R/helpers_llm_api.R", "R/helpers_llm_stream_io.R"),
  c("R/helpers_llm_stream_io.R", "R/helpers_llm_sse.R"),
  c("R/helpers_llm_sse.R", "R/helpers_llm_worker_payload.R"),
  c("R/helpers_llm_worker_payload.R", "R/helpers_llm_worker_tool_results.R"),
  c("R/helpers_llm_worker_tool_results.R", "R/helpers_llm_worker.R"),
  c("R/server_handler_true_streaming.R", "R/server_send_message.R"),

  c("R/utils_session_cleanup.R", "R/server_session_cache.R"),
  c("R/utils_session_cleanup.R", "R/server_init_session_state.R"),
  c("R/module_user_identity.R", "R/helpers_user_session_identity.R"),
  c("R/helpers_user_session_identity.R", "R/server_init_user_session.R"),
  c("R/server_init_forward_refs.R", "R/server_init_user_session.R"),
  c("R/server_init_user_session.R", "R/helpers_server_runtime_contracts.R"),
  c("R/helpers_server_runtime_contracts.R", "R/server_runtime_context.R"),
  c("R/server_runtime_context.R", "R/server_runtime_function_slot.R"),
  c("R/server_runtime_function_slot.R", "R/server_module_wiring.R"),
  c("R/server_module_wiring.R", "R/server_init_session_state.R"),
  c("R/server_module_wiring.R", "R/server_init_chat_runtime.R"),

  c("R/helpers_admin_geri_bildirim.R", "R/helpers_admin_geri_bildirim_queries.R"),
  c("R/helpers_admin_geri_bildirim_queries.R", "R/module_admin_geri_bildirim.R"),
  c("R/helpers_admin_hata_analizi.R", "R/module_admin_hata_analizi.R")
)