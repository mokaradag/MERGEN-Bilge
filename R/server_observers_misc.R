# R/server_observers_misc.R
# Dosya Yolu: R/server_observers_misc.R
# Açıklama: Çeşitli UI observer'ları ve çıktı tanımları.
# Geri bildirim buton senkronizasyonu, dosya yöneticisi mesajları, 
# yönetici menüsü ve diğer küçük observer'lar burada toplanmıştır.

# PR #672 Codex inceleme düzeltmeleri, ilgili bütün Bilge Yolaç yardımcıları
# yüklendikten sonra tek ve açık bir geç-yükleme noktasından uygulanır.
load_claude_code_codex_review_fixes <- function() {
  if (isTRUE(get0(
    ".claude_code_codex_review_fixes_loaded",
    envir = globalenv(),
    inherits = FALSE,
    ifnotfound = FALSE
  ))) {
    return(invisible(TRUE))
  }

  required_helpers <- c(
    "mirror_directory_to_local_workspace",
    "cc_scan_directory_bounded",
    "cc_dispatch_run_preparation",
    "cc_dispatch_run_output_processing"
  )
  helpers_ready <- all(vapply(
    required_helpers,
    exists,
    logical(1),
    envir = globalenv(),
    mode = "function",
    inherits = TRUE
  ))
  if (!isTRUE(helpers_ready)) {
    return(invisible(FALSE))
  }

  repo_candidates <- unique(c(
    Sys.getenv("MERGEN_REPO_ROOT", ""),
    getwd(),
    file.path(getwd(), ".."),
    file.path(getwd(), "..", "..")
  ))
  repo_candidates <- repo_candidates[nzchar(repo_candidates)]
  fix_files <- c(
    "helpers_claude_code_codex_runtime_fixes.R",
    "helpers_claude_code_codex_output_fixes.R"
  )
  repo_root <- ""
  for (candidate in repo_candidates) {
    if (all(file.exists(file.path(candidate, "R", fix_files)))) {
      repo_root <- candidate
      break
    }
  }
  if (!nzchar(repo_root)) {
    stop("PR #672 Codex hardening dosyaları bulunamadı.", call. = FALSE)
  }

  for (fix_file in fix_files) {
    source(
      file.path(repo_root, "R", fix_file),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
  assign(
    ".claude_code_codex_review_fixes_loaded",
    TRUE,
    envir = globalenv()
  )
  invisible(TRUE)
}

# Uygulama manifestinde bu dosya Bilge Yolaç yardımcılarından sonra yüklenir;
# izole testlerde yardımcılar yoksa loader güvenle FALSE döner.
load_claude_code_codex_review_fixes()

#' Çeşitli UI Gözlemcilerini Başlat
#' @description Çeşitli UI observer ve output tanımlarını kurar
#' @param input Shiny input nesnesi
#' @param output Shiny output nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param file_manager_data Dosya yöneticisi modül verisi
#' @param filePreview Dosya önizleme modülü
#' @param add_message Mesaj ekleme fonksiyonu
#' @param api_key API anahtar modülü
#' @param user_config Kullanıcı yapılandırması
#' @param pool Veritabanı bağlantı havuzu
miscObserversInit <- function(input, output, session, values, 
                               file_manager_data, filePreview, add_message,
                               api_key, user_config, pool = NULL) {
  
  load_claude_code_codex_review_fixes()
  
  admin_modulleri_baslatildi <- reactiveVal(FALSE)
  
  mevcut_yetki <- reactive({
    cfg <- user_config()
    seviye <- cfg$auth_level %||% "USER"
    toupper(trimws(as.character(seviye)))
  })
  
  # Geri bildirim verisi değiştiğinde buton renklerini JS ile güncelle
  observe({
    liked_db_ids <- as.character(values$liked_messages %||% character(0))
    disliked_db_ids <- as.character(values$disliked_messages %||% character(0))
    
    current_msgs <- values$messages
    dom_liked <- character(0)
    dom_disliked <- character(0)
    
    if (length(current_msgs) > 0) {
      for (m in current_msgs) {
        if (!is.null(m$db_id) && !is.na(m$db_id)) {
          mid_str <- as.character(m$db_id)
          if (mid_str %in% liked_db_ids) {
            dom_liked <- c(dom_liked, m$id)
          } else if (mid_str %in% disliked_db_ids) {
            dom_disliked <- c(dom_disliked, m$id)
          }
        }
      }
    }
    
    shinyjs::runjs(sprintf("
      $('.message-action-btn.like-btn').removeClass('active liked');
      $('.message-action-btn.dislike-btn').removeClass('active disliked');
      
      var liked = %s;
      if (liked && liked.length) {
        liked.forEach(function(id) {
           $('#like_' + id).addClass('active liked');
        });
      }
      
      var disliked = %s;
      if (disliked && disliked.length) {
        disliked.forEach(function(id) {
           $('#dislike_' + id).addClass('active disliked');
        });
      }
    ", 
    jsonlite::toJSON(dom_liked, auto_unbox = FALSE),
    jsonlite::toJSON(dom_disliked, auto_unbox = FALSE)
    ))
  })
  
  # Dosya yöneticisi mesaj tetikleyicisi
  observeEvent(file_manager_data$message_trigger(), {
    req(file_manager_data$message_trigger() > 0)
    
    msg <- file_manager_data$get_message()
    
    if (!is.null(msg)) {
      if (identical(msg$type, "view_file")) {
        file_id <- msg$content
        file_info <- file_manager_data$file_contents()[[file_id]]
        if (!is.null(file_info)) {
          openAnyPreview(file_info, session, filePreview)
        }
      } else {
        add_message(msg$content, type = "system", html = msg$html)
      }
    }
  }, ignoreInit = TRUE)
  
  # API anahtarı modal açma
  observeEvent(input$`settings_yapilandirma_module-open_api_key_modal`, {
    api_key$open("API Anahtarı Güncelleme")
  }, ignoreInit = TRUE)
  
  # Yönetici menüsü görünürlüğü
  output$show_admin_menu <- reactive({
    identical(mevcut_yetki(), "ADMIN")
  })
  outputOptions(output, "show_admin_menu", suspendWhenHidden = FALSE)
  
  # Yönetici menü öğesi (alt menülerle gruplandırılmış)
  output$admin_menu_item <- renderMenu({
    if (identical(mevcut_yetki(), "ADMIN")) {
      menuItem("Yönetici Paneli", icon = icon("shield-alt"), startExpanded = FALSE,
        menuSubItem("Genel Analiz", tabName = "admin_analytics", icon = icon("chart-line")),
        menuSubItem("Geri Bildirim Analizi", tabName = "admin_geri_bildirim", icon = icon("comment-dots")),
        menuSubItem("Hata Analizi", tabName = "admin_hata_analizi", icon = icon("bug")),
        menuSubItem("Yanıt Geri Bildirimi", tabName = "admin_yanit_analizi", icon = icon("thumbs-up")),
        menuSubItem("Dokümantasyon", tabName = "admin_dokumantasyon", icon = icon("book")),
        menuSubItem("Sistem Durumu", tabName = "health", icon = icon("heartbeat"))
      )
    }
  })
  # Karşılama ekranı açıkken kenar çubuğu gizli sayılabildiğinden menü ancak
  # ilk tıklamada beliriyordu; render gizliyken de çalışmalı.
  outputOptions(output, "admin_menu_item", suspendWhenHidden = FALSE)

  # Yönetici analitik sunucularını yetki geldikten sonra tek sefer başlat
  observeEvent(mevcut_yetki(), {
    req(identical(mevcut_yetki(), "ADMIN"))
    
    if (isTRUE(admin_modulleri_baslatildi())) {
      return(invisible(NULL))
    }
    
    admin_modulleri_baslatildi(TRUE)
    adminAnalyticsServer("admin_analytics_module", pool = pool)
    adminGeriBildirimServer("admin_geri_bildirim_module")
    adminHataAnaliziServer("admin_hata_analizi_module")
    adminYanitAnaliziServer("admin_yanit_analizi_module")
    adminDokumantasyonServer("admin_dokumantasyon_module")
  }, ignoreInit = FALSE)
  
  # Mesaj sayısı çıktısı
  output$message_count <- renderText({ length(values$messages) })
  
  # Welcome ekranı görünürlük çıktısı
  output$show_welcome_screen <- reactive({ values$show_welcome })
  outputOptions(output, "show_welcome_screen", suspendWhenHidden = FALSE)
  
  invisible(NULL)
}
