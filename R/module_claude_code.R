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

      # Windows + UNC + Türkçe karakterli dizinlerde cmd.exe kararsız çalışabildiği için
      # gerekirse yerel ASCII çalışma alanına aynala.
      # Aynı sohbette aynı kaynak için yapılan takip çağrılarında mevcut runtime
      # klasörünü yeniden kullan: Claude CLI --resume oturum metadatası bu klasöre
      # bağlı olduğundan her run için yeni runtime klasörü açmak
      # "No conversation found with session ID" hatasına yol açar.
      mevcut_runtime_workdir <- NULL
      if (!is.null(rv$active_runtime_source) &&
          !is.null(rv$active_runtime_workdir) &&
          identical(
            as.character(rv$active_runtime_source),
            as.character(calisma_dizini)
          )) {
        mevcut_runtime_workdir <- rv$active_runtime_workdir
      }

      runtime_dizin <- prepare_claude_runtime_workdir(
        calisma_dizini,
        user_id = effective_user_id,
        runtime_token = run_request_id,
        existing_runtime_workdir = mevcut_runtime_workdir
      )

      kaynak_calisma_dizini <- runtime_dizin$source_workdir %||% calisma_dizini
      calisma_dizini <- runtime_dizin$runtime_workdir %||% calisma_dizini
      mirror_kullanildi <- isTRUE(runtime_dizin$mirrored)

      # Aynalama yapıldıysa takip çağrılarında yeniden kullanmak üzere kaydet.
      if (isTRUE(mirror_kullanildi)) {
        rv$active_runtime_workdir <- calisma_dizini
        rv$active_runtime_source <- workdir_policy$path %||% kaynak_calisma_dizini
      }

      log_info(sprintf(
        "%s [RUNTIME_WORKDIR] original=%s | source=%s | runtime=%s | mirrored=%s",
        CLAUDE_CODE_LOG_PREFIX, workdir_policy$path %||% "",
        kaynak_calisma_dizini %||% "", calisma_dizini %||% "",
        isTRUE(mirror_kullanildi)
      ))

      dokuman_baglami <- prepare_claude_code_document_context(
        prompt = kullanici_prompt,
        runtime_workdir = calisma_dizini,
        source_workdir = kaynak_calisma_dizini,
        user_id = effective_user_id
      )

      log_info(sprintf(
        "%s [DOC_DEBUG_1] detected=%s | binary=%s | sidecars=%s | files=%d | errors=%d",
        CLAUDE_CODE_LOG_PREFIX, isTRUE(dokuman_baglami$document_task_detected),
        isTRUE(dokuman_baglami$has_binary_docs),
        isTRUE(dokuman_baglami$text_sidecars_ready),
        length(dokuman_baglami$prepared_files %||% list()),
        length(dokuman_baglami$extraction_errors %||% character(0))
      ))

      calistirma_promptu <- dokuman_baglami$prompt %||% kullanici_prompt

      if (isTRUE(dokuman_baglami$text_sidecars_ready)) {
        calisma_dizini <- dokuman_baglami$effective_workdir %||%
          dokuman_baglami$support_dir %||%
          calisma_dizini

        # Doküman destek dizini yalnızca düz metin çıkarımları içerir.
        # Modelin orijinal ikili dosyalara dönmemesi için çalışma dizini burada tutulur.
        # Bu nedenle kaynak klasöre geri senkronlama yapılmamalı.
        mirror_kullanildi <- FALSE

        showNotification(
          paste0(
            length(dokuman_baglami$prepared_files %||% list()),
            " doküman için yerel metin çıkarımı hazırlandı."
          ),
          type = "message",
          duration = 5
        )

        log_info(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Doküman görevi için yerel metin çıkarımları hazırlandı.",
          "Hazır dosya sayısı:",
          length(dokuman_baglami$prepared_files %||% list()),
          "| Rehber:",
          dokuman_baglami$manifest_path %||% "",
          "| Etkin çalışma dizini:",
          calisma_dizini
        ))
      }

      if (isTRUE(dokuman_baglami$has_binary_docs)) {
        model_cozumu <- list(
          allow_run = TRUE,
          model = model,
          fallback_used = FALSE,
          reason = "",
          selected_model = model
        )
      } else {
        model_cozumu <- resolve_claude_code_execution_model(
          selected_model = model,
          prompt = kullanici_prompt,
          workdir = kaynak_calisma_dizini %||% calisma_dizini,
          document_context = dokuman_baglami
        )
      }

      if (!isTRUE(model_cozumu$allow_run)) {
        cc_abort_run_before_streaming(rv, run_request_id)

        cc_send_run_blocked_message(
          session = session,
          ns = ns,
          message = model_cozumu$reason
        )

        return()
      }

      efektif_model <- model_cozumu$model %||% model

      if (!is.null(rv$current_runtime_model) &&
          !identical(rv$current_runtime_model, efektif_model)) {
        rv$cli_session_id <- NULL
        rv$conversation_context <- list()
        # Çalıştırılan model farklıysa Claude CLI oturumu yeni modelde yeniden
        # kurulacak; bu yüzden önceki runtime klasörünü de yeniden kullanma.
        rv$active_runtime_workdir <- NULL
        rv$active_runtime_source <- NULL

        log_info(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Çalıştırılan model değişti, CLI oturumu sıfırlandı. Yeni model:",
          efektif_model
        ))
      }

      rv$current_runtime_model <- efektif_model
      model <- efektif_model

      if (isTRUE(model_cozumu$fallback_used)) {
        showNotification(
          paste0(
            "Doküman uyumluluğu için geçici olarak düşünmeyen modele geçildi: ",
            efektif_model
          ),
          type = "warning",
          duration = 6
        )

        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Düşünen model doküman görevi için düşünmeyen modele yönlendirildi.",
          "Seçilen:", model_cozumu$selected_model,
          "| Çalıştırılan:", efektif_model
        ))
      }

      # Karakter bilgisini al
      karakter <- get_active_character()
      karakter_id <- karakter$id
      karakter_renk <- karakter$accent

      # Düşünme mesajını seç
      dusunme_mesaji <- get_thinking_message(karakter_id)

      # Kullanıcı adını al
      ad <- kullanici_adi()

      # Kalıcı oturum kaydını garanti et. Tablolar yoksa veya DB hatası
      # olursa sessizce bellek-içi moda düşer; çalıştırma asla engellenmez.
      if (exists("cc_persist_session_begin", mode = "function", inherits = TRUE)) {
        cc_persist_session_begin(
          rv = rv,
          user_id = effective_user_id,
          prompt = kullanici_prompt,
          workdir = workdir_policy$path %||% kaynak_calisma_dizini,
          source_workdir = kaynak_calisma_dizini,
          runtime_workdir = calisma_dizini,
          model = model,
          runtime_model = efektif_model,
          character_id = karakter_id
        )
      }

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

      # Zaman damgası (akış mesajları için)
      zaman_damgasi <- format(Sys.time(), "%H:%M:%S")
	  
      dokuman_gorevi_yerel_ozet_modu <- isTRUE(dokuman_baglami$has_binary_docs)

      if (isTRUE(dokuman_gorevi_yerel_ozet_modu)) {
        cc_handle_document_summary_run(
          session = session,
          ns = ns,
          rv = rv,
          run_request_id = run_request_id,
          dokuman_baglami = dokuman_baglami,
          model = model,
          zaman_asimi = zaman_asimi,
          kaynak_calisma_dizini = kaynak_calisma_dizini,
          calisma_dizini = calisma_dizini,
          effective_user_id = effective_user_id,
          kullanici_prompt = kullanici_prompt,
          karakter = karakter,
          karakter_id = karakter_id,
          karakter_renk = karakter_renk,
          finalize_streaming = finalize_streaming,
          observe_dir_contents = observe_dir_contents
        )

        return()
      }

      # -----------------------------------------------------------------------
      # CANLI AKIŞ: processx süreci başlat, akış durumunu rv'ye kaydet.
      # Yoklama ayrı bir observe() ile yapılır (invalidateLater ile).
      # Bu sayede sendCustomMessage mesajları reaktif döngü içinde kalarak
      # her yoklama turunda tarayıcıya zamanında iletilir.
      # -----------------------------------------------------------------------

      # Akış durumu ortamı (referans nesnesi - reaktif tetikleme yapmadan değiştirilebilir)
      stream_env <- new.env(parent = emptyenv())
      stream_env$baslangic <- Sys.time()
      stream_env$zaman_asimi <- zaman_asimi
      stream_env$karakter_renk <- karakter_renk
      stream_env$karakter_adi <- karakter$display_name
      stream_env$karakter_id <- karakter_id
      stream_env$zaman_damgasi <- zaman_damgasi
      stream_env$prompt <- kullanici_prompt
      stream_env$calisma_dizini <- calisma_dizini
      stream_env$kaynak_calisma_dizini <- kaynak_calisma_dizini
      stream_env$mirror_kullanildi <- mirror_kullanildi
      stream_env$user_id <- effective_user_id
      stream_env$session_token <- session$token %||% format(Sys.time(), "%Y%m%d%H%M%S")
      stream_env$request_id <- run_request_id
      stream_env$tum_satirlar <- character(0)
      stream_env$durduruldu <- FALSE
      stream_env$oturum_id <- NULL  # stream-json olaylarından gelecek

      # Çalıştırma öncesi çalışma dizini anlık görüntüsü
      # (Claude Code'un ürettiği .docx/.xlsx gibi dosyaları bash yoluyla
      # oluştursa bile tespit edebilmek için)
      stream_env$workdir_snapshot <- tryCatch(
        snapshot_claude_code_workdir_files(calisma_dizini),
        error = function(e) list()
      )

      rv$stream_env <- stream_env
      rv$poll_state <- stream_env

      # CLI argümanlarını merkezi güvenlik ilkesinden oluştur
      # stream-json formatı olayları gerçek zamanlı olarak satır satır verir
      # include-partial-messages ile metin parçaları da anlık gelir
      cli_args <- cc_policy_build_cli_args(
        prompt = calistirma_promptu,
        output_format = "stream-json",
        model = model,
        session_id = oturum_id,
        include_partial_messages = TRUE,
        verbose = TRUE,
        user_id = effective_user_id,
        settings_data = settings_data,
        workdir = kaynak_calisma_dizini %||% calisma_dizini
      )

      # Süreci başlat
      tryCatch({
        log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Canlı akış başlatılıyor"))

        # Windows'ta .cmd dosyalarını cmd.exe üzerinden çalıştır
        komut <- build_processx_command(cli_yolu, cli_args, workdir = calisma_dizini)

        # API anahtarı dosyaya yazılmaz; yalnızca bu process için ortam
        # değişkeni olarak aktarılır. Loglarda ham anahtar gösterilmez.
        komut$env <- cc_apply_runtime_api_key_env(
          env = komut$env,
          api_key = api_key_plan$key
        )

		proc <- processx::process$new(
		  command = komut$command,
		  args = komut$args,
		  env = komut$env,
		  wd = komut$wd %||% calisma_dizini,
		  stdout = "|",
		  stderr = "|",
		  cleanup = TRUE,
		  cleanup_tree = TRUE,
		  windows_verbatim_args = isTRUE(komut$windows_verbatim_args)
		)

        # Süreç referansını sakla (yoklama gözlemcisi ve durdurma için)
        rv$active_process <- proc
        # rv$is_running zaten TRUE - yoklama gözlemcisi otomatik başlayacak

      }, error = function(e) {
        cc_abort_run_before_streaming(rv, run_request_id)

        session$sendCustomMessage(
          type = "cc-finalize-ui",
          message = list(
            runBtnId = ns("run_command"),
            stopBtnId = ns("stop_command")
          )
        )

        session$sendCustomMessage(
          type = "cc-thinking-stop",
          message = list(
            overlayId = ns("thinking_overlay"),
            statusId = ns("status_text"),
            durationId = ns("duration_text")
          )
        )

        hata_metni <- conditionMessage(e)
        temiz_hata <- gsub("[{}]", "", hata_metni)
        log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Akış başlatma hatası:", temiz_hata))

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = paste0("Beklenmeyen hata: ", htmltools::htmlEscape(hata_metni)),
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )

        session$sendCustomMessage(
          type = "cc-update-status",
          message = list(
            statusId = ns("status_text"),
            durationId = ns("duration_text"),
            status = "Hata",
            statusIcon = "exclamation-triangle",
            statusColor = "#E57373",
            duration = ""
          )
        )
      })
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
      start_new_session = workbench_session_api$start_new_session
    )
  })
}