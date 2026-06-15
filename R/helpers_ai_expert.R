# R/helpers_ai_expert.R
# Dosya Yolu: R/helpers_ai_expert.R
# Açıklama: AI Uzman (AI Expert) modülü için yardımcı fonksiyonlar.
#            Kullanıcının geçmiş etkileşimlerini analiz eder, kişiselleştirilmiş
#            karşılama metni oluşturur ve LLM API çağrılarını yönetir.
#            Kullanıcı adı DB'den alınarak doğal bir etkileşim sağlanır.
#            NOT: Worker-safe veritabanı okuma yardımcıları (fetch_user_full_name,
#            fetch_user_work_context, fetch_recent_user_prompts,
#            fetch_user_last_login) R/helpers_ai_expert_user_data.R dosyasına
#            taşındı ve manifest'te bu dosyadan ÖNCE yüklenir.

# --- AI Uzman metni telaffuz/yazım düzeltici ---
# LLM modelleri bazen "Bilge Yolaç" yerine "Bilge Yola" üretir; bu hem altyazıyı
# (kullanıcı "Bilge Yola" görür) hem de TTS telaffuzunu (ses olarak "Yola"
# okur) bozar. Burada yapılan düzeltme her iki kanalı da düzeltir, çünkü
# AI Uzman'da aynı metin hem alt yazı hem TTS için kullanılır.
#
# Regex açıklaması: "Bilge Yola" eşleşmesi sadece arkasından bir harf gelmiyor
# ise (yani "Yolaç" / "Yolarda" / "Yolası" değilse) "Bilge Yolaç" ile değiştirilir.
# Türkçe harfler (ç, ğ, ı, İ, ö, ş, ü) negatif lookahead'e açık kimliklerle
# eklenmiştir; bu sayede "Yolaç" / "Yolarda" gibi zaten doğru ya da farklı
# kelimeler bozulmaz.
sanitize_ai_expert_pronunciation <- function(text) {
  if (is.null(text)) return(text)

  raw_text <- tryCatch(as.character(text)[1], error = function(e) NA_character_)
  if (is.na(raw_text) || !nzchar(raw_text)) return(text)

  # "Bilge Yola" arkasından harf gelmiyorsa "Bilge Yolaç"
  pattern <- "Bilge Yola(?![A-Za-zçÇğĞıİöÖşŞüÜ])"
  fixed <- tryCatch(
    gsub(pattern, "Bilge Yolaç", raw_text, perl = TRUE),
    error = function(e) raw_text
  )

  # Küçük harf varyantı (cümle ortasında geçebilir, ama sapmalar mümkün)
  pattern_lower <- "bilge yola(?![A-Za-zçÇğĞıİöÖşŞüÜ])"
  fixed <- tryCatch(
    gsub(pattern_lower, "bilge yolaç", fixed, perl = TRUE),
    error = function(e) fixed
  )

  fixed
}

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
                                max_tokens = 500, temperature = 0.7) {

  system_prompt <- safe_trimws(system_prompt)
  user_context  <- safe_trimws(user_context)
  model_name    <- safe_trimws(model_name)
  endpoint      <- safe_trimws(endpoint)
  api_key       <- safe_trimws(api_key)

  # Uç nokta ve model adı kontrolü
  if (is.null(endpoint) || !safe_nzchar(endpoint)) {
    endpoint <- safe_trimws(Sys.getenv("LOCAL_LLM_ENDPOINT", ""))
  }

  if (!safe_nzchar(endpoint)) {
    cat("[AI_EXPERT] API uç noktası yapılandırılmamış, konuşma oluşturulamadı.\n")
    return(NULL)
  }

  if (is.null(model_name) || !safe_nzchar(model_name)) {
    model_name <- safe_trimws(Sys.getenv("AI_EXPERT_MODEL", ""))
    if (!safe_nzchar(model_name)) {
      cat("[AI_EXPERT] Model adı belirtilmemiş.\n")
      return(NULL)
    }
  }

  # API anahtarı çözümleme
  if (is.null(api_key) || !safe_nzchar(api_key)) {
    api_key <- safe_trimws(Sys.getenv("LOCAL_LLM_API_KEY", ""))
  }

  # Üretim parametrelerini güvenli hale getir
  max_tokens <- suppressWarnings(as.integer(max_tokens))
  if (is.na(max_tokens) || max_tokens < 64) {
    max_tokens <- 500L
  }

  temperature <- suppressWarnings(as.numeric(temperature))
  if (!is.finite(temperature)) {
    temperature <- 0.7
  }
  temperature <- max(0, min(1.2, temperature))

  # Mesaj yapısı
  messages_payload <- list(
    list(role = "system", content = system_prompt),
    list(role = "user", content = user_context)
  )

  body <- list(
    model       = model_name,
    messages    = messages_payload,
    stream      = FALSE,
    temperature = temperature,
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

  response_text <- tryCatch(
    httr::content(response, as = "text", encoding = "UTF-8"),
    error = function(e) NULL
  )

  response_text <- normalize_utf8_text(response_text)
  if (!safe_nzchar(response_text)) return(NULL)

  parsed <- tryCatch(
    jsonlite::fromJSON(response_text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(parsed)) return(NULL)

  # Yanıtı çıkar
  ai_text <- NULL
  if (is.list(parsed$choices) && length(parsed$choices) > 0) {
    choice <- parsed$choices[[1]]
    if (!is.null(choice$message) && !is.null(choice$message$content)) {
      ai_text <- safe_trimws(choice$message$content)
    }
  }

  if (is.null(ai_text) || !safe_nzchar(ai_text)) {
    cat("[AI_EXPERT] API yanıtı boş.\n")
    return(NULL)
  }

  # Telaffuz/yazım düzeltmesi: "Bilge Yola" -> "Bilge Yolaç" gibi.
  # Bu adım hem altyazıda görünen metni hem TTS'ye gönderilen metni düzeltir.
  ai_text <- sanitize_ai_expert_pronunciation(ai_text)

  cat(sprintf("[AI_EXPERT] Konuşma metni oluşturuldu (%d karakter)\n", nchar(ai_text)))
  return(ai_text)
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
# @param current_session_messages Mevcut oturumdaki mesajlar (reaktif olmayan düz liste)
# @return Bağlam bilgisi içeren karakter dizisi
build_ai_expert_user_context <- function(user_id, user_name = "",
                                          last_login_date = NULL,
                                          include_recent_prompts = TRUE,
                                          max_prompts = 5,
                                          current_session_messages = NULL,
                                          user_work_context = NULL) {

  user_name <- safe_trimws(user_name)
  current_session_messages <- normalize_utf8_text(current_session_messages)
  context_parts <- list()

  # Kullanıcı adı bilgisi
  if (nzchar(user_name)) {
    context_parts <- c(context_parts, sprintf("Kullanıcının adı: %s", user_name))
  }
  
  # Kullanıcının birim bilgisi
  if (is.list(user_work_context)) {
    effective_unit <- safe_trimws(user_work_context$effective_unit %||% "")
    department <- safe_trimws(user_work_context$department %||% "")
    mudurluk <- safe_trimws(user_work_context$mudurluk %||% "")

    if (safe_nzchar(department) && safe_nzchar(mudurluk)) {
      context_parts <- c(context_parts, sprintf(
        "Kullanıcının departmanı: %s. Bağlı olduğu müdürlük/direktörlük: %s",
        department, mudurluk
      ))
    } else if (safe_nzchar(effective_unit)) {
      context_parts <- c(context_parts, sprintf(
        "Kullanıcının çalıştığı birim: %s",
        effective_unit
      ))
    }

    if (safe_nzchar(effective_unit)) {
      context_parts <- c(
        context_parts,
        "Bu bilgiyi yalnızca konuşmayı bağlama oturtmak için kullan. Kullanıcının güncel işi, görevi veya üzerinde çalıştığı konu hakkında doğrulanmamış varsayım üretme."
      )
    }
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

  # Mevcut oturumdaki mesajlar (güncel bağlam)
  if (!is.null(current_session_messages) && length(current_session_messages) > 0) {
    session_prompts <- paste(
      sprintf("- \"%s\"", substr(current_session_messages, 1, 200)),
      collapse = "\n"
    )
    context_parts <- c(context_parts, sprintf(
      "Bu oturumdaki kullanıcı mesajları (EN GÜNCEL - öncelikli bağlam):\n%s",
      session_prompts
    ))
  }

  # Mevcut zaman bilgisi
  context_parts <- c(context_parts, sprintf(
    "Şimdi: %s", format(Sys.time(), "%d %B %Y %H:%M", tz = "Europe/Istanbul")
  ))

  context_parts <- normalize_utf8_text(unlist(context_parts, use.names = FALSE))
  paste(context_parts, collapse = "\n\n")
}


# --- AI Uzman üretim parametrelerini çözümle ---
# Konuşma uzunluğu ve tarzı ayarlarının LLM üzerinde daha belirgin
# etkisi olması için max_tokens ve temperature değerlerini üretir.
#
# @param scenario Senaryo türü
# @param talk_length Konuşma uzunluğu ayarı
# @param talk_style Konuşma tarzı ayarı
# @return Liste: max_tokens, temperature
get_ai_expert_generation_config <- function(scenario = "idle_chat",
                                            talk_length = "orta",
                                            talk_style = "profesyonel") {
  # Konuşma metni token tavanı. Eski değerler (220/150/240) modelin tam
  # konuşmayı bitirmesine yetmiyordu; uzun konuşmalarda metin cümle ortasında
  # kesiliyor ve TTS/altyazı genelde 3. parçadan sonra eksik kalıyordu. Tavan,
  # modelin doğal yanıtını tamamlamasına yetecek kadar yükseltildi. Asıl
  # uzunluk yine talk_length (kisa/orta/uzun) ve sistem istemiyle yönlendirilir.
  base_max_tokens <- switch(scenario,
    "greeting" = 480L,
    "page_guidance" = 360L,
    "idle_chat" = 560L,
    480L
  )

  max_tokens <- switch(talk_length %||% "orta",
    "kisa" = max(200L, as.integer(round(base_max_tokens * 0.55))),
    "orta" = base_max_tokens,
    "uzun" = as.integer(round(base_max_tokens * 1.80)),
    base_max_tokens
  )

  temperature <- switch(talk_style %||% "profesyonel",
    "profesyonel" = 0.55,
    "samimi" = 0.80,
    "motivasyonel" = 0.90,
    "bilimsel" = 0.45,
    0.70
  )

  list(
    max_tokens = max_tokens,
    temperature = temperature
  )
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
                                           is_revisit = FALSE,
                                           talk_length = "orta",
                                           talk_style = "profesyonel") {

  # Rehber belgesini oku
  guide_text <- ""
  guide_path <- file.path(getwd(), "ai_rehber.md")
  if (file.exists(guide_path)) {
    guide_text <- tryCatch(
      normalize_utf8_text(
        paste(readLines(guide_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
      ),
      error = function(e) ""
    )
  }

  char_name <- safe_trimws(character_data$display_name %||% "EMRE ONAT")
  char_style <- safe_trimws(character_data$style_tr %||% "")
  page_name <- safe_trimws(page_name %||% "")
  user_name <- safe_trimws(user_name %||% "")
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
      "bahset, kullanıcıyı keşfe davet et. Samimi ve merak uyandırıcı ol. ",
      "Sağ taraftaki Hızlı Başlangıç butonlarından bahset: dosya yükleme ve analiz, ",
      "toplantı notu özetleme, proje durum raporu oluşturma gibi hızlı işlemleri ",
      "kolayca başlatabileceklerini söyle.\n",
      "- Geri dönen kullanıcı ise: Son konuşma konularından doğal bir geçişle bahset. ",
      "'Geçen seferki konuşmamızda...' gibi bir giriş yapabilirsin. ",
      "Kaldığı yerden devam etmek isteyip istemediğini sor. ",
      "Ayrıca sağ taraftaki hızlı işlem butonlarıyla yeni bir şey deneyebileceğini belirt.\n",
      "- Uzun süredir giriş yapmamış kullanıcı ise: Tekrar görmenin sevindirici olduğunu ",
      "belirt, nazikçe yokluğuna değin, nasıl yardımcı olabileceğini sor.\n\n",
      "Kullanıcı Ana Söyleşi sayfasında. Bu sayfada sohbet edebilir, sorular sorabilir ",
      "ve sağ taraftaki Hızlı Başlangıç butonlarını kullanarak hızlıca işlemlere başlayabilir.\n\n",
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
      "Bu konuşma devam eden bir sohbetin doğal parçası gibi hissettirmeli. ",
      "Sen aynı kurumda çalışan, teknik dünyaya aşina, güven veren bir iş arkadaşı gibi konuş. ",
      "ASELSAN ve benzeri elektronik savunma, radar ve elektronik harp ortamının diline ve ciddiyetine uygun ol, ama resmî anons gibi konuşma.\n\n",
      "ÖNCELİK SIRASI: Önce bu oturumdaki en güncel kullanıcı mesajlarına bak. Sonra veritabanındaki son kullanıcı mesajlarını dikkate al. ",
      "Bunlardan anlamlı bir bağ kurabiliyorsan konuşmanı öncelikle bunun etrafında şekillendir. ",
      "Kullanıcının departman veya müdürlük bilgisi varsa bunu sadece bağlam kurmak için kullan; ",
      "kullanıcının o anda ne yaptığı, hangi projede olduğu veya hangi görevi yürüttüğü hakkında varsayım uydurma.\n\n",
      "YASAKLAR: Asla 'merhaba', 'hoş geldin', 'nasılsın' gibi yeni sohbet açan kalıplar kullanma. ",
      "Asla 'uzun süredir görüşmedik' deme. Aynı giriş cümlesini, aynı konu başlığını veya aynı tavrı tekrar etme. ",
      "Sunucu anonsu, eğitim videosu anlatımı, kurumsal bülten veya robotik asistan gibi konuşma.\n\n",
      "KONU ÇERÇEVESİ: Konuşma çoğunlukla kullanıcının son mesajları, ilgi gösterdiği teknik başlıklar, çalıştığı birim bağlamı, ",
      "uygulamanın yararlı özellikleri ve genel mühendislik çalışma pratiği etrafında dönsün. ",
      "Bunun yanında zaman zaman iş dışı ama fazla kişisel olmayan hafif başlıklara da değinebilirsin; ",
      "örneğin odaklanma, kısa mola, öğrenme alışkanlıkları, teknoloji merakı, günün ritmi veya zihni tazeleyen küçük rutinler. ",
      "Özel hayat, aile, sağlık, maddi durum, siyasi görüş veya mahrem alanlara girme.\n\n",
      "DAVRANIŞ: Tek mesajda tek ana fikir seç. Bazen kısa bir gözlem paylaş, bazen kullanıcının önceki mesajına doğal bir yorum yap, ",
      "bazen küçük ama işe yarar bir öneri sun, bazen de düşünmeye sevk eden hafif bir soru sor. ",
      "Her seferinde soru sormak zorunda değilsin. Ama konuşma canlı, doğal ve karşılıklıymış gibi hissettirsin.\n\n",
      "TON: Sıcak, doğal, akıllı ve meslektaş gibi konuş. Bilgili ol ama ukala olma. Teknik ol ama jargona boğma. ",
      "3-5 cümle ideal. Her konuşma taze ve insani olsun."
    ),
    # Varsayılan
    paste0(name_instruction, "Profesyonel ve samimi bir mesaj oluştur. 3-5 cümle ile konuş.")
  )

  # Konuşma uzunluğu talimatı
  length_instruction <- switch(talk_length %||% "orta",
    "kisa" = "UZUNLUK: Çok kısa konuş, 1-2 cümle yeterli. Özlü ve vurucu ol.",
    "orta" = "UZUNLUK: 3-5 cümle ile akıcı şekilde konuş.",
    "uzun" = "UZUNLUK: 5-8 cümle ile detaylı ve zengin konuş. Konuyu derinlemesine işle.",
    "UZUNLUK: 3-5 cümle ile akıcı şekilde konuş."
  )

  # Konuşma tarzı talimatı
  style_instruction <- switch(talk_style %||% "profesyonel",
    "profesyonel" = "TARZ: Profesyonel, net ve dengeli ol. Kurumsal ortama uygun kal, ama soğuk ve mesafeli durma.",
    "samimi" = "TARZ: Daha yakın, daha konuşma dili gibi ve iş arkadaşı sıcaklığında ol. Resmiyeti azalt ama ciddiyeti bozma.",
    "motivasyonel" = "TARZ: Yapıcı, cesaret verici ve enerji yükselten bir ton kullan. Kullanıcıyı sıkmadan motive et.",
    "bilimsel" = "TARZ: Analitik, kavramsal ve teknik doğruluk odaklı ol. Yöntem, neden-sonuç ve mühendislik mantığını vurgula.",
    "TARZ: Profesyonel, net ve dengeli ol. Kurumsal ortama uygun kal, ama soğuk ve mesafeli durma."
  )

  # Sistem istemini birleştir
  prompt <- paste0(
    "Sen ", char_name, " adında bir AI asistanısın. ",
    "MERGEN Bilge uygulamasının yapay zeka uzmanı olarak kullanıcıyla sesli ve yazılı etkileşim kuruyorsun. ",
    "Türkçe konuşuyorsun. Asla İngilizce konuşma. ",
    "Bu uygulama ASELSAN ve benzeri elektronik savunma, radar ve elektronik harp odaklı kurumsal bir mühendislik ortamında kullanılıyor. ",
    if (nzchar(char_style)) paste0("\nKarakter Tarzı: ", char_style, "\n") else "",
    "\n\n",
    "ÖNEMLİ KURALLAR:\n",
    "- Her zaman Türkçe konuş, asla İngilizce kelime veya cümle kullanma\n",
    "- Doğal, akıcı ve insani bir şekilde konuş - kısa kesik cümleler değil, akıcı paragraflar\n",
    "- Mekanik veya robotik durma, bir insan gibi konuş\n",
    "- Emoji kullanma\n",
    "- Markdown formatlaması kullanma (yıldız, diyez, madde işareti vb.)\n",
    "- Sadece düz metin yaz, liste yapma\n",
    "- Bilge, rehber niteliğinde ama kibirli veya üstten konuşma\n",
    "- Kullanıcının görevi, yaptığı iş veya o anda ne üzerinde çalıştığı hakkında bağlam dışı varsayım üretme\n",
    "- Önce kullanıcının son mesajlarına, sohbet bağlamına ve bilinen birim bilgisine yaslan\n",
    "- Konuşman sesli olarak okunacak, bu yüzden kulağa hoş gelen, doğal bir Türkçe kullan\n",
    "- Uzun tire (em dash, en dash) kullanma, normal tire veya virgül kullan\n",
    "- Özel Unicode karakterleri kullanma (oklar, kutucuklar, semboller vb.)\n\n",
    length_instruction, "\n",
    style_instruction, "\n\n",
    "GÖREV:\n", scenario_instruction, "\n\n",
    "UYGULAMA REHBERİ (Referans olarak kullan):\n",
    if (nzchar(guide_text)) substr(guide_text, 1, 10000) else "(Rehber belgesi bulunamadı)"
  )

  return(prompt)
}