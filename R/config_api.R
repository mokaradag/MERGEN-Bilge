# ==============================================================================
# R/config_api.R
# API yapılandırması: LLM uç noktaları, model tanımları, TTS/STT ayarları,
# API anahtarı doğrulama, servis masası bağlantıları ve kullanıcı yapılandırması.
# global.R tarafından config_logging.R'den sonra source() ile çağrılır.
# ==============================================================================

# --- .Renviron DOSYASINI ZORLA YÜKLE ---
# Tüm Sys.getenv() çağrılarından ÖNCE yüklenmeli ki doğru değerler okunabilsin
if (file.exists(".Renviron")) {
  readRenviron(".Renviron")
}

# --- GLOBAL YAPILANDIRMA ---

# Word önizleme modu: "html" (istemci tarafı mammoth.js) veya "pdf" (sunucu tarafı LibreOffice)
options(mergen.word_preview_mode = "html")

# --- LLM UÇ NOKTALARI ---
primary_llm_endpoint   <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")
secondary_llm_endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT_ALT", primary_llm_endpoint)
secondary_llm_api_key  <- Sys.getenv("LOCAL_LLM_ENDPOINT_ALT_API_KEY", "")

options(mergen.filter_model = Sys.getenv("FILTER_MODEL", "mergen-local-model"))

# --- DERİN DÜŞÜNME MODELLERİ ---
# Excel Analizi ve Kod Uzmanı araçlarında "Derin Düşünme" düğmesi etkinleştirildiğinde
# kullanılacak ek modeller. Bu modeller normal "Model Değiştir" / Yapılandırma model
# dropdown'larında listelenmez; yalnızca ilgili aracın derin düşünme modunda otomatik
# olarak seçilir. Çevre değişkenleri tanımsızsa varsayılan teknik modele düşülür.
excel_deep_low_model   <- Sys.getenv("EXCEL_DEEP_LOW_MODEL",   "technical name 3")
excel_deep_high_model  <- Sys.getenv("EXCEL_DEEP_HIGH_MODEL",  "technical name 4")
coding_deep_low_model  <- Sys.getenv("CODING_DEEP_LOW_MODEL",  "technical name 3")
coding_deep_high_model <- Sys.getenv("CODING_DEEP_HIGH_MODEL", "technical name 4")

