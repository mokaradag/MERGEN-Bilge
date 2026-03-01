# R/server_ai_expert_handlers.R
# Dosya Yolu: R/server_ai_expert_handlers.R
# Açıklama: AI Uzman (AI Expert) sunucu tarafındaki işleyiciler.
#            Karşılama, sayfa rehberliği, boşta konuşma ve kullanıcı adıyla
#            kişiselleştirilmiş etkileşim mantığını yönetir.
#            Yarış durumu (race condition) önleme mekanizmalarını içerir.
#            Boşta konuşma zinciri her zaman yeniden planlanır (kırılmaz).

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

  # Kullanıcı adı (DB'den alınacak)
  user_first_name <- session$userData$user_first_name %||% ""

  # Boşta konuşma arası (ms) - daha sık konuşma için kısa tutuldu
  IDLE_INTERVAL_MS   <- 35000   # 35 saniye
  # Karşılama sonrası ilk boşta konuşma bekleme süresi (ms)
  FIRST_IDLE_DELAY_MS <- 25000  # 25 saniye

  # --- Karşılama konuşması (uygulama açıldığında bir kez) ---
  # session$onFlushed ile UI hazır olduktan sonra çalışır
  session$onFlushed(function() {
    # Ayarların yüklenmesini beklemek için kısa bir gecikme
    shinyjs::delay(2500, {
      trigger_greeting()
    })
  }, once = TRUE)

  # --- Ayarlar değiştiğinde karşılama tetikleyicisi ---
  # Kullanıcı giriş ekranında "Bütünleşik" modunu seçtiğinde veya
  # ayarlar localStorage'dan yüklendiğinde karşılamayı tetikle
  observe({
    # Ayar değişikliklerini izle
    ai_on <- isTRUE(settings_data$enable_ai_expert)
    mode <- settings_data$experience_mode

    # Koşullar sağlanıyorsa ve karşılama henüz yapılmadıysa tetikle
    if (ai_on && identical(mode, "kesif") && !isTRUE(isolate(greeting_done()))) {
      shinyjs::delay(1500, {
        trigger_greeting()
      })
    }
  })

  # Karşılama konuşmasını tetikleme fonksiyonu
  trigger_greeting <- function() {
    # Zaten yapıldıysa tekrarlama
    if (isTRUE(greeting_done())) return()

    # Özellik açık mı kontrol et (can_speak yerine doğrudan kontrol)
    if (!isTRUE(settings_data$enable_ai_expert)) return()
    if (!identical(settings_data$experience_mode, "kesif")) return()

    # Karşılama yapıldı olarak işaretle (tekrar tetiklemeyi önle)
    greeting_done(TRUE)

    cat("[AI_EXPERT] Karşılama konuşması tetikleniyor...\n")

    # Reaktif değerleri yakalama (worker-safe)
    user_id <- current_user_id
    user_name <- user_first_name
    char_id <- isolate(settings_data$selected_character) %||% "mergen"
    model_name <- Sys.getenv("AI_EXPERT_MODEL", "")
    endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
    api_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")

    # Kullanıcı API anahtarını kontrol et
    user_api_key <- NULL
    if (!is.null(session$userData$ai_api_key)) {
      user_api_key <- session$userData$ai_api_key
    }
    final_api_key <- if (!is.null(user_api_key) && nzchar(user_api_key)) user_api_key else api_key

    # Karakter bilgilerini al
    chars_data <- get_characters_data()
    char_info <- Find(function(x) x$id == char_id, chars_data$styles)
    if (is.null(char_info)) {
      char_info <- chars_data$styles[[1]]
    }

    # Asenkron işlem (UI'yi bloklamaz)
    promises::future_promise({
      # Worker içinde: DB erişimi ve LLM çağrısı
      last_login <- fetch_user_last_login(user_id)
      user_full_name <- fetch_user_full_name(user_id)

      # İlk ismi ayıkla (tam isimden)
      u_name <- user_name
      if (nzchar(user_full_name %||% "")) {
        parts <- strsplit(trimws(user_full_name), "\\s+")[[1]]
        u_name <- paste0(toupper(substring(parts[1], 1, 1)), tolower(substring(parts[1], 2)))
      }

      user_context <- build_ai_expert_user_context(
        user_id,
        user_name       = u_name,
        last_login_date = last_login,
        include_recent_prompts = TRUE,
        max_prompts = 5
      )
      system_prompt <- build_ai_expert_system_prompt(
        char_info,
        scenario  = "greeting",
        user_name = u_name
      )
      call_ai_expert_llm(
        system_prompt = system_prompt,
        user_context  = user_context,
        model_name    = model_name,
        api_key       = final_api_key,
        endpoint      = endpoint,
        max_tokens    = 500
      )
    }) %...>% (function(greeting_text) {
      if (!is.null(greeting_text) && nzchar(greeting_text)) {
        cat(sprintf("[AI_EXPERT] Karşılama metni alındı (%d karakter)\n", nchar(greeting_text)))
        # Doğrudan konuşmayı başlat (can_speak kontrolünü atla, karşılama özeldir)
        ai_expert$start_speaking(greeting_text, ai_expert$COOLDOWN_GREETING)

        # Boşta konuşma zamanlayıcısını başlat
        schedule_idle_chat(FIRST_IDLE_DELAY_MS)
      } else {
        # Metin alınamadıysa bile boşta konuşma zamanlayıcısını başlat
        schedule_idle_chat(FIRST_IDLE_DELAY_MS)
      }
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Karşılama hatası: %s\n", conditionMessage(e)))
      # Hata durumunda bile boşta konuşma zamanlayıcısını başlat
      schedule_idle_chat(FIRST_IDLE_DELAY_MS)
    })
  }

  # --- Boşta konuşma zamanlayıcısı yardımcısı ---
  # Her zaman bir sonraki boşta konuşmayı planlar (zincir asla kırılmaz)
  schedule_idle_chat <- function(delay_ms = IDLE_INTERVAL_MS) {
    shinyjs::delay(delay_ms, {
      trigger_idle_chat()
    })
  }

  # --- Sayfa geçişi rehberliği ---
  # Navigasyon değişikliklerini dinle
  observeEvent(input$tabs, {
    page <- input$tabs
    ai_expert$set_page(page)

    # Yasaklı sayfalarda konuşma
    muted <- c("settings_kisisel", "admin_analytics", "health")
    if (page %in% muted) return()

    # Özellik kontrolü
    if (!isTRUE(settings_data$enable_ai_expert)) return()
    if (!identical(settings_data$experience_mode, "kesif")) return()

    # Zaten ziyaret edilmiş sayfaları kontrol et
    visited <- isolate(visited_pages())

    # Ana Söyleşi sayfasına geri dönüldüğünde: boşta konuşma zamanlayıcısını başlat
    if (page == "chat") {
      schedule_idle_chat(20000)
      return()
    }

    # Bu sayfa daha önce ziyaret edildiyse, farklı bir zamanlayıcıyla (daha uzun) konuş
    already_visited <- page %in% visited

    # Sayfayı ziyaret edilmiş olarak işaretle
    visited_pages(unique(c(visited, page)))

    # Gecikme ile sayfa rehberliği konuşması - daha hızlı yanıt
    delay_ms <- if (already_visited) 3000 else 1500
    shinyjs::delay(delay_ms, {
      trigger_page_guidance(page, already_visited)
    })
  }, ignoreInit = TRUE)

  # Sayfa rehberliği konuşması
  trigger_page_guidance <- function(page, is_revisit = FALSE) {
    if (!ai_expert$can_speak()) return()

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

    # Bilinmeyen sayfa veya NULL ise konuşma
    if (is.null(page_name_tr)) return()

    cat(sprintf("[AI_EXPERT] Sayfa rehberliği: %s (tekrar ziyaret: %s)\n", page_name_tr, is_revisit))

    char_id <- isolate(settings_data$selected_character) %||% "mergen"
    model_name <- Sys.getenv("AI_EXPERT_MODEL", "")
    endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
    api_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")
    user_name <- user_first_name

    user_api_key <- NULL
    if (!is.null(session$userData$ai_api_key)) {
      user_api_key <- session$userData$ai_api_key
    }
    final_api_key <- if (!is.null(user_api_key) && nzchar(user_api_key)) user_api_key else api_key

    chars_data <- get_characters_data()
    char_info <- Find(function(x) x$id == char_id, chars_data$styles)
    if (is.null(char_info)) char_info <- chars_data$styles[[1]]

    promises::future_promise({
      user_full_name <- fetch_user_full_name(current_user_id)
      u_name <- user_name
      if (nzchar(user_full_name %||% "")) {
        parts <- strsplit(trimws(user_full_name), "\\s+")[[1]]
        u_name <- paste0(toupper(substring(parts[1], 1, 1)), tolower(substring(parts[1], 2)))
      }

      system_prompt <- build_ai_expert_system_prompt(
        char_info,
        scenario   = "page_guidance",
        page_name  = page_name_tr,
        user_name  = u_name,
        is_revisit = is_revisit
      )
      user_context <- sprintf(
        "Kullanıcı '%s' sayfasına geçiş yaptı. Şimdi: %s. Bu sayfayı %s ziyaret ediyor.",
        page_name_tr,
        format(Sys.time(), "%d %B %Y %H:%M"),
        if (is_revisit) "tekrar" else "ilk kez"
      )
      call_ai_expert_llm(
        system_prompt = system_prompt,
        user_context  = user_context,
        model_name    = model_name,
        api_key       = final_api_key,
        endpoint      = endpoint,
        max_tokens    = 400
      )
    }) %...>% (function(guidance_text) {
      if (!is.null(guidance_text) && nzchar(guidance_text)) {
        if (ai_expert$can_speak()) {
          ai_expert$start_speaking(guidance_text, ai_expert$COOLDOWN_PAGE)
          last_page_talk_time(Sys.time())
        }
      }
      # Sayfa konuşması başarılı olsun ya da olmasın, boşta konuşmayı planla
      schedule_idle_chat(IDLE_INTERVAL_MS)
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Sayfa rehberliği hatası: %s\n", conditionMessage(e)))
      # Hata durumunda bile bir sonraki boşta konuşmayı planla
      schedule_idle_chat(IDLE_INTERVAL_MS)
    })
  }

  # --- Boşta konuşma (kullanıcı bir süredir etkileşimde bulunmadığında) ---
  trigger_idle_chat <- function() {
    # Özellik kapalıysa sadece yeniden planla
    if (!isTRUE(settings_data$enable_ai_expert) ||
        !identical(settings_data$experience_mode, "kesif")) {
      schedule_idle_chat(IDLE_INTERVAL_MS)
      return()
    }

    # Konuşamıyorsa yeniden planla ve çık
    if (!ai_expert$can_speak()) {
      schedule_idle_chat(IDLE_INTERVAL_MS)
      return()
    }

    # Kullanıcı aktif sohbetteyse yeniden planla ve çık
    if (isTRUE(values$is_sending)) {
      schedule_idle_chat(IDLE_INTERVAL_MS)
      return()
    }

    cat("[AI_EXPERT] Boşta konuşma tetikleniyor...\n")

    char_id <- isolate(settings_data$selected_character) %||% "mergen"
    model_name <- Sys.getenv("AI_EXPERT_MODEL", "")
    endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
    api_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")
    user_name <- user_first_name
    current_page_val <- isolate(input$tabs) %||% "chat"

    user_api_key <- NULL
    if (!is.null(session$userData$ai_api_key)) {
      user_api_key <- session$userData$ai_api_key
    }
    final_api_key <- if (!is.null(user_api_key) && nzchar(user_api_key)) user_api_key else api_key

    chars_data <- get_characters_data()
    char_info <- Find(function(x) x$id == char_id, chars_data$styles)
    if (is.null(char_info)) char_info <- chars_data$styles[[1]]

    # Sayfa adını Türkçe'ye çevir
    page_name_tr <- switch(current_page_val,
      "chat"                  = "Ana Söyleşi",
      "history"               = "Söyleşi Geçmişi",
      "saved_chats"           = "Kayıtlı Söyleşiler",
      "image_gallery"         = "Görsel Galerisi",
      "files"                 = "Dosya Yönetimi",
      "settings_yapilandirma" = "Yapılandırma",
      "Ana Söyleşi"
    )

    promises::future_promise({
      user_full_name <- fetch_user_full_name(current_user_id)
      u_name <- user_name
      if (nzchar(user_full_name %||% "")) {
        parts <- strsplit(trimws(user_full_name), "\\s+")[[1]]
        u_name <- paste0(toupper(substring(parts[1], 1, 1)), tolower(substring(parts[1], 2)))
      }

      # Son mesajları al (bağlam için)
      recent_prompts <- tryCatch(
        fetch_recent_user_prompts(current_user_id, 3),
        error = function(e) NULL
      )

      system_prompt <- build_ai_expert_system_prompt(
        char_info,
        scenario  = "idle_chat",
        page_name = page_name_tr,
        user_name = u_name
      )

      context_parts <- list()
      context_parts <- c(context_parts, sprintf(
        "Kullanıcı şu anda '%s' sayfasında ve bir süredir etkileşimde bulunmadı.",
        page_name_tr
      ))
      if (!is.null(recent_prompts) && length(recent_prompts) > 0) {
        prompts_text <- paste(sprintf("- \"%s\"", substr(recent_prompts, 1, 120)), collapse = "\n")
        context_parts <- c(context_parts, sprintf("Kullanıcının son konuşma konuları:\n%s", prompts_text))
      }
      context_parts <- c(context_parts, sprintf("Şimdi: %s", format(Sys.time(), "%d %B %Y %H:%M")))

      user_context <- paste(context_parts, collapse = "\n\n")

      call_ai_expert_llm(
        system_prompt = system_prompt,
        user_context  = user_context,
        model_name    = model_name,
        api_key       = final_api_key,
        endpoint      = endpoint,
        max_tokens    = 400
      )
    }) %...>% (function(idle_text) {
      if (!is.null(idle_text) && nzchar(idle_text)) {
        if (ai_expert$can_speak()) {
          ai_expert$start_speaking(idle_text, ai_expert$COOLDOWN_IDLE)
        }
      }
      # Her zaman bir sonraki boşta konuşmayı planla (zincir asla kırılmaz)
      schedule_idle_chat(IDLE_INTERVAL_MS)
    }) %...!% (function(e) {
      cat(sprintf("[AI_EXPERT] Boşta konuşma hatası: %s\n", conditionMessage(e)))
      # Hata durumunda bile bir sonraki boşta konuşmayı planla
      schedule_idle_chat(IDLE_INTERVAL_MS)
    })
  }

  # --- Kullanıcı aktivitesi izleme (yarış durumu önleme) ---
  # Kullanıcı mesaj gönderdiğinde AI konuşmasını durdur
  observeEvent(values$is_sending, {
    if (isTRUE(values$is_sending)) {
      ai_expert$set_user_active(TRUE)
      # Aktif konuşma varsa durdur
      if (isTRUE(ai_expert$is_speaking())) {
        cat("[AI_EXPERT] Kullanıcı mesaj gönderiyor, konuşma durduruluyor.\n")
        ai_expert$stop_speaking()
      }
    } else {
      # Mesaj gönderimi bittikten sonra kısa bir bekleme ile aktif durumu kapat
      shinyjs::delay(3000, {
        ai_expert$set_user_active(FALSE)
      })
    }
  }, ignoreInit = TRUE)

  # --- TTS seslendirmesi ile çakışma önleme ---
  # Ana sohbette TTS seslendirmesi başladığında AI konuşmasını engelle
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
