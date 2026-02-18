# R/server_observers_startup.R
# Dosya Yolu: R/server_observers_startup.R
# Açıklama: Oturum başlangıcı ve uygulama ilk yüklenme observer'ları.
# Welcome ekranı başlatma, widget bağımlılıkları ön yükleme, 
# kayıtlı sohbetlerin asenkron yüklenmesi ve JS köprüleri bu dosyadadır.

#' Başlangıç Gözlemcilerini Başlat
#' @description Uygulama açılışında bir kez çalışan observer'ları kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param render_welcome_screen Karşılama ekranı render fonksiyonu
#' @param current_user_id Mevcut kullanıcı ID'si
startupObserversInit <- function(input, session, values, render_welcome_screen, current_user_id) {
  
  observeEvent(TRUE, {
    if (isTRUE(values$show_welcome)) {
      render_welcome_screen(values$saved_chats)
    }
    
    if (requireNamespace("highcharter", quietly = TRUE)) {
      insertUI(
        selector = "body", where = "beforeEnd",
        ui = tags$div(
          style = "width:1px;height:1px;overflow:hidden;position:absolute;left:-9999px;top:-9999px;",
          highcharter::highchartOutput("deps_hc", width = "1px", height = "1px")
        ),
        immediate = TRUE
      )
    }
    if (requireNamespace("plotly", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)) {
      insertUI(
        selector = "body", where = "beforeEnd",
        ui = tags$div(
          style = "width:1px;height:1px;overflow:hidden;position:absolute;left:-9999px;top:-9999px;",
          tagList(
            plotly::plotlyOutput("deps_pl", width = "1px", height = "1px"),
            plotly::plotlyOutput("plotly_html", width = "1px", height = "1px")
          )
        ),
        immediate = TRUE
      )
    }
  }, once = TRUE)
  
  session$onFlushed(function() {
    shinyjs::runjs("
      Shiny.addCustomMessageHandler('reloadWelcomeScreen', function(data) {
        Shiny.setInputValue('reloadWelcomeScreenTrigger', data.timestamp, {priority: 'event'});
      });
    ")
  }, once = TRUE)
  
  session$onFlushed(function(){
    shinyjs::runjs("
	  if (!window.__srcLinkBound) {
        window.__srcLinkBound = true;
        document.addEventListener('click', function(e){
          // closest() ile alt elemanlardaki (ikon, metin) tıklamaları da yakala
          var t = e.target.closest ? e.target.closest('.source-link') : null;
          if (!t) {
            // Satır içi alıntı numaraları için de kontrol et
            var citBtn = e.target.closest ? e.target.closest('.citation-index-btn') : null;
            if (citBtn) { e.preventDefault(); e.stopPropagation(); }
            return;
          }
          e.preventDefault();
          e.stopPropagation();
          var fn = t.getAttribute('data-filename') || (t.textContent || '').trim();
          Shiny.setInputValue('source_file_clicked', { filename: fn, nonce: Math.random() }, { priority: 'event' });
        }, true);
      }
    ");
  }, once = TRUE)
  
  observeEvent(input$reloadWelcomeScreenTrigger, {
    if (isTRUE(values$show_welcome)) {
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
      ")
      
      render_welcome_screen(values$saved_chats, replace_existing = TRUE)
    }
  }, ignoreInit = TRUE)
  
  session$userData$initial_saved_chats_promise <- promises::then(
    promises::future_promise({
      load_chats_from_db(current_user_id, include_messages = FALSE)
    }),
    onFulfilled = function(chats) {
      chats <- chats %||% list()
      values$saved_chats <- chats
      
      if (length(chats) > 0) {
        render_welcome_screen(chats, replace_existing = TRUE)
      }
      NULL
    },
    onRejected = function(err) {
      warning(sprintf("[SERVER] Initial saved chat load failed: %s", conditionMessage(err)))
      NULL
    }
  )
  
  invisible(NULL)
}