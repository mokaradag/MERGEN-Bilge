# R/helpers_ai_expert.R
# Dosya Yolu: R/helpers_ai_expert.R
# Açıklama: AI Uzman (AI Expert) modülü için yardımcı fonksiyonlar.
#            Kullanıcının geçmiş etkileşimlerini analiz eder, kişiselleştirilmiş
#            karşılama metni oluşturur ve LLM API çağrılarını yönetir.
#            Kullanıcı adı DB'den alınarak doğal bir etkileşim sağlanır.

# --- AI Uzman için LLM çağrı fonksiyonu ---
# Bu fonksiyon, AI Uzman konuşma metni oluşturmak için LLM API'sini çağırır.
# Worker-safe: Tüm reaktif değerler önceden yakalanmış olmalıdır.
#
# @param system_prompt Sistem istemi (karakter + rehber bilgisi)
# @param user_context Kullanıcı bağlam bilgisi (geçmiş sohbetler, son giriş vb.)
# @param model_name Kullanılacak model adı (.Renviron'dan)
# @param api_key API anahtarı
# @param endpoint API uç noktası URL'i
# @param max_tokens Maksimum token sayısı (varsayılan: 500, zengin konuşmalar için)
# @return Karakter dizisi (AI yanıtı) veya NULL (hata durumunda)
call_ai_expert_llm <- function(system_prompt, user_context, model_name,
                                api_key = NULL, endpoint = NULL,
                                max_tokens = 500) {

  # Uç nokta ve model adı kontrolü
  if (is.null(endpoint) || !nzchar(endpoint)) {
    endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
  }
  if (!nzchar(endpoint)) {
    cat("[AI_EXPERT] API uç noktası yapılandırılmamış, konuşma oluşturulamadı.\n")
    return(NULL)
  }

  if (is.null(model_name) || !nzchar(model_name)) {
    model_name <- Sys.getenv("AI_EXPERT_MODEL", "")
    if (!nzchar(model_name)) {
      cat("[AI_EXPERT] Model adı belirtilmemiş.\n")
      return(NULL)
    }
  }

  # API anahtarı çözümleme
  if (is.null(api_key) || !nzchar(api_key)) {
    api_key <- Sys.getenv("LOCAL_LLM_API_KEY", "")
  }

  # Mesaj yapısı
  messages_payload <- list(
    list(role = "system", content = system_prompt),
    list(role = "user", content = user_context)
  )

  body <- list(
    model    = model_name,
    messages = messages_payload,
    stream   = FALSE,
    temperature = 0.7,
    max_tokens  = max_tokens
  )

  # Başlıklar
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
    cat(sprintf("[AI_EXPERT] API bağlantı hatası: %s\n", conditionMessage(e)))
    return(NULL)
  })

  if (is.null(response)) return(NULL)

  if (httr::status_code(response) >= 400) {
    cat(sprintf("[AI_EXPERT] API HTTP hatası: %d\n", httr::status_code(response)))
    return(NULL)
  }

  parsed <- tryCatch(httr::content(response, "parsed"), error = function(e) NULL)
  if (is.null(parsed)) return(NULL)

  # Yanıtı çıkar
  ai_text <- NULL
  if (is.list(parsed$choices) && length(parsed$choices) > 0) {
    choice <- parsed$choices[[1]]
    if (!is.null(choice$message) && !is.null(choice$message$content)) {
      ai_text <- trimws(choice$message$content)
    }
  }

  if (is.null(ai_text) || !nzchar(ai_text)) {
    cat("[AI_EXPERT] API yanıtı boş.\n")
    return(NULL)
  }

  cat(sprintf("[AI_EXPERT] Konuşma metni oluşturuldu (%d karakter)\n", nchar(ai_text)))
  return(ai_text)
}


