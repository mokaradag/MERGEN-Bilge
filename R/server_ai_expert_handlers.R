# R/server_ai_expert_handlers.R
# Dosya Yolu: R/server_ai_expert_handlers.R
# Açıklama: AI Uzman (AI Expert) sunucu tarafındaki işleyiciler.
#            Karşılama, sayfa rehberliği, boşta konuşma ve kullanıcı adıyla
#            kişiselleştirilmiş etkileşim mantığını yönetir.
#            Yarış durumu (race condition) önleme mekanizmalarını içerir.
#            Boşta konuşma zinciri her zaman yeniden planlanır (kırılmaz).
#            Sayfa rehberliği gecikmesiz başlatılır (LLM çağrısı hemen tetiklenir).

#' AI Uzman İşleyicilerini Başlat
#'
#' @description AI Uzman konuşma tetikleyicilerini ve observer'larını kurar.
#'   Karşılama, sayfa rehberliği ve boşta kalma konuşmaları yönetilir.
#'   Kullanıcının adı DB'den alınarak kişiselleştirilmiş deneyim sağlanır.
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param ai_expert AI Uzman modülü (module_ai_expert.R'den)
#' @param tts_processor TTS işleme modülü
#' @param current_user_id Mevcut kullanıcı ID'si
#' @return Görünmez NULL
aiExpertHandlersInit <- function(input, session, values, settings_data,
                                  ai_expert, tts_processor,
                                  current_user_id, chat_history_rv = NULL) {

  # --- Durum değişkenleri ---
  greeting_done     <- reactiveVal(FALSE)
  visited_pages     <- reactiveVal(character(0))  # Ziyaret edilen sayfalar
  idle_timer_active <- reactiveVal(FALSE)          # Boşta zamanlayıcısı aktif mi
  last_page_talk_time <- reactiveVal(NULL)         # Son sayfa konuşma zamanı
  idle_talk_counter <- reactiveVal(0L)             # Boşta konuşma sayacı (tekrar önleme)

  # Karşılama için önceden hazırlanmış bağlam önbelleği
  greeting_prefetch_result  <- reactiveVal(NULL)
  greeting_prefetch_started <- reactiveVal(FALSE)

  # Kullanıcı adı (DB'den alınacak)
  user_first_name <- session$userData$user_first_name %||% ""

  # Boşta konuşma arası (ms) - ayarlardan okunur
  IDLE_INTERVAL_MS   <- 35000   # 35 saniye (varsayılan, ayarlarla güncellenir)
  # Karşılama sonrası ilk boşta konuşma bekleme süresi (ms)
  FIRST_IDLE_DELAY_MS <- 20000  # 20 saniye

  # Sıklık ayarına göre interval hesapla
  get_idle_interval <- function() {
    freq <- isolate(settings_data$ai_expert_talk_frequency) %||% "orta"
    switch(freq,
      "az"  = 60000,  # 60 saniye
      "orta" = 35000, # 35 saniye
      "sik" = 20000,  # 20 saniye
      35000
    )
  }

  # --- Yardımcı: Temel konuşabilirlik kontrolü (bekleme süresini ATLAR) ---
  # Sayfa rehberliği gibi kullanıcı eylemine doğrudan yanıt verilen durumlarda kullanılır
  can_speak_basic <- function() {
    if (!isTRUE(settings_data$enable_ai_expert)) return(FALSE)
    if (!identical(settings_data$experience_mode, "kesif")) return(FALSE)
    if (isTRUE(ai_expert$is_speaking())) return(FALSE)
    if (isTRUE(isolate(values$is_sending))) return(FALSE)
    return(TRUE)
  }

  # --- Yardımcı: Ortak LLM çağrı parametrelerini hazırla ---
	prepare_llm_params <- function() {
	  char_id <- isolate(settings_data$selected_character) %||% "mergen"
	  model_name <- safe_trimws(Sys.getenv("AI_EXPERT_MODEL", ""))
	  endpoint <- safe_trimws(Sys.getenv("LOCAL_LLM_ENDPOINT", ""))
	  api_key <- safe_trimws(Sys.getenv("LOCAL_LLM_API_KEY", ""))
	  user_api_key <- NULL

	  if (!is.null(session$userData$ai_api_key)) {
		user_api_key <- safe_trimws(session$userData$ai_api_key)
	  }

	  final_api_key <- if (!is.null(user_api_key) && safe_nzchar(user_api_key)) user_api_key else api_key

	  chars_data <- get_characters_data()
	  char_info <- Find(function(x) x$id == char_id, chars_data$styles)
	  if (is.null(char_info)) char_info <- chars_data$styles[[1]]

	  list(
		char_info = char_info,
		model_name = model_name,
		endpoint = endpoint,
		api_key = final_api_key,
		user_name = safe_trimws(user_first_name)
	  )
	}

  # --- Yardımcı: Mevcut oturumdaki kullanıcı mesajlarını yakala ---
  capture_session_messages <- function(max_messages = 5) {
    tryCatch({
      if (!is.null(chat_history_rv)) {
        history <- isolate(chat_history_rv())
        if (is.list(history) && length(history) > 0) {
          # Sadece kullanıcı mesajlarını filtrele
          user_msgs <- Filter(function(m) {
            identical(m$role, "user") && !is.null(m$content) && nzchar(m$content)
          }, history)
          # Son max_messages mesajı al (en yeni sondan)
          if (length(user_msgs) > max_messages) {
            user_msgs <- tail(user_msgs, max_messages)
          }
		  return(normalize_utf8_text(sapply(user_msgs, function(m) m$content)))
        }
      }
      return(NULL)
    }, error = function(e) {
      cat(sprintf("[AI_EXPERT] Oturum mesajları yakalanamadı: %s\n", conditionMessage(e)))
      return(NULL)
    })
  }

  # --- Yardımcı: Kullanıcı adını worker içinde çözümle ---
	resolve_user_name <- function(user_name) {
	  user_full_name <- safe_trimws(fetch_user_full_name(current_user_id))
	  u_name <- safe_trimws(user_name)

	  if (safe_nzchar(user_full_name)) {
		parts <- strsplit(user_full_name, "\\s+")[[1]]
		first_name <- safe_trimws(parts[1] %||% "")
		if (safe_nzchar(first_name)) {
		  u_name <- first_name
		}
	  }

	  u_name
	}

  # --- Karşılama bağlamını önceden hazırla ---
  start_greeting_prefetch <- function(force = FALSE) {
    if (!force && isTRUE(greeting_prefetch_started())) return(invisible(NULL))
    if (!isTRUE(settings_data$enable_ai_expert)) return(invisible(NULL))
    if (!identical(settings_data$experience_mode, "kesif")) return(invisible(NULL))

    greeting_prefetch_started(TRUE)

    params <- prepare_llm_params()
    user_id <- current_user_id
    talk_length_val <- isolate(settings_data$ai_expert_talk_length) %||% "orta"
    talk_style_val <- isolate(settings_data$ai_expert_talk_style) %||% "profesyonel"

    promises::future_promise({
      last_login <- fetch_user_last_login(user_id)
      u_name <- resolve_user_name(params$user_name)

      user_context <- build_ai_expert_user_context(
        user_id,
        user_name = u_name,
        last_login_date = last_login,
        include_recent_prompts = TRUE,
        max_prompts = 5
      )

      system_prompt <- build_ai_expert_system_prompt(
        params$char_info,
        scenario = "greeting",
        user_name = u_name,
        talk_length = talk_length_val,
        talk_style = talk_style_val
      )

      list(
        user_context = user_context,
        system_prompt = system_prompt,
        model_name = params$model_name,
        api_key = params$api_key,
        endpoint = params$endpoint
      )
    }) %...>% (function(prefetched) {
      greeting_prefetch_result(prefetched)
      cat("[AI_EXPERT] Karşılama bağlamı önceden hazırlandı.\n")
    }) %...!% (function(e) {
      greeting_prefetch_started(FALSE)
      cat(sprintf("[AI_EXPERT] Karşılama ön yükleme hatası: %s\n", conditionMessage(e)))
    })

    invisible(NULL)
  }

  # --- Karşılama konuşması (uygulama açıldığında bir kez) ---
  session$onFlushed(function() {
    start_greeting_prefetch()

    shinyjs::delay(150, {
      trigger_greeting()
    })
  }, once = TRUE)

  # --- Ayarlar değiştiğinde karşılama tetikleyicisi ---
  observe({
    ai_on <- isTRUE(settings_data$enable_ai_expert)
    mode <- settings_data$experience_mode

    if (ai_on && identical(mode, "kesif") && !isTRUE(isolate(greeting_done()))) {
      start_greeting_prefetch()

      shinyjs::delay(120, {
        trigger_greeting()
      })
    }
  })

  # Karşılama konuşmasını tetikleme fonksiyonu
  trigger_greeting <- function(prefetch_wait_attempt = 0L) {
    if (isTRUE(greeting_done())) return()
    if (!isTRUE(settings_data$enable_ai_expert)) return()
    if (!identical(settings_data$experience_mode, "kesif")) return()

    prefetched <- isolate(greeting_prefetch_result())
    prefetch_started <- isTRUE(isolate(greeting_prefetch_started()))

    # Ön yükleme başlatıldıysa ama henüz bitmediyse kısa süre bekle
    if (is.null(prefetched) && prefetch_started && prefetch_wait_attempt < 4L) {
      shinyjs::delay(120, {
        trigger_greeting(prefetch_wait_attempt + 1L)
      })
      return(invisible(NULL))
    }

    greeting_done(TRUE)
    cat("[AI_EXPERT] Karşılama konuşması tetikleniyor...\n")

    start_greeting_request <- function(system_prompt, user_context, model_name, api_key, endpoint) {
      promises::future_promise({
        call_ai_expert_llm(
          system_prompt = system_prompt,
          user_context = user_context,
          model_name = model_name,
          api_key = api_key,
          endpoint = endpoint,
          max_tokens = 220
        )
      }) %...>% (function(greeting_text) {
        if (!is.null(greeting_text) && nzchar(greeting_text)) {
          cat(sprintf("[AI_EXPERT] Karşılama metni alındı (%d karakter)\n", nchar(greeting_text)))
          ai_expert$start_speaking(greeting_text, ai_expert$COOLDOWN_GREETING)
        }
        schedule_idle_chat(FIRST_IDLE_DELAY_MS)
      }) %...!% (function(e) {
        cat(sprintf("[AI_EXPERT] Karşılama hatası: %s\n", conditionMessage(e)))
        schedule_idle_chat(FIRST_IDLE_DELAY_MS)
      })
    }

    # Önceden hazırlanmış bağlam varsa doğrudan onu kullan
    if (!is.null(prefetched)) {
      start_greeting_request(
        system_prompt = prefetched$system_prompt,
        user_context = prefetched$user_context,
        model_name = prefetched$model_name,
        api_key = prefetched$api_key,
        endpoint = prefetched$endpoint
      )
      return(invisible(NULL))
    }

    # Ön yükleme hazır değilse mevcut akışa geri düş
    params <- prepare_llm_params()
    user_id <- current_user_id
    talk_length_val <- isolate(settings_data$ai_expert_talk_length) %||% "orta"
    talk_style_val <- isolate(settings_data$ai_expert_talk_style) %||% "profesyonel"

    promises::future_promise({
      last_login <- fetch_user_last_login(user_id)
      u_name <- resolve_user_name(params$user_name)

      user_context <- build_ai_expert_user_context(
        user_id,
        user_name = u_name,
        last_login_date = last_login,
        include_recent_prompts = TRUE,
        max_prompts = 5
      )

      system_prompt <- build_ai_expert_system_prompt(
        params$char_info,
        scenario = "greeting",
        user_name = u_name,
        talk_length = talk_length_val,
        talk_style = talk_style_val
      )

      list(
        system_prompt = system_prompt,
        user_context = user_context,
        model_name = params$model_name,
        api_key = params$api_key,
        endpoint = params$endpoint
      )
    }) %...>% (function(prepared) {
      start_greeting_request(
        system_prompt = prepared$system_prompt,
        user_context = prepared$user_context,
        model_name = prepared$model_name,
        api_key = prepared$api_key,
        endpoint = prepared$endpoint
      )
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Karşılama hazırlık hatası: %s\n", conditionMessage(e)))
      schedule_idle_chat(FIRST_IDLE_DELAY_MS)
    })

    invisible(NULL)
  }

  # --- Boşta konuşma zamanlayıcısı yardımcısı ---
  schedule_idle_chat <- function(delay_ms = NULL) {
    if (is.null(delay_ms)) delay_ms <- get_idle_interval()
    shinyjs::delay(delay_ms, {
      trigger_idle_chat()
    })
  }

  # --- Sayfa geçişi rehberliği ---
  observeEvent(input$tabs, {
    page <- input$tabs
    ai_expert$set_page(page)

    # Yasaklı sayfalarda konuşma
    muted <- c("settings_kisisel", "admin_analytics", "health")
    if (page %in% muted) return()

    # Özellik kontrolü
    if (!isTRUE(settings_data$enable_ai_expert)) return()
    if (!identical(settings_data$experience_mode, "kesif")) return()

    visited <- isolate(visited_pages())

    # Ana Söyleşi sayfasına geri dönüldüğünde: boşta konuşma planla
    if (page == "chat") {
      schedule_idle_chat(15000)
      return()
    }

    already_visited <- page %in% visited
    visited_pages(unique(c(visited, page)))

    # GECİKMESİZ: Sayfa rehberliği LLM çağrısını hemen başlat
    # Kullanıcı sayfayı tıkladığında metin hazırlığı anında başlar
    trigger_page_guidance(page, already_visited)

  }, ignoreInit = TRUE)

  # Sayfa rehberliği konuşması
  trigger_page_guidance <- function(page, is_revisit = FALSE) {
    # Temel kontrol: konuşuyor mu veya mesaj mı gönderiyor (bekleme süresini ATLA)
    if (!can_speak_basic()) return()

    # Aktif sayfanın hâlâ aynı olduğunu kontrol et
    current <- isolate(input$tabs)
    if (!identical(current, page)) return()

    # Sayfa adını Türkçe'ye çevir
    page_name_tr <- switch(page,
      "history"               = "Söyleşi Geçmişi",
      "saved_chats"           = "Kayıtlı Söyleşiler",
      "image_gallery"         = "Görsel Galerisi",
      "files"                 = "Dosya Yönetimi",
      "settings_yapilandirma" = "Yapılandırma",
      NULL
    )
    if (is.null(page_name_tr)) return()

    cat(sprintf("[AI_EXPERT] Sayfa rehberliği: %s (tekrar ziyaret: %s)\n", page_name_tr, is_revisit))

    params <- prepare_llm_params()
    talk_length_val <- isolate(settings_data$ai_expert_talk_length) %||% "orta"
    talk_style_val <- isolate(settings_data$ai_expert_talk_style) %||% "profesyonel"

    # GECİKMESİZ: LLM çağrısı hemen başlar
    promises::future_promise({
      u_name <- resolve_user_name(params$user_name)
      system_prompt <- build_ai_expert_system_prompt(
        params$char_info, scenario = "page_guidance",
        page_name = page_name_tr, user_name = u_name, is_revisit = is_revisit,
        talk_length = talk_length_val, talk_style = talk_style_val
      )
      user_context <- sprintf(
        "Kullanıcı '%s' sayfasına geçiş yaptı. Şimdi: %s. Bu sayfayı %s ziyaret ediyor.",
        page_name_tr, format(Sys.time(), "%d %B %Y %H:%M"),
        if (is_revisit) "tekrar" else "ilk kez"
      )
      call_ai_expert_llm(
        system_prompt = system_prompt, user_context = user_context,
        model_name = params$model_name, api_key = params$api_key,
        endpoint = params$endpoint, max_tokens = 180
      )
    }) %...>% (function(guidance_text) {
      if (!is.null(guidance_text) && nzchar(guidance_text)) {
        # Konuşma sırasında aktif konuşma varsa durdurup yenisini başlat
        if (isTRUE(ai_expert$is_speaking())) {
          ai_expert$stop_speaking(0)
        }
        ai_expert$start_speaking(guidance_text, ai_expert$COOLDOWN_PAGE)
        last_page_talk_time(Sys.time())
      }
      schedule_idle_chat()
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Sayfa rehberliği hatası: %s\n", conditionMessage(e)))
      schedule_idle_chat()
    })
  }

  # --- Boşta konuşma ---
  trigger_idle_chat <- function() {
    if (!isTRUE(settings_data$enable_ai_expert) ||
        !identical(settings_data$experience_mode, "kesif")) {
      schedule_idle_chat()
      return()
    }
    if (!ai_expert$can_speak()) {
      schedule_idle_chat()
      return()
    }
    if (isTRUE(values$is_sending)) {
      schedule_idle_chat()
      return()
    }

    # Sayacı artır (tekrar eden konuşmaları önlemek için bağlam sağlar)
    current_count <- isolate(idle_talk_counter()) + 1L
    idle_talk_counter(current_count)

    cat(sprintf("[AI_EXPERT] Boşta konuşma #%d tetikleniyor...\n", current_count))

    params <- prepare_llm_params()
    current_page_val <- isolate(input$tabs) %||% "chat"

    page_name_tr <- switch(current_page_val,
      "chat"                  = "Ana Söyleşi",
      "history"               = "Söyleşi Geçmişi",
      "saved_chats"           = "Kayıtlı Söyleşiler",
      "image_gallery"         = "Görsel Galerisi",
      "files"                 = "Dosya Yönetimi",
      "settings_yapilandirma" = "Yapılandırma",
      "Ana Söyleşi"
    )

    # Boşta konuşma sayacını LLM bağlamına ekle
    idle_count_val <- current_count

    # Mevcut oturumdaki mesajları yakala (reaktif değerleri main thread'de oku)
    session_msgs <- capture_session_messages(5)

    # AI Uzman konuşma uzunluğu/sıklığı/tarz ayarlarını oku
    talk_length_val <- isolate(settings_data$ai_expert_talk_length) %||% "orta"
    talk_style_val <- isolate(settings_data$ai_expert_talk_style) %||% "profesyonel"

    promises::future_promise({
      u_name <- resolve_user_name(params$user_name)

      recent_prompts <- tryCatch(
        fetch_recent_user_prompts(current_user_id, 3),
        error = function(e) NULL
      )

      system_prompt <- build_ai_expert_system_prompt(
        params$char_info, scenario = "idle_chat",
        page_name = page_name_tr, user_name = u_name,
        talk_length = talk_length_val, talk_style = talk_style_val
      )

      context_parts <- list()
      context_parts <- c(context_parts, sprintf(
        "Kullanıcı şu anda '%s' sayfasında ve bir süredir etkileşimde bulunmadı.",
        page_name_tr
      ))

      # Konuşma sayacı: LLM'ye bu bilgiyi ver ki tekrar etmesin
      context_parts <- c(context_parts, sprintf(
        "Bu oturumda %d. boşta konuşman. ÖNEMLİ: Selam verme, merhaba deme, hoş geldin deme. Bu zaten devam eden bir sohbet. Önceki konuşmalarını tekrarlama, her seferinde farklı bir konuya değin ve farklı bir giriş cümlesi kullan. Yaratıcı ol, sürpriz yap.",
        idle_count_val
      ))

      # Mevcut oturum mesajları (en güncel bağlam)
      if (!is.null(session_msgs) && length(session_msgs) > 0) {
        session_text <- paste(sprintf("- \"%s\"", substr(session_msgs, 1, 200)), collapse = "\n")
        context_parts <- c(context_parts, sprintf(
          "Bu oturumdaki kullanıcı mesajları (EN GÜNCEL - bu konulara öncelik ver):\n%s",
          session_text
        ))
      }

      if (!is.null(recent_prompts) && length(recent_prompts) > 0) {
        prompts_text <- paste(sprintf("- \"%s\"", substr(recent_prompts, 1, 120)), collapse = "\n")
        context_parts <- c(context_parts, sprintf("Veritabanından son konuşma konuları:\n%s", prompts_text))
      }
      context_parts <- c(context_parts, sprintf("Şimdi: %s", format(Sys.time(), "%d %B %Y %H:%M")))

      user_context <- paste(context_parts, collapse = "\n\n")

      call_ai_expert_llm(
        system_prompt = system_prompt, user_context = user_context,
        model_name = params$model_name, api_key = params$api_key,
        endpoint = params$endpoint, max_tokens = 400
      )
    }) %...>% (function(idle_text) {
      if (!is.null(idle_text) && nzchar(idle_text)) {
        if (ai_expert$can_speak()) {
          ai_expert$start_speaking(idle_text, ai_expert$COOLDOWN_IDLE)
        }
      }
      schedule_idle_chat()
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Boşta konuşma hatası: %s\n", conditionMessage(e)))
      schedule_idle_chat()
    })
  }

  # --- Kullanıcı aktivitesi izleme (yarış durumu önleme) ---
  observeEvent(values$is_sending, {
    if (isTRUE(values$is_sending)) {
      ai_expert$set_user_active(TRUE)
      if (isTRUE(ai_expert$is_speaking())) {
        cat("[AI_EXPERT] Kullanıcı mesaj gönderiyor, konuşma durduruluyor.\n")
        ai_expert$stop_speaking()
      }
    } else {
      shinyjs::delay(3000, {
        ai_expert$set_user_active(FALSE)
      })
    }
  }, ignoreInit = TRUE)

  # --- TTS seslendirmesi ile çakışma önleme ---
  observeEvent(input$tts_is_playing, {
    is_playing <- isTRUE(input$tts_is_playing)
    ai_expert$set_tts_vocalizing(is_playing)
    if (is_playing && isTRUE(ai_expert$is_speaking())) {
      cat("[AI_EXPERT] TTS seslendirmesi başladı, AI konuşması durduruluyor.\n")
      ai_expert$stop_speaking()
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}