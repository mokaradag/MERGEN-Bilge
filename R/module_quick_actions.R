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
#' @param quick_action_skip_mcp Hızlı işlem sonrası bir sonraki istekte MCP atlaması için kullanılan reaktif değer fonksiyonu
#' @param output Sohbet mesajı kutularını eklemek için kullanılan Shiny output nesnesi
#' @param current_user_id Geçerli kullanıcı kimliği; oturum içinden çözümlenemediğinde yedek olarak kullanılır
#'
#' @return NULL (observer'lar kaydedilir)
quickActionsInit <- function(input, session, values, settings_data,
                              session_files, quick_action_skip_mcp,
                              output = NULL, current_user_id = NULL,
                              send_message_fn = NULL) {
  
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
      updateSelectInput(session, "settings_yapilandirma_module-model_selection", selected = template_model)
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
      updateCheckboxInput(session, paste0("settings_yapilandirma_module-", tool), value = value)
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
  
	resolve_quick_action_user_id <- function() {
	  effective_user_id <- resolve_effective_user_id(
		session = session,
		current_user_id = current_user_id
	  )

	  if (is.na(effective_user_id) || effective_user_id < 0L) {
		effective_user_id <- 0L
	  }

	  effective_user_id
	}

  show_quick_action_intro <- function(action_id) {
    if (is.null(output)) {
      return(invisible(NULL))
    }

    intro_text <- build_quick_action_intro_message(
      action_id = action_id,
      user_name = resolve_quick_action_user_name(
        session = session,
        settings_data = settings_data
      )
    )

    if (!nzchar(intro_text)) {
      return(invisible(NULL))
    }

    chat_add_message(
      session = session,
      values = values,
      settings_data = settings_data,
      output = output,
      content = intro_text,
      type = "ai",
      current_user_id = resolve_quick_action_user_id(),
      persist_to_db = FALSE,
      add_to_saved_chats = FALSE,
      include_in_context = FALSE
    )

    invisible(NULL)
  }

  last_quick_action_signature <- reactiveVal("")
  last_quick_action_at <- reactiveVal(as.numeric(0))

  is_duplicate_quick_action_event <- function(action_id, model_id) {
    if (is.null(action_id) || !nzchar(action_id)) {
      return(FALSE)
    }

    now_ms <- as.numeric(Sys.time()) * 1000
    signature <- paste(action_id %||% "", model_id %||% "", sep = "|")

    previous_signature <- isolate(last_quick_action_signature())
    previous_at <- isolate(last_quick_action_at())

    if (identical(previous_signature, signature) &&
        is.finite(previous_at) &&
        (now_ms - previous_at) < 600) {
      return(TRUE)
    }

    last_quick_action_signature(signature)
    last_quick_action_at(now_ms)
    FALSE
  }
  
  # ---------------------------------------------------------------------------
  # Yardımcı: Tam eylem işleyicisi (model + araç + mesaj)
  # ---------------------------------------------------------------------------
  handle_tool_action <- function(action_id, tool_name, toast_message,
                                  template_model) {
    cat("[QUICK_TEMPLATE]", action_id, "isteği tespit edildi\n")

    tool_cfg <- get_tool_mode_config(action_id, by = "quick_action_id")
    resolved_model <- tool_cfg$model_id %||% template_model %||%
      settings_data$model_selection %||% as.character(api_config$local_models[1])

    if (!is.null(resolved_model) && nzchar(resolved_model)) {
      template_model <- resolved_model
    }
    
    # 1. Tüm sohbet içi araç panelleri ön bilgisi: kapatma çağrıları her dalda
    # tekrarlanmamak için yardımcı.
    close_all_tool_panels <- function() {
      session$sendCustomMessage("toggleImageMode", list(active = FALSE))
      session$sendCustomMessage("toggleSummaryMode", list(active = FALSE))
      session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
      session$sendCustomMessage("toggleExcelMode", list(active = FALSE))
      session$sendCustomMessage("toggleCodingMode", list(active = FALSE))
    }

    if (tool_name == "enable_image_tools") {
      # Görsel modu için dall-e-3 modeli zorunlu
      image_model <- Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3")
      isolate({ settings_data$model_selection <- image_model })
      session$sendCustomMessage("saveSettings", list(model_selection = image_model))
      close_all_tool_panels()
      session$sendCustomMessage("toggleImageMode", list(active = TRUE))
    } else if (tool_name == "enable_summarization_tools") {
      change_model_if_provided(template_model)
      close_all_tool_panels()
      session$sendCustomMessage("toggleSummaryMode", list(active = TRUE))
    } else if (tool_name == "enable_rdata_tools") {
      change_model_if_provided(template_model)
      close_all_tool_panels()
      session$sendCustomMessage("toggleAnalysisMode", list(active = TRUE))
      session$sendCustomMessage("syncAnalysisSettingsToChat", list(
        deep_thinking = isTRUE(isolate(settings_data$analysis_deep_thinking)),
        detail_level = isolate(settings_data$analysis_detail_level) %||% "standart"
      ))
    } else if (tool_name == "enable_mcp_tools") {
      # Excel Analizi: Derin Düşünme paneli görünür hale getirilir
      change_model_if_provided(template_model)
      close_all_tool_panels()
      session$sendCustomMessage("toggleExcelMode", list(active = TRUE))
      session$sendCustomMessage("syncExcelDeepThinkingToChat", list(
        deep_thinking = isTRUE(isolate(settings_data$excel_deep_thinking)),
        level = isolate(settings_data$excel_deep_level) %||% "low"
      ))
    } else if (tool_name == "enable_coding_tools") {
      # Kod Uzmanı: Derin Düşünme paneli görünür hale getirilir
      change_model_if_provided(template_model)
      close_all_tool_panels()
      session$sendCustomMessage("toggleCodingMode", list(active = TRUE))
      session$sendCustomMessage("syncCodingDeepThinkingToChat", list(
        deep_thinking = isTRUE(isolate(settings_data$coding_deep_thinking)),
        level = isolate(settings_data$coding_deep_level) %||% "low"
      ))
    } else {
      change_model_if_provided(template_model)
      close_all_tool_panels()
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

    # 6. LLM çağrısı yapmadan hazır yönlendirme mesajı göster
    show_quick_action_intro(action_id)

    # 7. Sunucu otoriter olarak sohbet arka plan ailesini ayarla.
    #    İstemci tarafındaki click listener erken görsel ipucu olarak
    #    kalır; ancak gerçek aktivasyon yetkisi bu mesaja aittir. Bu
    #    sayede DOM redraw veya stale tıklama durumlarında bile araç
    #    arka plan animasyonu doğru ailede başlar.
    family <- tool_cfg$family
    if (is.null(family) || !nzchar(as.character(family)[1])) {
      family <- ""
    }
    tryCatch(
      session$sendCustomMessage("setToolBackgroundFamily", list(
        action_id = action_id %||% "",
        family = as.character(family)[1]
      )),
      error = function(e) invisible(NULL)
    )
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

    if (is_duplicate_quick_action_event(template_action_id, template_model)) {
      cat("[QUICK_TEMPLATE] Yinelenen hızlı işlem olayı yoksayıldı: ",
          template_action_id, "\n", sep = "")
      return()
    }
    
    # -------------------------------------------------------------------------
    # EYLEM: Kodlama Desteği
    # -------------------------------------------------------------------------
    if (identical(template_action_id, "coding-support")) {
      handle_tool_action(
        action_id = "coding-support",
        tool_name = "enable_coding_tools",
        toast_message = "Kod Uzmanı modu aktif edildi. Kodlama konusunda size yardımcı olmaya hazırım!",
        template_model = template_model
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
        template_model = template_model
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
        template_model = template_model
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
        template_model = template_model
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
        template_model = template_model
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
        template_model = template_model
      )
      return()
    }
    
    # -------------------------------------------------------------------------
    # EYLEM: Dosya Özetleme
    # -------------------------------------------------------------------------
    if (identical(template_action_id, "summarization")) {
      cat("[QUICK_TEMPLATE] Özetleme isteği tespit edildi\n")

      change_model_if_provided(template_model)

      disable_all_tools()
      isolate({ settings_data$enable_summarization_tools <- TRUE })
      update_tool_checkboxes("enable_summarization_tools")
      save_tool_settings("enable_summarization_tools")

      # Özetleme kontrollerini göster, diğer araç panellerini gizle
      session$sendCustomMessage("toggleSummaryMode", list(active = TRUE))
      session$sendCustomMessage("toggleImageMode", list(active = FALSE))
      session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))
      session$sendCustomMessage("toggleExcelMode", list(active = FALSE))
      session$sendCustomMessage("toggleCodingMode", list(active = FALSE))

      # Sunucu otoriter arka plan aile sinyali (handle_tool_action ile aynı sözleşme)
      tryCatch(
        session$sendCustomMessage("setToolBackgroundFamily", list(
          action_id = "summarization",
          family = "summarization"
        )),
        error = function(e) invisible(NULL)
      )

      cat("[QUICK_TEMPLATE] Özetleme modu aktif edildi\n")

      show_quick_action_intro("summarization")
      
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
              " adet), hazır bilgilendirme gösteriliyor...\n", sep = "")
          showToast(
            session,
            "Özetleme modu hazır. Şimdi nasıl bir özet istediğinizi yazabilirsiniz.",
            "success"
          )
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
      if (!is.function(send_message_fn)) {
        showToast(session, "Mesaj gönderme fonksiyonu henüz hazır değil.", "warning")
        cat("[QUICK_TEMPLATE] UYARI: send_message_fn hazır değil, normal template gönderilmedi\n")
        return()
      }

      if (!is.null(template_model) && nzchar(template_model)) {
        cat("[QUICK_TEMPLATE] Normal template için model değiştiriliyor:", template_model, "\n")
        
        isolate({ settings_data$model_selection <- template_model })
        updateSelectInput(session, "settings_yapilandirma_module-model_selection", selected = template_model)
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
    
    # Hızlı eylem -> bir sonraki istekte MCP kapalı
    quick_action_skip_mcp(TRUE)
    
    # Ayarlar modülündeki reaktif değeri güncelle
    isolate({ settings_data$model_selection <- new_model_id })
    updateSelectInput(session, "settings_yapilandirma_module-model_selection", selected = new_model_id)
    
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

    # Özetleme kontrollerini göster, görsel kontrollerini gizle
    session$sendCustomMessage("toggleSummaryMode", list(active = TRUE))
    session$sendCustomMessage("toggleImageMode", list(active = FALSE))
    session$sendCustomMessage("toggleAnalysisMode", list(active = FALSE))

    showToast(session,
      "Dosya Özetleme modu aktif edildi. Şimdi Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.",
      "success")
    
    show_quick_action_intro("summarization")

    current_files <- isolate(session_files())
    if (!length(current_files)) {
      showToast(session,
        "Dosya Özetleme modu aktif edildi. Lütfen Dosya Yönetimi sayfasından dosya yükleyin ve 'Model Bağlamı' seçin.",
        "info")
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}