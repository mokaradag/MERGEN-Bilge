# ==============================================================================
# Dosya Yolu: R/server_init_chat_runtime.R
# Açıklama: server.R içinde kullanılan sohbet çalışma zamanı yardımcılarını
#           kurar. Mesaj ekleme, durum sıfırlama, başlık üretme ve simüle
#           streaming sarmalayıcılarını tek yerde toplar.
# ==============================================================================

serverInitChatRuntime <- function(session, values, settings_data, output,
                                  resolve_current_user_id, stop_generation) {

  # ---------------------------------------------------------------------------
  # Sohbet durumunu sıfırlayan yardımcı
  # ---------------------------------------------------------------------------
  reset_chat_state <- function() {
    chat_reset_state(session, values)
  }

  # ---------------------------------------------------------------------------
  # Oturumun etkin kullanıcı kimliği ile mesaj ekleyen yardımcı
  # ---------------------------------------------------------------------------
  add_message <- function(content, type = "user", html = NULL, followups = NULL,
                          audio_src = NULL, audio_voice = NULL,
                          reasoning_content = NULL) {

    # SQL analizinin doğrudan dönen karakter/hata yanıtları normal LLM
    # sonlandırıcılarına uğramaz. Mesaj ekleme sınırı, bekleyen köken alt
    # bilgisini bütün AI yanıtlarında son bir kez ve idempotent biçimde tüketir.
    if ((identical(type, "ai") || identical(type, "assistant")) &&
        exists("pk_provenance_decorate", mode = "function", inherits = TRUE)) {
      content <- pk_provenance_decorate(content, session)
    }

    effective_user_id <- resolve_current_user_id()

    chat_add_message(
      session = session,
      values = values,
      settings_data = settings_data,
      output = output,
      content = content,
      type = type,
      html = html,
      current_user_id = effective_user_id,
      followups = followups,
      audio_src = audio_src,
      audio_voice = audio_voice,
      reasoning_content = reasoning_content
    )
  }

  # ---------------------------------------------------------------------------
  # Sohbet başlığı üreten yardımcı
  # ---------------------------------------------------------------------------
  generate_title_from_prompt <- function(prompt, max_len = 60) {
    chat_generate_title_from_prompt(prompt, max_len)
  }

  # ---------------------------------------------------------------------------
  # Simüle streaming sarmalayıcısı
  # ---------------------------------------------------------------------------
  simulate_streaming_stoppable <- function(full_response, followups = NULL,
                                           on_complete = NULL, on_start = NULL,
                                           tts_engine = NULL, tts_voice = NULL) {
    chat_simulate_streaming(
      full_response = full_response,
      session = session,
      values = values,
      settings_data = settings_data,
      output = output,
      stop_generation = stop_generation,
      followups = followups,
      on_complete = on_complete,
      on_start = on_start,
      tts_engine = tts_engine,
      tts_voice = tts_voice
    )
  }

  list(
    reset_chat_state = reset_chat_state,
    add_message = add_message,
    generate_title_from_prompt = generate_title_from_prompt,
    simulate_streaming_stoppable = simulate_streaming_stoppable
  )
}

