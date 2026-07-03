# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_server_setup.R
# Açıklama: Bilge Yolaç sunucu modülünün başlangıç, kimlik, karakter, çalışma
#           dizini ve dizin gezgini observer bağlama sorumluluklarını toplar.
# ==============================================================================

cc_bind_server_setup <- function(input,
                                 output,
                                 session,
                                 ns,
                                 rv,
                                 current_user_id,
                                 settings_data = NULL,
                                 user_first_name = NULL,
                                 dir_refresh_guard) {
  resolve_current_user_id <- function() {
    cc_resolve_effective_user_id(
      session = session,
      current_user_id = current_user_id
    )
  }

  ensure_ready_user_id <- function(action_label = "işlem") {
    cc_require_ready_user_id(
      session = session,
      current_user_id = current_user_id,
      sso_enabled = SSO_ENABLED,
      action_label = action_label
    )
  }

  # --- Uygulama başladığında CLI yolunu otomatik tespit et ---
  observe({
    yol <- resolve_claude_cli_path(claude_code_config$cli_path)
    rv$cli_path_resolved <- yol
  }, priority = 100)

  # --- SSO modunda varsayılan çalışma dizinini kullanıcının profiline ayarla ---
  observe({
    req(isTRUE(SSO_ENABLED))
    req(isTRUE(session$userData$auth_initialized))

    # Yapılandırmada açıkça bir yol belirtilmemişse kullanıcı profilini kullan
    if (nzchar(claude_code_config$default_workdir)) return()

    kullanici <- session$userData$system_username
    req(!is.null(kullanici), nzchar(kullanici))

    if (.Platform$OS.type == "windows") {
      profil <- file.path("C:/Users", kullanici)
    } else {
      profil <- file.path("/home", kullanici)
    }

    if (dir.exists(profil)) {
      updateTextInput(session, "workdir", value = normalizePath(profil, winslash = "/"))
    }
  }, priority = 90)

  # --- Otomatik bağlantı testi (açılış kritik yolundan ERTELENİR) ---
  # check_claude_code_status(), `claude.cmd --version` alt sürecini SENKRON
  # çalıştırır (processx + proc$wait). Windows .cmd/UNC ortamında bu birkaç
  # saniye sürebilir. Doğrudan oturum açılışında çalıştırılırsa Shiny olay
  # döngüsünü bloke eder ve açılış ilerleme çubuğunu "takılı" gösterir (boot
  # kontrol noktaları tek seferde toplu olarak akar). Bu nedenle alt süreç testi,
  # açılış kontrol noktaları (kimlik/dosya/karşılama/medya) tipik olarak akıp
  # bittikten SONRA kısa bir gecikmeyle çalıştırılır. Bağlantı rozeti yalnızca
  # Bilge Yolaç sayfasında görünür ve o ana kadar "kontrol ediliyor" durumunda
  # kalır; bu yüzden erteleme görünür bir UX gerilemesi yaratmaz.
  cc_baglanti_testi_planlandi <- FALSE

  cc_run_connection_check <- function() {
    if (!is.null(rv$connection_ok)) return(invisible(NULL))

    cli_yolu <- rv$cli_path_resolved
    if (is.null(cli_yolu)) {
      rv$connection_ok <- FALSE
      return(invisible(NULL))
    }

    durum <- tryCatch({
      check_claude_code_status(cli_yolu)
    }, error = function(e) {
      list(installed = FALSE)
    })

    if (isTRUE(durum$installed)) {
      rv$connection_ok <- TRUE
      log_info(paste(CLAUDE_CODE_LOG_PREFIX, "CLI erişilebilir:", durum$version))
    } else {
      rv$connection_ok <- FALSE
      temiz_hata <- gsub("[{}]", "", durum$error %||% "")
      log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "CLI erişilemez:", temiz_hata))
    }

    invisible(NULL)
  }

  observe({
    req(is.null(rv$connection_ok))
    req(!is.null(rv$cli_path_resolved))
    if (isTRUE(cc_baglanti_testi_planlandi)) return()
    cc_baglanti_testi_planlandi <<- TRUE

    # Alt süreç testini açılış ilerleme çubuğunu bloke etmeyecek şekilde ertele.
    shinyjs::delay(6000, {
      cc_run_connection_check()
    })
  }, priority = 50)

  # --- Yapılandırma sayfasından bağlantı testi sonucunu dinle ---
  observe({
    req(!is.null(settings_data))

    zaman_asimi <- settings_data$claude_code_timeout
    if (!is.null(zaman_asimi)) {
      # Zaman aşımı ayarı değiştiğinde not al (iletişim aktif)
    }
  })

  # --- Yapılandırma sayfasından bağlantı testi sonucu geldiğinde güncelle ---
  observe({
    req(!is.null(settings_data))

    yapilandirma_sonucu <- settings_data$claude_code_connection_ok
    if (!is.null(yapilandirma_sonucu)) {
      rv$connection_ok <- yapilandirma_sonucu
    }
  })

  # --- Aktif karakter bilgisini al ---
  get_active_character <- cc_create_active_character_reactive(settings_data)

  # --- Karakter değiştiğinde temayı güncelle ---
  observe({
    karakter <- get_active_character()

    session$sendCustomMessage(
      type = "cc-update-theme",
      message = list(
        characterId = karakter$id,
        accentColor = karakter$accent,
        accentHover = karakter$accent_hover %||% karakter$accent,
        displayName = karakter$display_name
      )
    )
  })

  # --- Yazı tipi boyutu değiştiğinde Claude Code sayfasına uygula ---
  observe({
    req(!is.null(settings_data))

    boyut <- settings_data$font_size
    if (!is.null(boyut) && nzchar(boyut)) {
      session$sendCustomMessage(
        type = "cc-update-font-size",
        message = list(size = boyut)
      )
    }
  })

  # --- Kullanıcı adını belirle ---
  kullanici_adi <- cc_create_user_first_name_reactive(
    session = session,
    user_first_name = user_first_name
  )

  # --- Bağlantı Durumu Rozeti ---
  output$connection_status_badge <- renderUI({
    durum <- rv$connection_ok

    if (is.null(durum)) {
      tags$span(
        class = "cc-status-badge cc-status-checking",
        icon("spinner", class = "fa-spin"),
        "Kontrol ediliyor..."
      )
    } else if (isTRUE(durum)) {
      tags$span(
        class = "cc-status-badge cc-status-ok",
        icon("check-circle"),
        "Bağlı"
      )
    } else {
      tags$span(
        class = "cc-status-badge cc-status-error",
        icon("times-circle"),
        "Bağlantı Yok"
      )
    }
  })

  # --- Aktif Karakter Göstergesi ---
  output$active_character_indicator <- renderUI({
    karakter <- get_active_character()

    tags$span(
      class = "cc-character-badge",
      style = paste0("background-color: ", karakter$accent, ";"),
      karakter$display_name
    )
  })

  # --- Kullanıcının yükleme klasörüne yönlendirme ---
  observeEvent(input$go_upload_folder, {
    user_check <- ensure_ready_user_id("yükleme klasörüne geçiş")
    if (!isTRUE(user_check$ok)) {
      showNotification(user_check$message, type = "warning", duration = 5)
      return()
    }

    user_id <- user_check$user_id
    yukle_dizin <- cc_resolve_real_upload_folder(
      user_id,
      session_file_registry = session$userData$current_session_files
    )

    if (is.null(yukle_dizin) || !nzchar(yukle_dizin)) {
      showNotification(
        "Kullanıcının yükleme klasörü bulunamadı.",
        type = "warning",
        duration = 5
      )
      return()
    }

    updateTextInput(session, "workdir", value = yukle_dizin)

    log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Yükleme klasörüne gidildi:",
      yukle_dizin,
      "(user_id=", user_id, ")"
    ))
  })

  # --- Yerel klasör yükleme ---
  observeEvent(input$yerel_klasor, {
    dosyalar <- input$yerel_klasor
    req(nrow(dosyalar) > 0)

    yollar_json <- input$yerel_klasor_yollar
    yollar <- if (!is.null(yollar_json) && nzchar(yollar_json)) {
      tryCatch(jsonlite::fromJSON(yollar_json), error = function(e) NULL)
    }

    user_check <- ensure_ready_user_id("yerel klasör yükleme")
    if (!isTRUE(user_check$ok)) {
      showNotification(user_check$message, type = "warning", duration = 5)
      return()
    }

    user_id <- user_check$user_id
    calisma_alani <- get_user_workspace(user_id)

    dosya_sayisi <- 0L
    for (i in seq_len(nrow(dosyalar))) {
      goreceli <- if (!is.null(yollar) && length(yollar) >= i) {
        yollar[i]
      } else {
        dosyalar$name[i]
      }

      hedef <- file.path(calisma_alani, goreceli)
      hedef_dizin <- dirname(hedef)

      if (!dir.exists(hedef_dizin)) {
        dir.create(hedef_dizin, recursive = TRUE, showWarnings = FALSE)
      }

      file.copy(dosyalar$datapath[i], hedef, overwrite = TRUE)
      dosya_sayisi <- dosya_sayisi + 1L
    }

    updateTextInput(session, "workdir", value = normalizePath(calisma_alani, winslash = "/"))

    showNotification(
      paste0(dosya_sayisi, " dosya yerel bilgisayardan yüklendi."),
      type = "message",
      duration = 5
    )

    log_info(paste(
      CLAUDE_CODE_LOG_PREFIX,
      dosya_sayisi,
      "dosya yerel klasörden yüklendi:",
      calisma_alani
    ))
  })

  # --- Model değiştiğinde oturumu sıfırla ---
  observeEvent(input$model, {
    if (!is.null(rv$current_model) && !identical(rv$current_model, input$model)) {
      rv$cli_session_id <- NULL
      rv$conversation_context <- list()
      # Model değiştiğinde CLI oturumu farklı bir oturuma bağlanacağı için
      # önceki aynalanmış runtime klasörünü yeniden kullanma; taze bir
      # runtime klasörü oluşturulsun.
      rv$active_runtime_workdir <- NULL
      rv$active_runtime_source <- NULL

      # Kalıcı oturum bağını kopar (geçmiş silinmez); bir sonraki çalıştırma
      # yeni bir kalıcı oturum kaydı açar.
      if (exists("cc_persist_detach_session", mode = "function", inherits = TRUE)) {
        cc_persist_detach_session(rv)
      }

      log_info(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Model değişti, oturum sıfırlandı. Yeni model:",
        input$model
      ))
    }

    rv$current_model <- input$model
  }, ignoreInit = TRUE)

  # --- Senaryo Düğmeleri ---
  lapply(claude_code_scenarios, function(senaryo) {
    observeEvent(input[[paste0("scenario_", senaryo$id)]], {
      if (nzchar(senaryo$sablon)) {
        shinyjs::runjs(sprintf(
          "var el = document.getElementById('%s'); if(el) { el.value = %s; el.focus(); }",
          ns("prompt_input"),
          jsonlite::toJSON(senaryo$sablon, auto_unbox = TRUE)
        ))
      }
    })
  })

  # --- Dizin İçeriğini Göster ---
  observe_dir_contents <- function(dizin = NULL) {
    refresh_id <- dir_refresh_guard$next_id()
    yol <- dizin %||% isolate(input$workdir)

    if (is.null(yol) || !nzchar(yol)) {
      output$dir_contents_ui <- renderUI({
        if (!dir_refresh_guard$is_latest(refresh_id)) return(NULL)
        tags$p(class = "cc-dir-empty", "Proje dizini belirtilmedi.")
      })
      return(invisible(FALSE))
    }

    user_check <- ensure_ready_user_id("proje dizini listeleme")
    if (!isTRUE(user_check$ok)) {
      output$dir_contents_ui <- renderUI({
        if (!dir_refresh_guard$is_latest(refresh_id)) return(NULL)
        tags$p(class = "cc-dir-empty", user_check$message)
      })
      return(invisible(FALSE))
    }

    icerik <- list_directory_contents(
      yol,
      user_id = user_check$user_id
    )

    if (!dir_refresh_guard$is_latest(refresh_id)) {
      return(invisible(FALSE))
    }

    resolved_yol <- icerik$resolved_path %||% yol

    session$sendCustomMessage(
      type = "cc-update-element-text",
      message = list(
        elementId = ns("dir_current_path"),
        text = resolved_yol
      )
    )

    output$dir_contents_ui <- renderUI({
      if (!dir_refresh_guard$is_latest(refresh_id)) return(NULL)
      cc_build_dir_contents_ui(icerik, ns = ns)
    })

    invisible(TRUE)
  }

  observeEvent(input$dir_navigate, {
    req(input$dir_navigate)

    yeni_yol <- input$dir_navigate
    if (dir.exists(yeni_yol)) {
      # NOT: normalizePath() Windows VM'de UNC yolunu mapped drive harfine
      # (örn. //rehisds/... -> M:/rehisds/...) çözüyor. Mapped harf yerel
      # makinede geçerli olsa da on-prem sunucuda farklı (S:/) veya tanımsız
      # olabilir; bu durumda cmd.exe spawn'lı CLI "The system cannot find the
      # path specified" hatasıyla biter. normalize_mcp_path UNC formunu korur.
      yeni_norm <- tryCatch(
        normalize_mcp_path(yeni_yol, must_exist = FALSE),
        error = function(e) normalizePath(yeni_yol, winslash = "/", mustWork = FALSE)
      )
      updateTextInput(
        session,
        "workdir",
        value = yeni_norm
      )
    }
  })

  observeEvent(input$dir_go_up, {
    yol <- input$workdir

    if (!is.null(yol) && nzchar(yol)) {
      ust <- dirname(yol)
      if (dir.exists(ust) && ust != yol) {
        # UNC formunu korumak için normalize_mcp_path kullan; aksi halde
        # normalizePath bir üst dizine çıkış sırasında UNC'yi drive harfine
        # çevirebilir.
        ust_norm <- tryCatch(
          normalize_mcp_path(ust, must_exist = FALSE),
          error = function(e) normalizePath(ust, winslash = "/", mustWork = FALSE)
        )
        updateTextInput(
          session,
          "workdir",
          value = ust_norm
        )
      }
    }
  })

  observeEvent(input$refresh_dir, {
    observe_dir_contents()
  })

  observeEvent(input$workdir, {
    # Kayıtlı oturum hidrasyonu workdir'i geri yüklerken bu observer'ın
    # yeni yüklenen oturumun resume bağlarını sıfırlamaması gerekir; bayrak
    # yalnızca o tek güncelleme için reset'i bastırır.
    if (isTRUE(rv$suppress_workdir_reset_once)) {
      rv$suppress_workdir_reset_once <- FALSE
      observe_dir_contents()
      return()
    }

    rv$cli_session_id <- NULL
    rv$conversation_context <- list()
    # Yeni proje dizini seçildiğinde önceki aynalanmış runtime klasörünün
    # yeniden kullanılmaması gerekir; aksi halde yeni kaynağa ait Claude CLI
    # oturumu farklı runtime klasöründe oluşur ve takip çağrıları başarısız olur.
    rv$active_runtime_workdir <- NULL
    rv$active_runtime_source <- NULL

    # Kalıcı oturum bağını kopar; eski oturum Oturumlar sayfasında kalır.
    if (exists("cc_persist_detach_session", mode = "function", inherits = TRUE)) {
      cc_persist_detach_session(rv)
    }

    observe_dir_contents()
  }, ignoreInit = TRUE)

  observeEvent(input$clear_output, {
    rv$output_history <- list()
    rv$has_messages <- FALSE
    rv$conversation_context <- list()
    rv$cli_session_id <- NULL
    # Sohbet sıfırlanırken aynalanmış runtime klasörünü de unut; bir sonraki
    # çalıştırmada Claude CLI taze bir oturum kuracaktır.
    rv$active_runtime_workdir <- NULL
    rv$active_runtime_source <- NULL

    # ÇIKTIYI TEMİZLE KALICI GEÇMİŞİ SİLMEZ: yalnızca aktif oturum bağı
    # koparılır; kayıtlar Bilge Yolaç > Oturumlar sayfasında erişilebilir
    # kalır ve bir sonraki çalıştırma yeni bir kalıcı oturum açar.
    if (exists("cc_persist_detach_session", mode = "function", inherits = TRUE)) {
      cc_persist_detach_session(rv)
    }

    session$sendCustomMessage(
      type = "cc-clear-output",
      message = list(
        target = ns("output_area"),
        welcomeId = ns("welcome_screen"),
        statusId = ns("status_text"),
        durationId = ns("duration_text")
      )
    )
  })

  observeEvent(input$thinking_tick, {
    karakter <- get_active_character()
    yeni_mesaj <- get_thinking_message(karakter$id)

    session$sendCustomMessage(
      type = "cc-update-thinking-text",
      message = list(
        textId = ns("thinking_text"),
        message = yeni_mesaj
      )
    )
  })

  list(
    resolve_current_user_id = resolve_current_user_id,
    ensure_ready_user_id = ensure_ready_user_id,
    get_active_character = get_active_character,
    kullanici_adi = kullanici_adi,
    observe_dir_contents = observe_dir_contents
  )
}