# --- ANA API YAPILANDIRMASI ---
api_config <- list(
  # Geriye dönük uyumluluk: eski tek-endpoint alanını koru
  local_llm_endpoint = primary_llm_endpoint,
  # Çoklu uç nokta desteği (aşağıdaki model haritasında anahtarla referansla)
  local_llm_endpoints = list(
    primary   = primary_llm_endpoint,
    secondary = secondary_llm_endpoint
  ),
  local_llm_endpoint_keys = list(
    primary   = NULL,
    secondary = secondary_llm_api_key
  ),
  local_llm_endpoint_user_managed = c(
    primary   = TRUE,
    secondary = FALSE
  ),
  local_llm_default_endpoint_key = "primary",
  # Açılır menü etiketleri -> teknik model kimlikleri
  local_models = c(
    "Dropdown display model 1" = "technical name 1",
    "Dropdown display model 2" = "technical name 2",
    "Dropdown display model 3" = "technical name 3",
    "Dropdown display model 4" = "technical name 4",
    "Dropdown display model 5" = "technical name 5",
    "Dropdown display model 6" = "technical name 6"
  ),
  # Model açıklamaları (tooltip'ler için)
  local_model_descriptions = list(
    "technical name 1" = "Genel amaçlı, dengeli performans",
    "technical name 2" = "Hızlı yanıt, günlük kullanım",
    "technical name 3" = "Gelişmiş akıl yürütme",
    "technical name 4" = "Yüksek hassasiyet, detaylı analiz",
    "technical name 5" = "İkincil endpoint modeli",
    "technical name 6" = "Özel görevler için optimize"
  ),
  # Model bağlam penceresi boyutları
  local_model_context_sizes = list(
    "technical name 1" = "128K",
    "technical name 2" = "128K",
    "technical name 3" = "256K",
    "technical name 4" = "128K",
    "technical name 5" = "200K",
    "technical name 6" = "128K"
  ),
  # Dropdown'da model adlarının yanında gösterilecek Unicode ikonlar
  local_model_icons = list(
    "technical name 1" = "\U0001F4A1",
    "technical name 2" = "\U0001F680",
    "technical name 3" = "\U0001F9E0",
    "technical name 4" = "\U0001F50D",
    "technical name 5" = "\U0001F310",
    "technical name 6" = "\U00002699"
  ),
  # Her teknik model kimliğini bir uç nokta anahtarına eşle.
  # Derin Düşünme modelleri yalnızca temel haritada bulunmuyorsa eklenir.
  # NOT: unique() adlandırılmış karakter vektörlerde sadece DEĞERE göre dedup
  # yapar ve isimleri kaybeder. Bu yüzden manuel ekleme döngüsü kullanılır.
  local_model_endpoint_map = c(
    "technical name 1" = "primary",
    "technical name 2" = "primary",
    "technical name 3" = "primary",
    "technical name 4" = "primary",
    "technical name 5" = "secondary",
    "technical name 6" = "secondary"
  ),
  # Excel/Kod araçlarındaki Derin Düşünme düğmesi için (family, level) -> model_id eşlemesi.
  # Bu modeller dropdown'larda görünmez; sadece runtime'da seçilir.
  deep_thinking_models = list(
    mcp_excel = list(low = excel_deep_low_model,  high = excel_deep_high_model),
    coding    = list(low = coding_deep_low_model, high = coding_deep_high_model)
  ),
  # Teknik kimlikler -> temel klasörler (sadece teknik kimlikleri kullan)
  local_model_paths = list(
    "technical name 1" = "\\\\main folder\\secondary folder\\repository\\top folder",
    "technical name 2" = "\\\\main folder\\secondary folder\\repository\\top folder2"
  ),
  # Araç/uzman modlarının merkezi tanımı
  tool_mode_config = list(
    process = list(
      family = "process",
      setting_flag = "enable_process_tools",
      quick_action_id = "project-process",
      title = "Süreç Yönetimi Sistemi",
      message = "Kurumsal süreç ve dokümantasyon konusunda yardıma ihtiyacım var.",
      description = "Şirket içi süreç, izleç, rehber ve şablon dokümanları hakkında detaylı bilgi edinin.",
      icon_name = "briefcase",
      themeColor = "#3b82f6",
      model_id = "technical name 1",
      real_tool = FALSE
    ),
    app_expert = list(
      family = "app_expert",
      setting_flag = "enable_app_expert_tools",
      quick_action_id = "app-expert",
      title = "Uygulama Uzmanı",
      message = "Primavera P6 konusunda uzman desteğine ihtiyacım var.",
      description = "Şirket genelinde kullanılan uygulamalar hakkında bilgi edinin. SAP, Primavera P6, Jira gibi uygulamalar hakkında detaylı bilgi edinin.",
      icon_name = "window-maximize",
      themeColor = "#8b5cf6",
      model_id = "technical name 6",
      real_tool = FALSE
    ),	
    sql_analysis = list(
      family = "sql_analysis",
      setting_flag = "enable_rdata_tools",
      quick_action_id = "resource-analysis",
      title = "Proje ve Kaynak Analizi",
      message = "Kaynak kullanımını analiz etmem konusunda yardıma ihtiyacım var.",
      description = "Primavera P6 ve SAP raporları üzerinden proje takvimi ve kaynak yönetimi hakkında verileri analiz edin.",
      icon_name = "chart-bar",
      themeColor = "#06b6d4",
      model_id = "technical name 3",
      real_tool = TRUE
    ),
    mcp_excel = list(
      family = "mcp_excel",
      setting_flag = "enable_mcp_tools",
      quick_action_id = "excel-analysis",
      title = "Excel Analizi",
      message = "Excel dosyamı analiz etmem için yardım eder misin?",
      description = "MCP Excel aracı ile karmaşık veri setlerini otomatik olarak analiz edin.",
      icon_name = "file-excel",
      themeColor = "#10b981",
      model_id = "technical name 4",
      real_tool = TRUE
    ),
    image = list(
      family = "image",
      setting_flag = "enable_image_tools",
      quick_action_id = "image-creation",
      title = "Görsel Oluşturma",
      message = "Yapay zeka ile görsel oluşturmak istiyorum.",
      description = "Metin tabanlı açıklamalarla AI görüntü oluşturma modellerini kullanarak özel görseller tasarlayın.",
      icon_name = "image",
      themeColor = "#ec4899",
      model_id = Sys.getenv("IMAGE_GEN_MODEL", "dall-e-3"),
      real_tool = TRUE
    ),	
    coding = list(
      family = "coding",
      setting_flag = "enable_coding_tools",
      quick_action_id = "coding-support",
      title = "Kodlama Desteği",
      message = "Yazılım geliştirme konusunda yardıma ihtiyacım var.",
      description = "C++, Python, R, JavaScript ve diğer dillerde kod optimizasyonu, hata ayıklama, algoritma tasarımı ve best practice önerileri.",
      icon_name = "code",
      themeColor = "#f59e0b",
      model_id = "technical name 5",
      real_tool = FALSE
    ),	
    summarization = list(
      family = "summarization",
      setting_flag = "enable_summarization_tools",
      quick_action_id = "summarization",
      title = "Özetleme Desteği",
      message = "__SUMMARIZATION_REQUEST__",
      description = "Dosya Yönetimi'nde eklediğiniz belgeleri kapsamlı şekilde özetleyin. Tüm önemli başlıklar, alt konular ve sayısal veriler korunur.",
      icon_name = "file-alt",
      themeColor = "#6366f1",
      model_id = "technical name 2",
      real_tool = TRUE
    )
  ),
  # Model yetenekleri: thinking davranışı ve akış ayrıştırma kuralları
  local_model_capabilities = list(
    "technical name 1" = list(
      thinking = FALSE,
      omit_temperature = FALSE,
      stream_reasoning = FALSE,
      allow_reasoning_fallback = FALSE
    ),
    "technical name 2" = list(
      thinking = FALSE,
      omit_temperature = FALSE,
      stream_reasoning = FALSE,
      allow_reasoning_fallback = FALSE
    ),
    "technical name 3" = list(
      thinking = TRUE,
      omit_temperature = TRUE,
      stream_reasoning = TRUE,
      allow_reasoning_fallback = TRUE
    ),
	"technical name 4" = list(
	  thinking = TRUE,
	  omit_temperature = TRUE,
	  stream_reasoning = TRUE,
	  allow_reasoning_fallback = TRUE,

	  # Gemma endpoint'i reasoning'i otomatik ayırmıyorsa thinking template'i
	  # açıkça etkinleştir. Bu alan ham HTTP body içine top-level olarak eklenir.
	  request_overrides = list(
		chat_template_kwargs = list(
		  enable_thinking = TRUE
		)
	  )
	),
    "technical name 5" = list(
      thinking = FALSE,
      omit_temperature = FALSE,
      stream_reasoning = FALSE,
      allow_reasoning_fallback = FALSE
    ),
    "technical name 6" = list(
      thinking = FALSE,
      omit_temperature = FALSE,
      stream_reasoning = FALSE,
      allow_reasoning_fallback = FALSE
    )
  )
)

