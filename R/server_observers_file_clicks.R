# R/server_observers_file_clicks.R
# Dosya Yolu: R/server_observers_file_clicks.R
# Açıklama: Kaynak dosya tıklamaları, analiz dosyası tıklamaları ve
# dosya yöneticisi bağlantı observer'ları.
# Kaynakça linkleri, analiz çıktı dosyaları ve sohbet içi dosya önizlemeleri burada işlenir.

#' Dosya Tıklama Gözlemcilerini Başlat
#' @description Kaynak ve analiz dosyası tıklama observer'larını kurar
#' @param input Shiny input nesnesi
#' @param session Shiny session nesnesi
#' @param settings_data Ayarlar modülünden dönen reaktif ayarlar
#' @param api_config API yapılandırma listesi
#' @param filePreview Dosya önizleme modülü
#' @param file_manager_data Dosya yöneticisi modül verisi
#' @param session_files Oturum dosyaları reaktif değeri
fileClickObserversInit <- function(input, session, settings_data, api_config,
                                    filePreview, file_manager_data, session_files) {
  
  last_source_click <- reactiveVal(list(name = NULL, t = 0))
  
  observeEvent(input$source_file_clicked, {
    req(input$source_file_clicked)
    
    ev <- input$source_file_clicked
    raw_name <- if (is.character(ev)) ev[1] else (ev$filename %||% ev$name %||% "")
    raw_name <- as.character(raw_name %||% "")
    raw_name <- sub("^\\s*\\d+\\)\\s*", "", raw_name)
    
    now  <- as.numeric(Sys.time())
    last <- last_source_click()
    if (is.list(last) && identical(last$name, raw_name) && (now - (last$t %||% 0)) < 0.5) {
      return(invisible(NULL))
    }
    last_source_click(list(name = raw_name, t = now))
    
    if (!nzchar(raw_name)) {
      showToast(session, "Geçersiz kaynak bağlantısı: dosya adı yok.", "error")
      return(invisible(NULL))
    }
    
    log_info("[SRC_CLICK] tıklanan kaynak: '{raw_name}'")
    
    handle_source_file_click(ev, settings_data, api_config, session, filePreview)
  }, ignoreInit = TRUE)
  
  observeEvent(input$analysis_file_clicked, {
    req(input$analysis_file_clicked)
    
    filepath_raw <- input$analysis_file_clicked$filepath
    # SKALER ZORUNLU: çok elemanlı bir değerde trimws/gsub vektörü koruyor,
    # aşağıdaki grepl() koşulu `if` içine uzunluk > 1 vektör veriyor ve önizleme
    # açılmadan işlem hatayla düşüyordu.
    # KARAKTER ZORUNLU: istemci tek elemanlı bir LİSTE gönderirse uzunluk
    # denetimi geçiyor, nzchar() hata veriyor ve gözlemci kullanıcıya hiç
    # bildirim göstermeden düşüyordu.
    if (is.null(filepath_raw) || !is.character(filepath_raw) ||
        length(filepath_raw) != 1L ||
        is.na(filepath_raw) || !nzchar(filepath_raw)) {
      showToast(session, "Geçersiz dosya yolu.", "error")
      return(invisible(NULL))
    }
    
	filepath_clean <- trimws(as.character(filepath_raw))

	# Yalnızca boşluktan oluşan değer `nzchar()` denetimini geçiyor, kırpma
	# sonrası boş yol mevcut `www` DİZİNİNE çözülüyor ve önizleme modalı
	# reddetme yerine "Desteklenmeyen Dosya Türü" gösteriyordu.
	if (!nzchar(filepath_clean)) {
	  showToast(session, "Geçersiz dosya yolu.", "error")
	  return(invisible(NULL))
	}

	repo_root_for_files <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
	repo_candidates <- unique(Filter(nzchar, c(
	  repo_root_for_files,
	  tryCatch(as.character(get0("repo_root", envir = globalenv(), inherits = TRUE) %||% "")[1],
			   error = function(e) ""),
	  getwd(),
	  file.path(getwd(), ".."),
	  file.path(getwd(), "../..")
	)))

	repo_root_for_files <- getwd()
	for (cand in repo_candidates) {
	  cand_norm <- tryCatch(normalizePath(cand, winslash = "/", mustWork = FALSE),
							error = function(e) cand)
	  if (file.exists(file.path(cand_norm, "app.R")) &&
		  dir.exists(file.path(cand_norm, "www"))) {
		repo_root_for_files <- cand_norm
		break
	  }
	}

	filepath_slash <- gsub("\\", "/", filepath_clean, fixed = TRUE)

	# '..' geçişi hiçbir biçimde kabul edilmez.
	if (grepl("(^|/)\\.\\.(/|$)", filepath_slash, perl = TRUE)) {
	  showToast(session, "Geçersiz dosya yolu.", "error")
	  log_warn("[ANALYSIS_FILE] Yol geçişi reddedildi: {filepath_clean}", filepath_clean = filepath_clean)
	  return(invisible(NULL))
	}

	mutlak_mi <- startsWith(filepath_slash, "/") ||
	  grepl("^//", filepath_slash) ||
	  grepl("^[A-Za-z]:", filepath_slash)

	full_path <- if (mutlak_mi) {
	  filepath_clean
	} else if (startsWith(filepath_slash, "www/")) {
	  file.path(repo_root_for_files, filepath_slash)
	} else {
	  file.path(repo_root_for_files, "www", filepath_slash)
	}

    full_path <- normalize_mcp_path(full_path, must_exist = FALSE)

	# Çözülen yol ONAYLI köklerden birinin içinde kalmalıdır. Eskiden istemciden
	# gelen mutlak yol olduğu gibi kullanılıyordu ve sunucu hesabıyla keyfi yerel
	# dosya okunup indirilebiliyordu.
	.afc_kok_anahtar <- function(x) {
	  x <- tryCatch(
	    normalizePath(as.character(x)[1], winslash = "/", mustWork = FALSE),
	    error = function(e) as.character(x)[1]
	  )
	  x <- sub("/+$", "", gsub("\\\\", "/", x))
	  if (.Platform$OS.type == "windows") tolower(x) else x
	}

	tiklayan_uid <- tryCatch(
	  resolve_effective_user_id(session = session),
	  error = function(e) 0L
	)

	izinli_kokler <- unique(Filter(nzchar, c(
	  file.path(repo_root_for_files, "www"),
	  if (isTRUE(tiklayan_uid > 0L)) {
	    tryCatch(mergen_user_upload_dir(tiklayan_uid), error = function(e) "")
	  } else {
	    ""
	  }
	)))

	hedef_anahtar <- .afc_kok_anahtar(full_path)
	kok_anahtarlari <- vapply(izinli_kokler, .afc_kok_anahtar, character(1), USE.NAMES = FALSE)

	if (!any(hedef_anahtar == kok_anahtarlari |
			 startsWith(hedef_anahtar, paste0(kok_anahtarlari, "/")))) {
	  showToast(session, "Geçersiz dosya yolu.", "error")
	  log_warn("[ANALYSIS_FILE] Onaylı kök dışındaki yol reddedildi: {hedef_anahtar}", hedef_anahtar = hedef_anahtar)
	  return(invisible(NULL))
	}

	# Varlığı KANITLANAN varyant alınır: `path_exists_relaxed()` bir UNC ya da
	# `enc2utf8()` varyantı üzerinden TRUE dönebiliyor, ancak kanonikleştirme
	# ÖZGÜN yolu kullandığı için sonuç NA oluyor ve dosya "Geçersiz dosya yolu."
	# ile reddediliyordu.
	var_olan_varyant <- path_existing_variant(full_path)
	if (is.na(var_olan_varyant)) {
	  showToast(session, paste("Dosya bulunamadı:", basename(filepath_clean)), "error")
	  log_error("[ANALYSIS_FILE] Dosya mevcut değil: {full_path}", full_path = full_path)
	  return(invisible(NULL))
	}

	# KANONİK YOL ZORUNLU: `normalizePath(..., mustWork = FALSE)` sembolik
	# bağlantı / reparse point çözülemediğinde yolu SÖZDİZİMSEL hâliyle
	# döndürebiliyor. Bu durumda izinli kök altındaki bir bağlantı önek
	# denetiminden geçiyor, ancak `openAnyPreview()` kök DIŞINDAKİ hedefe
	# erişiyordu. Varlık denetiminden SONRA hem hedef hem kökler `mustWork = TRUE`
	# ile kanonikleştirilip yeniden karşılaştırılır ve önizlemeye KANONİK yol geçer.
	kanonik_hedef <- tryCatch(
	  normalizePath(var_olan_varyant, winslash = "/", mustWork = TRUE),
	  error = function(e) NA_character_
	)
	kanonik_kokler <- vapply(
	  izinli_kokler,
	  function(k) tryCatch(
	    normalizePath(k, winslash = "/", mustWork = TRUE),
	    error = function(e) NA_character_
	  ),
	  character(1), USE.NAMES = FALSE
	)
	kanonik_kokler <- kanonik_kokler[!is.na(kanonik_kokler)]

	if (is.na(kanonik_hedef) || !length(kanonik_kokler)) {
	  showToast(session, "Geçersiz dosya yolu.", "error")
	  log_warn("[ANALYSIS_FILE] Kanonik yol çözülemedi; erişim reddedildi.")
	  return(invisible(NULL))
	}

	kanonik_hedef_anahtar <- .afc_kok_anahtar(kanonik_hedef)
	kanonik_kok_anahtarlari <- vapply(kanonik_kokler, .afc_kok_anahtar, character(1), USE.NAMES = FALSE)

	if (!any(kanonik_hedef_anahtar == kanonik_kok_anahtarlari |
			 startsWith(kanonik_hedef_anahtar, paste0(kanonik_kok_anahtarlari, "/")))) {
	  showToast(session, "Geçersiz dosya yolu.", "error")
	  log_warn("[ANALYSIS_FILE] Kanonik kök dışındaki yol reddedildi.")
	  return(invisible(NULL))
	}

	full_path <- kanonik_hedef

    file_info <- list(
      name = basename(full_path),
      datapath = full_path,
      size = suppressWarnings(file.info(full_path)$size)
    )

	# DOĞRULAMA ile OKUMA ARASINDAKİ PENCERE (TOCTOU): yol tabanlı erişim ata
	# bileşenlerini İZLER; kanonik denetim ile önizleme arasında bir ata dizin
	# bağlantı/junction ile takas edilirse okuma izinli kök DIŞINA çıkabiliyordu.
	# Base R tanıtıcı-bağıl (openat / O_NOFOLLOW) temel işlem sunmadığı için
	# pencere tamamen kapatılamaz; kanonik çözüm önizlemeden HEMEN ÖNCE yeniden
	# yapılır ve fark hâlinde erişim REDDEDİLİR (asla "başarılı" raporlanmaz).
	son_kanonik <- tryCatch(
	  normalizePath(full_path, winslash = "/", mustWork = TRUE),
	  error = function(e) NA_character_
	)
	if (is.na(son_kanonik) ||
		!identical(.afc_kok_anahtar(son_kanonik), kanonik_hedef_anahtar)) {
	  showToast(session, "Geçersiz dosya yolu.", "error")
	  log_warn("[ANALYSIS_FILE] Kanonik yol önizleme öncesi değişti; erişim reddedildi.")
	  return(invisible(NULL))
	}

    log_info("[ANALYSIS_FILE] Önizleme açılıyor: {full_path}", full_path = full_path)
    openAnyPreview(file_info, session, filePreview)
    
  }, ignoreInit = TRUE)
  
  observeEvent(input$view_file_from_chat, {
    req(input$view_file_from_chat)
    file_id <- input$view_file_from_chat
    
    if (exists("file_store") && !is.null(file_store[[file_id]])) {
      file_info <- file_store[[file_id]]
      filePreview$open(file_info)
    } else {
      showToast(session, "Dosya bulunamadı.", "error")
    }
  }, ignoreInit = TRUE)
  
  observeEvent(file_manager_data$file_removed(), {
    removed_file <- file_manager_data$file_removed()
    if (!is.null(removed_file)) {
      current_files <- session_files()
      if (!is.null(removed_file$name) && removed_file$name %in% names(current_files)) {
        current_files[[removed_file$name]] <- NULL
        session_files(current_files)
        showToast(session, paste("Dosya AI bağlamından kaldırıldı:", removed_file$name), "info")
        
        session_user_data_remove_list_item(
          session,
          "file_summaries",
          removed_file$name
        )
      }
    }
  }, ignoreInit = TRUE)
  
  observeEvent(file_manager_data$all_files_cleared(), {
    if (isTRUE(file_manager_data$all_files_cleared())) {
      session_files(list())
      session_user_data_set_list(session, "file_summaries", list())
      showToast(session, "Tüm dosyalar AI bağlamından temizlendi.", "info")
    }
  }, ignoreInit = TRUE)
  
  invisible(NULL)
}