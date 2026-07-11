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

  startup_state <- new.env(parent = emptyenv())
  startup_state$initial_saved_chats_status <- "idle"
  startup_state$lane_wait_registered <- FALSE
  startup_state$full_saved_chats_load_started <- FALSE
  startup_state$welcome_client_ready_seen <- FALSE
  startup_state$preview_hydration_started <- FALSE
  startup_state$run_preview_hydration <- NULL

	observeEvent(input$welcome_client_ready, {
	  startup_state$welcome_client_ready_seen <- TRUE
	  mark_boot(
		"welcome_client_ready",
		"Ana Söyleşi görsel bileşenleri hazır",
		detail = input$welcome_client_ready
	  )
	  # Hızlı şerit: ön izleme ısıtması İLK ÇİZİMDEN SONRA başlar; böylece
	  # açılış katmanı ve ilk etkileşim ön izleme hazırlığını hiç beklemez.
	  if (is.function(startup_state$run_preview_hydration)) {
		startup_state$run_preview_hydration("welcome_client_ready")
	  }
	}, ignoreInit = TRUE)

	# SSO akışında başlangıçta current_user_id=0 gelebilir.
	# Bu nedenle kullanıcı ID'sini her yükleme anında oturumdan çöz.
	resolve_current_user_id <- function() {
		resolve_effective_user_id(
		  session = session,
		  current_user_id = current_user_id
		)
	}
  
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
	# Yarış düzeltmesi: şerit çözülmeden yükleme kararı verilmez. Şerit API'si
	# olmayan istemcide sunucu köprüsü rich_lane (legacy_no_api) gönderir,
	# bu yüzden giriş her durumda gelir ve eski davranış korunur.
	lane_payload <- shiny::isolate(input$startup_lane_resolved)
	if (is.null(lane_payload)) {
	  if (!isTRUE(startup_state$lane_wait_registered)) {
		startup_state$lane_wait_registered <- TRUE
		observeEvent(input$startup_lane_resolved, {
		  load_initial_saved_chats()
		}, once = TRUE)
		cat("[STARTUP] Kayıtlı sohbet yüklemesi başlangıç şeridi çözümünü bekliyor\n")
	  }
	  return(invisible(NULL))
	}
	startup_state$initial_saved_chats_status <- "loading"

	fast_lane <- mergen_startup_lane_is_fast(
	  if (is.list(lane_payload)) lane_payload$lane else lane_payload
	)

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

	apply_preview_chats <- function(preview_chats, deferred = FALSE) {
	  preview_chats <- preview_chats %||% list()
	  if (length(preview_chats) > 0) {
		values$saved_chats <- preview_chats
		mark_boot(
		  "saved_chats_preview_ready",
		  "Son konuşmalar hazır",
		  detail = list(count = length(preview_chats), deferred = deferred)
		)
		refresh_welcome_if_needed(preview_chats)
	  } else {
		mark_boot(
		  "saved_chats_preview_ready",
		  "Son konuşma yok",
		  detail = list(count = 0L, deferred = deferred)
		)
	  }
	  invisible(NULL)
	}

	session_closed <- function() {
	  tryCatch(isTRUE(session$isClosed()), error = function(e) FALSE)
	}

	if (isTRUE(fast_lane)) {
	  # Worker başlatılırken mevcut kayıtlı sohbet durumu alınır. Callback yalnızca
	  # bu durum değişmediyse ön izlemeyi uygulayabilir; yerel sohbet ekleme/güncelleme
	  # daha yeni durumu temsil eder ve hiçbir zaman eski ön izlemeyle ezilmez.
	  preview_saved_chats_snapshot <- shiny::isolate(values$saved_chats)

	  # Dürüst kontrol noktası: ön izleme Hızlı Başlangıç kapanış sözleşmesinin
	  # parçası değildir ve HEMEN ertelenmiş olarak işaretlenir. Gerçek ısıtma
	  # ayrı bir kontrol noktasıyla (saved_chats_preview_hydrated) raporlanır;
	  # aynı anahtar iki farklı durumu (ertelendi/yüklendi) temsil edemez.
	  mark_boot(
		"saved_chats_preview_ready",
		"Son konuşmalar arka planda yüklenecek",
		detail = list(deferred = TRUE)
	  )

	  hydrate_preview_chats <- function(chats) {
		# Kapanan oturumun geç kalan callback'i durum değiştiremez.
		if (session_closed()) {
		  return(invisible(NULL))
		}
		# Worker gönderildikten sonra kimlik değişmişse (SSO yenileme, oturum
		# yeniden bağlama veya testte simüle edilen kullanıcı değişimi), eski
		# kullanıcının ön izlemesi artık bu oturum durumuna uygulanamaz.
		current_hydration_user_id <- resolve_current_user_id()
		dispatched_hydration_user_id <- startup_state$preview_hydration_user_id
		if (!identical(
		  suppressWarnings(as.integer(current_hydration_user_id[1])),
		  suppressWarnings(as.integer(dispatched_hydration_user_id[1]))
		)) {
		  startup_state$preview_hydration_started <- FALSE
		  startup_state$preview_hydration_user_id <- NULL
		  cat("[STARTUP] Ön izleme kimliği değişti, geç kalan sonuç atlandı\n")
		  return(invisible(NULL))
		}
		# Tam liste yüklemesi başladıktan sonra geç gelen 6 sohbetlik ön izleme
		# daha güncel tam listeyi daraltmamalıdır.
		if (isTRUE(startup_state$full_saved_chats_load_started)) {
		  cat("[STARTUP] Tam söyleşi yüklemesi başladı, geç kalan ön izleme atlandı\n")
		  return(invisible(NULL))
		}
		shiny::isolate({
		  if (!identical(values$saved_chats, preview_saved_chats_snapshot)) {
			cat("[STARTUP] Kayıtlı sohbet durumu değişti, eski ön izleme atlandı\n")
			return(invisible(NULL))
		  }

		  chats <- chats %||% list()
		  if (length(chats) > 0) {
			values$saved_chats <- chats
			mark_boot(
			  "saved_chats_preview_hydrated",
			  "Son konuşmalar hazır",
			  detail = list(count = length(chats))
			)
			refresh_welcome_if_needed(chats)
		  } else {
			mark_boot(
			  "saved_chats_preview_hydrated",
			  "Son konuşma yok",
			  detail = list(count = 0L)
			)
		  }
		})
		invisible(NULL)
	  }

	  run_preview_hydration <- function(trigger = "bilinmiyor") {
		# Isıtma idempotenttir: istemci sinyali ve güvenlik zamanlayıcısı
		# birlikte tetiklese bile tek bir worker gönderimi yapılır.
		if (isTRUE(startup_state$preview_hydration_started)) {
		  return(invisible(FALSE))
		}
		if (session_closed()) {
		  return(invisible(FALSE))
		}

		# Kimlik ısıtma anında yeniden çözülür; geçersiz kimlikle sorgu açılmaz.
		hydration_user_id <- resolve_current_user_id()
		if (is.na(hydration_user_id) || hydration_user_id <= 0) {
		  cat("[STARTUP] Ön izleme ısıtması: geçerli kullanıcı kimliği yok, atlandı\n")
		  return(invisible(FALSE))
		}
		startup_state$preview_hydration_started <- TRUE
		startup_state$preview_hydration_user_id <- hydration_user_id

		dispatch_started <- Sys.time()
		preview_promise <- tryCatch({
		  if (exists("mergen_startup_chat_preview_promise",
					 mode = "function", inherits = TRUE)) {
			mergen_startup_chat_preview_promise(
			  hydration_user_id,
			  limit = 6L,
			  session_token = session$token
			)
		  } else {
			# İzole bağlamlar için korumalı geri dönüş: eski otomatik-tarama yolu.
			tracked_future_promise(
			  task_fn = function() {
				load_chats_preview_from_db(hydration_user_id, limit = 6L)
			  },
			  task_type = "startup_saved_chats_preview",
			  session_token = session$token
			)
		  }
		}, error = function(e) {
		  warning(sprintf("[SERVER] Preview chat dispatch failed: %s", conditionMessage(e)))
		  NULL
		})

		cat(sprintf(
		  "[STARTUP PERF] preview_dispatch trigger=%s elapsed_ms=%.0f\n",
		  trigger,
		  as.numeric(difftime(Sys.time(), dispatch_started, units = "secs")) * 1000
		))

		if (is.null(preview_promise)) {
		  startup_state$preview_hydration_started <- FALSE
		  startup_state$preview_hydration_user_id <- NULL
		  return(invisible(FALSE))
		}

		session$userData$initial_saved_chats_preview_promise <- promises::then(
		  preview_promise,
		  onFulfilled = function(chats) {
			hydrate_preview_chats(chats)
			NULL
		  },
		  onRejected = function(err) {
			startup_state$preview_hydration_started <- FALSE
			startup_state$preview_hydration_user_id <- NULL
			warning(sprintf("[SERVER] Preview chat load failed: %s", conditionMessage(err)))
			NULL
		  }
		)
		invisible(TRUE)
	  }
	  startup_state$run_preview_hydration <- run_preview_hydration

	  if (isTRUE(startup_state$welcome_client_ready_seen)) {
		# İlk çizim sinyali şerit çözümünden önce geldiyse ısıtma hemen başlar.
		run_preview_hydration("welcome_ready_onceden")
	  } else {
		# Güvenli geri dönüş: istemci hazır sinyali hiç gelmezse ön izleme yine
		# de yüklenir; açılış sözleşmesi bu zamanlayıcıya bağlı değildir.
		fallback_secs <- getOption("mergen.startup_preview_fallback_secs", 10)
		later::later(function() {
		  tryCatch(run_preview_hydration("fallback_timer"), error = function(e) NULL)
		}, delay = fallback_secs)
	  }
	} else {
	  # Zengin şerit: ilk ekranın hızlı gelmesi için hafif özet liste senkron yüklenir.
	  preview_chats <- tryCatch(
		load_chats_preview_from_db(effective_user_id, limit = 6L),
		error = function(e) {
		  warning(sprintf("[SERVER] Preview chat load failed: %s", conditionMessage(e)))
		  list()
		}
	  )
	  apply_preview_chats(preview_chats)
	}

	# Tam söyleşi listesi (mesajsız) arka plan yükleyicisi. Hızlı Başlangıç'ta
	# bu iş AÇILIŞTA çalıştırılmaz: Ana Söyleşi'ye ön izleme (6 söyleşi) ile
	# inilir; tam liste kullanıcı Kayıtlı Söyleşiler / Söyleşi Geçmişi'ni ilk
	# açtığında TEMBEL yüklenir. Zengin şeritte mevcut davranış korunur.
	run_full_saved_chats_load <- function() {
	  session$userData$saved_chats_full_pending <- FALSE

	  # Kimlik, çalıştırma anında tekrar çözülür (tembel yol geç tetiklenebilir).
	  run_user_id <- resolve_current_user_id()
	  if (is.na(run_user_id) || run_user_id <= 0) {
		startup_state$initial_saved_chats_status <- "deferred"
		session$userData$saved_chats_full_pending <- TRUE
		cat("[STARTUP] Tam söyleşi yüklemesi: geçerli kullanıcı kimliği yok, ertelendi\n")
		return(invisible(NULL))
	  }

	  # Bu bayrak monotondur: worker başlatıldıktan sonra geç kalan ön izleme
	  # artık values$saved_chats üzerine yazamaz.
	  startup_state$full_saved_chats_load_started <- TRUE
	  full_load_user_id <- run_user_id

	  session$userData$initial_saved_chats_promise <- promises::then(
		tracked_future_promise(
		  task_fn = function() {
			load_chats_from_db(run_user_id, include_messages = FALSE)
		  },
		  task_type = "startup_saved_chats",
		  session_token = session$token
		),
		  onFulfilled = function(chats) {
			if (session_closed()) {
			  return(NULL)
			}
			current_full_user_id <- resolve_current_user_id()
			if (!identical(
			  suppressWarnings(as.integer(current_full_user_id[1])),
			  suppressWarnings(as.integer(full_load_user_id[1]))
			)) {
			  startup_state$initial_saved_chats_status <- "deferred"
			  session$userData$saved_chats_full_pending <- TRUE
			  cat("[STARTUP] Tam söyleşi yüklemesi kimliği değişti, geç kalan sonuç atlandı\n")
			  return(NULL)
			}
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
		  # Başarısızlıkta tembel yol yeniden deneyebilsin.
		  startup_state$initial_saved_chats_status <- "deferred"
		  session$userData$saved_chats_full_pending <- TRUE
		  warning(sprintf("[SERVER] Initial saved chat load failed: %s", conditionMessage(err)))
		  NULL
		}
	  )
	}

	if (isTRUE(fast_lane)) {
	  # Hızlı şerit: tam yükleme ertelenir (kritik açılış yolunun dışında).
	  # Erteleme ve gerçek tamamlanma AYRI anahtarlardır: saved_chats_full_loaded
	  # yalnızca tam liste gerçekten yüklendiğinde işaretlenir; böylece boot
	  # performans logunda gerçek tamamlanma görünmez hâle gelmez.
	  startup_state$initial_saved_chats_status <- "deferred"
	  session$userData$saved_chats_full_pending <- TRUE
	  mark_boot(
		"saved_chats_full_deferred",
		"Söyleşi listesi gerektiğinde yüklenecek",
		detail = list(deferred = TRUE, lane = "fast_lane")
	  )
	  cat("[STARTUP] Hızlı şerit: tam söyleşi listesi ertelendi (tembel yükleme).\n")
	} else {
	  run_full_saved_chats_load()
	}

	# Tembel tetikleyicinin anlık kontrolü ve observer yolu aynı idempotent
	# koşulları kullanır; böylece şerit çözülmeden önce seçilmiş sekme kaçırılmaz.
	trigger_lazy_full_saved_chats_load <- function(tab) {
	  if (!identical(tab, "saved_chats") && !identical(tab, "history")) {
		return(invisible(FALSE))
	  }
	  if (!isTRUE(session$userData$saved_chats_full_pending) ||
		  !identical(startup_state$initial_saved_chats_status, "deferred")) {
		return(invisible(FALSE))
	  }

	  startup_state$initial_saved_chats_status <- "loading"
	  cat(sprintf("[STARTUP] Tembel tam söyleşi yükleme tetiklendi (sekme: %s).\n", tab))
	  run_full_saved_chats_load()
	  invisible(TRUE)
	}

	# Hızlı şeritte kullanıcı Kayıtlı Söyleşiler / Söyleşi Geçmişi'ni ilk
	# açtığında tam liste bir kez arka planda yüklenir.
	observeEvent(input$tabs, {
	  trigger_lazy_full_saved_chats_load(input$tabs)
	}, ignoreInit = TRUE)

	# Sekme şerit çözülmeden önce restore edilmiş olabilir. Deferral kurulduktan
	# sonra mevcut değeri aynı korumalı yol üzerinden hemen değerlendir.
	trigger_lazy_full_saved_chats_load(shiny::isolate(input$tabs))
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
