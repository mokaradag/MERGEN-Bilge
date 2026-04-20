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
  # Her teknik model kimliğini bir uç nokta anahtarına eşle
  local_model_endpoint_map = c(
    "technical name 1" = "primary",
    "technical name 2" = "primary",
    "technical name 3" = "primary",
    "technical name 4" = "primary",
    "technical name 5" = "secondary",
    "technical name 6" = "secondary"
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
      thinking = FALSE,
      omit_temperature = FALSE,
      stream_reasoning = FALSE,
      allow_reasoning_fallback = FALSE
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

# --- UÇ NOKTA ÇÖZÜMLEME FONKSİYONLARI ---

# Model capability'lerini çözümle
get_local_model_capabilities <- function(model_id = NULL, config = api_config) {
  defaults <- list(
    thinking = FALSE,
    omit_temperature = FALSE,
    stream_reasoning = FALSE,
    allow_reasoning_fallback = FALSE
  )

  model_id <- as.character(model_id %||% "")[1]
  caps <- config$local_model_capabilities[[model_id]]

  if (!is.list(caps)) {
    caps <- list()
  }

  utils::modifyList(defaults, caps, keep.null = TRUE)
}

is_thinking_model <- function(model_id = NULL, config = api_config) {
  isTRUE(get_local_model_capabilities(model_id, config)$thinking)
}

should_omit_temperature <- function(model_id = NULL, config = api_config) {
  caps <- get_local_model_capabilities(model_id, config)
  isTRUE(caps$omit_temperature) || isTRUE(caps$thinking)
}

should_stream_reasoning <- function(model_id = NULL, config = api_config) {
  isTRUE(get_local_model_capabilities(model_id, config)$stream_reasoning)
}

should_allow_reasoning_fallback <- function(model_id = NULL, config = api_config) {
  isTRUE(get_local_model_capabilities(model_id, config)$allow_reasoning_fallback)
}

# Verilen teknik model kimliği için uygun yerel LLM uç noktasını çözümle
resolve_local_llm_endpoint <- function(model_id = NULL, config = api_config) {
  default_endpoint <- config$local_llm_endpoint %||% config$local_llm$endpoint %||% ""
  endpoints <- config$local_llm_endpoints %||% list()
  endpoint_map <- config$local_model_endpoint_map %||% character()

  pick_endpoint <- function(key) {
    if (is.null(key) || !nzchar(key)) {
      return(NULL)
    }
    from_list <- endpoints[[key]]
    if (!is.null(from_list) && nzchar(from_list)) {
      return(from_list)
    }
    if (grepl("^https?://", key, ignore.case = TRUE)) {
      return(key)
    }
    NULL
  }

  # İstenen modele bağlı uç noktayı tercih et
  if (!is.null(model_id) && nzchar(model_id)) {
    endpoint_key <- NULL
    if (!is.null(endpoint_map) &&
        length(endpoint_map) > 0 &&
        !is.null(names(endpoint_map)) &&
        model_id %in% names(endpoint_map)) {
      endpoint_key <- as.character(endpoint_map[model_id])[1]
      if (is.na(endpoint_key) || !nzchar(endpoint_key)) {
        endpoint_key <- NULL
      }
    }
    chosen <- pick_endpoint(endpoint_key)
    if (!is.null(chosen) && nzchar(chosen)) {
      return(chosen)
    }
  }

  # Sonra tanımlı varsayılan anahtarı dene
  first_model_id <- as.character(config$local_models[1] %||% "")[1]

  mapped_default_key <- NULL
  if (!is.null(endpoint_map) &&
      length(endpoint_map) > 0 &&
      !is.null(names(endpoint_map)) &&
      nzchar(first_model_id) &&
      first_model_id %in% names(endpoint_map)) {
    mapped_default_key <- as.character(endpoint_map[first_model_id])[1]
    if (is.na(mapped_default_key) || !nzchar(mapped_default_key)) {
      mapped_default_key <- NULL
    }
  }

  default_key <- config$local_llm_default_endpoint_key %||%
    mapped_default_key %||%
    names(endpoints)[1]
  chosen_default <- pick_endpoint(default_key)
  if (!is.null(chosen_default) && nzchar(chosen_default)) {
    return(chosen_default)
  }

  # Son çare: listedeki ilk boş olmayan uç noktayı kullan
  if (length(endpoints)) {
    for (ep in endpoints) {
      if (!is.null(ep) && nzchar(ep)) {
        return(ep)
      }
    }
  }

  default_endpoint
}

# Bir LLM çağrısı için denenebilecek uç nokta hedeflerinin (url + api_key)
# sıralı, tekilleştirilmiş listesini üret. Çağıranın verdiği (zaten model için
# çözümlenmiş) URL/anahtar başa konur; ardından yapılandırmadaki
# (api_config$local_llm_endpoints) diğer boş olmayan uç noktalar kendi
# yapılandırılmış anahtarlarıyla eklenir. Bu sayede bir uç nokta 5xx veya
# bağlantı hatası döndürdüğünde çağıranlar sıradaki uç noktaya sessizce geçiş
# yapabilir. Değerler tamamen yapılandırmadan türediği için hiçbir URL/model
# adı sabit kodlanmaz.
llm_call_targets <- function(current_endpoint = NULL,
                             current_api_key = NULL,
                             model_id = NULL,
                             config = api_config) {
  endpoints_cfg <- config$local_llm_endpoints %||% list()
  key_map <- config$local_llm_endpoint_keys %||% list()
  user_flags <- config$local_llm_endpoint_user_managed %||% logical()

  targets <- list()

  add_target <- function(url, api_key) {
    if (is.null(url)) return(invisible(NULL))
    url_val <- as.character(url)[1]
    if (is.na(url_val) || !nzchar(url_val)) return(invisible(NULL))
    existing_urls <- vapply(targets, function(t) t$url %||% "", character(1))
    if (url_val %in% existing_urls) return(invisible(NULL))
    key_val <- if (is.null(api_key)) "" else as.character(api_key)[1]
    if (is.na(key_val)) key_val <- ""
    targets[[length(targets) + 1L]] <<- list(url = url_val, api_key = key_val)
    invisible(NULL)
  }

  # Öncelik: çağıranın zaten çözdüğü URL ve anahtar
  add_target(current_endpoint, current_api_key)

  # Çağıran URL vermediyse modelden çöz
  if (!length(targets) && !is.null(model_id) && nzchar(as.character(model_id)[1])) {
    primary_creds <- tryCatch(resolve_local_llm_credentials(model_id, config),
                              error = function(e) NULL)
    if (!is.null(primary_creds)) {
      add_target(primary_creds$endpoint, current_api_key %||% primary_creds$default_api_key)
    }
  }

  # Yapılandırmadaki diğer uç noktaları kendi anahtarlarıyla sıraya ekle
  if (length(endpoints_cfg)) {
    for (nm in names(endpoints_cfg)) {
      url <- endpoints_cfg[[nm]]
      if (is.null(url) || !nzchar(as.character(url)[1])) next
      default_key <- key_map[[nm]] %||% ""
      allow_user <- isTRUE(user_flags[[nm]])
      # Kullanıcı yönetimli uç noktalarda çağıranın anahtarı öncelikli; aksi
      # halde yapılandırmanın (ör. .Renviron) tanımladığı varsayılan anahtar
      api_key <- if (allow_user) {
        current_api_key %||% default_key
      } else {
        default_key
      }
      add_target(url, api_key)
    }
  }

  targets
}

# Verilen model için hem uç noktayı hem varsayılan API anahtarını çözümle
resolve_local_llm_credentials <- function(model_id = NULL, config = api_config) {
  endpoints <- config$local_llm_endpoints %||% list()
  endpoint_map <- config$local_model_endpoint_map %||% character()
  key_map <- config$local_llm_endpoint_keys %||% list()
  user_key_flags <- config$local_llm_endpoint_user_managed %||% logical()

  default_key_id <- config$local_llm_default_endpoint_key %||% names(endpoints)[1] %||% ""
  endpoint_key <- NULL

  if (!is.null(model_id) && nzchar(as.character(model_id)[1])) {
    model_key <- as.character(model_id)[1]
    endpoint_key <- NULL

    if (!is.null(endpoint_map) &&
        length(endpoint_map) > 0 &&
        !is.null(names(endpoint_map)) &&
        !is.na(model_key) &&
        nzchar(model_key) &&
        model_key %in% names(endpoint_map)) {
      endpoint_key <- as.character(endpoint_map[model_key])[1]
      if (is.na(endpoint_key) || !nzchar(endpoint_key)) {
        endpoint_key <- NULL
      }
    }
  }

  if (is.null(endpoint_key) || !nzchar(endpoint_key)) {
    endpoint_key <- default_key_id
  }

  endpoint_url <- resolve_local_llm_endpoint(model_id, config)
  default_api_key <- key_map[[endpoint_key]] %||% ""

  if (is.null(default_api_key) || is.na(default_api_key)) {
    default_api_key <- ""
  }

  allow_user_key <- TRUE
  if (!is.null(endpoint_key) && nzchar(endpoint_key) && length(user_key_flags)) {
    allow_user_key <- isTRUE(user_key_flags[[endpoint_key]])
  }

  list(
    endpoint        = endpoint_url %||% "",
    endpoint_key    = endpoint_key %||% "",
    default_api_key = as.character(default_api_key)[1] %||% "",
    allow_user_key  = allow_user_key
  )
}

# API anahtarı doğrulama hedefini belirle (kullanıcı yönetimli uç noktayı seç)
determine_api_key_validation_target <- function(requested_model_id = NULL, config = api_config) {
  models_vector <- config$local_models %||% character()
  requested_model_id <- as.character(requested_model_id %||% models_vector[1] %||% "")

  target_creds    <- resolve_local_llm_credentials(requested_model_id, config)
  target_model    <- requested_model_id
  target_endpoint <- target_creds$endpoint %||% resolve_local_llm_endpoint(requested_model_id, config)
  target_key      <- target_creds$endpoint_key %||% ""
  allow_user_key  <- isTRUE(target_creds$allow_user_key)
  fallback_used   <- FALSE

  if (!allow_user_key) {
    endpoint_map <- config$local_model_endpoint_map %||% character()
    user_flags   <- config$local_llm_endpoint_user_managed %||% logical()
    managed_keys <- names(user_flags)[vapply(user_flags, isTRUE, logical(1))]

    fallback_model <- NULL
    if (length(managed_keys)) {
      for (key in managed_keys) {
        candidate_vec <- names(endpoint_map)[which(endpoint_map == key)]
        candidate_vec <- candidate_vec[!is.na(candidate_vec) & nzchar(candidate_vec)]
        if (length(candidate_vec)) {
          fallback_model <- candidate_vec[1]
          break
        }
      }
    }

    if (is.null(fallback_model) || !nzchar(fallback_model)) {
      fallback_model <- models_vector[1] %||% ""
    }

    fallback_creds <- resolve_local_llm_credentials(fallback_model, config)
    if (isTRUE(fallback_creds$allow_user_key) && nzchar(fallback_creds$endpoint %||% "")) {
      target_model    <- fallback_model
      target_endpoint <- fallback_creds$endpoint
      target_key      <- fallback_creds$endpoint_key %||% ""
      allow_user_key  <- TRUE
      fallback_used   <- !identical(target_model, requested_model_id)
    } else {
      allow_user_key <- FALSE
    }
  }

  if (!nzchar(target_endpoint)) {
    target_endpoint <- resolve_local_llm_endpoint(target_model, config)
  }

  list(
    model_id           = target_model,
    endpoint           = target_endpoint %||% "",
    endpoint_key       = target_key %||% "",
    allow_user_key     = allow_user_key,
    fallback_used      = fallback_used,
    requested_model_id = requested_model_id
  )
}

# --- ARAÇ MODU ÇÖZÜMLEME YARDIMCILARI ---
get_tool_mode_config <- function(value, by = c("family", "setting_flag", "quick_action_id"), config = api_config) {
  by <- match.arg(by)
  all_cfg <- config$tool_mode_config %||% list()

  for (cfg in all_cfg) {
    candidate <- cfg[[by]] %||% NULL
    if (!is.null(candidate) && identical(as.character(candidate), as.character(value))) {
      return(cfg)
    }
  }

  NULL
}

resolve_tool_model_for_family <- function(tool_family, fallback_model = NULL, config = api_config) {
  cfg <- get_tool_mode_config(tool_family, by = "family", config = config)
  model_id <- cfg$model_id %||% fallback_model %||% as.character(config$local_models[1]) %||% ""
  as.character(model_id)[1]
}

resolve_tool_model_for_flag <- function(setting_flag, fallback_model = NULL, config = api_config) {
  cfg <- get_tool_mode_config(setting_flag, by = "setting_flag", config = config)
  model_id <- cfg$model_id %||% fallback_model %||% as.character(config$local_models[1]) %||% ""
  as.character(model_id)[1]
}

build_main_actions_data_from_config <- function(config = api_config) {
  all_cfg <- config$tool_mode_config %||% list()

  actions <- lapply(all_cfg, function(cfg) {
    if (is.null(cfg$quick_action_id) || !nzchar(cfg$quick_action_id %||% "")) {
      return(NULL)
    }

    list(
      id = cfg$quick_action_id,
      title = cfg$title %||% cfg$quick_action_id,
      message = cfg$message %||% "",
      description = cfg$description %||% "",
      icon_name = cfg$icon_name %||% "bolt",
      themeColor = cfg$themeColor %||% "#6366f1",
      model_value = cfg$model_id %||% as.character(config$local_models[1]) %||% ""
    )
  })

  Filter(Negate(is.null), actions)
}

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
  jsonlite::write_json(rec, f, auto_unbox = TRUE, pretty = TRUE)
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