# --- DERİN DÜŞÜNME MODEL YETENEKLERİ ---
# Derin Düşünme modelleri (Excel ve Kod araçları için) thinking-capable kabul edilir.
# Eğer model kimliği halihazırda local_model_capabilities içinde tanımlı değilse
# güvenli varsayılanlarla eklenir. Var olan tanımlar dokunulmaz; üretim için
# zaten tanımlı thinking modellerinin (örn. "technical name 3"/"technical name 4")
# kapasiteleri korunur.
.mb_deep_thinking_capability_template <- list(
  thinking = TRUE,
  omit_temperature = TRUE,
  stream_reasoning = TRUE,
  allow_reasoning_fallback = TRUE,
  request_overrides = list(
    chat_template_kwargs = list(
      enable_thinking = TRUE
    )
  )
)

for (.mb_dt_model in unique(c(excel_deep_low_model, excel_deep_high_model,
                              coding_deep_low_model, coding_deep_high_model))) {
  .mb_dt_model <- as.character(.mb_dt_model)[1]

  if (is.na(.mb_dt_model) || !nzchar(.mb_dt_model)) {
    next
  }

  if (is.null(api_config$local_model_capabilities[[.mb_dt_model]])) {
    api_config$local_model_capabilities[[.mb_dt_model]] <- .mb_deep_thinking_capability_template
  }

  # Yeni Derin Düşünme modeli endpoint haritasında yoksa varsayılan olarak
  # birincil (primary) endpoint'e eşle. Mevcut girdiler korunur.
  #
  # ÖNEMLİ:
  # local_model_endpoint_map adlandırılmış karakter vektörüdür.
  # Eksik ada [[...]] ile erişmek "altindis sınırlar dışında" hatası verir.
  endpoint_map <- api_config$local_model_endpoint_map
  if (is.null(endpoint_map)) {
    endpoint_map <- character()
  }

  endpoint_map_names <- names(endpoint_map)

  endpoint_mapped <- !is.null(endpoint_map_names) &&
    .mb_dt_model %in% endpoint_map_names &&
    !is.na(endpoint_map[.mb_dt_model]) &&
    nzchar(as.character(endpoint_map[.mb_dt_model])[1])

  if (!isTRUE(endpoint_mapped)) {
    endpoint_map[.mb_dt_model] <- "primary"
    api_config$local_model_endpoint_map <- endpoint_map
  }
}
rm(.mb_dt_model, .mb_deep_thinking_capability_template)

