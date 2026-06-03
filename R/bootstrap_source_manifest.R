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

  # Windows CRLF / eski Mac CR satır sonlarını gerçek LF karakterine çevir.
  # "\\n" kullanılmamalıdır; bu değer replacement tarafında literal "n"e
  # dönüşerek geçerli R dosyalarının parse edilmesini bozabilir.
  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

source_manifest_validate_config_objects <- function(envir = globalenv()) {
  required_objects <- c(
    "source_manifest_group_1_paths",
    "source_manifest_after_future_paths",
    "source_manifest_runtime_paths"
  )

  missing_objects <- required_objects[!vapply(
    required_objects,
    exists,
    logical(1),
    envir = envir,
    inherits = FALSE
  )]

  if (length(missing_objects) > 0L) {
    source_manifest_stop(sprintf(
      "kaynak manifesti nesne(leri) bulunamadı: %s",
      paste(missing_objects, collapse = ", ")
    ))
  }

  get_paths <- function(object_name) {
    paths <- get(object_name, envir = envir, inherits = FALSE)

    if (!is.character(paths) || length(paths) == 0L) {
      source_manifest_stop(sprintf(
        "kaynak manifesti nesnesi geçersiz veya boş: %s",
        object_name
      ))
    }

    paths <- enc2utf8(paths)
    invalid_mask <- is.na(paths) | !nzchar(trimws(ifelse(is.na(paths), "", paths)))

    if (any(invalid_mask)) {
      source_manifest_stop(sprintf(
        "kaynak manifesti nesnesi içinde boş dosya yolu var: %s",
        object_name
      ))
    }

    paths
  }

  group_1_paths <- get_paths("source_manifest_group_1_paths")
  after_future_paths <- get_paths("source_manifest_after_future_paths")
  runtime_paths <- get_paths("source_manifest_runtime_paths")
  expected_runtime_paths <- c(group_1_paths, after_future_paths)

  if (!identical(runtime_paths, expected_runtime_paths)) {
    source_manifest_stop(
      "source_manifest_runtime_paths, source_manifest_group_1_paths ve source_manifest_after_future_paths birleşimiyle aynı değil."
    )
  }

  invisible(list(
    group_1_paths = group_1_paths,
    after_future_paths = after_future_paths,
    runtime_paths = runtime_paths
  ))
}

