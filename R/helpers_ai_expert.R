# R/helpers_ai_expert.R
# Dosya Yolu: R/helpers_ai_expert.R
# Aciklama: AI Uzman (AI Expert) modulu icin yardimci fonksiyonlar.
#            Kullanicinin gecmis etkilesimlerini analiz eder, uygun karsilama
#            metni olusturur ve LLM API cagrilarini yonetir.

# --- AI Uzman icin LLM cagri fonksiyonu ---
# Bu fonksiyon, AI Uzman konusma metni olusturmak icin LLM API'sini cagirir.
# Worker-safe: Tum reaktif degerler onceden yakalanmis olmalidir.
#
# @param system_prompt Sistem istemi (karakter + rehber bilgisi)
# @param user_context Kullanici baglam bilgisi (gecmis sohbetler, son giris vb.)
# @param model_name Kullanilacak model adi (.Renviron'dan)
# @param api_key API anahtari
# @param endpoint API uc noktasi URL'i
# @param max_tokens Maksimum token sayisi (varsayilan: 300, kisa konusmalar icin)
# @return Karakter dizisi (AI yaniti) veya NULL (hata durumunda)
call_ai_expert_llm <- function(system_prompt, user_context, model_name,
                                api_key = NULL, endpoint = NULL,
                                max_tokens = 300) {

  # Uc nokta ve model adi kontrolu
  if (is.null(endpoint) || !nzchar(endpoint)) {
    endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
  }
  if (!nzchar(endpoint)) {
    cat("[AI_EXPERT] API uc noktasi yapilandirilmamis, konusma olusturulamadi.\n")
    return(NULL)
  }

  if (is.null(model_name) || !nzchar(model_name)) {
    model_name <- Sys.getenv("AI_EXPERT_MODEL", "")
    if (!nzchar(model_name)) {
      cat("[AI_EXPERT] Model adi belirtilmemis.\n")
      return(NULL)
    }
  }

  # API anahtari cozumleme
  if (is.null(api_key) || !nzchar(api_key)) {
    api_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")
  }

  # Mesaj yapisi
  messages_payload <- list(
    list(role = "system", content = system_prompt),
    list(role = "user", content = user_context)
  )

  body <- list(
    model    = model_name,
    messages = messages_payload,
    stream   = FALSE,
    temperature = 0.6,
    max_tokens  = max_tokens
  )

  # Basliklar

  hds <- list(`Content-Type` = "application/json")
  if (nzchar(api_key)) hds$Authorization <- paste("Bearer", api_key)

  response <- tryCatch({
    httr::POST(
      url     = endpoint,
      body    = body,
      encode  = "json",
      do.call(httr::add_headers, hds),
      httr::timeout(60)
    )
  }, error = function(e) {
    cat(sprintf("[AI_EXPERT] API baglanti hatasi: %s\n", conditionMessage(e)))
    return(NULL)
  })

  if (is.null(response)) return(NULL)

  if (httr::status_code(response) >= 400) {
    cat(sprintf("[AI_EXPERT] API HTTP hatasi: %d\n", httr::status_code(response)))
    return(NULL)
  }

  parsed <- tryCatch(httr::content(response, "parsed"), error = function(e) NULL)
  if (is.null(parsed)) return(NULL)

  # Yaniti cikar
  ai_text <- NULL
  if (is.list(parsed$choices) && length(parsed$choices) > 0) {
    choice <- parsed$choices[[1]]
    if (!is.null(choice$message) && !is.null(choice$message$content)) {
      ai_text <- trimws(choice$message$content)
    }
  }

  if (is.null(ai_text) || !nzchar(ai_text)) {
    cat("[AI_EXPERT] API yaniti bos.\n")
    return(NULL)
  }

  cat(sprintf("[AI_EXPERT] Konusma metni olusturuldu (%d karakter)\n", nchar(ai_text)))
  return(ai_text)
}