# --- SES SENTEZİ (TTS) YAPILANDIRMASI ---
# OpenAI uyumlu ses uç noktası
tts_config <- list(
  base_url        = Sys.getenv("LOCAL_TTS_ENDPOINT", ""),
  api_key         = Sys.getenv("LOCAL_TTS_API_KEY", ""),
  model           = Sys.getenv("LOCAL_TTS_MODEL", "tts-1-hd"),
  default_voice   = Sys.getenv("LOCAL_TTS_VOICE", "tr-male-1"),
  timeout_seconds = as.numeric(Sys.getenv("LOCAL_TTS_TIMEOUT", "90")),
  verify_ssl      = isTRUE(as.logical(Sys.getenv("LOCAL_TTS_VERIFY_SSL", "TRUE")))
)

# --- SES TANIMA (STT) YAPILANDIRMASI ---
stt_config <- list(
  endpoint = Sys.getenv("LOCAL_STT_ENDPOINT"),
  model    = Sys.getenv("LOCAL_STT_MODEL"),
  api_key  = Sys.getenv("AI_KEYS_MASTER", Sys.getenv("OPENAI_API_KEY", ""))
)

# STT yapılandırma durumunu log seviyesinde kaydet (üretimde hassas bilgi sızdırmaz)
log_debug("STT yapılandırma kontrolü - Endpoint tanımlı: {nzchar(stt_config$endpoint)}, API anahtarı uzunluğu: {nchar(stt_config$api_key)}")
if (!nzchar(stt_config$api_key)) {
  log_warn("STT API anahtarı boş \U2014 .Renviron dosyasının doğru yüklendiğinden emin olun.")
}

# Başlangıçta indeksleri hazırla (ilk tıklama gecikmesini azaltır)
try({
  bases <- unique(unname(api_config$local_model_paths %||% character()))
  invisible(lapply(bases, function(p) .build_basename_index(p)))
}, silent = TRUE)

