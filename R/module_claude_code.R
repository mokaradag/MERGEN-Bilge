# ==============================================================================
# Dosya Yolu: R/module_claude_code.R
# Açıklama: Claude Code entegrasyon modülünün ana dosyası. UI tanımı ve sunucu
#           mantığının giriş noktasını içerir. Klasör tarayıcı gözlemcileri
#           module_claude_code_klasor.R dosyasında, canlı akış yardımcıları
#           module_claude_code_akis.R dosyasında tanımlıdır.
# ==============================================================================

# ==============================================================================
# CLAUDE CODE UI
# ==============================================================================

claudeCodeUI <- function(id) {
  ns <- NS(id)

  # settings.json'dan model listesini oku ve katman etiketleriyle eşleştir
  ayarlar <- read_claude_settings_json()
  model_secenekleri <- ayarlar$models
  varsayilan_model <- ayarlar$default_model

  # Model katmanlarını oluştur
  katmanlar <- build_model_tier_choices(model_secenekleri)
  # Kısa etiketler (ikon + isim), açıklama tooltip ile gösterilir
  model_degerleri <- setNames(
    sapply(katmanlar, function(k) k$deger),
    sapply(katmanlar, function(k) k$etiket)
  )
  # Açıklama ve ikon verilerini JSON olarak JavaScript'e iletmek için hazırla
  model_meta <- lapply(katmanlar, function(k) {
    list(deger = k$deger, etiket = k$etiket, ikon = k$ikon, aciklama = k$aciklama)
  })

  tagList(
    div(
      class = "claude-code-container",
      # Karakter teması için veri özniteliği (JavaScript tarafından güncellenir)
      `data-character` = "mergen",

      # --- Sayfa Başlığı ---
      div(
        class = "chat-header settings-header-fixed",
        div(
          class = "chat-header-left",
          h4("Bilge Yolaç", class = "page-title"),
          tags$span(class = "cc-badge", "AJAN")
        ),
        div(
          class = "chat-header-right",
          # Bağlantı durum göstergesi
          uiOutput(ns("connection_status_badge"))
        )
      ),

      # --- Ana İçerik (sabit düzen) ---
      div(
        class = "cc-main-content",

        # --- Sol Panel: Ayarlar ve Senaryolar ---
        div(
          class = "cc-sidebar-panel",

          # Proje Dizini Kartı
          div(
            class = "cc-settings-card",
            h5(class = "cc-card-title", icon("folder-open"), "Proje Dizini"),

            # Proje dizini giriş alanı + klasör tarayıcı düğmeleri
            div(
              class = "cc-workdir-row",
              textInput(
                ns("workdir"),
                label = NULL,
                value = claude_code_config$default_workdir,
                placeholder = "Proje klasör yolunu girin..."
              ),
              # Sunucu taraflı klasör tarayıcı düğmesi
              actionButton(
                ns("open_folder_browser"),
                label = NULL,
                icon = icon("folder-open"),
                class = "cc-browse-btn",
                title = "Sunucu klasörü seç"
              ),
              # Yerel bilgisayardan klasör yükle (gizli fileInput + görünür düğme)
              div(style = "display:none;",
                fileInput(ns("yerel_klasor"), label = NULL, multiple = TRUE)
              ),
              actionButton(
                ns("yerel_klasor_btn"),
                label = NULL,
                icon = icon("laptop"),
                class = "cc-browse-btn",
                title = "Yerel bilgisayardan klasör yükle",
                onclick = sprintf(
                  "document.getElementById('%s').click();",
                  ns("yerel_klasor")
                )
              ),
              # webkitdirectory özniteliğini ekle + göreceli yolları yakala
              tags$script(HTML(sprintf("
$(function(){
  var fi = document.getElementById('%s');
  if(fi){
    fi.setAttribute('webkitdirectory','');
    fi.setAttribute('directory','');
    fi.addEventListener('change', function(e){
      var yollar = [];
      for(var i = 0; i < e.target.files.length; i++){
        yollar.push(e.target.files[i].webkitRelativePath || e.target.files[i].name);
      }
      Shiny.setInputValue('%s', JSON.stringify(yollar), {priority:'event'});
    });
  }
});", ns("yerel_klasor"), ns("yerel_klasor_yollar"))))
            ),

            # Model Seçimi (ikon + tooltip ile)
            div(
              class = "cc-model-select-wrapper",
              tags$label(class = "cc-select-label", "Model"),
              div(
                class = "cc-model-tier-group",
                lapply(model_meta, function(m) {
                  secili <- if (nzchar(varsayilan_model)) {
                    identical(m$deger, varsayilan_model)
                  } else {
                    identical(m$etiket, "Dengeli")
                  }
                  tags$button(
                    type = "button",
                    class = paste0("cc-model-tier-btn", if (secili) " active" else ""),
                    `data-value` = m$deger,
                    `data-ikon` = m$ikon,
                    title = m$aciklama,
                    onclick = sprintf(
                      "document.querySelectorAll('.cc-model-tier-btn').forEach(function(b){b.classList.remove('active')});this.classList.add('active');Shiny.setInputValue('%s',this.getAttribute('data-value'),{priority:'event'});",
                      ns("model")
                    ),
                    tags$i(class = paste0("fas ", m$ikon)),
                    tags$span(m$etiket)
                  )
                })
              ),
              # Başlangıç değerini Shiny'ye bildir
              tags$script(sprintf(
                "$(function(){Shiny.setInputValue('%s','%s');});",
                ns("model"),
                if (nzchar(varsayilan_model)) gsub("'", "\\\\'", varsayilan_model) else ""
              ))
            )
          ),

          # Ön Tanımlı Senaryolar
          div(
            class = "cc-settings-card cc-scenarios-card",
            h5(class = "cc-card-title", icon("bolt"), "Hazır Senaryolar"),
            div(
              class = "cc-scenario-grid",
              lapply(claude_code_scenarios, function(senaryo) {
                actionButton(
                  ns(paste0("scenario_", senaryo$id)),
                  label = tagList(
                    icon(senaryo$ikon),
                    span(senaryo$baslik)
                  ),
                  class = "cc-scenario-btn",
                  title = senaryo$aciklama
                )
              })
            )
          ),

          # Dizin İçerik Paneli
          div(
            class = "cc-settings-card cc-dir-card",
            h5(class = "cc-card-title", icon("folder-tree"), "Dizin İçeriği"),
            # Üst gezinti çubuğu (geri düğmesi + mevcut dizin)
            div(
              class = "cc-dir-nav",
              actionButton(
                ns("dir_go_up"),
                label = NULL,
                icon = icon("arrow-up"),
                class = "btn-sm cc-dir-up-btn",
                title = "Üst dizine git"
              ),
              span(id = ns("dir_current_path"), class = "cc-dir-current-path"),
              actionButton(
                ns("refresh_dir"),
                label = NULL,
                icon = icon("sync"),
                class = "btn-sm cc-refresh-btn",
                title = "Yenile"
              )
            ),
            uiOutput(ns("dir_contents_ui"))
          )
        ),

        # --- Sağ Panel: Terminal / Sohbet Alanı ---
        div(
          class = "cc-terminal-panel",

          # Çıktı / Sonuç Alanı (kaydırılabilir, esnek yükseklik)
          div(
            class = "cc-output-wrapper",
            # Retro karşılama ekranı (çıktı alanı boşken görünür)
            div(
              id = ns("welcome_screen"),
              class = "cc-welcome-screen cc-welcome-active"
              # İçerik JavaScript tarafından oluşturulur
            ),
            div(
              id = ns("output_area"),
              class = "cc-output-area"
              # İçerik JavaScript tarafından yönetilir
            )
          ),

          # 8-bit düşünme animasyonu (küçültülmüş, köşede)
          div(
            id = ns("thinking_overlay"),
            class = "cc-thinking-mini cc-hidden",
            tags$canvas(
              id = ns("pixel_canvas"),
              class = "cc-pixel-canvas-mini",
              width = "48",
              height = "48"
            ),
            div(
              id = ns("thinking_text"),
              class = "cc-thinking-text-mini"
            )
          ),

          # Komut Giriş Alanı (sabit konumda, altta)
          div(
            class = "cc-input-area",
            div(
              class = "cc-input-wrapper",
              tags$textarea(
                id = ns("prompt_input"),
                class = "cc-prompt-input",
                placeholder = "Claude Code'a bir komut yazın...",
                rows = 3
              ),
              div(
                class = "cc-input-actions",
                # Karakter Göstergesi
                uiOutput(ns("active_character_indicator")),
                # Temizle Düğmesi
                actionButton(
                  ns("clear_output"),
                  label = NULL,
                  icon = icon("eraser"),
                  class = "cc-action-btn cc-clear-btn",
                  title = "Çıktıyı Temizle"
                ),
                # Durdur Düğmesi (çalışırken görünür)
                actionButton(
                  ns("stop_command"),
                  label = tagList(icon("stop"), "Durdur"),
                  class = "cc-stop-btn cc-hidden",
                  title = "İşlemi durdur"
                ),
                # Çalıştır Düğmesi
                actionButton(
                  ns("run_command"),
                  label = tagList(icon("play"), "Çalıştır"),
                  class = "cc-run-btn"
                )
              )
            ),
            # Durum Çubuğu
            div(
              class = "cc-status-bar",
              span(id = ns("status_text"), class = "cc-status-text"),
              span(id = ns("duration_text"), class = "cc-duration-text")
            )
          )
        )
      )
    )
  )
}

# ==============================================================================
# CLAUDE CODE SERVER
# ==============================================================================

claudeCodeServer <- function(id, current_user_id, settings_data = NULL,
                              user_first_name = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Etkin kullanıcı kimliğini her kullanım anında oturumdan çöz.
    resolve_current_user_id <- function() {
      session_uid <- session$userData$user_id %||% NULL
      uid <- suppressWarnings(as.integer(session_uid %||% current_user_id %||% 0L))
      if (is.na(uid)) uid <- 0L
      uid
    }

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
      current_model = NULL,           # Model değişim takibi
      active_process = NULL,          # Aktif processx süreci (durdurma için)
      poll_state = NULL,              # Yoklama durumu (ortam değişkeni, durdurma için)
      stream_env = NULL               # Akış durumu (yoklama gözlemcisi için)
    )

    # --- Uygulama başladığında CLI yolunu otomatik tespit et ---
    observe({
      yol <- resolve_claude_cli_path(claude_code_config$cli_path)
      rv$cli_path_resolved <- yol
    }, priority = 100)

    # --- SSO modunda varsayılan çalışma dizinini kullanıcının profiline ayarla ---
    observe({
      req(isTRUE(SSO_ENABLED))
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

    # --- Otomatik bağlantı testi (sayfa görüntülendiğinde, başlangıçta değil) ---
    # Uygulama başlangıcını yavaşlatmamak için sadece CLI durumunu kontrol et,
    # tam bağlantı testini kullanıcı sayfayı görüntülediğinde çalıştır.
    observe({
      req(is.null(rv$connection_ok))
      cli_yolu <- rv$cli_path_resolved
      if (is.null(cli_yolu)) {
        rv$connection_ok <- FALSE
        return()
      }
      # Sadece CLI erişilebilirliğini kontrol et (hızlı, --version ile)
      durum <- tryCatch({
        check_claude_code_status(cli_yolu)
      }, error = function(e) {
        list(installed = FALSE)
      })
      if (durum$installed) {
        rv$connection_ok <- TRUE
        log_info(paste(CLAUDE_CODE_LOG_PREFIX, "CLI erişilebilir:", durum$version))
      } else {
        rv$connection_ok <- FALSE
        temiz_hata <- gsub("[{}]", "", durum$error %||% "")
        log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "CLI erişilemez:", temiz_hata))
      }
    }, priority = 50)

    # --- Yapılandırma sayfasından bağlantı testi sonucunu dinle ---
    observe({
      req(!is.null(settings_data))
      # Yapılandırma sayfasında test başarılı olduysa güncelle
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
    get_active_character <- reactive({
      karakter_id <- "mergen"
      if (!is.null(settings_data) && !is.null(settings_data$selected_character)) {
        secili <- settings_data$selected_character
        if (!is.null(secili) && nzchar(secili)) {
          karakter_id <- secili
        }
      }

      # Karakter verilerinden renk bilgisini al
      karakterler <- get_characters_data()
      secili <- NULL
      for (s in karakterler$styles) {
        if (s$id == karakter_id) {
          secili <- s
          break
        }
      }
      if (is.null(secili)) secili <- karakterler$styles[[1]]
      secili
    })

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
    kullanici_adi <- reactive({
      # Önce parametre olarak gelen adı dene
      if (!is.null(user_first_name)) {
        ad <- if (is.reactive(user_first_name)) user_first_name() else user_first_name
        if (!is.null(ad) && nzchar(ad)) return(ad)
      }
      # session$userData'dan dene
      ad <- session$userData$user_first_name
      if (!is.null(ad) && nzchar(ad)) return(ad)
      # user_config'den dene
      uc <- session$userData$user_config
      if (!is.null(uc) && !is.null(uc$first_name) && nzchar(uc$first_name)) return(uc$first_name)
      if (!is.null(uc) && !is.null(uc$name) && nzchar(uc$name)) return(uc$name)
      # Varsayılan
      "Siz"
    })

    # --- Bağlantı Durumu Rozeti ---
    output$connection_status_badge <- renderUI({
      durum <- rv$connection_ok
      if (is.null(durum)) {
        tags$span(class = "cc-status-badge cc-status-checking",
                  icon("spinner", class = "fa-spin"), "Kontrol ediliyor...")
      } else if (isTRUE(durum)) {
        tags$span(class = "cc-status-badge cc-status-ok",
                  icon("check-circle"), "Bağlı")
      } else {
        tags$span(class = "cc-status-badge cc-status-error",
                  icon("times-circle"), "Bağlantı Yok")
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

    # --- Sunucu taraflı klasör tarayıcı (module_claude_code_klasor.R) ---
    rv_browser <- reactiveValues(
      current_path = NULL,
      history = list()
    )
    init_klasor_gezgini_observers(input, output, session, ns, rv_browser)

    # --- Yerel klasör yükleme (kullanıcının kendi bilgisayarından) ---
    observeEvent(input$yerel_klasor, {
      dosyalar <- input$yerel_klasor
      req(nrow(dosyalar) > 0)

      # Göreceli yolları JavaScript'ten al
      yollar_json <- input$yerel_klasor_yollar
      yollar <- if (!is.null(yollar_json) && nzchar(yollar_json)) {
        tryCatch(jsonlite::fromJSON(yollar_json), error = function(e) NULL)
      }

      # Kullanıcıya özel çalışma alanı oluştur
      user_id <- resolve_current_user_id()
      calisma_alani <- get_user_workspace(user_id)

      # Dosyaları dizin yapısını koruyarak kopyala
      dosya_sayisi <- 0L
      for (i in seq_len(nrow(dosyalar))) {
        # webkitRelativePath varsa kullan, yoksa düz dosya adı
        goreceli <- if (!is.null(yollar) && length(yollar) >= i) {
          yollar[i]
        } else {
          dosyalar$name[i]
        }

        hedef <- file.path(calisma_alani, goreceli)
        hedef_dizin <- dirname(hedef)
        if (!dir.exists(hedef_dizin)) dir.create(hedef_dizin, recursive = TRUE, showWarnings = FALSE)
        file.copy(dosyalar$datapath[i], hedef, overwrite = TRUE)
        dosya_sayisi <- dosya_sayisi + 1L
      }

      # Çalışma dizinini güncelle
      updateTextInput(session, "workdir", value = normalizePath(calisma_alani, winslash = "/"))
      showNotification(
        paste0(dosya_sayisi, " dosya yerel bilgisayardan yüklendi."),
        type = "message", duration = 5
      )
      log_info(paste(CLAUDE_CODE_LOG_PREFIX, dosya_sayisi, "dosya yerel klasörden yüklendi:", calisma_alani))
    })

    # --- Model değiştiğinde oturumu sıfırla ---
    # Farklı bir modele geçildiğinde önceki oturumun bağlamı geçersiz olur.
    # Yeni model ile temiz bir oturum başlatılmalıdır.
    observeEvent(input$model, {
      if (!is.null(rv$current_model) && !identical(rv$current_model, input$model)) {
        rv$cli_session_id <- NULL
        rv$conversation_context <- list()
        log_info(paste(CLAUDE_CODE_LOG_PREFIX,
                       "Model değişti, oturum sıfırlandı. Yeni model:", input$model))
      }
      rv$current_model <- input$model
    }, ignoreInit = TRUE)

    # --- Senaryo Düğmeleri ---
    lapply(claude_code_scenarios, function(senaryo) {
      observeEvent(input[[paste0("scenario_", senaryo$id)]], {
        if (nzchar(senaryo$sablon)) {
          # textarea güncelleme (JavaScript ile)
          shinyjs::runjs(sprintf(
            "var el = document.getElementById('%s'); if(el) { el.value = %s; el.focus(); }",
            ns("prompt_input"),
            jsonlite::toJSON(senaryo$sablon, auto_unbox = TRUE)
          ))
        }
      })
    })

    # --- Dizin İçeriğini Göster (tıklanabilir klasörlerle) ---
    # dizin parametresi: later::later gibi reaktif olmayan bağlamlardan
    # çağrıldığında input$workdir yerine kullanılır.
    observe_dir_contents <- function(dizin = NULL) {
      yol <- dizin %||% isolate(input$workdir)
      if (is.null(yol) || !nzchar(yol)) {
        output$dir_contents_ui <- renderUI({
          tags$p(class = "cc-dir-empty", "Proje dizini belirtilmedi.")
        })
        return()
      }

      icerik <- list_directory_contents(yol)

      # Mevcut dizin yolunu güncelle
      # Not: shinyjs::runjs yerine sendCustomMessage kullanılır,
      # çünkü bu fonksiyon later::later bağlamından da çağrılabilir.
      session$sendCustomMessage(
        type = "cc-update-element-text",
        message = list(
          elementId = ns("dir_current_path"),
          text = yol
        )
      )

      output$dir_contents_ui <- renderUI({
        if (!icerik$success) {
          tags$p(class = "cc-dir-error", icerik$error)
        } else if (length(icerik$items) == 0) {
          tags$p(class = "cc-dir-empty", "Dizin boş.")
        } else {
          tags$div(
            class = "cc-dir-list",
            if (icerik$toplam > length(icerik$items)) {
              tags$small(class = "cc-dir-count",
                         paste0(icerik$toplam, " ögeden ilk ",
                                length(icerik$items), " tanesi"))
            },
            lapply(icerik$items, function(oge) {
              ikon <- if (oge$tip == "klasor") "folder" else "file"
              boyut_text <- if (!is.na(oge$boyut)) {
                if (oge$boyut < 1024) paste0(oge$boyut, " B")
                else if (oge$boyut < 1048576) paste0(round(oge$boyut / 1024, 1), " KB")
                else paste0(round(oge$boyut / 1048576, 1), " MB")
              } else ""

              # Klasörlere tıklanabilirlik ekle
              ek_sinif <- if (oge$tip == "klasor") " cc-dir-clickable" else ""
              ek_olay <- if (oge$tip == "klasor") {
                sprintf(
                  "Shiny.setInputValue('%s', '%s', {priority: 'event'});",
                  ns("dir_navigate"),
                  gsub("'", "\\\\'", oge$yol)
                )
              } else NULL

              tags$div(
                class = paste0("cc-dir-item cc-dir-", oge$tip, ek_sinif),
                onclick = ek_olay,
                icon(ikon),
                tags$span(class = "cc-dir-name", oge$ad),
                tags$span(class = "cc-dir-size", boyut_text)
              )
            })
          )
        }
      })
    }

    # Dizin gezgini: klasöre tıklama
    observeEvent(input$dir_navigate, {
      req(input$dir_navigate)
      yeni_yol <- input$dir_navigate
      if (dir.exists(yeni_yol)) {
        updateTextInput(session, "workdir",
                        value = normalizePath(yeni_yol, winslash = "/", mustWork = FALSE))
      }
    })

    # Üst dizine git düğmesi
    observeEvent(input$dir_go_up, {
      yol <- input$workdir
      if (!is.null(yol) && nzchar(yol)) {
        ust <- dirname(yol)
        if (dir.exists(ust) && ust != yol) {
          updateTextInput(session, "workdir",
                          value = normalizePath(ust, winslash = "/", mustWork = FALSE))
        }
      }
    })

    observeEvent(input$refresh_dir, {
      observe_dir_contents()
    })

    observeEvent(input$workdir, {
      # Çalışma dizini değiştiğinde oturumu sıfırla
      rv$cli_session_id <- NULL
      rv$conversation_context <- list()
      observe_dir_contents()
    }, ignoreInit = TRUE)

    # --- Çıktıyı Temizle ---
    observeEvent(input$clear_output, {
      rv$output_history <- list()
      rv$has_messages <- FALSE
      rv$conversation_context <- list()
      rv$cli_session_id <- NULL
      session$sendCustomMessage(
        type = "cc-clear-output",
        message = list(
          target = ns("output_area"),
          welcomeId = ns("welcome_screen")
        )
      )
    })

    # --- Düşünme mesajı güncelleme ---
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

      # Çift tıklama koruması
      if (isTRUE(rv$is_running)) return()
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
      if (is.null(calisma_dizini) || !nzchar(calisma_dizini)) {
        effective_user_id <- resolve_current_user_id()

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
        list(role = "user", content = prompt)
      ))

      # Oturum kimliğini yakala
      oturum_id <- rv$cli_session_id

      # Kullanıcı komutunu çıktıya ekle
      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "user",
          content = htmltools::htmlEscape(prompt),
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
      stream_env$prompt <- prompt
      stream_env$calisma_dizini <- calisma_dizini
      stream_env$tum_satirlar <- character(0)
      stream_env$durduruldu <- FALSE
      stream_env$oturum_id <- NULL  # stream-json olaylarından gelecek
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
      cli_args <- c(cli_args, prompt)

      # Süreci başlat
      tryCatch({
        log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Canlı akış başlatılıyor"))

        # Windows'ta .cmd dosyalarını cmd.exe üzerinden çalıştır
        komut <- build_processx_command(cli_yolu, cli_args)

        proc <- processx::process$new(
          command = komut$command,
          args = komut$args,
          env = komut$env,
          wd = calisma_dizini,
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
        finalize_streaming("Durduruldu", "stop-circle", "#FFB74D")
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
        finalize_streaming("Zaman Aşımı", "clock", "#FFB74D")
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

          # Akış mesajını sonlandır
          # stream-json modunda metin zaten anlık gösterildiği için
          # finalContent yalnızca yedek olarak gönderilir
          son_icerik <- format_claude_code_output(ayristirma$text_output)

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
            success = TRUE, output = ayristirma$text_output,
            error = "", duration = sure,
            tool_uses = ayristirma$tool_uses,
            session_id = oturum_id
          )

          finalize_streaming("Tamamlandı", "check-circle", "#81C784", sure)
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

          finalize_streaming("Hata", "exclamation-triangle", "#E57373", sure)
        }

        # Geçmişe ekle
        rv$output_history <- c(rv$output_history, list(list(
          prompt = env$prompt,
          result = rv$last_result,
          timestamp = Sys.time(),
          character = env$karakter_id
        )))

        # Dizin içeriğini güncelle
        observe_dir_contents(dizin = env$calisma_dizini)
      }
    })

    # --- Durdur düğmesi ---
    observeEvent(input$stop_command, {
      if (isTRUE(rv$is_running)) {
        # Yoklama döngüsüne durdurma sinyali gönder (ortam değişkeni ile)
        if (!is.null(rv$poll_state)) {
          rv$poll_state$durduruldu <- TRUE
        }

        # Aktif süreci sonlandır
        if (!is.null(rv$active_process)) {
          tryCatch({
            rv$active_process$kill()
            log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Süreç kullanıcı tarafından durduruldu"))
          }, error = function(e) NULL)
          rv$active_process <- NULL
        }
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