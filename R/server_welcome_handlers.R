# R/server_welcome_handlers.R
# Dosya Yolu: R/server_welcome_handlers.R
# Açıklama: Hoş geldin ekranı işlemleri için yardımcı fonksiyonlar.
# Bu dosya server.R'den ayrılarak modülerlik sağlanmıştır.
 
#' Hoş Geldin Ekranı İşleyicilerini Başlat
#' @description Hoş geldin ekranı ile ilgili fonksiyonları kurar
#' @param session Shiny session nesnesi
#' @param values Ana reaktif değerler
#' @param saved_chats_data Kayıtlı sohbetler modülü
#' @param session_files Oturum dosyaları reactiveVal
#' @param filePreview Dosya önizleme modülü
#' @param current_user_id Mevcut kullanıcı kimliği
#' @param file_manager_data Dosya yöneticisi modülü
#' @return Hoş geldin ekranı fonksiyonlarını içeren liste
welcomeHandlersInit <- function(session, values, saved_chats_data, session_files,
                                 filePreview, current_user_id, file_manager_data,
                                 user_first_name = NULL) {
								 
  resolve_user_first_name <- function() {
    deger <- if (is.function(user_first_name)) {
      tryCatch(user_first_name(), error = function(e) NULL)
    } else {
      user_first_name
    }

    deger <- as.character(
      deger %||%
        session$userData$user_first_name %||%
        session$userData$user_config$first_name %||%
        ""
    )[1]

    deger %||% ""
  }
  
  resolve_current_user_id <- function() {
    resolve_effective_user_id(
      session = session,
      current_user_id = current_user_id
    )
  }
 
  # Hoş geldin ekranını render et
  # Bu fonksiyon welcome ekranını oluşturur ve animasyonları başlatır
	render_welcome_screen <- function(saved_chats, replace_existing = FALSE) {
	  if (!isTRUE(shiny::isolate(values$show_welcome))) {
		return(invisible(NULL))
	  }

	  # Welcome ekranı zaten bağlıysa ve tam yenileme istenmiyorsa
	  # sadece Son Konuşmalar bölümünü güncelle.
	  if (isTRUE(session$userData$welcome_screen_attached) && !isTRUE(replace_existing)) {
		shinyjs::runjs("
		  $('#welcome_fullscreen_container').removeClass('hidden').show();
		  $('#chat_content_container').hide();
		")

		shiny::removeUI(
		  selector = "#welcome_fullscreen_container .modern-welcome-footer-section",
		  multiple = TRUE,
		  immediate = TRUE
		)

		shiny::insertUI(
		  selector = "#welcome_fullscreen_container .modern-welcome-left-panel",
		  where = "beforeEnd",
		  ui = createModernRecentChatsSection(saved_chats),
		  immediate = TRUE
		)

		# Hafif yeniden gösterme yolunda da modern welcome animasyonlarını yeniden bağla.
		# Karakter seçimi Kişiselleştirme sayfasında gizli welcome canvas'ını etkilemiş
		# olabilir; Ana Söyleşi'ye dönünce video, neural canvas ve greeting tekrar
		# görünür DOM ölçüleriyle başlatılmalıdır.
		shinyjs::delay(80, {
		  session$sendCustomMessage("initModernWelcome", list())

		  shinyjs::delay(80, {
		    session$sendCustomMessage("initPersonalGreeting", list(
		      first_name = resolve_user_first_name()
		    ))
		  })
		})

		return(invisible(NULL))
	  }

	  # Mevcut welcome içeriğini ve chat içeriğini tamamen temizle
	  shiny::removeUI(selector = "#welcome_fullscreen_container > *", multiple = TRUE, immediate = TRUE)
	  shiny::removeUI(selector = "#chat_content_container > *", multiple = TRUE, immediate = TRUE)

	  # Animasyonları önce temizle
	  # NOT: DeepSpaceIntro'yu burada yok etme! Giriş ekranı kendi yaşam
	  # döngüsünü module_startup_screen.R ve mode_selection.js ile yönetir.
	  # Burada yok etmek, aktif giriş animasyonunu sonlandırır.
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

	  # Konteyneri göster ve UI ekle
	  shinyjs::runjs("
		$('#welcome_fullscreen_container').empty().removeClass('hidden').show();
		$('#chat_content_container').empty().hide();
	  ")

	  shiny::insertUI(
		selector = "#welcome_fullscreen_container",
		where = "beforeEnd",
		ui = createWelcomeScreen(saved_chats),
		immediate = TRUE
	  )

	  session$userData$welcome_screen_attached <- TRUE

	  # Animasyonları başlat (yalnızca gerçek full render'da çağrılmalı)
	  shinyjs::delay(40, {
		session$sendCustomMessage("initModernWelcome", list())

		# Kişiselleştirilmiş karşılama animasyonunu başlat
		shinyjs::delay(80, {
          session$sendCustomMessage("initPersonalGreeting", list(
            first_name = resolve_user_first_name()
          ))
		})
	  })
	}
 
  # Yeni sohbet başlat
  # Bu fonksiyon mevcut sohbeti temizler ve hoş geldin ekranını gösterir
  start_new_chat <- function() {
    # Önce mevcut animasyonları tamamen temizle
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
      if(window.WelcomePersonalGreeting && window.WelcomePersonalGreeting.destroy) {
        window.WelcomePersonalGreeting.destroy();
      }
    ")
 
    # Chat durumunu sıfırla (helpers_chat_runtime.R'dan)
    chat_start_new_chat(session, values, saved_chats_data, session_files,
                        filePreview, current_user_id, file_manager_data)
 
    # Welcome ekranını aktif et
    values$show_welcome <- TRUE
    values$messages <- list()

    # Welcome ekranına dönmeden hemen önce kayıtlı sohbet listesini
    # veritabanından yeniden al. Böylece son tamamlanan sohbet
    # "Son Konuşmalar" bölümünde eksiksiz görünür.
    effective_user_id <- resolve_current_user_id()

    if (!is.na(effective_user_id) && effective_user_id > 0) {
      latest_saved_chats <- tryCatch(
        load_chats_from_db(effective_user_id, include_messages = FALSE),
        error = function(e) {
          log_warn("[WELCOME] Kayıtlı sohbetler yenilenemedi: {e$message}")
          values$saved_chats %||% list()
        }
      )

      if (is.list(latest_saved_chats)) {
        values$saved_chats <- latest_saved_chats
      }
    }

    # Tamamen temizle ve yeniden render et
    shinyjs::runjs("
      $('#welcome_fullscreen_container').empty().removeClass('hidden').show();
      $('#chat_content_container').empty().hide();
    ")

    # Yeni welcome ekranını güncel sohbet listesi ile render et
    render_welcome_screen(values$saved_chats, replace_existing = TRUE)

    # Kayıtlı Söyleşiler modülünün kendi görünümünü de taze tut
    try(saved_chats_data$refresh(), silent = TRUE)
 
    # Müzik bağlam geçişi kaldırıldı - yeni mimaride müzik kesintisiz çalar
  }
 
  # Fonksiyonları döndür
  list(
    render_welcome_screen = render_welcome_screen,
    start_new_chat = start_new_chat
  )
}