# ==============================================================================
# Proje/Kaynak Analizi — doğrudan çıkış gözlem güvenlik ağı
# ==============================================================================
# module_proje_kaynak_analizi.R bu dosyadan önce yüklenir. Ana analiz motoru,
# filtre aşamasına ulaşan sonuçları kendi bağlamında gözlemler. Aşağıdaki ince
# sarmalayıcı yalnızca motorun doğrudan döndüğü ve henüz köken alt bilgisi
# bırakmadığı çıkışları (başlangıç durdurma, kimlik/yetki, eşleşme yok, SQL ve
# yapılandırma hataları ile beklenmeyen istisnalar) tamamlar. Böylece başarılı
# yolların telemetrisi yinelenmez.
if (exists("pk_analiz_process_request", mode = "function", inherits = TRUE) &&
    !exists(".pk_analiz_process_request_without_exit_observer", inherits = FALSE)) {

  .pk_analiz_process_request_without_exit_observer <- get(
    "pk_analiz_process_request", mode = "function", inherits = TRUE
  )

  pk_analiz_process_request <- function(user_prompt, chat_history, session,
                                        stop_check = NULL) {
    started_at <- Sys.time()
    caught_error <- NULL
    result <- tryCatch(
      .pk_analiz_process_request_without_exit_observer(
        user_prompt = user_prompt,
        chat_history = chat_history,
        session = session,
        stop_check = stop_check
      ),
      error = function(e) {
        caught_error <<- e
        e
      }
    )

    is_exception <- inherits(result, "condition")
    is_direct_exit <- is_exception || is.character(result) ||
      (is.list(result) && identical(result$type, "error_message"))
    if (!isTRUE(is_direct_exit)) return(result)

    # Motorun RLS-sıfır/filtre-sıfır gibi zaten gözlediği doğrudan yanıtlarında
    # bekleyen bir alt bilgi vardır. Onları ikinci kez yazma.
    has_pending_footer <- tryCatch(
      !is.null(session$userData$pk_provenance_pending),
      error = function(e) FALSE
    )
    if (isTRUE(has_pending_footer)) {
      if (is_exception) stop(caught_error)
      return(result)
    }

    # Windows SSO başlangıcında kimlik henüz kesinleşmemişken ana motor bilinçli
    # olarak DB bağlantısı açmadan "kimlik hazırlanıyor" yanıtı döndürür. Bu
    # güvenlik ağı o sınırı telemetri uğruna delmemelidir.
    auth_pending <- tryCatch(
      identical(session$userData$auth_initialized, FALSE),
      error = function(e) FALSE
    )
    if (isTRUE(auth_pending)) {
      if (is_exception) stop(caught_error)
      return(result)
    }

    if (!exists("pk_analysis_observe", mode = "function", inherits = TRUE)) {
      if (is_exception) stop(caught_error)
      return(result)
    }

    response_text <- if (is_exception) {
      conditionMessage(result)
    } else if (is.character(result)) {
      as.character(result)[1]
    } else {
      as.character(result$content %||% "")[1]
    }
    if (is.na(response_text)) response_text <- ""

    stopped <- grepl("İşlem Durduruldu", response_text, fixed = TRUE)
    unauthorized <- grepl("Yetki Hatası", response_text, fixed = TRUE)
    no_match <- grepl("mevcut analiz kütüphanesinde bulunamadı", response_text, fixed = TRUE)

    outcome <- if (stopped) {
      "Durduruldu"
    } else if (unauthorized) {
      "Yetkisiz"
    } else if (no_match) {
      "EslesmeYok"
    } else {
      "Hata"
    }

    request_id <- if (exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
      tryCatch(pk_provenance_current_request_id(session), error = function(e) NULL)
    } else {
      NULL
    }

    username <- tryCatch(
      session$userData$system_username %||%
        session$userData$username %||%
        session$userData$user_name %||%
        "Unknown",
      error = function(e) "Unknown"
    )
    user_id <- tryCatch(session$userData$user_id %||% NULL, error = function(e) NULL)

    conn_list <- tryCatch(get_connection(), error = function(e) NULL)
    conn <- if (is.list(conn_list)) conn_list$conn %||% NULL else NULL
    if (!is.null(conn_list)) {
      on.exit(try(release_connection(conn_list), silent = TRUE), add = TRUE)
    }

    try(
      pk_analysis_observe(session, conn, list(
        request_id = request_id,
        question = user_prompt,
        username = username,
        user_id = user_id,
        deep_thinking = FALSE,
        query_name = "Tekil analiz",
        filter_status = if (stopped) "stopped" else "not_reached",
        filters = list(),
        outcome = outcome,
        duration_ms = as.numeric(difftime(Sys.time(), started_at, units = "secs")) * 1000
      )),
      silent = TRUE
    )

    if (is_exception) stop(caught_error)
    result
  }
}

# ==============================================================================
# Derin analiz — giriş anındaki iptali gözlemle
# ==============================================================================
# Derin analiz motorunun kendi gözlemcisi ilk stop_check() dönüşünden sonra
# kuruluyordu. Bu ince sarmalayıcı yalnızca çağrı girişinde zaten iptal edilmiş
# istekleri yakalar; diğer bütün yolları değiştirmeden asıl motora devreder.
if (exists("pk_deep_analysis_process", mode = "function", inherits = TRUE) &&
    !exists(".pk_deep_analysis_process_without_entry_observer", inherits = FALSE)) {

  .pk_deep_analysis_process_without_entry_observer <- get(
    "pk_deep_analysis_process", mode = "function", inherits = TRUE
  )

  pk_deep_analysis_process <- function(user_prompt, chat_history, session,
                                       detail_level = "standart",
                                       stop_check = NULL) {
    entry_stopped <- is.function(stop_check) && isTRUE(stop_check())
    if (!isTRUE(entry_stopped)) {
      return(.pk_deep_analysis_process_without_entry_observer(
        user_prompt = user_prompt,
        chat_history = chat_history,
        session = session,
        detail_level = detail_level,
        stop_check = stop_check
      ))
    }

    # SSO kimliği bekleniyorsa iptal yanıtı DB erişimi başlatmamalıdır. Kimlik
    # hazır olduğunda ise iptal hem telemetriye hem köken alt bilgisine yazılır.
    auth_pending <- tryCatch(
      identical(session$userData$auth_initialized, FALSE),
      error = function(e) FALSE
    )
    if (!isTRUE(auth_pending) &&
        exists("pk_analysis_observe", mode = "function", inherits = TRUE)) {
      started_at <- Sys.time()
      request_id <- if (exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
        tryCatch(pk_provenance_current_request_id(session), error = function(e) NULL)
      } else {
        NULL
      }
      username <- tryCatch(
        session$userData$system_username %||%
          session$userData$username %||%
          session$userData$user_name %||%
          "Unknown",
        error = function(e) "Unknown"
      )
      user_id <- tryCatch(session$userData$user_id %||% NULL, error = function(e) NULL)

      conn_list <- tryCatch(get_connection(), error = function(e) NULL)
      conn <- if (is.list(conn_list)) conn_list$conn %||% NULL else NULL
      if (!is.null(conn_list)) {
        on.exit(try(release_connection(conn_list), silent = TRUE), add = TRUE)
      }

      try(
        pk_analysis_observe(session, conn, list(
          request_id = request_id,
          question = user_prompt,
          username = username,
          user_id = user_id,
          deep_thinking = TRUE,
          query_name = "Derin analiz",
          filter_status = "stopped",
          filters = list(),
          outcome = "Durduruldu",
          duration_ms = as.numeric(difftime(Sys.time(), started_at, units = "secs")) * 1000
        )),
        silent = TRUE
      )
    }

    "\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi."
  }
}