# --- Kullanıcının tam adını DB'den al ---
# Worker-safe: Kendi bağlantısını açar.
# MB_Users tablosundaki KaynakAdi sütunundan kullanıcı adını alır.
#
# @param user_id Kullanıcı ID
# @return Karakter dizisi (tam ad) veya boş karakter
fetch_user_full_name <- function(user_id) {
  conn_info <- tryCatch(get_connection(), error = function(e) NULL)
  if (is.null(conn_info)) return("")
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT KaynakAdi FROM MB_Users WHERE UserID = ?"
  result <- tryCatch(
    DBI::dbGetQuery(conn, query, params = list(user_id)),
    error = function(e) {
      cat(sprintf("[AI_EXPERT] KaynakAdi sorgu hatası: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) > 0 && !is.na(result$KaynakAdi[1]) && nzchar(result$KaynakAdi[1])) {
    return(as.character(result$KaynakAdi[1]))
  }

  return("")
}


# --- Kullanıcı bağlam bilgisi oluşturma ---
# Veritabanından kullanıcının geçmiş verilerini alır ve metin olarak döndürür.
# Worker-safe: DB bağlantısı fonksiyon içinde açılır.
#
# @param user_id Kullanıcı ID
# @param user_name Kullanıcının ilk adı
# @param last_login_date Son giriş tarihi (önceden yakalanmış)
# @param include_recent_prompts Son mesajları dahil et (varsayılan: TRUE)
# @param max_prompts Alınacak maksimum mesaj sayısı (varsayılan: 5)
# @return Bağlam bilgisi içeren karakter dizisi
build_ai_expert_user_context <- function(user_id, user_name = "",
                                          last_login_date = NULL,
                                          include_recent_prompts = TRUE,
                                          max_prompts = 5) {

  context_parts <- list()

  # Kullanıcı adı bilgisi
  if (nzchar(user_name)) {
    context_parts <- c(context_parts, sprintf("Kullanıcının adı: %s", user_name))
  }

  # Son giriş zamanı bilgisi
  if (!is.null(last_login_date)) {
    context_parts <- c(context_parts, sprintf(
      "Kullanıcının son giriş zamanı: %s", as.character(last_login_date)
    ))

    # Son giriş ile şimdi arasındaki farkı hesapla
    time_diff <- difftime(Sys.time(), as.POSIXct(last_login_date), units = "hours")
    if (time_diff < 1) {
      context_parts <- c(context_parts, "Kullanıcı çok kısa süre önce giriş yapmış (1 saatten az).")
    } else if (time_diff < 24) {
      context_parts <- c(context_parts, sprintf(
        "Kullanıcı yaklaşık %.0f saat önce giriş yapmış.", as.numeric(time_diff)
      ))
    } else {
      days_ago <- as.numeric(difftime(Sys.time(), as.POSIXct(last_login_date), units = "days"))
      context_parts <- c(context_parts, sprintf(
        "Kullanıcı yaklaşık %.0f gün önce giriş yapmış.", days_ago
      ))
      if (days_ago > 7) {
        context_parts <- c(context_parts,
          "Kullanıcı uzun süredir giriş yapmamış. Bu durumu sıcak ama profesyonel şekilde ele al.")
      }
    }
  } else {
    context_parts <- c(context_parts,
      "Kullanıcının önceki giriş kaydı bulunamadı. Bu ilk girişi olabilir.")
  }

  # Son kullanıcı mesajları
  if (isTRUE(include_recent_prompts)) {
    recent_prompts <- tryCatch({
      fetch_recent_user_prompts(user_id, max_prompts)
    }, error = function(e) {
      cat(sprintf("[AI_EXPERT] Son mesajlar alınamadı: %s\n", conditionMessage(e)))
      NULL
    })

    if (!is.null(recent_prompts) && length(recent_prompts) > 0) {
      prompts_text <- paste(
        sprintf("- \"%s\"", substr(recent_prompts, 1, 200)),
        collapse = "\n"
      )
      context_parts <- c(context_parts, sprintf(
        "Kullanıcının son konuşma konuları:\n%s", prompts_text
      ))
    } else {
      context_parts <- c(context_parts,
        "Kullanıcının geçmiş mesajı bulunmuyor. Bu muhtemelen ilk kullanımı.")
    }
  }

  # Mevcut zaman bilgisi
  context_parts <- c(context_parts, sprintf(
    "Şimdi: %s", format(Sys.time(), "%d %B %Y %H:%M", tz = "Europe/Istanbul")
  ))

  paste(context_parts, collapse = "\n\n")
}


# --- Son kullanıcı mesajlarını DB'den al ---
# Worker-safe: Kendi bağlantısını açar.
#
# @param user_id Kullanıcı ID
# @param max_prompts Maksimum mesaj sayısı
# @return Karakter vektörü (mesaj içerikler) veya NULL
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
      cat(sprintf("[AI_EXPERT] DB sorgu hatası: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) > 0) {
    return(as.character(result$MessageContent))
  }

  return(NULL)
}


# --- Son giriş tarihini DB'den al ---
# Worker-safe: Kendi bağlantısını açar.
#
# @param user_id Kullanıcı ID
# @return POSIXct tarih veya NULL
fetch_user_last_login <- function(user_id) {
  conn_info <- get_connection()
  conn <- conn_info$conn
  on.exit(release_connection(conn_info))

  query <- "SELECT LastLoginDate FROM MB_Users WHERE UserID = ?"
  result <- tryCatch(
    DBI::dbGetQuery(conn, query, params = list(user_id)),
    error = function(e) {
      cat(sprintf("[AI_EXPERT] LastLoginDate sorgu hatası: %s\n", conditionMessage(e)))
      data.frame()
    }
  )

  if (nrow(result) > 0 && !is.na(result$LastLoginDate[1])) {
    return(as.POSIXct(result$LastLoginDate[1]))
  }

  return(NULL)
}


# --- AI Uzman sistem istemi oluştur ---
# Seçili karakter ve rehber belgesine dayalı, zengin ve doğal sistem istemi oluşturur.
# Kullanıcı adı ile kişiselleştirilmiş, profesyonel ama sıcak bir ton hedeflenir.
#
# @param character_data Karakter bilgileri (config_characters.R'den)
# @param scenario Senaryo türü ("greeting", "page_guidance", "idle_chat")
# @param page_name Sayfa adı (sayfa rehberliği için)
# @param user_name Kullanıcının ilk adı (kişiselleştirme için)
# @param is_revisit Tekrar ziyaret mi (sayfa rehberliği için)
# @return Sistem istemi karakter dizisi
build_ai_expert_system_prompt <- function(character_data, scenario = "greeting",
                                           page_name = NULL, user_name = NULL,
                                           is_revisit = FALSE) {

  # Rehber belgesini oku
  guide_text <- ""
  guide_path <- file.path(getwd(), "ai_rehber.md")
  if (file.exists(guide_path)) {
    guide_text <- tryCatch(
      paste(readLines(guide_path, encoding = "UTF-8", warn = FALSE), collapse = "\n"),
      error = function(e) ""
    )
  }

  # Karakter kişilik bilgisi
  char_name <- character_data$display_name %||% "MERGEN"
  char_style <- character_data$style_tr %||% ""
  char_system <- character_data$system_prompt_en %||% ""

  # Kullanıcı adı talimatı
  name_instruction <- ""
  if (!is.null(user_name) && nzchar(user_name)) {
    name_instruction <- sprintf(
      "Kullanıcının adı %s. Konuşmanda zaman zaman adını kullanabilirsin ama her cümlede kullanma, doğal ol. ",
      user_name
    )
  }

  # Senaryo bazlı yönlendirme
  scenario_instruction <- switch(scenario,
    "greeting" = paste0(
      "Kullanıcıyı sıcak ve samimi bir şekilde karşıla. ",
      name_instruction,
      "Karakterinin kişiliğini doğal şekilde yansıt. ",
      "Kullanıcının geçmiş bilgilerine dayanarak konuşmanı kişiselleştir:\n",
      "- İlk kez gelen kullanıcı ise: Kendini tanıt, uygulamanın neler yapabileceğinden ",
      "bahset, kullanıcıyı keşfe davet et. Samimi ve merak uyandırıcı ol.\n",
      "- Geri dönen kullanıcı ise: Son konuşma konularından doğal bir geçişle bahset. ",
      "'Geçen seferki konuşmamızda...' gibi bir giriş yapabilirsin. ",
      "Kaldığı yerden devam etmek isteyip istemediğini sor.\n",
      "- Uzun süredir giriş yapmamış kullanıcı ise: Tekrar görmenin sevindirici olduğunu ",
      "belirt, nazikçe yokluğuna değin, nasıl yardımcı olabileceğini sor.\n\n",
      "KONUŞMA TARZI: Doğal, akıcı, insan gibi konuş. Kısa cümleler kullanma, ",
      "birkaç cümlelik akıcı paragraflar oluştur. Monolog gibi değil, ",
      "karşındaki kişiyle sohbet ediyormuş gibi konuş. 4-6 cümle ideal. ",
      "Profesyonel ama samimi ol. Mekanik veya robotik durma."
    ),
    "page_guidance" = {
      revisit_note <- if (is_revisit) {
        "Kullanıcı bu sayfaya daha önce de geldi. Farklı bir bakış açısıyla konuş, tekrarlama. İpuçları, ileri düzey kullanım veya gözden kaçırılabilecek özelliklerden bahset."
      } else {
        "Kullanıcı bu sayfayı ilk kez ziyaret ediyor. Sayfanın amacını ve temel özelliklerini açıkla."
      }
      paste0(
        sprintf("Kullanıcı '%s' sayfasına geçiş yaptı. ", page_name %||% "bilinmeyen"),
        name_instruction,
        revisit_note, " ",
        "Bu sayfa hakkında faydalı, bilgilendirici ve ilgi çekici bir rehberlik yap. ",
        "Sadece kuru bir sayfa açıklaması yapma; kullanıcıya bu sayfada neler keşfedebileceğini, ",
        "hangi işlemleri yapabileceğini ve pratik ipuçlarını doğal bir sohbet tarzında aktar. ",
        "3-5 cümle ile akıcı bir şekilde konuş. Profesyonel ama samimi ol."
      )
    },
    "idle_chat" = paste0(
      "Kullanıcı bir süredir sessiz ve etkileşimde bulunmadı. ",
      name_instruction,
      "YASAKLAR: Asla selam verme, asla 'merhaba' deme, asla 'hoş geldin' deme, ",
      "asla 'uzun süredir görüşmedik' deme. Bu zaten devam eden bir sohbet, ",
      "her konuşmayı sıfırdan başlatma. Daha önce söylediklerini tekrarlama.\n\n",
      "Doğal bir şekilde konuşmayı sürdür. Her seferinde FARKLI bir konuya değin. ",
      "Sadece bulunduğu sayfadan bahsetme, çeşitli konulara doğal geçişler yap:\n",
      "- Kullanıcının son konuşma konularına dayalı bir yorum veya öneri yap\n",
      "- Uygulamanın az bilinen veya güçlü bir özelliğinden ilginç bir şekilde bahset\n",
      "- İş hayatına veya verimliliğe dair yararlı bir ipucu paylaş\n",
      "- Yapay zeka veya teknoloji dünyasından ilginç bir bilgi paylaş\n",
      "- Kullanıcıya doğal bir soru sor (zorlayıcı olmadan, merak uyandırıcı)\n",
      "- Kendi karakterine özgü bir düşünce veya gözlem paylaş\n\n",
      "KONUŞMA TARZI: Doğal ve insani ol. Sanki arkadaşına bir şey söylüyormuşsun gibi ",
      "akıcı başla. Örneğin: 'Bu arada aklıma geldi...', 'Bir şey paylaşmak istiyorum...', ",
      "'Biliyor musun, az önce düşündüm de...', 'Merak ettim...' gibi doğal geçişler kullan. ",
      "3-5 cümle ile akıcı şekilde konuş. Her konuşma benzersiz ve taze olsun."
    ),
    # Varsayılan
    paste0(name_instruction, "Profesyonel ve samimi bir mesaj oluştur. 3-5 cümle ile konuş.")
  )

  # Sistem istemini birleştir
  prompt <- paste0(
    "Sen ", char_name, " adında bir AI asistanısın. ",
    "MERGEN Bilge uygulamasının yapay zeka uzmanı olarak kullanıcıyla sesli ve yazılı etkileşim kuruyorsun. ",
    "Türkçe konuşuyorsun. Asla İngilizce konuşma. ",
    if (nzchar(char_style)) paste0("\nKarakter Tarzı: ", char_style, "\n") else "",
    "\n\n",
    "ÖNEMLİ KURALLAR:\n",
    "- Her zaman Türkçe konuş, asla İngilizce kelime veya cümle kullanma\n",
    "- Doğal, akıcı ve insani bir şekilde konuş - kısa kesik cümleler değil, akıcı paragraflar\n",
    "- Profesyonel, saygılı, sıcak ve bilge ol\n",
    "- Mekanik veya robotik durma, bir insan gibi konuş\n",
    "- Emoji kullanma\n",
    "- Markdown formatlaması kullanma (yıldız, diyez, madde işareti vb.)\n",
    "- Sadece düz metin yaz, liste yapma\n",
    "- Kurumsal bir ortamda çalışıyorsun, profesyonel ama sıcak ol\n",
    "- Bilge, rehber niteliğinde ama kibirli veya üstten konuşma\n",
    "- Konuşman sesli olarak okunacak, bu yüzden kulağa hoş gelen, doğal bir Türkçe kullan\n\n",
    "GÖREV:\n", scenario_instruction, "\n\n",
    "UYGULAMA REHBERİ (Referans olarak kullan):\n",
    if (nzchar(guide_text)) substr(guide_text, 1, 10000) else "(Rehber belgesi bulunamadı)"
  )

  return(prompt)
}


# --- TTS için metin hazırlama (AI Uzman konuşması için) ---
# server_tts_handlers.R'deki prepare_tts_text ile benzer ama daha basit.
#
# @param text Ham metin
# @return TTS için temizlenmiş metin
prepare_ai_expert_tts_text <- function(text) {
  if (is.null(text) || !nzchar(text)) return("")

  # Markdown işaretlerini kaldır
  clean <- gsub("\\*+", "", text)
  clean <- gsub("#+\\s*", "", clean)
  clean <- gsub("`+", "", clean)
  clean <- gsub("\\[([^]]+)\\]\\([^)]+\\)", "\\1", clean)

  # Fazla boşluğu temizle
  clean <- gsub("\\s+", " ", clean)
  clean <- trimws(clean)

  return(clean)
}