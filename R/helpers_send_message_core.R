# ============================================================================== 
# Dosya Yolu: R/helpers_send_message_core.R
# Açıklama: send_message hattındaki yönlendirme, cleanup ve MCP hazırlık
# yardımcılarını tek yerde toplar. Amaç davranışı değiştirmeden
# server_send_message.R dosyasındaki merkezi baskıyı azaltmaktır.
# ==============================================================================

if (!exists("mergen_new_send_message_request_id", mode = "function", inherits = TRUE)) {
  safe_source("R/helpers_send_message_request_lifecycle.R", encoding = "UTF-8")
}

mergen_determine_tool_family <- function(settings_data, uploaded_count, skip_mcp_once, current_settings) {
  cfg_excel_on <- isTRUE(settings_data$enable_mcp_tools)
  cfg_sql_analysis_on <- isTRUE(settings_data$enable_rdata_tools)
  cfg_summarization_on <- isTRUE(settings_data$enable_summarization_tools)
  cfg_coding_on <- isTRUE(settings_data$enable_coding_tools)

  excel_allowed <- cfg_excel_on && uploaded_count > 0

  if (isTRUE(skip_mcp_once)) {
    tool_family <- "none"
  } else if (cfg_sql_analysis_on) {
    tool_family <- "sql_analysis"
    current_settings$max_output_tokens <- 4096
  } else if (excel_allowed) {
    tool_family <- "mcp_excel"
  } else if (cfg_summarization_on) {
    tool_family <- "summarization"
  } else if (cfg_coding_on) {
    tool_family <- "coding"
    current_settings$max_output_tokens <- 4096
  } else if (isTRUE(settings_data$enable_process_tools)) {
    tool_family <- "process"
  } else if (isTRUE(settings_data$enable_app_expert_tools)) {
    tool_family <- "app_expert"
  } else if (isTRUE(settings_data$enable_image_tools)) {
    tool_family <- "image"
  } else {
    tool_family <- "none"
  }

  list(
    tool_family = tool_family,
    current_settings = current_settings,
    cfg_excel_on = cfg_excel_on,
    cfg_sql_analysis_on = cfg_sql_analysis_on,
    cfg_summarization_on = cfg_summarization_on,
    cfg_coding_on = cfg_coding_on,
    excel_allowed = excel_allowed
  )
}

# Langflow (Süreç Yönetimi / Uygulama Uzmanı) çağrısı için handle_langflow_chat_mode
# bağlamını (ctx) hazırlar. Süreç Yönetimi için seçili akışı sohbet açılır
# menüsünden (input$chat_process_flow), yoksa kalıcı ayardan çözer; ikisi de yoksa
# handler varsayılan ilk akışa düşer.
mergen_build_langflow_ctx <- function(session, input, values, settings_data, tool_family,
                                      user_message_text, effective_user_id,
                                      stop_generation, active_request_id,
                                      add_message_fn, reset_chat_state_fn, api_config) {
  selected_process_flow <- shiny::isolate(input$chat_process_flow)
  if (is.null(selected_process_flow) || !nzchar(as.character(selected_process_flow)[1])) {
    selected_process_flow <- settings_data$process_flow_selection %||% NULL
  }

  list(
    session = session, values = values, settings_data = settings_data,
    tool_family = tool_family, user_message_text = user_message_text,
    current_user_id = effective_user_id,
    chat_id_val = shiny::isolate(values$current_chat_id),
    stop_generation = stop_generation, active_request_id = active_request_id,
    add_message_fn = add_message_fn, reset_chat_state_fn = reset_chat_state_fn,
    selected_process_flow = selected_process_flow,
    api_config = api_config
  )
}

