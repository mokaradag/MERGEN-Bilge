# ==============================================================================
# Dosya Yolu: R/server_chat_engine_dependencies.R
# Açıklama: Sohbet motoru için server.R ile server_module_wiring.R arasında
#           taşınan dış bağımlılıkları küçük ve doğrulanabilir bir bundle altında
#           toplar. Runtime state/cache/file/chat bağlamı runtime_ctx içinde kalır.
# ==============================================================================

.server_wiring_require_chat_engine_deps <- function(chat_engine_deps) {
  if (!is.list(chat_engine_deps)) {
    .server_wiring_stop(
      "chat_engine_deps liste olmalıdır."
    )
  }

  .server_runtime_require_values(
    chat_engine_deps,
    c(
      "settings_data",
      "api_key",
      "user_config_rv",
      "perf_tracker",
      "ai_processor",
      "tts_processor",
      "tts_visualizer",
      "stt_data",
      "saved_chats_data",
      "send_message_fns",
      "send_message_proxy",
      "api_config"
    ),
    "chat_engine_deps"
  )

  .server_wiring_require_environment(
    chat_engine_deps$send_message_fns,
    "chat_engine_deps$send_message_fns"
  )

  .server_wiring_require_functions(list(
    send_message_proxy = chat_engine_deps$send_message_proxy,
    perf_tracker_track_error = chat_engine_deps$perf_tracker$track_error,
    perf_tracker_track_request = chat_engine_deps$perf_tracker$track_request,
    ai_processor_call_llm_non_streaming = chat_engine_deps$ai_processor$call_llm_non_streaming
  ))

  invisible(TRUE)
}

serverBuildChatEngineDependencyBundle <- function(settings_data,
                                                  api_key,
                                                  user_config_rv,
                                                  perf_tracker,
                                                  saved_chats_data,
                                                  send_message_fns,
                                                  send_message_proxy,
                                                  api_config,
                                                  media_modules = NULL,
                                                  ai_processor = NULL,
                                                  tts_processor = NULL,
                                                  tts_visualizer = NULL,
                                                  stt_data = NULL,
                                                  admin_pool = NULL,
                                                  feedback_modal = NULL) {
  if (!is.null(media_modules)) {
    if (is.null(ai_processor)) {
      ai_processor <- media_modules$ai_processor
    }

    if (is.null(tts_processor)) {
      tts_processor <- media_modules$tts_processor
    }

    if (is.null(tts_visualizer)) {
      tts_visualizer <- media_modules$tts_visualizer
    }

    if (is.null(stt_data)) {
      stt_data <- media_modules$stt_data
    }

    if (is.null(feedback_modal)) {
      feedback_modal <- media_modules$feedback_modal
    }
  }

  chat_engine_deps <- list(
    settings_data = settings_data,
    api_key = api_key,
    user_config_rv = user_config_rv,
    perf_tracker = perf_tracker,
    ai_processor = ai_processor,
    tts_processor = tts_processor,
    tts_visualizer = tts_visualizer,
    stt_data = stt_data,
    saved_chats_data = saved_chats_data,
    send_message_fns = send_message_fns,
    send_message_proxy = send_message_proxy,
    api_config = api_config,
    admin_pool = admin_pool,
    feedback_modal = feedback_modal
  )

  .server_wiring_require_chat_engine_deps(chat_engine_deps)

  class(chat_engine_deps) <- c(
    "mergen_chat_engine_dependency_bundle",
    "list"
  )

  chat_engine_deps
}

.server_wiring_resolve_chat_engine_deps <- function(chat_engine_deps,
                                                    settings_data,
                                                    api_key,
                                                    user_config_rv,
                                                    perf_tracker,
                                                    saved_chats_data,
                                                    send_message_fns,
                                                    send_message_proxy,
                                                    api_config,
                                                    media_modules = NULL,
                                                    ai_processor = NULL,
                                                    tts_processor = NULL,
                                                    tts_visualizer = NULL,
                                                    stt_data = NULL,
                                                    admin_pool = NULL,
                                                    feedback_modal = NULL) {
  if (!is.null(chat_engine_deps)) {
    .server_wiring_require_chat_engine_deps(chat_engine_deps)
    return(chat_engine_deps)
  }

  serverBuildChatEngineDependencyBundle(
    settings_data = settings_data,
    api_key = api_key,
    user_config_rv = user_config_rv,
    perf_tracker = perf_tracker,
    saved_chats_data = saved_chats_data,
    send_message_fns = send_message_fns,
    send_message_proxy = send_message_proxy,
    api_config = api_config,
    media_modules = media_modules,
    ai_processor = ai_processor,
    tts_processor = tts_processor,
    tts_visualizer = tts_visualizer,
    stt_data = stt_data,
    admin_pool = admin_pool,
    feedback_modal = feedback_modal
  )
}

# =============================================================================
# PR #695 — Derin analiz ve Ortak Oturum Codex çalışma zamanı düzeltmeleri
# =============================================================================
.pk_hook_same_connection_list <- function(left, right) {
  if (is.null(left) || is.null(right)) return(FALSE)
  if (!is.list(left) || !is.list(right)) return(identical(left, right))
  identical(left$conn %||% NULL, right$conn %||% NULL)
}

