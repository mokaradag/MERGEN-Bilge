# ==============================================================================
# R/module_quick_actions.R
# Hızlı eylem şablonlarını (quick action templates) işleyen modül.
# Ana Söyleşi sayfasındaki hızlı başlangıç butonlarının mantığını içerir.
# ==============================================================================

#' Hızlı Eylem Şablonları Server Mantığı
#'
#' @description
#' Bu fonksiyon, karşılama ekranındaki hızlı eylem butonlarının tıklama
#' olaylarını işler. Her eylem için uygun araç modunu etkinleştirir ve
#' gerekirse model değişikliği yapar.
#'
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler listesi (messages, show_welcome, vb.)
#' @param settings_data Ayarlar modülünden dönen reaktif değerler
#' @param session_files Oturum dosyalarını tutan reaktif değer fonksiyonu
#' @param send_message_fn Mesaj gönderme fonksiyonu
#' @param quick_action_skip_mcp MCP atlaması için reaktif değer fonksiyonu
#'
#' @return NULL (observer'lar kaydedilir)
quickActionsInit <- function(input, session, values, settings_data,
                              session_files, send_message_fn,
                              quick_action_skip_mcp) {
  
  # ---------------------------------------------------------------------------
  # Yardımcı: Welcome ekranını gizle ve sohbet alanını göster
  # ---------------------------------------------------------------------------
  hide_welcome_show_chat <- function() {
    values$show_welcome <- FALSE
    shinyjs::runjs("
      $('#welcome_fullscreen_container').addClass('hidden').empty();
      $('#chat_content_container').show();
    ")
    removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
  }
  
  # ---------------------------------------------------------------------------
  # Yardımcı: Model değiştir (ortak mantık)
  # ---------------------------------------------------------------------------
  change_model_if_provided <- function(template_model) {
    if (!is.null(template_model) && nzchar(template_model)) {
      cat("[QUICK_TEMPLATE] Model değiştiriliyor:", template_model, "\n")
      isolate({ settings_data$model_selection <- template_model })
      updateSelectInput(session, "settings_module-model_selection", selected = template_model)
      session$sendCustomMessage("saveSettings", list(model_selection = template_model))
      showToast(session, paste("Model değiştirildi:", template_model), "info")
      return(TRUE)
    }
    return(FALSE)
  }
  
  # ---------------------------------------------------------------------------
  # Yardımcı: Tüm araç modlarını kapat
  # ---------------------------------------------------------------------------
  disable_all_tools <- function() {
    isolate({
      settings_data$enable_rdata_tools <- FALSE
      settings_data$enable_mcp_tools <- FALSE
      settings_data$enable_summarization_tools <- FALSE
      settings_data$enable_coding_tools <- FALSE
      settings_data$enable_process_tools <- FALSE
      settings_data$enable_app_expert_tools <- FALSE
      settings_data$enable_image_tools <- FALSE
    })
  }
  
  # ---------------------------------------------------------------------------
  # Yardımcı: Checkbox'ları güncelle
  # ---------------------------------------------------------------------------
  update_tool_checkboxes <- function(active_tool = NULL) {
    all_tools <- c(
      "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
      "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
      "enable_image_tools"
    )
    
    for (tool in all_tools) {
      value <- identical(tool, active_tool)
      updateCheckboxInput(session, paste0("settings_module-", tool), value = value)
    }
  }
  
  # ---------------------------------------------------------------------------
  # Yardımcı: Ayarları kaydet (client-side localStorage)
  # ---------------------------------------------------------------------------
  save_tool_settings <- function(active_tool = NULL) {
    settings_list <- list(
      enable_rdata_tools = identical(active_tool, "enable_rdata_tools"),
      enable_mcp_tools = identical(active_tool, "enable_mcp_tools"),
      enable_summarization_tools = identical(active_tool, "enable_summarization_tools"),
      enable_coding_tools = identical(active_tool, "enable_coding_tools"),
      enable_process_tools = identical(active_tool, "enable_process_tools"),
      enable_app_expert_tools = identical(active_tool, "enable_app_expert_tools"),
      enable_image_tools = identical(active_tool, "enable_image_tools")
    )
    session$sendCustomMessage("saveSettings", settings_list)
  }
  
  # ---------------------------------------------------------------------------
  # Yardımcı: Tam eylem işleyicisi (model + araç + mesaj)
  # ---------------------------------------------------------------------------
  handle_tool_action <- function(action_id, tool_name, toast_message,
                                  template_model, template_text) {
    cat("[QUICK_TEMPLATE]", action_id, "isteği tespit edildi\n")
    
    # 1. Görsel modu için özel model işleme
    if (tool_name == "enable_image_tools") {
      # Görsel modu için dall-e-3 modeli zorunlu
      image_model <- Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3")
      isolate({ settings_data$model_selection <- image_model })
      session$sendCustomMessage("saveSettings", list(model_selection = image_model))
      session$sendCustomMessage("toggleImageMode", list(active = TRUE))
    } else {
      # Normal model değiştirme
      change_model_if_provided(template_model)
      session$sendCustomMessage("toggleImageMode", list(active = FALSE))
    }
    
    # 2. Araçları kapat, sadece istenen aracı aç
    disable_all_tools()
    isolate({ settings_data[[tool_name]] <- TRUE })
    
    # 3. UI checkbox'larını güncelle
    update_tool_checkboxes(tool_name)
    
    # 4. Ayarları kaydet
    save_tool_settings(tool_name)
    
    # 5. Bildirim göster
    showToast(session, toast_message, "success")
    
    # 6. Mesaj varsa gönder
    if (nzchar(template_text)) {
      shinyjs::delay(300, { send_message_fn(template_text) })
    }
  }
  
  # ===========================================================================
  # ANA OBSERVER: input$quick_template
  # ===========================================================================
  observeEvent(input$quick_template, {
    # Welcome ekranını kapat
    hide_welcome_show_chat()
    
    # Gelen veriyi işle
    if (is.list(input$quick_template)) {
      template_text <- input$quick_template$text %||% ""
      template_model <- input$quick_template$model %||% NULL
      template_action_id <- input$quick_template$action_id %||% ""
    } else {
      template_text <- as.character(input$quick_template)
      template_model <- NULL
      template_action_id <- ""
    }
    
    cat("[QUICK_TEMPLATE] Gelen veri: text='", template_text, 
        "', model='", template_model, 
        "', action_id='", template_action_id, "'\n", sep = "")
    
    # -------------------------------------------------------------------------
    # EYLEM: Kodlama Desteği
    # -------------------------------------------------------------------------
    if (identical(template_action_id, "coding-support")) {
      handle_tool_action(
        action_id = "coding-support",
        tool_name = "enable_coding_tools",
        toast_message = "Kod Uzmanı modu aktif edildi. Kodlama konusunda size yardımcı olmaya hazırım!",
        template_model = template_model,
        template_text = template_text
      )
      return()
    }
    
    # -------------------------------------------------------------------------
    # EYLEM: Süreç Yönetimi
    # -------------------------------------------------------------------------
    if (identical(template_action_id, "project-process")) {
      handle_tool_action(
        action_id = "project-process",
        tool_name = "enable_process_tools",
        toast_message = "Süreç Yönetimi modu aktif edildi. Kurumsal süreç ve dokümanlar hakkında size yardımcı olmaya hazırım!",
        template_model = template_model,
        template_text = template_text
      )
      return()
    }
    
    # -------------------------------------------------------------------------
    # EYLEM: Uygulama Uzmanı
    # -------------------------------------------------------------------------
    if (identical(template_action_id, "app-expert")) {
      handle_tool_action(
        action_id = "app-expert",
        tool_name = "enable_app_expert_tools",
        toast_message = "Uygulama Uzmanı modu aktif edildi. Uygulama mimarisi konusunda size yardımcı olmaya hazırım!",
        template_model = template_model,
        template_text = template_text
      )
      return()
    }
    
    # -------------------------------------------------------------------------
    # EYLEM: Proje ve Kaynak Analizi (SQL)
    # -------------------------------------------------------------------------
    if (identical(template_action_id, "resource-analysis")) {
      handle_tool_action(
        action_id = "resource-analysis",
        tool_name = "enable_rdata_tools",
        toast_message = "Proje ve Kaynak Analizi modu aktif edildi. Veri analizi konusunda size yardımcı olmaya hazırım!",
        template_model = template_model,
        template_text = template_text
      )
      return()
    }
    
    # -------------------------------------------------------------------------
    # EYLEM: Excel Analizi (MCP)
    # -------------------------------------------------------------------------
    if (identical(template_action_id, "excel-analysis")) {
      handle_tool_action(
        action_id = "excel-analysis",
        tool_name = "enable_mcp_tools",
        toast_message = "Excel Analizi modu aktif edildi. Excel dosyalarınızı analiz etmeye hazırım!",
        template_model = template_model,
        template_text = template_text
      )
      return()
    }
    
    # -------------------------------------------------------------------------
    # EYLEM: Görsel Oluşturma
    # -------------------------------------------------------------------------
    if (identical(template_action_id, "image-creation")) {
      handle_tool_action(
        action_id = "image-creation",
        tool_name = "enable_image_tools",
        toast_message = "Görsel Uzmanı modu aktif edildi. Görsel oluşturma konusunda size yardımcı olmaya hazırım!",
        template_model = template_model,
        template_text = template_text
      )
      return()
    }
    
    # -------------------------------------------------------------------------
    # EYLEM: Dosya Özetleme
    # -------------------------------------------------------------------------
    if (identical(template_text, "__SUMMARIZATION_REQUEST__")) {
      cat("[QUICK_TEMPLATE] Özetleme isteği tespit edildi\n")
      
      change_model_if_provided(template_model)
      
      disable_all_tools()
      isolate({ settings_data$enable_summarization_tools <- TRUE })
      update_tool_checkboxes("enable_summarization_tools")
      save_tool_settings("enable_summarization_tools")
      
      cat("[QUICK_TEMPLATE] Özetleme modu aktif edildi\n")
      
      current_files <- isolate(session_files())
      
      if (length(current_files) > 0) {
        excel_extensions <- c("xls", "xlsx")
        excel_files <- c()
        
        for (fname in names(current_files)) {
          ext <- tolower(tools::file_ext(fname))
          if (ext %in% excel_extensions) {
            excel_files <- c(excel_files, fname)
          }
        }
        
        if (length(excel_files) > 0) {
          fm_data <- session$userData$file_manager_data
          if (!is.null(fm_data) && !is.null(fm_data$set_attachment_checked)) {
            for (fname in excel_files) {
              fm_data$set_attachment_checked(fname, FALSE)
            }
          }
          
          updated_files <- isolate(session_files())
          for (fname in excel_files) {
            if (fname %in% names(updated_files)) {
              updated_files[[fname]] <- NULL
            }
          }
          session_files(updated_files)
          
          showToast(session, 
            paste0("Dosya Özetleme modu Excel dosyalarını desteklemez. Kaldırılan dosyalar: ", 
                   paste(excel_files, collapse = ", ")), 
            "warning")
          cat("[QUICK_TEMPLATE] Excel dosyaları bağlamdan kaldırıldı:", paste(excel_files, collapse = ", "), "\n")
        }
        
        remaining_files <- setdiff(names(current_files), excel_files)
        if (length(remaining_files) > 0) {
          cat("[QUICK_TEMPLATE] Kalan dosyalar (", length(remaining_files), 
              " adet), özetleme başlatılıyor...\n", sep = "")
          shinyjs::delay(300, { send_message_fn("") })
        } else {
          showToast(session, 
            "Tüm seçili dosyalar Excel formatındaydı ve kaldırıldı. Lütfen desteklenen formatta dosya seçin (DOC, DOCX, PDF, TXT).", 
            "info")
        }
      } else {
        cat("[QUICK_TEMPLATE] Dosya yok, bilgilendirme gösteriliyor\n")
        showToast(session, 
          "Lütfen önce Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.", 
          "info")
      }
      return()
    }
    
    # -------------------------------------------------------------------------
    # VARSAYILAN: Normal şablon mesajı
    # -------------------------------------------------------------------------
    if (nzchar(template_text)) {
      if (!is.null(template_model) && nzchar(template_model)) {
        cat("[QUICK_TEMPLATE] Normal template için model değiştiriliyor:", template_model, "\n")
        
        isolate({ settings_data$model_selection <- template_model })
        updateSelectInput(session, "settings_module-model_selection", selected = template_model)
        session$sendCustomMessage("saveSettings", list(model_selection = template_model))
        showToast(session, paste("Model değiştirildi:", template_model), "info")
        
        # Model değişikliğinden sonra mesajı gönder
        shinyjs::delay(200, { send_message_fn(template_text) })
      } else {
        # Model değişikliği yoksa direkt mesajı gönder
        send_message_fn(template_text)
      }
    }
  }, ignoreInit = TRUE)
  
  # ===========================================================================
  # EK OBSERVER: Hızlı model değişimi (quick_action_model_change)
  # ===========================================================================
  observeEvent(input$quick_action_model_change, {
    req(input$quick_action_model_change)
    new_model_id <- input$quick_action_model_change
    
    # Hızlı eylem → bir sonraki istekte MCP kapalı
    quick_action_skip_mcp(TRUE)
    
    # Ayarlar modülündeki reaktif değeri güncelle
    isolate({ settings_data$model_selection <- new_model_id })
    updateSelectInput(session, "settings_module-model_selection", selected = new_model_id)
    
    # Modelin görünen adını bul
    all_models <- api_config$local_models
    display_name <- names(all_models)[match(new_model_id, all_models)]
    if (is.na(display_name) || is.null(display_name) || display_name == "") {
      display_name <- new_model_id
    }
    
    showToast(session, paste("Model değiştirildi:", display_name), "info")
    log_info(paste("[MAIN_CHAT] Hızlı model değişimi:", new_model_id))
  }, ignoreInit = TRUE)
  
  # ===========================================================================
  # EK OBSERVER: Alternatif özetleme butonu (quick_action_summarization)
  # ===========================================================================
  observeEvent(input$quick_action_summarization, {
    req(input$quick_action_summarization)
    cat("[QUICK_ACTION_SUMMARIZATION] Tetiklendi (alternatif yol)\n")
    
    # Özetleme modunu aktif et
    disable_all_tools()
    isolate({ settings_data$enable_summarization_tools <- TRUE })
    update_tool_checkboxes("enable_summarization_tools")
    save_tool_settings("enable_summarization_tools")
    
    showToast(session, 
      "Dosya Özetleme modu aktif edildi. Şimdi Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.", 
      "success")
    
    # Dosyalar varsa özetlemeyi başlat
    current_files <- isolate(session_files())
    if (length(current_files) > 0) {
      shinyjs::delay(500, { send_message_fn("") })
    } else {
      showToast(session, 
        "Dosya Özetleme modu aktif edildi. Lütfen Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.", 
        "info")
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}