# --- Kullanici baglam bilgisi olusturma ---
# Veritabanindan kullanicinin gecmis verilerini alir ve metin olarak dondurur.
# Worker-safe: DB baglantisi fonksiyon icinde acilir.
#
# @param user_id Kullanici ID
# @param last_login_date Son giris tarihi (onceden yakalanmis)
# @param include_recent_prompts Son mesajlari dahil et (varsayilan: TRUE)
# @param max_prompts Alinacak maksimum mesaj sayisi (varsayilan: 5)
# @return Baglam bilgisi iceren karakter dizisi
build_ai_expert_user_context <- function(user_id, last_login_date = NULL,
                                          include_recent_prompts = TRUE,
                                          max_prompts = 5) {

  context_parts <- list()

  # Son giris zamani bilgisi

  if (!is.null(last_login_date)) {
    context_parts <- c(context_parts, sprintf(
      "Kullanicinin son giris zamani: %s", as.character(last_login_date)
    ))

    # Son giris ile simdi arasindaki farki hesapla
    time_diff <- difftime(Sys.time(), as.POSIXct(last_login_date), units = "hours")
    if (time_diff < 1) {
      context_parts <- c(context_parts, "Kullanici cok kisa sure once giris yapmis (1 saatten az).")
    } else if (time_diff < 24) {
      context_parts <- c(context_parts, sprintf("Kullanici yaklasik %.0f saat once giris yapmis.", as.numeric(time_diff)))
    } else {
      days_ago <- as.numeric(difftime(Sys.time(), as.POSIXct(last_login_date), units = "days"))
      context_parts <- c(context_parts, sprintf("Kullanici yaklasik %.0f gun once giris yapmis.", days_ago))
    }
  }

  # Son kullanici mesajlari
  if (isTRUE(include_recent_prompts)) {
    recent_prompts <- tryCatch({
      fetch_recent_user_prompts(user_id, max_prompts)
    }, error = function(e) {
      cat(sprintf("[AI_EXPERT] Son mesajlar alinamadi: %s\n", conditionMessage(e)))
      NULL
    })

    if (!is.null(recent_prompts) && length(recent_prompts) > 0) {
      prompts_text <- paste(
        sprintf("- \"%s\"", substr(recent_prompts, 1, 150)),
        collapse = "\n"
      )
      context_parts <- c(context_parts, sprintf(
        "Kullanicinin son mesajlari:\n%s", prompts_text
      ))
    } else {
      context_parts <- c(context_parts, "Kullanicinin gecmis mesaji bulunmuyor (ilk kullanim olabilir).")
    }
  }

  # Mevcut zaman bilgisi
  context_parts <- c(context_parts, sprintf(
    "Simdi: %s", format(Sys.time(), "%d %B %Y %H:%M", tz = "Europe/Istanbul")
  ))

  paste(context_parts, collapse = "\n\n")
}


