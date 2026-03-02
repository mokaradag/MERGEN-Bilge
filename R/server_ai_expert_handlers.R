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
                                  current_user_id) {

  # --- Durum değişkenleri ---
  greeting_done     <- reactiveVal(FALSE)
  visited_pages     <- reactiveVal(character(0))  # Ziyaret edilen sayfalar
  idle_timer_active <- reactiveVal(FALSE)          # Boşta zamanlayıcısı aktif mi
  last_page_talk_time <- reactiveVal(NULL)         # Son sayfa konuşma zamanı
  idle_talk_counter <- reactiveVal(0L)             # Boşta konuşma sayacı (tekrar önleme)

  # Kullanıcı adı (DB'den alınacak)
  user_first_name <- session$userData$user_first_name %||% ""

  # Boşta konuşma arası (ms)
  IDLE_INTERVAL_MS   <- 35000   # 35 saniye
  # Karşılama sonrası ilk boşta konuşma bekleme süresi (ms)
  FIRST_IDLE_DELAY_MS <- 20000  # 20 saniye

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
    model_name <- Sys.getenv("AI_EXPERT_MODEL", "")
    endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
    api_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")
    user_api_key <- NULL
    if (!is.null(session$userData$ai_api_key)) {
      user_api_key <- session$userData$ai_api_key
    }
    final_api_key <- if (!is.null(user_api_key) && nzchar(user_api_key)) user_api_key else api_key
    chars_data <- get_characters_data()
    char_info <- Find(function(x) x$id == char_id, chars_data$styles)
    if (is.null(char_info)) char_info <- chars_data$styles[[1]]
    list(
      char_info = char_info,
      model_name = model_name,
      endpoint = endpoint,
      api_key = final_api_key,
      user_name = user_first_name
    )
  }

  # --- Yardımcı: Kullanıcı adını worker içinde çözümle ---
  resolve_user_name <- function(user_name) {
    user_full_name <- fetch_user_full_name(current_user_id)
    u_name <- user_name
    if (nzchar(user_full_name %||% "")) {
      parts <- strsplit(trimws(user_full_name), "\\s+")[[1]]
      u_name <- paste0(toupper(substring(parts[1], 1, 1)), tolower(substring(parts[1], 2)))
    }
    u_name
  }

  # --- Karşılama konuşması (uygulama açıldığında bir kez) ---
  session$onFlushed(function() {
    shinyjs::delay(2000, {
      trigger_greeting()
    })
  }, once = TRUE)

  # --- Ayarlar değiştiğinde karşılama tetikleyicisi ---
  observe({
    ai_on <- isTRUE(settings_data$enable_ai_expert)
    mode <- settings_data$experience_mode
    if (ai_on && identical(mode, "kesif") && !isTRUE(isolate(greeting_done()))) {
      shinyjs::delay(1000, {
        trigger_greeting()
      })
    }
  })

  # Karşılama konuşmasını tetikleme fonksiyonu
  trigger_greeting <- function() {
    if (isTRUE(greeting_done())) return()
    if (!isTRUE(settings_data$enable_ai_expert)) return()
    if (!identical(settings_data$experience_mode, "kesif")) return()

    greeting_done(TRUE)
    cat("[AI_EXPERT] Karşılama konuşması tetikleniyor...\n")

    params <- prepare_llm_params()
    user_id <- current_user_id

    # Gecikmesiz LLM çağrısı
    promises::future_promise({
      last_login <- fetch_user_last_login(user_id)
      u_name <- resolve_user_name(params$user_name)
      user_context <- build_ai_expert_user_context(
        user_id, user_name = u_name,
        last_login_date = last_login,
        include_recent_prompts = TRUE, max_prompts = 5
      )
      system_prompt <- build_ai_expert_system_prompt(
        params$char_info, scenario = "greeting", user_name = u_name
      )
      call_ai_expert_llm(
        system_prompt = system_prompt, user_context = user_context,
        model_name = params$model_name, api_key = params$api_key,
        endpoint = params$endpoint, max_tokens = 500
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

  # --- Boşta konuşma zamanlayıcısı yardımcısı ---
  schedule_idle_chat <- function(delay_ms = IDLE_INTERVAL_MS) {
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

    # GECİKMESİZ: LLM çağrısı hemen başlar
    promises::future_promise({
      u_name <- resolve_user_name(params$user_name)
      system_prompt <- build_ai_expert_system_prompt(
        params$char_info, scenario = "page_guidance",
        page_name = page_name_tr, user_name = u_name, is_revisit = is_revisit
      )
      user_context <- sprintf(
        "Kullanıcı '%s' sayfasına geçiş yaptı. Şimdi: %s. Bu sayfayı %s ziyaret ediyor.",
        page_name_tr, format(Sys.time(), "%d %B %Y %H:%M"),
        if (is_revisit) "tekrar" else "ilk kez"
      )
      call_ai_expert_llm(
        system_prompt = system_prompt, user_context = user_context,
        model_name = params$model_name, api_key = params$api_key,
        endpoint = params$endpoint, max_tokens = 400
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
      schedule_idle_chat(IDLE_INTERVAL_MS)
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Sayfa rehberliği hatası: %s\n", conditionMessage(e)))
      schedule_idle_chat(IDLE_INTERVAL_MS)
    })
  }

  # --- Boşta konuşma ---
  trigger_idle_chat <- function() {
    if (!isTRUE(settings_data$enable_ai_expert) ||
        !identical(settings_data$experience_mode, "kesif")) {
      schedule_idle_chat(IDLE_INTERVAL_MS)
      return()
    }
    if (!ai_expert$can_speak()) {
      schedule_idle_chat(IDLE_INTERVAL_MS)
      return()
    }
    if (isTRUE(values$is_sending)) {
      schedule_idle_chat(IDLE_INTERVAL_MS)
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

    promises::future_promise({
      u_name <- resolve_user_name(params$user_name)

      recent_prompts <- tryCatch(
        fetch_recent_user_prompts(current_user_id, 3),
        error = function(e) NULL
      )

      system_prompt <- build_ai_expert_system_prompt(
        params$char_info, scenario = "idle_chat",
        page_name = page_name_tr, user_name = u_name
      )

      context_parts <- list()
      context_parts <- c(context_parts, sprintf(
        "Kullanıcı şu anda '%s' sayfasında ve bir süredir etkileşimde bulunmadı.",
        page_name_tr
      ))

      # Konuşma sayacı: LLM'ye bu bilgiyi ver ki tekrar etmesin
      context_parts <- c(context_parts, sprintf(
        "Bu oturumda %d. boşta konuşman. ÖNEMLİ: Selam verme, merhaba deme, hoş geldin deme. Bu zaten devam eden bir sohbet. Önceki konuşmalarını tekrarlama, her seferinde farklı bir konuya değin. Yaratıcı ol, sürpriz yap.",
        idle_count_val
      ))

      if (!is.null(recent_prompts) && length(recent_prompts) > 0) {
        prompts_text <- paste(sprintf("- \"%s\"", substr(recent_prompts, 1, 120)), collapse = "\n")
        context_parts <- c(context_parts, sprintf("Kullanıcının son konuşma konuları:\n%s", prompts_text))
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
      schedule_idle_chat(IDLE_INTERVAL_MS)
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Boşta konuşma hatası: %s\n", conditionMessage(e)))
      schedule_idle_chat(IDLE_INTERVAL_MS)
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
