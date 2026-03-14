# ==============================================================================
# Dosya Yolu: R/helpers_llm_api.R
# Açıklama:   Temel LLM API çağrı fonksiyonları (call_local_llm, call_llm_with_retry).
#              Kimlik doğrulama, istek gönderme, yanıt ayrıştırma ve Kaynakça oluşturma
#              işlemlerini kapsar. global.R tarafından config_api.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- DEBUG LOG YARDIMCISI ---
# mergen.debug seçeneği TRUE ise konsola yazar, değilse sessizce geçer
mergen_debug_cat <- function(...) {
  if (isTRUE(getOption("mergen.debug", FALSE))) {
    cat(...)
  }
}

# --- ANA LLM API ÇAĞRI FONKSİYONU ---
# İşçi güvenli (worker-safe) LLM çağrısı - orijinal çalışan sürümden korunmuştur
call_local_llm <- function(chat_history, current_settings) {
  llm_start_time <- Sys.time()
  selected_model <- current_settings$model_selection

  creds <- resolve_local_llm_credentials(selected_model)
  api_url <- creds$endpoint
  if (!nzchar(api_url)) {
    stop("API endpoint not found in configuration")
  }

  default_api_key <- creds$default_api_key %||% ""
  allow_user_key <- isTRUE(creds$allow_user_key)
  # Önce ilgili uç için kullanıcı anahtarı kullanılabilir mi bak
  api_key <- ""
  if (allow_user_key) {
    api_key <- as.character(current_settings$api_key %||% current_settings$api_key_override %||% "")
    if (!nzchar(api_key)) {
      sess <- current_settings$shiny_session %||% NULL
      if (!is.null(sess) && !is.null(sess$userData$ai_api_key)) {
        api_key <- as.character(sess$userData$ai_api_key)[1]
      }
    }
  } else {
    api_key <- as.character(current_settings$api_key_override %||% "")
  }
  if (!nzchar(api_key) && nzchar(default_api_key)) {
    api_key <- as.character(default_api_key)[1]
  }
  # Yerel uçlar (Ollama/LM Studio vb.) için anahtar zorunlu değil
  is_local_noauth <- grepl("(?i)(localhost|127\\.0\\.0\\.1|ollama)", api_url)
  if (!nzchar(api_key) && !is_local_noauth) {
    stop("AUTH_MISSING_KEY: Kullanıcı API anahtarı bulunamadı. Lütfen Ayarlar > Model Ayarları > API Anahtarı Güncelleme üzerinden girin.")
  }

  messages_payload <- lapply(chat_history, function(msg) {
    role_val <- NULL
    if (!is.null(msg$type)) {
      role_val <- if (identical(msg$type, "user")) "user"
        else if (identical(msg$type, "system")) "system"
        else "assistant"
    } else if (!is.null(msg$role)) {
      role_val <- tolower(as.character(msg$role))
      if (!(role_val %in% c("user", "assistant", "system"))) {
        role_val <- "user"
      }
    } else {
      role_val <- "user"
    }

    content_val <- NULL
    if (!is.null(msg$content)) {
      content_val <- msg$content
    } else if (!is.null(msg$message)) {
      content_val <- msg$message
    } else {
      content_val <- as.character(msg)
    }

    list(role = role_val, content = content_val)
  })

  # Sıcaklık ve maksimum token ayarları
  temp_value <- if (!is.null(current_settings$temperature)) current_settings$temperature else 0.4
  # Varsayilan token limiti: 4096 (uzun kod bloklarinin kesilmesini onler)
  max_tokens_val <- current_settings$max_output_tokens %||% 4096

  body <- list(
    model = selected_model,
    messages = messages_payload,
    stream = FALSE,
    temperature = temp_value,
    max_tokens = max_tokens_val
  )

  # Yerel uçlarda boş Authorization başlığını GÖNDERME
  hds <- list(`Content-Type` = "application/json")
  if (nzchar(api_key)) hds$Authorization <- paste("Bearer", api_key)

  response <- tryCatch({
    httr::POST(
      url = api_url,
      body = body,
      encode = "json",
      do.call(httr::add_headers, hds),
      httr::timeout(300)
    )
  }, error = function(e) {
    stop(sprintf("API_CONNECTION_ERROR: %s", conditionMessage(e)))
  })

  if (httr::status_code(response) >= 400) {
    error_content <- try(httr::content(response, "text", encoding = "UTF-8"), silent = TRUE)
    stop(sprintf("API_HTTP_ERROR_%d: %s",
                 httr::status_code(response),
                 if(!inherits(error_content, "try-error")) substr(error_content, 1, 200) else ""))
  }

  response_content <- httr::content(response, "parsed")

  # İçerik ve kaynakları çıkar
  ai_content <- NULL
  sources_list <- NULL

  if (is.list(response_content) &&
      !is.null(response_content$choices) &&
      length(response_content$choices) > 0) {
    first_choice <- response_content$choices[[1]]
    if (is.list(first_choice) &&
        !is.null(first_choice$message) &&
        !is.null(first_choice$message$content)) {
      content_obj <- first_choice$message$content
      if (is.character(content_obj) && length(content_obj) > 0) {
        ai_content <- trimws(content_obj[1])
      } else {
        ai_content <- ""
      }

      # Kaynakları çıkar (varsa)
      if (!is.null(first_choice$message$sources)) {
        sources_list <- first_choice$message$sources
      }
    }
  }

  # İçerik çıkarımından hemen sonra debug log
  mergen_debug_cat("[LOCAL_LLM] parsed content length=",
      if (is.null(ai_content)) NA_integer_ else length(ai_content),
      " class=", paste(class(ai_content), collapse = ","),
      " nzchar1=",
      if (is.character(ai_content) && length(ai_content) > 0) nzchar(ai_content[1]) else NA,
      ' preview="', substr(as.character(ai_content)[1], 1, 120), '"\n',
      sep = "")

  # Farklı seviyelerdeki kaynakları kontrol et
  if (is.null(sources_list) && !is.null(response_content$sources)) {
    sources_list <- response_content$sources
  }
  if (is.null(sources_list) && !is.null(response_content$message$sources)) {
    sources_list <- response_content$message$sources
  }

  # Kaynaklar bulunduysa dosya adlarını çıkar ve Kaynakça oluştur
  if (!is.null(sources_list) && length(sources_list) > 0) {
    mergen_debug_cat("\n========== SOURCES PROCESSING ==========\n")

    extracted_sources <- list()
    seen_filenames <- character(0)

    for (i in seq_along(sources_list)) {
      src <- sources_list[[i]]

      if (is.list(src) && !is.null(src[["metadata"]])) {
        metadata_array <- src[["metadata"]]

        for (j in seq_along(metadata_array)) {
          doc <- metadata_array[[j]]

          # Dosya adını "name" veya "source" alanından al
          filename <- doc[["name"]] %||% doc[["source"]]

          if (!is.null(filename) && nzchar(filename) && !(filename %in% seen_filenames)) {
            seen_filenames <- c(seen_filenames, filename)

            # Süreç numarasını çıkar (varsa)
            process_num <- ""
            file_ext <- tolower(tools::file_ext(filename))
            original_filename <- filename

            # Dosya adını formatla
            formatted_filename <- filename

            mergen_debug_cat("[DOCUMENT ", j, "] Final: ", process_num, ": ", formatted_filename, "\n\n", sep = "")

            extracted_sources[[length(extracted_sources) + 1]] <- list(
              process = process_num,
              filename = formatted_filename,
              original_filename = filename
            )
          }
        }
      }
    }

    mergen_debug_cat("[SUMMARY] Total unique sources:", length(extracted_sources), "\n")

    # Tiklanabilir baglantilarla Kaynakca bolumu ekle
    if (length(extracted_sources) > 0) {
      # LLM'in kendi urettigi duz metin Kaynakca bolumunu kaldir (tekrari onle)
      ai_content <- sub("\\n*Kaynakça:\\s*\\n(\\s*\\[?\\d+[)\\].]\\s*[^\\n]+\\n?)*\\s*$", "", ai_content, perl = TRUE)
      ai_content <- trimws(ai_content)

      sources_text <- "\n\nKaynakça:\n"

      for (i in seq_along(extracted_sources)) {
        src_info <- extracted_sources[[i]]

        # Bu kaynak için benzersiz kimlik
        source_id <- paste0("source_", i, "_", gsub("[^a-z0-9]", "", tolower(src_info$filename)))

        # Açma işlemi için her zaman ORİJİNAL dosya adını kullan
        original_filename <- src_info$original_filename
        file_ext <- tolower(tools::file_ext(original_filename))

        # Uzantıya göre ikon seç (Word/PDF, genel yedek)
        icon_html <- if (file_ext %in% c("doc","docx")) {
          "<i class='fa-regular fa-file-word' style='margin-right:6px;color:#2b579a'></i>"
        } else if (identical(file_ext, "pdf")) {
          "<i class='fa-regular fa-file-pdf' style='margin-right:6px;color:#c00'></i>"
        } else {
          "<i class='fa-regular fa-file' style='margin-right:6px;'></i>"
        }

        # Görüntüde sadece son parçayı göster; tıklama için TAM dosya adını taşı
        parts_raw <- strsplit(original_filename, "&&", fixed = TRUE)[[1]]

        # Etiket ön eki (süreç bilgisi varsa)
        label_prefix <- if (nchar(src_info$process) > 0) paste0(src_info$process, ": ") else ""

        if (length(parts_raw) > 1) {
          parts <- trimws(parts_raw)
          left_parts <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)
          right_part <- parts[length(parts)]

          left_html <- if (length(left_parts)) {
            paste(
              vapply(left_parts, function(p) {
                paste0("<span class='source-chunk'>", htmltools::htmlEscape(p), "</span>")
              }, character(1)),
              collapse = " - "
            )
          } else ""

          clickable_html <- paste0(
            "<span class='source-link' data-source-id='", source_id,
            "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
            "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
            htmltools::htmlEscape(trimws(right_part)),
            "</span>"
          )

          # Her Kaynakca girisini veri-entry ozelligi ile sarar; JS atif eslestirmesi icin gerekli
          line <- paste0(
            "<span class='kaynakca-entry' data-entry='", i, "'>",
            i, ") ", label_prefix, icon_html,
            if (nzchar(left_html)) paste0(left_html, " - ") else "",
            clickable_html,
            "</span>\n"
          )

        } else {
          clickable_html <- paste0(
            "<span class='source-link' data-source-id='", source_id,
            "' data-filename='", htmltools::htmlEscape(original_filename, attribute = TRUE),
            "' style='color:#007bff; cursor:pointer; text-decoration:underline;'>",
            htmltools::htmlEscape(src_info$filename),
            "</span>"
          )
          # Tek parcali Kaynakca girisi de ayni sekilde sarlaniyor
          line <- paste0(
            "<span class='kaynakca-entry' data-entry='", i, "'>",
            i, ") ", label_prefix, icon_html, clickable_html,
            "</span>\n"
          )
        }

        sources_text <- paste0(sources_text, line)
      }

      ai_content <- paste0(ai_content, sources_text)
      mergen_debug_cat("[SUCCESS] Kaynakça appended with", length(extracted_sources), "unique sources\n")
    }

    mergen_debug_cat("========================================\n\n")
  }

  if (!(is.character(ai_content) && length(ai_content) > 0 && nzchar(ai_content[1]))) {
    stop("EMPTY_RESPONSE: AI yanıtı boş veya geçersiz (content yok).")
  }

  ai_content <- strip_planner_text(ai_content)

  # --- Sağlamlaştırma: her zaman scalar string döndür ---
  if (!is.character(ai_content) || length(ai_content) == 0 || is.na(ai_content[1])) {
    ai_content <- ""
  } else {
    ai_content <- as.character(ai_content)[1]
  }
  if (!nzchar(ai_content)) ai_content <- ""

  # Dönüş özeti
  mergen_debug_cat("[LOCAL_LLM] returning shape=list content_nchar=", nchar(ai_content),
      " duration_s=", as.numeric(difftime(Sys.time(), llm_start_time, units = "secs")),
      "\n", sep = "")

  return(list(
    content  = ai_content,
    duration = as.numeric(difftime(Sys.time(), llm_start_time, units = "secs"))
  ))
}

# --- YENİDEN DENEME MEKANİZMASI ---
# API çağrılarında hata durumunda üstel geri çekilmeyle yeniden dener
call_llm_with_retry <- function(chat_history, settings, max_retries = 3) {
  for (i in 1:max_retries) {
    tryCatch({
      res <- call_local_llm(chat_history, settings)
      # Geriye uyumluluk: eski çağrılar character bekliyorsa list'e sar
      if (is.character(res)) {
        res <- list(content = as.character(res)[1] %||% "", duration = NA_real_)
      }
      return(res)
    }, error = function(e) {
      if (i == max_retries) {
        stop(e)
      }
      Sys.sleep(2^i)
    })
  }
}