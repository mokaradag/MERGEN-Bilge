# R/server_outputs_chat.R
# Dosya Yolu: R/server_outputs_chat.R
# Açıklama: Ana Söyleşi sayfasındaki header UI çıktılarını (renderUI) içerir.
# Model göstergesi, MCP modu göstergesi ve model seçici dropdown bu dosyadadır.

#' Sohbet Çıktılarını Başlat
#' @description Ana Söyleşi sayfasındaki UI çıktılarını tanımlar
#' @param output Shiny output nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
chatOutputsInit <- function(output, settings_data) {
  
  output$current_model_display <- renderUI({
    # Langflow araçları (Süreç Yönetimi / Uygulama Uzmanı) yerel model kullanmaz;
    # model, Langflow akışının içine gömülüdür. Bu araçlar aktifken yerel model
    # rozeti yanıltıcı olacağından hiç gösterilmez. Tespit runtime=="langflow"
    # üzerinden yapılır (araç adına sabit kodlanmaz).
    if (exists("mergen_langflow_setting_flags", mode = "function", inherits = TRUE)) {
      langflow_flags <- mergen_langflow_setting_flags(api_config)
      langflow_active <- any(vapply(
        langflow_flags,
        function(f) isTRUE(settings_data[[f]]),
        logical(1)
      ))
      if (isTRUE(langflow_active)) {
        return(NULL)
      }
    }

    # Görsel modu aktifse dall-e-3 göster
    if (isTRUE(settings_data$enable_image_tools)) {
      display_name <- "dall-e-3"
    } else {
      selected_model_id <- settings_data$model_selection %||% api_config$local_models[1]
      display_name <- names(api_config$local_models)[api_config$local_models == selected_model_id]
      if (length(display_name) == 0) display_name <- selected_model_id
    }

    # Excel/Kod araçlarında Derin Düşünme aktifse runtime'da kullanılan modeli
    # bilgi balonu olarak göster (dropdown'da seçilen değer değişmez; sadece
    # araç-aktif kullanıcı için bilgi amaçlı).
    runtime_hint <- NULL
    if (isTRUE(settings_data$enable_mcp_tools) && isTRUE(settings_data$excel_deep_thinking)) {
      runtime_hint <- resolve_deep_thinking_model("mcp_excel", settings_data$excel_deep_level)
    } else if (isTRUE(settings_data$enable_coding_tools) && isTRUE(settings_data$coding_deep_thinking)) {
      runtime_hint <- resolve_deep_thinking_model("coding", settings_data$coding_deep_level)
    }
    title_text <- paste0("Model: ", display_name)
    if (!is.null(runtime_hint) && nzchar(runtime_hint)) {
      title_text <- paste0(title_text, " (Derin Düşünme: ", runtime_hint, ")")
    }

    div(
      class = "header-stat-item",
      title = title_text,
      style = "background: rgba(255, 255, 255, 0.05); border-color: rgba(255, 255, 255, 0.1);",
      span(
        style = "font-weight: 500; color: #b0b0b0;",
        paste0("Model: ", display_name)
      )
    )
  })
  
  output$mcp_mode_indicator <- renderUI({
    coding_active <- isTRUE(settings_data$enable_coding_tools)
    process_active <- isTRUE(settings_data$enable_process_tools)
    app_expert_active <- isTRUE(settings_data$enable_app_expert_tools)
    image_active <- isTRUE(settings_data$enable_image_tools)
    excel_active <- isTRUE(settings_data$enable_mcp_tools)
    rdata_active <- isTRUE(settings_data$enable_rdata_tools)
    summarization_active <- isTRUE(settings_data$enable_summarization_tools)
    
    if (coding_active) {
      div(
        class = "mcp-indicator coding-active",
        tags$i(class = "fas fa-code"),
        span("Kod Uzmanı")
      )
    } else if (process_active) {
      div(
        class = "mcp-indicator process-active",
        tags$i(class = "fas fa-briefcase"),
        span("Süreç Yönetimi")
      )
    } else if (app_expert_active) {
      div(
        class = "mcp-indicator app-expert-active",
        tags$i(class = "fas fa-window-maximize"),
        span("Uygulama Uzmanı")
      )
    } else if (image_active) {
      div(
        class = "mcp-indicator image-active",
        tags$i(class = "fas fa-image"),
        span("Görsel Uzmanı")
      )
    } else if (summarization_active) {
      div(
        class = "mcp-indicator summarization-active",
        tags$i(class = "fas fa-file-alt"),
        span("Dosya Özetleme")
      )
    } else if (excel_active) {
      div(
        class = "mcp-indicator excel-active",
        tags$i(class = "fas fa-file-excel"),
        span("Excel Analizi")
      )
    } else if (rdata_active) {
      div(
        class = "mcp-indicator rdata-active",
        tags$i(class = "fas fa-chart-bar"),
        span("Proje ve Kaynak Analizi")
      )
    } else {
      NULL
    }
  })
  
  output$chat_model_selector_ui <- renderUI({
    current_val <- settings_data$model_selection
    models <- api_config$local_models
    descriptions <- api_config$local_model_descriptions %||% list()
    
    if (is.null(names(models))) names(models) <- models
    
    menu_items <- lapply(seq_along(models), function(i) {
      m_name <- names(models)[i]
      m_id   <- models[[i]]
      is_active <- identical(as.character(m_id), as.character(current_val))
      desc <- descriptions[[m_id]] %||% m_name
      
      tags$li(
        tags$a(
          class = paste0("dropdown-item model-option", if(is_active) " active" else ""),
          href = "#",
          title = desc, 
          onclick = sprintf("Shiny.setInputValue('quick_action_model_change', '%s', {priority: 'event'}); return false;", m_id),
          div(
            class = "model-item-content",
            span(class = "model-name", m_name),
            if(is_active) icon("check", class = "selected-icon") else NULL
          )
        )
      )
    })

    div(
      title = "Model Değiştir", 
      shinyWidgets::dropdown(
        inputId = "chat_model_dropdown_container",
        style = "minimal",
        icon = icon("microchip"), 
        status = "default",  
        right = TRUE,        
        up = TRUE,           
        width = "250px",     
        
        div(
          class = "dropdown-menu-header",
          style = "padding: 8px 12px; margin-bottom: 4px;",
          icon("layer-group"),
          tags$span(
            style = "font-weight: 600; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px;",
            "Model Kataloğu"
          )
        ),
        tags$ul(
          class = "dropdown-menu-custom-list",
          style = "list-style: none; padding: 0; margin: 0;",
          menu_items
        )
      )
    )
  })
  
  invisible(NULL)
}