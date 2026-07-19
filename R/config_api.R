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

# --- LLM UÇ NOKTASI ---
# Tek birincil yerel LLM uç noktası kullanılır. Eskiden ayrı bir uca giden
# akışlar artık kurumsal Langflow ile karşılanır.
primary_llm_endpoint   <- Sys.getenv("LOCAL_LLM_ENDPOINT", "")

mergen_default_api_key_enabled <- isTRUE(as.logical(
  Sys.getenv("MERGEN_ALLOW_DEFAULT_API_KEY", "FALSE")
)) && !isTRUE(as.logical(
  Sys.getenv("MERGEN_REQUIRE_PERSONAL_API_KEY", "FALSE")
))

mergen_default_api_key <- if (isTRUE(mergen_default_api_key_enabled)) {
  Sys.getenv("MERGEN_DEFAULT_API_KEY", "")
} else {
  ""
}

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

# --- LANGFLOW AKIŞ ENTEGRASYONU ---
# "Süreç Yönetimi Sistemi" ve "Uygulama Uzmanı" araçları normal yerel LLM uç
# noktası yerine kurumsal Langflow akışlarını (Chat Input / Chat Output) çağırır.
# GÜVENLİK NOTU: Langflow'un kendi LANGFLOW_API_KEY'i vardır; yerel LLM
# anahtarlarıyla ilişkisi yoktur ve örtük fallback YOKTUR. Süreç Yönetimi birden
# fazla adlandırılmış akışı destekler; ham env değerleri saklanır ve
# helpers_langflow_runtime.R tarafından çözülür (process_flows).
langflow_base_url <- Sys.getenv("LANGFLOW_BASE_URL", "")
langflow_api_key  <- Sys.getenv("LANGFLOW_API_KEY", "")
langflow_timeout_seconds <- suppressWarnings(as.numeric(
  Sys.getenv("LANGFLOW_TIMEOUT_SECONDS", "300")
))
if (is.na(langflow_timeout_seconds) || langflow_timeout_seconds <= 0) {
  langflow_timeout_seconds <- 300
}
langflow_app_expert_flow_id <- Sys.getenv("LANGFLOW_APP_EXPERT_FLOW_ID", "")