# --- Son kullanici mesajlarini DB'den al ---
# Worker-safe: Kendi baglantisini acar.
#
# @param user_id Kullanici ID
# @param max_prompts Maksimum mesaj sayisi
# @return Karakter vektoru (mesaj icerikler) veya NULL
fetch_recent_user_prompts <- function(user_id, max_prompts = 5) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- sprintf("
    SELECT TOP %d m.MessageContent
    FROM MB_Messages m
    JOIN MB_Chats c ON m.ChatID = c.ChatID
    WHERE c.UserID = ? AND m.MessageType = 'user' AND c.IsDeleted = 0
    ORDER BY m.MessageTimestamp DESC
  ", as.integer(max_prompts))

  result <- tryCatch(
    DBI::dbGetQuery(conn, query, params = list(user_id)),
    error = function(e) {
      cat(sprintf("[AI_EXPERT] DB sorgu hatasi: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) > 0) {
    return(as.character(result$MessageContent))
  }

  return(NULL)
}


# --- Son giris tarihini DB'den al ---
# Worker-safe: Kendi baglantisini acar.
#
# @param user_id Kullanici ID
# @return POSIXct tarih veya NULL
fetch_user_last_login <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT LastLoginDate FROM MB_Users WHERE UserID = ?"
  result <- tryCatch(
    DBI::dbGetQuery(conn, query, params = list(user_id)),
    error = function(e) {
      cat(sprintf("[AI_EXPERT] LastLoginDate sorgu hatasi: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) > 0 && !is.na(result$LastLoginDate[1])) {
    return(as.POSIXct(result$LastLoginDate[1]))
  }

  return(NULL)
}


# --- AI Uzman sistem istemi olustur ---
# Secili karakter ve rehber belgesine dayali sistem istemi olusturur.
#
# @param character_data Karakter bilgileri (config_characters.R'den)
# @param scenario Senaryo turu ("greeting", "page_guidance", "idle_chat")
# @param page_name Sayfa adi (sayfa rehberligi icin)
# @return Sistem istemi karakter dizisi
build_ai_expert_system_prompt <- function(character_data, scenario = "greeting",
                                           page_name = NULL) {

  # Rehber belgesini oku
  guide_text <- ""
  guide_path <- file.path(getwd(), "ai_rehber.md")
  if (file.exists(guide_path)) {
    guide_text <- tryCatch(
      paste(readLines(guide_path, encoding = "UTF-8", warn = FALSE), collapse = "\n"),
      error = function(e) ""
    )
  }

  # Karakter kisilik bilgisi
  char_name <- character_data$display_name %||% "MERGEN"
  char_style <- character_data$style_tr %||% ""
  char_system <- character_data$system_prompt_en %||% ""

  # Senaryo bazli yonlendirme

  scenario_instruction <- switch(scenario,
    "greeting" = paste0(
      "Kullaniciya kisa ve sicak bir karsilama yap. ",
      "Karakterinin kisiligini yansit. ",
      "Kullanicinin gecmis bilgilerine dayanarak uygun bir karsilama olustur. ",
      "Ilk kullanici ise kendini kisa tanit. Donen kullanici ise son konusmalarindan bahset. ",
      "Uzun konusma. 2-4 cumle yeterli. Profesyonel ve sicak ol."
    ),
    "page_guidance" = sprintf(
      "Kullanici '%s' sayfasina gecti. Bu sayfa hakkinda kisa ve faydali bir rehberlik yap. 1-2 cumle yeterli. Profesyonel ol.",
      page_name %||% "bilinmeyen"
    ),
    "idle_chat" = paste0(
      "Kullanici bir suredir bosta bekliyor. Kisa ve profesyonel bir sohbet baslat. ",
      "Ilgili bir ipucu ver veya nasil yardimci olabileceginissor. 1-2 cumle yeterli."
    ),
    # Varsayilan
    "Kisa ve profesyonel bir mesaj olustur."
  )

  # Sistem istemini birlestir
  prompt <- paste0(
    "Sen ", char_name, " adinda bir AI asistanisin. ",
    "Turkce konusuyorsun. Asla Ingilizce konusma. ",
    char_style, "\n\n",
    "ONEMLI KURALLAR:\n",
    "- Her zaman Turkce konusman gerekiyor\n",
    "- Kisa ve oz ol, uzun monologlardan kacin\n",
    "- Profesyonel, saygilii, sicak ve bilge ol\n",
    "- Mekanik veya robotik durma\n",
    "- Kullaniciya ismiyle hitap etme (ismini bilmiyorsun)\n",
    "- Emoji kullanma\n",
    "- Markdown formatlamasi kullanma\n",
    "- Sadece duz metin yaz\n\n",
    "GOREV:\n", scenario_instruction, "\n\n",
    "UYGULAMA REHBERI (Referans):\n",
    if (nzchar(guide_text)) substr(guide_text, 1, 8000) else "(Rehber belgesi bulunamadi)"
  )

  return(prompt)
}


# --- TTS icin metin hazirlama (AI Uzman konusmasi icin) ---
# server_tts_handlers.R'deki prepare_tts_text ile benzer ama daha basit.
#
# @param text Ham metin
# @return TTS icin temizlenmis metin
prepare_ai_expert_tts_text <- function(text) {
  if (is.null(text) || !nzchar(text)) return("")

  # Markdown isaretlerini kaldir
  clean <- gsub("\\*+", "", text)
  clean <- gsub("#+\\s*", "", clean)
  clean <- gsub("`+", "", clean)
  clean <- gsub("\\[([^]]+)\\]\\([^)]+\\)", "\\1", clean)

  # Fazla boslugu temizle
  clean <- gsub("\\s+", " ", clean)
  clean <- trimws(clean)

  return(clean)
}