mergen_build_stream_profile <- function(tool_family, uploaded_count, settings_data, force_non_streaming_sql = FALSE) {
  stream_profile <- list(
    label = "standard",
    use_delta_transport = FALSE,
    poll_interval_ms = 50L
  )

  if ((identical(tool_family, "none") || identical(tool_family, "coding")) &&
      uploaded_count == 0 &&
      !isTRUE(settings_data$enable_tts_audio) &&
      !isTRUE(force_non_streaming_sql)) {
    stream_profile$label <- if (identical(tool_family, "coding")) "coding_fast" else "plain_fast"
    stream_profile$use_delta_transport <- TRUE
    stream_profile$poll_interval_ms <- 15L
  }

  stream_profile
}

# Proje/Kaynak (SQL) analizinde düşünmeli model akış planı.
# Düşünmeli SQL/Proje analizi artık canlı "Düşünce Akışı" için gerçek SSE ile
# akıtılır (Excel Analizi gibi). Güvenlik ağı olarak işçi tarafında non-streaming
# geri dönüş açılır: SSE yalnızca akıl yürütme benzeri/boş içerik döndürürse işçi
# stream=FALSE ile tek seferlik yeniden dener ve yalnızca nihai yanıt gövdesini
# düzeltir. TTS açıkken veya streaming kapalıyken eski güvenli non-streaming korunur
# (TTS yolu simulate_streaming kullanır; reasoning'i gerçek SSE gibi akıtmaz).
# Saf karar yardımcısıdır: Shiny/oturum/ağ erişimi yoktur, izole test edilebilir.
mergen_sql_analysis_stream_plan <- function(tool_family,
                                            thinking_model,
                                            enable_streaming,
                                            enable_mcp_tools,
                                            enable_tts_audio) {
  is_sql_thinking <- identical(tool_family, "sql_analysis") && isTRUE(thinking_model)

  can_true_stream <- is_sql_thinking &&
    isTRUE(enable_streaming) &&
    !isTRUE(enable_mcp_tools) &&
    !isTRUE(enable_tts_audio)

  list(
    is_sql_thinking = is_sql_thinking,
    allow_non_streaming_fallback = can_true_stream,
    force_non_streaming = is_sql_thinking && !can_true_stream
  )
}

# Saf yardımcı: "düz hızlı sohbet" yolu kararı. Yalnızca araç=none, dosya yok,
# streaming açık, MCP/TTS kapalı ve SQL non-streaming zorlaması yoksa TRUE döner.
# Bu yol; ağır tanılama dökümü, MCP/dosya hazırlığı ve gereksiz worker yükü gibi
# ilk-token öncesi işleri atlamak için kullanılır. Kodlama Desteği bilinçli olarak
# AYRI bir hızlı profille (coding_fast) yönetilir; bu yardımcı yalnızca "none"
# içindir (görsel/özetleme/SQL/MCP/coding kapsam dışıdır).
mergen_is_plain_fast_chat <- function(tool_family,
                                      uploaded_count,
                                      current_settings = list(),
                                      settings_data = list(),
                                      force_non_streaming_sql = FALSE) {
  identical(tool_family, "none") &&
    isTRUE((uploaded_count %||% 0L) == 0L) &&
    isTRUE(current_settings$enable_streaming) &&
    !isTRUE(current_settings$enable_mcp_tools) &&
    !isTRUE(settings_data$enable_tts_audio) &&
    !isTRUE(force_non_streaming_sql)
}

# Worker'a (tracked_future_promise) serileştirilecek ayar listesini küçültür.
# Amaç: ilk-token gecikmesini azaltmak için worker'a gönderilen yükü minimize
# etmek. Shiny oturumu HER ZAMAN çıkarılır (serileştirilemez ve gereksizdir).
# Düz hızlı sohbette ek olarak ağır/gereksiz alanlar (dosya kayıtları, MCP
# snapshot, dosya yolları, kullanıcı config blob'u) atılır.
# call_local_llm_sse_worker'ın ihtiyaç duyduğu alanlar (model_selection,
# temperature, max_output_tokens, api_key/override, request zaman damgaları,
# allow_* bayrakları) KORUNUR.
mergen_sanitize_llm_settings_for_worker <- function(current_settings,
                                                    plain_fast = FALSE) {
  settings <- if (is.list(current_settings)) current_settings else list()

  # Oturum nesnesi worker tarafına asla gönderilmez.
  settings$shiny_session <- NULL

  if (isTRUE(plain_fast)) {
    heavy_fields <- c(
      "current_session_files",
      "mcp_registry_snapshot",
      "mcp_snapshot",
      "file_paths",
      "uploaded_files",
      "user_config"
    )
    for (field in heavy_fields) {
      settings[[field]] <- NULL
    }
  }

  settings
}

