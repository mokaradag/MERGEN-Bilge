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
            // Kapsam: ortak oturum odalarındaki kaynaklar data-source-scope=
            // 'model_bases' taşır; sunucu kişisel kovayı atlayıp yalnızca model
            // taban klasörlerinde çözer (çapraz-kullanıcı sızıntısı önlenir).
            var scope = t.getAttribute('data-source-scope') || '';
            Shiny.setInputValue('source_file_clicked', { filename: fn, scope: scope, nonce: Math.random() }, { priority: 'event' });
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

  # Söyleşi Yönetimi hazır-olma sözleşmesi: sayfaların verisi gerçekten
  # hazırlandığında modüller kendi kontrol noktasını işaretler; toplu
  # management_pages_ready anahtarını bootReadinessInit() üretir.
  # Tek seferlik: tekrarlayan tarama/ziyaretler yinelenen bildirim üretmez.
  session$userData$mergen_yonetim_hazir <- if (is.function(boot_ready$mark_once)) boot_ready$mark_once else mark_boot
  # Sayfa hazırlığı, navigasyon gözlemcisiyle aynı desende modül girdisi
  # üzerinden ve tarayıcı boştayken (düşük öncelik) tetiklenir. Yalnızca geçmiş
  # ilk sayfası hazırlanır (DB okuması işçide). Galeri ve Ortak Söyleşiler
  # burada okunmaz (ilk ziyarette): eşzamanlı okumaları olay döngüsünü tutardı.
  yonetim_hazirla <- function() {
    shinyjs::runjs(sprintf(paste0(
      "(function(){var t=%s;var f=function(){['history_module-hazirla'].forEach(",
      "function(id){Shiny.setInputValue(id,t,{priority:'event'});});};",
      "if(window.requestIdleCallback){requestIdleCallback(f,{timeout:1500});}else{setTimeout(f,0);}})();"
    ), as.numeric(Sys.time())))
  }

  startup_state <- new.env(parent = emptyenv())
  startup_state$full_load_generation <- 0L
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

	  hydrate_preview_chats <- function(chats, dispatched_hydration_user_id) {
		# Kapanan oturumun geç kalan callback'i durum değiştiremez.
		if (session_closed()) {
		  return(invisible(NULL))
		}
		# Worker gönderildikten sonra kimlik değişmişse (SSO yenileme, oturum
		# yeniden bağlama veya testte simüle edilen kullanıcı değişimi), eski
		# kullanıcının ön izlemesi artık bu oturum durumuna uygulanamaz.
		current_hydration_user_id <- resolve_current_user_id()
		if (!identical(
		  suppressWarnings(as.integer(current_hydration_user_id[1])),
		  suppressWarnings(as.integer(dispatched_hydration_user_id[1]))
		)) {
		  # Yeni sahibin süren ısıtması bayat sonuçla sıfırlanmaz.
		  if (identical(startup_state$preview_hydration_user_id, dispatched_hydration_user_id)) {
			startup_state$preview_hydration_started <- FALSE
			startup_state$preview_hydration_user_id <- NULL
		  }
		  cat("[STARTUP] Ön izleme kimliği değişti, geç kalan sonuç atlandı\n")
		  return(invisible(NULL))
		}
		# Tam liste yüklemesi başladıktan sonra geç gelen 6 sohbetlik ön izleme
		# daha güncel tam listeyi daraltmamalıdır.
		if (isTRUE(startup_state$full_saved_chats_load_started)) {
		  cat("[STARTUP] Tam söyleşi yüklemesi başladı, geç kalan ön izleme atlandı\n")
		  return(invisible(NULL))
		}
		# Ön izleme UYGULANDIKTAN sonra tam liste, kullanıcının sayfayı açmasını
		# beklemeden arka planda (işçide) hazırlanır; bir sonraki döngü turunda
		# başlatılır ki ön izleme çizimi önce gitsin. Yerel durum değiştiyse
		# (kullanıcı söyleşiye başladıysa) tembel sekme yolu korunur.
		arka_plan_tam_liste <- function() {
		  # Ertelenen tetik yalnızca planlandığı nesilde çalışır: arada sahip
		  # değiştiyse yeni sahibin ön izlemesinden önce tam yükleme başlatmaz.
		  planlanan_nesil <- startup_state$full_load_generation
		  later::later(function() {
			tetikle <- startup_state$trigger_lazy_full_saved_chats_load
			if (is.function(tetikle) && !session_closed() &&
			    identical(startup_state$full_load_generation, planlanan_nesil)) {
			  shiny::withReactiveDomain(session, shiny::isolate(tetikle("arka_plan")))
			}
		  }, 0)
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
		arka_plan_tam_liste()
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
			hydrate_preview_chats(chats, hydration_user_id)
			NULL
		  },
		  onRejected = function(err) {
			if (identical(startup_state$preview_hydration_user_id, hydration_user_id)) {
			  startup_state$preview_hydration_started <- FALSE
			  startup_state$preview_hydration_user_id <- NULL
			}
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
		# Sahip değişimlerinde tek zamanlayıcı bekler ve en güncel ısıtıcıyı çağırır.
		if (!isTRUE(startup_state$preview_fallback_pending)) {
		  startup_state$preview_fallback_pending <- TRUE
		  fallback_secs <- getOption("mergen.startup_preview_fallback_secs", 10)
		  later::later(function() {
			startup_state$preview_fallback_pending <- FALSE
			calistir <- startup_state$run_preview_hydration
			if (is.function(calistir)) tryCatch(calistir("fallback_timer"), error = function(e) NULL)
		  }, delay = fallback_secs)
		}
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
	# bu iş açılışın kritik yolunda çalıştırılmaz: Ana Söyleşi'ye ön izleme
	# (6 söyleşi) ile inilir; ön izleme uygulanınca tam liste arka planda
	# (işçide) hazırlanır. Yerel durum değiştiyse Kayıtlı Söyleşiler / Söyleşi
	# Geçmişi ilk açıldığında tembel yüklenir. Zengin şeritte açılışta yüklenir.
	run_full_saved_chats_load <- function() {
	  session$userData$saved_chats_full_pending <- FALSE

	  # Kimlik, çalıştırma anında tekrar çözülür (tembel yol geç tetiklenebilir).
	  run_user_id <- resolve_current_user_id()
	  if (is.na(run_user_id) || run_user_id <= 0) {
		startup_state$initial_saved_chats_status <- "deferred"
		session$userData$saved_chats_full_pending <- TRUE
		cat("[STARTUP] Tam söyleşi yüklemesi: geçerli kullanıcı kimliği yok, ertelendi\n")
		# Zengin Deneyim kimliksiz sonsuza dek beklemez: durum "kısmen" bildirilir.
		# Bu yalnızca açılış göstergesidir, veri erişimi açmaz (her okuma kimliği
		# yeniden doğrular). Kimlik gelince sahip yenilemesi anahtarları sıfırlar.
		if (!isTRUE(fast_lane)) {
		  session$userData$mergen_yonetim_hazir("management_pages_ready",
		    "Kullanıcı kimliği bekleniyor; Söyleşi Yönetimi kimlik doğrulanınca hazırlanacak",
		    detail = list(degraded = TRUE, identity = FALSE))
		}
		return(invisible(NULL))
	  }

	  # Bu bayrak monotondur: worker başlatıldıktan sonra geç kalan ön izleme
	  # artık values$saved_chats üzerine yazamaz.
	  startup_state$full_saved_chats_load_started <- TRUE
	  full_load_user_id <- run_user_id
	  startup_state$full_load_generation <- startup_state$full_load_generation + 1L
	  full_load_generation <- startup_state$full_load_generation

	  # Tam liste, ön izlemeyle AYNI dar açık (explicit) worker sözleşmesiyle
	  # gönderilir (limit = NA): otomatik bağımlılık taraması ana olay döngüsünü
	  # saniyelerce bloklamaz; biçim load_chats_from_db(include_messages = FALSE)
	  # ile aynıdır.
	  gonderim <- tryCatch(
		mergen_startup_chat_preview_promise(run_user_id, limit = NA_integer_,
		                                    session_token = session$token),
		error = function(e) promises::promise_reject(e))
	  # Gönderim anındaki yerel durum: sonuç geldiğinde arada yerelde
	  # eklenen/değişen/silinen söyleşiler eski DB görüntüsüyle ezilmez.
	  gonderim_aninda <- shiny::isolate(values$saved_chats)
	  # Silme/Tümünü Temizle listeyi DB'den yetkili olarak yeniden kurar ve bu
	  # sürümü artırır; gönderimden sonra artmışsa eski DB görüntüsü uygulanmaz.
	  gonderim_surumu <- session$userData$saved_chats_yetkili_surum %||% 0L
	  # Asılı kalan bir DB sorgusu/işçi Söyleşi Yönetimi hazırlığını sonsuza dek
	  # bekletmez: süre dolunca durum dürüstçe "kısmen" bildirilir (tek seferlik;
	  # zamanında tamamlanırsa etkisizdir). Tam liste geç gelse de uygulanır.
	  # Yalnızca Zengin Deneyim'de: Hızlı Başlangıç bu anahtarı beklemez.
	  if (!isTRUE(fast_lane)) later::later(function() {
		if (!session_closed() && identical(startup_state$full_load_generation, full_load_generation)) {
		  session$userData$mergen_yonetim_hazir("management_pages_ready",
		    "Söyleşi Yönetimi hazırlığı zaman aşımına uğradı; sayfa açıldığında tamamlanacak",
		    detail = list(degraded = TRUE, timeout = TRUE))
		}
	  }, delay = getOption("mergen.management_ready_deadline_secs", 20))
	  session$userData$initial_saved_chats_promise <- promises::then(
		  gonderim,
		  onFulfilled = function(chats) {
			if (session_closed() || !identical(startup_state$full_load_generation, full_load_generation)) {
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
			  if (identical(session$userData$saved_chats_yetkili_surum %||% 0L, gonderim_surumu)) {
				chats <- mergen_saved_chats_merge_newer(chats, gonderim_aninda, values$saved_chats)
			  } else {
				chats <- values$saved_chats %||% list()
			  }
			  values$saved_chats <- chats
			  session$userData$saved_chats_full_loaded <- TRUE

			  session$userData$mergen_yonetim_hazir(
				"saved_chats_full_loaded",
				"Tüm söyleşiler arka planda hazır",
				detail = list(count = length(chats))
			  )

			  # Tam liste geldiğinde karşılama ekranını güncelle.
			  refresh_welcome_if_needed(chats)
			})
			# Tam liste hazır: geçmiş ilk sayfası arka planda (işçide) hazırlanır.
			yonetim_hazirla()

			NULL
		  },
		onRejected = function(err) {
		  if (session_closed() || !identical(startup_state$full_load_generation, full_load_generation)) {
			return(NULL)
		  }
		  current_full_user_id <- resolve_current_user_id()
		  if (!identical(
			suppressWarnings(as.integer(current_full_user_id[1])),
			suppressWarnings(as.integer(full_load_user_id[1]))
		  )) {
			startup_state$initial_saved_chats_status <- "deferred"
			session$userData$saved_chats_full_pending <- TRUE
			cat("[STARTUP] Tam söyleşi yüklemesi hatası eski kimliğe ait, güncel kimlik için yeniden deneme bekletiliyor\n")
			return(NULL)
		  }
		  # Başarısızlıkta tembel yol yeniden deneyebilsin.
		  startup_state$initial_saved_chats_status <- "deferred"
		  session$userData$saved_chats_full_pending <- TRUE
		  # Açılış asılı kalmaz; durum dürüstçe "kısmen" olarak bildirilir.
		  session$userData$mergen_yonetim_hazir("management_pages_ready",
		            "Söyleşi listesi yüklenemedi; sayfa açıldığında yeniden denenecek",
		            detail = list(degraded = TRUE))
		  # Sürücü hatası DSN/sunucu adı taşıyabilir; günlüğe maskelenmiş yazılır.
		  hata_metni <- if (exists("redacted_condition_message", mode = "function")) {
			redacted_condition_message(err)
		  } else "(ayrıntı gizlendi)"
		  warning(sprintf("[SERVER] Initial saved chat load failed: %s", hata_metni))
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
	  if (length(tab) != 1L || !tab %in% c("saved_chats", "history", "arka_plan")) {
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
	# açtığında tam liste bir kez arka planda yüklenir. Gözlemci oturumda bir
	# kez kaydolur; sahip değişiminde yalnız güncel tetikleyici değişir.
	startup_state$trigger_lazy_full_saved_chats_load <- trigger_lazy_full_saved_chats_load
	if (!isTRUE(startup_state$lazy_tabs_observer_registered)) {
	  startup_state$lazy_tabs_observer_registered <- TRUE
	  observeEvent(input$tabs, {
		startup_state$trigger_lazy_full_saved_chats_load(input$tabs)
	  }, ignoreInit = TRUE)
	}

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

	# Oturum başka kullanıcıya geçince ya da kimlik düşünce kayıtlı söyleşiler
	# temizlenir; kimlik (yeni sahip ya da aynı kullanıcı) hazır olunca baştan
	# yüklenir. A'nın geç gelen yükleme sonucu kimlik denetimiyle atlanır.
	sahip_yenileme <- shiny::reactiveVal(0L)
	if (exists("mergen_session_on_owner_change", mode = "function")) {
	  mergen_session_on_owner_change(session, function(neden) {
		startup_state$full_load_generation <- startup_state$full_load_generation + 1L
		sahip_yenileme(shiny::isolate(sahip_yenileme()) + 1L)
	  })
	}
	if (exists("mergen_session_identity_signal", mode = "function")) {
	  kimlik_sinyali <- mergen_session_identity_signal(session)
	  observeEvent(kimlik_sinyali(), {
		uid <- resolve_current_user_id()
		if (isTRUE(startup_state$kimlik_bekleniyor) && !is.na(uid) && uid > 0) {
		  startup_state$kimlik_bekleniyor <- FALSE
		  sahip_yenileme(shiny::isolate(sahip_yenileme()) + 1L)
		}
	  }, ignoreInit = TRUE)
	}
	observeEvent(sahip_yenileme(), {
	  uid <- resolve_current_user_id()
	  startup_state$kimlik_bekleniyor <- is.na(uid) || uid <= 0
	  startup_state$initial_saved_chats_status <- "idle"
	  startup_state$full_saved_chats_load_started <- FALSE
	  startup_state$preview_hydration_started <- FALSE
	  startup_state$preview_hydration_user_id <- NULL
	  session$userData$saved_chats_full_pending <- FALSE
	  session$userData$saved_chats_full_loaded <- FALSE
	  # Sahibe özgü hazır-olma anahtarları yeni sahip için baştan bildirilir.
	  if (is.function(boot_ready$reset)) {
		boot_ready$reset(c("saved_chats_full_loaded", "history_rows_ready",
		                   "management_pages_ready"))
	  }
	  # Yeni sahibin listesi boşsa önceki sahibin söyleşileri görünmez.
	  values$saved_chats <- list()
	  if (isTRUE(values$show_welcome)) render_welcome_screen(list(), replace_existing = TRUE)
	  load_initial_saved_chats()
	  if (is.function(startup_state$run_preview_hydration) && isTRUE(startup_state$welcome_client_ready_seen)) {
		startup_state$run_preview_hydration("owner_change")
	  }
	}, ignoreInit = TRUE)
  
  invisible(NULL)
}
