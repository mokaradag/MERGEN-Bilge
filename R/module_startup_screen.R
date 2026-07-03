# R/module_startup_screen.R
# Dosya Yolu: R/module_startup_screen.R
# Açıklama: Derin uzay giriş ekranı modülünün SUNUCU mantığı. Atlama tercihi,
# Three.js başlatma, deneyim modu seçimi, karakter/persona senkronizasyonu ve
# karakter medyası ön yükleme gözlemcilerini yönetir.
# UI tanımı R/module_startup_screen_ui.R içindedir (createStartupScreenUI()).

#' Giriş Ekranı Gözlemcilerini Başlat
#' @description Giriş ekranı ile ilgili server-side observer'ları kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
startupScreenObserversInit <- function(input, session, settings_data, boot_ready = NULL) {

  # Giriş ekranını başlat (Shiny bağlantısı kurulduğunda).
  # Başlangıç şeridi (startup lane) çözümü istemcidedir
  # (www/js/app_loading_lane.js): kayıtlı tercih > MERGEN_STARTUP_LANE >
  # ilk açılış seçicisi. Şerit köprüsü ve şerit gözlemcisi
  # R/module_startup_lane.R içindedir: şerit çözülene dek intro kararı
  # bekletilir, Hızlı Başlangıç intro'yu her zaman atlar, zengin şeritte
  # eski skip_intro tercihi aynen uygulanır.
  startupLaneObserversInit(input, session, settings_data, boot_ready = boot_ready)

  ensure_welcome_screen_ready <- function() {
    if (isTRUE(session$userData$welcome_screen_attached)) {
      return(invisible(NULL))
    }

    shinyjs::delay(120, {
      session$sendCustomMessage("reloadWelcomeScreen", list(
        timestamp = as.numeric(Sys.time())
      ))
    })

    invisible(NULL)
  }

  # Atlama tercihine göre giriş ekranını göster veya tamamen atla
  observeEvent(input$startup_skip_intro, {
    skip <- isTRUE(input$startup_skip_intro)

	if (skip) {
	  # Giriş ekranı atlandı - işaretle
	  session$userData$deep_space_dismissed <- TRUE

	  # Atlama Hızlı Başlangıç şeridinden mi geldi? Şerit kaynaklı atlama,
	  # kalıcı "Bir daha gösterme" (skip_intro) tercihine DÖNÜŞTÜRÜLMEZ; aksi
	  # halde kullanıcı sonradan Zengin Deneyim'e dönünce sinematik giriş
	  # kalıcı olarak kapalı kalırdı.
	  lane_now <- tryCatch({
		lp <- shiny::isolate(input$startup_lane_resolved)
		if (is.list(lp)) lp$lane else lp
	  }, error = function(e) NULL)
	  fast_lane_active <- identical(as.character(lane_now %||% "")[1], "fast_lane")

	  # Giriş ekranını tamamen atla - DOM'dan kaldır ve uygulamayı göster
	  shinyjs::runjs("
		(function() {
		  var ds = document.getElementById('deep-space-container');
		  if (ds && ds.parentNode) ds.parentNode.removeChild(ds);
		  document.body.classList.remove('deep-space-active');
		  document.body.classList.add('app-ready');
		})();
	  ")
	  # Ayarlar sayfasındaki onay kutusunu yalnızca ESKİ skip_intro tercihi
	  # için senkronize et. Bu onay kutusunun gözlemcisi skip_intro değerini
	  # localStorage'a anında kalıcılaştırdığından, şerit kaynaklı atlamada
	  # çağrılması hızlı şerit kullanımını kalıcı intro-kapatmaya çevirirdi.
	  if (!fast_lane_active) {
	    updateCheckboxInput(session, "settings_yapilandirma_module-show_intro_animation", value = FALSE)
	  }

	  # Giriş atlandığında varsayılan personanın rengini uygula
	  char_id <- normalize_character_id(settings_data$selected_character)
	  char <- get_character_record(char_id)
	  if (!is.null(char)) {
        session$sendCustomMessage("updateCharacterButtons", list(
          character = char_id,
          accent = char$accent,
          accent_active = char$accent_active,
          accent_hover = char$accent_hover,
          committed = TRUE
        ))

        # Giriş atlandığında da seçili/varsayılan persona renginin neural
        # animasyona uygulanması için (deneyim-modu akışıyla tutarlı olsun).
        session$sendCustomMessage("updateNeuralColor", list(
          accent = char$accent
        ))
	  }

      # Giriş atlandığında, kayıtlı moda göre uygulama arka plan müziğini
      # ayarla. Derin uzay intro müziği bu akışta hiç çalmaz; yalnızca
      # MusicManager ana teması önceki mod tercihine göre başlatılır.
      # Hızlı Başlangıç şeridinde açılışta müzik HİÇ başlatılmaz (katı
      # varsayılan); kullanıcı müziği uygulama içinden açabilir.
      if (!fast_lane_active) {
        shinyjs::delay(450, {
          session$sendCustomMessage("toggleMusic", list(
            enabled = isTRUE(settings_data$enable_background_music),
            character = char_id
          ))
        })
      }

      # Karşılama ekranı zaten arkada kurulmuşsa tekrar yükleme yapma
      ensure_welcome_screen_ready()

	} else {
      # Three.js sahnesini başlat
      session$sendCustomMessage("initDeepSpace", list(
        texturePath = "lib/threejs/textures/"
      ))
    }
  }, once = TRUE)

  # Giriş ekranı açıldığında karakter verilerini istemciye gönder
  session$onFlushed(function() {
    chars_data <- get_characters_data()
    if (!is.null(chars_data) && !is.null(chars_data$styles)) {
      char_list <- lapply(chars_data$styles, function(ch) {
        list(
          id = ch$id,
          label = ch$label,
          display_name = ch$display_name,
          subtitle = ch$subtitle,
          image = ch$image,
          accent = ch$accent,
          accent_hover = ch$accent_hover,
          accent_active = ch$accent_active,
          lore_tr = ch$lore_tr,
          selection_card_tr = ch$selection_card_tr,
          style_tr = ch$style_tr,
          profile_metrics = ch$profile_metrics,
          signature_moves = ch$signature_moves
        )
      })
      session$sendCustomMessage("loadCinematicCharacters", list(characters = char_list))

      # Karakter butonlarını oluştur (istemci tarafında)
      buttons_js <- paste0(
        "(function() {",
        "  var row = document.getElementById('cinematic-char-buttons-row');",
        "  if (!row) return;",
        "  row.innerHTML = '';",
        "  var chars = ", jsonlite::toJSON(lapply(char_list, function(ch) {
          list(id = ch$id, label = ch$label, accent = ch$accent)
        }), auto_unbox = TRUE), ";",
        "  chars.forEach(function(ch, i) {",
        "    var btn = document.createElement('button');",
        "    btn.className = 'cinematic-char-btn' + (i === 0 ? ' active' : '');",
        "    btn.setAttribute('data-character', ch.id);",
        "    btn.textContent = ch.label;",
        "    row.appendChild(btn);",
        "  });",
        "})();"
      )
      shinyjs::runjs(buttons_js)

      # Video verileri artık tembel yükleme ile alınıyor:
      # Kullanıcı Bütünleşik mod karakter adımına girdiğinde
      # explore_request_char_video olayı ile talep edilir.
      # Başlangıçta tüm karakterleri yüklemek oturumu gereksiz yere bloke eder.
    }

    # Sürüm bilgilendirme verilerini modala gönder
    version_data <- get_version_history()
    if (!is.null(version_data)) {
      session$sendCustomMessage("initVersionModal", list(
        versions = version_data$versions,
        current_version = version_data$current_version
      ))
    }
  }, once = TRUE)

  # Mod seçimi (giriş ekranından)
	observeEvent(input$selected_experience_mode, {
	  req(input$selected_experience_mode)
	  mode_data <- input$selected_experience_mode

	  mode <- mode_data$mode
	  if (is.null(mode) || !mode %in% c("odak", "denge", "kesif")) return()

	  # Giriş ekranı kapanıyor - işaretle (yeniden render koruması için)
	  session$userData$deep_space_dismissed <- TRUE

	  # Mod ayarlarını uygula
	  # Not: Giriş ekranı akışında müzik aşağıda, deep-space kapanışından sonra tek kez başlatılır.
	  apply_experience_mode(session, settings_data, mode, sync_music = FALSE)

	  # Ayarlar sayfasındaki mod kartlarını güncelle
	  session$sendCustomMessage("updateSettingsMode", list(mode = mode))

	  # Persona seçimi: Bütünleşik modda 2. adımdan gelir,
	  # diğer modlarda mevcut/varsayılan persona (emre) kullanılır
	  char_id <- mode_data$character
	  if (is.null(char_id) || !nzchar(char_id)) {
		char_id <- settings_data$selected_character
	  }
	  char_id <- normalize_character_id(char_id)
	  cat(sprintf("[STARTUP] Persona belirlendi: %s (mod: %s)\n", char_id, mode))

	  # Karakter ayarlarını güncelle
	  settings_data$selected_character <- char_id

	  {

		# Persona verilerini al (kimlik zaten normalleştirildi)
		char <- get_character_record(char_id)

		if (!is.null(char)) {
		  # Yapılandırma sayfasındaki karakter butonlarını güncelle
          session$sendCustomMessage("updateCharacterButtons", list(
            character = char_id,
            accent = char$accent,
            accent_active = char$accent_active,
            accent_hover = char$accent_hover,
            committed = TRUE
          ))

		  # Hoşgeldin ekranındaki neural network rengini güncelle
		  session$sendCustomMessage("updateNeuralColor", list(
			accent = char$accent
		  ))

		# Müzik karakterini güncelle (modun müzik ayarına göre)
		# Deep-space intro müziği fade-out tamamlandıktan sonra ana müzik yöneticisini
		# tek kez başlat. Böylece Ana Tema isteği karakter isteğiyle ezilmez.
		shinyjs::delay(2400, {
		  session$sendCustomMessage("toggleMusic", list(
			enabled = isTRUE(settings_data$enable_background_music),
			character = char_id
		  ))
		})

		  # localStorage'a kaydet
		  shinyjs::runjs(sprintf(
			"try { var s = JSON.parse(localStorage.getItem('mergen_settings') || '{}'); s.selected_character = '%s'; localStorage.setItem('mergen_settings', JSON.stringify(s)); } catch(e) {}",
			char_id
		  ))
		}
	  }

    # Odak ve Dinamik akışında gereksiz yeniden yüklemeyi engelle
    # Karşılama ekranı zaten hazırsa doğrudan görünür hale gelsin
    ensure_welcome_screen_ready()

	}, ignoreInit = TRUE)

	# Giriş ekranı karakter adımından video verisi talebi
	observeEvent(input$explore_request_char_video, {
	  req(input$explore_request_char_video)
	  char_id <- input$explore_request_char_video$character
	  if (!is.null(char_id) && nzchar(char_id)) {
		video_data <- tryCatch(get_character_video_data(char_id), error = function(e) NULL)
		if (!is.null(video_data)) {
		  session$sendCustomMessage("loadExploreCharVideo", video_data)
		}
	  }
	}, ignoreInit = TRUE)

	# Açılış sırasında tüm karakter/persona videolarını ön yükleme talebi
	observeEvent(input$explore_request_all_char_videos, {
	  all_video_data <- lapply(CHARACTER_VALID_IDS, function(id) {
		tryCatch(get_character_video_data(id), error = function(e) NULL)
	  })
	  all_video_data <- Filter(Negate(is.null), all_video_data)

	  session$sendCustomMessage(
		"loadExploreAllCharVideos",
		list(characters = all_video_data)
	  )
	}, ignoreInit = TRUE)

	# İstemci tarafı karakter medya ön yüklemesi tamamlandı bildirimi
	observeEvent(input$character_media_preload_ready, {
	  if (!is.null(boot_ready) && is.function(boot_ready$mark)) {
		boot_ready$mark(
		  "character_media_ready",
		  "Asistan medyası hazır",
		  detail = input$character_media_preload_ready
		)
	  }
	}, ignoreInit = TRUE)

	# Animasyonu atlama onay kutusu değişikliği (giriş ekranındaki checkbox)
	observeEvent(input$skip_intro_changed, {
    req(input$skip_intro_changed)
    skip <- isTRUE(input$skip_intro_changed$skip)

    # Ayarlar sayfasındaki onay kutusunu güncelle (skip = TRUE ise show = FALSE)
    updateCheckboxInput(session, "settings_yapilandirma_module-show_intro_animation", value = !skip)

    # settings_data reaktif değerini de güncelle
    if (!is.null(settings_data)) {
      settings_data$show_intro_animation <- !skip
    }
  }, ignoreInit = TRUE)

  invisible(NULL)
}

#' Deneyim Modunu Uygula
#' @description Seçilen moda göre ayarları günceller
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar reaktif değerleri
#' @param mode Seçilen mod (odak, denge, kesif)
apply_experience_mode <- function(session, settings_data, mode, sync_music = TRUE) {
  # Mod tanımları
  mode_settings <- list(
    odak = list(
      enable_tts_audio = FALSE,
      enable_followups = FALSE,
      enable_background_music = FALSE,
      enable_ai_expert = FALSE
    ),
    denge = list(
      enable_tts_audio = FALSE,
      enable_followups = TRUE,
      enable_background_music = TRUE,
      enable_ai_expert = FALSE
    ),
    kesif = list(
      enable_tts_audio = TRUE,
      enable_followups = TRUE,
      enable_background_music = TRUE,
      enable_ai_expert = TRUE
    )
  )

  s <- mode_settings[[mode]]
  if (is.null(s)) return()

  # Mod adını da güncelle (giriş ekranından seçildiğinde senkronizasyon için)
  settings_data$experience_mode <- mode

  # Reaktif değerleri güncelle
  settings_data$enable_tts_audio <- s$enable_tts_audio
  settings_data$enable_followups <- s$enable_followups
  settings_data$enable_background_music <- s$enable_background_music
  settings_data$enable_ai_expert <- s$enable_ai_expert

  # UI onay kutularını güncelle
  updateCheckboxInput(session, "settings_yapilandirma_module-enable_tts_audio", value = s$enable_tts_audio)
  updateCheckboxInput(session, "settings_yapilandirma_module-enable_followups", value = s$enable_followups)
  updateCheckboxInput(session, "settings_yapilandirma_module-enable_background_music", value = s$enable_background_music)
  updateCheckboxInput(session, "settings_yapilandirma_module-enable_ai_expert", value = s$enable_ai_expert)

  # Müzik durumunu güncelle (karakter bilgisiyle birlikte)
	if (isTRUE(sync_music)) {
	  session$sendCustomMessage("toggleMusic", list(
		enabled = isTRUE(settings_data$enable_background_music),
		character = normalize_character_id(settings_data$selected_character)
	  ))
	}

  # Mod tercihini localStorage'a kaydet
  shinyjs::runjs(sprintf(
    "try { var s = JSON.parse(localStorage.getItem('mergen_settings') || '{}'); s.experience_mode = '%s'; s.enable_tts_audio = %s; s.enable_followups = %s; s.enable_background_music = %s; s.enable_ai_expert = %s; localStorage.setItem('mergen_settings', JSON.stringify(s)); } catch(e) {}",
    mode,
    tolower(as.character(s$enable_tts_audio)),
    tolower(as.character(s$enable_followups)),
    tolower(as.character(s$enable_background_music)),
    tolower(as.character(s$enable_ai_expert))
  ))
}
