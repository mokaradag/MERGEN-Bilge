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
    max_tokens = max_tokens_val
  )

  # Düşünmeli modeller bazı uçlarda temperature alanını reddedebiliyor
  if (!grepl("(?i)(think|reason|qwen3\\.5)", selected_model, perl = TRUE)) {
    body$temperature <- temp_value
  }

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
  ayristirilmis_yanit <- extract_llm_content_and_sources(response_content)
  ai_content <- ayristirilmis_yanit$content
  sources_list <- ayristirilmis_yanit$sources

  # İçerik çıkarımından hemen sonra debug log
  mergen_debug_cat("[LOCAL_LLM] parsed content length=",
      if (is.null(ai_content)) NA_integer_ else length(ai_content),
      " class=", paste(class(ai_content), collapse = ","),
      " nzchar1=",
      if (is.character(ai_content) && length(ai_content) > 0) nzchar(ai_content[1]) else NA,
      ' preview="', substr(as.character(ai_content)[1], 1, 120), '"\n',
      sep = "")

  ai_content <- append_clickable_sources(ai_content, sources_list)

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