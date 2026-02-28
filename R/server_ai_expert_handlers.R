# R/server_ai_expert_handlers.R
# Dosya Yolu: R/server_ai_expert_handlers.R
# Aciklama: AI Uzman (AI Expert) sunucu tarafindaki isleyiciler.
#            Karsilama, sayfa rehberligi ve bosta kalma konusmalari icin
#            observer'lari ve tetikleme mantikini yonetir.
#            Yaris durumu (race condition) onleme mekanizmalarini icerir.

#' AI Uzman Isleyicilerini Baslat
#'
#' @description AI Uzman konusma tetikleyicilerini ve observer'larini kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif degerler
#' @param settings_data Ayarlar modulunden donen reaktif ayarlar
#' @param ai_expert AI Uzman modulu (module_ai_expert.R'den)
#' @param tts_processor TTS isleme modulu
#' @param current_user_id Mevcut kullanici ID'si
#' @return Gorunmez NULL
aiExpertHandlersInit <- function(input, session, values, settings_data,
                                  ai_expert, tts_processor,
                                  current_user_id) {

  # --- Karsilama konusmasi (uygulama acildiginda bir kez) ---
  greeting_done <- reactiveVal(FALSE)

  # Uygulama acildiginda karsilama konusmasini tetikle
  # session$onFlushed ile UI hazir oldugunda calisir
  session$onFlushed(function() {
    # Kisa bir gecikme ile karsilama konusmasini tetikle
    # (diger modullerin yuklenmesini bekle)
    shinyjs::delay(4000, {
      trigger_greeting()
    })
  }, once = TRUE)

  # Karsilama konusmasini tetikleme fonksiyonu
  trigger_greeting <- function() {
    # Zaten yapildiysa tekrarlama
    if (isTRUE(greeting_done())) return()

    # AI Uzman konusabilir mi kontrol et
    if (!ai_expert$can_speak()) return()

    # Karsilama yapildi olarak isaretle (tekrar tetiklemeyi onle)
    greeting_done(TRUE)

    cat("[AI_EXPERT] Karsilama konusmasi tetikleniyor...\n")

    # Reaktif degerleri yakalama (worker-safe)
    user_id <- current_user_id
    char_id <- isolate(settings_data$selected_character) %||% "mergen"
    model_name <- Sys.getenv("AI_EXPERT_MODEL", "")
    endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
    api_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")

    # Kullanici API anahtarini kontrol et
    user_api_key <- NULL
    if (!is.null(session$userData$ai_api_key)) {
      user_api_key <- session$userData$ai_api_key
    }
    final_api_key <- if (!is.null(user_api_key) && nzchar(user_api_key)) user_api_key else api_key

    # Karakter bilgilerini al
    chars_data <- get_characters_data()
    char_info <- Find(function(x) x$id == char_id, chars_data$styles)
    if (is.null(char_info)) {
      char_info <- chars_data$styles[[1]] # Varsayilan: MERGEN
    }

    # Asenkron islem (UI'yi bloklamaz)
    promises::future_promise({
      # Worker icinde: DB erisimi ve LLM cagrisi
      last_login <- fetch_user_last_login(user_id)
      user_context <- build_ai_expert_user_context(
        user_id,
        last_login_date = last_login,
        include_recent_prompts = TRUE,
        max_prompts = 5
      )
      system_prompt <- build_ai_expert_system_prompt(
        char_info,
        scenario = "greeting"
      )
      call_ai_expert_llm(
        system_prompt = system_prompt,
        user_context  = user_context,
        model_name    = model_name,
        api_key       = final_api_key,
        endpoint      = endpoint,
        max_tokens    = 200
      )
    }) %...>% (function(greeting_text) {
      if (!is.null(greeting_text) && nzchar(greeting_text)) {
        # Son kontrol: AI Uzman hala konusabilir mi?
        if (ai_expert$can_speak()) {
          ai_expert$start_speaking(greeting_text)
        }
      }
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Karsilama hatasi: %s\n", conditionMessage(e)))
    })
  }

  # --- Sayfa gecisi rehberligi ---
  # Navigasyon degisikliklerini dinle
  observeEvent(input$tabs, {
    page <- input$tabs
    ai_expert$set_page(page)

    # Yasakli sayfalarda konusma
    muted <- c("settings_kisisel", "admin_analytics", "health")
    if (page %in% muted) return()

    # Ana Soylesi sayfasinda karsilama zaten yapildi, tekrar konusma
    if (page == "chat") return()

    # Kisa gecikme ile sayfa rehberligi konusmasi
    shinyjs::delay(3000, {
      trigger_page_guidance(page)
    })
  }, ignoreInit = TRUE)

  # Sayfa rehberligi konusmasi
  trigger_page_guidance <- function(page) {
    if (!ai_expert$can_speak()) return()

    # Sayfa adini Turkce'ye cevir
    page_name_tr <- switch(page,
      "history"             = "Soylesi Gecmisi",
      "saved_chats"         = "Kayitli Soylesiler",
      "image_gallery"       = "Gorsel Galerisi",
      "files"               = "Dosya Yonetimi",
      "settings_yapilandirma" = "Yapilandirma",
      NULL
    )

    # Bilinmeyen sayfa veya NULL ise konusma
    if (is.null(page_name_tr)) return()

    cat(sprintf("[AI_EXPERT] Sayfa rehberligi: %s\n", page_name_tr))

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

    promises::future_promise({
      system_prompt <- build_ai_expert_system_prompt(
        char_info,
        scenario  = "page_guidance",
        page_name = page_name_tr
      )
      user_context <- sprintf(
        "Kullanici '%s' sayfasina gecis yapti. Simdi: %s",
        page_name_tr,
        format(Sys.time(), "%d %B %Y %H:%M")
      )
      call_ai_expert_llm(
        system_prompt = system_prompt,
        user_context  = user_context,
        model_name    = model_name,
        api_key       = final_api_key,
        endpoint      = endpoint,
        max_tokens    = 150
      )
    }) %...>% (function(guidance_text) {
      if (!is.null(guidance_text) && nzchar(guidance_text)) {
        if (ai_expert$can_speak()) {
          ai_expert$start_speaking(guidance_text)
        }
      }
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Sayfa rehberligi hatasi: %s\n", conditionMessage(e)))
    })
  }

  # --- Kullanici aktivitesi izleme (yaris durumu onleme) ---
  # Kullanici mesaj gonderdiginde AI konusmasini durdur
  observeEvent(values$is_sending, {
    if (isTRUE(values$is_sending)) {
      ai_expert$set_user_active(TRUE)
      # Aktif konusma varsa durdur
      if (isTRUE(ai_expert$is_speaking())) {
        cat("[AI_EXPERT] Kullanici mesaj gonderiyor, konusma durduruluyor.\n")
        ai_expert$stop_speaking()
      }
    } else {
      # Mesaj gonderimi bittikten sonra kisa bir bekleme ile aktif durumu kapat
      shinyjs::delay(5000, {
        ai_expert$set_user_active(FALSE)
      })
    }
  }, ignoreInit = TRUE)

  # --- TTS seslendirmesi ile cakisma onleme ---
  # TTS seslendirmesi basladiginda AI konusmasini engelle
  observeEvent(settings_data$enable_tts_audio, {
    # TTS acildiginda ve bir mesaj isleniyor
    # (bu sadece ayar degisikligini izler, gercek cakisma
    # can_speak() kontrolunde yapilir)
  }, ignoreInit = TRUE)

  invisible(NULL)
}
