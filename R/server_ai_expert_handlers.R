# R/server_ai_expert_handlers.R
# AI Uzman (AI Expert) sunucu tarafı işleyicileri.
# Karşılama ve sayfa rehberliği ÖNCEDEN ÜRETİLMİŞ persona WAV varlıklarıyla
# (hibrit konuşma çalışma zamanı) oynatılır; LLM yalnızca boşta konuşma metni
# üretir. Yarış durumu önleme mekanizmalarını içerir.

#' AI Uzman İşleyicilerini Başlat
#'
#' @param input Shiny input; session Shiny session; values reaktif değerler;
#'   settings_data ayarlar; ai_expert AI Uzman modülü; tts_processor TTS
#'   işleme; current_user_id kullanıcı kimliği; chat_history_rv (opsiyonel).
#' @return Görünmez NULL
aiExpertHandlersInit <- function(input, session, values, settings_data,
                                  ai_expert, tts_processor,
                                  current_user_id, chat_history_rv = NULL) {

  # --- Durum değişkenleri ---
  greeting_done        <- reactiveVal(FALSE)
  page_guidance_times  <- reactiveVal(list())       # Sayfa bazında son rehberlik zamanı
  idle_timer_active    <- reactiveVal(FALSE)        # Boşta zamanlayıcısı aktif mi
  idle_talk_counter    <- reactiveVal(0L)            # Boşta konuşma sayacı (tekrar önleme)

  PAGE_GUIDANCE_REPEAT_SECS <- 15 * 60

  # Hibrit konuşma çalışma zamanı: statik karşılama/rehberlik + kişisel önek
  speech_runtime <- speechAssetsRuntimeInit(
    input = input, session = session, settings_data = settings_data,
    ai_expert = ai_expert, tts_processor = tts_processor,
    current_user_id = current_user_id
  )
  speechPcmStreamObserversInit(input, session)

  # Kullanıcı adı (DB'den alınacak)
  user_first_name <- session$userData$user_first_name %||% ""
  
  # SSO akışında başlangıçtaki current_user_id değeri 0 olabilir.
  # Bu yüzden AI Uzman tarafında kullanıcı kimliğini her kullanım anında
  # oturumdan yeniden çözmek gerekir.
	resolve_ai_expert_user_id <- function() {
	  uid_source <- if (is.function(current_user_id)) current_user_id() else current_user_id
	  uid <- session$userData$user_id %||% uid_source %||% 0L
	  uid <- suppressWarnings(as.integer(uid))
	  if (is.na(uid) || uid < 0) uid <- 0L
	  uid
	}

  # Sıklık ayarını her kullanım anında oturumdan izole oku.
  # Saf sıklık -> ms eşlemesi R/helpers_ai_expert_handlers_support.R içindedir
  # (ai_expert_first_idle_delay_ms / ai_expert_idle_interval_ms).
  current_talk_frequency <- function() {
    isolate(settings_data$ai_expert_talk_frequency) %||% "orta"
  }

  # --- Yardımcı: Temel konuşabilirlik kontrolü (bekleme süresini ATLAR) ---
  # Sayfa rehberliği gibi kullanıcı eylemine doğrudan yanıt verilen durumlarda kullanılır
  is_stt_modal_active <- function() {
    isTRUE(isolate(input$stt_modal_active))
  }

  # KASITLI OLARAK is_speaking() KONTROLÜ YOK: sayfa rehberliği kullanıcının
  # gezinme eylemidir ve start_speaking() içindeki öncelik matrisi
  # (mergen_speech_priority_decision) "page_guidance" türünün aktif
  # karşılama/eski rehberliği KESMESİNE zaten izin verir (stop_active=TRUE).
  # Burada is_speaking() nedeniyle erken dönersek o kesme mantığına hiç
  # ulaşılmaz ve eski klip yeni sayfada çalmaya devam eder.
  can_speak_basic <- function() {
    if (!isTRUE(settings_data$enable_ai_expert)) return(FALSE)
    if (!identical(settings_data$experience_mode, "kesif")) return(FALSE)
    if (is_stt_modal_active()) return(FALSE)
    if (isTRUE(isolate(values$is_sending))) return(FALSE)
    return(TRUE)
  }

  # --- Yardımcı: Ortak LLM çağrı parametrelerini hazırla ---
    prepare_llm_params <- function(selected_char_id = NULL) {
      char_id <- normalize_character_id(selected_char_id %||% isolate(settings_data$selected_character))
	  model_name <- safe_trimws(Sys.getenv("AI_EXPERT_MODEL", ""))
	  endpoint <- safe_trimws(Sys.getenv("LOCAL_LLM_ENDPOINT", ""))
	  legacy_llm_key <- safe_trimws(Sys.getenv("LOCAL_LLM_API_KEY", ""))

	  final_api_key <- mb_api_key_get_feature_key_value(
		session = session,
		service_key = "",
		fallback_key = legacy_llm_key,
		require_auth = TRUE,
		clear_on_mismatch = TRUE,
		prefer_service_key_after_personal = FALSE
	  )

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
    u_name <- safe_trimws(user_name)

    # Öncelik SSO'dan gelen ilk adda olsun
    if (safe_nzchar(u_name)) {
      return(u_name)
    }

    # SSO ilk adı yoksa DB'deki tam addan ilk adı türet
    effective_user_id <- resolve_ai_expert_user_id()
    user_full_name <- safe_trimws(fetch_user_full_name(effective_user_id))

    if (safe_nzchar(user_full_name)) {
      parts <- strsplit(user_full_name, "\\s+")[[1]]
      first_name <- safe_trimws(parts[1] %||% "")
      if (safe_nzchar(first_name)) {
        return(first_name)
      }
    }

    ""
  }

  # Persona onaylandığı anda (Başlayalım düğmesi) kişisel karşılama önekini
  # sentezlemeye başla ve seçilecek karşılama klibini tarayıcıya önden ısıt.
  # Önek deterministiktir (LLM ÇAĞRILMAZ) ve statik karşılamayı asla
  # geciktirmez; süre sınırını hibrit konuşma çalışma zamanı uygular.
  observeEvent(input$explore_preheat_initial_greeting, {
    req(is.list(input$explore_preheat_initial_greeting))
    req(identical(input$explore_preheat_initial_greeting$mode %||% "", "kesif"))
    req(nzchar(input$explore_preheat_initial_greeting$character %||% ""))

    speech_runtime$prewarm_welcome(input$explore_preheat_initial_greeting$character)
  }, ignoreInit = TRUE)

  # --- Karşılama konuşması (uygulama açıldığında bir kez) ---
  session$onFlushed(function() {
    shinyjs::delay(400, {
      trigger_greeting()
    })
  }, once = TRUE)

  # --- Ayarlar değiştiğinde karşılama tetikleyicisi ---
  observe({
    ai_on <- isTRUE(settings_data$enable_ai_expert)
    mode <- settings_data$experience_mode
    if (ai_on && identical(mode, "kesif") && !isTRUE(isolate(greeting_done()))) {
      shinyjs::delay(250, {
        trigger_greeting()
      })
    }
  })

  # Karşılama konuşmasını tetikleme fonksiyonu: önceden üretilmiş persona
  # karşılama WAV'ı (varsa kişisel önek ile) tek dizi olarak oynatılır.
  # Statik varlıklar üretilmemişse konuşma güvenle atlanır; başka bir sesle
  # karşılama SÖYLENMEZ (fail-closed) ve uygulama akışı bozulmaz.
  trigger_greeting <- function() {
    if (isTRUE(greeting_done())) return()
    if (!isTRUE(settings_data$enable_ai_expert)) return()
    if (!identical(settings_data$experience_mode, "kesif")) return()

    greeting_done(TRUE)

    selected_char_id <- normalize_character_id(isolate(settings_data$selected_character))
    dispatched <- speech_runtime$play_welcome(selected_char_id)

    if (isTRUE(dispatched)) {
      cat(sprintf("[AI_EXPERT] Statik karşılama dizisi başlatıldı (persona: %s).\n", selected_char_id))
    } else {
      cat(sprintf(
        "[AI_EXPERT] Statik karşılama varlıkları hazır değil (persona: %s); karşılama konuşması atlandı.\n",
        selected_char_id
      ))
    }

    schedule_idle_chat(ai_expert_first_idle_delay_ms(current_talk_frequency()))
  }

  # --- Boşta konuşma zamanlayıcısı yardımcısı ---
  schedule_idle_chat <- function(delay_ms = NULL) {
    if (is.null(delay_ms)) delay_ms <- ai_expert_idle_interval_ms(current_talk_frequency())
    shinyjs::delay(delay_ms, {
      trigger_idle_chat()
    })
  }

  # --- Sayfa geçişi rehberliği ---
  observeEvent(input$tabs, {
    page <- input$tabs
    ai_expert$set_page(page)

    # Tek yetkili rehberlik politikası: rehberli/sessiz sayfa kümeleri
    # R/config_speech_assets.R'de tanımlıdır. Sessiz yüzeye (Kişiselleştirme,
    # yönetici sayfaları, Sistem Durumu) geçişte aktif konuşma nazikçe durur;
    # özellikle persona tanıtım videosuyla üst üste binme engellenir.
    policy <- mergen_speech_guidance_policy(page)
    if (!identical(policy, "guided")) {
      # Ana Söyleşi'ye dönüş İSTİSNASI yalnızca karşılama/boşta konuşmasını
      # (kind="welcome"/"idle") KAPSAR; bu sayfa zaten karşılama tarafından
      # kapsanır ve durdurulmamalıdır. Ancak BAŞKA bir sayfadan sızmış bir
      # "page_guidance" klibi hâlâ çalıyorsa (kullanıcı hızlıca ileri-geri
      # gezindiyse) chat'e dönüşte de durmalıdır; aksi halde eski sayfaya
      # özgü rehberlik Ana Söyleşi'de çalmaya devam eder.
      should_stop_on_return <- !identical(page, "chat") ||
        identical(mergen_speech_active_kind(session), "page_guidance")
      if (should_stop_on_return && isTRUE(ai_expert$is_speaking())) {
        cat(sprintf("[AI_EXPERT] Sessiz sayfaya geçiş (%s), aktif konuşma durduruluyor.\n", page))
        ai_expert$stop_speaking(0)
      }

      # Ana Söyleşi'ye dönüşte ek rehberlik klibi OYNATILMAZ (karşılama bu
      # sayfayı kapsar); yalnızca boşta konuşma planlanır.
      if (identical(page, "chat") &&
          isTRUE(settings_data$enable_ai_expert) &&
          identical(settings_data$experience_mode, "kesif")) {
        schedule_idle_chat(15000)
      }
      return()
    }

    # Özellik kontrolü
    if (!isTRUE(settings_data$enable_ai_expert)) return()
    if (!identical(settings_data$experience_mode, "kesif")) return()

    # GECİKMESİZ: rehberlik klibi statik varlıktan anında seçilip gönderilir
    trigger_page_guidance(page)

  }, ignoreInit = TRUE)

  # Sayfa rehberliği konuşması: önceden üretilmiş persona WAV'ı oynatılır.
  # Gezinme anında LLM ÇAĞRILMAZ; metin ortak senaryo dosyasından gelir.
  trigger_page_guidance <- function(page) {
    # Temel kontrol: konuşuyor mu veya mesaj mı gönderiyor (bekleme süresini ATLA)
    if (!can_speak_basic()) return()

    # Aktif sayfanın hâlâ aynı olduğunu kontrol et (bayat gezinme koruması)
    current <- isolate(input$tabs)
    if (!identical(current, page)) return()

    now <- Sys.time()
    guidance_times <- isolate(page_guidance_times())
    last_guidance <- guidance_times[[page]]
    if (!is.null(last_guidance)) {
      elapsed <- as.numeric(difftime(now, last_guidance, units = "secs"))
      if (is.finite(elapsed) && elapsed < PAGE_GUIDANCE_REPEAT_SECS) {
        if (isTRUE(ai_expert$is_speaking())) ai_expert$stop_speaking(0)
        cat(sprintf("[AI_EXPERT] Sayfa rehberliği yakın zamanda oynatıldı, atlandı: %s\n", page))
        return()
      }
    }

    dispatched <- speech_runtime$play_page_guidance(page)
    if (isTRUE(dispatched)) {
      guidance_times[[page]] <- now
      page_guidance_times(guidance_times)
    }
    schedule_idle_chat()
  }

  # --- Boşta konuşma ---
  trigger_idle_chat <- function() {
    if (!isTRUE(settings_data$enable_ai_expert) ||
        !identical(settings_data$experience_mode, "kesif")) {
      schedule_idle_chat()
      return()
    }
    if (is_stt_modal_active()) {
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
    cat(sprintf("[AI_EXPERT] Etkin kullanıcı ID: %s\n", resolve_ai_expert_user_id()))

	params <- prepare_llm_params()
	current_page_val <- isolate(input$tabs) %||% "chat"

	page_name_tr <- ai_expert_page_name_tr(current_page_val) %||% "Ana Söyleşi"

	idle_count_val <- current_count
	session_msgs <- capture_session_messages(5)
	effective_user_id <- resolve_ai_expert_user_id()
	talk_length_val <- isolate(settings_data$ai_expert_talk_length) %||% "orta"
	talk_style_val <- isolate(settings_data$ai_expert_talk_style) %||% "profesyonel"

	u_name <- resolve_user_name(params$user_name)

	recent_prompts <- tryCatch(
	  fetch_recent_user_prompts(effective_user_id, 5),
	  error = function(e) NULL
	)

	user_work_context <- tryCatch(
	  fetch_user_work_context(effective_user_id),
	  error = function(e) NULL
	)

	generation_cfg <- get_ai_expert_generation_config(
	  scenario = "idle_chat",
	  talk_length = talk_length_val,
	  talk_style = talk_style_val
	)

	system_prompt <- build_ai_expert_system_prompt(
	  params$char_info, scenario = "idle_chat",
	  page_name = page_name_tr, user_name = u_name,
	  talk_length = talk_length_val, talk_style = talk_style_val
	)

	user_context <- build_ai_expert_idle_user_context(
	  page_name_tr = page_name_tr,
	  user_work_context = user_work_context,
	  idle_count = idle_count_val,
	  session_msgs = session_msgs,
	  recent_prompts = recent_prompts,
	  now_text = format(Sys.time(), "%d %B %Y %H:%M")
	)

	model_name_val <- params$model_name
	api_key_val <- params$api_key
	endpoint_val <- params$endpoint
	max_tokens_val <- generation_cfg$max_tokens
	temperature_val <- generation_cfg$temperature

	tracked_future_promise(
	  task_fn = function() {
		call_ai_expert_llm(
		  system_prompt = system_prompt,
		  user_context = user_context,
		  model_name = model_name_val,
		  api_key = api_key_val,
		  endpoint = endpoint_val,
		  max_tokens = max_tokens_val,
		  temperature = temperature_val
		)
	  },
	  task_type = "ai_expert_idle_chat",
	  session_token = session$token,
	  globals = list(
		call_ai_expert_llm = call_ai_expert_llm,
		system_prompt = system_prompt,
		user_context = user_context,
		model_name_val = model_name_val,
		api_key_val = api_key_val,
		endpoint_val = endpoint_val,
		max_tokens_val = max_tokens_val,
		temperature_val = temperature_val
	  )
	) %...>% (function(idle_text) {
      if (!is.null(idle_text) && nzchar(idle_text) && !is_stt_modal_active()) {
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
  
  observeEvent(input$stt_modal_active, {
    stt_active <- isTRUE(input$stt_modal_active)

    ai_expert$set_user_active(stt_active)

    if (stt_active && isTRUE(ai_expert$is_speaking())) {
      cat("[AI_EXPERT] STT modalı açıldı, AI konuşması durduruluyor.\n")
      ai_expert$stop_speaking()
    }

    if (!stt_active) {
      shinyjs::delay(1500, {
        if (!isTRUE(input$stt_modal_active) && !isTRUE(values$is_sending)) {
          ai_expert$set_user_active(FALSE)
        }
      })
    }
  }, ignoreInit = TRUE)

  # --- TTS seslendirmesi ile çakışma önleme ---
  # Kullanıcı istekli yanıt seslendirmesi en yüksek önceliktir: GERÇEK oynatma
  # başladığında konuşma durumunda "response_tts" aktifleşir ve otomatik
  # konuşmalar (karşılama/rehberlik/boşta) reddedilir; bitince durum temizlenir.
  observeEvent(input$tts_is_playing, {
    is_playing <- isTRUE(input$tts_is_playing)
    ai_expert$set_tts_vocalizing(is_playing)
    if (is_playing) {
      # Önce aktif AI konuşmasını durdur, SONRA response_tts durumunu kur.
      # stop_speaking() token'sız mergen_speech_end() çağırıp aktif konuşma
      # durumunu koşulsuz temizler; response_tts'i önce kurarsak stop_speaking
      # onu da siler ve öncelik matrisi kullanıcı isteği yanıt sesini görmez
      # (gezinme rehberliği yanıt sesinin üzerine konuşabilir). Sıralamayı ters
      # çevirmek response_tts durumunu korur.
      if (isTRUE(ai_expert$is_speaking())) {
        cat("[AI_EXPERT] TTS seslendirmesi başladı, AI konuşması durduruluyor.\n")
        ai_expert$stop_speaking()
      }
      mergen_speech_begin(session, "response_tts")
    } else if (identical(mergen_speech_active_kind(session), "response_tts")) {
      mergen_speech_end(session)
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}
