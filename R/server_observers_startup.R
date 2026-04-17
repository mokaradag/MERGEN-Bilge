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
		render_welcome_screen(values$saved_chats, replace_existing = FALSE)
	  }
	}, ignoreInit = TRUE)
  
  # SSO akışında başlangıçta current_user_id=0 gelebilir.
  # Bu nedenle kullanıcı ID'sini her yükleme anında oturumdan çöz.
  resolve_current_user_id <- function() {
    session_uid <- session$userData$user_id %||% NULL
    suppressWarnings(as.integer(session_uid %||% current_user_id %||% 0L))
  }
  
  startup_state <- new.env(parent = emptyenv())
  startup_state$initial_saved_chats_loaded <- FALSE

  load_initial_saved_chats <- function() {
    effective_user_id <- resolve_current_user_id()

    if (is.na(effective_user_id) || effective_user_id <= 0) {
      cat("[STARTUP] Geçerli kullanıcı kimliği yok, kayıtlı sohbet yüklemesi atlandı\n")
      return(invisible(NULL))
    }

    if (isTRUE(startup_state$initial_saved_chats_loaded)) {
      cat("[STARTUP] İlk kayıtlı sohbet yüklemesi zaten yapıldı, tekrar atlanıyor\n")
      return(invisible(NULL))
    }
    startup_state$initial_saved_chats_loaded <- TRUE

	refresh_welcome_if_needed <- function(chats) {
	  if (!isTRUE(session$userData$deep_space_dismissed)) {
		cat("[STARTUP] Giriş ekranı aktif, karşılama yeniden render ertelendi\n")
		return(invisible(NULL))
	  }

	  if (!isTRUE(values$show_welcome)) {
		return(invisible(NULL))
	  }

	  render_welcome_screen(chats, replace_existing = FALSE)
	  invisible(NULL)
	}

    # İlk ekranın hızlı gelmesi için önce hafif özet listeyi yükle.
	preview_chats <- tryCatch(
	  load_chats_preview_from_db(effective_user_id, limit = 6L),
	  error = function(e) {
		warning(sprintf("[SERVER] Preview chat load failed: %s", conditionMessage(e)))
		list()
	  }
	)

    if (length(preview_chats) > 0) {
      values$saved_chats <- preview_chats
      refresh_welcome_if_needed(preview_chats)
    }

    session$userData$initial_saved_chats_promise <- promises::then(
      promises::future_promise({
        load_chats_from_db(effective_user_id, include_messages = FALSE)
      }),
      onFulfilled = function(chats) {
        chats <- chats %||% list()
        values$saved_chats <- chats

        # Tam liste geldiğinde karşılama ekranını güncelle.
        refresh_welcome_if_needed(chats)
        NULL
      },
      onRejected = function(err) {
        warning(sprintf("[SERVER] Initial saved chat load failed: %s", conditionMessage(err)))
        NULL
      }
    )
  }

  if (isTRUE(session$userData$sso_active)) {
    # session$userData$auth_initialized reaktif olmadığı için
    # kısa aralıkla kontrol ederek kimlik hazır olunca tek sefer yükle.
    auth_wait_observer <- NULL
	auth_wait_observer <- observe({
	  if (!isTRUE(session$userData$auth_initialized)) {
		invalidateLater(50, session)
		return(invisible(NULL))
	  }
	  load_initial_saved_chats()
	  if (!is.null(auth_wait_observer)) {
		auth_wait_observer$destroy()
	  }
	  invisible(NULL)
	})
  } else {
    load_initial_saved_chats()
  }
  
  invisible(NULL)
}