# --- ANA API YAPILANDIRMASI ---
api_config <- list(
  # Tek birincil yerel LLM uç noktası (eski tek-endpoint alanıyla aynı değer)
  local_llm_endpoint = primary_llm_endpoint,
  # Uç nokta haritası tek "primary" anahtarına indirgenmiştir.
  local_llm_endpoints = list(
    primary   = primary_llm_endpoint
  ),
  local_llm_endpoint_keys = list(
    primary   = mergen_default_api_key
  ),
  local_llm_endpoint_user_managed = c(
    primary   = TRUE
  ),
  local_llm_default_endpoint_key = "primary",
  # Açılır menü etiketleri -> teknik model kimlikleri
  local_models = c(
    "Dropdown display model 1" = "technical name 1",
    "Dropdown display model 2" = "technical name 2",
    "Dropdown display model 3" = "technical name 3",
    "Dropdown display model 4" = "technical name 4",
    "Dropdown display model 5" = "technical name 5",
	"Dropdown display model 6" = "technical name 6",
    "Dropdown display model 7" = "technical name 7"
  ),
  # Model açıklamaları (tooltip'ler için)
  local_model_descriptions = list(
    "technical name 1" = "Genel amaçlı, dengeli performans",
    "technical name 2" = "Hızlı yanıt, günlük kullanım",
    "technical name 3" = "Gelişmiş akıl yürütme",
    "technical name 4" = "Yüksek hassasiyet, detaylı analiz",
    "technical name 5" = "Gelişmiş görevler için optimize",
    "technical name 6" = "Özel görevler için optimize",
	"technical name 7" = "Özel görevler için optimize"
  ),
  # Model bağlam penceresi boyutları
  local_model_context_sizes = list(
    "technical name 1" = "128K",
    "technical name 2" = "128K",
    "technical name 3" = "256K",
    "technical name 4" = "128K",
    "technical name 5" = "200K",
    "technical name 6" = "256K",
	"technical name 7" = "128K"
  ),
  # Dropdown'da model adlarının yanında gösterilecek Unicode ikonlar
  local_model_icons = list(
    "technical name 1" = "\U0001F4A1",
    "technical name 2" = "\U0001F680",
    "technical name 3" = "\U0001F9E0",
    "technical name 4" = "\U0001F50D",
	"technical name 5" = "\U0001F50D",
    "technical name 6" = "\U0001F310",
    "technical name 7" = "\U00002699"
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
	"technical name 5" = "primary",
    "technical name 6" = "primary",
    "technical name 7" = "primary"
  ),
  # Excel/Kod araçlarındaki Derin Düşünme düğmesi için (family, level) -> model_id eşlemesi.
  # Bu modeller dropdown'larda görünmez; sadece runtime'da seçilir.
  deep_thinking_models = list(
    mcp_excel = list(low = excel_deep_low_model,  high = excel_deep_high_model),
    coding    = list(low = coding_deep_low_model, high = coding_deep_high_model)
  ),
  # Kurumsal Langflow akış entegrasyonu. base_url ve akış kimlikleri ortam
  # değişkenlerinden okunur; tanımsızsa ilgili araç normal LLM yoluna düşmez,
  # bunun yerine net bir yapılandırma-eksik mesajı gösterir (bkz.
  # R/server_handler_langflow.R). API anahtarı asla loglanmaz/istemciye gönderilmez.
  langflow = list(
    base_url = langflow_base_url,
    api_key = langflow_api_key,
    timeout_seconds = langflow_timeout_seconds,
    # Süreç Yönetimi çoklu akış ham env değerleri; parse ve seçim çözümlemesi
    # helpers_langflow_runtime.R içindedir (mergen_langflow_process_flows).
    process_flow_ids_raw   = Sys.getenv("LANGFLOW_PROCESS_FLOW_IDS", ""),
    process_flow_names_raw = Sys.getenv("LANGFLOW_PROCESS_FLOW_NAMES", ""),
    process_flow_legacy_id = Sys.getenv("LANGFLOW_PROCESS_FLOW_ID", ""),
    flow_ids = list(
      app_expert = langflow_app_expert_flow_id
    )
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
      # Langflow aracı: yerel model kavramı yok (akış kendi modelini taşır).
      # Süreç akışı seçimi çoklu process_flows üzerinden çözülür (model_id yok).
      runtime = "langflow",
      real_tool = TRUE
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
      # Langflow aracı: yerel model kavramı yok (akış kendi modelini taşır).
      runtime = "langflow",
      langflow_flow_id = langflow_app_expert_flow_id,
      real_tool = TRUE
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
	  thinking = TRUE,
	  omit_temperature = TRUE,
	  stream_reasoning = TRUE,
	  allow_reasoning_fallback = TRUE,
	  request_overrides = list(
		chat_template_kwargs = list(
		  enable_thinking = TRUE
		)
	  )
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
	  thinking = TRUE,
	  omit_temperature = TRUE,
	  stream_reasoning = TRUE,
	  allow_reasoning_fallback = TRUE,
	  request_overrides = list(
		chat_template_kwargs = list(
		  enable_thinking = TRUE
		)
	  )
    ),
    "technical name 6" = list(
      thinking = FALSE,
      omit_temperature = FALSE,
      stream_reasoning = FALSE,
      allow_reasoning_fallback = FALSE
    ),
    "technical name 7" = list(
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
  )
)

# --- DERİN DÜŞÜNME MODEL YETENEKLERİ ---
# Derin Düşünme modelleri (Excel ve Kod araçları için) thinking-capable kabul
# edilir. Kayıt mekanizması saf yardımcıda tek sahiptedir
# (bkz. R/helpers_deep_thinking_model_capabilities.R): tabloda olmayan model
# güvenli varsayılanlarla açılır, var olan açık tanımların değerleri korunur ve
# eksik endpoint eşlemesi "primary" ile tamamlanır. İzole test/debug bağlamında
# bu dosya tek başına source edilirse helper yüklü olmayabilir; o bağlamlar
# helper'ı config_api.R'den ÖNCE source etmelidir.
if (exists("apply_deep_thinking_model_capabilities", mode = "function", inherits = TRUE)) {
  api_config <- apply_deep_thinking_model_capabilities(api_config)
}

# --- SES SENTEZİ (TTS) YAPILANDIRMASI ---
# OpenAI uyumlu ses uç noktası
tts_config <- list(
  base_url        = Sys.getenv("LOCAL_TTS_ENDPOINT", ""),
  api_key         = Sys.getenv("LOCAL_TTS_API_KEY", ""),
  model           = Sys.getenv("LOCAL_TTS_MODEL", ""),
  default_voice   = Sys.getenv("LOCAL_TTS_VOICE", ""),
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
# Kullanıcı API anahtarı şifreleme/saklama katmanı (API_KEYS_DIR, .api_user_file,
# .hash_key_hex, .enc_key, .dec_key, save/load/exists/verify) artık
# R/helpers_api_key_crypto.R içindedir ve manifest üzerinden bu dosyadan sonra
# yüklenir. Buraya geri taşımayın; sınır test sözleşmeleriyle korunur.

# Vision (Image Input) yetenek işaretleme (bkz. R/helpers_vision_model_capabilities.R).
if (exists("apply_vision_model_capabilities", mode = "function", inherits = TRUE)) {
  api_config <- apply_vision_model_capabilities(api_config, c(coding_deep_low_model, coding_deep_high_model))
}
