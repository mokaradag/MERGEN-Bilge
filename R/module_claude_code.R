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
                              user_first_name = NULL) {
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
      active_request_id = NULL        # Async/poll callback'leri için aktif çalışma kimliği
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
        rv$is_running <- FALSE
        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = "Claude Code CLI bulunamadı. Lütfen npm ile kurulu olduğundan emin olun.",
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )
        return()
      }

      # SSO akışında kimlik doğrulama tamamlanmadan komut çalıştırma.
      if (isTRUE(SSO_ENABLED) && !isTRUE(session$userData$auth_initialized)) {
        rv$is_running <- FALSE

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = "Kimlik doğrulama tamamlanmadan komut çalıştırılamaz.",
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )
        return()
      }

      # Çalışma dizini yoksa gerçek kullanıcı kimliği ile kullanıcı çalışma alanını kullan.
      user_check <- ensure_ready_user_id("komut çalıştırma")
      if (!isTRUE(user_check$ok)) {
        rv$is_running <- FALSE

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = user_check$message,
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )

        return()
      }

      effective_user_id <- user_check$user_id

      if (is.null(calisma_dizini) || !nzchar(calisma_dizini)) {
        if (effective_user_id > 0) {
          calisma_dizini <- get_user_workspace(effective_user_id)
        } else {
          rv$is_running <- FALSE

          session$sendCustomMessage(
            type = "cc-add-message",
            message = list(
              target = ns("output_area"),
              type = "error",
              content = "Kullanıcı çalışma alanı oluşturulamadı. Lütfen sayfayı yenileyin.",
              timestamp = format(Sys.time(), "%H:%M:%S"),
              welcomeId = ns("welcome_screen")
            )
          )
          return()
        }
      }

      # Windows + UNC + Türkçe karakterli dizinlerde cmd.exe kararsız çalışabildiği için
      # gerekirse yerel ASCII çalışma alanına aynala.
      runtime_dizin <- prepare_claude_runtime_workdir(
        calisma_dizini,
        user_id = effective_user_id,
        runtime_token = run_request_id
      )

      kaynak_calisma_dizini <- runtime_dizin$source_workdir %||% calisma_dizini
      calisma_dizini <- runtime_dizin$runtime_workdir %||% calisma_dizini
      mirror_kullanildi <- isTRUE(runtime_dizin$mirrored)

      dokuman_baglami <- prepare_claude_code_document_context(
        prompt = kullanici_prompt,
        runtime_workdir = calisma_dizini,
        source_workdir = kaynak_calisma_dizini,
        user_id = effective_user_id
      )

      log_info(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "[DOC_DEBUG_1] Doküman bağlamı oluşturuldu.",
        "document_task_detected =", isTRUE(dokuman_baglami$document_task_detected),
        "| has_binary_docs =", isTRUE(dokuman_baglami$has_binary_docs),
        "| text_sidecars_ready =", isTRUE(dokuman_baglami$text_sidecars_ready),
        "| prepared_files =", length(dokuman_baglami$prepared_files %||% list()),
        "| support_dir =", dokuman_baglami$support_dir %||% "",
        "| effective_workdir =", dokuman_baglami$effective_workdir %||% "",
        "| extraction_errors =",
        if (length(dokuman_baglami$extraction_errors %||% character(0))) {
          paste(dokuman_baglami$extraction_errors, collapse = " || ")
        } else {
          "(yok)"
        }
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
        rv$is_running <- FALSE

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = htmltools::htmlEscape(model_cozumu$reason),
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )

        return()
      }

      efektif_model <- model_cozumu$model %||% model

      if (!is.null(rv$current_runtime_model) &&
          !identical(rv$current_runtime_model, efektif_model)) {
        rv$cli_session_id <- NULL
        rv$conversation_context <- list()

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

      # CLI argümanlarını oluştur
      # stream-json formatı olayları gerçek zamanlı olarak satır satır verir
      # include-partial-messages ile metin parçaları da anlık gelir
      cli_args <- c(
        "--print",
        "--verbose",
        "--output-format", "stream-json",
        "--include-partial-messages",
        "--dangerously-skip-permissions"
      )
      if (!is.null(model) && nzchar(model)) {
        cli_args <- c(cli_args, "--model", model)
      }
      if (!is.null(oturum_id) && nzchar(oturum_id)) {
        cli_args <- c(cli_args, "--resume", oturum_id)
      }
      cli_args <- c(cli_args, calistirma_promptu)

      # Süreci başlat
      tryCatch({
        log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Canlı akış başlatılıyor"))

        # Windows'ta .cmd dosyalarını cmd.exe üzerinden çalıştır
        komut <- build_processx_command(cli_yolu, cli_args, workdir = calisma_dizini)

        proc <- processx::process$new(
          command = komut$command,
          args = komut$args,
          env = komut$env,
          wd = komut$wd %||% calisma_dizini,
          stdout = "|",
          stderr = "|",
          cleanup = TRUE,
          cleanup_tree = TRUE
        )

        # Süreç referansını sakla (yoklama gözlemcisi ve durdurma için)
        rv$active_process <- proc
        # rv$is_running zaten TRUE - yoklama gözlemcisi otomatik başlayacak

      }, error = function(e) {
        rv$is_running <- FALSE
        if (cc_is_active_run(rv, run_request_id)) {
          rv$active_request_id <- NULL
        }

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

    # --- Yoklama gözlemcisi ---
    observe({
      # Yalnızca akış aktifken çalış
      req(isTRUE(rv$is_running))
      proc <- rv$active_process
      req(!is.null(proc))

      # 200ms sonra tekrar çalış (reaktif döngü içinde)
      invalidateLater(200, session)

      env <- rv$stream_env
      if (is.null(env)) return()

      # Durdurma isteği kontrolü
      if (isTRUE(env$durduruldu)) {
        tryCatch(proc$kill(), error = function(e) NULL)
        finalize_streaming("Durduruldu", "stop-circle", "#FFB74D", request_id = env$request_id)
        return()
      }

      # Zaman aşımı kontrolü
      gecen_sure <- as.numeric(difftime(Sys.time(), env$baslangic, units = "secs"))
      if (gecen_sure > env$zaman_asimi) {
        tryCatch(proc$kill(), error = function(e) NULL)
        log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Akış zaman aşımı:", env$zaman_asimi, "sn"))
        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = paste0("İşlem zaman aşımına uğradı (", env$zaman_asimi, " saniye)."),
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )
        finalize_streaming("Zaman Aşımı", "clock", "#FFB74D", request_id = env$request_id)
        return()
      }

      # stdout'tan oku
      tryCatch({
        proc$poll_io(0)
        # Windows'ta processx yerel kodlama kullanır; UTF-8'e dönüştür
        yeni_satirlar <- tryCatch(ensure_utf8(proc$read_output_lines()), error = function(e) character(0))

        if (length(yeni_satirlar) > 0) {
          for (satir in yeni_satirlar) {
            satir <- trimws(satir)
            if (!nzchar(satir)) next
            env$tum_satirlar <- c(env$tum_satirlar, satir)

            # Parçayı ayrıştır ve istemciye gönder
            parca <- parse_streaming_chunk(satir)
            send_parca(parca, env)
          }
        }
      }, error = function(e) {
        log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Akış okuma hatası:",
                       conditionMessage(e)))
      })

      # Süreç bitmişse sonlandır
      if (!proc$is_alive()) {
        # Kalan çıktıyı oku
        tryCatch({
          kalan <- ensure_utf8(proc$read_all_output())
          if (nzchar(kalan)) {
            kalan_satirlar <- strsplit(kalan, "\n")[[1]]
            for (satir in kalan_satirlar) {
              satir <- trimws(satir)
              if (!nzchar(satir)) next
              env$tum_satirlar <- c(env$tum_satirlar, satir)

              parca <- parse_streaming_chunk(satir)
              send_parca(parca, env)
            }
          }
        }, error = function(e) NULL)

        # Tam çıktıyı ayrıştır (stream-json ve eski json formatı uyumlu)
        tam_cikti <- paste(env$tum_satirlar, collapse = "\n")
        ayristirma <- parse_claude_code_json_output(tam_cikti)
        cikis_kodu <- proc$get_exit_status()
        sure <- round(as.numeric(difftime(Sys.time(), env$baslangic, units = "secs")), 1)

        if (identical(cikis_kodu, 0L)) {
          log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Akış tamamlandı - Süre:", sure, "sn"))

          # Oturum kimliğini kaydet (akış sırasında veya ayrıştırma sonucu)
          oturum_id <- env$oturum_id %||% ayristirma$session_id
          if (!is.null(oturum_id) && nzchar(oturum_id %||% "")) {
            rv$cli_session_id <- oturum_id
          }

          # Konuşma bağlamına ekle
          rv$conversation_context <- c(rv$conversation_context, list(
            list(role = "assistant", content = ayristirma$text_output)
          ))

          # Üretilen dosyaları yerel indirme bağlantılarına dönüştür.
          # Çalıştırma öncesi snapshot ile dizin farkını alarak Claude Code'un
          # Bash aracılığıyla python-docx / openpyxl / officer gibi yollarla
          # oluşturduğu .docx ve .xlsx dosyalarını da yakalar. Ayrıca üretilen
          # .txt dosyalarının Türkçe karakter kodlamasını UTF-8 BOM olarak
          # normalize eder (Windows Notepad mojibake düzeltmesi).
          olusan_dosyalar <- collect_claude_code_workdir_changes_downloads(
            before_snapshot = env$workdir_snapshot,
            tool_uses = ayristirma$tool_uses,
            runtime_workdir = env$calisma_dizini,
            source_workdir = env$kaynak_calisma_dizini,
            user_id = env$user_id,
            session_token = env$session_token
          )

          # Akış mesajını sonlandır
          # stream-json modunda metin zaten anlık gösterildiği için
          # finalContent yalnızca yedek olarak gönderilir
          son_icerik <- paste0(
            format_claude_code_output(ayristirma$text_output),
            format_claude_code_generated_downloads_html(olusan_dosyalar)
          )

          session$sendCustomMessage(
            type = "cc-stream-end",
            message = list(
              target = ns("output_area"),
              duration = sure,
              finalContent = son_icerik,
              accentColor = env$karakter_renk,
              characterName = env$karakter_adi
            )
          )

          # Sonucu sakla
          rv$last_result <- list(
            success = TRUE,
            output = ayristirma$text_output,
            error = "",
            duration = sure,
            tool_uses = ayristirma$tool_uses,
            session_id = oturum_id,
            generated_downloads = olusan_dosyalar
          )

          finalize_streaming("Tamamlandı", "check-circle", "#81C784", sure, request_id = env$request_id)
        } else {
          # Hata durumu
          stderr_metin <- tryCatch(ensure_utf8(proc$read_all_error()), error = function(e) "")
          hata_mesaji <- if (nzchar(stderr_metin)) stderr_metin else tam_cikti
          temiz_log <- gsub("[{}]", "", substr(hata_mesaji, 1, 200))
          log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Akış hata kodu:", cikis_kodu,
                         "- Mesaj:", temiz_log))

          session$sendCustomMessage(
            type = "cc-stream-end",
            message = list(target = ns("output_area"))
          )

          session$sendCustomMessage(
            type = "cc-add-message",
            message = list(
              target = ns("output_area"),
              type = "error",
              content = htmltools::htmlEscape(hata_mesaji),
              timestamp = format(Sys.time(), "%H:%M:%S"),
              welcomeId = ns("welcome_screen")
            )
          )

          finalize_streaming("Hata", "exclamation-triangle", "#E57373", sure, request_id = env$request_id)
        }

        # Geçmişe ekle
        rv$output_history <- c(rv$output_history, list(list(
          prompt = env$prompt,
          result = rv$last_result,
          timestamp = Sys.time(),
          character = env$karakter_id
        )))

        # Yerel aynalama kullanıldıysa değişiklikleri kaynak klasöre geri yaz
        if (isTRUE(env$mirror_kullanildi)) {
          tryCatch(
            sync_claude_runtime_workdir_back(
              runtime_workdir = env$calisma_dizini,
              source_workdir = env$kaynak_calisma_dizini
            ),
            error = function(e) {
              log_warn(paste(
                CLAUDE_CODE_LOG_PREFIX,
                "Yerel çalışma alanı geri senkronlanamadı:",
                conditionMessage(e)
              ))
            }
          )
        }

        # Dizin içeriğini kaynak klasörden güncelle
        observe_dir_contents(
          dizin = env$kaynak_calisma_dizini %||% env$calisma_dizini
        )
      }
    })

    # --- Durdur düğmesi ---
    observeEvent(input$stop_command, {
      if (isTRUE(rv$is_running)) {
        env <- rv$stream_env %||% rv$poll_state
        request_id <- if (!is.null(env)) {
          env$request_id %||% rv$active_request_id
        } else {
          rv$active_request_id
        }

        # Yoklama döngüsüne durdurma sinyali gönder (ortam değişkeni ile)
        if (!is.null(env)) {
          env$durduruldu <- TRUE
        }

        # Aktif süreci sonlandır. active_process burada elle NULL yapılmaz;
        # finalize_streaming() tek noktadan UI ve state temizliği yapar.
        proc <- rv$active_process
        if (!is.null(proc)) {
          tryCatch({
            proc$kill()
            log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Süreç kullanıcı tarafından durduruldu"))
          }, error = function(e) NULL)
        }

        # Poll observer artık active_process=NULL nedeniyle stop branch'e
        # ulaşamayabileceği için UI finalize işlemini stop observer içinde
        # idempotent olarak tamamla.
        session$sendCustomMessage(
          type = "cc-stream-end",
          message = list(target = ns("output_area"))
        )

        finalize_streaming(
          "Durduruldu",
          "stop-circle",
          "#FFB74D",
          request_id = request_id
        )
      }
    })

    # --- Klavye Kısayolu: Enter ile gönderme ---
    observeEvent(input$prompt_submit_key, {
      # JavaScript tarafından tetiklenir (Ctrl+Enter veya Shift+Enter)
      if (!isTRUE(rv$is_running)) {
        shinyjs::click("run_command")
      }
    })

    invisible(NULL)
  })
}