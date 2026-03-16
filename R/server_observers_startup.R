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
  
  # Karşılama ekranını başlat (widget bağımlılıkları ui.R'de statik olarak tanımlı)
  observeEvent(TRUE, {
    if (isTRUE(values$show_welcome)) {
      render_welcome_screen(values$saved_chats)
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
          var t = e.target;
          if (t && t.classList && t.classList.contains('source-link')) {
            e.preventDefault();
            e.stopPropagation();
            var fn = t.getAttribute('data-filename') || (t.textContent || '').trim();
            Shiny.setInputValue('source_file_clicked', { filename: fn, nonce: Math.random() }, { priority: 'event' });
          }
        }, true);
      }
    ");
  }, once = TRUE)
  
  observeEvent(input$reloadWelcomeScreenTrigger, {
    if (isTRUE(values$show_welcome)) {
      # NOT: DeepSpaceIntro burada yok edilmez (kendi yaşam döngüsü var)
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

      # Kayıtlı sohbetler yüklendiğinde karşılama ekranını güncelle.
      # Derin uzay giriş animasyonu aktifken tam yeniden render yapmak
      # tüm başlangıç dizisini gereksiz yere yeniden tetikler.
      if (length(chats) > 0) {
        if (isTRUE(session$userData$deep_space_dismissed)) {
          # Giriş animasyonu kapandıktan sonra - güvenle güncelle
          render_welcome_screen(chats, replace_existing = TRUE)
        } else {
          # Giriş animasyonu hâlâ aktif - yeniden render ertelendi.
          # Karşılama ekranı zaten ilk render'da oluşturuldu;
          # saved_chats değiştiğinde bir sonraki render'da güncellenecek.
          cat("[STARTUP] Giriş ekranı aktif, karşılama yeniden render ertelendi\n")
        }
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