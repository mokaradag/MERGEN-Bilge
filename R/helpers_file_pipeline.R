# R/helpers_file_pipeline.R

as_llm_settings_list <- function(settings) {
  if (is.null(settings)) return(list())

  # reaktif değerler (reactiveValues) is.list() kontrolünde TRUE döndürür; bu
  # nedenle düz liste kontrolünden ÖNCE yakalanmalıdır. Aksi halde canlı reaktif
  # nesne, anlık görüntüye çevrilmeden worker/arka plan bağlamına sızabilir ve
  # "reactive value outside consumer" hatasına yol açabilir
  # (CLAUDE.md: worker'a canlı reaktif nesne geçirme, önce düz değer yakala).
  # isolate ile reaktif olmayan bağlamda da güvenli anlık görüntü alınır.
  if (shiny::is.reactivevalues(settings)) {
    return(tryCatch(
      shiny::isolate(shiny::reactiveValuesToList(settings)),
      error = function(e) list()
    ))
  }

  if (is.list(settings)) return(settings)

  tryCatch(
    shiny::isolate(shiny::reactiveValuesToList(settings)),
    error = function(e) list()
  )
}

summarize_file_with_llm <- function(file_text, filename, settings) {
  snippet <- substr(file_text %||% "", 1, 60000)
  settings_list <- as_llm_settings_list(settings)
  chat <- list(
    list(type = "system",
         content = "Türkçe yanıtla. ÖNEMLİ: Bu bir 'özet' görevi DEĞİLDİR. Görevin, dosyanın içeriğini kapsamlı bir şekilde 'ÇIKARTMAK' ve raporlamaktır. \
Asla yüzeysel geçme. Dosyadaki her ana başlığı, alt başlığı, istatistiksel veriyi, sayısal değerleri ve teknik detayları koruyarak uzun ve ayrıntılı bir içerik dökümü hazırla. \
Kullanıcı 'özet' dese bile, sen 'Ayrıntılı İçerik Analizi' formatında yanıt ver. \
Eksik bilgi bırakma. İçeriği maddeler halinde, hiyerarşik ve okunabilir şekilde sun."),
    list(type = "user",
         content = paste0("Dosya adı: ", filename,
                          "\nİçerik (kısaltılmış olabilir):\n", snippet))
  )
  tryCatch({
    warn_msgs <- character(0)
	res <- withCallingHandlers(
	  call_llm_with_retry(chat, settings_list, max_retries = 2),
      warning = function(w) {
        warn_msgs <<- c(warn_msgs, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    if (is.list(res) && !is.null(res$content)) {
      res <- res$content
    }
    if (!is.character(res) || length(res) == 0 || is.na(res[1])) {
      res <- ""
    } else {
      res <- as.character(res)[1]
    }
    if (!nzchar(res)) {
      paste("Özet çıkarılamadı. İçerikten bir parça:\n", substr(snippet, 1, 1000))
    } else {
      res
    }
  }, error = function(e) {
    paste("Özet çıkarılamadı. İçerikten bir parça:\n", substr(snippet, 1, 1000))
  })
}

processAndSummarizeFile <- function(file_info,
                                    current_user_id,
                                    session,
                                    settings,
                                    file_manager_data,
                                    session_files_reactive,
                                    update_manager_ui = TRUE,
                                    show_toast = TRUE,
                                    auto_attach = FALSE,
                                    already_persisted = FALSE) {
  note_id <- showNotification(sprintf("İşlem başlatıldı: %s", file_info$name),
                              duration = NULL, type = "message")

  # SSO modunda başlangıçta gelen 0L yerine oturumdaki gerçek kullanıcıyı kullan
  effective_user_id <- suppressWarnings(as.integer(session$userData$user_id %||% current_user_id %||% 0L))
  if (is.na(effective_user_id)) effective_user_id <- 0L

  # KİMLİK ÇÖZÜLEMEZSE KALICILAŞTIRMA DURUR (kapalı-başarısız). Yalnızca log
  # yazmak dosyayı `user_0` klasörüne kopyalıyor ve indeksi `user_id = 0` ile
  # güncelliyordu; bu kova daha sonra kimliği doğrulanmış BAŞKA bir kullanıcıya
  # da görünebiliyordu (IDOR).
  if (effective_user_id <= 0L) {
    cat(sprintf("[FILE PIPELINE] UYARI: effective_user_id=%d (session=%s, param=%s) - dosya: %s\n",
                effective_user_id,
                as.character(session$userData$user_id %||% "NULL"),
                as.character(current_user_id %||% "NULL"),
                file_info$name))
    try(removeNotification(note_id), silent = TRUE)
    if (isTRUE(show_toast)) {
      showToast(
        session,
        "Kimlik doğrulama tamamlanmadan dosya kalıcı klasöre kaydedilemez.",
        "warning"
      )
    }
    return(invisible(NULL))
  }

  # Kalıcılaştırma TEK yerde yapılır. Dosya alım hattı (veya Dosya Yönetimi)
  # tarafından zaten kopyalanıp indekslenmiş dosya için burada ikinci kez
  # kopyalama/indeks yazımı YAPILMAZ; kayıt tam olarak bir kez gerçekleşir.
  dest <- file_info$datapath
  zaten_kalici <- isTRUE(already_persisted) || is_under_mcp_base(dest)

  if (!zaten_kalici) {
    # Kalıcılaştırma hatası bildirimi açık bırakmaz ve partiyi yarıda kesmez.
    dest <- tryCatch(
      copy_to_mcp_base(list(name = file_info$name, datapath = file_info$datapath), effective_user_id),
      error = function(e) {
        cat("[FILE PIPELINE] Kalıcılaştırma başarısız:", conditionMessage(e), "\n")
        NULL
      }
    )
    if (is.null(dest)) {
      try(removeNotification(note_id), silent = TRUE)
      if (isTRUE(show_toast)) {
        showToast(session, paste(file_info$name, "kalıcı klasöre kaydedilemedi."), "error")
      }
      return(invisible(NULL))
    }

    # İNDEKS KAYDI BAŞARISIZSA YÜKLEME DURUR. Hata yutulduğunda dosya oturum
    # durumuna ekleniyor, arayüz "yüklendi" raporluyor ancak kalıcı indeks
    # dosyayı HİÇ içermiyordu (yeniden başlatmada kayıp). Kopya da geri alınır:
    # işlem ya tam başarılı olur ya da diskte iz bırakmaz.
    indekslendi <- tryCatch({
      global_register_file(
        dest, file_info$name,
        user_id = effective_user_id,
        persist_under_mcp_base = TRUE
      )
      cat("[FILE PIPELINE] Dosya indekse kaydedildi:", file_info$name, "\n")
      TRUE
    }, error = function(e) {
      cat("[FILE PIPELINE] İndeks kaydı başarısız:", conditionMessage(e), "\n")
      FALSE
    })

    if (!isTRUE(indekslendi)) {
      # Yetim kopya yalnızca DOĞRULANMIŞ kullanıcı kökü altındaysa kaldırılır.
      if (exists("fm_cleanup_orphan_upload", mode = "function", inherits = TRUE)) {
        try(fm_cleanup_orphan_upload(dest), silent = TRUE)
      }
      try(removeNotification(note_id), silent = TRUE)
      if (isTRUE(show_toast)) {
        showToast(session, paste(file_info$name, "kalıcı indekse kaydedilemedi."), "error")
      }
      return(invisible(NULL))
    }
  }

  # MCP araçları için oturum dosya kayıt defterini merkezi helper ile güncelle
  session_user_data_put_list_item(
    session,
    "current_session_files",
    file_info$name,
    list(name = file_info$name, datapath = dest, path = dest)
  )

  # Ayar anlık görüntüsü: reactiveValues VE düz liste için aynı yardımcı.
  settings_snapshot <- tryCatch(as_llm_settings_list(settings), error = function(e) list())
  settings_snapshot$shiny_session <- NULL

  # Encoding-safe path for worker (UTF-8 dönüşümü)
  dest_safe <- tryCatch(enc2utf8(as.character(dest)), error = function(e) as.character(dest))
  file_name_safe <- tryCatch(enc2utf8(as.character(file_info$name)), error = function(e) as.character(file_info$name))

	tracked_future_promise(
	  task_fn = function() {
		file_ext <- tolower(tools::file_ext(file_name_safe))

		# Özet çıkarma - hata durumunda basit bilgi döndür
		digest <- tryCatch({
		  switch(file_ext,
			"xlsx" = , "xls" = build_excel_digest_json(dest_safe, top_levels = 12),
			{
			  txt <- readFileContentToString(list(name = file_name_safe, datapath = dest_safe, size = file.info(dest_safe)$size))
			  substr(txt, 1, 50000)
			}
		  )
		}, error = function(e) {
		  # Özet çıkarılamadı - basit bir açıklama döndür
		  sprintf("Dosya: %s\nBoyut: %s bayt\nTip: %s\n(Detaylı içerik okunamadı: %s)",
				  file_name_safe,
				  file.info(dest_safe)$size %||% "bilinmiyor",
				  file_ext,
				  conditionMessage(e))
		})

		summary_text <- summarize_file_with_llm(digest, file_name_safe, settings_snapshot)
		list(summary = summary_text, dest = dest_safe, ext = file_ext)
	  },
	  task_type = "file_summary",
	  session_token = session$token
	) %...>%
    (function(res) {
      if (isTRUE(auto_attach)) {
        current_files <- session_files_reactive() %||% list()
        current_files[[file_info$name]] <- list(
          name = file_info$name,
          summary = res$summary,
          size = file.info(res$dest)$size,
          type = res$ext
        )
        session_files_reactive(current_files)
      }

      session_user_data_put_list_item(
        session,
        "file_summaries",
        file_info$name,
        res$summary
      )

      if (!is.null(file_manager_data$sync_file_to_context)) {
        file_manager_data$sync_file_to_context(
          file_info$name,
          summary = res$summary,
          persisted_path = res$dest
        )
      }

      # NOT: global_register_file artık promise'dan önce çağrılıyor (satır 63-72)

      removeNotification(note_id)
      if (isTRUE(show_toast)) showToast(session, paste(file_info$name, "özetlendi."), "success")
    }) %...!%
    (function(e) {
      removeNotification(note_id)
      # Dosya zaten indekse kaydedildi, sadece özetleme başarısız oldu
      msg <- tryCatch(enc2utf8(conditionMessage(e)), error = function(err) conditionMessage(e))
      cat("[FILE PIPELINE] Özetleme hatası:", msg, "\n")
      showToast(session, paste(file_info$name, "yüklendi ancak özet çıkarılamadı."), "warning")
    })

  invisible(NULL)
}

# Ana Söyleşi yüklemesinin ANA SÜREÇ commit'i: kopyalama/indeksleme bittikten
# sonra dosyayı sohbet bağlamına ekler ve özetlemeyi kuyruğa alır.
# Promise geri çağrısı reaktif bağlam içinde olmadığı için isolate kullanılır.
chat_upload_commit_results <- function(results, ctx, batch_id = NULL) {
  if (!is.null(batch_id)) try(removeNotification(batch_id), silent = TRUE)

  shiny::isolate({
    for (sonuc in results %||% list()) {
      if (!isTRUE(sonuc$ok)) {
        showToast(
          ctx$session,
          sprintf("'%s' kalıcı klasöre kaydedilemedi: %s", sonuc$name, sonuc$error %||% "bilinmeyen hata"),
          "warning"
        )
        next
      }

      uf <- list(
        name = sonuc$name,
        datapath = sonuc$dest,
        size = sonuc$size,
        type = sonuc$type
      )

      ctx$file_to_add_reactive(uf)

      processAndSummarizeFile(
        uf,
        current_user_id = ctx$user_id,
        session = ctx$session,
        settings = ctx$settings_data,
        file_manager_data = ctx$file_manager_data,
        session_files_reactive = ctx$session_files_reactive,
        update_manager_ui = TRUE,
        show_toast = TRUE,
        auto_attach = FALSE,
        already_persisted = TRUE
      )
    }
  })

  invisible(NULL)
}

# fileInput/sürükle-bırak toplu yüklemesini ortak dosya alım hattına gönderir.
# Doğrulama, kopyalama ve bütünlük denetimi arka planda çalışır; bu fonksiyon
# olay döngüsünü bloklamadan hemen döner.
handle_file_upload_batch <- function(uploads_df,
                                     current_user_id,
                                     session,
                                     settings_data,
                                     file_manager_data,
                                     session_files_reactive,
                                     file_to_add_reactive) {
  if (is.null(uploads_df)) return(invisible(NULL))

  if (is.data.frame(uploads_df)) {
    if (nrow(uploads_df) == 0) return(invisible(NULL))
  } else if (!(is.list(uploads_df) && !is.null(uploads_df$name))) {
    showToast(session, "Dosya yükleme bilgisi okunamadı.", "error")
    return(invisible(NULL))
  }

  # SSO modunda başlangıçta gelen 0L yerine oturumdaki gerçek kullanıcıyı kullan
  effective_user_id <- suppressWarnings(as.integer(session$userData$user_id %||% current_user_id %||% 0L))
  if (is.na(effective_user_id)) effective_user_id <- 0L

  if (effective_user_id <= 0L) {
    cat(sprintf("[UPLOAD BATCH] UYARI: effective_user_id=%d, session$userData$user_id=%s, current_user_id=%s\n",
                effective_user_id,
                as.character(session$userData$user_id %||% "NULL"),
                as.character(current_user_id %||% "NULL")))
    # Kimlik hazır değilken yükleme kullanıcı kovasına yazılamaz; reddedilir.
    showToast(session, "Kullanıcı kimliği henüz hazır değil; dosya yüklemesi reddedildi. Lütfen tekrar deneyin.", "error")
    return(invisible(NULL))
  }

  # İzin verilen uzantılar tek kaynaktan (fm_normal_allowed_extensions) gelir;
  # böylece Ana Söyleşi ve Dosya Yönetimi yükleme yolları tutarlı kalır.
  allowed_exts <- if (exists("fm_normal_allowed_extensions", mode = "function", inherits = TRUE)) {
    fm_normal_allowed_extensions()
  } else {
    c("txt","pdf","docx","xlsx","xls","csv","json","r","py","md","log","xml","html",
      "jpg","jpeg","png","gif","webp","bmp","svg")
  }

  batch_id <- file_ingestion_new_batch_id("chat")
  plan <- file_ingestion_plan_batch(
    uploads = uploads_df,
    existing_names = character(),
    user_id = effective_user_id,
    allowed_ext = allowed_exts,
    max_size_mb = if (exists("fm_upload_limit_mb", mode = "function", inherits = TRUE)) {
      fm_upload_limit_mb()
    } else {
      getOption("mergen.upload_max_mb", 25L)
    },
    batch_id = batch_id
  )

  for (red in plan$rejected %||% list()) {
    showToast(
      session,
      sprintf("'%s' dosyası işlenemedi: %s", red$name, red$error %||% "desteklenmiyor"),
      "warning"
    )
  }

  if (!length(plan$tasks)) return(invisible(NULL))

  cat(sprintf("[UPLOAD] %d dosya alındı ve alım hattına gönderiliyor.\n", length(plan$tasks)))

  showNotification(
    sprintf("%d dosya arka planda işleniyor\U2026", length(plan$tasks)),
    duration = NULL,
    type = "message",
    id = batch_id
  )

  commit_ctx <- list(
    session = session,
    user_id = effective_user_id,
    settings_data = settings_data,
    file_manager_data = file_manager_data,
    session_files_reactive = session_files_reactive,
    file_to_add_reactive = file_to_add_reactive
  )

  outcome <- file_ingestion_submit_batch(
    controller = file_ingestion_session_controller(session),
    tasks = plan$tasks,
    user_id = effective_user_id,
    on_complete = function(results, ctx) chat_upload_commit_results(results, commit_ctx, ctx$batch_id),
    on_failure = function(message, tasks) {
      try(removeNotification(batch_id), silent = TRUE)
      showToast(session, "Dosyalar işlenemedi. Lütfen tekrar deneyin.", "error")
    },
    batch_id = batch_id
  )

  if (identical(outcome$status, "rejected")) {
    try(removeNotification(batch_id), silent = TRUE)
    showToast(session, "Yükleme kuyruğu dolu. Lütfen biraz sonra tekrar deneyin.", "warning")
  }

  invisible(outcome)
}