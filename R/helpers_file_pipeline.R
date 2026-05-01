# R/helpers_file_pipeline.R

as_llm_settings_list <- function(settings) {
  if (is.null(settings)) return(list())
  if (is.list(settings)) return(settings)
  tryCatch(reactiveValuesToList(settings), error = function(e) list())
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
                                    auto_attach = FALSE) {
  note_id <- showNotification(sprintf("İşlem başlatıldı: %s", file_info$name),
                              duration = NULL, type = "message")

  # SSO modunda başlangıçta gelen 0L yerine oturumdaki gerçek kullanıcıyı kullan
  effective_user_id <- suppressWarnings(as.integer(session$userData$user_id %||% current_user_id %||% 0L))
  if (is.na(effective_user_id)) effective_user_id <- 0L

  if (effective_user_id <= 0L) {
    cat(sprintf("[FILE PIPELINE] UYARI: effective_user_id=%d (session=%s, param=%s) - dosya: %s\n",
                effective_user_id,
                as.character(session$userData$user_id %||% "NULL"),
                as.character(current_user_id %||% "NULL"),
                file_info$name))
  }

  # Ensure file is persisted under MCP base
  dest <- file_info$datapath
  if (!is_under_mcp_base(dest)) {
    dest <- copy_to_mcp_base(list(name = file_info$name, datapath = file_info$datapath), effective_user_id)
  }

  # ============================================================================
  # KRİTİK: Dosyayı HEMEN indekse kaydet (özetleme başarısız olsa bile kalıcı olmalı)
  # ============================================================================
  tryCatch({
    global_register_file(
      dest, file_info$name,
      user_id = effective_user_id,
      persist_under_mcp_base = TRUE
    )
    cat("[FILE PIPELINE] Dosya indekse kaydedildi:", file_info$name, "\n")
  }, error = function(e) {
    cat("[FILE PIPELINE] İndeks kaydı başarısız:", conditionMessage(e), "\n")
  })
  
  # MCP araçları için oturum dosya kayıt defterini merkezi helper ile güncelle
  session_user_data_put_list_item(
    session,
    "current_session_files",
    file_info$name,
    list(name = file_info$name, datapath = dest, path = dest)
  )

  # Snapshot settings once
  settings_snapshot <- tryCatch(reactiveValuesToList(settings), error = function(e) list())
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

# Handle a batch from fileInput with identical logic to server.R observer
handle_file_upload_batch <- function(uploads_df,
                                     current_user_id,
                                     session,
                                     settings_data,
                                     file_manager_data,
                                     session_files_reactive,
                                     file_to_add_reactive) {
  if (is.null(uploads_df)) return(invisible(NULL))

  # SSO modunda başlangıçta gelen 0L yerine oturumdaki gerçek kullanıcıyı kullan
  effective_user_id <- suppressWarnings(as.integer(session$userData$user_id %||% current_user_id %||% 0L))
  if (is.na(effective_user_id)) effective_user_id <- 0L

  # SSO modunda 0L ile başlayan user_id'yi oturumdan çözümle
  if (effective_user_id <= 0L) {
    cat(sprintf("[UPLOAD BATCH] UYARI: effective_user_id=%d, session$userData$user_id=%s, current_user_id=%s\n",
                effective_user_id,
                as.character(session$userData$user_id %||% "NULL"),
                as.character(current_user_id %||% "NULL")))
  }

  uploads <- NULL
  if (is.data.frame(uploads_df)) {
    if (nrow(uploads_df) == 0) return(invisible(NULL))
    uploads <- lapply(seq_len(nrow(uploads_df)), function(i) {
      list(
        name     = as.character(uploads_df$name[i]),
        datapath = as.character(uploads_df$datapath[i]),
        size     = suppressWarnings(as.numeric(uploads_df$size[i] %||% NA_real_)),
        type     = as.character(uploads_df$type[i] %||% "")
      )
    })
  } else if (is.list(uploads_df) && !is.null(uploads_df$name)) {
    uploads <- list(list(
      name     = uploads_df$name,
      datapath = uploads_df$datapath,
      size     = uploads_df$size %||% suppressWarnings(file.info(uploads_df$datapath)$size),
      type     = uploads_df$type %||% ""
    ))
  } else {
    showToast(session, "Dosya yükleme bilgisi okunamadı.", "error")
    return(invisible(NULL))
  }

  total <- length(uploads)
  cat(sprintf("[UPLOAD] %d dosya alındı: %s\n",
              total, paste(vapply(uploads, `[[`, "", "name"), collapse = ", ")))

  note_id <- showNotification(if (total > 1) "Dosyalar alındı. İşleme başlanıyor\U2026" else
                                            "Dosya alındı. İşleme başlanıyor\U2026",
                              duration = NULL, type = "message")

  process_next <- function(i) {
    if (i > total) {
      removeNotification(note_id)
      return(invisible(NULL))
    }
    uf <- uploads[[i]]
	
    allowed_exts <- c("txt","pdf","docx","xlsx","xls","csv","json","r","py","md","log","xml","html")
    ext <- tolower(tools::file_ext(uf$name))
    
    if (!ext %in% allowed_exts) {
      showToast(session, sprintf("'%s' uzantılı dosya desteklenmiyor. İşlem atlandı.", ext), "warning")
      shinyjs::delay(50, process_next(i + 1))
      return(invisible(NULL))
    }
	
    removeNotification(note_id)
    note_id <<- showNotification(sprintf("[%d/%d] İşleniyor: %s", i, total, uf$name),
                                 duration = NULL, type = "message")

    # Dosyayı kalıcı dizine kopyala ve hemen indekse kaydet
    copy_ok <- FALSE
    tryCatch({
      dest <- copy_to_mcp_base(uf, effective_user_id)

      # Ek doğrulama: dosya boyutunu karşılaştır
      src_size <- suppressWarnings(file.info(uf$datapath)$size)
      dest_size <- suppressWarnings(file.info(dest)$size)
      if (!is.na(src_size) && !is.na(dest_size) && dest_size > 0) {
        uf$datapath <- dest
        copy_ok <- TRUE
        cat(sprintf("[UPLOAD BATCH] Dosya kopyalandı: %s -> %s (boyut: %d bayt)\n",
                    uf$name, dest, dest_size))
      } else if (path_exists_relaxed(dest)) {
        # fs::file_info başarısız olabilir ama dosya mevcut olabilir (ağ paylaşımı)
        uf$datapath <- dest
        copy_ok <- TRUE
        cat(sprintf("[UPLOAD BATCH] Dosya kopyalandı (boyut doğrulanamadı): %s -> %s\n",
                    uf$name, dest))
      } else {
        cat(sprintf("[UPLOAD BATCH] HATA: Dosya kopyalandı ama doğrulanamadı: %s -> %s (src_size=%s, dest_size=%s)\n",
                    uf$name, dest,
                    as.character(src_size %||% "NA"), as.character(dest_size %||% "NA")))
      }

      # Hemen indekse kaydet (özetleme başarısız olsa bile dosya kalıcı olacak)
      if (copy_ok) {
        tryCatch({
          global_register_file(dest, uf$name, user_id = effective_user_id, persist_under_mcp_base = TRUE)
          cat("[UPLOAD BATCH] Dosya indekse kaydedildi:", uf$name, "\n")
        }, error = function(reg_err) {
          cat("[UPLOAD BATCH] İndeks kaydı başarısız:", conditionMessage(reg_err), "\n")
        })
      }
    }, error = function(e) {
      cat(sprintf("[UPLOAD BATCH] Dosya kopyalama hatası: %s (user_id=%s, hedef_dizin=%s)\n",
                  conditionMessage(e), as.character(effective_user_id),
                  tryCatch(file.path(Sys.getenv("MCP_FILES_BASE"), paste0("user_", effective_user_id)),
                           error = function(e2) "bilinmiyor")))
    })

    # Dosya kopyalama başarısız olsa bile UI'da göster (geçici yol ile)
    # ancak kullanıcıyı uyar
    if (!copy_ok) {
      showToast(session, sprintf("'%s' kalıcı klasöre kaydedilemedi. Dosya bu oturumda kullanılabilir ancak kalıcı olmayacak.", uf$name), "warning")
    }

    file_to_add_reactive(uf)

    processAndSummarizeFile(
      uf,
      current_user_id = effective_user_id,
      session = session,
      settings = settings_data,
      file_manager_data = file_manager_data,
      session_files_reactive = session_files_reactive,
      update_manager_ui = TRUE,
      show_toast = TRUE,
      auto_attach = FALSE
    )

    shinyjs::delay(50, process_next(i + 1))
  }

  process_next(1)
}