# ==============================================================================
# Dosya Yolu: R/helpers_api_model_config.R
# Açıklama:   API yapılandırmasından model yetenekleri, model bazlı istek
#             override'ları, yerel LLM uç noktası/kimlik bilgisi ve araç modu
#             model seçimlerini çözen saf yardımcı fonksiyonlar.
#             R/config_api.R tarafından tanımlanan api_config nesnesinden sonra
#             source() edilmelidir.
# ==============================================================================

# Model capability'lerini çözümle
get_local_model_capabilities <- function(model_id = NULL, config = api_config) {
	defaults <- list(
	  thinking = FALSE,
	  omit_temperature = FALSE,
	  stream_reasoning = FALSE,
	  allow_reasoning_fallback = FALSE,

	  # Model bazlı OpenAI-uyumlu ek istek alanları.
	  # Örn. bazı thinking modeller reasoning üretmek için
	  # chat_template_kwargs$enable_thinking = TRUE bekler.
	  request_overrides = list()
	)

  model_id <- as.character(model_id %||% "")[1]
  if (is.na(model_id)) {
    model_id <- ""
  }

  caps <- config$local_model_capabilities[[model_id]]

  if (!is.list(caps)) {
    caps <- list()
  }

  # Düşünme yetenekleri yalnızca config$local_model_capabilities içinde açıkça
  # bildirilen modeller için belirlenir. R/config_api.R artık her teknik modelin
  # thinking/omit_temperature/stream_reasoning/allow_reasoning_fallback değerlerini
  # net olarak tanımladığı için model adı üzerinden regex tabanlı tahmin yapılmaz.
  utils::modifyList(defaults, caps, keep.null = TRUE)
}

# ------------------------------------------------------------------------------
# MODEL BAZLI LLM İSTEK OVERRIDE YARDIMCISI
# ------------------------------------------------------------------------------
# Bazı OpenAI-uyumlu yerel uçlar, reasoning/thinking üretmek için model bazlı
# ek gövde alanları ister. Bu fonksiyon yalnızca config'te açıkça tanımlanmış
# request_overrides alanlarını body içine güvenli şekilde ekler.
merge_named_list_deep <- function(x, y) {
  if (!is.list(x)) x <- list()
  if (!is.list(y) || length(y) == 0) return(x)

  for (nm in names(y)) {
    if (!nzchar(nm)) next

    if (is.list(x[[nm]]) && is.list(y[[nm]])) {
      x[[nm]] <- merge_named_list_deep(x[[nm]], y[[nm]])
    } else {
      x[[nm]] <- y[[nm]]
    }
  }

  x
}

apply_model_request_overrides <- function(body, model_id = NULL, config = api_config) {
  caps <- get_local_model_capabilities(model_id, config)
  overrides <- caps$request_overrides %||% list()

  if (!is.list(overrides) || length(overrides) == 0) {
    return(body)
  }

  merge_named_list_deep(body, overrides)
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

#' Derin Düşünme aktifken araç ailesi + seviye için model çözümle
#'
#' Excel Analizi ve Kod Uzmanı araçlarında "Derin Düşünme" düğmesi aktifken
#' kullanılacak modeli döndürür. Eşleşme yoksa veya tanımlı değilse NULL.
#'
#' @param tool_family Araç ailesi ("mcp_excel" veya "coding")
#' @param deep_level "low" veya "high" (varsayılan dropdown seçimi)
#' @param config api_config nesnesi
#' @return Çözümlenmiş model kimliği (string) veya NULL
resolve_deep_thinking_model <- function(tool_family, deep_level = "low", config = api_config) {
  if (is.null(tool_family) || !nzchar(as.character(tool_family))) return(NULL)
  dt_cfg <- config$deep_thinking_models %||% list()
  family_cfg <- dt_cfg[[as.character(tool_family)]]
  if (is.null(family_cfg)) return(NULL)
  level_key <- if (identical(tolower(as.character(deep_level)), "high")) "high" else "low"
  model_id <- family_cfg[[level_key]]
  if (is.null(model_id) || !nzchar(as.character(model_id))) return(NULL)
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