mergen_remove_typing_wrapper_if_safe <- function(active_request_id = NULL,
                                                 req_id = NULL,
                                                 remove_ui_fn = removeUI) {
  if (!is.function(remove_ui_fn)) {
    return(invisible(FALSE))
  }

  if (!is.null(req_id) &&
      length(req_id) > 0L &&
      nzchar(as.character(req_id)[1]) &&
      is.function(active_request_id)) {
    request_id <- as.character(req_id)[1]
    current_id <- tryCatch(active_request_id(), error = function(e) NULL)

    if (!identical(current_id, request_id)) {
      return(invisible(FALSE))
    }
  }

  try(remove_ui_fn(selector = "#typing-animation-wrapper", immediate = TRUE), silent = TRUE)
  invisible(TRUE)
}

# --- Süreç-geneli kabul-denetimi (backpressure) slotu yardımcıları ---
# Pahalı LLM/sohbet işlemlerini süreç-genelinde üst-sınıra bağlamak için kullanılır
# (R/helpers_request_backpressure.R). Varsayılan KAPALI (limit 0) iken hepsi
# no-op'tur ve mevcut davranış bayt-bayt korunur. Helper yoksa da güvenli no-op.

# Bir slot edinmeyi dener. Limit 0/helper-yok -> acquired=TRUE, token=NULL.
mergen_send_message_acquire_slot <- function(kind = "llm") {
  if (exists("mergen_backpressure_try_acquire", mode = "function", inherits = TRUE)) {
    return(mergen_backpressure_try_acquire(kind))
  }
  list(acquired = TRUE, token = NULL)
}

# Verilen token'ı serbest bırakır (idempotent; NULL/helper-yok -> no-op).
mergen_send_message_release_slot <- function(token) {
  if (!is.null(token) && exists("mergen_backpressure_release", mode = "function", inherits = TRUE)) {
    try(mergen_backpressure_release(token), silent = TRUE)
  }
  invisible(NULL)
}

# values$backpressure_token'ı serbest bırakıp temizler (sonlandırma/iptal yolları
# ve yeni istek girişindeki bayat-slot temizliği için tek çağrı noktası).
mergen_send_message_release_values_token <- function(values, req_id = NULL) {
  tok <- tryCatch(shiny::isolate(values$backpressure_token), error = function(e) NULL)

  if (!is.null(req_id)) {
    expected_id <- tryCatch(as.character(req_id)[1], error = function(e) NA_character_)
    token_request_id <- tryCatch(
      shiny::isolate(values$backpressure_request_id),
      error = function(e) NULL
    )
    token_request_id <- tryCatch(
      as.character(token_request_id)[1],
      error = function(e) NA_character_
    )

    if (is.na(expected_id) ||
        is.na(token_request_id) ||
        !identical(token_request_id, expected_id)) {
      return(invisible(FALSE))
    }
  }

  mergen_send_message_release_slot(tok)
  values$backpressure_token <- NULL
  values$backpressure_request_id <- NULL
  invisible(TRUE)
}

