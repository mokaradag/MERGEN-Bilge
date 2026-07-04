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

		  # Açılış yükleme ekranı, welcome istemci bileşenleri GERÇEKTEN hazır
		  # olmadan kapanmasın: sol arka plan videosunun OYNUYOR olması, dinamik
		  # karşılama ve Son Konuşmalar bölümünün varlığı kontrol edilir.
		  # Arka plan videoları açılışta app_loading_media.js tarafından HTTP
		  # önbelleğine tam ısıtıldığı için bgPlaying normalde ~1 sn içinde true
		  # olur. Backstop bilinçli olarak uzun tutulur (eski 3 sn yerine ~12 sn):
		  # böylece checkpoint, video gerçekten oynamadan erken/yanıltıcı biçimde
		  # gönderilmez. Açılış çubuğu stall gözcüsü ilerleme oldukça beklemeyi
		  # sürdürdüğü için bu uzun pencere erken kapanışa yol açmaz.
		  shinyjs::delay(220, {
			shinyjs::runjs("
			  (function() {
				var attempts = 0;
				var timer = setInterval(function() {
				  // Serit secici acikken karsilama boot'u bilinçli olarak
				  // ertelenmistir; sayaç ilerletilmez ve 12 sn backstop
				  // welcome_client_ready'yi ERKEN gonderemez. Kontrol, serit
				  // cozuldukten sonra kaldigi yerden devam eder.
				  if (window.MergenStartupLane &&
				      typeof window.MergenStartupLane.needsSelection === 'function' &&
				      window.MergenStartupLane.needsSelection()) {
				    return;
				  }

				  attempts += 1;

				  // Hizli Baslangic seridinde arka plan videosu bilinçli olarak
				  // oynatilmaz; hazir-olma kontrolu video kosulunu beklemez.
				  var fastLane = document.documentElement.classList.contains('mergen-fast-lane');

				  var videos = Array.prototype.slice.call(
					document.querySelectorAll('.modern-welcome-video')
				  );

				  var bgPlaying = videos.some(function(v) {
					return v.readyState >= 2 && !v.paused;
				  });

				  var greetingReady = !!document.getElementById('dynamic-greeting-text');
				  var recentReady = !!document.querySelector('.modern-welcome-footer-section');

				  if (((fastLane || bgPlaying) && greetingReady && recentReady) || attempts >= 120) {
					clearInterval(timer);
					Shiny.setInputValue('welcome_client_ready', {
					  bg_playing: bgPlaying,
					  fast_lane: fastLane,
					  greeting_ready: greetingReady,
					  recent_ready: recentReady,
					  timestamp: Date.now()
					}, { priority: 'event' });
				  }
				}, 100);
			  })();
			")
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
 
    yeni_soylesi_baslangici <- Sys.time()

    # Chat durumunu sıfırla (helpers_chat_runtime.R'dan)
    chat_start_new_chat(session, values, saved_chats_data, session_files,
                        filePreview, current_user_id, file_manager_data)

    # Welcome ekranını aktif et
    values$show_welcome <- TRUE
    values$messages <- list()

    # Welcome ekranına dönmeden hemen önce kayıtlı sohbet listesinin YALNIZCA
    # hafif özetini (son 6 kayıt) veritabanından al ve bellek içi listeyle
    # birleştir. Eski davranış tüm sohbet listesini (load_chats_from_db)
    # senkron çekiyor ve "Yeni Söyleşi" tıklamasını görünür biçimde
    # geciktiriyordu. Özet sorgusu, son tamamlanan sohbetin "Son Konuşmalar"
    # bölümünde eksiksiz ve doğru sırayla görünmesi için yeterlidir
    # (karşılama ekranı en yeni etkinliğe göre sıralar ve ilk 3'ü gösterir).
    effective_user_id <- resolve_current_user_id()

    if (!is.na(effective_user_id) && effective_user_id > 0) {
      onizleme <- tryCatch(
        load_chats_preview_from_db(effective_user_id, limit = 6L),
        error = function(e) {
          log_warn("[WELCOME] Kayıtlı sohbet önizlemesi yenilenemedi: {e$message}")
          list()
        }
      )

      if (is.list(onizleme) && length(onizleme) > 0) {
        birlesik <- values$saved_chats %||% list()
        for (cid in names(onizleme)) {
          yeni_kayit <- onizleme[[cid]]
          onceki_kayit <- birlesik[[cid]]
          # Bellekte tam mesajlar varsa korunur; özet alanlar tazelenir.
          if (!is.null(onceki_kayit) && !is.null(onceki_kayit$messages)) {
            yeni_kayit$messages <- onceki_kayit$messages
          }
          birlesik[[cid]] <- yeni_kayit
        }
        values$saved_chats <- birlesik
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

    cat(sprintf(
      "[CHAT PERF] Yeni Söyleşi hazırlandı - %.0f ms\n",
      as.numeric(difftime(Sys.time(), yeni_soylesi_baslangici, units = "secs")) * 1000
    ))
    # Müzik bağlam geçişi kaldırıldı - yeni mimaride müzik kesintisiz çalar
  }
 
  # Fonksiyonları döndür
  list(
    render_welcome_screen = render_welcome_screen,
    start_new_chat = start_new_chat
  )
}