source_manifest_validate_files <- function(paths, repo_root = getwd()) {
  if (!is.character(paths) || length(paths) == 0L) {
    source_manifest_stop("manifest boş veya karakter vektörü değil.")
  }

  paths <- enc2utf8(paths)

  invalid_paths <- paths[is.na(paths) | !nzchar(trimws(ifelse(is.na(paths), "", paths)))]
  if (length(invalid_paths) > 0L) {
    source_manifest_stop("manifest içinde boş dosya yolu var.")
  }

  duplicate_paths <- sort(unique(paths[duplicated(paths)]))

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

source_manifest_validate_order_rule_targets <- function(paths,
                                                        order_rules,
                                                        optional_paths = character()) {
  if (!is.list(order_rules) || length(order_rules) == 0L) {
    return(invisible(TRUE))
  }

  for (rule in order_rules) {
    if (!is.character(rule) || length(rule) != 2L) {
      source_manifest_stop("geçersiz sıra kuralı tanımı var.")
    }
  }

  known_paths <- unique(enc2utf8(c(paths, optional_paths)))
  rule_paths <- unique(enc2utf8(unlist(order_rules, use.names = FALSE)))
  missing_rule_paths <- setdiff(rule_paths, known_paths)

  if (length(missing_rule_paths) > 0L) {
    source_manifest_stop(sprintf(
      "sıra kuralı manifest/boot allowlist dışında dosya içeriyor: %s",
      paste(missing_rule_paths, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

source_manifest_validate_order <- function(paths, order_rules) {
  if (!is.list(order_rules) || length(order_rules) == 0L) {
    return(invisible(TRUE))
  }

  paths <- enc2utf8(paths)

  positions <- seq_along(paths)
  names(positions) <- paths
  manifest_names <- names(positions)

  for (rule in order_rules) {
    if (!is.character(rule) || length(rule) != 2L) {
      source_manifest_stop("geçersiz sıra kuralı tanımı var.")
    }

    before_path <- enc2utf8(rule[[1]])
    after_path <- enc2utf8(rule[[2]])

    # Boot allowlist içindeki dosyalar runtime manifestte yer almayabilir.
    # Bu durumda hedef geçerliliği ayrı doğrulanır, sıra karşılaştırması atlanır.
    if (!(before_path %in% manifest_names) || !(after_path %in% manifest_names)) {
      next
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

source_manifest_get_runtime_paths <- function(manifest_object = "source_manifest_runtime_paths",
                                              envir = globalenv()) {
  if (!exists(manifest_object, envir = envir, inherits = FALSE)) {
    source_manifest_stop(sprintf(
      "kaynak manifesti nesnesi bulunamadı: %s",
      manifest_object
    ))
  }

  paths <- get(manifest_object, envir = envir, inherits = FALSE)

  if (!is.character(paths) || length(paths) == 0L) {
    source_manifest_stop(sprintf(
      "kaynak manifesti nesnesi geçersiz veya boş: %s",
      manifest_object
    ))
  }

  enc2utf8(paths)
}

source_manifest_load <- function(paths, encoding = "UTF-8") {
  if (!exists("safe_source", mode = "function")) {
    source_manifest_stop("safe_source fonksiyonu yüklenmeden kaynak yükleme başlatılamaz.")
  }

  if (!is.character(paths) || length(paths) == 0L) {
    source_manifest_stop("yüklenecek kaynak manifesti boş veya karakter vektörü değil.")
  }

  paths <- enc2utf8(paths)

  source_manifest_validate_files(paths)

  for (path in paths) {
    tryCatch(
      {
        safe_source(path, encoding = encoding)
      },
      error = function(e) {
        source_manifest_stop(sprintf(
          "kaynak dosya yüklenemedi: %s -> %s",
          path,
          conditionMessage(e)
        ))
      }
    )
  }

  invisible(TRUE)
}

source_manifest_validate <- function(order_rules,
                                     repo_root = getwd(),
                                     source_file = NULL,
                                     validate_parse = TRUE,
                                     paths = NULL,
                                     optional_order_paths = c(
                                       "app.R",
                                       "global.R",
                                       "ui.R",
                                       "server.R",
                                       "R/utils_safe_source.R",
                                       "R/bootstrap_source_manifest.R",
                                       "R/config_source_manifest.R"
                                     )) {
  if (!is.null(source_file)) {
    source_manifest_stop(
      "source_file parametresi artık desteklenmez; kaynak yolları R/config_source_manifest.R üzerinden açıkça verilmelidir."
    )
  }

  if (is.null(paths)) {
    source_manifest_stop(
      "doğrulanacak kaynak yolları açıkça verilmelidir; global.R içinden safe_source listesi çıkarılmaz."
    )
  }

  paths <- enc2utf8(paths)

  source_manifest_validate_files(paths, repo_root = repo_root)

  if (isTRUE(validate_parse)) {
    source_manifest_validate_parse(paths, repo_root = repo_root)
  }

  source_manifest_validate_order_rule_targets(
    paths = paths,
    order_rules = order_rules,
    optional_paths = optional_order_paths
  )

  source_manifest_validate_order(paths, order_rules)

  invisible(paths)
}

source_manifest_required_order <- list(
  c("R/bootstrap_source_manifest.R", "R/config_packages.R"),

  c("R/utils_common.R", "R/utils_text_encoding.R"),
  c("R/utils_text_encoding.R", "R/config_logging.R"),
  c("R/config_logging.R", "R/utils_rate_limiter.R"),
  c("R/utils_rate_limiter.R", "R/helpers_worker_monitor.R"),

  c("R/config_file_store.R", "R/config_file_store_index_mutation.R"),
  c("R/config_file_store_index_mutation.R", "R/config_file_store_listing_helpers.R"),
  c("R/config_file_store_listing_helpers.R", "R/config_file_store_registry.R"),
  c("R/config_file_store_registry.R", "R/config_characters.R"),

  c("R/config_api.R", "R/helpers_api_model_config.R"),
  c("R/helpers_api_model_config.R", "R/config_claude_code.R"),
  c("R/helpers_api_model_config.R", "R/helpers_llm_api.R"),
  c("R/helpers_api_model_config.R", "R/helpers_llm_sse.R"),
  c("R/helpers_api_model_config.R", "R/helpers_llm_worker.R"),

  c("R/helpers_db_connection.R", "R/helpers_db_user_encoding.R"),
  c("R/helpers_db_user_encoding.R", "R/helpers_db_validation.R"),
  c("R/helpers_db_validation.R", "R/helpers_chat_message_formatting.R"),
  c("R/helpers_chat_message_formatting.R", "R/helpers_db_chat_readers.R"),
  c("R/helpers_db_chat_readers.R", "R/helpers_db_chat_mutations.R"),
  c("R/helpers_db_chat_mutations.R", "R/helpers_database.R"),
  c("R/helpers_database.R", "R/module_chat_history.R"),

  c("R/library_queries.R", "R/config_sql_loader.R"),

  c("R/helpers_mcp_context.R", "R/helpers_mcp_bootstrap.R"),
  c("R/helpers_mcp_bootstrap.R", "R/helpers_mcp_table_readers.R"),
  c("R/helpers_mcp_table_readers.R", "R/helpers_mcp_file_resolver.R"),
  c("R/helpers_mcp_file_resolver.R", "R/helpers_mcp_schema_helpers.R"),
  c("R/helpers_mcp_schema_helpers.R", "R/helpers_mcp_basic_tools.R"),
  c("R/helpers_mcp_basic_tools.R", "R/helpers_mcp_chart_tools.R"),
  c("R/helpers_mcp_chart_tools.R", "R/helpers_mcp_analyze_visualize.R"),
  c("R/helpers_mcp_analyze_visualize.R", "R/helpers_mcp_tools.R"),
  c("R/helpers_mcp_tools.R", "R/helpers_chartlab_spec.R"),
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
  c("R/helpers_file_manager_state_runtime.R", "R/helpers_file_manager_attach_client.R"),
  c("R/helpers_file_manager_attach_client.R", "R/helpers_file_manager_table_runtime.R"),
  c("R/helpers_file_manager_state_runtime.R", "R/module_file_manager_ui.R"),
  c("R/helpers_file_manager_table_runtime.R", "R/module_file_manager.R"),
  c("R/helpers_file_manager_attach_client.R", "R/module_file_manager.R"),
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
  c("R/helpers_claude_code_downloads.R", "R/helpers_claude_code_downloads_html.R"),
  c("R/helpers_claude_code_downloads_html.R", "R/helpers_claude_code_existing_file_link.R"),
  c("R/helpers_claude_code_downloads.R", "R/helpers_claude_code_workdir_scan.R"),
  c("R/helpers_claude_code_workdir_scan.R", "R/helpers_claude_code_workdir_snapshot.R"),
  c("R/helpers_claude_code_workdir_snapshot.R", "R/helpers_claude_code_documents.R"),
  c("R/helpers_claude_code_documents.R", "R/helpers_claude_code_run_lifecycle.R"),
  c("R/helpers_claude_code_run_lifecycle.R", "R/module_claude_code_akis.R"),
  c("R/helpers_claude_code_run_lifecycle.R", "R/module_claude_code.R"),
  c("R/helpers_claude_code_server_setup.R", "R/module_claude_code.R"),

  c("R/helpers_llm_response_postprocess.R", "R/helpers_llm_api.R"),
  c("R/helpers_llm_api.R", "R/helpers_llm_stream_io.R"),
  c("R/helpers_llm_stream_io.R", "R/helpers_llm_sse_events.R"),
  c("R/helpers_llm_sse_events.R", "R/helpers_llm_sse.R"),
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
  c("R/helpers_server_runtime_contracts.R", "R/helpers_server_runtime_named_contracts.R"),
  c("R/helpers_server_runtime_named_contracts.R", "R/server_runtime_context.R"),
  c("R/server_runtime_context.R", "R/server_runtime_function_slot.R"),
  c("R/server_runtime_function_slot.R", "R/server_module_wiring.R"),
  c("R/server_module_wiring.R", "R/server_chat_engine_dependencies.R"),
  c("R/server_chat_engine_dependencies.R", "R/server_chat_engine_runtime.R"),
  c("R/server_module_wiring.R", "R/server_init_session_state.R"),
  c("R/server_module_wiring.R", "R/server_init_chat_runtime.R"),
  c("R/server_chat_engine_runtime.R", "R/server_init_session_state.R"),
  c("R/server_chat_engine_runtime.R", "R/server_init_chat_runtime.R"),

  c("R/welcome_screen_modern.R", "welcome_screen.R"),
  c("welcome_screen.R", "R/server_welcome_handlers.R"),

  c("R/helpers_admin_geri_bildirim.R", "R/helpers_admin_geri_bildirim_queries.R"),
  c("R/helpers_admin_geri_bildirim_queries.R", "R/module_admin_geri_bildirim.R"),
  c("R/helpers_admin_hata_analizi.R", "R/module_admin_hata_analizi.R")
)