# R/server_speech_assets_runtime.R
# Hibrit konuşma çalışma zamanı: önceden üretilmiş karşılama/sayfa rehberliği
# WAV'larının oturum içi seçimi ve gönderimi, deterministik kişisel karşılama
# öneki (kesin zaman sınırıyla), süreç kapsamlı VoxCPM2 ısındırma tetikleyicisi
# ve chunked_pcm modunda gerçek akış PCM köprüsü. AI Uzman modülü konuşma
# durumunun tek sahibi kalır; bu dosya statik planları o modüle teslim eder.

#' Konuşma performans ölçüm logu (gizli değer içermez).
.speech_perf_log <- function(event, detail = "") {
  cat(sprintf("[SPEECH PERF] %s event=%s %s\n",
              format(Sys.time(), "%H:%M:%S"), event, detail))
}

#' Persona + senaryo için statik oynatma öğesi kur (metin + URL + süre).
.speech_build_static_item <- function(manifest, persona, scenario, page, variant,
                                      root = mergen_speech_root()) {
  asset <- mergen_speech_asset_lookup(manifest, persona, scenario, page, variant)
  if (is.null(asset)) return(NULL)

  rel <- sub("^www/speech/", "", as.character(asset$script_path))
  script_abs <- file.path(root, rel)
  script_text <- .speech_read_utf8_text(script_abs)
  if (is.null(script_text) || !nzchar(script_text)) return(NULL)

  audio_abs <- file.path(root, sub("^www/speech/", "", as.character(asset$audio_path)))
  if (!file.exists(audio_abs)) return(NULL)

  list(
    text = script_text,
    audio_src = mergen_speech_audio_url(persona, scenario, page, variant),
    duration_ms = suppressWarnings(as.numeric(asset$duration_ms))
  )
}

#' Kişisel önek gecikme sınırı (ms).
.speech_prefix_deadline_ms <- function() {
  ms <- suppressWarnings(as.numeric(Sys.getenv("VOXCPM2_PREFIX_DEADLINE_MS", "2500")))
  if (is.na(ms) || ms < 0) ms <- 2500
  ms
}

#' TTS uç noktası için etkin API anahtarını çöz (kişisel > servis > eski).
.speech_resolve_tts_api_key <- function(session) {
  cfg <- get0("tts_config", ifnotfound = list())
  service_key <- cfg$api_key %||% ""
  legacy_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")

  resolver <- get0("mb_api_key_get_feature_key_value", mode = "function")
  if (is.null(resolver)) {
    return(if (nzchar(service_key)) service_key else legacy_key)
  }

  resolver(
    session = session,
    service_key = service_key,
    fallback_key = legacy_key,
    require_auth = TRUE,
    clear_on_mismatch = TRUE,
    prefer_service_key_after_personal = TRUE
  )
}

#' Süreç kapsamlı VoxCPM2 ısındırmasını (bir kez) tetikle. Onaylı referansı
#' olan ilk persona ile küçük bir sentez isteği koşulur; başarısızlık uygulama
#' akışını etkilemez.
.speech_trigger_process_warmup <- function(session) {
  if (!mergen_speech_warmup_should_start()) return(invisible(FALSE))

  starter <- function(on_success, on_failure) {
    ref <- NULL
    for (persona in mergen_speech_personas()) {
      candidate <- mergen_speech_reference_payload(persona)
      if (isTRUE(candidate$ok)) { ref <- candidate; break }
    }
    if (is.null(ref)) {
      on_failure("onaylı persona referansı yok; ısındırma atlandı")
      return(invisible(NULL))
    }

    body <- mergen_voxcpm2_request_body(
      profile = ref$profile, text = "Merhaba.",
      reference = ref, response_format = "wav"
    )

    cfg <- get0("tts_config", ifnotfound = list())
    endpoint <- mergen_voxcpm2_endpoint_url(cfg$base_url %||% NULL)
    api_key <- .speech_resolve_tts_api_key(session)
    timeout_val <- mergen_speech_warmup_timeout()
    verify_ssl <- isTRUE(cfg$verify_ssl %||% TRUE)

    .speech_perf_log("warmup_start", sprintf("persona=%s", ref$persona_id))

    tracked_future_promise(
      task_fn = function() {
        mergen_voxcpm2_synthesize_blocking(
          body = body, endpoint_url = endpoint, api_key = api_key,
          timeout_seconds = timeout_val, verify_ssl = verify_ssl
        )
      },
      task_type = "tts",
      session_token = session$token,
      meta = list(purpose = "voxcpm2_warmup")
    ) %...>% (function(res) {
      if (isTRUE(res$success)) {
        .speech_perf_log("warmup_ready", "")
        on_success()
      } else {
        on_failure(res$error %||% "bilinmeyen hata")
      }
    }) %...!% (function(e) {
      on_failure(conditionMessage(e))
    })

    invisible(NULL)
  }

  mergen_speech_warmup_start_once(starter)
}