mergen_cleanup_send_message <- function(values,
                                        reset_chat_state_fn,
                                        remove_typing_wrapper = TRUE,
                                        active_request_id = NULL,
                                        req_id = NULL,
                                        remove_ui_fn = removeUI) {
  if (isTRUE(remove_typing_wrapper)) {
    mergen_remove_typing_wrapper_if_safe(
      active_request_id = active_request_id,
      req_id = req_id,
      remove_ui_fn = remove_ui_fn
    )
  }

  values$typing <- FALSE
  reset_chat_state_fn()
  invisible(NULL)
}

mergen_abort_send_message <- function(
  session,
  values,
  reset_chat_state_fn,
  toast_message = NULL,
  toast_type = "warning",
  remove_typing_wrapper = TRUE,
  active_request_id = NULL,
  req_id = NULL,
  remove_ui_fn = removeUI
) {
  mergen_cleanup_send_message(
    values = values,
    reset_chat_state_fn = reset_chat_state_fn,
    remove_typing_wrapper = remove_typing_wrapper,
    active_request_id = active_request_id,
    req_id = req_id,
    remove_ui_fn = remove_ui_fn
  )

  msg <- tryCatch(as.character(toast_message %||% "")[1], error = function(e) "")
  if (nzchar(msg)) {
    showToast(session, msg, toast_type)
  }

  invisible(NULL)
}