# --- API ANAHTARI DOĞRULAMA ---
validate_api_key <- function(api_key, model_id = NULL, endpoint = NULL, timeout_seconds = 5) {
  if (!nzchar(api_key)) {
    return(list(valid = FALSE, message = "Anahtar boş."))
  }

  # 1) Model belirle
  if (is.null(model_id) || !nzchar(model_id)) {
    model_id <- as.character(api_config$local_models[1])
  }

  # 2) Sağlık uç noktası varsa onu kullan
  health_url <- Sys.getenv("LLM_HEALTH_ENDPOINT", "")
  if (!nzchar(endpoint)) {
    endpoint <- resolve_local_llm_endpoint(model_id)
  }

  hdrs <- httr::add_headers(
    `Content-Type`  = "application/json",
    `Authorization` = paste("Bearer", api_key)
  )

  # Yardımcı: hafif /v1/models URL'si türet (hızlı doğrulama)
  derive_models_url <- function(ep) {
    if (!nzchar(ep)) return("")
    url_no_query <- sub("\\?.*$", "", ep)
    url_no_query <- sub("/+$", "", url_no_query)
    if (grepl("/v1/", url_no_query, fixed = TRUE)) {
      sub("(/v1/).*", "\\1models", url_no_query)
    } else {
      paste0(url_no_query, "/v1/models")
    }
  }

  models_url <- derive_models_url(endpoint)
  model_fail_detail <- ""

  if (nzchar(models_url)) {
    res_models <- try(
      httr::GET(models_url, hdrs, httr::accept_json(), httr::timeout(min(timeout_seconds, 4))),
      silent = TRUE
    )

    if (!inherits(res_models, "try-error")) {
      sc_models <- httr::status_code(res_models)
      if (sc_models == 200) {
        return(list(valid = TRUE, message = "Anahtar doğrulandı (model listesi)."))
      }
      if (sc_models %in% c(401, 403)) {
        return(list(valid = FALSE, message = "Anahtar reddedildi (401/403)."))
      }
      if (sc_models == 429) {
        model_fail_detail <- "Model listesi isteği hız limitine takıldı (429)."
      } else if (sc_models >= 500) {
        model_fail_detail <- paste("Model listesi isteği sunucu hatası verdi:", sc_models)
      } else {
        model_fail_detail <- paste("Model listesi isteği beklenmedik yanıt döndürdü:", sc_models)
      }
    } else {
      model_fail_detail <- "Model listesi isteğine ulaşılamadı (bağlantı/timeout)."
    }
  }

  # Önce sağlık uç noktasını (GET) dene (varsa)
  if (nzchar(health_url)) {
    res <- try(httr::GET(health_url, hdrs, httr::timeout(timeout_seconds)), silent = TRUE)
    if (!inherits(res, "try-error")) {
      sc <- httr::status_code(res)
      if (sc == 200) return(list(valid = TRUE,  message = "Sağlık/kimlik doğrulama başarılı."))
      if (sc %in% c(401, 403)) return(list(valid = FALSE, message = "Anahtar reddedildi (401/403)."))
    }
  }

  # Sağlık yoksa veya başarısızsa: sohbet uç noktasına minimum POST ping
  if (!nzchar(endpoint)) {
    return(list(valid = NA, message = "Doğrulama yapılamadı (endpoint tanımsız)."))
  }

  body <- list(
    model = model_id,
    messages = list(list(role = "user", content = "test")),
    max_tokens = 1
  )

  res <- try(
    httr::POST(endpoint, hdrs, body = jsonlite::toJSON(body, auto_unbox = TRUE),
               encode = "raw", httr::timeout(timeout_seconds)),
    silent = TRUE
  )

  if (inherits(res, "try-error")) {
    detail <- if (nzchar(model_fail_detail)) paste0(" (", model_fail_detail, ")") else ""
    return(list(valid = NA, message = paste0("Sunucuya ulaşılamadı.", detail)))
  }

  sc <- httr::status_code(res)
  if (sc %in% c(200, 201)) {
    return(list(valid = TRUE, message = "Anahtar doğrulandı (sohbet ping)."))
  }
  if (sc %in% c(401, 403)) {
    return(list(valid = FALSE, message = "Anahtar reddedildi (401/403)."))
  }
  if (sc == 429) {
    return(list(valid = TRUE, message = "Sunucu hız limiti uyguladı; anahtar geçerli kabul edildi."))
  }

  list(valid = NA, message = paste0("Beklenmedik HTTP kodu: ", sc, ". Bağlantıyı kontrol edin."))
}

