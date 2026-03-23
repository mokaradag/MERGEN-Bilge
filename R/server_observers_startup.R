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
  
  # --- Kayıtlı söyleşileri asenkron yükle ---
  # SSO modunda current_user_id başlangıçta 0L olur; kullanıcı kimliği
  # doğrulandığında reactiveVal güncellenir. Bu observer değişikliği
  # yakalar ve gerçek kullanıcı için söyleşileri yükler.
  load_saved_chats_for_user <- function(uid) {
    session$userData$initial_saved_chats_promise <- promises::then(
      promises::future_promise({
        if (identical(uid, 0L) || identical(uid, 0)) return(list())
        load_chats_from_db(uid, include_messages = FALSE)
      }),
      onFulfilled = function(chats) {
        chats <- chats %||% list()
        values$saved_chats <- chats

        # Kayıtlı sohbetler yüklendiğinde karşılama ekranını güncelle
        if (length(chats) > 0) {
          if (isTRUE(session$userData$deep_space_dismissed)) {
            render_welcome_screen(chats, replace_existing = TRUE)
          } else {
            cat("[STARTUP] Giriş ekranı aktif, karşılama yeniden render ertelendi\n")
          }
        }
        NULL
      },
      onRejected = function(err) {
        warning(sprintf("[SERVER] Kayıtlı söyleşi yüklemesi başarısız: %s", conditionMessage(err)))
        NULL
      }
    )
  }

  # İlk yükleme: SSO kapalıysa hemen çalışır, SSO açıksa uid=0 olduğundan atlanır
  uid_for_load <- isolate(current_user_id())
  load_saved_chats_for_user(uid_for_load)

  # SSO modunda: kullanıcı kimliği doğrulandığında söyleşileri yeniden yükle
  observeEvent(current_user_id(), {
    uid <- current_user_id()
    if (!identical(uid, 0L) && !identical(uid, 0)) {
      load_saved_chats_for_user(uid)
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}