mergen_prepare_mcp_session_files <- function(
  session,
  file_manager_data,
  uploaded_names,
  effective_user_id,
  current_settings,
  cache_mcp_file_locally_fn,
  update_mcp_registry_snapshot_fn,
  tool_family
) {
  # Opsiyonel performans ölçümü (yalnızca MERGEN_PERF_LOG açıkken aktiftir).
  .perf_start <- if (exists("mergen_perf_now", mode = "function", inherits = TRUE)) mergen_perf_now() else NULL
  if (!is.null(.perf_start)) on.exit(mergen_perf_log("send_message.mcp_prepare", .perf_start), add = TRUE)

  if (!(identical(tool_family, "mcp_excel") && length(uploaded_names) > 0)) {
    # MCP dışı yollarda current_session_files temizlenmez.
    # Aynı store görsel anlama (vision) tarafından da kullanılır; burada
    # temizlenirse ilk görsel sorusundan sonra sonraki sorularda görsel yolu
    # kaybolur ve kullanıcı yeniden giriş yapmadan görsel tekrar analiz edilemez.
    mevcut_dosya_kaydi <- session_user_data_get_list(
      session,
      "current_session_files",
      default = list(),
      create = FALSE
    )

    return(list(
      current_session_files = mevcut_dosya_kaydi,
      mcp_snapshot = update_mcp_registry_snapshot_fn(list())
    ))
  }

  fm_files <- file_manager_data$file_contents()

  resolve_from_manager <- function(target_name) {
    if (!length(fm_files)) return(NULL)

    for (fid in names(fm_files)) {
      obj <- fm_files[[fid]]
      nm  <- obj$name %||% basename(obj$datapath %||% obj$path %||% "")
      if (identical(nm, target_name)) {
        return(list(info = obj, id = fid))
      }
    }

    NULL
  }

  pick_existing_path <- function(info) {
    candidates <- c(info$persisted_path, info$path, info$datapath)
    candidates <- candidates[
      !vapply(candidates, function(x) is.null(x) || !nzchar(as.character(x)[1]), logical(1))
    ]

    for (cand in candidates) {
      c0 <- as.character(cand)[1]
      if (nzchar(c0) && path_exists_relaxed(c0)) return(c0)
    }

    NULL
  }

  csf <- list()

  for (fname in uploaded_names) {
    fm_hit <- resolve_from_manager(fname)
    finfo  <- fm_hit$info %||% list(name = fname)
    fid    <- fm_hit$id %||% NULL

    path_now <- pick_existing_path(finfo)
    if (is.null(path_now) || !nzchar(path_now)) {
		resolved <- tryCatch(
		  resolve_uploaded_file(
			fname,
			user_id = effective_user_id
		  ),
		  error = function(e) NULL
		)

		if (!is.null(resolved) && nzchar(resolved) && path_exists_relaxed(resolved)) {
		  path_now <- resolved
		}
    }

    if (is.null(path_now) || !nzchar(path_now) || !path_exists_relaxed(path_now)) {
      log_debug("[FILE STORE] {fname} için yol bulunamadı — atlanıyor")
      next
    }

    path_now <- tryCatch(
      normalizePath(path_now, winslash = "/", mustWork = TRUE),
      error = function(e) path_now
    )

    if (!grepl("^//[^/]+/[^/]+", gsub("\\", "/", path_now, fixed = TRUE))) {
      path_now <- safe_windows_short_path(path_now, must_exist = path_exists_relaxed(path_now))
    } else {
      path_now <- paste0("//", sub("^/+", "", gsub("\\", "/", path_now, fixed = TRUE)))
    }

    path_original <- path_now
    tryCatch({
      if (!is_under_mcp_base(path_now) && isTRUE(current_settings$enable_mcp_tools)) {
        copied <- copy_to_mcp_base(list(name = fname, datapath = path_now), effective_user_id)
        if (nzchar(copied) && path_exists_relaxed(copied)) path_now <- copied
      }
    }, error = function(e) {
      log_warn("[FILE STORE] copy_to_mcp_base başarısız: {e$message}")
    })

    cached_path <- cache_mcp_file_locally_fn(path_now)
    if (is.null(cached_path) || !nzchar(cached_path)) {
      cached_path <- path_now
    } else if (!identical(cached_path, path_now)) {
      log_debug("[FILE STORE] Yerel MCP önbelleği hazırlandı: {cached_path}")
    }
	
    if (!grepl("^//[^/]+/[^/]+", gsub("\\", "/", cached_path, fixed = TRUE))) {
      cached_path <- safe_windows_short_path(cached_path, must_exist = path_exists_relaxed(cached_path))
    } else {
      cached_path <- paste0("//", sub("^/+", "", gsub("\\", "/", cached_path, fixed = TRUE)))
    }

    file_obj <- list(
      name = fname,
      datapath = cached_path,
      path = cached_path,
      source_path = path_original
    )

    csf[[fname]] <- file_obj
    if (!is.null(fid)) csf[[fid]] <- file_obj
  }

  session$userData$current_session_files <- csf
  mcp_snapshot <- update_mcp_registry_snapshot_fn(csf)

  if (
    exists("helpers_mcp_tools", inherits = TRUE) &&
    is.function(helpers_mcp_tools$reset_session_file_registry) &&
    is.function(helpers_mcp_tools$register_uploaded_file)
  ) {
    helpers_mcp_tools$reset_session_file_registry(session)
    registered_keys <- character()

    for (key in names(csf)) {
      obj <- csf[[key]]
      if (!is.list(obj)) next

      path_reg <- obj$path %||% obj$datapath
      if (is.null(path_reg) || !nzchar(path_reg) || !path_exists_relaxed(path_reg)) next

      display <- obj$name %||% key
      tokens <- unique(c(key, display))

      for (tk in tokens) {
        if (!nzchar(tk) || tk %in% registered_keys) next

        try(
          helpers_mcp_tools$register_uploaded_file(
            session = session,
            token = tk,
            abs_path = path_reg,
            display_name = display
          ),
          silent = TRUE
        )

        registered_keys <- c(registered_keys, tk)
      }
    }
  }

  if (length(csf)) {
    unique_names <- unique(vapply(csf, function(x) x$name %||% "", character(1)))
    log_debug("[FILE STORE] MCP dosyaları (seçili): {paste(unique_names[nzchar(unique_names)], collapse = ', ')}")
  } else {
    log_debug("[FILE STORE] Filtreleme sonrasında geçerli MCP dosyası yok")
  }

  list(
    current_session_files = csf,
    mcp_snapshot = mcp_snapshot
  )
}