# --- SERVİS MASASI BAĞLANTILARI ---
SERVICE_DESK <- list(
  api_key_request_url = Sys.getenv("SERVICE_DESK_API_KEY_URL", "https://servicedesk.example.com/api-key"),
  rate_limit_url      = Sys.getenv("SERVICE_DESK_RATE_LIMIT_URL", "https://servicedesk.example.com/rate-limit")
)

# --- KULLANICI YAPILANDIRMASI ---
# Not: name ve userId oturum başında server.R tarafından güncellenir.
# SSO_ENABLED=TRUE ise Keycloak token'ından, FALSE ise DB'den doldurulur.
# Ek alanlar (sicil, sektor, department, vb.) SSO aktifken Keycloak'tan gelir.
user_config <- list(
  name            = "",
  icon            = "user-circle",
  userId          = "",
  auth_level      = Sys.getenv("MERGEN_AUTH_LEVEL", "ADMIN"),
  # SSO ile gelen ek alanlar (Keycloak claim'leri)
  sicil           = NULL,
  email           = NULL,
  first_name      = NULL,
  last_name       = NULL,
  sektor          = NULL,
  department      = NULL,
  mudurluk        = NULL,
  masraf_yeri_kodu = NULL
)

# --- KULLANICI API ANAHTARI YÖNETİMİ ---
API_KEYS_DIR <- normalizePath(file.path(getwd(), "api_keys"), winslash = "/", mustWork = FALSE)
dir.create(API_KEYS_DIR, showWarnings = FALSE, recursive = TRUE)

# Kullanıcıya özel anahtar dosya yolu
.api_user_file <- function(system_username) {
  file.path(API_KEYS_DIR, sprintf("%s_api_key", system_username))
}

# Tuzlu hash oluştur (SHA256 hex): SHA256(salt || key)
.hash_key_hex <- function(key_plain, salt_raw) {
  stopifnot(is.character(key_plain), length(key_plain) == 1)
  openssl::sha256(paste0(rawToChar(salt_raw), key_plain)) |>
    as.character() # hex string
}

# AES-256-GCM (kimlik doğrulamalı) şifreleme
# Geriye dönük uyumluluk: GCM yoksa CBC'ye düşer
.enc_key <- function(plain_text, master) {
  stopifnot(is.character(plain_text), length(plain_text) == 1)

  # 32 baytlık anahtar türet
  k <- openssl::sha256(charToRaw(master))

  # GCM mevcutsa ve beklenen yapıyı döndürüyorsa tercih et
  use_gcm <- isTRUE(exists("aes_gcm_encrypt", where = asNamespace("openssl"), inherits = FALSE))
  if (use_gcm) {
    iv12 <- openssl::rand_bytes(12L)
    gcm  <- openssl::aes_gcm_encrypt(
      data = charToRaw(plain_text),
      key  = k,
      iv   = iv12
    )

    # Bazı openssl sürümleri list(data=raw, tag=raw) döndürür, bazıları farklı
    if (is.list(gcm) && !is.null(gcm$data) && is.raw(gcm$data) && !is.null(gcm$tag) && is.raw(gcm$tag)) {
      return(list(
        alg        = "aes-256-gcm",
        iv_b64     = base64enc::base64encode(iv12),
        cipher_b64 = base64enc::base64encode(gcm$data),
        tag_b64    = base64enc::base64encode(gcm$tag)
      ))
    }
    # GCM var ama beklenen yapıyı döndürmedi -> CBC'ye düş
  }

  # Yedek: AES-256-CBC (her zaman mevcut)
  iv16 <- openssl::rand_bytes(16L)
  ct   <- openssl::aes_cbc_encrypt(charToRaw(plain_text), key = k, iv = iv16)
  list(
    alg        = "aes-256-cbc",
    iv_b64     = base64enc::base64encode(iv16),
    cipher_b64 = base64enc::base64encode(ct)
    # CBC'de tag_b64 yok
  )
}

