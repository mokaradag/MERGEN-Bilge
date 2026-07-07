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
startupObserversInit <- function(input, session, values, render_welcome_screen,
                                 current_user_id, sso_state = NULL,
                                 boot_ready = NULL) {

  mark_boot <- function(key, label = key, pct = NULL, detail = NULL) {
    if (!is.null(boot_ready) && is.function(boot_ready$mark)) {
      boot_ready$mark(key, label = label, pct = pct, detail = detail)
    }
  }

  # Karşılama ekranını başlat...
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

	observeEvent(input$welcome_client_ready, {
	  mark_boot(
		"welcome_client_ready",
		"Ana Söyleşi görsel bileşenleri hazır",
		detail = input$welcome_client_ready
	  )
	}, ignoreInit = TRUE)

	# SSO akışında başlangıçta current_user_id=0 gelebilir.
	# Bu nedenle kullanıcı ID'sini her yükleme anında oturumdan çöz.
	resolve_current_user_id <- function() {
		resolve_effective_user_id(
		  session = session,
		  current_user_id = current_user_id
		)
	}
  
  startup_state <- new.env(parent = emptyenv())
  startup_state$initial_saved_chats_status <- "idle"
  
  load_initial_saved_chats <- function() {
    effective_user_id <- resolve_current_user_id()

	if (is.na(effective_user_id) || effective_user_id <= 0) {
	  cat("[STARTUP] Geçerli kullanıcı kimliği yok, kayıtlı sohbet yüklemesi atlandı\n")
	  return(invisible(NULL))
	}

	mark_boot("auth_ready", "Kimlik doğrulandı")

	if (!identical(startup_state$initial_saved_chats_status, "idle")) {
	  cat(sprintf(
		"[STARTUP] İlk kayıtlı sohbet yükleme durumu=%s, tekrar atlanıyor\n",
		startup_state$initial_saved_chats_status
	  ))
	  return(invisible(NULL))
	}
	startup_state$initial_saved_chats_status <- "loading"

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
	  mark_boot(
		"saved_chats_preview_ready",
		"Son konuşmalar hazır",
		detail = list(count = length(preview_chats))
	  )
	  refresh_welcome_if_needed(preview_chats)
	} else {
	  mark_boot(
		"saved_chats_preview_ready",
		"Son konuşma yok",
		detail = list(count = 0L)
	  )
	}

	# Tam söyleşi listesi (mesajsız) arka plan yükleyicisi. Hızlı Başlangıç'ta
	# bu iş AÇILIŞTA çalıştırılmaz: Ana Söyleşi'ye ön izleme (6 söyleşi) ile
	# inilir; tam liste kullanıcı Kayıtlı Söyleşiler / Söyleşi Geçmişi'ni ilk
	# açtığında TEMBEL yüklenir. Zengin şeritte mevcut davranış korunur.
	run_full_saved_chats_load <- function() {
	  session$userData$saved_chats_full_pending <- FALSE

	  session$userData$initial_saved_chats_promise <- promises::then(
		tracked_future_promise(
		  task_fn = function() {
			load_chats_from_db(effective_user_id, include_messages = FALSE)
		  },
		  task_type = "startup_saved_chats",
		  session_token = session$token
		),
		  onFulfilled = function(chats) {
			startup_state$initial_saved_chats_status <- "done"

			chats <- chats %||% list()

			# Promise geri çağrısı reaktif bağlam dışında çalışır; values
			# okumaları ve render_welcome_screen gibi reaktif değer
			# bağımlılıkları olan akışlar isolate ile sarmalanmalıdır. Aksi
			# halde "Can't access reactive value 'authenticated'" gibi
			# bağlam dışı reaktif okuma hataları üretebilir.
			shiny::isolate({
			  values$saved_chats <- chats

			  mark_boot(
				"saved_chats_full_loaded",
				"Tüm söyleşiler arka planda hazır",
				detail = list(count = length(chats))
			  )

			  # Tam liste geldiğinde karşılama ekranını güncelle.
			  refresh_welcome_if_needed(chats)
			})

			NULL
		  },
		onRejected = function(err) {
		  startup_state$initial_saved_chats_status <- "idle"
		  warning(sprintf("[SERVER] Initial saved chat load failed: %s", conditionMessage(err)))
		  NULL
		}
	  )
	}

	fast_lane <- mergen_startup_lane_is_fast(session$userData$startup_lane)

	if (isTRUE(fast_lane)) {
	  # Hızlı şerit: tam yükleme ertelenir (kritik açılış yolunun dışında).
	  startup_state$initial_saved_chats_status <- "deferred"
	  session$userData$saved_chats_full_pending <- TRUE
	  mark_boot(
		"saved_chats_full_loaded",
		"Söyleşi listesi gerektiğinde yüklenecek",
		detail = list(deferred = TRUE, lane = "fast_lane")
	  )
	  cat("[STARTUP] Hızlı şerit: tam söyleşi listesi ertelendi (tembel yükleme).\n")
	} else {
	  run_full_saved_chats_load()
	}

	# Tembel tetikleyici: Hızlı şeritte kullanıcı Kayıtlı Söyleşiler / Söyleşi
	# Geçmişi'ni ilk açtığında tam liste bir kez arka planda yüklenir.
	observeEvent(input$tabs, {
	  if (input$tabs %in% c("saved_chats", "history") &&
		  isTRUE(session$userData$saved_chats_full_pending) &&
		  identical(startup_state$initial_saved_chats_status, "deferred")) {
		startup_state$initial_saved_chats_status <- "loading"
		cat(sprintf("[STARTUP] Tembel tam söyleşi yükleme tetiklendi (sekme: %s).\n", input$tabs))
		run_full_saved_chats_load()
	  }
	}, ignoreInit = TRUE)
  }

	if (isTRUE(session$userData$sso_active)) {
	  observeEvent(sso_state$authenticated, {
		req(isTRUE(sso_state$authenticated))
		load_initial_saved_chats()
	  }, ignoreInit = TRUE, once = TRUE)
	} else {
	  load_initial_saved_chats()
	}
  
  invisible(NULL)
}