# Derin analiz henüz server_init_chat_runtime.R giriş-iptal sarmalayıcısını
# almadan önce çekirdeği sarılır. İlk bağlantı yalnızca RLS kimlik okumasına
# kadar yaşar; gözlem çağrıları kısa ömürlü telemetri bağlantıları kullanır.
if (exists("pk_deep_analysis_process", mode = "function", inherits = TRUE) &&
    !exists(".pk_hook_deep_core", inherits = FALSE)) {

  .pk_hook_deep_core <- get(
    "pk_deep_analysis_process", mode = "function", inherits = TRUE
  )
  .pk_hook_deep_core_env <- environment(.pk_hook_deep_core)
  .pk_hook_real_get_connection <- get(
    "get_connection", mode = "function", envir = .pk_hook_deep_core_env, inherits = TRUE
  )
  .pk_hook_real_release_connection <- get(
    "release_connection", mode = "function", envir = .pk_hook_deep_core_env, inherits = TRUE
  )
  .pk_hook_real_get_user_rls_info <- get(
    "get_user_rls_info", mode = "function", envir = .pk_hook_deep_core_env, inherits = TRUE
  )
  .pk_hook_real_pk_analysis_observe <- get(
    "pk_analysis_observe", mode = "function", envir = .pk_hook_deep_core_env, inherits = TRUE
  )

  pk_deep_analysis_process <- function(user_prompt, chat_history, session,
                                       detail_level = "standart",
                                       stop_check = NULL) {
    request_id <- .pk_hook_current_request_id(session)
    on.exit(
      try(pk_filter_observation_clear(request_id, user_prompt), silent = TRUE),
      add = TRUE
    )

    state <- new.env(parent = emptyenv())
    state$primary <- NULL
    state$primary_released <- FALSE

    call_env <- new.env(parent = .pk_hook_deep_core_env)

    # `target` SARMALAYICIDA DA KABUL EDİLİR VE İLETİLİR.
    #
    # Gerçek `get_connection(target = "primary")` imzasını taşımayan bir
    # sarmalayıcı, hedef belirten her çağrıda "unused argument" ile düşerdi.
    # Yalnızca BİRİNCİL bağlantı yaşam döngüsü izlenir; ikincil/üçüncül hedefler
    # çağıranın kendi `release_connection()` sözleşmesine tabidir.
    call_env$get_connection <- function(target = "primary") {
      conn_list <- .pk_hook_real_get_connection(target)
      if (identical(target, "primary") && is.null(state$primary)) {
        state$primary <- conn_list
      }
      conn_list
    }

    call_env$release_connection <- function(conn_list) {
      is_primary <- .pk_hook_same_connection_list(conn_list, state$primary)
      if (is_primary && isTRUE(state$primary_released)) {
        return(invisible(NULL))
      }
      if (is_primary) state$primary_released <- TRUE
      .pk_hook_real_release_connection(conn_list)
    }

    call_env$get_user_rls_info <- function(username, conn) {
      on.exit({
        if (!is.null(state$primary) && !isTRUE(state$primary_released)) {
          try(call_env$release_connection(state$primary), silent = TRUE)
        }
      }, add = TRUE)
      .pk_hook_real_get_user_rls_info(username, conn)
    }

    call_env$pk_analysis_observe <- function(session, conn, info) {
      telemetry_list <- tryCatch(
        .pk_hook_real_get_connection(),
        error = function(e) NULL
      )
      telemetry_conn <- if (is.list(telemetry_list)) {
        telemetry_list$conn %||% NULL
      } else {
        NULL
      }
      if (!is.null(telemetry_list)) {
        on.exit(
          try(.pk_hook_real_release_connection(telemetry_list), silent = TRUE),
          add = TRUE
        )
      }
      .pk_hook_real_pk_analysis_observe(session, telemetry_conn, info)
    }

    core <- .pk_hook_deep_core
    environment(core) <- call_env
    core(
      user_prompt = user_prompt,
      chat_history = chat_history,
      session = session,
      detail_level = detail_level,
      stop_check = stop_check
    )
  }
}

# YETKİLİ ALT BİLGİ MODEL METNİNE GÖRE BASTIRILMAZ.
#
# Eski metin tabanlı idempotentlik denetimi (`grepl("**Analiz Kaynağı", ...)`)
# modelin KENDİ yazdığı ya da istem enjeksiyonuyla ürettiği bir başlığı
# "footer zaten var" sanıp R'ye ait YETKİLİ alt bilgiyi DÜŞÜRÜYORDU. Kayıt bu
# noktada ZATEN tüketilmiştir, yani daha sonra teslim edilme şansı da yoktur:
# kullanıcıya yalnızca MODEL DENETİMİNDEKİ kaynak bölümü kalırdı.
#
# İdempotentlik BANT DIŞI sağlanır: `provenance_store` girdisi `istek_id`
# anahtarıyla tutulur ve okunduğu anda SİLİNİR (bkz. `motor$tamamla`
# sarmalayıcısı) — `pk_provenance_decorate()` ile aynı sözleşme.
.pk_hook_room_footer_append <- function(text, footer) {
  footer <- .pk_hook_scalar_text(footer)
  if (!nzchar(footer)) return(text)
  paste0(.pk_hook_scalar_text(text), footer)
}