#' Hibrit konuşma çalışma zamanını başlat.
#'
#' @param input,session Shiny nesneleri.
#' @param settings_data Merkezi ayarlar.
#' @param ai_expert AI Uzman modülü (konuşma durumu sahibi).
#' @param tts_processor TTS modülü (önek sentezi için).
#' @param current_user_id Canlı kullanıcı kimliği sağlayıcısı.
#' @return Konuşma çalışma zamanı API listesi.
speechAssetsRuntimeInit <- function(input, session, settings_data,
                                    ai_expert, tts_processor,
                                    current_user_id) {

  root <- mergen_speech_root()

  # Önek durumu: nesil sayaçlı tek slot (persona değişimi bayatlatır)
  prefix_slot <- new.env(parent = emptyenv())
  prefix_slot$gen <- 0L
  prefix_slot$persona <- NA_character_
  prefix_slot$status <- "none"     # none | pending | ready | failed
  prefix_slot$text <- ""
  prefix_slot$audio_src <- NULL
  prefix_slot$duration <- 0
  prefix_slot$promise <- NULL

  static_ready <- function(persona) {
    persona <- mergen_speech_canonical_persona(persona)
    if (is.na(persona)) return(FALSE)
    isTRUE(mergen_speech_persona_static_ready(persona, root))
  }

  resolve_user_id <- function() {
    uid <- tryCatch({
      if (is.function(current_user_id)) {
        shiny::isolate(current_user_id())
      } else {
        current_user_id
      }
    }, error = function(e) 0L)
    uid <- suppressWarnings(as.integer(uid))
    if (is.na(uid) || uid < 0L) uid <- 0L
    uid
  }

  build_prefix_text <- function() {
    first_name <- tryCatch(
      session$userData$user_first_name %||% "",
      error = function(e) ""
    )

    topics <- NULL
    uid <- resolve_user_id()
    fetch_fn <- get0("fetch_recent_user_prompts", mode = "function")
    if (uid > 0L && !is.null(fetch_fn)) {
      topics <- tryCatch(fetch_fn(uid, 1), error = function(e) NULL)
    }

    mergen_speech_build_welcome_prefix(first_name, topics)
  }

  send_prefetch <- function(urls) {
    urls <- Filter(nzchar, as.character(urls))
    if (length(urls) == 0) return(invisible(NULL))
    limit <- suppressWarnings(as.integer(Sys.getenv("VOXCPM2_PRELOAD_LIMIT", "3")))
    if (is.na(limit) || limit < 1L) limit <- 3L
    session$sendCustomMessage("speechPrefetch", list(
      urls = as.list(utils::head(urls, limit))
    ))
    invisible(NULL)
  }

  session_is_closed <- function() {
    tryCatch(
      is.function(session$isClosed) && isTRUE(session$isClosed()),
      error = function(e) FALSE
    )
  }

  dispatch_in_session <- function(expr) {
    if (session_is_closed()) return(invisible(NULL))

    # later/promise callbacks do not automatically inherit either a reactive
    # consumer or Shiny's default session domain. Both are needed here:
    # reactiveVal reads require isolate(), while shinyjs resolves its session
    # through getDefaultReactiveDomain().
    shiny::withReactiveDomain(session, {
      shiny::isolate(force(expr))
    })
  }

  # --- Kişisel öneki persona onaylandığı anda hazırlamaya başla ---
  prewarm_welcome <- function(persona_id) {
    persona <- mergen_speech_canonical_persona(persona_id)
    if (is.na(persona)) return(invisible(FALSE))

    prefix_slot$gen <- prefix_slot$gen + 1L
    my_gen <- prefix_slot$gen
    prefix_slot$persona <- persona
    prefix_slot$status <- "none"
    prefix_slot$audio_src <- NULL
    prefix_slot$promise <- NULL

    if (!static_ready(persona)) {
      .speech_perf_log("prewarm_skipped", sprintf("persona=%s statik hazır değil", persona))
      return(invisible(FALSE))
    }

    # Seçilecek karşılama klibini tarayıcı önbelleğine ısıt (torba tüketilmez)
    state <- mergen_speech_state(session)
    peek_variant <- mergen_speech_shuffle_bag_peek(state$bags, "welcome")
    send_prefetch(mergen_speech_audio_url(persona, "welcome", NULL, peek_variant))

    prefix_text <- build_prefix_text()
    if (!nzchar(prefix_text)) return(invisible(FALSE))

    prefix_slot$status <- "pending"
    prefix_slot$text <- prefix_text
    .speech_perf_log("prefix_synth_start", sprintf("persona=%s", persona))

    prefix_promise <- tts_processor$synthesize_speech(prefix_text, persona_id = persona)
    prefix_slot$promise <- prefix_promise

    prefix_promise %...>% (function(res) {
      if (!identical(prefix_slot$gen, my_gen)) return(invisible(NULL))
      if (isTRUE(res$success) && nzchar(res$audio_src %||% "")) {
        prefix_slot$status <- "ready"
        prefix_slot$audio_src <- res$audio_src
        prefix_slot$duration <- res$duration %||% 0
        .speech_perf_log("prefix_ready", sprintf("persona=%s", persona))
      } else {
        prefix_slot$status <- "failed"
      }
    }) %...!% (function(e) {
      if (identical(prefix_slot$gen, my_gen)) prefix_slot$status <- "failed"
    })

    invisible(TRUE)
  }

  # --- Karşılama dizisini (önek + statik WAV) tek konuşma olarak oynat ---
  play_welcome <- function(persona_id) {
    persona <- mergen_speech_canonical_persona(persona_id)
    if (is.na(persona) || !static_ready(persona)) return(FALSE)

    loaded <- mergen_speech_manifest_runtime(root)
    if (!isTRUE(loaded$ok)) return(FALSE)

    state <- mergen_speech_state(session)
    variant <- mergen_speech_shuffle_bag_draw(state$bags, "welcome")
    welcome_item <- .speech_build_static_item(loaded$manifest, persona, "welcome",
                                              NULL, variant, root)
    if (is.null(welcome_item)) return(FALSE)

    dispatch_guard <- new.env(parent = emptyenv())
    dispatch_guard$done <- FALSE

    dispatch <- function(include_prefix) {
      if (isTRUE(dispatch_guard$done)) return(invisible(NULL))
      dispatch_guard$done <- TRUE
      if (session_is_closed()) return(invisible(NULL))

      # Karşılama yalnızca sohbet/başlangıç yüzeyinde geçerlidir: gönderim
      # anında kontrol. Gecikmeli (deadline) gönderim penceresinde kullanıcı
      # sohbetten ayrılıp rehberli bir sayfaya (ör. Dosya Yönetimi) geçtiyse,
      # yalnızca sessiz sayfaları değil sohbet DIŞINDAKİ her yüzeyi bastır ki
      # karşılama, o sayfanın rehberlik klibini önüne geçip kesmesin.
      current_tab <- tryCatch(shiny::isolate(input$tabs), error = function(e) NULL)
      if (!is.null(current_tab) && nzchar(current_tab) &&
          !identical(current_tab, "chat")) {
        .speech_perf_log("welcome_suppressed", sprintf("page=%s", current_tab))
        return(invisible(NULL))
      }

      items <- list(welcome_item)
      if (isTRUE(include_prefix) &&
          identical(prefix_slot$status, "ready") &&
          identical(prefix_slot$persona, persona)) {
        items <- list(
          list(text = prefix_slot$text, audio_src = prefix_slot$audio_src,
               duration_ms = (prefix_slot$duration %||% 0) * 1000),
          welcome_item
        )
      }

      .speech_perf_log("welcome_dispatch", sprintf(
        "persona=%s variant=%d prefix=%s", persona, variant,
        if (length(items) > 1) "evet" else "hayır"
      ))

      dispatch_in_session(
        ai_expert$start_speaking(
          items[[1]]$text,
          cooldown_secs = ai_expert$COOLDOWN_GREETING,
          kind = "welcome",
          static_plan = list(items = items)
        )
      )
      invisible(NULL)
    }

    if (identical(prefix_slot$status, "ready") &&
        identical(prefix_slot$persona, persona)) {
      dispatch(TRUE)
    } else if (identical(prefix_slot$status, "pending") &&
               identical(prefix_slot$persona, persona) &&
               !is.null(prefix_slot$promise)) {
      # Önek hazırsa onunla, süre sınırında değilse öneksiz başlat
      deadline_secs <- .speech_prefix_deadline_ms() / 1000
      later::later(function() dispatch(FALSE), delay = deadline_secs)
      prefix_slot$promise %...>% (function(res) dispatch(TRUE)) %...!%
        (function(e) dispatch(FALSE))
    } else {
      dispatch(FALSE)
    }

    TRUE
  }

  # --- Sayfa rehberliği: statik varlık, LLM yok ---
  play_page_guidance <- function(page) {
    if (!identical(mergen_speech_guidance_policy(page), "guided")) return(FALSE)

    persona <- mergen_speech_canonical_persona(
      shiny::isolate(settings_data$selected_character)
    )
    if (is.na(persona) || !static_ready(persona)) return(FALSE)

    loaded <- mergen_speech_manifest_runtime(root)
    if (!isTRUE(loaded$ok)) return(FALSE)

    state <- mergen_speech_state(session)
    bag_key <- sprintf("page:%s", page)
    variant <- mergen_speech_shuffle_bag_draw(state$bags, bag_key)

    item <- .speech_build_static_item(loaded$manifest, persona, "page_guidance",
                                      page, variant, root)
    if (is.null(item)) return(FALSE)

    .speech_perf_log("guidance_dispatch", sprintf(
      "page=%s persona=%s variant=%d", page, persona, variant
    ))

    dispatch_in_session(
      ai_expert$start_speaking(
        item$text,
        cooldown_secs = ai_expert$COOLDOWN_PAGE,
        kind = "page_guidance",
        static_plan = list(items = list(item))
      )
    )

    # Tüketilen klipten sonra bu sayfanın SIRADAKİ adayını önden ısıt
    next_variant <- mergen_speech_shuffle_bag_peek(state$bags, bag_key)
    send_prefetch(mergen_speech_audio_url(persona, "page_guidance", page, next_variant))

    TRUE
  }

  # Isındırmayı hızlı başlangıç şeridini bloklamadan, oturum kurulumundan
  # sonra ertelenmiş olarak tetikle (süreçte yalnızca ilk oturum başlatır).
  later::later(function() {
    tryCatch(.speech_trigger_process_warmup(session), error = function(e) {
      cat(sprintf("[SPEECH] Isındırma tetikleyici hatası: %s\n", conditionMessage(e)))
    })
  }, delay = 3)

  list(
    static_ready = static_ready,
    prewarm_welcome = prewarm_welcome,
    play_welcome = play_welcome,
    play_page_guidance = play_page_guidance
  )
}
