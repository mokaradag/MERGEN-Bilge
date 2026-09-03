# ==============================================================================
# Dosya Yolu: R/module_claude_code.R
# Açıklama: Claude Code entegrasyon modülünün ana sunucu dosyası.
#           UI tanımı R/module_claude_code_ui.R dosyasında tanımlıdır.
#           Canlı akış yardımcıları module_claude_code_akis.R dosyasında tanımlıdır.
# ==============================================================================

# ==============================================================================
# CLAUDE CODE SERVER
# ==============================================================================

claudeCodeServer <- function(id, current_user_id, settings_data = NULL,
                              user_first_name = NULL, parent_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Etkin kullanıcı kimliği Bilge Yolaç setup yardımcıları içinde canlı
    # sağlayıcıyla çözülür; SSO hazır olmadan user_id=0 ile devam edilmez.

    # Kullanıcının gerçek yükleme klasörünü çözme sorumluluğu
    # R/helpers_claude_code_upload_folder.R içinde tutulur.

    # Reaktif değerler
    rv <- reactiveValues(
      is_running = FALSE,
      output_history = list(),
      last_result = NULL,
      connection_ok = NULL,
      cli_path_resolved = NULL,
      has_messages = FALSE,
      conversation_context = list(),  # Bağlam koruma için konuşma geçmişi
      cli_session_id = NULL,          # Claude Code CLI oturum kimliği (--resume için)
      current_model = NULL,           # Arayüzde seçili model takibi
      current_runtime_model = NULL,   # Gerçekte çalıştırılan model takibi
      active_process = NULL,          # Aktif processx süreci (durdurma için)
      poll_state = NULL,              # Yoklama durumu (ortam değişkeni, durdurma için)
      stream_env = NULL,              # Akış durumu (yoklama gözlemcisi için)
      active_request_id = NULL,       # Async/poll callback'leri için aktif çalışma kimliği
      # Takip eden sorularda Claude CLI --resume oturumunun bozulmaması için
      # aynalanmış runtime klasörünü ve onun kaynak workdir eşleşmesini sakla.
      active_runtime_workdir = NULL,
      active_runtime_source = NULL,
      # Kalıcı oturum (MB_ClaudeCode_Sessions) bağları: kayıt kimliği, başlık,
      # hidrasyonla yüklenme durumu ve tablo erişilebilirlik önbelleği.
      claude_session_record_id = NULL,
      claude_session_loaded = FALSE,
      claude_session_title = NULL,
      claude_session_persistence_available = NULL,
      # Oturum hidrasyonu workdir'i geri yüklerken input$workdir observer'ının
      # oturum bağlarını sıfırlamasını bir defalığına bastırır.
      suppress_workdir_reset_once = FALSE
    )
	
    dir_refresh_guard <- cc_create_dir_refresh_guard()
	
    server_setup <- cc_bind_server_setup(
      input = input,
      output = output,
      session = session,
      ns = ns,
      rv = rv,
      current_user_id = current_user_id,
      settings_data = settings_data,
      user_first_name = user_first_name,
      dir_refresh_guard = dir_refresh_guard
    )

    resolve_current_user_id <- server_setup$resolve_current_user_id
    ensure_ready_user_id <- server_setup$ensure_ready_user_id
    get_active_character <- server_setup$get_active_character
    kullanici_adi <- server_setup$kullanici_adi
    observe_dir_contents <- server_setup$observe_dir_contents

    # --- Ana Komut Çalıştırma (Canlı Akış Destekli) ---
    observeEvent(input$run_command, {
      prompt <- NULL

      # JavaScript'ten gelen prompt değerini oku
      prompt_from_js <- input$prompt_value
      if (!is.null(prompt_from_js) && nzchar(trimws(prompt_from_js))) {
        prompt <- trimws(prompt_from_js)
      }

      # Boş kontrolü
      if (is.null(prompt) || !nzchar(prompt)) return()
      kullanici_prompt <- prompt
      calistirma_promptu <- prompt

      # Çift tıklama koruması
      if (isTRUE(rv$is_running)) return()
      run_request_id <- cc_next_run_request_id()
      cc_mark_active_run(rv, run_request_id)
      rv$is_running <- TRUE

      # Ayarları al
      cli_yolu <- rv$cli_path_resolved
      calisma_dizini <- input$workdir
      model <- input$model
      zaman_asimi <- isolate({
        if (!is.null(settings_data) && !is.null(settings_data$claude_code_timeout)) {
          settings_data$claude_code_timeout
        } else {
          claude_code_config$timeout_seconds
        }
      })

      # CLI yolu yoksa hata ver
      if (is.null(cli_yolu)) {
        cc_abort_run_before_streaming(rv, run_request_id)
        cc_send_run_blocked_message(
          session = session,
          ns = ns,
          message = "Claude Code CLI bulunamadı. Lütfen npm ile kurulu olduğundan emin olun."
        )
        return()
      }

      # SSO akışında kimlik doğrulama tamamlanmadan komut çalıştırma.
      if (isTRUE(SSO_ENABLED) && !isTRUE(session$userData$auth_initialized)) {
        cc_abort_run_before_streaming(rv, run_request_id)

        cc_send_run_blocked_message(
          session = session,
          ns = ns,
          message = "Kimlik doğrulama tamamlanmadan komut çalıştırılamaz."
        )
        return()
      }

      # Çalışma dizini yoksa gerçek kullanıcı kimliği ile kullanıcı çalışma alanını kullan.
      user_check <- ensure_ready_user_id("komut çalıştırma")
      if (!isTRUE(user_check$ok)) {
        cc_abort_run_before_streaming(rv, run_request_id)

        cc_send_run_blocked_message(
          session = session,
          ns = ns,
          message = user_check$message
        )

        return()
      }

      effective_user_id <- user_check$user_id

      api_key_plan <- cc_resolve_runtime_api_key(session)
      if (!isTRUE(api_key_plan$ok)) {
        cc_abort_run_before_streaming(rv, run_request_id)

        cc_send_run_blocked_message(
          session = session,
          ns = ns,
          message = api_key_plan$message
        )

        return()
      }

      if (is.null(calisma_dizini) || !nzchar(calisma_dizini)) {
        if (effective_user_id > 0) {
          calisma_dizini <- get_user_workspace(effective_user_id)
        } else {
          cc_abort_run_before_streaming(rv, run_request_id)

          cc_send_run_blocked_message(
            session = session,
            ns = ns,
            message = "Kullanıcı çalışma alanı oluşturulamadı. Lütfen sayfayı yenileyin."
          )
          return()
        }
      }

      workdir_policy <- cc_prepare_safe_workdir_for_run(
        session = session,
        ns = ns,
        rv = rv,
        request_id = run_request_id,
        workdir = calisma_dizini,
        user_id = effective_user_id,
        prompt = kullanici_prompt
      )
      if (!isTRUE(workdir_policy$ok)) return()

      calisma_dizini <- workdir_policy$path

      # Karakter bilgisini al
      karakter <- get_active_character()
      karakter_id <- karakter$id
      karakter_renk <- karakter$accent

      # Düşünme mesajını seç
      dusunme_mesaji <- get_thinking_message(karakter_id)

      # Kullanıcı adını al
      ad <- kullanici_adi()

      # Karşılama ekranını gizle, mesaj alanı aktif
      rv$has_messages <- TRUE

      # Konuşma bağlamına ekle
      rv$conversation_context <- c(rv$conversation_context, list(
        list(role = "user", content = kullanici_prompt)
      ))

      # Oturum kimliğini yakala
      oturum_id <- rv$cli_session_id

      # Kullanıcı komutunu çıktıya ekle
      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "user",
          content = htmltools::htmlEscape(kullanici_prompt),
          timestamp = format(Sys.time(), "%H:%M:%S"),
          senderName = ad,
          welcomeId = ns("welcome_screen")
        )
      )

      # Düşünme animasyonunu başlat
      session$sendCustomMessage(
        type = "cc-thinking-start",
        message = list(
          overlayId = ns("thinking_overlay"),
          textId = ns("thinking_text"),
          canvasId = ns("pixel_canvas"),
          statusId = ns("status_text"),
          durationId = ns("duration_text"),
          message = dusunme_mesaji,
          characterId = karakter_id,
          accentColor = karakter_renk
        )
      )

      # Prompt giriş alanını temizle
      shinyjs::runjs(sprintf(
        "var el = document.getElementById('%s'); if(el) el.value = '';",
        ns("prompt_input")
      ))
      shinyjs::disable("run_command")
      shinyjs::runjs(sprintf(
        "document.getElementById('%s').classList.remove('cc-hidden');",
        ns("stop_command")
      ))

      # Pahalı dosya sistemi hazırlığı (sınırlı tarama, gerekli girdi
      # dosyalarının kopyalanması, doküman metin çıkarımı ve çalıştırma
      # öncesi çıktı anlık görüntüsü) ana Shiny sürecinde YAPILMAZ. Bu iş
      # arka plan worker'ına gönderilir; böylece büyük bir klasör seçen tek
      # bir kullanıcı diğer oturumları bloke edemez.
      cc_dispatch_run_preparation(list(
        session = session,
        ns = ns,
        rv = rv,
        run_request_id = run_request_id,
        user_id = effective_user_id,
        workdir = calisma_dizini,
        prompt = kullanici_prompt,
        explicit_files = character(0),
        model = model,
        timeout = zaman_asimi,
        settings_data = settings_data,
        cli_path = cli_yolu,
        api_key = api_key_plan$key,
        character = karakter,
        character_id = karakter_id,
        accent = karakter_renk,
        user_name = ad,
        finalize_streaming = finalize_streaming,
        observe_dir_contents = observe_dir_contents
      ))
    })

    # =====================================================================
    # CANLI AKIŞ YOKLAMA GÖZLEMCİSİ
    # observe + invalidateLater ile reaktif döngü içinde çalışır.
    # Bu sayede sendCustomMessage mesajları her turda tarayıcıya iletilir.
    # later::later kullanıldığında mesajlar reaktif döngü dışında kalarak
    # birikir ve yalnızca süreç bittiğinde toplu gönderilirdi.
    # =====================================================================

    # --- Eklenti yönetimi (module_claude_code_plugins.R) ---
    claudeCodePluginsServer(input, output, session, ns, rv)

    # --- Akış yardımcıları (module_claude_code_akis.R) ---
    akis <- create_akis_yardimcilari(session, ns, rv)
    send_parca <- akis$send_parca
    finalize_streaming <- akis$finalize_streaming
	
	cc_bind_claude_code_stream_polling(
	  input = input,
	  session = session,
	  ns = ns,
	  rv = rv,
	  send_parca = send_parca,
	  finalize_streaming = finalize_streaming,
	  observe_dir_contents = observe_dir_contents
	)

    # --- Çalışma alanı başlığındaki kompakt "Oturumlar" bağlantısı ---
    observeEvent(input$open_sessions_page, {
      if (!is.null(parent_session)) {
        shinydashboard::updateTabItems(parent_session, "tabs", "claude_code_sessions")
      }
    })

    # --- Oturumlar sayfasına açılan oturum API'si ---
    # Kayıtlı oturumu çalışma alanına yükleme (hidrasyon) ve yeni oturum
    # başlatma; ayrıntılar R/helpers_claude_code_workbench_session_api.R.
    workbench_session_api <- cc_create_workbench_session_api(
      session = session,
      input = input,
      ns = ns,
      rv = rv,
      ensure_ready_user_id = ensure_ready_user_id,
      get_active_character = get_active_character,
      kullanici_adi = kullanici_adi
    )

    list(
      load_persisted_session = workbench_session_api$load_persisted_session,
      start_new_session = workbench_session_api$start_new_session,
      detach_archived_session = workbench_session_api$detach_archived_session
    )
  })
}