# AES-256-GCM / CBC çözme (geriye dönük uyumlu)
.dec_key <- function(enc_obj, master) {

  # Basit doğrulama: zorunlu alanlar
  if (is.null(enc_obj$iv_b64) || is.null(enc_obj$cipher_b64)) {
    stop("Kayıt bozuk: iv/cipher alanı yok.")
  }

  k <- openssl::sha256(charToRaw(master))

  # Önce GCM varsay: tag varsa GCM çöz
  if (!is.null(enc_obj$tag_b64)) {
    iv <- base64enc::base64decode(enc_obj$iv_b64 %||% "")
    ct <- base64enc::base64decode(enc_obj$cipher_b64 %||% "")
    tg <- base64enc::base64decode(enc_obj$tag_b64 %||% "")

    raw <- openssl::aes_gcm_decrypt(
      data = ct,
      key  = k,
      iv   = iv,
      tag  = tg
    )
    return(rawToChar(raw))
  }

  # Geriye dönük: eski CBC kayıtları için çözüm
  iv <- base64enc::base64decode(enc_obj$iv_b64 %||% "")
  ct <- base64enc::base64decode(enc_obj$cipher_b64 %||% "")
  rawToChar(openssl::aes_cbc_decrypt(ct, key = k, iv = iv))
}

# Kullanıcı API anahtarını şifrele ve kaydet
save_user_api_key <- function(system_username, key_plain) {
  f <- .api_user_file(system_username)
  master <- Sys.getenv("AI_KEYS_MASTER", "")
  if (!nzchar(master)) stop("AI_KEYS_MASTER is missing in .Renviron")

  salt <- openssl::rand_bytes(16L)
  hash_hex <- .hash_key_hex(key_plain, salt)
  enc <- .enc_key(key_plain, master)

  rec <- list(
    user = system_username,
    salt_b64 = base64enc::base64encode(salt),
    hash_hex = hash_hex,
    enc = enc,
    created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  # API anahtarı kayıt dosyası kısmi yazıma karşı kritiktir; atomik yardımcıdan
  # geçirilir (tmp -> rename) ve Windows VM'de kilitli dosya durumunda kopya
  # fallback davranışı korunur.
  atomic_write_json(rec, f, pretty = TRUE, auto_unbox = TRUE)
  normalizePath(f, winslash = "/", mustWork = FALSE)
}

# Kullanıcı API anahtarını çöz ve döndür
load_user_api_key <- function(system_username) {
  f <- .api_user_file(system_username)
  if (!file.exists(f)) return(NULL)
  master <- Sys.getenv("AI_KEYS_MASTER", "")
  if (!nzchar(master)) return(NULL)
  rec <- try(jsonlite::read_json(f, simplifyVector = TRUE), silent = TRUE)
  if (inherits(rec, "try-error") || is.null(rec$enc)) return(NULL)
  tryCatch(.dec_key(rec$enc, master), error = function(e) NULL)
}

# Kullanıcının kayıtlı API anahtarı var mı?
user_api_key_exists <- function(system_username) file.exists(.api_user_file(system_username))

# Kullanıcının girdiği anahtarı mevcut kayıtla doğrula (hash karşılaştırması)
verify_user_api_key <- function(system_username, candidate_plain) {
  f <- .api_user_file(system_username)
  if (!file.exists(f)) return(FALSE)
  rec <- try(jsonlite::read_json(f, simplifyVector = TRUE), silent = TRUE)
  if (inherits(rec, "try-error")) return(FALSE)
  salt <- base64enc::base64decode(rec$salt_b64 %||% "")
  hash_hex <- .hash_key_hex(candidate_plain, salt)
  isTRUE(identical(tolower(hash_hex), tolower(rec$hash_hex %||% "")))
}