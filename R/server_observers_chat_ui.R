# R/server_observers_chat_ui.R
# Dosya Yolu: R/server_observers_chat_ui.R
# Açıklama: Ana Söyleşi sayfası UI observer'ları.
# Yeni sohbet butonu, takip soruları ve benzeri UI etkileşimleri bu dosyadadır.

#' Sohbet UI Gözlemcilerini Başlat
#' @description Ana Söyleşi sayfasındaki UI observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param start_new_chat Yeni sohbet başlatma fonksiyonu
#' @param send_message Mesaj gönderme fonksiyonu
#' @param render_welcome_screen Karşılama ekranı render fonksiyonu
#' @param settings_data Ayarlar modülünden dönen reaktif değerler
chatUIObserversInit <- function(input, session, values, start_new_chat, 
                                 send_message, render_welcome_screen,
                                 settings_data = NULL) {
  
  observeEvent(input$new_chat_btn, {
	shinyjs::runjs("
      if(window.WelcomeVideoPlayer && window.WelcomeVideoPlayer.destroy) {
        window.WelcomeVideoPlayer.destroy();
      }
      if(window.WelcomeNeuralNetwork && window.WelcomeNeuralNetwork.destroy) {
        window.WelcomeNeuralNetwork.destroy();
      }
      if(window.WelcomeGreeting && window.WelcomeGreeting.destroy) {
        window.WelcomeGreeting.destroy();
      }
      if(window.WelcomePersonalGreeting && window.WelcomePersonalGreeting.destroy) {
        window.WelcomePersonalGreeting.destroy();
      }
    ")
    
    if (!is.null(settings_data)) {
      analysis_tools <- c(
        "enable_rdata_tools", "enable_mcp_tools", "enable_summarization_tools",
        "enable_coding_tools", "enable_process_tools", "enable_app_expert_tools",
        "enable_image_tools"
      )
      
      tool_labels <- list(
        enable_rdata_tools = "Proje ve Kaynak Analizi",
        enable_mcp_tools = "MCP: Excel",
        enable_summarization_tools = "Dosya Özetleme",
        enable_coding_tools = "Kod Uzmanı",
        enable_process_tools = "Süreç Yönetimi",
        enable_app_expert_tools = "Uygulama Uzmanı",
        enable_image_tools = "Görsel Uzmanı"
      )
      
      deactivated_tools <- c()
      
      for (tool in analysis_tools) {
        if (isTRUE(isolate(settings_data[[tool]]))) {
          isolate({ settings_data[[tool]] <- FALSE })
          updateCheckboxInput(session, paste0("settings_yapilandirma_module-", tool), value = FALSE)
          deactivated_tools <- c(deactivated_tools, tool_labels[[tool]])
        }
      }
      
      if (length(deactivated_tools) > 0) {
        settings_list <- list(
          enable_rdata_tools = FALSE,
          enable_mcp_tools = FALSE,
          enable_summarization_tools = FALSE,
          enable_coding_tools = FALSE,
          enable_process_tools = FALSE,
          enable_app_expert_tools = FALSE,
          enable_image_tools = FALSE
        )
        session$sendCustomMessage("saveSettings", settings_list)
        
        showToast(session, 
          paste0("Yeni söyleşi başlatıldı. Devre dışı bırakılan araçlar: ", 
                 paste(deactivated_tools, collapse = ", ")), 
          "info")
        cat("[NEW_CHAT] Devre dışı bırakılan araçlar:", paste(deactivated_tools, collapse = ", "), "\n")
      }
    }
    
    start_new_chat()
    # Müzik bağlam geçişi kaldırıldı - yeni mimaride müzik kesintisiz çalar

    # Karşılama ekranına dönüldüğünde "aşağı kaydır" butonunu gizle
    shinyjs::runjs("$('#scroll_to_bottom_container').removeClass('show');")

    # Yeni söyleşide model seçim kilidini de serbest bırak (panelsiz Süreç/
    # Uygulama Uzmanı araçları için sunucu otoriter kilit temizliği).
    tryCatch(
      session$sendCustomMessage("setToolModelLock", list(active = FALSE)),
      error = function(e) invisible(NULL)
    )

    # Sunucu otoriter olarak araç arka plan ailesini temizle. İstemci
    # tarafında bind edilen #new_chat_btn click handler stale duruma
    # düşerse de bu mesaj sayesinde arka plan animasyonu güvenle silinir.
    tryCatch(
      session$sendCustomMessage("setToolBackgroundFamily", list(clear = TRUE)),
      error = function(e) invisible(NULL)
    )

    # Süreç Yönetimi (Langflow) sohbet içi akış seçici, yalnızca JS `hidden`
    # sınıfıyla gizlenir ve #chat_input_wrapper içinde #chat_content_container'ın
    # kardeşi olduğundan yeni söyleşi DOM temizliğinden etkilenmez. Aktif süreç
    # modundan sonra normal sohbete geçildiğinde açılır menü görünür kalmasın
    # diye seçiciyi burada da açıkça gizle.
    tryCatch(
      session$sendCustomMessage("toggleProcessMode", list(active = FALSE)),
      error = function(e) invisible(NULL)
    )

    shinyjs::delay(300, {
      render_welcome_screen(values$saved_chats, replace_existing = TRUE)
    })
  }, ignoreInit = TRUE)
  
  observeEvent(input$followup_question_clicked, {
    req(is.list(input$followup_question_clicked))
    req(nzchar(input$followup_question_clicked$text %||% ""))
    send_message(input$followup_question_clicked)
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}