.pk_hook_room_footer_publish <- function(footer) {
  footer <- .pk_hook_scalar_text(footer)
  if (!nzchar(footer)) return(invisible(FALSE))

  for (frame in rev(sys.frames())) {
    has_store <- exists(".pk_room_provenance_store", envir = frame, inherits = FALSE)
    has_key <- exists(".pk_room_provenance_key", envir = frame, inherits = FALSE)
    if (!has_store || !has_key) next

    store <- get(".pk_room_provenance_store", envir = frame, inherits = FALSE)
    key <- .pk_hook_scalar_text(get(
      ".pk_room_provenance_key", envir = frame, inherits = FALSE
    ))
    if (is.environment(store) && nzchar(key)) {
      assign(key, footer, envir = store)
      return(invisible(TRUE))
    }
  }

  invisible(FALSE)
}

# Sentetik oda session'ındaki köken alt bilgisi açıkça köprü dönüşüne eklenir
# ve aynı istek için Ortak Oturum üretim deposuna yayınlanır.
if (exists("oo_arac_sql_baglami_kur", mode = "function", inherits = TRUE) &&
    !exists(".pk_hook_room_sql_core", inherits = FALSE)) {

  .pk_hook_room_sql_core <- get(
    "oo_arac_sql_baglami_kur", mode = "function", inherits = TRUE
  )

  oo_arac_sql_baglami_kur <- function(soru, gecmis, oda_session, arac_meta) {
    result <- .pk_hook_room_sql_core(soru, gecmis, oda_session, arac_meta)
    footer <- if (exists("pk_provenance_take", mode = "function", inherits = TRUE)) {
      tryCatch(pk_provenance_take(oda_session), error = function(e) NULL)
    } else {
      NULL
    }

    footer <- .pk_hook_scalar_text(footer)
    if (is.list(result) && nzchar(footer)) {
      result$provenance_footer <- footer
      .pk_hook_room_footer_publish(footer)
    }
    result
  }
}

# Her Ortak Oturum isteği için küçük bir alt-bilgi deposu kurulur. Doğrudan
# yanıt ve asenkron model yanıtı aynı motor$tamamla sınırında tek kez süslenir.
if (exists("ortakOturumYzBind", mode = "function", inherits = TRUE) &&
    !exists(".pk_hook_room_bind_core", inherits = FALSE)) {

  .pk_hook_room_bind_core <- get(
    "ortakOturumYzBind", mode = "function", inherits = TRUE
  )

  ortakOturumYzBind <- function(input, output, session, ctx, motor) {
    result <- .pk_hook_room_bind_core(input, output, session, ctx, motor)

    provenance_store <- new.env(parent = emptyenv())
    original_llm <- motor$llm_uret
    original_finish <- motor$tamamla

    if (is.function(original_llm)) {
      motor$llm_uret <- function(oturum_id, soru_id, soran_id, istek_id,
                                 kuyruk_id = NULL, persona_kimligi = NULL) {
        .pk_room_provenance_store <- provenance_store
        .pk_room_provenance_key <- .pk_hook_scalar_text(istek_id)
        original_llm(
          oturum_id = oturum_id,
          soru_id = soru_id,
          soran_id = soran_id,
          istek_id = istek_id,
          kuyruk_id = kuyruk_id,
          persona_kimligi = persona_kimligi
        )
      }
    }

    if (is.function(original_finish)) {
      motor$tamamla <- function(oturum_id, soru_id, istek_id,
                                yanit_metni = NULL, hata_metni = NULL,
                                kuyruk_id = NULL, soran_id = NULL,
                                persona_id = NULL) {
        key <- .pk_hook_scalar_text(istek_id)
        footer <- if (nzchar(key) &&
                      exists(key, envir = provenance_store, inherits = FALSE)) {
          value <- get(key, envir = provenance_store, inherits = FALSE)
          rm(list = key, envir = provenance_store)
          value
        } else {
          NULL
        }

        # Alt bilgi TEK terminal metne eklenir; yanıt varsa ona, yoksa hataya.
        if (!is.null(yanit_metni)) {
          yanit_metni <- .pk_hook_room_footer_append(yanit_metni, footer)
        } else if (!is.null(hata_metni)) {
          hata_metni <- .pk_hook_room_footer_append(hata_metni, footer)
        }

        original_finish(
          oturum_id = oturum_id,
          soru_id = soru_id,
          istek_id = istek_id,
          yanit_metni = yanit_metni,
          hata_metni = hata_metni,
          kuyruk_id = kuyruk_id,
          soran_id = soran_id,
          persona_id = persona_id
        )
      }
    }

    result
  }
}
